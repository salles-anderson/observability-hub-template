# -----------------------------------------------------------------------------
# EFS Access Point - Grafana
# -----------------------------------------------------------------------------
# Migrado para o workspace hub-foundation-data (decomposicao strangler).
# Consumido read-only via local.data.efs_ap_grafana_id / efs_ap_grafana_arn.
# Ver remote-state-foundation.tf.

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
  listener_arn = local.edge.https_listener_arn
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
  execution_role_arn       = local.security.ecs_task_execution_role_arn
  task_role_arn            = local.security.ecs_task_role_arn

  volume {
    name = "grafana-data"

    efs_volume_configuration {
      file_system_id     = local.data.efs_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = local.data.efs_ap_grafana_id
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
          value = "${local.data.rds_cluster_endpoint}:${local.data.rds_port}"
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

      # ⚠️ valueFrom = ARN LITERAL (mesma classe do firelens LG / hardcodes vpc-subnet).
      # Os 2 SSM SecureString de senha (observability_db_password = GF_DATABASE_PASSWORD,
      # grafana_admin_password = GF_SECURITY_ADMIN_PASSWORD) sao secrets de-escopados:
      # PERMANECEM no workspace build (build/secrets.tf) — NAO migram para o lgtm
      # (decisao do gabarito §Exclusoes / plan S4 linhas 137,275). Para evitar
      # dependencia cross-ws REVERSA (lgtm -> build), referenciamos os ARNs por string
      # literal deterministica — identica ao que aws_ssm_parameter.X.arn produz no build
      # (mesmo padrao de ai-platform/iam.tf:183) — => import da task-def (L3) fecha no-op.
      secrets = [
        {
          name      = "GF_DATABASE_PASSWORD"
          valueFrom = "arn:aws:ssm:${var.aws_region}:${var.account_id}:parameter/${local.name_prefix}/observability/db-password"
        },
        {
          name      = "GF_SECURITY_ADMIN_PASSWORD"
          valueFrom = "arn:aws:ssm:${var.aws_region}:${var.account_id}:parameter/${local.name_prefix}/grafana/admin-password"
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
  cluster                            = local.network.ecs_cluster_id
  task_definition                    = aws_ecs_task_definition.grafana.arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  enable_execute_command             = true
  force_new_deployment               = true
  health_check_grace_period_seconds  = 60
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

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "grafana"
    container_port   = 3000
  }

  service_registries {
    registry_arn = local.network.service_discovery_services["grafana"].arn
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-grafana-service"
  })

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_lb_listener_rule.grafana
  ]
}
