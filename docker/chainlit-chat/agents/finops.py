"""
FinOps Agent — Cost Explorer, forecast, rightsizing, anomalies.

8 tools + RAG. DeepSeek V3 via LiteLLM.
"""

from core.base_agent import BaseAgent
from tools import get_tools_for_agent, execute_tool
from prompts.base import SYSTEM_PROMPT_BASE
from prompts.finops import SYSTEM_PROMPT_FINOPS


class FinOpsAgent(BaseAgent):
    name = "finops"
    model = "deepseek/deepseek-chat"
    max_turns = 6
    timeout = 60

    @property
    def tools(self) -> list[dict]:
        return get_tools_for_agent(self.name)

    @property
    def system_prompt(self) -> str:
        return SYSTEM_PROMPT_BASE + SYSTEM_PROMPT_FINOPS

    async def execute_tool(self, name: str, input_data: dict) -> str:
        return await execute_tool(name, input_data)
