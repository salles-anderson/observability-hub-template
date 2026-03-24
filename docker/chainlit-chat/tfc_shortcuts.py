"""
Terraform Cloud shortcuts — Level 1 cache for TFC queries.

Bypasses LLM for common Terraform questions using TFC API directly:
1. Pattern-match user question (regex, Portuguese/English)
2. Query TFC API via httpx (~1-3s)
3. Format response with markdown templates

Covers: workspaces status, runs, plan output, state versions, drift detection.
TFC Organization: YOUR_ORG
"""

import asyncio
import json
import re
import os
import time
import logging
import unicodedata
from datetime import datetime, timezone
from typing import Optional

import httpx

logger = logging.getLogger("tfc-shortcuts")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
TFC_API_TOKEN = os.environ.get("TFC_API_TOKEN", "")
TFC_BASE_URL = "https://app.terraform.io/api/v2"
TFC_ORG = os.environ.get("TFC_ORG", "YOUR_ORG")

# Known workspaces for quick resolution
KNOWN_WORKSPACES = {
    "hub": "teck-observability-hub-prod",
    "infra": "teck-observability-hub-prod",
    "observability": "teck-observability-hub-prod",
    "dashboards": "grafana-dashboards",
    "grafana": "grafana-dashboards",
    "alerts": "grafana-dashboards",
}

# ---------------------------------------------------------------------------
# HTTP client
# ---------------------------------------------------------------------------
_client: httpx.AsyncClient | None = None


def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(
            base_url=TFC_BASE_URL,
            headers={
                "Authorization": f"Bearer {TFC_API_TOKEN}",
                "Content-Type": "application/vnd.api+json",
            },
            timeout=httpx.Timeout(15.0, connect=5.0),
        )
    return _client


async def _tfc_get(path: str) -> dict:
    """GET request to TFC API."""
    client = _get_client()
    resp = await client.get(path)
    resp.raise_for_status()
    return resp.json()


async def _tfc_post(path: str, payload: dict) -> dict:
    """POST request to TFC API."""
    client = _get_client()
    resp = await client.post(path, json=payload)
    resp.raise_for_status()
    return resp.json()


# ---------------------------------------------------------------------------
# Response formatting
# ---------------------------------------------------------------------------
def _fmt_tfc(
    title: str,
    headers: list[str],
    rows: list[list[str]],
    interpretation: str,
) -> str:
    """Build consistent markdown response for TFC queries."""
    hdr = "| " + " | ".join(headers) + " |"
    sep = "|" + "|".join("-------" for _ in headers) + "|"
    body = "\n".join("| " + " | ".join(r) + " |" for r in rows)
    return "\n".join([f"### {title}", "", hdr, sep, body, "", interpretation])


def _resolve_workspace(question: str) -> str:
    """Resolve workspace name from question context."""
    q_lower = question.lower()
    for alias, ws_name in KNOWN_WORKSPACES.items():
        if alias in q_lower:
            return ws_name
    return "teck-observability-hub-prod"


# ===================================================================
# TFC HANDLERS
# ===================================================================
async def _list_workspaces(**kwargs) -> Optional[str]:
    """List all TFC workspaces with status."""
    try:
        if not TFC_API_TOKEN:
            return _fmt_tfc("Terraform Cloud", ["Info"], [["TFC_API_TOKEN nao configurado"]], "Configure a variavel de ambiente TFC_API_TOKEN.")

        resp = await _tfc_get(f"/organizations/{TFC_ORG}/workspaces?page[size]=20")
        workspaces = resp.get("data", [])

        if not workspaces:
            return _fmt_tfc("TFC Workspaces", ["Info"], [["Nenhum workspace encontrado"]], f"Organizacao: {TFC_ORG}")

        rows = []
        for ws in sorted(workspaces, key=lambda w: w.get("attributes", {}).get("name", "")):
            attrs = ws.get("attributes", {})
            name = attrs.get("name", "?")
            resource_count = attrs.get("resource-count", 0)
            updated = attrs.get("updated-at", "?")[:10]
            tf_version = attrs.get("terraform-version", "?")
            execution_mode = attrs.get("execution-mode", "?")

            # Get latest run status
            latest_run = attrs.get("current-run", {})
            run_status = "N/A"
            if latest_run:
                run_status = latest_run.get("status", "N/A") if isinstance(latest_run, dict) else "N/A"

            rows.append([name, str(resource_count), tf_version, execution_mode, updated])

        return _fmt_tfc(
            f"TFC Workspaces — {TFC_ORG}",
            ["Workspace", "Recursos", "TF Version", "Execucao", "Atualizado"],
            rows, f"**{len(workspaces)} workspace(s)** na organizacao {TFC_ORG}.",
        )
    except httpx.HTTPStatusError as e:
        logger.error(f"TFC API error: {e.response.status_code} — {e.response.text[:200]}")
        return None
    except Exception as e:
        logger.error(f"List workspaces error: {e}")
        return None


async def _get_workspace_runs(**kwargs) -> Optional[str]:
    """Get recent runs for a workspace."""
    try:
        if not TFC_API_TOKEN:
            return None

        question = kwargs.get("question", "")
        ws_name = _resolve_workspace(question)

        # Get workspace ID
        resp = await _tfc_get(f"/organizations/{TFC_ORG}/workspaces/{ws_name}")
        ws_id = resp.get("data", {}).get("id", "")

        if not ws_id:
            return _fmt_tfc("TFC Runs", ["Info"], [[f"Workspace '{ws_name}' nao encontrado"]], "Verifique o nome do workspace.")

        # Get runs
        runs_resp = await _tfc_get(f"/workspaces/{ws_id}/runs?page[size]=10")
        runs = runs_resp.get("data", [])

        if not runs:
            return _fmt_tfc(f"TFC Runs — {ws_name}", ["Info"], [["Nenhum run encontrado"]], "Sem runs recentes neste workspace.")

        rows = []
        for run in runs[:10]:
            attrs = run.get("attributes", {})
            run_id = run.get("id", "?")[:12]
            status = attrs.get("status", "?")
            created = attrs.get("created-at", "?")[:16].replace("T", " ")
            message = attrs.get("message", "")[:40]
            is_destroy = "DESTROY" if attrs.get("is-destroy") else ""

            status_icon = {
                "applied": "applied",
                "planned_and_finished": "plan_ok",
                "planned": "planned",
                "planning": "planning...",
                "errored": "ERRORED",
                "discarded": "discarded",
                "canceled": "canceled",
            }.get(status, status)

            rows.append([run_id, status_icon, created, message, is_destroy])

        return _fmt_tfc(
            f"TFC Runs — {ws_name}",
            ["Run ID", "Status", "Criado", "Mensagem", "Destroy?"],
            rows, f"Ultimos **{len(runs)}** runs do workspace `{ws_name}`.",
        )
    except Exception as e:
        logger.error(f"Get workspace runs error: {e}")
        return None


async def _get_state_version(**kwargs) -> Optional[str]:
    """Get current state version info for a workspace."""
    try:
        if not TFC_API_TOKEN:
            return None

        question = kwargs.get("question", "")
        ws_name = _resolve_workspace(question)

        resp = await _tfc_get(f"/organizations/{TFC_ORG}/workspaces/{ws_name}")
        ws_id = resp.get("data", {}).get("id", "")
        ws_attrs = resp.get("data", {}).get("attributes", {})
        resource_count = ws_attrs.get("resource-count", 0)

        if not ws_id:
            return None

        # Get latest state version
        state_resp = await _tfc_get(f"/workspaces/{ws_id}/current-state-version")
        state_data = state_resp.get("data", {})
        state_attrs = state_data.get("attributes", {})

        serial = state_attrs.get("serial", "?")
        created = state_attrs.get("created-at", "?")[:16].replace("T", " ")
        size = state_attrs.get("size", 0)
        size_kb = size / 1024 if size else 0

        rows = [
            ["Workspace", ws_name],
            ["Recursos", str(resource_count)],
            ["State Serial", str(serial)],
            ["Tamanho", f"{size_kb:.1f} KB"],
            ["Ultima atualizacao", created],
        ]

        return _fmt_tfc(
            f"TFC State — {ws_name}",
            ["Atributo", "Valor"], rows,
            f"State version **#{serial}** com **{resource_count} recursos**.",
        )
    except Exception as e:
        logger.error(f"Get state version error: {e}")
        return None


async def _get_plan_output(**kwargs) -> Optional[str]:
    """Get plan output summary for the latest run."""
    try:
        if not TFC_API_TOKEN:
            return None

        question = kwargs.get("question", "")
        ws_name = _resolve_workspace(question)

        # Get workspace ID and latest run
        resp = await _tfc_get(f"/organizations/{TFC_ORG}/workspaces/{ws_name}")
        ws_id = resp.get("data", {}).get("id", "")
        if not ws_id:
            return None

        runs_resp = await _tfc_get(f"/workspaces/{ws_id}/runs?page[size]=1")
        runs = runs_resp.get("data", [])
        if not runs:
            return _fmt_tfc(f"TFC Plan — {ws_name}", ["Info"], [["Nenhum run encontrado"]], "")

        run = runs[0]
        run_id = run.get("id", "?")
        attrs = run.get("attributes", {})
        status = attrs.get("status", "?")
        message = attrs.get("message", "?")
        has_changes = attrs.get("has-changes", False)

        plan_rel = run.get("relationships", {}).get("plan", {}).get("data", {})
        plan_id = plan_rel.get("id", "")

        add = attrs.get("resource-additions", 0) or 0
        change = attrs.get("resource-changes", 0) or 0
        destroy = attrs.get("resource-destructions", 0) or 0

        rows = [
            ["Run ID", run_id[:20]],
            ["Status", status],
            ["Mensagem", message[:60]],
            ["Tem mudancas?", "Sim" if has_changes else "Nao"],
            ["Adicoes", str(add)],
            ["Alteracoes", str(change)],
            ["Destruicoes", str(destroy)],
        ]

        risk = "BAIXO"
        if destroy > 0:
            risk = "ALTO (destruicoes detectadas!)"
        elif change > 5:
            risk = "MEDIO (muitas alteracoes)"

        return _fmt_tfc(
            f"TFC Plan — {ws_name}",
            ["Atributo", "Valor"], rows,
            f"Plan: **+{add} ~{change} -{destroy}** | Risco: **{risk}**",
        )
    except Exception as e:
        logger.error(f"Get plan output error: {e}")
        return None


# ===================================================================
# SHORTCUT REGISTRY
# ===================================================================
_TFC_SHORTCUTS: list[tuple[re.Pattern, callable]] = [
    # Plan specific
    (re.compile(r"plan\s*(terraform|tfc|output|diff|review)|terraform\s*plan|ultimo\s*plan|analise?\s*o?\s*plan", re.I), _get_plan_output),

    # State specific
    (re.compile(r"state\s*(terraform|version|serial|recursos)|terraform\s*state|quantos?\s*recursos?", re.I), _get_state_version),

    # Runs — "último run", "run do workspace", "runs recentes", "current run"
    (re.compile(r"ultim\w*\s*run|current\s*run|run\w*\s*do\s*workspace|historico.*run", re.I), _get_workspace_runs),

    # Workspaces — most general, must be last
    (re.compile(r"list\w*\s*workspace|workspace|tfc|status.*(terraform|infra)", re.I), _list_workspaces),
]


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
def _strip_accents(text: str) -> str:
    """Remove accents for regex matching (último → ultimo)."""
    nfkd = unicodedata.normalize("NFKD", text)
    return "".join(c for c in nfkd if not unicodedata.combining(c))


async def try_tfc_shortcut(question: str) -> Optional[str]:
    """Try to answer TFC question with direct API call.

    Returns formatted markdown response or None (fallback to LLM).
    """
    if not TFC_API_TOKEN:
        logger.debug("TFC shortcuts disabled: TFC_API_TOKEN not set")
        return None

    start = time.monotonic()
    q_lower = _strip_accents(question.lower())

    for pattern, handler in _TFC_SHORTCUTS:
        if pattern.search(q_lower):
            try:
                response = await handler(question=question)
                elapsed_ms = (time.monotonic() - start) * 1000

                if response:
                    source = "TFC API (app.terraform.io)"
                    response += (
                        f"\n\n---\n*Resposta direta via {source} — "
                        f"{elapsed_ms:.0f}ms (sem LLM)*"
                    )
                    logger.info(json.dumps({
                        "event": "tfc_shortcut",
                        "hit": True,
                        "handler": handler.__name__,
                        "latency_ms": round(elapsed_ms),
                        "question": question[:100],
                    }))
                    return response

                return None

            except Exception as e:
                logger.error(f"TFC shortcut handler error: {e}")
                return None

    return None
