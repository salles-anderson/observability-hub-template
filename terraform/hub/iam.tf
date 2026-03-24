# -----------------------------------------------------------------------------
# ECS Task Execution Role
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name_prefix}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ecs-task-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# -----------------------------------------------------------------------------
# ECS Task Execution Role - SSM Parameter Store Policy
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_task_execution_ssm" {
  statement {
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter"
    ]

    resources = concat([
      aws_ssm_parameter.observability_db_password.arn,
      aws_ssm_parameter.grafana_admin_password.arn
    ], var.enable_grafana_llm ? concat([
      aws_ssm_parameter.anthropic_api_key[0].arn,
      aws_ssm_parameter.gemini_api_key[0].arn
    ], var.deepseek_api_key != "" ? [
      aws_ssm_parameter.deepseek_api_key[0].arn
    ] : []) : [], var.enable_agent_sdk ? [
      aws_ssm_parameter.grafana_sa_token[0].arn,
      aws_ssm_parameter.anthropic_api_key_agent[0].arn
    ] : [], var.enable_chainlit ? concat([
      aws_ssm_parameter.chainlit_auth_secret[0].arn,
      aws_ssm_parameter.cognito_client_secret[0].arn
    ], var.tfc_api_token != "" ? [
      aws_ssm_parameter.tfc_api_token[0].arn
    ] : [], var.github_token_obs_hub != "" ? [
      aws_ssm_parameter.github_token[0].arn
    ] : [], var.sonarqube_token != "" ? [
      aws_ssm_parameter.sonarqube_token[0].arn
    ] : []) : [])
  }

  statement {
    actions = [
      "kms:Decrypt"
    ]

    resources = [module.kms.key_arn]
  }
}

resource "aws_iam_role_policy" "ecs_task_execution_ssm" {
  name   = "${local.name_prefix}-ecs-task-execution-ssm-policy"
  role   = aws_iam_role.ecs_task_execution.id
  policy = data.aws_iam_policy_document.ecs_task_execution_ssm.json
}

# -----------------------------------------------------------------------------
# ECS Task Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task" {
  name               = "${local.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ecs-task-role"
  })
}

# -----------------------------------------------------------------------------
# ECS Task Role - S3 Policy
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_task_s3" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      module.s3_bucket.bucket_arn,
      "${module.s3_bucket.bucket_arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "ecs_task_s3" {
  name   = "${local.name_prefix}-ecs-task-s3-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_s3.json
}

# -----------------------------------------------------------------------------
# ECS Task Role - KMS Policy
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_task_kms" {
  statement {
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]

    resources = [module.kms.key_arn]
  }
}

resource "aws_iam_role_policy" "ecs_task_kms" {
  name   = "${local.name_prefix}-ecs-task-kms-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_kms.json
}

# -----------------------------------------------------------------------------
# ECS Task Role - CloudWatch Logs Policy
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_task_logs" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "ecs_task_logs" {
  name   = "${local.name_prefix}-ecs-task-logs-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_logs.json
}

# -----------------------------------------------------------------------------
# ECS Task Role - CloudWatch Metrics Read Policy (Grafana datasource)
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_task_cloudwatch" {
  statement {
    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetInsightRuleReport"
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "logs:DescribeLogGroups",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "logs:GetLogEvents"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_task_cloudwatch" {
  name   = "${local.name_prefix}-ecs-task-cloudwatch-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_cloudwatch.json
}

# -----------------------------------------------------------------------------
# ECS Task Role - EFS Policy
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_task_efs" {
  statement {
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:ClientRootAccess"
    ]

    resources = [aws_efs_file_system.this[0].arn]

    condition {
      test     = "StringEquals"
      variable = "elasticfilesystem:AccessPointArn"
      values = concat(
        [aws_efs_access_point.grafana.arn],
        var.enable_qdrant ? [aws_efs_access_point.qdrant[0].arn] : []
      )
    }
  }
}

resource "aws_iam_role_policy" "ecs_task_efs" {
  name   = "${local.name_prefix}-ecs-task-efs-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_efs.json
}

# -----------------------------------------------------------------------------
# ECS Task Role - SSM Policy (ECS Exec)
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_task_ssm" {
  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_task_ssm" {
  name   = "${local.name_prefix}-ecs-task-ssm-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_ssm.json
}

# -----------------------------------------------------------------------------
# ECS Task Role - Bedrock Policy (LiteLLM → Titan Embed v2 para RAG)
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_task_bedrock" {
  statement {
    sid     = "BedrockTitanEmbed"
    actions = ["bedrock:InvokeModel"]
    resources = [
      "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
    ]
  }
}

resource "aws_iam_role_policy" "ecs_task_bedrock" {
  count = var.enable_qdrant ? 1 : 0

  name   = "${local.name_prefix}-ecs-task-bedrock-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_bedrock.json
}

# -----------------------------------------------------------------------------
# Chainlit Task Role — AWS Solutions Architect (Read-Only)
# -----------------------------------------------------------------------------
# Dedicated role for Chainlit AI assistant with comprehensive read-only access
# to ALL AWS services. Follows least privilege with explicit DENY for sensitive
# data (secrets, S3 objects, message content).
# -----------------------------------------------------------------------------
resource "aws_iam_role" "chainlit_task" {
  count = var.enable_chainlit ? 1 : 0

  name               = "${local.name_prefix}-chainlit-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-chainlit-task-role"
  })
}

# AWS Managed ReadOnlyAccess — covers 200+ AWS services
resource "aws_iam_role_policy_attachment" "chainlit_readonly" {
  count = var.enable_chainlit ? 1 : 0

  role       = aws_iam_role.chainlit_task[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Extra permissions not included in ReadOnlyAccess
resource "aws_iam_role_policy" "chainlit_extras" {
  count = var.enable_chainlit ? 1 : 0

  name = "${local.name_prefix}-chainlit-extras-policy"
  role = aws_iam_role.chainlit_task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CostExplorer"
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetCostForecast",
          "ce:GetCostAndUsageWithResources",
          "ce:GetReservationCoverage",
          "ce:GetReservationUtilization",
          "ce:GetSavingsPlansUtilization",
          "ce:GetSavingsPlansCoverage",
          "ce:GetRightsizingRecommendation",
          "ce:GetReservationPurchaseRecommendation",
          "ce:GetAnomalies",
          "ce:GetAnomalyMonitors",
          "ce:GetAnomalySubscriptions"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [module.kms.key_arn]
      },
      {
        Sid    = "SSMExec"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Explicit DENY for sensitive data — security guardrail
# Allows SSM read ONLY for the chainlit users parameter (bcrypt hashes for auth)
resource "aws_iam_role_policy" "chainlit_deny_sensitive" {
  count = var.enable_chainlit ? 1 : 0

  name = "${local.name_prefix}-chainlit-deny-sensitive-policy"
  role = aws_iam_role.chainlit_task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenySSMExceptChainlitUsers"
        Effect = "Deny"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        NotResource = [
          "arn:aws:ssm:${var.aws_region}:${var.account_id}:parameter/${local.name_prefix}/chainlit/users"
        ]
      },
      {
        Sid    = "DenySensitiveDataAccess"
        Effect = "Deny"
        Action = [
          "secretsmanager:GetSecretValue",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "sqs:ReceiveMessage",
          "sqs:SendMessage",
          "sqs:DeleteMessage",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "kinesis:GetRecords",
          "codecommit:GetFile",
          "codecommit:GetBlob"
        ]
        Resource = "*"
      }
    ]
  })
}

# Cross-account AssumeRole — allows Chainlit to query spoke accounts (read-only)
resource "aws_iam_role_policy" "chainlit_cross_account" {
  count = var.enable_chainlit && length(var.spoke_account_ids) > 0 ? 1 : 0

  name = "${local.name_prefix}-chainlit-cross-account-policy"
  role = aws_iam_role.chainlit_task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeSpokReadOnlyRoles"
        Effect = "Allow"
        Action = ["sts:AssumeRole"]
        Resource = [
          for id in var.spoke_account_ids :
          "arn:aws:iam::${id}:role/${var.spoke_role_name}"
        ]
      }
    ]
  })
}
