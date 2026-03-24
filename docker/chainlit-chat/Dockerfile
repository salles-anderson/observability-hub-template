# -----------------------------------------------------------------------------
# Chainlit Chat — Teck AI Assistant v12 (AG-1/AG-2 Dual Pipeline)
# -----------------------------------------------------------------------------
# Python 3.12 + Anthropic SDK + OpenAI SDK (LiteLLM)
# AG-1: Single orchestrator (42 tools, Claude Sonnet)
# AG-2: 7 specialized agents (Router + Agents + Correlator)
# Feature flag: AGENT_VERSION=ag1|ag2
# -----------------------------------------------------------------------------

FROM python:3.12-slim AS base

# Instalar curl (healthcheck)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Criar usuario non-root
RUN useradd -m -u 1000 chainlit

WORKDIR /app

# Instalar dependencias Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Gerar config.toml default compativel com a versao instalada
RUN python -m chainlit init && rm -f chainlit.md

# Copiar codigo fonte e assets
COPY app.py agent.py tools_registry.py query_cache.py aws_shortcuts.py security_shortcuts.py tfc_shortcuts.py tfc_reviewer.py rag_retriever.py rag_indexer.py rag_contextual.py semantic_cache.py obs_tools.py github_tools.py sonarqube_tools.py alert_investigator.py guardrails.py account_resolver.py entrypoint.sh ./
COPY core/ ./core/
COPY tools/ ./tools/
COPY agents/ ./agents/
COPY shortcuts/ ./shortcuts/
COPY prompts/ ./prompts/
COPY public/ ./public/
COPY docs/ ./docs/

# Ajustar permissoes
RUN chmod +x entrypoint.sh && chown -R chainlit:chainlit /app

USER chainlit

EXPOSE 8501

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:8501/ || exit 1

ENTRYPOINT ["./entrypoint.sh"]
