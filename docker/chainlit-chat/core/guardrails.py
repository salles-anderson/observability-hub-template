"""
Guardrails — Input validation, output scanning, and RBAC.

Moved from guardrails.py to core/ for AG-2 package organization.

3 layers:
  1. Input: max length, prompt injection detection, destructive pattern blocking
  2. Output: credential/secret scanning before sending to user
  3. RBAC: role-based access control (all read-only, future granularity)
"""

import re
import logging

logger = logging.getLogger("guardrails")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
MAX_INPUT_LENGTH = 16384
MAX_HISTORY_MESSAGES = 20

# ---------------------------------------------------------------------------
# Layer 1: Input validation
# ---------------------------------------------------------------------------

_INJECTION_PATTERNS = re.compile(
    r"ignore\s*(all\s*)?(previous|prior|above)\s*(instructions?|prompts?|rules?)|"
    r"you\s*are\s*now\s*(a|an|the)\s*|"
    r"system\s*prompt|"
    r"forget\s*(everything|all|your|previous)|"
    r"(override|bypass|ignore|disregard)\s*(your|the|all)?\s*(instructions?|rules?|guardrails?|restrictions?)|"
    r"jailbreak|DAN\s*mode|developer\s*mode|"
    r"pretend\s*(you\s*are|to\s*be)|"
    r"act\s*as\s*(if|though)\s*you\s*(have\s*no|don.t\s*have)|"
    r"repeat\s*(the|your)\s*(system|initial)\s*(prompt|instructions?)|"
    r"what\s*(is|are)\s*your\s*(system|initial)\s*(prompt|instructions?)|"
    r"ignore\s*(as|suas|todas)\s*(instru[cç][oõ]es|regras|restri[cç][oõ]es)|"
    r"esque[cç]a\s*(tudo|todas?\s*(as\s*)?regras|as\s*regras|suas\s*instru)|"
    r"modo\s*(desenvolvedor|admin|root|irrestrito)|"
    r"finja\s*(que\s*[eé]|ser)|"
    r"(desative|desabilite|remova)\s*(as?\s*)?(guardrails?|prote[cç][oõ]es?|filtros?|restri[cç])",
    re.IGNORECASE,
)

_DESTRUCTIVE_PATTERNS = re.compile(
    r"(delete|destroy|drop|truncate|remove|wipe|purge)\s+"
    r"(all|every|the)?\s*(database|table|bucket|cluster|vpc|instance|stack|resource|user|role|secret)|"
    r"(apague|exclua|destrua|remova|delete)\s+(todo|toda|todos|todas|o|a|os|as)?\s*"
    r"(banco|tabela|bucket|cluster|vpc|instancia|stack|recurso|usuario|role|secret|servico|container)|"
    r"rm\s+-rf|format\s+c:|shutdown|halt|kill\s+-9|force\s*delete|force\s*remove",
    re.IGNORECASE,
)


class InputGuardError(Exception):
    """Raised when input validation fails."""

    def __init__(self, message: str, reason: str):
        super().__init__(message)
        self.reason = reason
        self.user_message = message


def validate_input(question: str) -> str:
    """Validate and sanitize user input. Returns cleaned input or raises InputGuardError."""
    if not question or not question.strip():
        raise InputGuardError(
            "Por favor, envie uma pergunta.",
            reason="empty_input",
        )

    question = question.strip()

    if len(question) > MAX_INPUT_LENGTH:
        raise InputGuardError(
            f"Pergunta muito longa ({len(question)} caracteres). "
            f"Limite: {MAX_INPUT_LENGTH} caracteres.",
            reason="too_long",
        )

    if _INJECTION_PATTERNS.search(question):
        logger.warning(f"GUARDRAIL: prompt injection attempt blocked: {question[:100]}")
        raise InputGuardError(
            "Essa pergunta contém padrões não permitidos. "
            "Por favor, reformule sua pergunta sobre observabilidade, AWS ou infraestrutura.",
            reason="injection_attempt",
        )

    if _DESTRUCTIVE_PATTERNS.search(question):
        logger.warning(f"GUARDRAIL: destructive pattern blocked: {question[:100]}")
        raise InputGuardError(
            "O assistente opera em modo **read-only** e não pode executar operações destrutivas. "
            "Posso ajudar a diagnosticar, analisar ou recomendar ações.",
            reason="destructive_pattern",
        )

    return question


# ---------------------------------------------------------------------------
# Layer 2: Output scanning — detect leaked credentials/secrets
# ---------------------------------------------------------------------------

_SECRET_PATTERNS = [
    (re.compile(r"AKIA[0-9A-Z]{16}"), "AWS Access Key ID"),
    (re.compile(r"(?<![A-Za-z0-9/+=])[A-Za-z0-9/+=]{40}(?![A-Za-z0-9/+=])"), None),
    (re.compile(r"glsa_[A-Za-z0-9_]{32,}"), "Grafana Service Account Token"),
    (re.compile(r"sk-[A-Za-z0-9]{20,}"), "API Secret Key"),
    (re.compile(r"ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}"), "GitHub Token"),
    (re.compile(r"[A-Za-z0-9]{14}\.atlasv1\.[A-Za-z0-9]{60,}"), "TFC API Token"),
    (re.compile(r"(?<![A-Fa-f0-9])[A-Fa-f0-9]{64,}(?![A-Fa-f0-9])"), None),
]

_SAFE_PATTERNS = re.compile(
    r"(rtb|vpc|subnet|sg|eni|igw|nat|tgw|pcx|acl|ami|i|vol|snap|eip)-[0-9a-f]+|"
    r"arn:aws:[a-z0-9-]+:[a-z0-9-]*:\d{12}:|"
    r"sha256:[a-f0-9]{64}|"
    r"[a-f0-9]{32,40}(?=\s|$)",
)


def scan_output(response: str) -> str:
    """Scan LLM response for leaked credentials. Redacts if found."""
    redacted = False
    result = response

    for pattern, label in _SECRET_PATTERNS:
        for match in pattern.finditer(result):
            matched_text = match.group()
            if _SAFE_PATTERNS.search(matched_text):
                continue
            if len(matched_text) < 20:
                continue
            label_str = label or "Possible Secret"
            logger.warning(f"GUARDRAIL: redacted {label_str} from output")
            result = result.replace(matched_text, f"[REDACTED: {label_str}]")
            redacted = True

    if redacted:
        result += (
            "\n\n> **Guardrail**: Credenciais detectadas e removidas da resposta. "
            "Nunca compartilhe tokens ou chaves em texto."
        )

    return result


# ---------------------------------------------------------------------------
# Layer 3: Role-based access control
# ---------------------------------------------------------------------------

_ALL_QUERY_TYPES = {"observability", "github", "security", "terraform", "finops", "aws", "general"}

ROLE_TOOLS = {
    "admin": _ALL_QUERY_TYPES,
    "devops": _ALL_QUERY_TYPES,
    "user": _ALL_QUERY_TYPES,
    "dev": _ALL_QUERY_TYPES,
    "po": _ALL_QUERY_TYPES,
    "viewer": _ALL_QUERY_TYPES,
}

DEFAULT_ROLE = "user"


def check_role_access(role: str, query_type: str) -> bool:
    """Check if role has access to the given query type."""
    allowed = ROLE_TOOLS.get(role, _ALL_QUERY_TYPES)
    return query_type in allowed


def get_denied_message(role: str, query_type: str) -> str:
    """Return user-friendly message when access is denied."""
    return (
        f"Seu perfil **{role}** não tem acesso a consultas de **{query_type}**. "
        f"Entre em contato com o time DevOps para solicitar acesso."
    )
