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
# Os 9 SSM SecureString foram DES-ESCOPADOS do S2 (ficam no build / migram com
# os serviços na S5 — são consumidos por ~17 task-defs + a master pw do RDS).
# A role transversal ecs_task_execution PERMANECE no cimento e precisa ler esses
# parâmetros em runtime → referenciamos por ARN LITERAL (determinístico do path),
# mantendo a MESMA composição condicional => policy byte-idêntica => no-op.
locals {
  ssm_arn_prefix = "arn:aws:ssm:${var.aws_region}:${var.account_id}:parameter/${local.name_prefix}"
}

data "aws_iam_policy_document" "ecs_task_execution_ssm" {
  statement {
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter"
    ]

    resources = concat([
      "${local.ssm_arn_prefix}/observability/db-password",
      "${local.ssm_arn_prefix}/grafana/admin-password"
      ], var.enable_grafana_llm ? concat([
        "${local.ssm_arn_prefix}/litellm/anthropic-api-key",
        "${local.ssm_arn_prefix}/litellm/gemini-api-key"
        ], var.deepseek_api_key != "" ? [
        "${local.ssm_arn_prefix}/litellm/deepseek-api-key"
      ] : []) : [], var.enable_agent_sdk ? [
      "${local.ssm_arn_prefix}/agent-sdk/grafana-sa-token",
      "${local.ssm_arn_prefix}/agent-sdk/anthropic-api-key"
      ] : [], var.enable_chainlit ? concat([
        var.chainlit_auth_secret_arn
        ], var.tfc_api_token != "" ? [
        "${local.ssm_arn_prefix}/chainlit/tfc-api-token"
        ] : [], var.github_token_obs_hub != "" ? [
        "${local.ssm_arn_prefix}/chainlit/github-token"
        ] : [], var.sonarqube_token != "" ? [
        "${local.ssm_arn_prefix}/chainlit/sonarqube-token"
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
      var.app_s3_bucket_arn,
      "${var.app_s3_bucket_arn}/*"
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

    resources = [var.efs_arn]

    condition {
      test     = "StringEquals"
      variable = "elasticfilesystem:AccessPointArn"
      values = concat(
        [var.efs_access_point_grafana_arn],
        var.enable_qdrant ? [var.efs_access_point_qdrant_arn] : []
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
# ECS Task Role - Cross-Account AssumeRole (MCP AWS spoke access)
# -----------------------------------------------------------------------------
# MCP AWS server runs in the ecs_task role (mcp-servers task), NOT chainlit_task.
# It needs sts:AssumeRole to query spoke accounts (RDS, ECS, CloudWatch, etc.)
# Created via CLI on 2026-04-10 as emergency fix; now codified in IaC.
resource "aws_iam_role_policy" "ecs_task_cross_account" {
  count = length(var.spoke_account_ids) > 0 ? 1 : 0

  name = "${local.name_prefix}-mcp-cross-account-policy"
  role = aws_iam_role.ecs_task.id

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

# -----------------------------------------------------------------------------
# ECS Task Role - Hub-account read-only (MCP AWS enxergar a propria conta)
# -----------------------------------------------------------------------------
# A conta hub (111111111111) usa creds base (sem assume) no _get_client do MCP
# AWS (docker/mcp-aws/server.py:78); spokes ja tem read amplo. Sem este bloco a
# task role so tinha cloudwatch/logs read (datasource Grafana) -> AG-5 cego pra
# ecs/rds/ce/elasticache da propria conta hub (AccessDenied no teste 2026-06-02,
# confirmado por simulate-principal-policy). Apenas Describe/List/Get read-only:
# sem mutacao, sem leitura de dados/segredos (nada de secretsmanager/s3:GetObject).
resource "aws_iam_role_policy" "ecs_task_hub_readonly" {
  name = "${local.name_prefix}-mcp-hub-readonly-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "HubReadOnlyObservability"
        Effect = "Allow"
        Action = [
          "ecs:Describe*", "ecs:List*",
          "rds:Describe*", "rds:ListTagsForResource",
          "elasticache:Describe*", "elasticache:List*",
          "ce:Get*", "ce:Describe*", "ce:List*",
          "lambda:List*", "lambda:GetFunction", "lambda:GetFunctionConfiguration",
          "sqs:ListQueues", "sqs:GetQueueAttributes",
          "sns:List*", "sns:GetTopicAttributes",
          "cognito-idp:List*", "cognito-idp:Describe*",
          "elasticloadbalancing:Describe*",
          "acm:List*", "acm:Describe*",
          "route53:List*", "route53:Get*",
          "wafv2:List*", "wafv2:Get*",
          "cloudfront:List*", "cloudfront:Get*",
          "states:List*", "states:Describe*",
          "application-autoscaling:Describe*",
          "autoscaling:Describe*"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# ECS Task Role - Bedrock Policy (LiteLLM → Titan Embed v2 para RAG)
# -----------------------------------------------------------------------------
# Claude SEMPRE via Anthropic API direto (ANTHROPIC_API_KEY).
# Bedrock usado APENAS para Titan Embeddings (RAG) via LiteLLM proxy.
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
  count = 1 # Always enabled — Bedrock used for Titan embeddings only

  name   = "${local.name_prefix}-ecs-task-bedrock-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_bedrock.json
}

# -----------------------------------------------------------------------------
# ECS Task Role - Skills S3 Policy (AG-5 Agent Skills read)
# -----------------------------------------------------------------------------
# Inline policy anexada à role transversal ecs_task (mora em build/skills.tf).
# O bucket dono (module.skills_bucket) fica no build → resolvido por var.skills_bucket_id.
data "aws_iam_policy_document" "ecs_task_skills_s3" {
  statement {
    sid     = "AG5SkillsRead"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${var.skills_bucket_id}",
      "arn:aws:s3:::${var.skills_bucket_id}/*",
    ]
  }
}

resource "aws_iam_role_policy" "ecs_task_skills_s3" {
  name   = "${local.name_prefix}-ecs-task-skills-s3-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_skills_s3.json
}
