# -----------------------------------------------------------------------------
# SSM Parameter Store - Prometheus Config
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "prometheus_config" {
  name  = "/${local.name_prefix}/prometheus/config"
  type  = "String"
  value = file("${path.module}/configs/prometheus.yml")

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-prometheus-config"
  })
}

# Recording rules carregadas via env var base64 no ECS task (prometheus.tf)
# Nao armazenadas no SSM devido ao limite de 8KB

# -----------------------------------------------------------------------------
# SSM Parameter Store - AlertManager Config
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "alertmanager_config" {
  name  = "/${local.name_prefix}/alertmanager/config"
  type  = "String"
  tier  = "Advanced"
  value = base64encode(templatefile("${path.module}/configs/alertmanager.yml.tpl", {
    slack_webhook_url = var.slack_webhook_url
    aiops_webhook_url = var.enable_alert_investigation ? "http://chainlit-chat.${var.cloudmap_namespace}:8501/api/alert-investigate" : (var.enable_aiops ? "${aws_apigatewayv2_api.alert_webhook[0].api_endpoint}/prod/v2/webhook/alertmanager" : "")
  }))

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alertmanager-config"
  })
}

# -----------------------------------------------------------------------------
# SSM Parameter Store - Loki Config
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "loki_config" {
  name  = "/${local.name_prefix}/loki/config"
  type  = "String"
  value = file("${path.module}/configs/loki-config.yaml")

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-loki-config"
  })
}

# -----------------------------------------------------------------------------
# SSM Parameter Store - Tempo Config
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "tempo_config" {
  name  = "/${local.name_prefix}/tempo/config"
  type  = "String"
  value = file("${path.module}/configs/tempo-config.yaml")

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-tempo-config"
  })
}

