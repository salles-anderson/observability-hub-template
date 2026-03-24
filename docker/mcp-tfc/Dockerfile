# -----------------------------------------------------------------------------
# mcp-tfc — MCP Server for Terraform Cloud (AG-5)
# -----------------------------------------------------------------------------
# Exposes TFC API as MCP tools: workspaces, runs, state, plans, trigger.
# Transport: SSE on port 8003
# Build: docker build -t mcp-tfc .
# Run:   docker run -p 8003:8003 -e TFC_API_TOKEN=... mcp-tfc
# -----------------------------------------------------------------------------

FROM python:3.12-slim

LABEL maintainer="Teck Solucoes - Observability Hub"
LABEL io.modelcontextprotocol.server.name="teck/mcp-tfc"

RUN apt-get update && apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

RUN adduser --disabled-password --uid 1000 mcp
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py .

USER mcp

EXPOSE 8003

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -sf http://localhost:8003/sse || exit 1

CMD ["python", "server.py"]
