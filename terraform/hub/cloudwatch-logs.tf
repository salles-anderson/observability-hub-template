# -----------------------------------------------------------------------------
# CloudWatch Log Groups
# Log groups para centralização de logs dos serviços de observabilidade
# Nota: O log group do Grafana está definido em grafana.tf
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Lista de serviços que terão log groups
# -----------------------------------------------------------------------------
locals {
  observability_services = [
    "prometheus",
    "loki",
    "tempo",
    "otel-collector",
    "alertmanager"
  ]
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups para cada serviço
# Todos os logs são criptografados com KMS e têm retenção configurável
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "services" {
  for_each = toset(local.observability_services)

  name              = "/ecs/${local.name_prefix}/${each.value}"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name    = "${local.name_prefix}-logs-${each.value}"
    Service = each.value
  })
}
