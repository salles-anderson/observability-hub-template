"""
Observability tools for Claude tool_use — Teck AI Assistant v10.

Defines tools that Claude can call to query real data from Prometheus, Loki
and Tempo. Replaces the MCP Grafana sidecar with direct HTTP queries.

Each tool:
  1. Is defined as an Anthropic tool schema (TOOLS list)
  2. Has an executor function that calls the observability backend
  3. Returns formatted data for Claude to analyze

Used by: agent.py _query_anthropic_with_tools()
"""

import os
import time
import logging
import json

import httpx

logger = logging.getLogger("obs-tools")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
PROMETHEUS_URL = os.environ.get(
    "PROMETHEUS_URL", "http://prometheus.observability.local:9090"
)
LOKI_URL = os.environ.get(
    "LOKI_URL", "http://loki.observability.local:3100"
)
GRAFANA_URL = os.environ.get(
    "GRAFANA_URL", "https://grafana.observability.tower.yourorg.com.br"
)
GRAFANA_TOKEN = os.environ.get("GRAFANA_API_KEY", "")

_client: httpx.AsyncClient | None = None


async def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(timeout=10.0)
    return _client


# ---------------------------------------------------------------------------
# Tool definitions (Anthropic tool_use format)
# ---------------------------------------------------------------------------
TOOLS: list[dict] = [
    {
        "name": "query_prometheus",
        "description": (
            "Execute uma query PromQL no Prometheus e retorne os resultados. "
            "Use para metricas, SLIs, SLOs, anomalias, error budget, burn rate. "
            "Suporta instant queries e range queries."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "expr": {
                    "type": "string",
                    "description": (
                        "Expressao PromQL. Exemplos: "
                        'sli:http_latency_p95:5m{job="example-api-api"}, '
                        'sli:http_error_rate:ratio_rate1h{job="example-api-api"}, '
                        "incident:alerts_firing:count"
                    ),
                },
                "range_minutes": {
                    "type": "integer",
                    "description": (
                        "Se informado, executa range query nos ultimos N minutos "
                        "com step=60s. Se omitido, executa instant query."
                    ),
                },
                "step": {
                    "type": "string",
                    "description": "Step para range query (default: 60s).",
                },
            },
            "required": ["expr"],
        },
    },
    {
        "name": "query_loki",
        "description": (
            "Execute uma query LogQL no Loki e retorne logs. "
            "Use para buscar logs de erro, warning, recentes, ou fazer "
            "agregacoes de logs (rate, count_over_time)."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": (
                        "Expressao LogQL. Exemplos: "
                        '{service_name="example-api-api"} | json | level="ERROR", '
                        '{service_name="kong-gateway"} |= "timeout"'
                    ),
                },
                "minutes": {
                    "type": "integer",
                    "description": "Periodo em minutos para buscar logs (default: 30).",
                },
                "limit": {
                    "type": "integer",
                    "description": "Numero maximo de linhas de log (default: 30, max: 100).",
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "query_tempo",
        "description": (
            "Busque traces no Tempo usando TraceQL. "
            "Use para investigar latencia, erros em spans especificos, "
            "ou correlacionar traces com logs/metricas."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": (
                        "Expressao TraceQL. Exemplos: "
                        '{resource.service.name="example-api-api" && span.http.status_code>=500}, '
                        '{resource.service.name="example-api-api" && duration>1s}'
                    ),
                },
                "limit": {
                    "type": "integer",
                    "description": "Numero maximo de traces (default: 10).",
                },
                "minutes": {
                    "type": "integer",
                    "description": "Periodo em minutos (default: 60).",
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "list_dashboards",
        "description": (
            "Liste os dashboards disponiveis no Grafana. "
            "Use quando o usuario perguntar sobre dashboards, "
            "quiser links ou nao souber qual dashboard usar."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "search": {
                    "type": "string",
                    "description": "Termo de busca para filtrar dashboards (opcional).",
                },
            },
            "required": [],
        },
    },
]


# ---------------------------------------------------------------------------
# Tool executors
# ---------------------------------------------------------------------------
async def execute_tool(name: str, input_data: dict) -> str:
    """Execute a tool by name and return result as string for Claude."""
    executors = {
        "query_prometheus": _exec_prometheus,
        "query_loki": _exec_loki,
        "query_tempo": _exec_tempo,
        "list_dashboards": _exec_list_dashboards,
    }
    executor = executors.get(name)
    if not executor:
        return f"Tool '{name}' nao encontrada."
    try:
        return await executor(input_data)
    except Exception as e:
        logger.error(f"Tool {name} error: {e}")
        return f"Erro ao executar {name}: {e}"


async def _exec_prometheus(params: dict) -> str:
    """Execute PromQL query against Prometheus HTTP API."""
    client = await _get_client()
    expr = params["expr"]
    range_minutes = params.get("range_minutes")

    if range_minutes:
        now = time.time()
        start = now - (range_minutes * 60)
        step = params.get("step", "60s")
        resp = await client.get(
            f"{PROMETHEUS_URL}/api/v1/query_range",
            params={"query": expr, "start": start, "end": now, "step": step},
        )
    else:
        resp = await client.get(
            f"{PROMETHEUS_URL}/api/v1/query",
            params={"query": expr},
        )

    resp.raise_for_status()
    data = resp.json()

    if data.get("status") != "success":
        return f"Prometheus retornou erro: {data.get('error', 'unknown')}"

    results = data["data"].get("result", [])
    if not results:
        return f"Query executada com sucesso, mas sem resultados para: {expr}"

    # Format results compactly for Claude
    formatted = []
    for r in results[:20]:
        metric = r.get("metric", {})
        labels = ", ".join(f'{k}="{v}"' for k, v in metric.items()) if metric else "scalar"

        if "values" in r:
            # Range query — show last 5 values
            values = r["values"][-5:]
            vals_str = ", ".join(f"{v[1]}" for v in values)
            formatted.append(f"  {{{labels}}}: [{vals_str}]")
        else:
            # Instant query
            val = r.get("value", [None, "N/A"])[1]
            formatted.append(f"  {{{labels}}}: {val}")

    return f"Resultados para `{expr}`:\n" + "\n".join(formatted)


async def _exec_loki(params: dict) -> str:
    """Execute LogQL query against Loki HTTP API."""
    client = await _get_client()
    logql = params["query"]
    minutes = min(params.get("minutes", 30), 1440)
    limit = min(params.get("limit", 30), 100)

    now_ns = int(time.time() * 1e9)
    start_ns = now_ns - (minutes * 60 * int(1e9))

    resp = await client.get(
        f"{LOKI_URL}/loki/api/v1/query_range",
        params={
            "query": logql,
            "start": str(start_ns),
            "end": str(now_ns),
            "limit": str(limit),
            "direction": "backward",
        },
    )
    resp.raise_for_status()
    data = resp.json()

    if data.get("status") != "success":
        return f"Loki retornou erro: {data.get('error', 'unknown')}"

    streams = data.get("data", {}).get("result", [])
    if not streams:
        return f"Nenhum log encontrado para: {logql} (ultimos {minutes}min)"

    entries = []
    for stream in streams:
        for ts, line in stream.get("values", []):
            entries.append(line)

    if not entries:
        return f"Nenhum log encontrado para: {logql} (ultimos {minutes}min)"

    # Parse and format log lines compactly
    log_lines = []
    for entry in entries[:limit]:
        try:
            parsed = json.loads(entry)
            level = parsed.get("level", parsed.get("severity", "INFO"))
            msg = parsed.get("message", parsed.get("msg", entry))[:200]
            ts = parsed.get("timestamp", parsed.get("time", ""))[:19]
            log_lines.append(f"[{ts}] {level}: {msg}")
        except (json.JSONDecodeError, TypeError):
            log_lines.append(entry[:200])

    header = f"{len(entries)} log(s) encontrado(s) para `{logql}` (ultimos {minutes}min):"
    return header + "\n" + "\n".join(log_lines)


async def _exec_tempo(params: dict) -> str:
    """Search traces in Tempo via Grafana API (Tempo datasource)."""
    client = await _get_client()
    traceql = params["query"]
    limit = min(params.get("limit", 10), 20)
    minutes = params.get("minutes", 60)

    now = int(time.time())
    start = now - (minutes * 60)

    # Use Grafana datasource proxy for Tempo (requires auth)
    if not GRAFANA_TOKEN:
        return "GRAFANA_API_KEY nao configurada — nao e possivel buscar traces."

    headers = {"Authorization": f"Bearer {GRAFANA_TOKEN}"}
    tempo_ds_uid = "dfaygwy06ufi8f"

    resp = await client.get(
        f"{GRAFANA_URL}/api/datasources/proxy/uid/{tempo_ds_uid}/api/search",
        params={
            "q": traceql,
            "limit": limit,
            "start": start,
            "end": now,
        },
        headers=headers,
    )
    resp.raise_for_status()
    data = resp.json()

    traces = data.get("traces", [])
    if not traces:
        return f"Nenhum trace encontrado para: {traceql} (ultimos {minutes}min)"

    formatted = []
    for t in traces[:limit]:
        trace_id = t.get("traceID", "?")
        root_name = t.get("rootServiceName", "?")
        root_span = t.get("rootTraceName", "?")
        duration_ms = t.get("durationMs", 0)
        formatted.append(
            f"  TraceID: {trace_id} | Service: {root_name} | "
            f"Span: {root_span} | Duration: {duration_ms}ms"
        )

    header = f"{len(traces)} trace(s) encontrado(s) para `{traceql}` (ultimos {minutes}min):"
    return header + "\n" + "\n".join(formatted)


async def _exec_list_dashboards(params: dict) -> str:
    """List Grafana dashboards via API."""
    client = await _get_client()

    if not GRAFANA_TOKEN:
        return "GRAFANA_API_KEY nao configurada."

    headers = {"Authorization": f"Bearer {GRAFANA_TOKEN}"}
    query_params = {"type": "dash-db", "limit": 50}
    search = params.get("search")
    if search:
        query_params["query"] = search

    resp = await client.get(
        f"{GRAFANA_URL}/api/search",
        params=query_params,
        headers=headers,
    )
    resp.raise_for_status()
    dashboards = resp.json()

    if not dashboards:
        return "Nenhum dashboard encontrado."

    formatted = []
    for d in dashboards:
        title = d.get("title", "?")
        uid = d.get("uid", "?")
        url = f"{GRAFANA_URL}{d.get('url', '')}"
        folder = d.get("folderTitle", "General")
        formatted.append(f"  [{title}]({url}) (folder: {folder}, uid: {uid})")

    return f"{len(dashboards)} dashboard(s):\n" + "\n".join(formatted)
