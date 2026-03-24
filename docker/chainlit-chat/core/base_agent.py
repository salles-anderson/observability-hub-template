"""
BaseAgent — ReAct loop with dual-API support (Anthropic + OpenAI/LiteLLM).

Extracted from agent.py v11 orchestrator. Each specialized agent inherits
this class and defines its own tools, prompt, and model.

Supports:
  - Anthropic SDK (Claude Sonnet/Haiku) — tool_use native
  - OpenAI SDK (DeepSeek V3 via LiteLLM) — function_call compatible
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
from abc import ABC, abstractmethod

import anthropic
import httpx
import openai

from core.models import AgentRequest, AgentResult, Timer

logger = logging.getLogger("base-agent")

# ---------------------------------------------------------------------------
# Shared clients (lazy-init)
# ---------------------------------------------------------------------------
_anthropic_client: anthropic.AsyncAnthropic | None = None
_openai_client: openai.AsyncOpenAI | None = None

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
# Kong AI Gateway: if KONG_AI_URL is set, route OpenAI SDK traffic through Kong (PII removal)
_KONG_AI_URL = os.environ.get("KONG_AI_URL", "")
LITELLM_BASE_URL = os.environ.get(
    "LITELLM_BASE_URL",
    _KONG_AI_URL if _KONG_AI_URL else "http://litellm.observability.local:4000",
)
LITELLM_API_KEY = os.environ.get("LITELLM_API_KEY", "sk-litellm-master-key")


def _get_anthropic_client() -> anthropic.AsyncAnthropic:
    global _anthropic_client
    if _anthropic_client is None:
        _anthropic_client = anthropic.AsyncAnthropic(
            api_key=ANTHROPIC_API_KEY,
            timeout=httpx.Timeout(90, connect=10.0),
        )
    return _anthropic_client


def _get_openai_client() -> openai.AsyncOpenAI:
    global _openai_client
    if _openai_client is None:
        _openai_client = openai.AsyncOpenAI(
            base_url=LITELLM_BASE_URL,
            api_key=LITELLM_API_KEY,
            timeout=httpx.Timeout(90, connect=10.0),
        )
    return _openai_client


# ---------------------------------------------------------------------------
# Tool executor type
# ---------------------------------------------------------------------------
ToolExecutor = type[None]  # placeholder — will be a callable


class BaseAgent(ABC):
    """Abstract base for all specialized agents.

    Subclasses must define:
      - name: str
      - model: str (e.g. "claude-sonnet-4-6" or "deepseek/deepseek-chat")
      - tools: list[dict] (Anthropic tool_use schema)
      - system_prompt: str
      - max_turns: int (default 5)
      - execute_tool(name, input_data) -> str
    """

    name: str = "base"
    model: str = "claude-sonnet-4-6"
    max_turns: int = 8
    timeout: int = 75

    @property
    @abstractmethod
    def tools(self) -> list[dict]:
        """Tool schemas (Anthropic format)."""
        ...

    @property
    @abstractmethod
    def system_prompt(self) -> str:
        """Full system prompt for this agent."""
        ...

    @abstractmethod
    async def execute_tool(self, name: str, input_data: dict) -> str:
        """Execute a tool by name. Returns formatted string result."""
        ...

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------
    async def run(self, request: AgentRequest) -> AgentResult:
        """Execute agent with ReAct loop. Returns AgentResult."""
        with Timer() as timer:
            try:
                if self._is_anthropic_model():
                    result = await self._run_anthropic(request)
                else:
                    result = await self._run_openai(request)
                return AgentResult(
                    agent_name=self.name,
                    status="success",
                    data=result["text"],
                    confidence=1.0,
                    sources=result.get("sources", []),
                    duration_ms=timer.elapsed_ms,
                    tool_calls=result.get("tool_calls", 0),
                )
            except asyncio.TimeoutError:
                return AgentResult.timeout(self.name, timer.elapsed_ms)
            except Exception as e:
                logger.error(f"Agent {self.name} error: {e}")
                return AgentResult.error(self.name, str(e), timer.elapsed_ms)

    # ------------------------------------------------------------------
    # Anthropic SDK path (Claude)
    # ------------------------------------------------------------------
    async def _run_anthropic(self, request: AgentRequest) -> dict:
        client = _get_anthropic_client()
        messages = self._build_messages(request)
        tool_call_count = 0

        for turn in range(self.max_turns):
            response = await asyncio.wait_for(
                client.messages.create(
                    model=self.model,
                    max_tokens=4096,
                    system=self.system_prompt,
                    tools=self.tools,
                    messages=messages,
                ),
                timeout=self.timeout,
            )

            text_parts = []
            tool_calls = []

            for block in response.content:
                if block.type == "text":
                    text_parts.append(block.text)
                elif block.type == "tool_use":
                    tool_calls.append(block)

            if response.stop_reason == "end_turn" or not tool_calls:
                return {
                    "text": "\n".join(text_parts),
                    "tool_calls": tool_call_count,
                }

            tool_call_count += len(tool_calls)
            messages.append({"role": "assistant", "content": response.content})

            for tc in tool_calls:
                logger.info(
                    f"[{self.name}] TOOL: {tc.name}"
                    f"({json.dumps(tc.input, ensure_ascii=False)[:120]})"
                )

            results = await asyncio.gather(
                *(self.execute_tool(tc.name, tc.input) for tc in tool_calls),
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

        return {"text": "Limite de iteracoes atingido.", "tool_calls": tool_call_count}

    # ------------------------------------------------------------------
    # OpenAI SDK path (DeepSeek via LiteLLM)
    # ------------------------------------------------------------------
    async def _run_openai(self, request: AgentRequest) -> dict:
        client = _get_openai_client()
        messages = [
            {"role": "system", "content": self.system_prompt},
            *self._build_messages(request),
        ]
        openai_tools = self._anthropic_tools_to_openai()
        tool_call_count = 0

        for turn in range(self.max_turns):
            kwargs = {
                "model": self.model,
                "messages": messages,
                "max_tokens": 4096,
            }
            if openai_tools:
                kwargs["tools"] = openai_tools

            response = await asyncio.wait_for(
                client.chat.completions.create(**kwargs),
                timeout=self.timeout,
            )

            if not response.choices:
                logger.warning(f"{self.name}: empty choices from LLM")
                return {"text": "Sem resposta do modelo. Tente novamente.", "tool_calls": tool_call_count}

            choice = response.choices[0]
            message = choice.message

            if choice.finish_reason != "tool_calls" or not message.tool_calls:
                return {
                    "text": message.content or "",
                    "tool_calls": tool_call_count,
                }

            tool_call_count += len(message.tool_calls)
            messages.append(message)

            for tc in message.tool_calls:
                fn = tc.function
                logger.info(f"[{self.name}] TOOL: {fn.name}({fn.arguments[:120]})")

                try:
                    args = json.loads(fn.arguments) if fn.arguments else {}
                    result = await self.execute_tool(fn.name, args)
                except Exception as e:
                    result = str(e)

                messages.append({
                    "role": "tool",
                    "tool_call_id": tc.id,
                    "content": result if isinstance(result, str) else str(result),
                })

        return {"text": "Limite de iteracoes atingido.", "tool_calls": tool_call_count}

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    def _is_anthropic_model(self) -> bool:
        return self.model.startswith("claude-")

    def _build_messages(self, request: AgentRequest) -> list[dict]:
        """Build messages array from history + question."""
        messages = []
        if request.history:
            for msg in request.history[-10:]:
                role = msg["role"]
                content = msg["content"]
                if messages and messages[-1]["role"] == role:
                    messages[-1]["content"] += f"\n\n{content}"
                else:
                    messages.append({"role": role, "content": content})

        if messages and messages[-1]["role"] == "user":
            messages[-1]["content"] += f"\n\n{request.question}"
        else:
            messages.append({"role": "user", "content": request.question})

        return messages

    def _anthropic_tools_to_openai(self) -> list[dict]:
        """Convert Anthropic tool_use schemas to OpenAI function calling format."""
        openai_tools = []
        for tool in self.tools:
            openai_tools.append({
                "type": "function",
                "function": {
                    "name": tool["name"],
                    "description": tool.get("description", ""),
                    "parameters": tool.get("input_schema", {"type": "object", "properties": {}}),
                },
            })
        return openai_tools
