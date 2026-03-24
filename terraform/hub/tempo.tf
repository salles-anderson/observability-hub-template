# -----------------------------------------------------------------------------
# ECS Task Definition - Tempo
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "tempo" {
  family                   = "${local.name_prefix}-tempo"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.tempo_cpu
  memory                   = var.tempo_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  volume {
    name = "tempo-config"
  }

  volume {
    name = "tempo-data"
  }

  container_definitions = jsonencode([
    {
      name      = "config-init"
      image     = local.images.busybox
      essential = false

      command = [
        "/bin/sh", "-c",
        "echo '${base64encode(file("${path.module}/configs/tempo-config.yaml"))}' | base64 -d > /config/tempo.yaml && mkdir -p /data/wal /data/blocks /data/generator/wal"
      ]

      mountPoints = [
        {
          sourceVolume  = "tempo-config"
          containerPath = "/config"
          readOnly      = false
        },
        {
          sourceVolume  = "tempo-data"
          containerPath = "/data"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.services["tempo"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "tempo-init"
        }
      }
    },
    {
      name      = "tempo"
      image     = local.images.tempo
      essential = true

      dependsOn = [
        {
          containerName = "config-init"
          condition     = "SUCCESS"
        }
      ]

      portMappings = [
        {
          containerPort = 3200
          hostPort      = 3200
          protocol      = "tcp"
        },
        {
          containerPort = 4317
          hostPort      = 4317
          protocol      = "tcp"
        },
        {
          containerPort = 4318
          hostPort      = 4318
          protocol      = "tcp"
        }
      ]

      command = ["-config.file=/config/tempo.yaml"]

      mountPoints = [
        {
          sourceVolume  = "tempo-config"
          containerPath = "/config"
          readOnly      = true
        },
        {
          sourceVolume  = "tempo-data"
          containerPath = "/var/tempo"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.services["tempo"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "tempo"
        }
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-tempo-task"
  })
}

# -----------------------------------------------------------------------------
# ECS Service - Tempo
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "tempo" {
  name                               = "${local.name_prefix}-tempo"
  cluster                            = module.ecs_cluster.cluster_id
  task_definition                    = aws_ecs_task_definition.tempo.arn
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
    registry_arn = aws_service_discovery_service.services["tempo"].arn
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-tempo-service"
  })

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_cloudwatch_log_group.services
  ]
}
