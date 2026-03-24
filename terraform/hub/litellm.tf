# -----------------------------------------------------------------------------
# LiteLLM Proxy - AI Platform (Sprint 1 AI Platform)
# -----------------------------------------------------------------------------
# Multi-provider proxy: Sonnet 4.6 + Gemini 2.5 Pro + DeepSeek V3
# Redis cache for response deduplication.
# Acesso via Cloud Map: litellm.observability.local:4000
# Acesso externo via Kong: /ai/v1/* (WAF IP restricted)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# CloudWatch Log Group - LiteLLM
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "litellm" {
  count = var.enable_grafana_llm ? 1 : 0

  name              = "/ecs/${local.name_prefix}/litellm"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-litellm-logs"
  })
}

# -----------------------------------------------------------------------------
# ECS Task Definition - LiteLLM
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "litellm" {
  count = var.enable_grafana_llm ? 1 : 0

  family                   = "${local.name_prefix}-litellm"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.litellm_cpu
  memory                   = var.litellm_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    local.fluent_bit_container,
    {
      name      = "litellm"
      image     = local.images.litellm
      essential = true

      portMappings = [
        {
          containerPort = 4000
          hostPort      = 4000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "LITELLM_CONFIG"
          value = base64encode(file("${path.module}/configs/litellm-config.yaml"))
        },
        {
          name  = "REDIS_HOST"
          value = module.litellm_redis[0].primary_endpoint
        }
      ]

      secrets = concat([
        {
          name      = "ANTHROPIC_API_KEY"
          valueFrom = aws_ssm_parameter.anthropic_api_key[0].arn
        },
        {
          name      = "GEMINI_API_KEY"
          valueFrom = aws_ssm_parameter.gemini_api_key[0].arn
        }
      ], var.deepseek_api_key != "" ? [
        {
          name      = "DEEPSEEK_API_KEY"
          valueFrom = aws_ssm_parameter.deepseek_api_key[0].arn
        }
      ] : [])

      entryPoint = ["/bin/sh", "-c"]
      command = [
        "echo $LITELLM_CONFIG | base64 -d > /app/config.yaml && litellm --config /app/config.yaml --host 0.0.0.0 --port 4000"
      ]

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          "Name"        = "loki"
          "Host"        = "loki.observability.local"
          "Port"        = "3100"
          "labels"      = "job=containerd, container=litellm"
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
        command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:4000/health/liveliness')\" || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 90
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-litellm-task"
  })
}

# -----------------------------------------------------------------------------
# ECS Service - LiteLLM
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "litellm" {
  count = var.enable_grafana_llm ? 1 : 0

  name                               = "${local.name_prefix}-litellm"
  cluster                            = module.ecs_cluster.cluster_id
  task_definition                    = aws_ecs_task_definition.litellm[0].arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  enable_execute_command             = true
  force_new_deployment               = true
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [module.ecs_tasks_sg.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["litellm"].arn
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-litellm-service"
  })

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_cloudwatch_log_group.litellm
  ]
}
