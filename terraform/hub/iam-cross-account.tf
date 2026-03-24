# -----------------------------------------------------------------------------
# Cross-Account IAM Roles
# -----------------------------------------------------------------------------
# Permite acesso cross-account para:
# - Grafana ler metricas CloudWatch de contas spoke
# - Collectors de contas spoke enviarem telemetria para o Hub
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
variable "enable_cross_account_roles" {
  description = "Habilitar roles cross-account para telemetria"
  type        = bool
  default     = false
}

variable "cross_account_external_id" {
  description = "External ID para assume role cross-account (manter secreto)"
  type        = string
  default     = "teck-observability-hub-2024"
  sensitive   = true
}

# -----------------------------------------------------------------------------
# IAM Role - Telemetry Writer
# Permite collectors de outras contas enviarem telemetria
# -----------------------------------------------------------------------------
resource "aws_iam_role" "telemetry_writer" {
  count = var.enable_cross_account_roles ? 1 : 0

  name               = "${local.name_prefix}-telemetry-writer"
  assume_role_policy = data.aws_iam_policy_document.telemetry_writer_assume[0].json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-telemetry-writer"
  })
}

data "aws_iam_policy_document" "telemetry_writer_assume" {
  count = var.enable_cross_account_roles ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [for id in var.spoke_account_ids : "arn:aws:iam::${id}:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.cross_account_external_id]
    }
  }
}

# Permissoes para escrita de telemetria
data "aws_iam_policy_document" "telemetry_writer_permissions" {
  count = var.enable_cross_account_roles ? 1 : 0

  # Escrita no S3 (logs de auditoria)
  statement {
    sid = "S3WriteAccess"
    actions = [
      "s3:PutObject",
      "s3:GetBucketLocation"
    ]
    resources = [
      module.s3_bucket.bucket_arn,
      "${module.s3_bucket.bucket_arn}/telemetry/*",
      "${module.s3_bucket.bucket_arn}/audit-logs/*"
    ]
  }

  # Decrypt/Encrypt com KMS
  statement {
    sid = "KMSAccess"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]
    resources = [module.kms.key_arn]
  }
}

resource "aws_iam_role_policy" "telemetry_writer" {
  count = var.enable_cross_account_roles ? 1 : 0

  name   = "${local.name_prefix}-telemetry-writer-policy"
  role   = aws_iam_role.telemetry_writer[0].id
  policy = data.aws_iam_policy_document.telemetry_writer_permissions[0].json
}

# -----------------------------------------------------------------------------
# IAM Role - CloudWatch Reader (para Grafana)
# Permite Grafana ler metricas de contas spoke
# NOTA: Esta role precisa ser criada nas contas SPOKE
# Aqui geramos o policy document de referencia
# -----------------------------------------------------------------------------
locals {
  # Policy document que deve ser usado nas contas spoke
  grafana_cloudwatch_reader_policy = var.enable_cross_account_roles ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAssumeFromObservabilityHub"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ecs_task.arn
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.cross_account_external_id
          }
        }
      }
    ]
  }) : null

  # Permissoes que a role nas contas spoke deve ter
  grafana_cloudwatch_permissions_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchReadAccess"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetInsightRuleReport"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsReadAccess"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2DescribeAccess"
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions"
        ]
        Resource = "*"
      },
      {
        Sid    = "TagReadAccess"
        Effect = "Allow"
        Action = [
          "tag:GetResources"
        ]
        Resource = "*"
      }
    ]
  })

  # Texto de onboarding para cross-account
  cross_account_onboarding_text = <<-EOT
    # Configuracao Cross-Account

    ## Para collectors nas contas spoke enviarem telemetria:

    1. Configure o collector (Alloy/OTel) com assume role:
       - Role ARN: (usar output telemetry_writer_role_arn)
       - External ID: (fornecido via canal seguro)

    2. Exemplo de configuracao Alloy:
       otelcol.auth.assumeRole "hub" {
         role_arn    = "<ROLE_ARN>"
         external_id = "<EXTERNAL_ID>"
       }

    ## Para Grafana ler CloudWatch das contas spoke:

    1. Criar role em cada conta spoke com:
       - Trust policy: (ver output spoke_role_trust_policy)
       - Permissions: (ver output spoke_role_permissions_policy)
       - Nome sugerido: grafana-cloudwatch-reader

    2. Configurar data source no Grafana:
       - Assume Role ARN: arn:aws:iam::<SPOKE_ACCOUNT>:role/grafana-cloudwatch-reader
       - External ID: (fornecido via canal seguro)
  EOT
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "telemetry_writer_role_arn" {
  description = "ARN da role para collectors assumirem"
  value       = var.enable_cross_account_roles ? aws_iam_role.telemetry_writer[0].arn : null
}

output "telemetry_writer_role_name" {
  description = "Nome da role para collectors"
  value       = var.enable_cross_account_roles ? aws_iam_role.telemetry_writer[0].name : null
}

output "spoke_role_trust_policy" {
  description = "Trust policy para criar role nas contas spoke (para Grafana ler CloudWatch)"
  value       = local.grafana_cloudwatch_reader_policy
  sensitive   = true
}

output "spoke_role_permissions_policy" {
  description = "Permissions policy para criar role nas contas spoke"
  value       = local.grafana_cloudwatch_permissions_policy
}

output "cross_account_onboarding" {
  description = "Instrucoes para configurar cross-account access"
  value       = var.enable_cross_account_roles ? local.cross_account_onboarding_text : "Cross-account roles nao habilitadas. Defina enable_cross_account_roles = true"
}
