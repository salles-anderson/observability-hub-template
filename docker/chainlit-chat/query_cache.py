"""
Direct query shortcuts — Level 1 cache for Chainlit response time.

Bypasses LLM for common observability queries:
1. Pattern-match user question (regex, Portuguese/English)
2. Query Prometheus HTTP API directly (~1-2s internal network)
3. Format response with markdown templates

Result: ~2-3s response vs ~10-12s with Haiku LLM.
"""

import asyncio
import json
import re
import os
import time
import logging
from typing import Optional

import httpx

logger = logging.getLogger("query-cache")

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
    "GRAFANA_URL", "https://grafana.observability.tower.yourorg.com.br",
)
DEFAULT_JOB = "example-api-api"

# ---------------------------------------------------------------------------
# Job resolver — maps common service names to Prometheus job labels
# ---------------------------------------------------------------------------
_JOB_ALIASES: dict[str, str] = {
    "example-api-api": "example-api-api",
    "example-api api": "example-api-api",
    "teck sign": "example-api-api",
    "example-api": "example-api-api",
    "kong-gateway": "kong-gateway",
    "kong gateway": "kong-gateway",
    "kong": "kong-gateway",
    "gateway": "kong-gateway",
    "gestao-cartao-api": "gestao-cartao-api",
    "gestao-cartao": "gestao-cartao-api",
    "gestao cartao": "gestao-cartao-api",
    "gestao": "gestao-cartao-api",
    "cartao": "gestao-cartao-api",
}


def _resolve_job(question: str) -> str:
    """Extract service/job from question, defaults to example-api-api."""
    q = question.lower()
    # Match longest alias first to avoid partial matches
    for alias, job in sorted(_JOB_ALIASES.items(), key=lambda x: -len(x[0])):
        if alias in q:
            return job
    return DEFAULT_JOB


# ---------------------------------------------------------------------------
# Prometheus HTTP client (lazy singleton)
# ---------------------------------------------------------------------------
_client: httpx.AsyncClient | None = None


async def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(timeout=5.0)
    return _client


async def _query_prom(expr: str) -> Optional[list]:
    """Execute instant query against Prometheus HTTP API."""
    try:
        client = await _get_client()
        resp = await client.get(
            f"{PROMETHEUS_URL}/api/v1/query",
            params={"query": expr},
        )
        resp.raise_for_status()
        data = resp.json()
        if data.get("status") == "success":
            return data["data"].get("result", [])
        return None
    except Exception as e:
        logger.error(f"Prometheus query failed [{expr[:80]}]: {e}")
        return None


def _scalar(results: Optional[list]) -> Optional[float]:
    """Extract single scalar value from Prometheus instant query results."""
    if not results:
        return None
    val = results[0].get("value", [None, None])[1]
    if val is None or val == "NaN":
        return None
    return float(val)


# ---------------------------------------------------------------------------
# Loki HTTP client
# ---------------------------------------------------------------------------
async def _query_loki(logql: str, minutes: int = 30, limit: int = 30) -> Optional[list]:
    """Execute Loki query_range and return log entries."""
    try:
        client = await _get_client()
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
        if data.get("status") == "success":
            streams = data.get("data", {}).get("result", [])
            entries = []
            for stream in streams:
                for ts, line in stream.get("values", []):
                    entries.append(line)
            return entries
        return None
    except Exception as e:
        logger.error(f"Loki query failed [{logql[:80]}]: {e}")
        return None


def _resolve_time_range(question: str) -> int:
    """Extract time range in minutes from question. Default 30min."""
    q = question.lower()
    if "1h" in q or "uma hora" in q or "ultima hora" in q or "1 hora" in q:
        return 60
    if "15" in q and "min" in q:
        return 15
    if "5" in q and "min" in q:
        return 5
    if "10" in q and "min" in q:
        return 10
    if "hoje" in q or "24h" in q:
        return 1440
    return 30


# ---------------------------------------------------------------------------
# Response formatting
# ---------------------------------------------------------------------------
NO_DATA = "Sem dados disponiveis no momento. O servico pode estar sem trafego."


def _fmt(
    title: str,
    headers: list[str],
    rows: list[list[str]],
    interpretation: str,
    expr: str | list[str],
) -> str:
    """Build consistent markdown response."""
    hdr = "| " + " | ".join(headers) + " |"
    sep = "|" + "|".join("-------" for _ in headers) + "|"
    body = "\n".join("| " + " | ".join(r) + " |" for r in rows)

    if isinstance(expr, list):
        query_block = "\n".join(expr)
    else:
        query_block = expr

    return "\n".join([
        f"### {title}",
        "",
        hdr,
        sep,
        body,
        "",
        interpretation,
        "",
        f"```promql\n{query_block}\n```",
        "",
        f"[Abrir Grafana Explore →]({GRAFANA_URL}/explore)",
    ])


# ---------------------------------------------------------------------------
# Shortcut handlers
# ---------------------------------------------------------------------------


async def _latency(job: str, percentile: str = "p95", **kwargs) -> Optional[str]:
    expr = f'sli:http_latency_{percentile}:5m{{job="{job}"}}'
    val = _scalar(await _query_prom(expr))
    label = percentile.upper()

    if val is None:
        return _fmt(
            f"Latencia {label} — {job}",
            ["Metrica", "Valor"],
            [[f"{label} (5min)", "Sem dados"]],
            NO_DATA, expr,
        )

    if val < 100:
        interp = "Excelente — abaixo de 100ms."
    elif val < 500:
        interp = "Dentro do SLO (< 500ms)."
    elif val < 1000:
        interp = "**Atencao** — acima de 500ms, proximo do limite SLO."
    else:
        interp = "**ALERTA** — acima de 1s, investigar imediatamente!"

    return _fmt(
        f"Latencia {label} — {job}",
        ["Metrica", "Valor"],
        [[f"{label} (5min)", f"**{val:.1f}ms**"]],
        interp, expr,
    )


async def _error_rate(job: str, **kwargs) -> Optional[str]:
    expr = f'sli:http_error_rate:ratio_rate1h{{job="{job}"}}'
    val = _scalar(await _query_prom(expr))

    if val is None:
        return _fmt(
            f"Taxa de Erro — {job}",
            ["Metrica", "Valor"],
            [["Error rate (1h)", "Sem dados"]],
            NO_DATA, expr,
        )

    pct = val * 100
    if pct < 0.1:
        interp = "Excelente — taxa de erro praticamente zero."
    elif pct < 1.0:
        interp = "Dentro do SLO (< 1%)."
    elif pct < 5.0:
        interp = "**Atencao** — taxa de erro elevada, monitorar."
    else:
        interp = "**ALERTA** — taxa de erro acima de 5%! Investigar imediatamente."

    return _fmt(
        f"Taxa de Erro — {job}",
        ["Metrica", "Valor"],
        [["Error rate (1h)", f"**{pct:.2f}%**"]],
        interp, expr,
    )


async def _availability(job: str, **kwargs) -> Optional[str]:
    expr = f'sli:http_availability:ratio_rate1d{{job="{job}"}}'
    val = _scalar(await _query_prom(expr))

    if val is None:
        return _fmt(
            f"Disponibilidade — {job}",
            ["Metrica", "Valor"],
            [["Disponibilidade (24h)", "Sem dados"]],
            NO_DATA, expr,
        )

    pct = val * 100
    if pct >= 99.9:
        interp = "Excelente — acima de 99.9%."
    elif pct >= 99.5:
        interp = "Dentro do SLO (> 99.5%)."
    elif pct >= 99.0:
        interp = "**Atencao** — abaixo de 99.5%, monitorar."
    else:
        interp = "**ALERTA** — disponibilidade abaixo de 99%! Investigar."

    return _fmt(
        f"Disponibilidade — {job}",
        ["Metrica", "Valor"],
        [["Disponibilidade (24h)", f"**{pct:.2f}%**"]],
        interp, expr,
    )


async def _throughput(job: str, **kwargs) -> Optional[str]:
    expr = f'sli:http_requests:rate5m{{job="{job}"}}'
    val = _scalar(await _query_prom(expr))

    if val is None:
        return _fmt(
            f"Throughput — {job}",
            ["Metrica", "Valor"],
            [["Requests/s (5min)", "Sem dados"]],
            NO_DATA, expr,
        )

    if val > 50:
        interp = "Trafego alto."
    elif val > 10:
        interp = "Trafego normal."
    elif val > 0:
        interp = "Trafego baixo."
    else:
        interp = "Sem trafego no momento."

    return _fmt(
        f"Throughput — {job}",
        ["Metrica", "Valor"],
        [["Requests/s (5min)", f"**{val:.1f} req/s**"]],
        interp, expr,
    )


async def _anomaly_specific(job: str, metric: str, **kwargs) -> Optional[str]:
    metric_map = {
        "error": ("http_error_rate", "Taxa de Erro"),
        "latencia": ("http_latency_p95", "Latencia P95"),
        "throughput": ("http_throughput", "Throughput"),
    }
    prom_key, display = metric_map.get(metric, ("http_error_rate", "Taxa de Erro"))
    expr = f'anomaly:{prom_key}:zscore_1h{{job="{job}"}}'
    val = _scalar(await _query_prom(expr))

    if val is None:
        return _fmt(
            f"Anomalia — {display} — {job}",
            ["Metrica", "Z-Score", "Status"],
            [[display, "Sem dados", "—"]],
            NO_DATA, expr,
        )

    abs_val = abs(val)
    if abs_val < 2.0:
        status = "Normal"
        interp = "Z-Score < 2.0 — comportamento dentro do esperado."
    elif abs_val < 3.0:
        status = "**Atencao**"
        interp = "**Z-Score entre 2.0 e 3.0** — desvio moderado, monitorar."
    else:
        status = "**ANOMALIA**"
        interp = "**Z-Score > 3.0** — anomalia detectada! Investigar imediatamente."

    return _fmt(
        f"Anomalia — {display} — {job}",
        ["Metrica", "Z-Score", "Status"],
        [[display, f"**{val:.2f}**", status]],
        interp, expr,
    )


async def _anomaly_general(job: str, **kwargs) -> Optional[str]:
    metrics = [
        ("anomaly:http_error_rate:zscore_1h", "Taxa de Erro"),
        ("anomaly:http_latency_p95:zscore_1h", "Latencia P95"),
        ("anomaly:http_throughput:zscore_1h", "Throughput"),
    ]
    exprs = [f'{m}{{job="{job}"}}' for m, _ in metrics]
    results = await asyncio.gather(*[_query_prom(e) for e in exprs])

    rows = []
    has_anomaly = False
    all_none = True

    for (_, display), res in zip(metrics, results):
        val = _scalar(res) if res else None
        if val is not None:
            all_none = False
            abs_val = abs(val)
            if abs_val < 2.0:
                status = "Normal"
            elif abs_val < 3.0:
                status = "**Atencao**"
                has_anomaly = True
            else:
                status = "**ANOMALIA**"
                has_anomaly = True
            rows.append([display, f"{val:.2f}", status])
        else:
            rows.append([display, "—", "Sem dados"])

    if all_none:
        return None

    if has_anomaly:
        interp = "**Anomalia(s) detectada(s)!** Investigue com queries detalhadas."
    else:
        interp = "Nenhuma anomalia detectada. Todos os indicadores normais."

    return _fmt(
        f"Verificacao de Anomalias — {job}",
        ["Metrica", "Z-Score", "Status"],
        rows,
        interp, exprs,
    )


async def _alerts(job: str, **kwargs) -> Optional[str]:
    expr = "incident:alerts_firing:count"
    val = _scalar(await _query_prom(expr))
    if val is None:
        val = 0.0

    count = int(val)
    if count == 0:
        interp = "Nenhum alerta ativo no momento."
    elif count <= 2:
        interp = f"{count} alerta(s) ativo(s) — verificar no AlertManager."
    else:
        interp = f"**ATENCAO** — {count} alertas ativos! Verificar urgentemente."

    return _fmt(
        "Alertas Ativos",
        ["Metrica", "Valor"],
        [["Alertas disparando", f"**{count}**"]],
        interp, expr,
    )


async def _error_budget(job: str, **kwargs) -> Optional[str]:
    expr_c = f'slo:error_budget_consumed_tier1:ratio{{job="{job}"}}'
    expr_r = f'slo:error_budget_remaining_tier1:ratio{{job="{job}"}}'
    r_c, r_r = await asyncio.gather(_query_prom(expr_c), _query_prom(expr_r))

    consumed = _scalar(r_c)
    remaining = _scalar(r_r)
    if consumed is None and remaining is None:
        return None

    rows = []
    if consumed is not None:
        rows.append(["Budget consumido", f"**{consumed * 100:.1f}%**"])
    if remaining is not None:
        rows.append(["Budget restante", f"**{remaining * 100:.1f}%**"])

    cpct = (consumed or 0) * 100
    if cpct < 25:
        interp = "Error budget saudavel — boa margem disponivel."
    elif cpct < 50:
        interp = "Error budget em consumo moderado — monitorar."
    elif cpct < 80:
        interp = "**Atencao** — error budget acima de 50%, reduzir deploys arriscados."
    else:
        interp = "**ALERTA** — error budget quase esgotado! Congelar deploys."

    return _fmt(
        f"Error Budget — {job} (Tier 1)",
        ["Metrica", "Valor"],
        rows,
        interp, [expr_c, expr_r],
    )


async def _burn_rate(job: str, **kwargs) -> Optional[str]:
    expr = f'slo:burn_rate_tier1:1h{{job="{job}"}}'
    val = _scalar(await _query_prom(expr))
    if val is None:
        return None

    if val < 1.0:
        interp = f"Normal — burn rate {val:.2f}x nao esta consumindo error budget."
    elif val < 2.0:
        interp = f"**Atencao** — burn rate {val:.2f}x, consumo acelerado."
    else:
        interp = f"**ALERTA** — burn rate {val:.2f}x! Budget sera esgotado rapidamente."

    return _fmt(
        f"Burn Rate — {job} (Tier 1)",
        ["Metrica", "Valor"],
        [["Burn rate (1h)", f"**{val:.2f}x**"]],
        interp, expr,
    )


async def _prom_disk(job: str, **kwargs) -> Optional[str]:
    expr = "anomaly:prometheus_storage:predict_bytes_7d"
    val = _scalar(await _query_prom(expr))
    if val is None:
        return None

    gb = val / (1024**3)
    if gb < 50:
        interp = f"Disco saudavel — previsao de {gb:.1f}GB em 7 dias."
    elif gb < 80:
        interp = f"**Atencao** — previsao de {gb:.1f}GB, monitorar crescimento."
    else:
        interp = f"**ALERTA** — previsao de {gb:.1f}GB! Avaliar retention ou storage."

    return _fmt(
        "Previsao de Disco — Prometheus",
        ["Metrica", "Valor"],
        [["Previsao 7 dias", f"**{gb:.1f} GB**"]],
        interp, expr,
    )


async def _errors_500(job: str, **kwargs) -> Optional[str]:
    expr = f'sli:http_requests_by_status:rate5m{{job="{job}",http_status_code="500"}}'
    val = _scalar(await _query_prom(expr))
    if val is None:
        val = 0.0

    if val == 0:
        interp = "Nenhum erro 500 nos ultimos 5 minutos."
    elif val < 0.1:
        interp = "Poucos erros 500 — pode ser transiente."
    else:
        interp = f"**ALERTA** — {val:.2f} req/s com erro 500! Verificar logs."

    return _fmt(
        f"Erros 500 — {job}",
        ["Metrica", "Valor"],
        [["Rate erros 500 (5min)", f"**{val:.3f} req/s**"]],
        interp, expr,
    )


async def _requests_by_status(job: str, **kwargs) -> Optional[str]:
    expr = f'sli:http_requests_by_status:rate5m{{job="{job}"}}'
    results = await _query_prom(expr)
    if not results:
        return None

    rows = []
    for r in sorted(
        results, key=lambda x: x.get("metric", {}).get("http_status_code", "")
    ):
        code = r.get("metric", {}).get("http_status_code", "?")
        val_str = r.get("value", [None, None])[1]
        if val_str and val_str != "NaN":
            rows.append([f"**{code}**", f"{float(val_str):.2f} req/s"])

    if not rows:
        return None

    return _fmt(
        f"Requests por Status — {job}",
        ["Status", "Rate (5min)"],
        rows,
        "Distribuicao de requests por codigo HTTP.",
        expr,
    )


async def _health_check(job: str, **kwargs) -> Optional[str]:
    """Overview — queries key metrics concurrently."""
    exprs = {
        "p95": f'sli:http_latency_p95:5m{{job="{job}"}}',
        "error": f'sli:http_error_rate:ratio_rate1h{{job="{job}"}}',
        "avail": f'sli:http_availability:ratio_rate1d{{job="{job}"}}',
        "rps": f'sli:http_requests:rate5m{{job="{job}"}}',
        "alerts": "incident:alerts_firing:count",
    }
    results = await asyncio.gather(*[_query_prom(e) for e in exprs.values()])
    vals = dict(zip(exprs.keys(), results))

    rows = []
    all_ok = True

    # Latency P95
    p95 = _scalar(vals["p95"])
    if p95 is not None:
        ok = p95 < 500
        if not ok:
            all_ok = False
        rows.append(["Latencia P95 (5min)", f"{p95:.1f}ms", "OK" if ok else "ALERTA"])
    else:
        rows.append(["Latencia P95 (5min)", "Sem dados", "—"])

    # Error rate
    err = _scalar(vals["error"])
    if err is not None:
        pct = err * 100
        ok = pct < 1.0
        if not ok:
            all_ok = False
        rows.append(["Taxa de Erro (1h)", f"{pct:.2f}%", "OK" if ok else "ALERTA"])
    else:
        rows.append(["Taxa de Erro (1h)", "Sem dados", "—"])

    # Availability
    avail = _scalar(vals["avail"])
    if avail is not None:
        pct = avail * 100
        ok = pct >= 99.5
        if not ok:
            all_ok = False
        rows.append(["Disponibilidade (24h)", f"{pct:.2f}%", "OK" if ok else "ALERTA"])
    else:
        rows.append(["Disponibilidade (24h)", "Sem dados", "—"])

    # Throughput
    rps = _scalar(vals["rps"])
    if rps is not None:
        rows.append(["Throughput (5min)", f"{rps:.1f} req/s", "OK"])
    else:
        rows.append(["Throughput (5min)", "Sem dados", "—"])

    # Alerts
    alert_val = _scalar(vals["alerts"])
    alert_count = int(alert_val) if alert_val else 0
    ok = alert_count == 0
    if not ok:
        all_ok = False
    rows.append(["Alertas ativos", str(alert_count), "OK" if ok else "ALERTA"])

    if all_ok:
        interp = "Todos os indicadores dentro do esperado."
    else:
        interp = "**Atencao** — alguns indicadores fora do esperado."

    return _fmt(
        f"Health Check — {job}",
        ["Metrica", "Valor", "Status"],
        rows,
        interp,
        list(exprs.values()),
    )


# ---------------------------------------------------------------------------
# Log shortcut handlers (Loki)
# ---------------------------------------------------------------------------
_SERVICE_MAP = {
    "example-api-api": "example-api-api",
    "kong-gateway": "kong-gateway",
    "gestao-cartao-api": "gestao-cartao-api",
}


async def _logs_error(job: str, question: str = "") -> Optional[str]:
    """Fetch recent error logs from Loki."""
    svc = _SERVICE_MAP.get(job, job)
    minutes = _resolve_time_range(question)
    logql = f'{{service_name="{svc}"}} | json | level="ERROR"'
    entries = await _query_loki(logql, minutes=minutes, limit=20)

    if entries is None:
        return None

    if not entries:
        return _fmt(
            f"Logs de Erro — {svc} (ultimos {minutes}min)",
            ["Info"],
            [["Nenhum log de erro encontrado"]],
            "Sem erros no periodo. Bom sinal!",
            logql,
        )

    # Format log lines (truncate long lines)
    log_lines = []
    for entry in entries[:15]:
        try:
            parsed = json.loads(entry)
            msg = parsed.get("message", parsed.get("msg", entry))[:150]
            ts = parsed.get("timestamp", parsed.get("time", ""))[:19]
            log_lines.append(f"`{ts}` {msg}")
        except (json.JSONDecodeError, TypeError):
            log_lines.append(f"  {entry[:150]}")

    body = "\n".join(log_lines)
    count = len(entries)

    return "\n".join([
        f"### Logs de Erro — {svc} (ultimos {minutes}min)",
        "",
        f"**{count} log(s) de erro encontrado(s):**",
        "",
        body,
        "",
        f"```logql\n{logql}\n```",
        "",
        f"[Abrir Grafana Explore →]({GRAFANA_URL}/explore)",
    ])


async def _logs_recent(job: str, question: str = "") -> Optional[str]:
    """Fetch recent logs (all levels) from Loki."""
    svc = _SERVICE_MAP.get(job, job)
    minutes = _resolve_time_range(question)
    logql = f'{{service_name="{svc}"}} | json'
    entries = await _query_loki(logql, minutes=minutes, limit=15)

    if entries is None:
        return None

    if not entries:
        return _fmt(
            f"Logs Recentes — {svc} (ultimos {minutes}min)",
            ["Info"],
            [["Nenhum log encontrado"]],
            "Sem logs no periodo.",
            logql,
        )

    log_lines = []
    for entry in entries[:15]:
        try:
            parsed = json.loads(entry)
            level = parsed.get("level", parsed.get("severity", "INFO"))[:5]
            msg = parsed.get("message", parsed.get("msg", entry))[:140]
            ts = parsed.get("timestamp", parsed.get("time", ""))[:19]
            log_lines.append(f"`{ts}` **{level}** {msg}")
        except (json.JSONDecodeError, TypeError):
            log_lines.append(f"  {entry[:150]}")

    body = "\n".join(log_lines)

    return "\n".join([
        f"### Logs Recentes — {svc} (ultimos {minutes}min)",
        "",
        body,
        "",
        f"```logql\n{logql}\n```",
        "",
        f"[Abrir Grafana Explore →]({GRAFANA_URL}/explore)",
    ])


async def _logs_warning(job: str, question: str = "") -> Optional[str]:
    """Fetch warning logs from Loki."""
    svc = _SERVICE_MAP.get(job, job)
    minutes = _resolve_time_range(question)
    logql = f'{{service_name="{svc}"}} | json | level="WARN"'
    entries = await _query_loki(logql, minutes=minutes, limit=20)

    if entries is None:
        return None

    if not entries:
        return _fmt(
            f"Logs de Warning — {svc} (ultimos {minutes}min)",
            ["Info"],
            [["Nenhum warning encontrado"]],
            "Sem warnings no periodo.",
            logql,
        )

    log_lines = []
    for entry in entries[:15]:
        try:
            parsed = json.loads(entry)
            msg = parsed.get("message", parsed.get("msg", entry))[:150]
            ts = parsed.get("timestamp", parsed.get("time", ""))[:19]
            log_lines.append(f"`{ts}` {msg}")
        except (json.JSONDecodeError, TypeError):
            log_lines.append(f"  {entry[:150]}")

    body = "\n".join(log_lines)
    count = len(entries)

    return "\n".join([
        f"### Logs de Warning — {svc} (ultimos {minutes}min)",
        "",
        f"**{count} warning(s) encontrado(s):**",
        "",
        body,
        "",
        f"```logql\n{logql}\n```",
        "",
        f"[Abrir Grafana Explore →]({GRAFANA_URL}/explore)",
    ])


# ---------------------------------------------------------------------------
# Shortcut registry — ordered most specific → most general
# ---------------------------------------------------------------------------
_SHORTCUTS: list[tuple[re.Pattern, callable]] = [
    # Latency — specific percentiles first
    (
        re.compile(r"lat[eê]ncia\s*p99|p99\b|percentil\s*99", re.I),
        lambda j, **kw: _latency(j, "p99"),
    ),
    (
        re.compile(r"lat[eê]ncia\s*p50|p50\b|percentil\s*50|mediana", re.I),
        lambda j, **kw: _latency(j, "p50"),
    ),
    (
        re.compile(
            r"lat[eê]ncia\s*p95|p95\b|percentil\s*95|"
            r"lat[eê]ncia\b(?!.*(p\d|compar|analise|investig))",
            re.I,
        ),
        lambda j, **kw: _latency(j, "p95"),
    ),
    # Error rate
    (
        re.compile(
            r"taxa\s*de\s*erro|error\s*rate|percentual\s*de\s*erro|"
            r"porcentagem\s*de\s*erro",
            re.I,
        ),
        _error_rate,
    ),
    # Availability
    (
        re.compile(r"disponibilidade|availability|uptime|sla\b", re.I),
        _availability,
    ),
    # Throughput
    (
        re.compile(
            r"throughput|requests?\s*por\s*segundo|req/s|rps\b|"
            r"vaz[aã]o|trafego|tr[aá]fego",
            re.I,
        ),
        _throughput,
    ),
    # Anomaly — specific first
    (
        re.compile(r"anomalia.*(erro|error)", re.I),
        lambda j, **kw: _anomaly_specific(j, "error"),
    ),
    (
        re.compile(r"anomalia.*(lat[eê]ncia|latency)", re.I),
        lambda j, **kw: _anomaly_specific(j, "latencia"),
    ),
    (
        re.compile(r"anomalia.*(throughput|trafego|tr[aá]fego|vaz[aã]o)", re.I),
        lambda j, **kw: _anomaly_specific(j, "throughput"),
    ),
    (
        re.compile(
            r"anomalia|anormal|tem\s*anomalia|algo\s*anormal|"
            r"comportamento\s*anormal|anomaly",
            re.I,
        ),
        _anomaly_general,
    ),
    # Alerts
    (
        re.compile(
            r"alerta|alertas?\s*ativo|alertas?\s*disparando|"
            r"quantos?\s*alerta|tem\s*alerta|alerts?\s*firing",
            re.I,
        ),
        _alerts,
    ),
    # Error budget
    (
        re.compile(r"error\s*budget|budget\s*de\s*erro|or[cç]amento", re.I),
        _error_budget,
    ),
    # Burn rate
    (
        re.compile(r"burn\s*rate|taxa\s*de\s*queima", re.I),
        _burn_rate,
    ),
    # Prometheus disk
    (
        re.compile(
            r"disco\s*(do\s*)?prometheus|prometheus\s*storage|"
            r"previs[aã]o\s*de\s*disco|storage\s*prometheus",
            re.I,
        ),
        _prom_disk,
    ),
    # Errors 500
    (
        re.compile(r"erros?\s*500|status\s*500|500\s*error", re.I),
        _errors_500,
    ),
    # Requests by status
    (
        re.compile(
            r"requests?\s*por\s*status|distribui[cç][aã]o\s*(de\s*)?status|"
            r"status\s*codes?|c[oó]digos?\s*http",
            re.I,
        ),
        _requests_by_status,
    ),
    # Logs — error logs (most specific first)
    (
        re.compile(
            r"logs?\s*(de\s*)?erro|error\s*logs?|logs?\s*error|"
            r"erros?\s*nos?\s*logs?|mostre?\s*(os\s*)?logs?\s*(de\s*)?erro",
            re.I,
        ),
        lambda j, **kw: _logs_error(j, question=kw.get("question", "")),
    ),
    # Logs — warning
    (
        re.compile(
            r"logs?\s*(de\s*)?warn|warning\s*logs?|logs?\s*warning|"
            r"avisos?\s*nos?\s*logs?",
            re.I,
        ),
        lambda j, **kw: _logs_warning(j, question=kw.get("question", "")),
    ),
    # Logs — recent (general)
    (
        re.compile(
            r"logs?\s*(recentes?|ultimos?|do\s+example-api|do\s+kong|da\s+api)|"
            r"mostre?\s*(os\s*)?logs?|ver\s*logs?|exib[aei]\s*logs?",
            re.I,
        ),
        lambda j, **kw: _logs_recent(j, question=kw.get("question", "")),
    ),
    # Health check — most general, last
    (
        re.compile(
            r"como\s*est[aá]|status\s*(do|da|geral)|"
            r"health\s*check|sa[uú]de\s*(do|da)|resumo\b|overview|"
            r"vis[aã]o\s*geral|tudo\s*bem|tudo\s*ok",
            re.I,
        ),
        _health_check,
    ),
]


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
async def try_shortcut(question: str) -> Optional[str]:
    """Try to answer with a direct Prometheus shortcut.

    Returns formatted markdown response or None (fallback to LLM).
    Logs structured JSON for Loki metrics.
    """
    start = time.monotonic()
    q_lower = question.lower()
    job = _resolve_job(question)

    for pattern, handler in _SHORTCUTS:
        if pattern.search(q_lower):
            try:
                response = await handler(job, question=question)
                elapsed_ms = (time.monotonic() - start) * 1000

                if response:
                    source = "Loki" if "logql" in response.lower() or "service_name" in response else "Prometheus"
                    response += (
                        f"\n\n---\n*Resposta direta via {source} — "
                        f"{elapsed_ms:.0f}ms (sem LLM)*"
                    )
                    logger.info(json.dumps({
                        "event": "query_shortcut",
                        "hit": True,
                        "shortcut": handler.__name__ if hasattr(handler, "__name__") else "lambda",
                        "job": job,
                        "latency_ms": round(elapsed_ms),
                        "question": question[:100],
                    }))
                    return response

                # Pattern matched but Prometheus returned no usable data
                logger.info(json.dumps({
                    "event": "query_shortcut",
                    "hit": False,
                    "reason": "no_data",
                    "job": job,
                    "latency_ms": round(elapsed_ms),
                    "question": question[:100],
                }))
                return None

            except Exception as e:
                logger.error(f"Shortcut handler error: {e}")
                return None

    # No pattern matched
    elapsed_ms = (time.monotonic() - start) * 1000
    logger.info(json.dumps({
        "event": "query_shortcut",
        "hit": False,
        "reason": "no_match",
        "latency_ms": round(elapsed_ms),
        "question": question[:100],
    }))
    return None
