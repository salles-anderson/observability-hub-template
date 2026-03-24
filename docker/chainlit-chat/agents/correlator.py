"""
Correlator Agent — synthesizes outputs from multiple specialized agents.

0 tools (analyzes agent outputs only). Claude Sonnet 4.6 (best reasoning).
"""

from core.base_agent import BaseAgent
from prompts.base import SYSTEM_PROMPT_BASE
from prompts.correlator import SYSTEM_PROMPT_CORRELATOR


class CorrelatorAgent(BaseAgent):
    name = "correlator"
    model = "claude-sonnet-4-6"
    max_turns = 1  # Single-turn — no tools, just synthesis
    timeout = 30

    @property
    def tools(self) -> list[dict]:
        return []  # Correlator has no tools

    @property
    def system_prompt(self) -> str:
        return SYSTEM_PROMPT_BASE + SYSTEM_PROMPT_CORRELATOR

    async def execute_tool(self, name: str, input_data: dict) -> str:
        return f"Correlator nao possui tools. Tool '{name}' ignorada."
