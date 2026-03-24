"""
Shortcuts package — regex fast-path (no LLM, ~200ms).

PHILOSOPHY: AG-2 by default. Shortcuts ONLY for queries that are
100% unambiguous, single-metric, and need no analysis.

A shortcut should ONLY fire when:
1. The user asks for ONE specific metric (latency p95, error rate, throughput)
2. There is NO analytical intent (no "why", "how", "analyze", "compare")
3. There is NO multi-domain aspect (no "and also check infra/code/costs")
4. The answer is a SINGLE number or table from ONE datasource

If there is ANY ambiguity → AG-2 handles it with full analysis.

This serves ALL personas: Dev, DevOps, SRE, DBA, Tech Lead, CTO.
A shortcut that gives a partial answer is WORSE than a slower complete answer.
"""

from __future__ import annotations

import asyncio
import logging
import re

logger = logging.getLogger("shortcuts")

# ---------------------------------------------------------------------------
# AG-2 force patterns — these ALWAYS go to AG-2, no exceptions
# ---------------------------------------------------------------------------
_AG2_FORCE_PATTERNS = re.compile(
    r"(?:"
    # Analytical intent
    r"investig|analise|analis[ea]r|analyz|diagnos|root\s*cause|"
    r"por\s*qu[eê]|why\b|what\s*caused|o\s+que\s+causou|"
    # Explanatory intent
    r"explique|explic[ao]|detalhe|me\s+expli|o\s+que\s+(?:significa|quer\s+dizer)|"
    # Fix/improvement intent
    r"como\s+(?:resolver|fix|corrigir|melhorar|otimizar|configurar|criar)|"
    # Comparison/correlation
    r"compara|correlacion|relacion|impacto|blast\s*radius|"
    # Error logs pasted
    r"Error:|error\s*:|StatusCode:\s*\d|exception|traceback|stack\s*trace|"
    r"secret\.valueFrom|RegisterTaskDefinition|ClientException|"
    # Multi-domain keywords
    r"completa|complet[ao]|geral|overview|vis[aã]o\s*geral|resumo\s*(?:completo|geral)|"
    r"tudo\s*(?:sobre|do|da)|analise\s*completa|"
    # Temporal analysis
    r"(?:ultim|últim)[ao]s?\s*\d+\s*(?:hora|dia|semana|minuto)|nas?\s*ultimas?|"
    r"o\s*que\s*mudou|o\s*que\s*aconteceu|mudanças|changes|"
    # Specific tools/services that need their own agent
    r"sonarqube|quality\s*gate|code\s*smell|coverage|"
    r"pr\b|pull\s*request|commit|pipeline|github|workflow|deploy|"
    r"guardduty|cloudtrail|finding|threat|vulnerab|"
    r"terraform|workspace|plan\b|state\b|drift|tfc\b|"
    r"custo|gasto|cost|budget|forecast|savings|rightsize|quanto\s*custa|"
    r"ecs\b.*(?:task|service|desired|running)|rds\b.*(?:status|connection)|"
    r"redis\b.*(?:status|connection)|elasticache|"
    # Risk/problem assessment
    r"risco|problema|issue|incidente|alerta.*ativ[oa]|"
    r"tem\s*algum\s*(?:problema|erro|risco|finding)|"
    # How is X doing (wants full analysis, not just metrics)
    r"como\s*(?:est[aá]|vai|anda)\b"
    r")",
    re.IGNORECASE,
)

# ---------------------------------------------------------------------------
# Shortcut ALLOW patterns — ONLY these very specific queries get shortcuts
# ---------------------------------------------------------------------------
_SHORTCUT_ALLOW_PATTERNS = [
    # Exact metric queries — no ambiguity
    (r"^(?:qual\s*[aeo]?\s*)?lat[eê]ncia\s*p9[59]\b", "latency"),
    (r"^(?:qual\s*[aeo]?\s*)?lat[eê]ncia\s*p50\b", "latency"),
    (r"^(?:qual\s*[aeo]?\s*)?error\s*rate\b", "error_rate"),
    (r"^(?:qual\s*[aeo]?\s*)?taxa\s*de\s*erro\b", "error_rate"),
    (r"^(?:qual\s*[aeo]?\s*)?throughput\b", "throughput"),
    (r"^(?:qual\s*[aeo]?\s*)?disponibilidade\b", "availability"),
    (r"^(?:qual\s*[aeo]?\s*)?uptime\b", "availability"),
    (r"^(?:qual\s*[aeo]?\s*)?error\s*budget\b", "error_budget"),
    (r"^(?:qual\s*[aeo]?\s*)?burn\s*rate\b", "burn_rate"),
    # Direct service listing — no analysis
    (r"^(?:lista?r?\s*)?(?:quais\s*)?servi[cç]os?\s*(?:ecs|rodando|ativos?)\b", "aws_list"),
    (r"^(?:lista?r?\s*)?(?:quais\s*)?(?:top\s*)?servi[cç]os?\s*(?:por\s*)?custo\b", "cost_top"),
]


def _is_shortcut_allowed(question: str) -> bool:
    """Return True ONLY if the query matches an exact shortcut pattern."""
    q = question.strip()
    for pattern, _ in _SHORTCUT_ALLOW_PATTERNS:
        if re.search(pattern, q, re.IGNORECASE):
            return True
    return False


def _should_skip_shortcuts(question: str) -> bool:
    """Return True if query should go to AG-2 (default: most queries).

    Philosophy: AG-2 by default. Shortcuts only for exact metric queries.
    """
    # Very long queries — always AG-2 (pasted logs, errors, etc)
    if len(question) > 150:
        logger.info(f"Shortcuts SKIP: long query ({len(question)} chars)")
        return True

    # AG-2 force patterns — analytical, multi-domain, explanatory
    if _AG2_FORCE_PATTERNS.search(question):
        logger.info("Shortcuts SKIP: AG-2 pattern detected")
        return True

    # If not explicitly allowed by shortcut patterns → AG-2
    if not _is_shortcut_allowed(question):
        logger.info("Shortcuts SKIP: not an exact metric query → AG-2")
        return True

    return False


async def try_all_shortcuts(question: str) -> str | None:
    """Try shortcuts ONLY for exact, unambiguous metric queries.

    Most queries bypass shortcuts and go to AG-2 for complete analysis.
    This ensures every persona (Dev, SRE, DBA, Tech Lead) gets
    accurate, multi-source answers.

    Shortcuts only handle:
    - "latência p95" → single Prometheus value
    - "error rate" → single Prometheus value
    - "throughput" → single Prometheus value
    - "error budget" → single Prometheus value
    - "serviços ECS rodando" → single boto3 call
    """
    # Default: skip shortcuts, go to AG-2
    if _should_skip_shortcuts(question):
        return None

    logger.info(f"Shortcuts ALLOW: exact metric query '{question[:60]}'")

    from query_cache import try_shortcut
    from aws_shortcuts import try_aws_shortcut
    from security_shortcuts import try_security_shortcut
    from tfc_shortcuts import try_tfc_shortcut

    results = await asyncio.gather(
        try_shortcut(question),
        try_aws_shortcut(question),
        try_security_shortcut(question),
        try_tfc_shortcut(question),
        return_exceptions=True,
    )

    for result in results:
        if isinstance(result, str) and result:
            return result

    return None
