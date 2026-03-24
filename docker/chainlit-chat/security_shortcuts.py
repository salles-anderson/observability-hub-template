"""
Security shortcuts — Level 1 cache for security queries.

Bypasses LLM for common security questions using boto3 directly:
1. Pattern-match user question (regex, Portuguese/English)
2. Query AWS API via boto3 + IAM Task Role (~1-3s)
3. Format response with markdown templates

Covers: GuardDuty findings, CloudTrail anomalies, IAM audit,
SSM secrets rotation, KMS key status, security prioritization.
"""

import asyncio
import json
import re
import os
import time
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

logger = logging.getLogger("security-shortcuts")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
ACCOUNT_ID = os.environ.get("AWS_ACCOUNT_ID", "YOUR_HUB_ACCOUNT_ID")

# ---------------------------------------------------------------------------
# boto3 clients — reuse cross-account engine from aws_shortcuts
# ---------------------------------------------------------------------------
from aws_shortcuts import _client, _call, set_account_context  # noqa: E402


# ---------------------------------------------------------------------------
# Response formatting
# ---------------------------------------------------------------------------
def _fmt_sec(
    title: str,
    headers: list[str],
    rows: list[list[str]],
    interpretation: str,
    details: str = "",
) -> str:
    """Build consistent markdown response for security queries."""
    hdr = "| " + " | ".join(headers) + " |"
    sep = "|" + "|".join("-------" for _ in headers) + "|"
    body = "\n".join("| " + " | ".join(r) + " |" for r in rows)

    parts = [f"### {title}", "", hdr, sep, body, "", interpretation]

    if details:
        parts.extend(["", f"```json\n{details}\n```"])

    return "\n".join(parts)


# ===================================================================
# GUARDDUTY HANDLERS
# ===================================================================
async def _guardduty_findings(**kwargs) -> Optional[str]:
    """List active GuardDuty findings."""
    try:
        # Get detector ID
        detectors = await _call("guardduty", "list_detectors")
        detector_ids = detectors.get("DetectorIds", [])
        if not detector_ids:
            return _fmt_sec(
                "GuardDuty Findings", ["Info"],
                [["GuardDuty nao esta habilitado nesta conta"]],
                "Habilite o GuardDuty para deteccao de ameacas.", "",
            )

        detector_id = detector_ids[0]

        # List findings (non-archived)
        findings_resp = await _call(
            "guardduty", "list_findings",
            DetectorId=detector_id,
            FindingCriteria={
                "Criterion": {
                    "service.archived": {"Eq": ["false"]},
                }
            },
            MaxResults=20,
        )
        finding_ids = findings_resp.get("FindingIds", [])

        if not finding_ids:
            return _fmt_sec(
                "GuardDuty Findings", ["Info"],
                [["Nenhum finding ativo"]],
                "Sem ameacas detectadas pelo GuardDuty. Ambiente limpo.", "",
            )

        # Get finding details
        details_resp = await _call(
            "guardduty", "get_findings",
            DetectorId=detector_id,
            FindingIds=finding_ids,
        )
        findings = details_resp.get("Findings", [])

        rows = []
        for f in sorted(findings, key=lambda x: x.get("Severity", 0), reverse=True):
            severity = f.get("Severity", 0)
            sev_label = "CRITICAL" if severity >= 8 else "HIGH" if severity >= 6 else "MEDIUM" if severity >= 4 else "LOW"
            title = f.get("Title", "?")[:50]
            finding_type = f.get("Type", "?")[:35]
            updated = f.get("UpdatedAt", "?")[:10]
            count = f.get("Service", {}).get("Count", 1)
            rows.append([sev_label, title, finding_type, updated, str(count)])

        return _fmt_sec(
            "GuardDuty — Findings Ativos",
            ["Severidade", "Titulo", "Tipo", "Atualizado", "Count"],
            rows,
            f"**{len(findings)} finding(s)** ativo(s). Investigue os de severidade HIGH/CRITICAL primeiro.",
        )
    except Exception as e:
        logger.error(f"GuardDuty findings error: {e}")
        return None


# ===================================================================
# CLOUDTRAIL ANOMALY HANDLERS
# ===================================================================
async def _cloudtrail_anomalies(**kwargs) -> Optional[str]:
    """Detect suspicious CloudTrail events in last 24h."""
    try:
        now = datetime.now(timezone.utc)
        start = now - timedelta(hours=24)

        # Run parallel lookups for different suspicious patterns
        unauthorized, root_usage, iam_changes = await asyncio.gather(
            _call("cloudtrail", "lookup_events",
                  LookupAttributes=[{"AttributeKey": "EventName", "AttributeValue": "ConsoleLogin"}],
                  StartTime=start, EndTime=now, MaxResults=50),
            _call("cloudtrail", "lookup_events",
                  LookupAttributes=[{"AttributeKey": "Username", "AttributeValue": "root"}],
                  StartTime=start, EndTime=now, MaxResults=10),
            _call("cloudtrail", "lookup_events",
                  StartTime=start, EndTime=now, MaxResults=50),
            return_exceptions=True,
        )

        anomalies = []

        # Check for failed logins
        if not isinstance(unauthorized, Exception):
            for ev in unauthorized.get("Events", []):
                try:
                    detail = json.loads(ev.get("CloudTrailEvent", "{}"))
                    result = detail.get("responseElements", {}).get("ConsoleLogin", "")
                    if result == "Failure":
                        anomalies.append({
                            "type": "FAILED_LOGIN",
                            "severity": "HIGH",
                            "user": ev.get("Username", "?"),
                            "ip": detail.get("sourceIPAddress", "?"),
                            "time": str(ev.get("EventTime", ""))[:19],
                        })
                except (json.JSONDecodeError, TypeError):
                    pass

        # Check for root account usage
        if not isinstance(root_usage, Exception):
            for ev in root_usage.get("Events", []):
                anomalies.append({
                    "type": "ROOT_USAGE",
                    "severity": "CRITICAL",
                    "user": "root",
                    "event": ev.get("EventName", "?"),
                    "time": str(ev.get("EventTime", ""))[:19],
                })

        # Check for IAM changes
        if not isinstance(iam_changes, Exception):
            iam_events = ["CreateUser", "DeleteUser", "CreateRole", "DeleteRole",
                          "AttachUserPolicy", "AttachRolePolicy", "PutUserPolicy",
                          "PutRolePolicy", "CreateAccessKey", "UpdateLoginProfile"]
            for ev in iam_changes.get("Events", []):
                if ev.get("EventName", "") in iam_events:
                    anomalies.append({
                        "type": "IAM_CHANGE",
                        "severity": "HIGH",
                        "user": ev.get("Username", "?"),
                        "event": ev.get("EventName", "?"),
                        "time": str(ev.get("EventTime", ""))[:19],
                    })

        if not anomalies:
            return _fmt_sec(
                "Anomalias de Seguranca (24h)", ["Info"],
                [["Nenhuma anomalia detectada"]],
                "Sem atividades suspeitas nas ultimas 24 horas.", "",
            )

        rows = []
        for a in sorted(anomalies, key=lambda x: {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3}.get(x["severity"], 4)):
            rows.append([
                a["severity"], a["type"], a.get("user", "?"),
                a.get("event", a.get("ip", "?")), a["time"],
            ])

        return _fmt_sec(
            "Anomalias de Seguranca — Ultimas 24h",
            ["Severidade", "Tipo", "Usuario", "Detalhe", "Timestamp"],
            rows[:20],
            f"**{len(anomalies)} anomalia(s)** detectada(s). "
            f"ROOT_USAGE e FAILED_LOGIN requerem investigacao imediata.",
        )
    except Exception as e:
        logger.error(f"CloudTrail anomalies error: {e}")
        return None


# ===================================================================
# PRIORITIZATION HANDLER
# ===================================================================
async def _prioritize_findings(**kwargs) -> Optional[str]:
    """Aggregate and prioritize all security findings."""
    try:
        # Run GuardDuty + CloudTrail in parallel
        gd_result, ct_result = await asyncio.gather(
            _guardduty_findings(),
            _cloudtrail_anomalies(),
            return_exceptions=True,
        )

        sections = ["### Triagem de Seguranca — Priorizada\n"]

        if isinstance(gd_result, str) and gd_result:
            sections.append("**GuardDuty:**")
            sections.append(gd_result)
        elif isinstance(gd_result, Exception):
            sections.append(f"GuardDuty: Erro — {gd_result}")

        sections.append("")

        if isinstance(ct_result, str) and ct_result:
            sections.append("**CloudTrail Anomalias:**")
            sections.append(ct_result)
        elif isinstance(ct_result, Exception):
            sections.append(f"CloudTrail: Erro — {ct_result}")

        sections.append("\n---\n**Ordem de investigacao recomendada:**")
        sections.append("1. ROOT_USAGE (acesso root nunca deveria ocorrer)")
        sections.append("2. CRITICAL GuardDuty findings")
        sections.append("3. FAILED_LOGIN (tentativas de acesso nao autorizado)")
        sections.append("4. IAM_CHANGE (mudancas de permissao)")
        sections.append("5. HIGH/MEDIUM GuardDuty findings")

        return "\n".join(sections)
    except Exception as e:
        logger.error(f"Prioritize findings error: {e}")
        return None


# ===================================================================
# SSM / KMS AUDIT HANDLERS
# ===================================================================
async def _audit_ssm_params(**kwargs) -> Optional[str]:
    """Audit SSM SecureString parameters."""
    try:
        resp = await _call(
            "ssm", "describe_parameters",
            ParameterFilters=[{"Key": "Type", "Values": ["SecureString"]}],
            MaxResults=50,
        )
        params = resp.get("Parameters", [])

        if not params:
            return _fmt_sec(
                "SSM SecureString Parameters", ["Info"],
                [["Nenhum parametro SecureString encontrado"]],
                "Sem secrets armazenados no SSM.", "",
            )

        now = datetime.now(timezone.utc)
        rows = []
        stale_count = 0
        for p in sorted(params, key=lambda x: x.get("LastModifiedDate", datetime.min.replace(tzinfo=timezone.utc))):
            name = p.get("Name", "?")
            version = p.get("Version", 0)
            last_modified = p.get("LastModifiedDate")
            if last_modified:
                age_days = (now - last_modified.replace(tzinfo=timezone.utc) if last_modified.tzinfo is None else now - last_modified).days
                mod_str = str(last_modified)[:10]
                age_str = f"{age_days}d"
                if age_days > 90:
                    age_str += " ⚠️"
                    stale_count += 1
            else:
                mod_str = "?"
                age_str = "?"

            rows.append([name[-40:], str(version), mod_str, age_str])

        tip = f"**{len(params)} secrets** | **{stale_count} com >90 dias** (considere rotacao)."
        return _fmt_sec(
            "SSM SecureString — Auditoria",
            ["Parametro", "Versao", "Modificado", "Idade"],
            rows, tip,
        )
    except Exception as e:
        logger.error(f"SSM audit error: {e}")
        return None


async def _kms_key_status(**kwargs) -> Optional[str]:
    """Check KMS key status and rotation."""
    try:
        resp = await _call("kms", "list_keys", Limit=20)
        keys = resp.get("Keys", [])

        if not keys:
            return _fmt_sec(
                "KMS Keys", ["Info"],
                [["Nenhuma KMS key encontrada"]],
                "Sem chaves KMS nesta conta.", "",
            )

        rows = []
        for k in keys:
            key_id = k.get("KeyId", "?")
            try:
                desc = await _call("kms", "describe_key", KeyId=key_id)
                meta = desc.get("KeyMetadata", {})
                state = meta.get("KeyState", "?")
                origin = meta.get("Origin", "?")
                manager = meta.get("KeyManager", "?")
                desc_text = meta.get("Description", "")[:25]

                if manager == "CUSTOMER":
                    try:
                        rot = await _call("kms", "get_key_rotation_status", KeyId=key_id)
                        rotation = "Ativo" if rot.get("KeyRotationEnabled") else "Inativo ⚠️"
                    except Exception:
                        rotation = "N/A"
                else:
                    rotation = "AWS-managed"

                rows.append([key_id[:12], state, manager, rotation, desc_text])
            except Exception:
                rows.append([key_id[:12], "?", "?", "?", "erro ao descrever"])

        return _fmt_sec(
            "KMS Keys — Status",
            ["Key ID", "Estado", "Manager", "Rotacao", "Descricao"],
            rows,
            f"**{len(keys)} chave(s)** KMS. Chaves CUSTOMER sem rotacao precisam de atencao.",
        )
    except Exception as e:
        logger.error(f"KMS key status error: {e}")
        return None


# ===================================================================
# SHORTCUT REGISTRY — ordered most specific → most general
# ===================================================================
_SECURITY_SHORTCUTS: list[tuple[re.Pattern, callable]] = [
    # GuardDuty specific
    (re.compile(r"guard\s*duty|findings?\s*(de\s*)?(segur|threat|ameac)", re.I), _guardduty_findings),

    # CloudTrail anomalies
    (re.compile(r"anomalia.*segur|login.*suspeito|acesso.*n[aã]o\s*autoriz|unauthorized|failed\s*login", re.I), _cloudtrail_anomalies),

    # Prioritized triage
    (re.compile(r"triagem|prioriz|triage|security\s*overview|postura\s*de\s*segur|vis[aã]o\s*geral.*segur", re.I), _prioritize_findings),

    # SSM/Secrets audit
    (re.compile(r"ssm|secrets?\s*(audit|rotac|rotat)|parametros?\s*seguros?|secure\s*string", re.I), _audit_ssm_params),

    # KMS
    (re.compile(r"kms|chaves?\s*(kms|cripto|encrypt)|key\s*rotation", re.I), _kms_key_status),

    # General security — catch-all (must be last)
    (re.compile(r"segur(an[cç]a|ity)|vulnerabilid|ameac|threat|security", re.I), _prioritize_findings),
]


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
async def try_security_shortcut(question: str) -> Optional[str]:
    """Try to answer security question with direct boto3 call.

    Returns formatted markdown response or None (fallback to LLM).
    """
    start = time.monotonic()
    q_lower = question.lower()

    for pattern, handler in _SECURITY_SHORTCUTS:
        if pattern.search(q_lower):
            try:
                response = await handler(question=question)
                elapsed_ms = (time.monotonic() - start) * 1000

                if response:
                    source = "AWS API (boto3 Security)"
                    response += (
                        f"\n\n---\n*Resposta direta via {source} — "
                        f"{elapsed_ms:.0f}ms (sem LLM)*"
                    )
                    logger.info(json.dumps({
                        "event": "security_shortcut",
                        "hit": True,
                        "handler": handler.__name__ if hasattr(handler, "__name__") else "lambda",
                        "latency_ms": round(elapsed_ms),
                        "question": question[:100],
                    }))
                    return response

                logger.info(json.dumps({
                    "event": "security_shortcut",
                    "hit": False,
                    "reason": "no_data",
                    "latency_ms": round(elapsed_ms),
                    "question": question[:100],
                }))
                return None

            except Exception as e:
                logger.error(f"Security shortcut handler error: {e}")
                return None

    elapsed_ms = (time.monotonic() - start) * 1000
    logger.info(json.dumps({
        "event": "security_shortcut",
        "hit": False,
        "reason": "no_match",
        "latency_ms": round(elapsed_ms),
        "question": question[:100],
    }))
    return None
