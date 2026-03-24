"""
Router — LLM classifier via tool_use (7 call_agent tools).

Uses Gemini 2.5 Pro (via LiteLLM) with max_tokens=256 to classify
which specialized agents should handle a query. Can dispatch 1-3
agents in parallel.

If no agent tool is called, falls back to AG-1 orchestrator path.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os

import openai
import httpx

logger = logging.getLogger("router")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ROUTER_MODEL = os.environ.get("ROUTER_MODEL", "gemini/gemini-2.0-flash")
ROUTER_TIMEOUT = int(os.environ.get("ROUTER_TIMEOUT", "15"))
LITELLM_BASE_URL = os.environ.get("LITELLM_BASE_URL", "http://litellm.observability.local:4000")
LITELLM_API_KEY = os.environ.get("LITELLM_API_KEY", "sk-litellm-master-key")

_client: openai.AsyncOpenAI | None = None


def _get_client() -> openai.AsyncOpenAI:
    global _client
    if _client is None:
        _client = openai.AsyncOpenAI(
            base_url=LITELLM_BASE_URL,
            api_key=LITELLM_API_KEY,
            timeout=httpx.Timeout(ROUTER_TIMEOUT, connect=5.0),
        )
    return _client


# ---------------------------------------------------------------------------
# Router tools — 7 call_agent functions
# ---------------------------------------------------------------------------
ROUTER_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "call_observability_agent",
            "description": (
                "Metricas (Prometheus/PromQL), logs (Loki/LogQL), traces (Tempo/TraceQL), "
                "dashboards Grafana, latencia, error rate, SLOs, anomalias de performance."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "sub_question": {
                        "type": "string",
                        "description": "Pergunta especifica para o agente de observabilidade.",
                    },
                },
                "required": ["sub_question"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "call_infrastructure_agent",
            "description": (
                "ECS services/tasks, RDS, ElastiCache, VPC, CloudMap, ECR, WAF, "
                "Route 53, NAT Gateways, Security Groups, account overview."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "sub_question": {
                        "type": "string",
                        "description": "Pergunta especifica para o agente de infraestrutura.",
                    },
                },
                "required": ["sub_question"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "call_finops_agent",
            "description": (
                "Custos AWS (Cost Explorer), forecast, custo por servico, tendencia diaria, "
                "Savings Plans, rightsizing, anomalias de custo, otimizacao."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "sub_question": {
                        "type": "string",
                        "description": "Pergunta especifica para o agente de FinOps.",
                    },
                },
                "required": ["sub_question"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "call_security_agent",
            "description": (
                "GuardDuty findings, CloudTrail anomalias/logins/mudancas, "
                "SSM audit, KMS keys, postura de seguranca."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "sub_question": {
                        "type": "string",
                        "description": "Pergunta especifica para o agente de seguranca.",
                    },
                },
                "required": ["sub_question"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "call_cicd_agent",
            "description": (
                "Terraform Cloud: workspaces, runs, state, plan output. "
                "CI/CD pipelines e IaC."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "sub_question": {
                        "type": "string",
                        "description": "Pergunta especifica para o agente de CI/CD.",
                    },
                },
                "required": ["sub_question"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "call_code_agent",
            "description": (
                "GitHub: repos, PRs, commits, code search, workflows, "
                "diffs, code review."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "sub_question": {
                        "type": "string",
                        "description": "Pergunta especifica para o agente de codigo.",
                    },
                },
                "required": ["sub_question"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "call_correlator_agent",
            "description": (
                "Correlacionar e sintetizar dados de MULTIPLOS dominios. "
                "Use quando a pergunta envolve 2+ areas (ex: latencia + custo, "
                "seguranca + infra, deploy + metricas)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "sub_question": {
                        "type": "string",
                        "description": "Pergunta de correlacao multi-dominio.",
                    },
                },
                "required": ["sub_question"],
            },
        },
    },
]

# ---------------------------------------------------------------------------
# Router system prompt
# ---------------------------------------------------------------------------
ROUTER_SYSTEM_PROMPT = """Voce e o Router do Observability Hub da Your Company.
Sua funcao e classificar perguntas e despachar para os agentes especializados corretos.

## Regras de Routing

1. Analise a pergunta e chame **1 a 3 agentes** via tool_use
2. Reformule a sub_question de forma **detalhada e especifica** para cada agente
3. SEMPRE chame o **correlator** quando 2+ agentes sao despachados
4. NAO responda a pergunta — apenas classifique e despache
5. Na duvida, prefira MAIS agentes que menos — a analise profunda e melhor que rasa

## Prioridades de Routing (ordem de peso)

### SEMPRE incluir Observability Agent quando:
- Mencionar: latencia, erro, log, metrica, trace, SLO, performance, status de servico
- Mencionar nome de projeto/servico: example-api, kong, cartao, solis, api
- Perguntar "como esta", "status de", "saude de" qualquer servico

### SEMPRE incluir Infrastructure Agent quando:
- Mencionar: ECS, tasks, RDS, Redis, VPC, deploy, health check, scaling, container
- Perguntar sobre estado de servicos AWS
- Perguntar sobre problemas de infraestrutura

### SEMPRE incluir Code Agent quando:
- Mencionar: PR, deploy, commit, pipeline, codigo, github, qualidade, sonarqube
- Investigar causa de problemas (pode ser regressao de codigo)
- Perguntar sobre mudancas recentes

### SEMPRE incluir CI/CD Agent quando:
- Mencionar: terraform, workspace, plan, state, drift, infra-as-code, apply, TFC
- Erros de Terraform: "Error:", "ClientException", "secret.valueFrom", "RegisterTaskDefinition"
- Logs de erro com "StatusCode: 4xx/5xx", "operation error", ".tf line"
- Perguntar sobre deploy de infraestrutura, IaC, task definition

### Incluir FinOps quando: custo, gasto, forecast, economia, budget, billing
### Incluir Security quando: guardduty, cloudtrail, seguranca, login, acesso, threat, vulnerabilidade

## Regra de Ouro: Investigacoes Profundas

Para perguntas que pedem analise, investigacao ou diagnostico, SEMPRE despache **3 agentes + correlator**:
- observability (metricas + logs + traces)
- infrastructure (estado AWS)
- code (deploys recentes que podem ser causa)
- correlator (sintetizar tudo)

Exemplos de investigacao profunda:
- "Como esta o example-api?" → obs + infra + code + correlator
- "Por que esta lento?" → obs + infra + code + correlator
- "Status dos servicos e erros" → obs + infra + correlator
- "O que causou o alerta?" → obs + infra + code + correlator
- "Tem algum problema?" → obs + infra + security + correlator

## Regra Critica: Logs de Erro Colados

Quando o usuario cola um log de erro, stack trace ou mensagem de erro:
1. Identifique o DOMINIO do erro (Terraform, ECS, RDS, aplicacao, etc.)
2. Despache o agente do dominio correto — NAO o Observability Agent
3. Se o erro menciona Terraform/IaC → CI/CD Agent
4. Se o erro menciona ECS/RDS/AWS API → Infrastructure Agent
5. Se o erro menciona codigo/exception da app → Code Agent + Observability Agent
6. Para erros ambiguos, despache 2-3 agentes + correlator

Exemplos de erro → routing correto:
- "Error: creating ECS Task Definition... secret.valueFrom" → cicd + infra + correlator
- "connection pool exhausted" → obs + infra + code + correlator
- "SonarQube quality gate failed" → code
- "GuardDuty finding HIGH" → security + infra + correlator
- "terraform plan failed" → cicd
- "OOMKilled" → infra + obs + correlator

## IMPORTANTE: Precisao Acima de Tudo
- NAO despache Observability Agent para erros de Terraform/IaC
- NAO despache Observability Agent quando o erro nao e de metricas/logs/traces
- Observability Agent e para MONITORAMENTO (Prometheus/Loki/Tempo), nao para erros de deploy ou IaC
- Cada agente tem ferramentas ESPECIFICAS — envie a query pro agente que TEM a ferramenta certa

## Exemplos Simples (1 agente)
- "Latencia p95 do example-api" → call_observability_agent
- "Quais servicos ECS rodando?" → call_infrastructure_agent
- "Quanto custa a conta Dev?" → call_finops_agent
- "PRs abertos do example-api" → call_code_agent
- "Findings GuardDuty" → call_security_agent
- "Ultimo run Terraform" → call_cicd_agent

## Exemplos Complexos (2-3 agentes + correlator)
- "Status completo do example-api-dev" → obs + infra + code + correlator
- "Por que o example-api esta lento e caro?" → obs + finops + code + correlator
- "Houve alguma mudanca que causou erros?" → obs + code + infra + correlator
- "Postura de seguranca e infra" → security + infra + correlator
- "Review do ultimo deploy" → code + obs + infra + correlator
- "Erro no terraform apply: secret.valueFrom null" → cicd + infra + correlator
- "ECS task definition falhou" → cicd + infra + correlator
- "Explique esse erro do TFC" + log colado → cicd + correlator
- "Em qual commit foi corrigido X?" → code

## Contexto Multi-Account
Contas: Dev (YOUR_DEV_ACCOUNT_ID), Prod (YOUR_PRD_ACCOUNT_ID), Capital (YOUR_CAPITAL_ACCOUNT_ID), Kong (YOUR_INFRA_ACCOUNT_ID),
Hub (YOUR_HUB_ACCOUNT_ID), Homolog (YOUR_HML_ACCOUNT_ID), HubDigital (131602690665), Admin (195835301200).
Se o usuario mencionar uma conta, inclua account_id ou nome na sub_question.

## Sub-Questions: Como Formular

NAO copie a pergunta original. REFORMULE de forma especifica para cada agente:
- Original: "Como esta o example-api?"
- Obs Agent: "Verifique latencia P95, error rate, throughput e logs de erro recentes do example-api-api nas ultimas 4h"
- Infra Agent: "Verifique status das tasks ECS, health checks, RDS connections e Redis do example-api na conta Dev"
- Code Agent: "Liste os ultimos 5 deploys/PRs merged do repositorio example-api-api e verifique quality gate no SonarQube"
"""


# ---------------------------------------------------------------------------
# Route dataclass
# ---------------------------------------------------------------------------
class RouteDecision:
    """Result of routing: list of (agent_name, sub_question) tuples."""

    def __init__(self, routes: list[tuple[str, str]]):
        self.routes = routes  # [(agent_name, sub_question), ...]

    @property
    def is_empty(self) -> bool:
        return len(self.routes) == 0

    @property
    def agent_names(self) -> list[str]:
        return [name for name, _ in self.routes]

    def __repr__(self) -> str:
        return f"RouteDecision({self.routes})"


# ---------------------------------------------------------------------------
# Agent name mapping
# ---------------------------------------------------------------------------
_TOOL_TO_AGENT = {
    "call_observability_agent": "observability",
    "call_infrastructure_agent": "infrastructure",
    "call_finops_agent": "finops",
    "call_security_agent": "security",
    "call_cicd_agent": "cicd",
    "call_code_agent": "code",
    "call_correlator_agent": "correlator",
}


# ---------------------------------------------------------------------------
# Main classify function
# ---------------------------------------------------------------------------
async def classify(question: str) -> RouteDecision:
    """Classify a question into 1-3 agent routes.

    Uses Gemini 2.5 Pro via LiteLLM with tool_use.
    Returns RouteDecision with agent_name + sub_question pairs.
    Falls back to empty RouteDecision on error (triggers AG-1 fallback).
    """
    client = _get_client()

    try:
        response = await asyncio.wait_for(
            client.chat.completions.create(
                model=ROUTER_MODEL,
                messages=[
                    {"role": "system", "content": ROUTER_SYSTEM_PROMPT},
                    {"role": "user", "content": question},
                ],
                tools=ROUTER_TOOLS,
                max_tokens=1024,
            ),
            timeout=ROUTER_TIMEOUT,
        )
    except (asyncio.TimeoutError, Exception) as e:
        logger.warning(f"Router error, falling back to AG-1: {e}")
        return RouteDecision([])

    if not response.choices:
        logger.warning("Router: empty choices from LLM, falling back to AG-1")
        return RouteDecision([])

    choice = response.choices[0]
    if not choice.message.tool_calls:
        logger.info("Router: no agent tools called, falling back to AG-1")
        return RouteDecision([])

    routes = []
    for tc in choice.message.tool_calls:
        agent_name = _TOOL_TO_AGENT.get(tc.function.name)
        if not agent_name:
            continue
        try:
            args = json.loads(tc.function.arguments) if tc.function.arguments else {}
        except json.JSONDecodeError:
            args = {}

        sub_question = args.get("sub_question", question)
        routes.append((agent_name, sub_question))
        logger.info(f"Router: {agent_name} ← {sub_question[:80]}")

    return RouteDecision(routes)
