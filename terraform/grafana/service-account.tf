# -----------------------------------------------------------------------------
# Grafana Service Account - mcp-grafana (Sprint 6A)
# -----------------------------------------------------------------------------
# Service account dedicado para o mcp-grafana acessar Grafana APIs.
# Permite: Prometheus (PromQL), Loki (LogQL), dashboards, alerting, annotations.
# Token armazenado como output sensitive para configurar no TFC workspace build.
# -----------------------------------------------------------------------------

resource "grafana_service_account" "mcp_grafana" {
  name        = "mcp-grafana"
  role        = "Editor"
  is_disabled = false
}

resource "grafana_service_account_token" "mcp_grafana" {
  name               = "mcp-grafana-agent-sdk"
  service_account_id = grafana_service_account.mcp_grafana.id
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "mcp_grafana_service_account_id" {
  description = "ID do service account mcp-grafana"
  value       = grafana_service_account.mcp_grafana.id
}

output "mcp_grafana_token" {
  description = "Token do service account mcp-grafana (configurar no TFC workspace build como grafana_service_account_token)"
  value       = grafana_service_account_token.mcp_grafana.key
  sensitive   = true
}
