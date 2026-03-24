# -----------------------------------------------------------------------------
# WAFv2 — Hub ALB Protection (Sprint 1 AI Platform)
# -----------------------------------------------------------------------------
# Protege o Hub ALB (Grafana, SonarQube, Chainlit) com duas camadas:
#
#   Regra 0: ALLOW se request tem "Authorization: Bearer" header
#            (API access autenticado — TFC, MCP Grafana, etc.)
#   Regra 1: BLOCK se IP NÃO está na allowlist
#            (protege UI contra acesso não-autorizado)
#   Default: ALLOW
#
# Isso permite que o TFC (IPs dinamicos) acesse a Grafana API via SA token,
# enquanto o acesso via browser continua restrito por IP.
#
# Para ativar: definir var.waf_allowed_cidrs com os CIDRs autorizados.
# Com lista vazia, o WAF nao e criado.
# -----------------------------------------------------------------------------

resource "aws_wafv2_ip_set" "hub_allowlist" {
  count = length(var.waf_allowed_cidrs) > 0 ? 1 : 0

  name               = "${local.name_prefix}-hub-allowlist"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.waf_allowed_cidrs

  tags = merge(local.tags, { Name = "${local.name_prefix}-hub-allowlist" })
}

resource "aws_wafv2_web_acl" "hub" {
  count = length(var.waf_allowed_cidrs) > 0 ? 1 : 0

  name  = "${local.name_prefix}-hub-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # ---------------------------------------------------------------------------
  # Rule 0: Allow authenticated API requests (Bearer token)
  # Grafana SA tokens usam "Authorization: Bearer glsa_..."
  # TFC provider, MCP Grafana, e qualquer client autenticado passam por aqui.
  # ---------------------------------------------------------------------------
  rule {
    name     = "allow-api-bearer-auth"
    priority = 0

    action {
      allow {}
    }

    statement {
      byte_match_statement {
        search_string         = "Bearer "
        positional_constraint = "STARTS_WITH"

        field_to_match {
          single_header { name = "authorization" }
        }

        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = replace("${local.name_prefix}-allow-api-bearer", "/[^A-Za-z0-9]/", "_")
      sampled_requests_enabled   = true
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 1: Block IPs not in allowlist
  # Browser access (sem Bearer token) só é permitido de IPs autorizados.
  # ---------------------------------------------------------------------------
  rule {
    name     = "block-all-except-allowlist"
    priority = 1

    action {
      block {}
    }

    statement {
      not_statement {
        statement {
          ip_set_reference_statement {
            arn = aws_wafv2_ip_set.hub_allowlist[0].arn
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = replace("${local.name_prefix}-block-non-allowlist", "/[^A-Za-z0-9]/", "_")
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = replace("${local.name_prefix}-hub-waf", "/[^A-Za-z0-9]/", "_")
    sampled_requests_enabled   = true
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-hub-waf" })
}

resource "aws_wafv2_web_acl_association" "hub" {
  count = length(var.waf_allowed_cidrs) > 0 ? 1 : 0

  resource_arn = module.alb.lb_arn
  web_acl_arn  = aws_wafv2_web_acl.hub[0].arn
}
