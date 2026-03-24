"""
Observability Agent — Prometheus, Loki, Tempo, Grafana dashboards.

4 tools + RAG. Gemini 3.1 Pro via LiteLLM (better tool calling than DeepSeek).
"""

from core.base_agent import BaseAgent
from tools import get_tools_for_agent, execute_tool
from prompts.base import SYSTEM_PROMPT_BASE
from prompts.observability import SYSTEM_PROMPT_OBSERVABILITY


class ObservabilityAgent(BaseAgent):
    name = "observability"
    model = "gemini/gemini-3.1-pro-preview"
    max_turns = 8
    timeout = 75

    @property
    def tools(self) -> list[dict]:
        return get_tools_for_agent(self.name)

    @property
    def system_prompt(self) -> str:
        return SYSTEM_PROMPT_BASE + SYSTEM_PROMPT_OBSERVABILITY

    async def execute_tool(self, name: str, input_data: dict) -> str:
        return await execute_tool(name, input_data)
