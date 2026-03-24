# -----------------------------------------------------------------------------
# Qdrant - Vector Store for RAG Runbooks (Sprint S11)
# -----------------------------------------------------------------------------
# Porta 6333: HTTP REST API (usado pelo qdrant-client Python)
# Porta 6334: gRPC (compatibilidade)
# Acesso via Cloud Map: qdrant.observability.local:6333
# Persistencia: EFS /qdrant (access point UID 1000)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "qdrant" {
  count = var.enable_qdrant ? 1 : 0

  name              = "/ecs/${local.name_prefix}/qdrant"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-qdrant-logs"
  })
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "qdrant" {
  count = var.enable_qdrant ? 1 : 0

  family                   = "${local.name_prefix}-qdrant"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.qdrant_cpu
  memory                   = var.qdrant_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  volume {
    name = "qdrant-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.this[0].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.qdrant[0].id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    local.fluent_bit_container,
    {
      name      = "qdrant"
      image     = local.images.qdrant
      essential = true

      portMappings = [
        {
          containerPort = 6333
          hostPort      = 6333
          protocol      = "tcp"
        },
        {
          containerPort = 6334
          hostPort      = 6334
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "QDRANT__STORAGE__STORAGE_PATH", value = "/qdrant/storage" },
        { name = "QDRANT__SERVICE__HTTP_PORT", value = "6333" },
        { name = "QDRANT__SERVICE__GRPC_PORT", value = "6334" },
        { name = "QDRANT__LOG_LEVEL", value = "INFO" }
      ]

      mountPoints = [
        {
          sourceVolume  = "qdrant-data"
          containerPath = "/qdrant/storage"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          "Name"        = "loki"
          "Host"        = "loki.observability.local"
          "Port"        = "3100"
          "labels"      = "job=containerd, container=qdrant"
          "line_format" = "json"
        }
      }

      dependsOn = [
        { containerName = "log-router", condition = "START" }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "bash -c 'echo > /dev/tcp/localhost/6333' || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-qdrant-task"
  })
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "qdrant" {
  count = var.enable_qdrant ? 1 : 0

  name                               = "${local.name_prefix}-qdrant"
  cluster                            = module.ecs_cluster.cluster_id
  task_definition                    = aws_ecs_task_definition.qdrant[0].arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  enable_execute_command             = true
  force_new_deployment               = true
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [module.ecs_tasks_sg.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["qdrant"].arn
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-qdrant-service"
  })

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_efs_access_point.qdrant,
    aws_cloudwatch_log_group.qdrant
  ]
}
