# -----------------------------------------------------------------------------
# EFS Access Point - Grafana
# -----------------------------------------------------------------------------
resource "aws_efs_access_point" "grafana" {
  file_system_id = aws_efs_file_system.this[0].id

  root_directory {
    path = "/grafana"
    creation_info {
      owner_gid   = 472
      owner_uid   = 472
      permissions = "0755"
    }
  }

  posix_user {
    gid = 472
    uid = 472
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-grafana-ap"
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group - Grafana
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/${local.name_prefix}/grafana"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-grafana-logs"
  })
}

# -----------------------------------------------------------------------------
# Target Group - Grafana
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "grafana" {
  name        = "${local.name_prefix}-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/api/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-grafana-tg"
  })
}

# -----------------------------------------------------------------------------
# ALB Listener Rule - Grafana
# -----------------------------------------------------------------------------
resource "aws_lb_listener_rule" "grafana" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    host_header {
      values = ["grafana.${var.domain_name}"]
    }
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-grafana-rule"
  })
}

# -----------------------------------------------------------------------------
# ECS Task Definition - Grafana
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "grafana" {
  family                   = "${local.name_prefix}-grafana"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.grafana_cpu
  memory                   = var.grafana_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  volume {
    name = "grafana-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.this[0].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.grafana.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    local.fluent_bit_container,
    {
      name      = "grafana"
      image     = local.images.grafana
      essential = true

      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = concat([
        {
          name  = "GF_SERVER_ROOT_URL"
          value = "https://grafana.${var.domain_name}"
        },
        {
          name  = "GF_SERVER_DOMAIN"
          value = "grafana.${var.domain_name}"
        },
        {
          name  = "GF_DATABASE_TYPE"
          value = "postgres"
        },
        {
          name  = "GF_DATABASE_HOST"
          value = "${module.rds_observability.writer_endpoint}:${module.rds_observability.port}"
        },
        {
          name  = "GF_DATABASE_NAME"
          value = "db_obs_prod"
        },
        {
          name  = "GF_DATABASE_USER"
          value = "admindbprod"
        },
        {
          name  = "GF_DATABASE_SSL_MODE"
          value = "require"
        },
        {
          name  = "GF_USERS_ALLOW_SIGN_UP"
          value = "false"
        },
        {
          name  = "GF_USERS_ALLOW_ORG_CREATE"
          value = "false"
        },
        {
          name  = "GF_AUTH_DISABLE_LOGIN_FORM"
          value = "false"
        },
        # ----- Branding: Remove Grafana default elements -----
        {
          name  = "GF_HELP_ENABLED"
          value = "false"
        },
        {
          name  = "GF_NEWS_NEWS_FEED_ENABLED"
          value = "false"
        },
        {
          name  = "GF_ANALYTICS_REPORTING_ENABLED"
          value = "false"
        },
        {
          name  = "GF_ANALYTICS_CHECK_FOR_UPDATES"
          value = "false"
        },
        {
          name  = "GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES"
          value = "false"
        }
      ], var.enable_grafana_llm ? [
        {
          name  = "GF_INSTALL_PLUGINS"
          value = "grafana-llm-app,yesoreyeram-infinity-datasource,marcusolsson-dynamictext-panel"
        },
        {
          name  = "GF_FEATURE_TOGGLES_ENABLE"
          value = "dashgpt,genAIForDashboard"
        }
      ] : [])

      secrets = [
        {
          name      = "GF_DATABASE_PASSWORD"
          valueFrom = aws_ssm_parameter.observability_db_password.arn
        },
        {
          name      = "GF_SECURITY_ADMIN_PASSWORD"
          valueFrom = aws_ssm_parameter.grafana_admin_password.arn
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "grafana-data"
          containerPath = "/var/lib/grafana"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          "Name"        = "loki"
          "Host"        = "loki.observability.local"
          "Port"        = "3100"
          "labels"      = "job=containerd, container=grafana"
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
        command     = ["CMD-SHELL", "wget -q --spider http://localhost:3000/api/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-grafana-task"
  })
}

# -----------------------------------------------------------------------------
# ECS Service - Grafana
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "grafana" {
  name                               = "${local.name_prefix}-grafana"
  cluster                            = module.ecs_cluster.cluster_id
  task_definition                    = aws_ecs_task_definition.grafana.arn
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

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "grafana"
    container_port   = 3000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["grafana"].arn
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-grafana-service"
  })

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_lb_listener.https,
    aws_lb_listener_rule.grafana,
    aws_efs_access_point.grafana,
    module.rds_observability
  ]
}
