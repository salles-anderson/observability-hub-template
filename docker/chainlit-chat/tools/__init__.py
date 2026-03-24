"""
Tools package — tool schemas and executors organized by domain.

Provides:
  - get_tools_for_agent(agent_name) → subset of tool schemas
  - execute_tool(name, input_data) → formatted string result
  - ALL_TOOLS → full list (for AG-1 compatibility)

Tool schemas use Anthropic tool_use format.
Executors are async functions that return formatted strings.
"""

from __future__ import annotations

import logging

from core.account_resolver import list_accounts, get_account_name
from tools.registry import (
    ACCOUNT_TOOLS,
    OBS_TOOL_SCHEMAS,
    GITHUB_TOOL_SCHEMAS,
    SONARQUBE_TOOL_SCHEMAS,
    AWS_TOOL_SCHEMAS,
    FINOPS_TOOL_SCHEMAS,
    SECURITY_TOOL_SCHEMAS,
    TFC_TOOL_SCHEMAS,
    RAG_TOOL_SCHEMAS,
    ALL_TOOLS,
)

logger = logging.getLogger("tools")

# ---------------------------------------------------------------------------
# Tool subsets per agent
# ---------------------------------------------------------------------------
_AGENT_TOOL_MAP: dict[str, list[str]] = {
    "observability": [
        "query_prometheus", "query_loki", "query_tempo", "list_dashboards",
        "rag_search_knowledge",
    ],
    "infrastructure": [
        "aws_list_accounts", "aws_list_ecs_services", "aws_list_ecs_tasks",
        "aws_rds_status", "aws_elasticache_status", "aws_ecr_images",
        "aws_cloudmap_services", "aws_vpc_overview", "aws_alarms_active",
        "aws_ecs_deployments", "aws_account_overview", "aws_waf_overview",
        "rag_search_knowledge",
    ],
    "finops": [
        "aws_list_accounts", "finops_cost_current_month", "finops_cost_forecast",
        "finops_cost_by_service", "finops_cost_daily_trend",
        "finops_savings_plan", "finops_rightsizing", "finops_cost_anomalies",
        "rag_search_knowledge",
    ],
    "security": [
        "aws_list_accounts", "security_guardduty_findings",
        "security_cloudtrail_anomalies", "security_posture",
        "security_ssm_audit", "security_kms_keys",
        "security_cloudtrail_logins", "security_cloudtrail_changes",
        "rag_search_knowledge",
    ],
    "cicd": [
        "tfc_list_workspaces", "tfc_get_runs", "tfc_get_state", "tfc_get_plan",
        "rag_search_knowledge",
    ],
    "code": [
        "github_list_repos", "github_search_prs",
        "github_list_contents", "github_get_file", "github_search_code",
        "github_get_repo_info", "github_get_commits", "github_list_prs",
        "github_get_pr_diff", "github_get_workflow_runs",
        "sonarqube_project_status", "sonarqube_issues", "sonarqube_metrics",
        "rag_search_knowledge",
    ],
    "correlator": [],  # Correlator has no tools — analyzes agent outputs
}


def get_tools_for_agent(agent_name: str) -> list[dict]:
    """Return curated tool schemas for a specific agent."""
    tool_names = _AGENT_TOOL_MAP.get(agent_name, [])
    if not tool_names:
        return []

    all_tools_map = {t["name"]: t for t in ALL_TOOLS}
    return [all_tools_map[name] for name in tool_names if name in all_tools_map]


# ---------------------------------------------------------------------------
# Unified executor — delegates to domain modules
# ---------------------------------------------------------------------------
async def execute_tool(name: str, input_data: dict) -> str:
    """Route tool execution to the correct domain handler.

    Imports are lazy to avoid circular dependencies and reduce startup time.
    """
    # Account listing
    if name == "aws_list_accounts":
        return list_accounts()

    # Observability
    if name.startswith("query_") or name == "list_dashboards":
        from obs_tools import execute_tool as obs_execute
        return await obs_execute(name, input_data)

    # GitHub
    if name.startswith("github_"):
        from github_tools import execute_tool as github_execute
        return await github_execute(name, input_data)

    # SonarQube
    if name.startswith("sonarqube_"):
        from sonarqube_tools import execute_tool as sonarqube_execute
        return await sonarqube_execute(name, input_data)

    # AWS Infrastructure
    if name.startswith("aws_"):
        return await _execute_aws(name, input_data)

    # FinOps
    if name.startswith("finops_"):
        return await _execute_finops(name, input_data)

    # Security
    if name.startswith("security_"):
        return await _execute_security(name, input_data)

    # Terraform Cloud
    if name.startswith("tfc_"):
        return await _execute_tfc(name, input_data)

    # RAG
    if name == "rag_search_knowledge":
        return await _execute_rag(input_data)

    return f"Tool '{name}' nao encontrada no registry."


# ---------------------------------------------------------------------------
# Domain executors (extracted from tools_registry.py)
# ---------------------------------------------------------------------------
async def _execute_aws(name: str, input_data: dict) -> str:
    from aws_shortcuts import (
        set_account_context,
        _ecs_services, _ecs_tasks, _rds_status, _elasticache_status,
        _ecr_images, _cloudmap_services, _vpc_overview, _security_groups,
        _nat_gateways, _route53_overview, _alarms_active,
        _ecs_deployments, _account_overview, _waf_overview, _ecs_events,
    )

    executors = {
        "aws_list_ecs_services": _ecs_services,
        "aws_list_ecs_tasks": _ecs_tasks,
        "aws_rds_status": _rds_status,
        "aws_elasticache_status": _elasticache_status,
        "aws_ecr_images": _ecr_images,
        "aws_cloudmap_services": _cloudmap_services,
        "aws_vpc_overview": _vpc_overview,
        "aws_alarms_active": _alarms_active,
        "aws_ecs_deployments": _ecs_deployments,
        "aws_account_overview": _account_overview,
        "aws_waf_overview": _waf_overview,
        "aws_security_groups": _security_groups,
        "aws_nat_gateways": _nat_gateways,
        "aws_route53_overview": _route53_overview,
    }

    executor = executors.get(name)
    if not executor:
        return f"AWS tool '{name}' nao encontrada."

    try:
        acct_label = _setup_account(input_data, set_account_context)
        kwargs = {}
        if "cluster" in input_data:
            kwargs["question"] = input_data["cluster"]
        result = await executor(**kwargs)
        suffix = f"\n\n*Conta: {acct_label}*" if acct_label else ""
        return (result or "Sem dados disponiveis.") + suffix
    except Exception as e:
        logger.error(f"AWS tool {name} error: {e}")
        return f"Erro ao executar {name}: {e}"
    finally:
        set_account_context(None)


async def _execute_finops(name: str, input_data: dict) -> str:
    from aws_shortcuts import (
        set_account_context,
        _cost_current_month, _cost_forecast, _cost_by_service,
        _cost_daily_trend, _savings_plan_coverage,
        _rightsizing_recommendations, _cost_anomalies,
    )

    executors = {
        "finops_cost_current_month": _cost_current_month,
        "finops_cost_forecast": _cost_forecast,
        "finops_cost_by_service": _cost_by_service,
        "finops_cost_daily_trend": _cost_daily_trend,
        "finops_savings_plan": _savings_plan_coverage,
        "finops_rightsizing": _rightsizing_recommendations,
        "finops_cost_anomalies": _cost_anomalies,
    }

    executor = executors.get(name)
    if not executor:
        return f"FinOps tool '{name}' nao encontrada."

    try:
        acct_label = _setup_account(input_data, set_account_context)
        result = await executor()
        suffix = f"\n\n*Conta: {acct_label}*" if acct_label else ""
        return (result or "Sem dados de custo.") + suffix
    except Exception as e:
        logger.error(f"FinOps tool {name} error: {e}")
        return f"Erro ao executar {name}: {e}"
    finally:
        set_account_context(None)


async def _execute_security(name: str, input_data: dict) -> str:
    from aws_shortcuts import set_account_context
    from security_shortcuts import (
        _guardduty_findings, _cloudtrail_anomalies, _prioritize_findings,
        _audit_ssm_params, _kms_key_status,
    )
    from aws_shortcuts import _cloudtrail_logins, _cloudtrail_changes

    executors = {
        "security_guardduty_findings": _guardduty_findings,
        "security_cloudtrail_anomalies": _cloudtrail_anomalies,
        "security_posture": _prioritize_findings,
        "security_ssm_audit": _audit_ssm_params,
        "security_kms_keys": _kms_key_status,
        "security_cloudtrail_logins": _cloudtrail_logins,
        "security_cloudtrail_changes": _cloudtrail_changes,
    }

    executor = executors.get(name)
    if not executor:
        return f"Security tool '{name}' nao encontrada."

    try:
        acct_label = _setup_account(input_data, set_account_context)
        result = await executor()
        suffix = f"\n\n*Conta: {acct_label}*" if acct_label else ""
        return (result or "Sem dados de seguranca.") + suffix
    except Exception as e:
        logger.error(f"Security tool {name} error: {e}")
        return f"Erro ao executar {name}: {e}"
    finally:
        set_account_context(None)


async def _execute_tfc(name: str, input_data: dict) -> str:
    from tfc_shortcuts import (
        _list_workspaces, _get_workspace_runs,
        _get_state_version, _get_plan_output,
    )

    executors = {
        "tfc_list_workspaces": _list_workspaces,
        "tfc_get_runs": _get_workspace_runs,
        "tfc_get_state": _get_state_version,
        "tfc_get_plan": _get_plan_output,
    }

    executor = executors.get(name)
    if not executor:
        return f"TFC tool '{name}' nao encontrada."

    try:
        kwargs = {}
        ws = input_data.get("workspace_name")
        if ws:
            kwargs["question"] = ws
        result = await executor(**kwargs)
        return result or "Sem dados do Terraform Cloud."
    except Exception as e:
        logger.error(f"TFC tool {name} error: {e}")
        return f"Erro ao executar {name}: {e}"


async def _execute_rag(input_data: dict) -> str:
    from rag_retriever import retrieve as rag_retrieve, build_rag_context

    try:
        query = input_data.get("query", "")
        top_k = min(input_data.get("top_k", 5), 10)
        chunks = await rag_retrieve(query, top_k=top_k)
        if not chunks:
            return "Nenhum resultado encontrado na base de conhecimento."
        return build_rag_context(chunks)
    except Exception as e:
        logger.error(f"RAG tool error: {e}")
        return f"Erro ao buscar na base de conhecimento: {e}"


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
def _setup_account(input_data: dict, set_context_fn) -> str | None:
    """Extract account_id, set context, return label."""
    account_id = input_data.pop("account_id", None)
    set_context_fn(account_id)
    if account_id:
        label = get_account_name(account_id)
        logger.info(f"Cross-account: {label} ({account_id})")
        return label
    return None
