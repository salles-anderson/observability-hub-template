"""
Agents package — 7 specialized agents for AG-2.

Each agent inherits BaseAgent and defines:
  - name, model, max_turns
  - tools (curated subset)
  - system_prompt (base + domain-specific)
  - execute_tool() delegation
"""

from agents.observability import ObservabilityAgent
from agents.infrastructure import InfrastructureAgent
from agents.finops import FinOpsAgent
from agents.security import SecurityAgent
from agents.cicd import CICDAgent
from agents.code import CodeAgent
from agents.correlator import CorrelatorAgent

AGENT_MAP: dict[str, type] = {
    "observability": ObservabilityAgent,
    "infrastructure": InfrastructureAgent,
    "finops": FinOpsAgent,
    "security": SecurityAgent,
    "cicd": CICDAgent,
    "code": CodeAgent,
    "correlator": CorrelatorAgent,
}
