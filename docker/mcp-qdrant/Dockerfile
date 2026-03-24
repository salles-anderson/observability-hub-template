# -----------------------------------------------------------------------------
# mcp-qdrant — MCP Server for RAG + Semantic Cache (AG-5)
# -----------------------------------------------------------------------------
# Exposes Qdrant vector search as MCP tools: rag_search, cache_lookup, cache_store.
# Transport: SSE on port 8004
# -----------------------------------------------------------------------------

FROM python:3.12-slim

LABEL maintainer="Teck Solucoes - Observability Hub"
LABEL io.modelcontextprotocol.server.name="teck/mcp-qdrant"

RUN apt-get update && apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

RUN adduser --disabled-password --uid 1000 mcp
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py .

USER mcp

EXPOSE 8004

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -sf http://localhost:8004/sse || exit 1

CMD ["python", "server.py"]
