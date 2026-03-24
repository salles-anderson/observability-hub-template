# -----------------------------------------------------------------------------
# SSM Automation Documents - Runbooks Basicos (Sprint 5)
# -----------------------------------------------------------------------------
# 3 runbooks para remediacao basica de incidentes ECS:
#   1. restart-ecs-service: force new deployment
#   2. scale-ecs-service: scale to desired count
#   3. collect-diagnostics: coleta logs, task status e metricas
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# IAM Role for SSM Automation
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ssm_automation" {
  count = var.enable_aiops ? 1 : 0

  name = "${local.name_prefix}-ssm-automation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-ssm-automation-role"
  })
}

resource "aws_iam_role_policy" "ssm_automation" {
  count = var.enable_aiops ? 1 : 0

  name = "${local.name_prefix}-ssm-automation-policy"
  role = aws_iam_role.ssm_automation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSAccess"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:ListTasks",
          "ecs:DescribeTasks"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = var.account_id
          }
        }
      },
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:*"
      },
      {
        Sid    = "S3DiagnosticsWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::${local.name_prefix}-diagnostics/*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# 1. Restart ECS Service (Force New Deployment)
# -----------------------------------------------------------------------------
resource "aws_ssm_document" "restart_ecs_service" {
  count = var.enable_aiops ? 1 : 0

  name            = "${local.name_prefix}-restart-ecs-service"
  document_type   = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Restart ECS service by forcing a new deployment"
    assumeRole    = aws_iam_role.ssm_automation[0].arn
    parameters = {
      ClusterName = {
        type        = "String"
        description = "ECS Cluster name"
      }
      ServiceName = {
        type        = "String"
        description = "ECS Service name"
      }
    }
    mainSteps = [
      {
        name   = "ForceNewDeployment"
        action = "aws:executeAwsApi"
        inputs = {
          Service = "ecs"
          Api     = "UpdateService"
          cluster = "{{ ClusterName }}"
          service = "{{ ServiceName }}"
          forceNewDeployment = true
        }
        outputs = [
          {
            Name     = "ServiceArn"
            Selector = "$.service.serviceArn"
            Type     = "String"
          }
        ]
      },
      {
        name      = "WaitForStableService"
        action    = "aws:waitForAwsResourceProperty"
        timeoutSeconds = 300
        inputs = {
          Service          = "ecs"
          Api              = "DescribeServices"
          cluster          = "{{ ClusterName }}"
          services         = ["{{ ServiceName }}"]
          PropertySelector = "$.services[0].deployments[0].rolloutState"
          DesiredValues    = ["COMPLETED"]
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-restart-ecs-service"
  })
}

# -----------------------------------------------------------------------------
# 2. Scale ECS Service
# -----------------------------------------------------------------------------
resource "aws_ssm_document" "scale_ecs_service" {
  count = var.enable_aiops ? 1 : 0

  name            = "${local.name_prefix}-scale-ecs-service"
  document_type   = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Scale ECS service to desired count"
    assumeRole    = aws_iam_role.ssm_automation[0].arn
    parameters = {
      ClusterName = {
        type        = "String"
        description = "ECS Cluster name"
      }
      ServiceName = {
        type        = "String"
        description = "ECS Service name"
      }
      DesiredCount = {
        type        = "Integer"
        description = "Desired number of tasks"
      }
    }
    mainSteps = [
      {
        name   = "GetCurrentState"
        action = "aws:executeAwsApi"
        inputs = {
          Service  = "ecs"
          Api      = "DescribeServices"
          cluster  = "{{ ClusterName }}"
          services = ["{{ ServiceName }}"]
        }
        outputs = [
          {
            Name     = "CurrentDesiredCount"
            Selector = "$.services[0].desiredCount"
            Type     = "Integer"
          },
          {
            Name     = "CurrentRunningCount"
            Selector = "$.services[0].runningCount"
            Type     = "Integer"
          }
        ]
      },
      {
        name   = "ScaleService"
        action = "aws:executeAwsApi"
        inputs = {
          Service      = "ecs"
          Api          = "UpdateService"
          cluster      = "{{ ClusterName }}"
          service      = "{{ ServiceName }}"
          desiredCount = "{{ DesiredCount }}"
        }
      },
      {
        name      = "WaitForScaling"
        action    = "aws:waitForAwsResourceProperty"
        timeoutSeconds = 300
        inputs = {
          Service          = "ecs"
          Api              = "DescribeServices"
          cluster          = "{{ ClusterName }}"
          services         = ["{{ ServiceName }}"]
          PropertySelector = "$.services[0].runningCount"
          DesiredValues    = ["{{ DesiredCount }}"]
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-scale-ecs-service"
  })
}

# -----------------------------------------------------------------------------
# 3. Collect Diagnostics
# -----------------------------------------------------------------------------
resource "aws_ssm_document" "collect_diagnostics" {
  count = var.enable_aiops ? 1 : 0

  name            = "${local.name_prefix}-collect-diagnostics"
  document_type   = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Collect diagnostics from ECS service (task status, recent logs)"
    assumeRole    = aws_iam_role.ssm_automation[0].arn
    parameters = {
      ClusterName = {
        type        = "String"
        description = "ECS Cluster name"
      }
      ServiceName = {
        type        = "String"
        description = "ECS Service name"
      }
    }
    mainSteps = [
      {
        name   = "ListTasks"
        action = "aws:executeAwsApi"
        inputs = {
          Service     = "ecs"
          Api         = "ListTasks"
          cluster     = "{{ ClusterName }}"
          serviceName = "{{ ServiceName }}"
        }
        outputs = [
          {
            Name     = "TaskArns"
            Selector = "$.taskArns"
            Type     = "StringList"
          }
        ]
      },
      {
        name   = "DescribeTasks"
        action = "aws:executeAwsApi"
        inputs = {
          Service = "ecs"
          Api     = "DescribeTasks"
          cluster = "{{ ClusterName }}"
          tasks   = "{{ ListTasks.TaskArns }}"
        }
        outputs = [
          {
            Name     = "TaskDetails"
            Selector = "$.tasks"
            Type     = "MapList"
          }
        ]
      },
      {
        name   = "DescribeService"
        action = "aws:executeAwsApi"
        inputs = {
          Service  = "ecs"
          Api      = "DescribeServices"
          cluster  = "{{ ClusterName }}"
          services = ["{{ ServiceName }}"]
        }
        outputs = [
          {
            Name     = "ServiceDetails"
            Selector = "$.services[0]"
            Type     = "StringMap"
          }
        ]
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-collect-diagnostics"
  })
}
