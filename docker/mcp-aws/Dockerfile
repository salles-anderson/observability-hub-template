# -----------------------------------------------------------------------------
# mcp-aws — MCP Server for AWS Infrastructure + FinOps + Security (AG-5)
# -----------------------------------------------------------------------------
# Exposes AWS APIs as MCP tools: ECS, RDS, ElastiCache, VPC, Cost Explorer,
# GuardDuty, CloudTrail, SSM, KMS, WAF, ECR, CloudMap.
# Cross-account via STS AssumeRole.
# Transport: SSE on port 8001
# -----------------------------------------------------------------------------

FROM python:3.12-slim

LABEL maintainer="Teck Solucoes - Observability Hub"
LABEL io.modelcontextprotocol.server.name="teck/mcp-aws"

RUN apt-get update && apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

RUN adduser --disabled-password --uid 1000 mcp
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py .

USER mcp

EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -sf http://localhost:8001/sse || exit 1

CMD ["python", "server.py"]
