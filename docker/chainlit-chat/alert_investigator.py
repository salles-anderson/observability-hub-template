"""
AG-3: Proactive Alert Investigation

Receives AlertManager webhooks, translates alerts into natural language,
runs AG-2 multi-agent pipeline, posts results to Slack, saves to Qdrant.

Endpoint: POST /api/alert-investigate (mounted on Chainlit's Starlette app)
Feature flag: ENABLE_ALERT_INVESTIGATION=true
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os
import time
from datetime import datetime, timezone

import httpx
from openai import AsyncOpenAI
from starlette.requests import Request
from starlette.responses import JSONResponse

logger = logging.getLogger("alert-investigator")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SLACK_BOT_TOKEN = os.environ.get("SLACK_BOT_TOKEN", "")
SLACK_ALERT_CHANNEL = os.environ.get("SLACK_ALERT_CHANNEL", "#observability-alerts")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://qdrant.observability.local:6333")
LITELLM_URL = os.environ.get("LITELLM_URL", "http://litellm.observability.local:4000")
EMBED_MODEL = os.environ.get("RAG_EMBED_MODEL", "text-embedding-titan-v2")
COLLECTION_NAME = os.environ.get("RAG_COLLECTION", "obs_hub_knowledge")
INVESTIGATION_TIMEOUT = int(os.environ.get("AG3_TIMEOUT", "180"))


# ---------------------------------------------------------------------------
# Rate Limiter + Dedup
# ---------------------------------------------------------------------------
class AlertRateLimiter:
    """In-memory rate limiter with per-fingerprint cooldown."""

    def __init__(self, max_per_hour: int = 5, cooldown_minutes: int = 30):
        self.max_per_hour = max_per_hour
        self.cooldown_minutes = cooldown_minutes
        self._history: list[float] = []
        self._cooldown: dict[str, float] = {}

    def should_investigate(self, fingerprint: str) -> tuple[bool, str]:
        now = time.monotonic()

        # Check cooldown per fingerprint
        last = self._cooldown.get(fingerprint)
        if last and (now - last) < self.cooldown_minutes * 60:
            remaining = int(self.cooldown_minutes - (now - last) / 60)
            return False, f"cooldown_active ({remaining}min remaining)"

        # Check global rate limit (sliding window)
        cutoff = now - 3600
        self._history = [ts for ts in self._history if ts > cutoff]
        if len(self._history) >= self.max_per_hour:
            return False, "rate_limit_exceeded"

        # Accept
        self._history.append(now)
        self._cooldown[fingerprint] = now
        return True, "accepted"

    @property
    def stats(self) -> dict:
        now = time.monotonic()
        cutoff = now - 3600
        active = [ts for ts in self._history if ts > cutoff]
        return {
            "investigations_last_hour": len(active),
            "max_per_hour": self.max_per_hour,
            "active_cooldowns": len(self._cooldown),
        }


_rate_limiter = AlertRateLimiter()


# ---------------------------------------------------------------------------
# Alert → Natural Language Query
# ---------------------------------------------------------------------------
def _fingerprint(alert: dict) -> str:
    """Generate dedup fingerprint from alert labels."""
    labels = alert.get("labels", {})
    key = f"{labels.get('alertname', '')}|{labels.get('job', '')}|{labels.get('severity', '')}"
    return hashlib.md5(key.encode()).hexdigest()[:12]


def alert_to_query(alert: dict) -> str:
    """Translate AlertManager alert into a multi-domain investigation query."""
    labels = alert.get("labels", {})
    annotations = alert.get("annotations", {})

    alertname = labels.get("alertname", "unknown")
    service = labels.get("job", labels.get("service", "unknown"))
    project = labels.get("project", service.split("-")[0] if "-" in service else service)
    severity = labels.get("severity", "unknown")
    summary = annotations.get("summary", "")
    description = annotations.get("description", "")
    starts_at = alert.get("startsAt", "")

    return (
        f"INVESTIGACAO AUTOMATICA DE ALERTA (AG-3)\n"
        f"Alerta: {alertname} ({severity})\n"
        f"Servico: {service} | Projeto: {project}\n"
        f"Inicio: {starts_at}\n"
        f"Resumo: {summary}\n"
        f"Descricao: {description}\n\n"
        f"Investigue este alerta de forma completa e acionavel:\n"
        f"1. Verifique metricas (latencia, error rate, throughput) e logs recentes do servico {service}\n"
        f"2. Verifique o estado da infraestrutura: ECS tasks, health checks, RDS, Redis\n"
        f"3. Verifique se houve deploys ou PRs recentes no repositorio {project}\n"
        f"4. Correlacione todas as evidencias e identifique a causa raiz provavel\n"
        f"5. Sugira acoes imediatas de mitigacao"
    )


# ---------------------------------------------------------------------------
# Slack Integration
# ---------------------------------------------------------------------------
async def post_investigation_to_slack(
    alert: dict,
    investigation: str,
    channel: str = "",
) -> None:
    """Post investigation result to Slack using chat.postMessage with Block Kit."""
    if not SLACK_BOT_TOKEN:
        logger.warning("SLACK_BOT_TOKEN not set, skipping Slack notification")
        return

    channel = channel or SLACK_ALERT_CHANNEL
    labels = alert.get("labels", {})
    alertname = labels.get("alertname", "unknown")
    service = labels.get("job", "unknown")
    severity = labels.get("severity", "unknown")

    severity_emoji = {"critical": ":rotating_light:", "warning": ":warning:"}.get(
        severity, ":information_source:"
    )

    # Truncate investigation for Slack (max ~3000 chars per section)
    inv_text = investigation[:2900] + "..." if len(investigation) > 2900 else investigation

    blocks = [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": f"{severity_emoji} AG-3 Investigation: {alertname}",
            },
        },
        {
            "type": "section",
            "fields": [
                {"type": "mrkdwn", "text": f"*Service:* `{service}`"},
                {"type": "mrkdwn", "text": f"*Severity:* {severity}"},
                {"type": "mrkdwn", "text": f"*Alert:* {alertname}"},
                {
                    "type": "mrkdwn",
                    "text": f"*Time:* {datetime.now(timezone.utc).strftime('%H:%M UTC')}",
                },
            ],
        },
        {"type": "divider"},
        {
            "type": "section",
            "text": {"type": "mrkdwn", "text": inv_text},
        },
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": ":robot_face: Investigacao automatica via AG-3 (Router + Agents + Correlator)",
                },
            ],
        },
    ]

    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(
                "https://slack.com/api/chat.postMessage",
                headers={"Authorization": f"Bearer {SLACK_BOT_TOKEN}"},
                json={
                    "channel": channel,
                    "blocks": blocks,
                    "text": f"AG-3 Investigation: {alertname} on {service}",
                },
            )
            data = resp.json()
            if not data.get("ok"):
                logger.error(f"Slack API error: {data.get('error', 'unknown')}")
            else:
                logger.info(f"Posted investigation to Slack {channel}")
    except Exception as e:
        logger.error(f"Failed to post to Slack: {e}")


# ---------------------------------------------------------------------------
# Qdrant Persistence
# ---------------------------------------------------------------------------
async def save_investigation_to_qdrant(alert: dict, investigation: str) -> None:
    """Embed and save investigation to Qdrant for future RAG retrieval."""
    if not QDRANT_URL:
        return

    labels = alert.get("labels", {})
    alertname = labels.get("alertname", "unknown")
    service = labels.get("job", "unknown")

    text = (
        f"## Investigacao de Alerta: {alertname} — {service}\n"
        f"**Severidade:** {labels.get('severity', 'unknown')}\n"
        f"**Data:** {datetime.now(timezone.utc).isoformat()}\n\n"
        f"{investigation}"
    )

    try:
        # Embed via LiteLLM → Titan Embed v2
        embed_client = AsyncOpenAI(base_url=f"{LITELLM_URL}/v1", api_key="not-needed")
        resp = await embed_client.embeddings.create(model=EMBED_MODEL, input=text[:2048])
        vector = resp.data[0].embedding

        # Deterministic point ID from content hash
        chunk_hash = hashlib.sha256(text.encode()).hexdigest()[:16]
        point_id = int(hashlib.sha256(chunk_hash.encode()).hexdigest()[:15], 16)

        # Upsert to Qdrant
        async with httpx.AsyncClient(base_url=QDRANT_URL, timeout=10) as client:
            await client.put(
                f"/collections/{COLLECTION_NAME}/points",
                json={
                    "points": [
                        {
                            "id": point_id,
                            "vector": vector,
                            "payload": {
                                "text": text,
                                "source_file": f"alert/{alertname}",
                                "section_title": f"Investigacao: {alertname} — {service}",
                                "doc_type": "alert_investigation",
                                "chunk_hash": chunk_hash,
                                "alert_labels": labels,
                                "investigated_at": datetime.now(timezone.utc).isoformat(),
                            },
                        }
                    ]
                },
            )
            logger.info(f"Saved investigation to Qdrant: {alertname}/{service}")
    except Exception as e:
        logger.error(f"Failed to save to Qdrant: {e}")


# ---------------------------------------------------------------------------
# Background Investigation Task
# ---------------------------------------------------------------------------
async def _investigate_alert(alert: dict) -> None:
    """Background task: run AG-2 pipeline, post Slack, save Qdrant."""
    from core.orchestrator import run_ag2_collect

    labels = alert.get("labels", {})
    alertname = labels.get("alertname", "unknown")
    service = labels.get("job", "unknown")

    logger.info(f"Starting investigation: {alertname} on {service}")
    start = time.monotonic()

    try:
        question = alert_to_query(alert)
        investigation = await asyncio.wait_for(
            run_ag2_collect(question, role="system"),
            timeout=INVESTIGATION_TIMEOUT,
        )
    except asyncio.TimeoutError:
        investigation = (
            f"Investigacao parcial (timeout {INVESTIGATION_TIMEOUT}s): "
            f"O alerta {alertname} no servico {service} requer investigacao manual."
        )
        logger.warning(f"Investigation timeout: {alertname}/{service}")
    except Exception as e:
        investigation = f"Erro na investigacao automatica: {e}"
        logger.error(f"Investigation error: {alertname}/{service}: {e}")

    elapsed = (time.monotonic() - start) * 1000
    logger.info(f"Investigation complete: {alertname}/{service} ({elapsed:.0f}ms)")

    # Post to Slack and save to Qdrant (parallel, non-blocking)
    await asyncio.gather(
        post_investigation_to_slack(alert, investigation),
        save_investigation_to_qdrant(alert, investigation),
        return_exceptions=True,
    )


# ---------------------------------------------------------------------------
# Starlette Endpoints
# ---------------------------------------------------------------------------
async def handle_alert_webhook(request: Request):
    """POST /api/alert-investigate — receive AlertManager webhook, dispatch investigations."""
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "invalid JSON"}, status_code=400)

    alerts = body.get("alerts", [])
    if not alerts:
        return JSONResponse({"error": "no alerts in payload"}, status_code=400)

    dispatched = 0
    skipped = []

    for alert in alerts:
        # Only investigate firing alerts
        if alert.get("status") != "firing":
            continue

        fp = _fingerprint(alert)
        ok, reason = _rate_limiter.should_investigate(fp)

        if not ok:
            labels = alert.get("labels", {})
            skipped.append({
                "alertname": labels.get("alertname", "unknown"),
                "reason": reason,
            })
            logger.info(f"Skipping alert {labels.get('alertname')}: {reason}")
            continue

        asyncio.create_task(_investigate_alert(alert))
        dispatched += 1

    return JSONResponse(
        {
            "status": "accepted",
            "dispatched": dispatched,
            "skipped": skipped,
            "rate_limiter": _rate_limiter.stats,
        },
        status_code=202,
    )


async def health_ag3(request: Request):
    """GET /api/alert-investigate/health — rate limiter stats."""
    return JSONResponse({
        "status": "ok",
        "rate_limiter": _rate_limiter.stats,
    })
