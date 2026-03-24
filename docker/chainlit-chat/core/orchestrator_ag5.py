"""
Orchestrator AG-5 — Claude + MCP (no router, no multi-agent)

Single Claude Sonnet 4.6 with direct access to all MCP tools.
Claude handles routing, tool selection, and synthesis natively.

Flow:
  1. Input guardrails
  2. Semantic cache lookup (2s timeout)
  3. Claude Sonnet + MCP tools (ReAct loop, streaming)
  4. Output guardrails
  5. Semantic cache store (fire-and-forget)
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from typing import AsyncGenerator

import anthropic
import httpx

from core.mcp_client import get_mcp_manager
from core.guardrails import (
    validate_input,
    scan_output,
    check_role_access,
    get_denied_message,
    InputGuardError,
    DEFAULT_ROLE,
)

logger = logging.getLogger("orchestrator-ag5")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
MODEL = os.environ.get("AGENT_MODEL_AG5", "claude-sonnet-4-6")
MAX_TURNS = int(os.environ.get("AG5_MAX_TURNS", "15"))
TIMEOUT = int(os.environ.get("AG5_TIMEOUT", "120"))

_client: anthropic.AsyncAnthropic | None = None


def _get_client() -> anthropic.AsyncAnthropic:
    global _client
    if _client is None:
        _client = anthropic.AsyncAnthropic(
            api_key=ANTHROPIC_API_KEY,
            timeout=httpx.Timeout(TIMEOUT, connect=10.0),
        )
    return _client


# ---------------------------------------------------------------------------
# System prompt
# ---------------------------------------------------------------------------
SYSTEM_PROMPT_AG5 = """Voce e o Assistente AI da Your Company — um time integrado de especialistas senior:
SRE Senior, DevOps Cloud Senior, Platform Engineer Senior, DevSecOps Senior, FinOps Senior.

Voce tem acesso DIRETO via MCP tools a:
- Grafana (Prometheus/PromQL, Loki/LogQL, Tempo/TraceQL, dashboards)
- AWS multi-account (ECS, RDS, ElastiCache, VPC, Cost Explorer, GuardDuty, CloudTrail)
- GitHub (repos, PRs, commits, code search, workflows, diffs)
- SonarQube (quality gates, issues, metrics)
- Terraform Cloud (workspaces, runs, state, plans)
- Knowledge Base (RAG documentation)

## Como Agir

1. **Investigue antes de responder** — SEMPRE use tools para buscar dados reais
2. **Busque em multiplas fontes** — cruze AWS + Prometheus + GitHub + Loki
3. **Nunca responda parcialmente** — se a pergunta pede analise, va fundo
4. **Adapte a profundidade** — pergunta simples = resposta direta, investigacao = analise completa
5. **Cite a fonte** — "(via Prometheus)", "(via boto3 ECS)", "(via GitHub API)"
6. **Nunca invente dados** — se um tool falhou, diga qual e por que

## Contexto Multi-Account AWS
| Conta | ID | Uso |
|-------|----|-----|
| Hub (Observability) | YOUR_HUB_ACCOUNT_ID | LGTM stack, AI, SonarQube |
| Dev | YOUR_DEV_ACCOUNT_ID | Example API, APIs de negocio |
| Prod | YOUR_PRD_ACCOUNT_ID | Producao |
| Infra (Kong) | YOUR_INFRA_ACCOUNT_ID | Kong Gateway |
| Capital | YOUR_CAPITAL_ACCOUNT_ID | APIs Capital |

## Loki Labels (IMPORTANTE)
- Prometheus: job="example-api-api"
- Loki: job="ecs", service="example-api-api" (NAO job="example-api-api"!)
- Tempo: resource.service.name="example-api-api"

## Formato
- Responda SEMPRE em portugues (BR)
- Use markdown (tabelas, code blocks, listas)
- Para problemas, classifique severidade (P1-P4)
- Inclua "Proximos Passos" com acoes concretas
- Proporcionalidade: pergunta simples = 10 linhas, investigacao = analise completa

## IMPORTANTE: Limites e Redirecionamentos

### Metricas de Negocio (KPIs)
Voce NAO tem acesso SQL direto ao banco do Example API. Para KPIs como:
- Documentos assinados, taxa de conversao, KYC approval rate, envelopes ativos
- Signatarios unicos, top tenants, OCR success rate

Responda: "Esses KPIs estao disponiveis no dashboard **Example API Business KPIs (DEV)** no Grafana:
https://grafana.observability.tower.yourorg.com.br/d/example-api-dev-business-kpis
Os dados sao consultados direto do banco PostgreSQL em tempo real."

Voce PODE consultar metricas de INFRAESTRUTURA (ECS, RDS, Redis, ALB) e OBSERVABILIDADE (Prometheus, Loki, Tempo).

### Eficiencia de Tools
- Se apos 3-4 tool calls nao encontrou a resposta, PARE e informe o que encontrou
- NAO fique em loop chamando tools repetidamente com variações da mesma query
- Se um tool retornou erro ou vazio, explique e sugira alternativa (CLI, Grafana, etc.)
"""


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------
async def run_ag5(
    question: str,
    history: list[dict] | None = None,
    role: str = DEFAULT_ROLE,
) -> AsyncGenerator[str, None]:
    """AG-5: Claude Sonnet + MCP tools (single model, no router)."""

    start_ts = time.monotonic()

    # Input guardrails
    try:
        question = validate_input(question)
    except InputGuardError as e:
        yield e.user_message
        return

    # RBAC
    if not check_role_access(role, "general"):
        yield get_denied_message(role, "general")
        return

    # Semantic cache lookup (2s timeout, non-blocking)
    try:
        import semantic_cache
        cached = await asyncio.wait_for(
            semantic_cache.lookup(question), timeout=2.0
        )
        if cached:
            yield cached
            yield "\n\n---\n*Resposta via cache semantico*"
            return
    except (asyncio.TimeoutError, Exception):
        pass

    # Initialize MCP client (discovers tools from all servers)
    mcp = await get_mcp_manager()
    tools = mcp.get_anthropic_tools()

    if not tools:
        yield "Nenhum MCP server disponivel. Verifique os sidecars."
        return

    logger.info(f"AG-5: {mcp.tool_count} tools from {mcp.server_summary}")

    # Build messages
    messages = []
    if history:
        for h in history[-10:]:  # Keep last 10 messages
            messages.append({"role": h["role"], "content": h["content"]})

    messages.append({"role": "user", "content": question})

    # Claude ReAct loop with MCP tools
    client = _get_client()
    total_tools = 0

    for turn in range(MAX_TURNS):
        try:
            response = await asyncio.wait_for(
                client.messages.create(
                    model=MODEL,
                    max_tokens=4096,
                    system=SYSTEM_PROMPT_AG5,
                    tools=tools,
                    messages=messages,
                ),
                timeout=TIMEOUT,
            )
        except asyncio.TimeoutError:
            yield "\n\nTimeout na chamada ao Claude. Tente novamente."
            break
        except Exception as e:
            yield f"\n\nErro na chamada ao Claude: {e}"
            break

        # Process response blocks
        text_parts = []
        tool_calls = []

        for block in response.content:
            if block.type == "text":
                text_parts.append(block.text)
            elif block.type == "tool_use":
                tool_calls.append(block)

        # If no tool calls, we're done — yield final text
        if response.stop_reason == "end_turn" or not tool_calls:
            final_text = "\n".join(text_parts)
            yield scan_output(final_text)
            break

        # Execute tool calls in parallel
        total_tools += len(tool_calls)

        tool_results = await asyncio.gather(
            *(mcp.call_tool(tc.name, tc.input) for tc in tool_calls),
            return_exceptions=True,
        )

        # Build tool results for next turn
        messages.append({"role": "assistant", "content": response.content})
        messages.append({
            "role": "user",
            "content": [
                {
                    "type": "tool_result",
                    "tool_use_id": tc.id,
                    "content": str(result) if isinstance(result, Exception) else result,
                }
                for tc, result in zip(tool_calls, tool_results)
            ],
        })

        logger.info(
            f"AG-5 turn {turn+1}: {len(tool_calls)} tool(s) — "
            f"{', '.join(tc.name for tc in tool_calls)}"
        )
    else:
        yield "\n\nLimite de iteracoes atingido."

    elapsed = int((time.monotonic() - start_ts) * 1000)
    yield f"\n\n---\n*AG-5 — {total_tools} tool call(s) — {elapsed}ms*"

    # Structured log for cost/usage tracking (persists in Loki)
    logger.info(json.dumps({
        "event": "ag5_query_completed",
        "question_preview": question[:100],
        "model": MODEL,
        "tool_calls": total_tools,
        "turns": turn + 1 if 'turn' in dir() else 0,
        "duration_ms": elapsed,
        "mcp_servers": mcp.server_summary,
        "input_tokens": response.usage.input_tokens if hasattr(response, 'usage') else 0,
        "output_tokens": response.usage.output_tokens if hasattr(response, 'usage') else 0,
        "cache_hit": False,
        "role": role,
    }))

    # Semantic cache store (fire-and-forget)
    try:
        import semantic_cache
        # Collect yielded text for caching (approximate — last text_parts)
        if text_parts:
            cache_text = "\n".join(text_parts)
            asyncio.create_task(
                semantic_cache.store(question, cache_text, mcp.server_summary)
            )
    except Exception:
        pass
