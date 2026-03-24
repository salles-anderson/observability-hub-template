# -----------------------------------------------------------------------------
# API Gateway HTTP API v2 - AIOps Webhook
# -----------------------------------------------------------------------------
# Pipeline: AlertManager --> API GW --> VPC Link --> ECS AIOps Agent v2 --> Slack
#           CW Alarms --> SNS --> (futuro: ECS Agent subscription)
#
# NOTA: Lambda v1 (alert-enrichment) foi removida. Toda logica de alert
# enrichment agora roda no ECS AIOps Agent (aiops-agent.tf).
# -----------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "alert_webhook" {
  count = var.enable_aiops ? 1 : 0

  name          = "${local.name_prefix}-alert-webhook"
  protocol_type = "HTTP"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alert-webhook"
  })
}

resource "aws_apigatewayv2_stage" "alert_webhook" {
  count = var.enable_aiops ? 1 : 0

  api_id      = aws_apigatewayv2_api.alert_webhook[0].id
  name        = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.aiops_apigw[0].arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alert-webhook-stage"
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group - API Gateway
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "aiops_apigw" {
  count = var.enable_aiops ? 1 : 0

  name              = "/aws/apigateway/${local.name_prefix}-alert-webhook"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-aiops-apigw-logs"
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "aiops_apigw_api_id" {
  description = "ID do API Gateway v2 (para metricas CloudWatch)"
  value       = var.enable_aiops ? aws_apigatewayv2_api.alert_webhook[0].id : null
}
