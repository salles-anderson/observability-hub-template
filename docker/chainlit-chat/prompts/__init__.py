"""Modular system prompts for Teck AI Assistant.

Architecture: base prompt (shared context) + domain addon (expertise).
Each query type gets: SYSTEM_PROMPT_BASE + domain-specific addon.

Hub central: 11 contas AWS, 13 VPCs, multiplas APIs.
O base.py concentra o contexto multi-account compartilhado.
Os addons adicionam expertise de dominio especifica.
"""

from prompts.base import SYSTEM_PROMPT_BASE
from prompts.observability import SYSTEM_PROMPT_OBSERVABILITY
from prompts.aws import SYSTEM_PROMPT_AWS
from prompts.finops import SYSTEM_PROMPT_FINOPS
from prompts.security import SYSTEM_PROMPT_SECURITY
from prompts.terraform import SYSTEM_PROMPT_TERRAFORM
from prompts.github import SYSTEM_PROMPT_GITHUB
from prompts.rag import SYSTEM_PROMPT_RAG_PREAMBLE
from prompts.orchestrator import SYSTEM_PROMPT_ORCHESTRATOR


def get_system_prompt(query_type: str) -> str:
    """Build system prompt: base + domain addon.

    Args:
        query_type: "observability", "finops", "aws", "security",
                    "terraform", or "general"

    Returns:
        Complete system prompt string.
    """
    if query_type == "observability":
        return SYSTEM_PROMPT_BASE + SYSTEM_PROMPT_OBSERVABILITY
    if query_type == "finops":
        return SYSTEM_PROMPT_BASE + SYSTEM_PROMPT_FINOPS
    if query_type == "security":
        return SYSTEM_PROMPT_BASE + SYSTEM_PROMPT_SECURITY
    if query_type == "terraform":
        return SYSTEM_PROMPT_BASE + SYSTEM_PROMPT_TERRAFORM
    if query_type == "aws":
        return SYSTEM_PROMPT_BASE + SYSTEM_PROMPT_AWS
    if query_type == "github":
        return SYSTEM_PROMPT_BASE + SYSTEM_PROMPT_GITHUB
    return SYSTEM_PROMPT_BASE
