"""
SonarQube tools for Claude tool_use — Teck AI Assistant.

Defines tools that Claude can call to query code quality data from SonarQube.
READ-ONLY — no project modifications.

Each tool:
  1. Is defined as an Anthropic tool schema (TOOLS list)
  2. Has an executor function that calls the SonarQube Web API
  3. Returns formatted data for Claude to analyze

Security: Uses SonarQube user token with read-only permissions.
Token stored in AWS SSM Parameter Store (KMS encrypted).

Used by: Code Agent (AG-2)
"""

import os
import logging
from base64 import b64encode

import httpx

logger = logging.getLogger("sonarqube-tools")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
SONARQUBE_URL = os.environ.get(
    "SONARQUBE_URL", "http://sonarqube.observability.local:9000"
)
SONARQUBE_TOKEN = os.environ.get("SONARQUBE_TOKEN", "")

_client: httpx.AsyncClient | None = None


async def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        headers = {"Accept": "application/json"}
        if SONARQUBE_TOKEN:
            # SonarQube token auth: Basic base64(token:)
            cred = b64encode(f"{SONARQUBE_TOKEN}:".encode()).decode()
            headers["Authorization"] = f"Basic {cred}"
        _client = httpx.AsyncClient(
            base_url=SONARQUBE_URL,
            timeout=15.0,
            headers=headers,
        )
    return _client


# ---------------------------------------------------------------------------
# Tool definitions (Anthropic tool_use format)
# ---------------------------------------------------------------------------
TOOLS: list[dict] = [
    {
        "name": "sonarqube_project_status",
        "description": (
            "Verifique o status do Quality Gate de um projeto SonarQube. "
            "Retorna se o projeto PASSED ou FAILED, com detalhes de cada condicao "
            "(cobertura, bugs, vulnerabilidades, code smells, duplicacao). "
            "Use como primeiro passo para avaliar qualidade de codigo."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "project_key": {
                    "type": "string",
                    "description": (
                        "Chave do projeto no SonarQube. "
                        "Exemplos: 'example-api-api', 'frontconsig-api', 'teck-observability-hub'"
                    ),
                },
            },
            "required": ["project_key"],
        },
    },
    {
        "name": "sonarqube_issues",
        "description": (
            "Busque bugs, vulnerabilidades e code smells de um projeto SonarQube. "
            "Retorna lista de issues com severidade, tipo, arquivo e linha. "
            "Use para detalhar problemas apos verificar o Quality Gate."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "project_key": {
                    "type": "string",
                    "description": (
                        "Chave do projeto no SonarQube. "
                        "Exemplos: 'example-api-api', 'frontconsig-api'"
                    ),
                },
                "types": {
                    "type": "string",
                    "description": (
                        "Tipos de issue separados por virgula (default: BUG,VULNERABILITY,CODE_SMELL). "
                        "Opcoes: BUG, VULNERABILITY, CODE_SMELL, SECURITY_HOTSPOT"
                    ),
                },
                "severities": {
                    "type": "string",
                    "description": (
                        "Severidades separadas por virgula (opcional). "
                        "Opcoes: BLOCKER, CRITICAL, MAJOR, MINOR, INFO"
                    ),
                },
                "count": {
                    "type": "integer",
                    "description": "Numero de issues (default: 20, max: 100).",
                },
            },
            "required": ["project_key"],
        },
    },
    {
        "name": "sonarqube_metrics",
        "description": (
            "Obtenha metricas de qualidade de um projeto SonarQube: "
            "cobertura de testes, duplicacao, divida tecnica, complexidade, "
            "linhas de codigo, bugs e vulnerabilidades. "
            "Use para visao quantitativa da saude do codigo."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "project_key": {
                    "type": "string",
                    "description": (
                        "Chave do projeto no SonarQube. "
                        "Exemplos: 'example-api-api', 'frontconsig-api'"
                    ),
                },
                "metrics": {
                    "type": "string",
                    "description": (
                        "Metricas separadas por virgula (opcional). "
                        "Default: bugs,vulnerabilities,code_smells,coverage,"
                        "duplicated_lines_density,ncloc,sqale_index,reliability_rating,"
                        "security_rating,sqale_rating"
                    ),
                },
            },
            "required": ["project_key"],
        },
    },
]


# ---------------------------------------------------------------------------
# Tool executors
# ---------------------------------------------------------------------------
async def execute_tool(name: str, input_data: dict) -> str:
    """Execute a SonarQube tool by name and return result as string for Claude."""
    if not SONARQUBE_TOKEN:
        return "SONARQUBE_TOKEN nao configurado — nao e possivel acessar SonarQube."

    executors = {
        "sonarqube_project_status": _exec_project_status,
        "sonarqube_issues": _exec_issues,
        "sonarqube_metrics": _exec_metrics,
    }
    executor = executors.get(name)
    if not executor:
        return f"Tool '{name}' nao encontrada."
    try:
        return await executor(input_data)
    except httpx.HTTPStatusError as e:
        if e.response.status_code == 404:
            return (
                f"Projeto nao encontrado (404). Verifique o project_key. "
                f"Tente variantes como 'example-api-api' ou 'YOUR_ORG_example-api-api'."
            )
        if e.response.status_code == 403:
            return "Acesso negado (403). Token sem permissao para este projeto."
        logger.error(f"SonarQube API error: {e}")
        return f"Erro SonarQube API ({e.response.status_code}): {e}"
    except Exception as e:
        logger.error(f"Tool {name} error: {e}")
        return f"Erro ao executar {name}: {e}"


async def _exec_project_status(params: dict) -> str:
    """Get Quality Gate status for a project."""
    client = await _get_client()
    project_key = params["project_key"]

    resp = await client.get(
        "/api/qualitygates/project_status",
        params={"projectKey": project_key},
    )
    resp.raise_for_status()
    data = resp.json()

    status = data.get("projectStatus", {})
    gate_status = status.get("status", "UNKNOWN")
    conditions = status.get("conditions", [])

    emoji = "✅" if gate_status == "OK" else "❌"
    formatted = [f"## Quality Gate: {emoji} {gate_status}", f"**Projeto:** {project_key}\n"]

    if conditions:
        formatted.append("| Metrica | Status | Valor | Limite |")
        formatted.append("|---------|--------|-------|--------|")
        for cond in conditions:
            metric = cond.get("metricKey", "?")
            cond_status = "✅" if cond.get("status") == "OK" else "❌"
            value = cond.get("actualValue", "N/A")
            threshold = cond.get("errorThreshold", "N/A")
            formatted.append(f"| {metric} | {cond_status} | {value} | {threshold} |")

    return "\n".join(formatted)


async def _exec_issues(params: dict) -> str:
    """Search issues in a project."""
    client = await _get_client()
    project_key = params["project_key"]
    types = params.get("types", "BUG,VULNERABILITY,CODE_SMELL")
    severities = params.get("severities", "")
    count = min(params.get("count", 20), 100)

    query_params = {
        "componentKeys": project_key,
        "types": types,
        "ps": count,
        "s": "SEVERITY",
        "asc": "false",
    }
    if severities:
        query_params["severities"] = severities

    resp = await client.get("/api/issues/search", params=query_params)
    resp.raise_for_status()
    data = resp.json()

    total = data.get("total", 0)
    issues = data.get("issues", [])

    if not issues:
        return f"Nenhuma issue encontrada em `{project_key}` (tipos: {types})."

    # Count by severity
    severity_count: dict[str, int] = {}
    for issue in issues:
        sev = issue.get("severity", "UNKNOWN")
        severity_count[sev] = severity_count.get(sev, 0) + 1

    formatted = [
        f"## Issues: {total} total em `{project_key}`",
        f"**Tipos:** {types}",
        f"**Por severidade:** {', '.join(f'{k}: {v}' for k, v in sorted(severity_count.items()))}",
        "",
    ]

    severity_emoji = {
        "BLOCKER": "🔴",
        "CRITICAL": "🟠",
        "MAJOR": "🟡",
        "MINOR": "🔵",
        "INFO": "⚪",
    }

    for issue in issues:
        sev = issue.get("severity", "?")
        emoji = severity_emoji.get(sev, "⚪")
        itype = issue.get("type", "?")
        msg = issue.get("message", "")[:80]
        component = issue.get("component", "").split(":")[-1]
        line = issue.get("line", "?")
        formatted.append(f"  {emoji} **{sev}** [{itype}] `{component}:{line}` — {msg}")

    if total > count:
        formatted.append(f"\n*Mostrando {count} de {total} issues.*")

    return "\n".join(formatted)


async def _exec_metrics(params: dict) -> str:
    """Get quality metrics for a project."""
    client = await _get_client()
    project_key = params["project_key"]
    metrics = params.get(
        "metrics",
        "bugs,vulnerabilities,code_smells,coverage,duplicated_lines_density,"
        "ncloc,sqale_index,reliability_rating,security_rating,sqale_rating",
    )

    resp = await client.get(
        "/api/measures/component",
        params={"component": project_key, "metricKeys": metrics},
    )
    resp.raise_for_status()
    data = resp.json()

    component = data.get("component", {})
    measures = component.get("measures", [])

    if not measures:
        return f"Nenhuma metrica encontrada para `{project_key}`. Verifique o project_key."

    # Rating map (SonarQube uses 1.0-5.0 for ratings)
    rating_map = {"1.0": "A", "2.0": "B", "3.0": "C", "4.0": "D", "5.0": "E"}

    # Friendly metric names
    metric_names = {
        "bugs": "Bugs",
        "vulnerabilities": "Vulnerabilidades",
        "code_smells": "Code Smells",
        "coverage": "Cobertura de Testes (%)",
        "duplicated_lines_density": "Duplicacao (%)",
        "ncloc": "Linhas de Codigo",
        "sqale_index": "Divida Tecnica (min)",
        "reliability_rating": "Rating Confiabilidade",
        "security_rating": "Rating Seguranca",
        "sqale_rating": "Rating Manutenibilidade",
    }

    formatted = [f"## Metricas: `{project_key}`\n"]
    formatted.append("| Metrica | Valor |")
    formatted.append("|---------|-------|")

    for m in measures:
        key = m.get("metric", "?")
        value = m.get("value", "N/A")
        name = metric_names.get(key, key)

        # Convert ratings to letters
        if key.endswith("_rating") and value in rating_map:
            value = rating_map[value]

        # Format large numbers
        if key == "ncloc" and value.isdigit():
            value = f"{int(value):,}"
        if key == "sqale_index" and value.isdigit():
            hours = int(value) // 60
            mins = int(value) % 60
            value = f"{hours}h {mins}min" if hours > 0 else f"{mins}min"

        formatted.append(f"| {name} | {value} |")

    return "\n".join(formatted)
