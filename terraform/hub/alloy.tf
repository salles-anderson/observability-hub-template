# -----------------------------------------------------------------------------
# CloudWatch Log Group - Alloy
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "alloy" {
  name              = "/ecs/${local.name_prefix}/alloy"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alloy-logs"
  })
}

# -----------------------------------------------------------------------------
# ECS Task Definition - Alloy (substitui OTel Collector)
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "alloy" {
  family                   = "${local.name_prefix}-alloy"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.alloy_cpu
  memory                   = var.alloy_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "alloy"
      image     = local.images.alloy
      essential = true

      portMappings = [
        {
          containerPort = 4317
          hostPort      = 4317
          protocol      = "tcp"
        },
        {
          containerPort = 4318
          hostPort      = 4318
          protocol      = "tcp"
        },
        {
          containerPort = 12345
          hostPort      = 12345
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "ALLOY_CONFIG"
          value = base64encode(file("${path.module}/configs/alloy-config.alloy"))
        }
      ]

      entryPoint = ["/bin/sh", "-c"]
      command = [
        "apt-get update -qq && apt-get install -y -qq wget >/dev/null 2>&1; echo $ALLOY_CONFIG | base64 -d > /etc/alloy/config.alloy && /bin/alloy run --server.http.listen-addr=0.0.0.0:12345 --storage.path=/var/lib/alloy/data /etc/alloy/config.alloy"
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${local.name_prefix}/alloy"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "alloy"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget -q --spider http://localhost:12345/-/ready || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 120
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alloy-task"
  })
}

# -----------------------------------------------------------------------------
# ECS Service - Alloy
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "alloy" {
  name                               = "${local.name_prefix}-alloy"
  cluster                            = module.ecs_cluster.cluster_id
  task_definition                    = aws_ecs_task_definition.alloy.arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  enable_execute_command             = true
  force_new_deployment               = true
  health_check_grace_period_seconds  = 60
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [module.ecs_tasks_sg.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["otel"].arn
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alloy-service"
  })

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_cloudwatch_log_group.alloy,
    aws_ecs_service.loki,
    aws_ecs_service.tempo
  ]
}
