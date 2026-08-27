# -----------------------------------------------------------------------------
# ECS Task Definition - Prometheus
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "prometheus" {
  family                   = "${local.name_prefix}-prometheus"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.prometheus_cpu
  memory                   = var.prometheus_memory
  execution_role_arn       = local.security.ecs_task_execution_role_arn
  task_role_arn            = local.security.ecs_task_role_arn

  volume {
    name = "prometheus-data"

    efs_volume_configuration {
      file_system_id     = local.data.efs_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = local.data.efs_ap_prometheus_id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "prometheus"
      image     = local.images.prometheus
      essential = true

      portMappings = [
        {
          containerPort = 9090
          hostPort      = 9090
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "PROMETHEUS_CONFIG_BASE64"
          value = base64encode(file("${path.module}/configs/prometheus.yml"))
        },
        {
          name  = "PROMETHEUS_RULES_BASE64"
          value = base64encode(file("${path.module}/configs/prometheus-rules.yml"))
        }
      ]

      entryPoint = ["/bin/sh", "-c"]
      command = [
        "mkdir -p /etc/prometheus/rules && echo $PROMETHEUS_CONFIG_BASE64 | base64 -d > /etc/prometheus/prometheus.yml && echo $PROMETHEUS_RULES_BASE64 | base64 -d > /etc/prometheus/rules/slo-rules.yml && /bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=${var.prometheus_retention_days}d --storage.tsdb.no-lockfile --web.enable-lifecycle --web.enable-admin-api --web.enable-remote-write-receiver"
      ]

      mountPoints = [
        {
          sourceVolume  = "prometheus-data"
          containerPath = "/prometheus"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${local.name_prefix}/prometheus"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "prometheus"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget -q --spider http://localhost:9090/-/healthy || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-prometheus-task"
  })
}

# -----------------------------------------------------------------------------
# ECS Service - Prometheus
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "prometheus" {
  name                               = "${local.name_prefix}-prometheus"
  cluster                            = local.network.ecs_cluster_id
  task_definition                    = aws_ecs_task_definition.prometheus.arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  enable_execute_command             = true
  force_new_deployment               = true
  health_check_grace_period_seconds  = 120
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 0

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [local.security.ecs_tasks_sg_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = local.network.service_discovery_services["prometheus"].arn
  }

  # Load balancer para Metric Streams (HTTPS para Firehose)
  dynamic "load_balancer" {
    for_each = var.enable_metric_streams ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.prometheus[0].arn
      container_name   = "prometheus"
      container_port   = 9090
    }
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-prometheus-service"
  })

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_cloudwatch_log_group.services
  ]
}
