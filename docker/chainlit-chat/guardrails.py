"""
Guardrails — Re-export stub for backwards compatibility.

Canonical location: core/guardrails.py
"""

from core.guardrails import (  # noqa: F401
    InputGuardError,
    validate_input,
    scan_output,
    check_role_access,
    get_denied_message,
    DEFAULT_ROLE,
    ROLE_TOOLS,
    MAX_INPUT_LENGTH,
    MAX_HISTORY_MESSAGES,
)
