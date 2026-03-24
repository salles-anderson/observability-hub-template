# -----------------------------------------------------------------------------
# ECS Task Definition - Loki
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "loki" {
  family                   = "${local.name_prefix}-loki"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.loki_cpu
  memory                   = var.loki_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "loki"
      image     = local.images.loki
      essential = true

      portMappings = [
        {
          containerPort = 3100
          hostPort      = 3100
          protocol      = "tcp"
        },
        {
          containerPort = 9096
          hostPort      = 9096
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "LOKI_CONFIG_BASE64"
          value = base64encode(file("${path.module}/configs/loki-config.yaml"))
        }
      ]

      entryPoint = ["/bin/sh", "-c"]
      command = [
        "mkdir -p /loki/index /loki/cache /loki/compactor && echo $LOKI_CONFIG_BASE64 | base64 -d > /etc/loki/local-config.yaml && /usr/bin/loki -config.file=/etc/loki/local-config.yaml"
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.services["loki"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "loki"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget -q --spider http://localhost:3100/ready || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-loki-task"
  })
}

# -----------------------------------------------------------------------------
# ECS Service - Loki
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "loki" {
  name                               = "${local.name_prefix}-loki"
  cluster                            = module.ecs_cluster.cluster_id
  task_definition                    = aws_ecs_task_definition.loki.arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  enable_execute_command             = true
  force_new_deployment               = true
  health_check_grace_period_seconds  = 120
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [module.ecs_tasks_sg.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["loki"].arn
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-loki-service"
  })

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_cloudwatch_log_group.services
  ]
}
