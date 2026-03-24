"""
MCP Server — Terraform Cloud (AG-5)

Exposes TFC API as MCP tools for the Claude Agent SDK.
Tools: list_workspaces, get_runs, get_state, get_plan, trigger_run

Organization: YOUR_ORG
Transport: SSE on port 8003
"""

import os
import logging
from datetime import datetime, timezone

import httpx
from mcp.server.fastmcp import FastMCP

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logger = logging.getLogger("mcp-tfc")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
TFC_API_TOKEN = os.environ.get("TFC_API_TOKEN", "")
TFC_BASE_URL = "https://app.terraform.io/api/v2"
TFC_ORG = os.environ.get("TFC_ORG", "YOUR_ORG")

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
    client = _get_client()
    resp = await client.get(path)
    resp.raise_for_status()
    return resp.json()


async def _tfc_post(path: str, payload: dict) -> dict:
    client = _get_client()
    resp = await client.post(path, json=payload)
    resp.raise_for_status()
    return resp.json()


def _resolve_workspace(name_or_alias: str) -> str:
    lower = name_or_alias.lower().strip()
    return KNOWN_WORKSPACES.get(lower, lower)


# ---------------------------------------------------------------------------
# MCP Server
# ---------------------------------------------------------------------------
mcp = FastMCP("Terraform Cloud")


@mcp.tool()
async def tfc_list_workspaces() -> str:
    """List all Terraform Cloud workspaces with resource count, TF version, and last update.

    Use this to get an overview of all IaC workspaces in the YOUR_ORG organization.
    """
    if not TFC_API_TOKEN:
        return "Error: TFC_API_TOKEN not configured"

    try:
        resp = await _tfc_get(f"/organizations/{TFC_ORG}/workspaces?page[size]=20")
        workspaces = resp.get("data", [])

        if not workspaces:
            return f"No workspaces found in organization {TFC_ORG}"

        lines = [f"## TFC Workspaces — {TFC_ORG}\n"]
        lines.append("| Workspace | Resources | TF Version | Execution | Updated |")
        lines.append("|-----------|-----------|------------|-----------|---------|")

        for ws in sorted(workspaces, key=lambda w: w["attributes"]["name"]):
            attrs = ws["attributes"]
            name = attrs.get("name", "?")
            resources = attrs.get("resource-count", 0)
            tf_ver = attrs.get("terraform-version", "?")
            exec_mode = attrs.get("execution-mode", "?")
            updated = attrs.get("updated-at", "?")[:10]
            lines.append(f"| {name} | {resources} | {tf_ver} | {exec_mode} | {updated} |")

        lines.append(f"\n**{len(workspaces)} workspace(s)** in org `{TFC_ORG}`")
        return "\n".join(lines)

    except httpx.HTTPStatusError as e:
        return f"TFC API error: {e.response.status_code} — {e.response.text[:200]}"
    except Exception as e:
        return f"Error listing workspaces: {e}"


@mcp.tool()
async def tfc_get_runs(workspace_name: str) -> str:
    """Get the last 10 runs for a Terraform Cloud workspace.

    Args:
        workspace_name: Workspace name or alias (e.g. "hub", "dashboards", "teck-observability-hub-prod")

    Returns run ID, status, commit message, and timestamp for each run.
    """
    if not TFC_API_TOKEN:
        return "Error: TFC_API_TOKEN not configured"

    ws_name = _resolve_workspace(workspace_name)

    try:
        resp = await _tfc_get(f"/organizations/{TFC_ORG}/workspaces/{ws_name}")
        ws_id = resp["data"]["id"]

        runs_resp = await _tfc_get(f"/workspaces/{ws_id}/runs?page[size]=10")
        runs = runs_resp.get("data", [])

        if not runs:
            return f"No runs found for workspace `{ws_name}`"

        lines = [f"## TFC Runs — {ws_name}\n"]
        lines.append("| Run ID | Status | Created | Message |")
        lines.append("|--------|--------|---------|---------|")

        for run in runs[:10]:
            attrs = run["attributes"]
            run_id = run["id"][:16]
            status = attrs.get("status", "?")
            created = attrs.get("created-at", "?")[:16].replace("T", " ")
            message = attrs.get("message", "")[:50]
            is_destroy = " **[DESTROY]**" if attrs.get("is-destroy") else ""

            lines.append(f"| {run_id} | {status}{is_destroy} | {created} | {message} |")

        lines.append(f"\nLast **{len(runs)}** runs for `{ws_name}`")
        return "\n".join(lines)

    except httpx.HTTPStatusError as e:
        if e.response.status_code == 404:
            return f"Workspace `{ws_name}` not found in org `{TFC_ORG}`"
        return f"TFC API error: {e.response.status_code}"
    except Exception as e:
        return f"Error getting runs: {e}"


@mcp.tool()
async def tfc_get_state(workspace_name: str) -> str:
    """Get the current Terraform state version for a workspace.

    Args:
        workspace_name: Workspace name or alias

    Returns state serial, resource count, size, and last update.
    """
    if not TFC_API_TOKEN:
        return "Error: TFC_API_TOKEN not configured"

    ws_name = _resolve_workspace(workspace_name)

    try:
        resp = await _tfc_get(f"/organizations/{TFC_ORG}/workspaces/{ws_name}")
        ws_id = resp["data"]["id"]
        resource_count = resp["data"]["attributes"].get("resource-count", 0)

        state_resp = await _tfc_get(f"/workspaces/{ws_id}/current-state-version")
        state_attrs = state_resp["data"]["attributes"]

        serial = state_attrs.get("serial", "?")
        created = state_attrs.get("created-at", "?")[:16].replace("T", " ")
        size_kb = (state_attrs.get("size", 0) or 0) / 1024

        return (
            f"## TFC State — {ws_name}\n\n"
            f"| Attribute | Value |\n"
            f"|-----------|-------|\n"
            f"| Workspace | {ws_name} |\n"
            f"| Resources | {resource_count} |\n"
            f"| State Serial | #{serial} |\n"
            f"| Size | {size_kb:.1f} KB |\n"
            f"| Last Updated | {created} |\n"
        )

    except Exception as e:
        return f"Error getting state: {e}"


@mcp.tool()
async def tfc_get_plan(workspace_name: str) -> str:
    """Get the plan output summary for the latest run in a workspace.

    Args:
        workspace_name: Workspace name or alias

    Returns additions, changes, destructions, risk level, and commit info.
    """
    if not TFC_API_TOKEN:
        return "Error: TFC_API_TOKEN not configured"

    ws_name = _resolve_workspace(workspace_name)

    try:
        resp = await _tfc_get(f"/organizations/{TFC_ORG}/workspaces/{ws_name}")
        ws_id = resp["data"]["id"]

        runs_resp = await _tfc_get(f"/workspaces/{ws_id}/runs?page[size]=1")
        runs = runs_resp.get("data", [])

        if not runs:
            return f"No runs found for workspace `{ws_name}`"

        run = runs[0]
        attrs = run["attributes"]
        run_id = run["id"]
        status = attrs.get("status", "?")
        message = attrs.get("message", "?")
        has_changes = attrs.get("has-changes", False)

        add = attrs.get("resource-additions", 0) or 0
        change = attrs.get("resource-changes", 0) or 0
        destroy = attrs.get("resource-destructions", 0) or 0

        risk = "LOW"
        if destroy > 0:
            risk = "**HIGH** (destructions detected!)"
        elif change > 5:
            risk = "MEDIUM (many changes)"

        return (
            f"## TFC Plan — {ws_name}\n\n"
            f"| Attribute | Value |\n"
            f"|-----------|-------|\n"
            f"| Run ID | {run_id} |\n"
            f"| Status | {status} |\n"
            f"| Message | {message[:80]} |\n"
            f"| Has Changes | {'Yes' if has_changes else 'No'} |\n"
            f"| Additions | +{add} |\n"
            f"| Changes | ~{change} |\n"
            f"| Destructions | -{destroy} |\n"
            f"| **Risk** | {risk} |\n"
            f"\nPlan: **+{add} ~{change} -{destroy}**"
        )

    except Exception as e:
        return f"Error getting plan: {e}"


@mcp.tool()
async def tfc_trigger_run(workspace_name: str, message: str = "Triggered via AI Assistant") -> str:
    """Trigger a new plan-only run in a Terraform Cloud workspace.

    IMPORTANT: This is a WRITE operation. Only creates a plan, does NOT auto-apply.
    The plan must be manually approved in TFC before applying.

    Args:
        workspace_name: Workspace name or alias
        message: Run message/description
    """
    if not TFC_API_TOKEN:
        return "Error: TFC_API_TOKEN not configured"

    ws_name = _resolve_workspace(workspace_name)

    try:
        resp = await _tfc_get(f"/organizations/{TFC_ORG}/workspaces/{ws_name}")
        ws_id = resp["data"]["id"]

        run_payload = {
            "data": {
                "type": "runs",
                "attributes": {
                    "message": message,
                    "plan-only": True,
                },
                "relationships": {
                    "workspace": {
                        "data": {
                            "type": "workspaces",
                            "id": ws_id,
                        }
                    }
                },
            }
        }

        result = await _tfc_post("/runs", run_payload)
        new_run_id = result["data"]["id"]
        new_status = result["data"]["attributes"]["status"]

        return (
            f"## TFC Run Triggered — {ws_name}\n\n"
            f"| Attribute | Value |\n"
            f"|-----------|-------|\n"
            f"| Run ID | {new_run_id} |\n"
            f"| Status | {new_status} |\n"
            f"| Message | {message} |\n"
            f"| Plan Only | Yes (requires manual approval to apply) |\n"
            f"\nRun created successfully. Check TFC for plan output."
        )

    except Exception as e:
        return f"Error triggering run: {e}"


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import uvicorn
    app = mcp.sse_app()
    uvicorn.run(app, host="0.0.0.0", port=8003)
