# -----------------------------------------------------------------------------
# ECS Task Definition - AlertManager
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "alertmanager" {
  family                   = "${local.name_prefix}-alertmanager"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.alertmanager_cpu
  memory                   = var.alertmanager_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  volume {
    name = "alertmanager-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.this[0].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.alertmanager[0].id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    local.fluent_bit_container,
    {
      name      = "alertmanager"
      image     = local.images.alertmanager
      essential = true

      portMappings = [
        {
          containerPort = 9093
          hostPort      = 9093
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "ALERTMANAGER_CONFIG_BASE64"
          value = base64encode(templatefile("${path.module}/configs/alertmanager.yml.tpl", {
            slack_webhook_url = var.slack_webhook_url
            aiops_webhook_url = var.enable_alert_investigation ? "http://chainlit-chat.${var.cloudmap_namespace}:8501/api/alert-investigate" : (var.enable_aiops ? "${aws_apigatewayv2_api.alert_webhook[0].api_endpoint}/prod/v2/webhook/alertmanager" : "")
          }))
        }
      ]

      entryPoint = ["/bin/sh", "-c"]
      command = [
        "echo $ALERTMANAGER_CONFIG_BASE64 | base64 -d > /etc/alertmanager/alertmanager.yml && /bin/alertmanager --config.file=/etc/alertmanager/alertmanager.yml --storage.path=/alertmanager --web.external-url=https://grafana.observability.tower.yourorg.com.br --cluster.listen-address="
      ]

      mountPoints = [
        {
          sourceVolume  = "alertmanager-data"
          containerPath = "/alertmanager"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          "Name"        = "loki"
          "Host"        = "loki.observability.local"
          "Port"        = "3100"
          "labels"      = "job=containerd, container=alertmanager"
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
        command     = ["CMD-SHELL", "wget -q --spider http://localhost:9093/-/healthy || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alertmanager-task"
  })
}

# -----------------------------------------------------------------------------
# ECS Service - AlertManager
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "alertmanager" {
  name                               = "${local.name_prefix}-alertmanager"
  cluster                            = module.ecs_cluster.cluster_id
  task_definition                    = aws_ecs_task_definition.alertmanager.arn
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
    registry_arn = aws_service_discovery_service.services["alertmanager"].arn
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alertmanager-service"
  })

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_efs_access_point.alertmanager,
    aws_cloudwatch_log_group.services
  ]
}
