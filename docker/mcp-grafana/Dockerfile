# -----------------------------------------------------------------------------
# mcp-grafana - MCP Server para acesso ao Grafana via Agent SDK (Sprint 6A)
# -----------------------------------------------------------------------------
# Build: docker build --build-arg MCP_GRAFANA_VERSION=v0.11.0 -t mcp-grafana .
# Run:   docker run -p 8000:8000 -e GRAFANA_URL=... -e GRAFANA_API_KEY=... mcp-grafana
# -----------------------------------------------------------------------------

ARG MCP_GRAFANA_VERSION=v0.11.0

# --- Build stage ---
FROM golang:1.24-alpine AS builder

ARG MCP_GRAFANA_VERSION

WORKDIR /app

RUN apk add --no-cache git && \
    git clone --depth 1 --branch ${MCP_GRAFANA_VERSION} \
      https://github.com/grafana/mcp-grafana.git . && \
    go mod download && \
    CGO_ENABLED=0 go build -ldflags="-s -w" -o mcp-grafana ./cmd/mcp-grafana

# --- Runtime stage ---
FROM alpine:3.21

LABEL io.modelcontextprotocol.server.name="io.github.grafana/mcp-grafana"
LABEL maintainer="Teck Solucoes - Observability Hub"

RUN apk upgrade --no-cache && apk add --no-cache ca-certificates

RUN adduser -D -u 1000 mcp-grafana

WORKDIR /app

COPY --from=builder --chown=1000:1000 /app/mcp-grafana /app/

USER mcp-grafana

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8000/sse || exit 1

ENTRYPOINT ["/app/mcp-grafana"]
CMD [ \
  "--transport", "sse", \
  "--address", "0.0.0.0:8000" \
]
