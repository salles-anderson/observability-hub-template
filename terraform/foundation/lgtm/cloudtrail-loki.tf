# -----------------------------------------------------------------------------
# OBS-SEC-1: CloudTrail Central → Loki
# -----------------------------------------------------------------------------
# Lambda que processa eventos do CloudTrail (S3 central) e envia para Loki.
# Permite consultar audit logs de TODAS as 11 contas no Grafana via LogQL.
#
# Arquitetura:
#   Org Trail (account 121212121212) → S3 → SQS → Lambda → Loki (Hub)
#
# Lambda subscription via S3 event notification → SQS queue.
#
# Portado VERBATIM de terraform/environment/build/cloudtrail-loki.tf. Refs
# cross-domain ja estavam no formato local.* no build e resolvem no lgtm:
#   local.private_subnet_ids   (locals.tf, hardcoded — network nao expoe output)
#   local.security.ecs_tasks_sg_id  (remote_state security)
# archive_file usa ${path.module}/../../../docker/cloudtrail-loki (mesma
# profundidade do build e do ai-platform/cognito-provisioning → MESMO dir).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Lambda IAM Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "cloudtrail_loki" {
  count = var.enable_cloudtrail_loki ? 1 : 0

  name = "${local.name_prefix}-cloudtrail-loki-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

# VPC ENI permissions — required because Lambda runs inside VPC (vpc_config)
resource "aws_iam_role_policy_attachment" "cloudtrail_loki_vpc" {
  count = var.enable_cloudtrail_loki ? 1 : 0

  role       = aws_iam_role.cloudtrail_loki[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "cloudtrail_loki" {
  count = var.enable_cloudtrail_loki ? 1 : 0

  name = "${local.name_prefix}-cloudtrail-loki-policy"
  role = aws_iam_role.cloudtrail_loki[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.cloudtrail_s3_bucket}",
          "arn:aws:s3:::${var.cloudtrail_s3_bucket}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
        ]
        Resource = "arn:aws:iam::${var.cloudtrail_account_id}:role/teck-obs-hub-spoke-role"
      },
    ]
  })
}

# -----------------------------------------------------------------------------
# Lambda — CloudTrail S3 → Loki processor
# -----------------------------------------------------------------------------
data "archive_file" "cloudtrail_loki" {
  count = var.enable_cloudtrail_loki ? 1 : 0

  type        = "zip"
  source_dir  = "${path.module}/../../../docker/cloudtrail-loki"
  output_path = "${path.module}/.lambda-builds/cloudtrail-loki.zip"
}

resource "aws_lambda_function" "cloudtrail_loki" {
  count = var.enable_cloudtrail_loki ? 1 : 0

  function_name = "${local.name_prefix}-cloudtrail-loki"
  role          = aws_iam_role.cloudtrail_loki[0].arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 512

  filename         = data.archive_file.cloudtrail_loki[0].output_path
  source_code_hash = data.archive_file.cloudtrail_loki[0].output_base64sha256

  environment {
    variables = {
      LOKI_URL                  = "http://loki.${var.cloudmap_namespace}:3100/loki/api/v1/push"
      CLOUDTRAIL_BUCKET         = var.cloudtrail_s3_bucket
      CLOUDTRAIL_ACCOUNT_ID     = var.cloudtrail_account_id
      SPOKE_ROLE_NAME           = var.spoke_role_name
      CROSS_ACCOUNT_EXTERNAL_ID = "teck-observability-hub-2024"
      PROCESS_WINDOW_MINUTES    = "20"
    }
  }

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [local.security.ecs_tasks_sg_id]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-cloudtrail-loki"
  })
}

# Schedule — process CloudTrail logs every 15 minutes
resource "aws_cloudwatch_event_rule" "cloudtrail_loki_schedule" {
  count = var.enable_cloudtrail_loki ? 1 : 0

  name                = "${local.name_prefix}-cloudtrail-loki-schedule"
  description         = "Process CloudTrail logs every 15 minutes"
  schedule_expression = "rate(15 minutes)"

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "cloudtrail_loki" {
  count = var.enable_cloudtrail_loki ? 1 : 0

  rule      = aws_cloudwatch_event_rule.cloudtrail_loki_schedule[0].name
  target_id = "cloudtrail-loki-lambda"
  arn       = aws_lambda_function.cloudtrail_loki[0].arn
}

resource "aws_lambda_permission" "cloudtrail_loki_eventbridge" {
  count = var.enable_cloudtrail_loki ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cloudtrail_loki[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cloudtrail_loki_schedule[0].arn
}
