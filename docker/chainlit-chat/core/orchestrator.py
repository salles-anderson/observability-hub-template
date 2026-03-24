"""
Orchestrator — AG-2 pipeline with AG-1 fallback via feature flag.

Flow (AG-2):
  1. Input guardrails
  2. RBAC check
  3. Fast path: regex shortcuts (no LLM, ~2s)
  4. Router: Gemini 2.5 Pro classifies → 1-3 agents
  5. Agents: DeepSeek V3 ReAct loop (parallel)
  6. Correlator: Claude Sonnet 4.6 synthesizes (if 2+ agents)
  7. Output guardrails

Feature flag: AGENT_VERSION=ag1|ag2 (default: ag1)
"""

from __future__ import annotations

import asyncio
import logging
import os
import time
from typing import AsyncGenerator

from core.guardrails import (
    validate_input,
    scan_output,
    check_role_access,
    get_denied_message,
    InputGuardError,
    DEFAULT_ROLE,
)
from core.models import AgentRequest, AgentResult

logger = logging.getLogger("orchestrator")

# ---------------------------------------------------------------------------
# Feature flag
# ---------------------------------------------------------------------------
AGENT_VERSION = os.environ.get("AGENT_VERSION", "ag1")


# ---------------------------------------------------------------------------
# AG-2 pipeline
# ---------------------------------------------------------------------------
async def _run_ag2(
    question: str,
    history: list[dict] | None = None,
    role: str = DEFAULT_ROLE,
) -> AsyncGenerator[str, None]:
    """AG-2: Cache → Router → Specialized Agents (parallel) → Correlator → Cache Store."""
    from core.router import classify
    from agents import AGENT_MAP

    # Step 0: Semantic cache lookup (2s hard timeout — never blocks pipeline)
    if not history or len(history) <= 1:
        try:
            import semantic_cache
            cached = await asyncio.wait_for(
                semantic_cache.lookup(question), timeout=2.0
            )
            if cached:
                yield cached
                yield "\n\n---\n*Resposta via cache semantico*"
                return
        except asyncio.TimeoutError:
            logger.warning("Semantic cache lookup timeout (2s) — skipping")
        except Exception as e:
            logger.warning(f"Semantic cache error: {e}")

    # Step 1: Router classifies the question
    route_decision = await classify(question)

    if route_decision.is_empty:
        # Fallback to AG-1 if router can't classify
        logger.info("AG-2: Router returned empty, falling back to AG-1")
        async for text in _run_ag1(question, history, role):
            yield text
        return

    # Step 2: Dispatch agents in parallel
    has_correlator = "correlator" in route_decision.agent_names
    agent_routes = [
        (name, sub_q)
        for name, sub_q in route_decision.routes
        if name != "correlator"
    ]

    if not agent_routes:
        async for text in _run_ag1(question, history, role):
            yield text
        return

    # Build agent tasks
    agent_tasks = []
    for agent_name, sub_question in agent_routes:
        agent_cls = AGENT_MAP.get(agent_name)
        if not agent_cls:
            logger.warning(f"AG-2: Unknown agent '{agent_name}', skipping")
            continue

        agent = agent_cls()
        request = AgentRequest(
            question=sub_question,
            history=history,
            role=role,
        )
        agent_tasks.append(agent.run(request))

    if not agent_tasks:
        async for text in _run_ag1(question, history, role):
            yield text
        return

    # Execute agents in parallel
    yield f"*Consultando {len(agent_tasks)} agente(s): {', '.join(n for n, _ in agent_routes)}...*\n\n"

    results: list[AgentResult] = await asyncio.gather(*agent_tasks)

    # Step 3: If 2+ results or correlator requested, synthesize
    correlator_result = None
    if (len(results) >= 2 or has_correlator) and "correlator" in AGENT_MAP:
        correlator = AGENT_MAP["correlator"]()
        correlator_input = _build_correlator_input(question, results)
        correlator_request = AgentRequest(
            question=correlator_input,
            role=role,
        )
        correlator_result = await correlator.run(correlator_request)
        yield correlator_result.data
        total_tools = sum(r.tool_calls for r in results) + correlator_result.tool_calls
        total_ms = max(r.duration_ms for r in results) + correlator_result.duration_ms
    else:
        # Single agent — return directly
        result = results[0]
        if result.status == "error":
            yield f"Erro no agente {result.agent_name}: {result.data}"
        elif result.status == "timeout":
            yield result.data
        else:
            yield result.data
        total_tools = result.tool_calls
        total_ms = result.duration_ms

    agents_used = ", ".join(r.agent_name for r in results)
    yield f"\n\n---\n*AG-2 — {agents_used} — {total_tools} tool call(s) — {total_ms}ms*"

    # Step 5: Store in semantic cache (fire-and-forget, never blocks response)
    try:
        import semantic_cache
        cache_response = (
            correlator_result.data if correlator_result else
            results[0].data if results else None
        )
        if cache_response:
            # Fire-and-forget — don't await, don't block
            asyncio.create_task(semantic_cache.store(question, cache_response, agents_used))
    except Exception as e:
        logger.warning(f"Semantic cache store error: {e}")


def _build_correlator_input(question: str, results: list[AgentResult]) -> str:
    """Build correlator input from multiple agent results."""
    parts = [f"## Pergunta original\n{question}\n"]

    for r in results:
        status = "OK" if r.status == "success" else r.status.upper()
        parts.append(
            f"## Resultado: {r.agent_name} ({status}, {r.duration_ms}ms)\n{r.data}\n"
        )

    parts.append(
        "## Instrucao\n"
        "Sintetize os dados acima em uma resposta unica, coerente e acionavel. "
        "Correlacione informacoes entre dominios. Destaque insights que so "
        "aparecem ao cruzar os dados."
    )

    return "\n".join(parts)


# ---------------------------------------------------------------------------
# AG-1 pipeline (current — imported from agent.py)
# ---------------------------------------------------------------------------
async def _run_ag1(
    question: str,
    history: list[dict] | None = None,
    role: str = DEFAULT_ROLE,
) -> AsyncGenerator[str, None]:
    """AG-1: Single orchestrator with all tools (current behavior)."""
    # Lazy import to avoid circular dependency during migration
    from agent import _try_all_shortcuts, _build_messages, _orchestrator_loop
    from prompts.orchestrator import SYSTEM_PROMPT_ORCHESTRATOR
    from prompts.base import SYSTEM_PROMPT_BASE

    # Fast path: shortcuts
    shortcut_response = await _try_all_shortcuts(question)
    if shortcut_response:
        yield scan_output(shortcut_response)
        return

    # Orchestrator ReAct loop
    logger.info(f"AG-1 ORCHESTRATOR: {question[:100]}")
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


# ---------------------------------------------------------------------------
# Main entry point — backwards compatible with agent.py
# ---------------------------------------------------------------------------
async def run_chat_query(
    question: str,
    history: list[dict] | None = None,
    role: str = DEFAULT_ROLE,
) -> AsyncGenerator[str, None]:
    """Execute query with guardrails + AG-1 or AG-2 pipeline.

    Drop-in replacement for agent.run_chat_query().
    """
    start_ts = time.monotonic()

    # Input guardrails
    try:
        question = validate_input(question)
    except InputGuardError as e:
        yield e.user_message
        return

    # RBAC
    if not check_role_access(role, "general"):
        yield get_denied_message(role, "general")
        return

    # Route to AG-1 or AG-2
    if AGENT_VERSION == "ag2":
        async for text in _run_ag2(question, history, role):
            yield text
    else:
        async for text in _run_ag1(question, history, role):
            yield text

    elapsed = (time.monotonic() - start_ts) * 1000
    yield f"\n\n---\n*Orchestrator {AGENT_VERSION} — {elapsed:.0f}ms*"


# ---------------------------------------------------------------------------
# AG-2 non-streaming entry point (used by alert_investigator)
# ---------------------------------------------------------------------------
async def run_ag2_collect(
    question: str,
    role: str = DEFAULT_ROLE,
) -> str:
    """Execute AG-2 pipeline and collect full response as string.

    Used by alert_investigator for background investigations (no streaming).
    """
    parts: list[str] = []
    async for text in _run_ag2(question, role=role):
        parts.append(text)
    return "".join(parts)
