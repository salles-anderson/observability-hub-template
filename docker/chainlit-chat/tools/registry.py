"""
Tool Registry — schemas organized by domain.

Extracted from tools_registry.py. Contains ONLY schema definitions,
no executor logic. Executors live in tools/__init__.py.

Schemas are in Anthropic tool_use format.
"""

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
# Observability Tool Schemas (imported from obs_tools at runtime)
# ---------------------------------------------------------------------------
try:
    from obs_tools import TOOLS as OBS_TOOL_SCHEMAS
except ImportError:
    OBS_TOOL_SCHEMAS = []

# ---------------------------------------------------------------------------
# GitHub Tool Schemas (imported from github_tools at runtime)
# ---------------------------------------------------------------------------
try:
    from github_tools import TOOLS as GITHUB_TOOL_SCHEMAS
except ImportError:
    GITHUB_TOOL_SCHEMAS = []

# ---------------------------------------------------------------------------
# SonarQube Tool Schemas (imported from sonarqube_tools at runtime)
# ---------------------------------------------------------------------------
try:
    from sonarqube_tools import TOOLS as SONARQUBE_TOOL_SCHEMAS
except ImportError:
    SONARQUBE_TOOL_SCHEMAS = []

# ---------------------------------------------------------------------------
# AWS Infrastructure Tools
# ---------------------------------------------------------------------------
AWS_TOOL_SCHEMAS: list[dict] = [
    {
        "name": "aws_list_ecs_services",
        "description": (
            "Liste todos os servicos ECS rodando no cluster. "
            "Mostra nome, status, desired/running count e saude."
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
        "name": "aws_list_ecs_tasks",
        "description": "Liste as tasks ECS rodando no cluster com IPs e status.",
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
        "description": "Liste instancias RDS com status, engine, tamanho e storage.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "aws_elasticache_status",
        "description": "Liste clusters ElastiCache (Redis/Memcached) com status.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "aws_ecr_images",
        "description": "Liste repositorios ECR com imagens e tags recentes.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "aws_cloudmap_services",
        "description": "Liste servicos registrados no Cloud Map (service discovery).",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "aws_vpc_overview",
        "description": "Visao geral das VPCs: CIDR, subnets, route tables.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "aws_alarms_active",
        "description": "Liste CloudWatch Alarms ativos (estado ALARM).",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "aws_ecs_deployments",
        "description": "Liste deployments recentes dos servicos ECS.",
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
            "Overview completo da conta AWS: ECS, RDS, ElastiCache, "
            "CloudMap, ECR, VPC, Route 53, NAT, WAF."
        ),
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "aws_waf_overview",
        "description": "Visao geral do AWS WAF: Web ACLs, rules, metricas.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
]

# ---------------------------------------------------------------------------
# FinOps Tools
# ---------------------------------------------------------------------------
FINOPS_TOOL_SCHEMAS: list[dict] = [
    {
        "name": "finops_cost_current_month",
        "description": "Custo total do mes atual da conta AWS.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "finops_cost_forecast",
        "description": "Previsao de custo para o final do mes (Cost Explorer forecast).",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "finops_cost_by_service",
        "description": "Custo quebrado por servico AWS (ECS, RDS, S3, etc).",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "finops_cost_daily_trend",
        "description": "Tendencia de custo diario nos ultimos 14 dias.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "finops_savings_plan",
        "description": "Cobertura e utilizacao de Savings Plans.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "finops_rightsizing",
        "description": "Recomendacoes de rightsizing do AWS Cost Explorer.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "finops_cost_anomalies",
        "description": "Anomalias de custo detectadas pelo AWS Cost Anomaly Detection.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
]

# ---------------------------------------------------------------------------
# Security Tools
# ---------------------------------------------------------------------------
SECURITY_TOOL_SCHEMAS: list[dict] = [
    {
        "name": "security_guardduty_findings",
        "description": "Liste findings ativos do GuardDuty (ameacas detectadas).",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "security_cloudtrail_anomalies",
        "description": "Anomalias no CloudTrail (24h): logins falhos, root, IAM changes.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "security_posture",
        "description": "Postura de seguranca: GuardDuty + CloudTrail priorizados.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "security_ssm_audit",
        "description": "Auditoria de parametros SSM SecureString.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "security_kms_keys",
        "description": "Status das chaves KMS: estado, rotacao, manager.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "security_cloudtrail_logins",
        "description": "Eventos de login do console AWS (CloudTrail, 24h).",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "security_cloudtrail_changes",
        "description": "Mudancas de infraestrutura pelo CloudTrail (24h).",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
]

# ---------------------------------------------------------------------------
# Terraform Cloud Tools
# ---------------------------------------------------------------------------
TFC_TOOL_SCHEMAS: list[dict] = [
    {
        "name": "tfc_list_workspaces",
        "description": "Liste todos os workspaces do Terraform Cloud (org YOUR_ORG).",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "tfc_get_runs",
        "description": "Liste os runs recentes de um workspace TFC.",
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
        "name": "tfc_get_state",
        "description": "State atual de um workspace: serial, tamanho, recursos.",
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
        "description": "Output do ultimo plan: add/change/destroy.",
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
# RAG Knowledge Base
# ---------------------------------------------------------------------------
RAG_TOOL_SCHEMAS: list[dict] = [
    {
        "name": "rag_search_knowledge",
        "description": (
            "Busque na base de conhecimento interna (Qdrant RAG). "
            "Documentacao, troubleshooting, runbooks, arquitetura."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Pergunta ou termos de busca.",
                },
                "top_k": {
                    "type": "integer",
                    "description": "Numero de chunks (default: 5, max: 10).",
                },
            },
            "required": ["query"],
        },
    },
]

# ---------------------------------------------------------------------------
# Inject account_id into AWS/FinOps/Security schemas
# ---------------------------------------------------------------------------
for tool in AWS_TOOL_SCHEMAS + FINOPS_TOOL_SCHEMAS + SECURITY_TOOL_SCHEMAS:
    tool["input_schema"] = _with_account_id(tool["input_schema"])

# ---------------------------------------------------------------------------
# ALL TOOLS — complete list
# ---------------------------------------------------------------------------
ALL_TOOLS = (
    ACCOUNT_TOOLS
    + OBS_TOOL_SCHEMAS
    + GITHUB_TOOL_SCHEMAS
    + SONARQUBE_TOOL_SCHEMAS
    + AWS_TOOL_SCHEMAS
    + FINOPS_TOOL_SCHEMAS
    + SECURITY_TOOL_SCHEMAS
    + TFC_TOOL_SCHEMAS
    + RAG_TOOL_SCHEMAS
)
