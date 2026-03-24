# -----------------------------------------------------------------------------
# AWS Cloud Map - Service Discovery
# Namespace privado para comunicação interna entre containers via DNS
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Namespace Privado
# Permite que os serviços se comuniquem usando nomes DNS internos
# Ex: prometheus.observability.local, grafana.observability.local
# -----------------------------------------------------------------------------
resource "aws_service_discovery_private_dns_namespace" "observability" {
  name        = var.cloudmap_namespace
  description = "Namespace privado para servicos de observabilidade"
  vpc         = local.vpc_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${var.cloudmap_namespace}"
  })
}

# -----------------------------------------------------------------------------
# Lista de serviços para Service Discovery
# -----------------------------------------------------------------------------
locals {
  service_discovery_services = merge(
    {
      grafana      = "grafana"
      prometheus   = "prometheus"
      loki         = "loki"
      tempo        = "tempo"
      otel         = "otel"
      alertmanager = "alertmanager"
    },
    var.enable_grafana_llm ? { litellm = "litellm" } : {},
    var.enable_chainlit ? { chainlit_chat = "chainlit-chat" } : {},
    var.enable_qdrant ? { qdrant = "qdrant" } : {}
  )
}

# -----------------------------------------------------------------------------
# Service Discovery Services
# Cada serviço terá um registro DNS no formato: <service>.observability.local
# -----------------------------------------------------------------------------
resource "aws_service_discovery_service" "services" {
  for_each = local.service_discovery_services

  name = each.value

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.observability.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    # Usa MULTIVALUE para retornar múltiplos IPs quando há múltiplas tasks
    routing_policy = "MULTIVALUE"
  }

  # Health check customizado para verificar saúde dos containers
  health_check_custom_config {
    failure_threshold = 1
  }

  tags = merge(local.tags, {
    Name    = "${local.name_prefix}-sd-${each.value}"
    Service = each.value
  })
}

# -----------------------------------------------------------------------------
# Service Discovery (SRV) - API Gateway + Cloud Map
# SRV records incluem porta, necessario para VPC Link do API Gateway.
# Nome diferente do A record para evitar conflito no namespace.
# -----------------------------------------------------------------------------
resource "aws_service_discovery_service" "aiops_agent_apigw" {
  count = var.enable_agent_sdk ? 1 : 0

  name = "aiops-agent-apigw"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.observability.id

    dns_records {
      ttl  = 10
      type = "SRV"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = merge(local.tags, {
    Name    = "${local.name_prefix}-sd-aiops-agent-apigw"
    Service = "aiops-agent-apigw"
  })
}
