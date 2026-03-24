"""
Teck AI Assistant v12 — AG-1/AG-2 Dual Pipeline.

AG-1: Single Claude Orchestrator (42 tools, ReAct loop) — current behavior
AG-2: 7 Specialized Agents (Router → Agents → Correlator) — new

Feature flag: AGENT_VERSION=ag1|ag2 (default: ag1, zero breaking changes)

v12.0: AG-2 — Multi-Agent pipeline with 7 specialized agents
v11.0: AG-1 — Agentic AI orchestrator (replaces v10 classifier)
v10.0: Multi-Agent with classifier + 4-tier routing

This file is a facade. The actual implementation lives in:
  - core/orchestrator.py — pipeline + feature flag
  - core/base_agent.py — ReAct loop (Anthropic + OpenAI/LiteLLM)
  - core/router.py — LLM classifier (Gemini 2.5 Pro)
  - agents/ — 7 specialized agents
  - tools/ — tool schemas + executors
  - shortcuts/ — regex fast-path (no LLM)
"""

import asyncio
import json
import logging
import os
import time
from typing import AsyncGenerator

import anthropic
import httpx

from tools_registry import ALL_TOOLS, execute_tool
from prompts.orchestrator import SYSTEM_PROMPT_ORCHESTRATOR
from prompts.base import SYSTEM_PROMPT_BASE
from shortcuts import try_all_shortcuts as _shortcuts_try_all
from guardrails import (
    validate_input,
    scan_output,
    check_role_access,
    get_denied_message,
    InputGuardError,
    DEFAULT_ROLE,
)

logger = logging.getLogger("chainlit-agent")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
MODEL_COMPLEX = os.environ.get("AGENT_MODEL_COMPLEX", "claude-sonnet-4-6")
AGENT_MAX_TURNS = int(os.environ.get("AGENT_MAX_TURNS_COMPLEX", "15"))
AGENT_TIMEOUT = int(os.environ.get("AGENT_TIMEOUT", "90"))
AGENT_VERSION = os.environ.get("AGENT_VERSION", "ag1")

_anthropic_client = None


def _get_anthropic_client() -> anthropic.AsyncAnthropic:
    """Lazy-init Anthropic async client."""
    global _anthropic_client
    if _anthropic_client is None:
        _anthropic_client = anthropic.AsyncAnthropic(
            api_key=ANTHROPIC_API_KEY,
            timeout=httpx.Timeout(AGENT_TIMEOUT, connect=10.0),
        )
    return _anthropic_client


# ---------------------------------------------------------------------------
# Fast path: Regex shortcuts (Tier 1 — no LLM, ~2-3s)
# Uses shortcuts/__init__.py which has complexity scoring to bypass
# shortcuts for long/complex queries (pasted logs, error messages, etc.)
# ---------------------------------------------------------------------------
async def _try_all_shortcuts(question: str) -> str | None:
    """Try ALL shortcut domains in parallel. Returns first match or None.

    Delegates to shortcuts/ package which checks query complexity first.
    Complex queries (long text, error logs, investigative) skip shortcuts
    entirely and return None so AG-2 handles them.
    """
    return await _shortcuts_try_all(question)


# ---------------------------------------------------------------------------
# Conversation history builder
# ---------------------------------------------------------------------------
def _build_messages(
    question: str, history: list[dict] | None,
) -> list[dict]:
    """Build Anthropic messages array from conversation history."""
    messages = []

    if history:
        for msg in history[-10:]:
            role = msg["role"]
            content = msg["content"]
            if messages and messages[-1]["role"] == role:
                messages[-1]["content"] += f"\n\n{content}"
            else:
                messages.append({"role": role, "content": content})

    if messages and messages[-1]["role"] == "user":
        messages[-1]["content"] += f"\n\n{question}"
    else:
        messages.append({"role": "user", "content": question})

    return messages


# ---------------------------------------------------------------------------
# Orchestrator ReAct Loop (AG-1)
# ---------------------------------------------------------------------------
async def _orchestrator_loop(
    messages: list[dict],
    system_prompt: str,
) -> AsyncGenerator[str, None]:
    """Claude Orchestrator with ReAct tool_use loop (AG-1 path)."""
    client = _get_anthropic_client()
    tool_call_count = 0

    for turn in range(AGENT_MAX_TURNS):
        try:
            response = await asyncio.wait_for(
                client.messages.create(
                    model=MODEL_COMPLEX,
                    max_tokens=4096,
                    system=system_prompt,
                    tools=ALL_TOOLS,
                    messages=messages,
                ),
                timeout=AGENT_TIMEOUT,
            )
        except asyncio.TimeoutError:
            logger.warning(f"Orchestrator timeout (turn {turn + 1}/{AGENT_MAX_TURNS})")
            yield "Desculpe, a consulta demorou mais que o esperado. Tente simplificar a pergunta."
            return
        except anthropic.APIError as e:
            logger.error(f"Anthropic API error: {e}")
            yield f"Erro ao consultar o assistente: {e}"
            return

        text_parts = []
        tool_calls = []

        for block in response.content:
            if block.type == "text":
                text_parts.append(block.text)
            elif block.type == "tool_use":
                tool_calls.append(block)

        if response.stop_reason == "end_turn" or not tool_calls:
            if text_parts:
                yield "\n".join(text_parts)
            return

        tool_call_count += len(tool_calls)
        messages.append({"role": "assistant", "content": response.content})

        for tc in tool_calls:
            logger.info(
                f"TOOL_CALL: {tc.name}("
                f"{json.dumps(tc.input, ensure_ascii=False)[:120]})"
            )

        results = await asyncio.gather(
            *(execute_tool(tc.name, tc.input) for tc in tool_calls),
            return_exceptions=True,
        )

        tool_results = []
        for tc, result in zip(tool_calls, results):
            content = str(result) if isinstance(result, Exception) else result
            tool_results.append({
                "type": "tool_result",
                "tool_use_id": tc.id,
                "content": content,
            })

        messages.append({"role": "user", "content": tool_results})

        if text_parts:
            yield "\n".join(text_parts) + "\n\n"

    yield "Limite de iteracoes atingido. Os dados coletados foram apresentados acima."


# ---------------------------------------------------------------------------
# Main entry point — routes to AG-1 or AG-2
# ---------------------------------------------------------------------------
async def run_chat_query(
    question: str,
    history: list[dict] | None = None,
    role: str = DEFAULT_ROLE,
) -> AsyncGenerator[str, None]:
    """Execute query with guardrails + AG pipeline.

    AGENT_VERSION=ag1: Single orchestrator, 42 tools (legacy)
    AGENT_VERSION=ag2: Multi-agent (router → 7 agents → correlator)
    AGENT_VERSION=ag5: Claude + MCP (single model, all tools via MCP servers)
    """
    if AGENT_VERSION == "ag5":
        from core.orchestrator_ag5 import run_ag5
        async for text in run_ag5(question, history, role):
            yield text
        return

    if AGENT_VERSION == "ag2":
        from core.orchestrator import run_chat_query as ag2_run
        async for text in ag2_run(question, history, role):
            yield text
        return

    # --- AG-1 path (default, unchanged) ---
    start_ts = time.monotonic()

    try:
        question = validate_input(question)
    except InputGuardError as e:
        yield e.user_message
        return

    if not check_role_access(role, "general"):
        yield get_denied_message(role, "general")
        return

    shortcut_response = await _try_all_shortcuts(question)
    if shortcut_response:
        yield scan_output(shortcut_response)
        return

    logger.info(f"ORCHESTRATOR: {question[:100]}")

    system_prompt = SYSTEM_PROMPT_BASE + SYSTEM_PROMPT_ORCHESTRATOR
    messages = _build_messages(question, history)

    collected = []
    async for text in _orchestrator_loop(messages, system_prompt):
        collected.append(text)
        yield text

    full_response = "".join(collected)
    scanned = scan_output(full_response)
    if scanned != full_response:
        yield "\n\n> **Guardrail**: Credenciais detectadas e removidas da resposta."

    elapsed = (time.monotonic() - start_ts) * 1000
    yield f"\n\n---\n*Orchestrator v11 — {elapsed:.0f}ms*"
