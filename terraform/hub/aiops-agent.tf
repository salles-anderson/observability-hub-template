# -----------------------------------------------------------------------------
# AIOps Agent - ECS Task Definition + Service (Sprint 6B)
# -----------------------------------------------------------------------------
# ECS Fargate task com dois containers:
#   1. aiops-agent (Python/FastAPI + claude-agent-sdk) - porta 8080
#   2. mcp-grafana (Go/SSE server) - porta 8000 (internal)
# Agent SDK conecta ao mcp-grafana via SSE (localhost:8000)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# CloudWatch Log Groups
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "aiops_agent" {
  count = var.enable_agent_sdk ? 1 : 0

  name              = "/ecs/${local.name_prefix}/aiops-agent"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-aiops-agent-logs"
  })
}

resource "aws_cloudwatch_log_group" "mcp_grafana" {
  count = var.enable_agent_sdk ? 1 : 0

  name              = "/ecs/${local.name_prefix}/mcp-grafana"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-mcp-grafana-logs"
  })
}

# -----------------------------------------------------------------------------
# IAM Role - AIOps Agent Task Role (DynamoDB + SSM + CloudWatch)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "aiops_agent_task" {
  count = var.enable_agent_sdk ? 1 : 0

  name               = "${local.name_prefix}-aiops-agent-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-aiops-agent-task-role"
  })
}

resource "aws_iam_role_policy" "aiops_agent_task" {
  count = var.enable_agent_sdk ? 1 : 0

  name = "${local.name_prefix}-aiops-agent-task-policy"
  role = aws_iam_role.aiops_agent_task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBIncidents"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = var.enable_aiops ? [
          aws_dynamodb_table.incidents[0].arn,
          "${aws_dynamodb_table.incidents[0].arn}/index/*"
        ] : []
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/ecs/${local.name_prefix}/aiops-*"
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

# -----------------------------------------------------------------------------
# ECS Task Definition - AIOps Agent + mcp-grafana sidecar
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "aiops_agent" {
  count = var.enable_agent_sdk ? 1 : 0

  family                   = "${local.name_prefix}-aiops-agent"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.aiops_agent_cpu
  memory                   = var.aiops_agent_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.aiops_agent_task[0].arn

  container_definitions = jsonencode([
    local.fluent_bit_container,
    {
      name      = "aiops-agent"
      image     = local.images.aiops_agent
      essential = true

      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "MCP_GRAFANA_URL", value = "http://localhost:8000/sse" },
        { name = "GRAFANA_URL", value = "https://grafana.${var.domain_name}" },
        { name = "INCIDENTS_TABLE_NAME", value = var.enable_aiops ? aws_dynamodb_table.incidents[0].name : "" },
        { name = "SLACK_WEBHOOK_URL", value = var.slack_webhook_url },
        { name = "SLACK_SIGNING_SECRET", value = var.slack_signing_secret },
        { name = "SLACK_BOT_TOKEN", value = var.slack_bot_token },
        { name = "LITELLM_URL", value = "http://litellm.${var.cloudmap_namespace}:4000" },
        { name = "QDRANT_URL", value = "http://qdrant.${var.cloudmap_namespace}:6333" },
        { name = "COOLDOWN_MINUTES", value = "30" },
      ]

      secrets = [
        {
          name      = "ANTHROPIC_API_KEY"
          valueFrom = aws_ssm_parameter.anthropic_api_key_agent[0].arn
        }
      ]

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          "Name"        = "loki"
          "Host"        = "loki.observability.local"
          "Port"        = "3100"
          "labels"      = "job=containerd, container=aiops-agent"
          "line_format" = "json"
        }
      }

      dependsOn = [
        {
          containerName = "mcp-grafana"
          condition     = "HEALTHY"
        },
        {
          containerName = "log-router"
          condition     = "START"
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    },
    {
      name      = "mcp-grafana"
      image     = local.images.mcp_grafana
      essential = true

      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "GRAFANA_URL", value = "http://grafana.${var.cloudmap_namespace}:3000" },
      ]

      secrets = [
        {
          name      = "GRAFANA_API_KEY"
          valueFrom = aws_ssm_parameter.grafana_sa_token[0].arn
        }
      ]

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          "Name"        = "loki"
          "Host"        = "loki.observability.local"
          "Port"        = "3100"
          "labels"      = "job=containerd, container=mcp-grafana"
          "line_format" = "json"
        }
      }

      dependsOn = [
        {
          containerName = "log-router"
          condition     = "START"
        }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://localhost:8000/healthz || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-aiops-agent"
  })
}

# -----------------------------------------------------------------------------
# ECS Service - AIOps Agent
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "aiops_agent" {
  count = var.enable_agent_sdk ? 1 : 0

  name            = "${local.name_prefix}-aiops-agent"
  cluster         = module.ecs_cluster.cluster_id
  task_definition = aws_ecs_task_definition.aiops_agent[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  enable_execute_command = true
  force_new_deployment   = true

  network_configuration {
    subnets         = local.private_subnet_ids
    security_groups = [module.ecs_tasks_sg.id]
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.aiops_agent_apigw[0].arn
    container_name = "aiops-agent"
    container_port = 8080
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-aiops-agent"
  })
}

# -----------------------------------------------------------------------------
# API Gateway v2 - Routes para AIOps Agent (via VPC Link)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_vpc_link" "aiops_agent" {
  count = var.enable_agent_sdk && var.enable_aiops ? 1 : 0

  name               = "${local.name_prefix}-aiops-agent-vpclink"
  subnet_ids         = local.private_subnet_ids
  security_group_ids = [module.ecs_tasks_sg.id]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-aiops-agent-vpclink"
  })
}

resource "aws_apigatewayv2_integration" "aiops_agent" {
  count = var.enable_agent_sdk && var.enable_aiops ? 1 : 0

  api_id             = aws_apigatewayv2_api.alert_webhook[0].id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_service_discovery_service.aiops_agent_apigw[0].arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.aiops_agent[0].id

  request_parameters = {
    "overwrite:path" = "$request.path"
  }
}

resource "aws_apigatewayv2_route" "agent_webhook" {
  count = var.enable_agent_sdk && var.enable_aiops ? 1 : 0

  api_id    = aws_apigatewayv2_api.alert_webhook[0].id
  route_key = "POST /v2/webhook/alertmanager"
  target    = "integrations/${aws_apigatewayv2_integration.aiops_agent[0].id}"
}

resource "aws_apigatewayv2_route" "agent_query_assist" {
  count = var.enable_agent_sdk && var.enable_aiops ? 1 : 0

  api_id    = aws_apigatewayv2_api.alert_webhook[0].id
  route_key = "POST /v2/query-assist"
  target    = "integrations/${aws_apigatewayv2_integration.aiops_agent[0].id}"
}

resource "aws_apigatewayv2_route" "agent_incidents" {
  count = var.enable_agent_sdk && var.enable_aiops ? 1 : 0

  api_id    = aws_apigatewayv2_api.alert_webhook[0].id
  route_key = "GET /v2/incidents"
  target    = "integrations/${aws_apigatewayv2_integration.aiops_agent[0].id}"
}

resource "aws_apigatewayv2_route" "agent_postmortem" {
  count = var.enable_agent_sdk && var.enable_aiops ? 1 : 0

  api_id    = aws_apigatewayv2_api.alert_webhook[0].id
  route_key = "POST /v2/postmortem"
  target    = "integrations/${aws_apigatewayv2_integration.aiops_agent[0].id}"
}

resource "aws_apigatewayv2_route" "agent_war_room" {
  count = var.enable_agent_sdk && var.enable_aiops ? 1 : 0

  api_id    = aws_apigatewayv2_api.alert_webhook[0].id
  route_key = "POST /v2/war-room"
  target    = "integrations/${aws_apigatewayv2_integration.aiops_agent[0].id}"
}

resource "aws_apigatewayv2_route" "agent_slack_ask" {
  count = var.enable_agent_sdk && var.enable_aiops ? 1 : 0

  api_id    = aws_apigatewayv2_api.alert_webhook[0].id
  route_key = "POST /v2/slack-ask"
  target    = "integrations/${aws_apigatewayv2_integration.aiops_agent[0].id}"
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "aiops_agent_service" {
  description = "Nome do ECS service do AIOps Agent"
  value       = var.enable_agent_sdk ? aws_ecs_service.aiops_agent[0].name : null
}

output "aiops_agent_webhook_url" {
  description = "URL do webhook v2 do AIOps Agent"
  value       = var.enable_agent_sdk && var.enable_aiops ? "${aws_apigatewayv2_api.alert_webhook[0].api_endpoint}/prod/v2/webhook/alertmanager" : null
}

output "aiops_agent_query_assist_url" {
  description = "URL da API v2 Smart Query Assistant (Agent SDK)"
  value       = var.enable_agent_sdk && var.enable_aiops ? "${aws_apigatewayv2_api.alert_webhook[0].api_endpoint}/prod/v2/query-assist" : null
}

output "aiops_agent_slack_ask_url" {
  description = "URL para configurar no Slack como Request URL do slash command /ask-hub"
  value       = var.enable_agent_sdk && var.enable_aiops ? "${aws_apigatewayv2_api.alert_webhook[0].api_endpoint}/prod/v2/slack-ask" : null
}
