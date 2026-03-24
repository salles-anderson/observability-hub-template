"""
Unified Tool Registry — ALL tools available to the Claude Orchestrator.

Consolidates tools from 7 domains:
  1. Observability: Prometheus, Loki, Tempo, Grafana dashboards
  2. GitHub: repos, PRs, commits, workflows, code search
  3. AWS Infrastructure: ECS, RDS, ElastiCache, VPC, CloudMap, ECR
  4. FinOps: Cost Explorer, forecast, rightsizing, anomalies
  5. Security: GuardDuty, CloudTrail, SSM audit, KMS
  6. Terraform Cloud: workspaces, runs, state, plan
  7. RAG: knowledge base search (Qdrant)

Each tool is defined as an Anthropic tool_use schema + async executor.
Used by: agent.py orchestrator loop.

v11.0: AG-1 — Agentic AI orchestrator (replaces rigid classifier)
v11.1: Cross-account — account_id parameter in AWS/FinOps/Security tools
"""

import logging

from obs_tools import TOOLS as OBS_TOOLS, execute_tool as obs_execute_tool
from github_tools import TOOLS as GITHUB_TOOLS, execute_tool as github_execute_tool
from account_resolver import list_accounts, get_account_name
from aws_shortcuts import (
    set_account_context,
    _ecs_services,
    _ecs_tasks,
    _rds_status,
    _elasticache_status,
    _ecr_images,
    _cloudmap_services,
    _vpc_overview,
    _security_groups,
    _nat_gateways,
    _route53_overview,
    _alarms_active,
    _ecs_deployments,
    _ecs_events,
    _cost_current_month,
    _cost_forecast,
    _cost_by_service,
    _cost_daily_trend,
    _savings_plan_coverage,
    _rightsizing_recommendations,
    _cost_anomalies,
    _account_overview,
    _waf_overview,
    _cloudtrail_recent,
    _cloudtrail_logins,
    _cloudtrail_changes,
)
from security_shortcuts import (
    _guardduty_findings,
    _cloudtrail_anomalies,
    _prioritize_findings,
    _audit_ssm_params,
    _kms_key_status,
)
from tfc_shortcuts import (
    _list_workspaces as _tfc_list_workspaces,
    _get_workspace_runs as _tfc_get_runs,
    _get_state_version as _tfc_get_state,
    _get_plan_output as _tfc_get_plan,
)
from rag_retriever import retrieve as rag_retrieve, build_rag_context

logger = logging.getLogger("tools-registry")

# ---------------------------------------------------------------------------
# Shared property: account_id (injected into AWS/FinOps/Security tools)
# ---------------------------------------------------------------------------
_ACCOUNT_ID_PROP = {
    "account_id": {
        "type": "string",
        "description": (
            "AWS account ID (opcional). Se omitido, usa conta Hub (YOUR_HUB_ACCOUNT_ID). "
            "Use aws_list_accounts para ver as 11 contas disponiveis. "
            "Exemplos: 'YOUR_DEV_ACCOUNT_ID' (Dev), 'YOUR_PRD_ACCOUNT_ID' (Prod)."
        ),
    },
}


def _with_account_id(schema: dict) -> dict:
    """Inject account_id property into a tool's input_schema."""
    props = {**schema.get("properties", {}), **_ACCOUNT_ID_PROP}
    return {**schema, "properties": props}


# ---------------------------------------------------------------------------
# Account Tools
# ---------------------------------------------------------------------------
ACCOUNT_TOOLS: list[dict] = [
    {
        "name": "aws_list_accounts",
        "description": (
            "Liste as 11 contas AWS monitoradas pelo Hub com IDs, nomes e aliases. "
            "Use ANTES de consultar outra conta para obter o account_id correto."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
]

# ---------------------------------------------------------------------------
# AWS Infrastructure Tools
# ---------------------------------------------------------------------------
AWS_TOOLS: list[dict] = [
    {
        "name": "aws_list_ecs_services",
        "description": (
            "Liste todos os servicos ECS rodando no cluster. "
            "Mostra nome, status, desired/running count e saude. "
            "Use para: 'quais servicos estao rodando?', 'status do cluster', "
            "'o que esta rodando na AWS?'"
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "cluster": {
                    "type": "string",
                    "description": (
                        "Nome do cluster ECS. Default: cluster-prod (Observability Hub). "
                        "Alternativas: cluster-dev (Example API/APIs de negocio)."
                    ),
                },
            },
            "required": [],
        },
    },
    {
        "name": "aws_list_ecs_tasks",
        "description": (
            "Liste as tasks ECS rodando no cluster com IPs e status. "
            "Use para: 'quais tasks estao rodando?', 'IPs das tasks'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "cluster": {
                    "type": "string",
                    "description": "Nome do cluster ECS (default: cluster-prod).",
                },
            },
            "required": [],
        },
    },
    {
        "name": "aws_rds_status",
        "description": (
            "Liste instancias RDS com status, engine, tamanho e storage. "
            "Use para: 'bancos de dados', 'RDS', 'instancias de banco'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "aws_elasticache_status",
        "description": (
            "Liste clusters ElastiCache (Redis/Memcached) com status e configuracao. "
            "Use para: 'Redis', 'ElastiCache', 'cache'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "aws_ecr_images",
        "description": (
            "Liste repositorios ECR com imagens e tags recentes. "
            "Use para: 'imagens Docker', 'ECR', 'repositorios de imagem'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "aws_cloudmap_services",
        "description": (
            "Liste servicos registrados no Cloud Map (service discovery). "
            "Use para: 'Cloud Map', 'service discovery', 'DNS interno'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "aws_vpc_overview",
        "description": (
            "Visao geral das VPCs: CIDR, subnets, route tables. "
            "Use para: 'VPCs', 'rede', 'subnets', 'infraestrutura de rede'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "aws_alarms_active",
        "description": (
            "Liste CloudWatch Alarms ativos (estado ALARM). "
            "Use para: 'alarmes', 'CloudWatch alarms', 'o que esta alarmando'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "aws_ecs_deployments",
        "description": (
            "Liste deployments recentes dos servicos ECS. "
            "Use para: 'deploys recentes', 'o que foi deployado', 'rollout'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "cluster": {
                    "type": "string",
                    "description": "Nome do cluster ECS (default: cluster-prod).",
                },
            },
            "required": [],
        },
    },
    {
        "name": "aws_account_overview",
        "description": (
            "Overview completo da conta AWS: ECS services, RDS, ElastiCache, "
            "CloudMap, ECR, VPC, Route 53, NAT Gateways, WAF. "
            "Use quando o usuario pedir uma visao geral da infraestrutura."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "aws_waf_overview",
        "description": (
            "Visao geral do AWS WAF: Web ACLs, rules, metricas. "
            "Use para: 'WAF', 'Web ACL', 'firewall web'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
]

# ---------------------------------------------------------------------------
# FinOps Tools
# ---------------------------------------------------------------------------
FINOPS_TOOLS: list[dict] = [
    {
        "name": "finops_cost_current_month",
        "description": (
            "Custo total do mes atual da conta AWS. "
            "Use para: 'quanto custa', 'gasto do mes', 'custo atual'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "finops_cost_forecast",
        "description": (
            "Previsao de custo para o final do mes (AWS Cost Explorer forecast). "
            "Use para: 'previsao de custo', 'forecast', 'quanto vai gastar'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "finops_cost_by_service",
        "description": (
            "Custo quebrado por servico AWS (ECS, RDS, S3, etc). "
            "Use para: 'custo por servico', 'o que mais gasta', 'breakdown de custo'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "finops_cost_daily_trend",
        "description": (
            "Tendencia de custo diario nos ultimos 14 dias. "
            "Use para: 'tendencia de custo', 'custo diario', 'evolucao de gasto'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "finops_savings_plan",
        "description": (
            "Cobertura e utilizacao de Savings Plans. "
            "Use para: 'savings plan', 'plano de economia', 'cobertura de RI'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "finops_rightsizing",
        "description": (
            "Recomendacoes de rightsizing do AWS Cost Explorer. "
            "Use para: 'rightsizing', 'dimensionamento', 'otimizacao de recursos'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "finops_cost_anomalies",
        "description": (
            "Anomalias de custo detectadas pelo AWS Cost Anomaly Detection. "
            "Use para: 'anomalia de custo', 'gasto inesperado', 'custo anormal'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
]

# ---------------------------------------------------------------------------
# Security Tools
# ---------------------------------------------------------------------------
SECURITY_TOOLS: list[dict] = [
    {
        "name": "security_guardduty_findings",
        "description": (
            "Liste findings ativos do GuardDuty (ameacas detectadas). "
            "Use para: 'GuardDuty', 'ameacas', 'findings de seguranca'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "security_cloudtrail_anomalies",
        "description": (
            "Detecte anomalias no CloudTrail (24h): logins falhos, uso root, mudancas IAM. "
            "Use para: 'anomalias de seguranca', 'login suspeito', 'acesso nao autorizado'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "security_posture",
        "description": (
            "Visao geral da postura de seguranca: GuardDuty + CloudTrail combinados, priorizados. "
            "Use para: 'seguranca', 'postura de seguranca', 'triagem de seguranca'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "security_ssm_audit",
        "description": (
            "Auditoria de parametros SSM SecureString: idade, rotacao, versao. "
            "Use para: 'SSM', 'secrets', 'parametros seguros', 'rotacao de secrets'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "security_kms_keys",
        "description": (
            "Status das chaves KMS: estado, rotacao, manager. "
            "Use para: 'KMS', 'chaves de criptografia', 'key rotation'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "security_cloudtrail_logins",
        "description": (
            "Eventos de login do console AWS (CloudTrail, ultimas 24h). "
            "Use para: 'quem logou', 'logins recentes', 'console login'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "security_cloudtrail_changes",
        "description": (
            "Mudancas de infraestrutura detectadas pelo CloudTrail (24h). "
            "Use para: 'o que mudou', 'mudancas recentes', 'quem alterou'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
]

# ---------------------------------------------------------------------------
# Terraform Cloud Tools
# ---------------------------------------------------------------------------
TFC_TOOLS: list[dict] = [
    {
        "name": "tfc_list_workspaces",
        "description": (
            "Liste todos os workspaces do Terraform Cloud (org YOUR_ORG). "
            "Mostra nome, recursos, versao TF, ultimo update. "
            "Use para: 'workspaces', 'Terraform Cloud', 'status do TFC'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "tfc_get_runs",
        "description": (
            "Liste os runs recentes de um workspace TFC. "
            "Use para: 'runs do workspace', 'ultimo run', 'historico de runs'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "workspace_name": {
                    "type": "string",
                    "description": (
                        "Nome do workspace. Conhecidos: "
                        "teck-observability-hub-prod (hub/infra), "
                        "grafana-dashboards (dashboards/alerts)."
                    ),
                },
            },
            "required": [],
        },
    },
    {
        "name": "tfc_get_state",
        "description": (
            "Informacoes do state atual de um workspace: serial, tamanho, recursos. "
            "Use para: 'state do workspace', 'quantos recursos', 'state version'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "workspace_name": {
                    "type": "string",
                    "description": "Nome do workspace TFC.",
                },
            },
            "required": [],
        },
    },
    {
        "name": "tfc_get_plan",
        "description": (
            "Output do ultimo plan de um workspace: adicoes, alteracoes, destruicoes. "
            "Use para: 'plan do Terraform', 'ultimo plan', 'diff do TFC'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "workspace_name": {
                    "type": "string",
                    "description": "Nome do workspace TFC.",
                },
            },
            "required": [],
        },
    },
]

# ---------------------------------------------------------------------------
# RAG Knowledge Base Tool
# ---------------------------------------------------------------------------
RAG_TOOLS: list[dict] = [
    {
        "name": "rag_search_knowledge",
        "description": (
            "Busque na base de conhecimento interna (Qdrant RAG). "
            "Contem documentacao de arquitetura, troubleshooting, runbooks, "
            "recording rules, configuracoes e processos do Observability Hub. "
            "Use para: perguntas sobre como algo funciona, arquitetura, "
            "processos internos, troubleshooting, runbooks. "
            "NAO use para dados em tempo real (metricas, logs, custos) — "
            "use as tools especificas para dados vivos."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Pergunta ou termos de busca para a base de conhecimento.",
                },
                "top_k": {
                    "type": "integer",
                    "description": "Numero de chunks relevantes (default: 5, max: 10).",
                },
            },
            "required": ["query"],
        },
    },
]


# ---------------------------------------------------------------------------
# Inject account_id into AWS/FinOps/Security tool schemas
# ---------------------------------------------------------------------------
for tool in AWS_TOOLS + FINOPS_TOOLS + SECURITY_TOOLS:
    tool["input_schema"] = _with_account_id(tool["input_schema"])

# ---------------------------------------------------------------------------
# ALL TOOLS — exposed to the orchestrator
# ---------------------------------------------------------------------------
ALL_TOOLS = (
    ACCOUNT_TOOLS
    + OBS_TOOLS
    + GITHUB_TOOLS
    + AWS_TOOLS
    + FINOPS_TOOLS
    + SECURITY_TOOLS
    + TFC_TOOLS
    + RAG_TOOLS
)


# ---------------------------------------------------------------------------
# Unified executor
# ---------------------------------------------------------------------------
_AWS_EXECUTORS = {
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

_FINOPS_EXECUTORS = {
    "finops_cost_current_month": _cost_current_month,
    "finops_cost_forecast": _cost_forecast,
    "finops_cost_by_service": _cost_by_service,
    "finops_cost_daily_trend": _cost_daily_trend,
    "finops_savings_plan": _savings_plan_coverage,
    "finops_rightsizing": _rightsizing_recommendations,
    "finops_cost_anomalies": _cost_anomalies,
}

_SECURITY_EXECUTORS = {
    "security_guardduty_findings": _guardduty_findings,
    "security_cloudtrail_anomalies": _cloudtrail_anomalies,
    "security_posture": _prioritize_findings,
    "security_ssm_audit": _audit_ssm_params,
    "security_kms_keys": _kms_key_status,
    "security_cloudtrail_logins": _cloudtrail_logins,
    "security_cloudtrail_changes": _cloudtrail_changes,
}

_TFC_EXECUTORS = {
    "tfc_list_workspaces": _tfc_list_workspaces,
    "tfc_get_runs": _tfc_get_runs,
    "tfc_get_state": _tfc_get_state,
    "tfc_get_plan": _tfc_get_plan,
}


def _setup_account_context(input_data: dict) -> str | None:
    """Extract account_id from input, set context var, return account label."""
    account_id = input_data.pop("account_id", None)
    set_account_context(account_id)
    if account_id:
        label = get_account_name(account_id)
        logger.info(f"Cross-account: {label} ({account_id})")
        return label
    return None


async def execute_tool(name: str, input_data: dict) -> str:
    """Route tool execution to the correct domain module.

    Returns formatted string result for Claude to analyze.
    """
    # Account listing (no AWS credentials needed)
    if name == "aws_list_accounts":
        return list_accounts()

    # Observability tools (query_prometheus, query_loki, query_tempo, list_dashboards)
    if name.startswith("query_") or name == "list_dashboards":
        return await obs_execute_tool(name, input_data)

    # GitHub tools (github_*)
    if name.startswith("github_"):
        return await github_execute_tool(name, input_data)

    # AWS Infrastructure tools
    if name in _AWS_EXECUTORS:
        executor = _AWS_EXECUTORS[name]
        try:
            acct_label = _setup_account_context(input_data)
            kwargs = {}
            if "cluster" in input_data:
                kwargs["question"] = input_data["cluster"]
            result = await executor(**kwargs)
            suffix = f"\n\n*Conta: {acct_label}*" if acct_label else ""
            return (result or "Sem dados disponiveis para esta consulta.") + suffix
        except Exception as e:
            logger.error(f"AWS tool {name} error: {e}")
            return f"Erro ao executar {name}: {e}"
        finally:
            set_account_context(None)

    # FinOps tools
    if name in _FINOPS_EXECUTORS:
        executor = _FINOPS_EXECUTORS[name]
        try:
            acct_label = _setup_account_context(input_data)
            result = await executor()
            suffix = f"\n\n*Conta: {acct_label}*" if acct_label else ""
            return (result or "Sem dados de custo disponiveis.") + suffix
        except Exception as e:
            logger.error(f"FinOps tool {name} error: {e}")
            return f"Erro ao executar {name}: {e}"
        finally:
            set_account_context(None)

    # Security tools
    if name in _SECURITY_EXECUTORS:
        executor = _SECURITY_EXECUTORS[name]
        try:
            acct_label = _setup_account_context(input_data)
            result = await executor()
            suffix = f"\n\n*Conta: {acct_label}*" if acct_label else ""
            return (result or "Sem dados de seguranca disponiveis.") + suffix
        except Exception as e:
            logger.error(f"Security tool {name} error: {e}")
            return f"Erro ao executar {name}: {e}"
        finally:
            set_account_context(None)

    # Terraform Cloud tools
    if name in _TFC_EXECUTORS:
        executor = _TFC_EXECUTORS[name]
        try:
            kwargs = {}
            ws = input_data.get("workspace_name")
            if ws:
                kwargs["question"] = ws
            result = await executor(**kwargs)
            return result or "Sem dados do Terraform Cloud disponiveis."
        except Exception as e:
            logger.error(f"TFC tool {name} error: {e}")
            return f"Erro ao executar {name}: {e}"

    # RAG Knowledge Base
    if name == "rag_search_knowledge":
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

    return f"Tool '{name}' nao encontrada no registry."
