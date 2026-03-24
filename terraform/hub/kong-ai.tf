# -----------------------------------------------------------------------------
# Kong AI Gateway — PII Removal + AI Observability + Rate Limiting
# -----------------------------------------------------------------------------
# Proxy: chainlit-chat → Kong AI → LiteLLM
# Plugins: pii-removal (custom), prometheus, rate-limiting, correlation-id
# Feature flag: var.enable_kong_ai (default: false)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------
locals {
  kong_ai_declarative_config = yamlencode({
    _format_version = "3.0"
    _transform      = true

    services = [
      {
        name            = "litellm-ai"
        url             = "http://litellm.${var.cloudmap_namespace}:4000"
        protocol        = "http"
        connect_timeout = 60000
        write_timeout   = 120000
        read_timeout    = 120000
        retries         = 2

        routes = [
          {
            name          = "ai-v1"
            paths         = ["/v1"]
            strip_path    = false
            preserve_host = false
            protocols     = ["http", "https"]
          }
        ]
      }
    ]

    plugins = [
      {
        name = "pii-removal"
        config = {
          enabled_patterns = {
            cpf_masked  = true
            cpf_raw     = true
            email       = true
            credit_card = true
            phone       = true
          }
        }
      },
      {
        name = "prometheus"
        config = {
          per_consumer        = true
          status_code_metrics = true
          latency_metrics     = true
          bandwidth_metrics   = true
        }
      },
      {
        name = "rate-limiting"
        config = {
          minute = 60
          policy = "local"
        }
      },
      {
        name = "correlation-id"
        config = {
          header_name     = "X-Correlation-ID"
          generator       = "uuid"
          echo_downstream = true
        }
      },
      {
        name = "file-log"
        config = {
          path   = "/dev/stdout"
          reopen = true
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "kong_ai" {
  count = var.enable_kong_ai ? 1 : 0

  name              = "/ecs/${local.name_prefix}/kong-ai"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-kong-ai-logs"
  })
}

# -----------------------------------------------------------------------------
# ECR Repository
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "kong_ai" {
  count = var.enable_kong_ai ? 1 : 0

  name                 = "obs-hub/kong-ai"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-kong-ai-ecr"
  })
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "kong_ai" {
  count = var.enable_kong_ai ? 1 : 0

  family                   = "${local.name_prefix}-kong-ai"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "kong-ai"
      image     = "${aws_ecr_repository.kong_ai[0].repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        },
        {
          containerPort = 8001
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "KONG_DATABASE", value = "off" },
        { name = "KONG_PROXY_LISTEN", value = "0.0.0.0:8000" },
        { name = "KONG_ADMIN_LISTEN", value = "0.0.0.0:8001" },
        { name = "KONG_PROXY_ACCESS_LOG", value = "/dev/stdout" },
        { name = "KONG_PROXY_ERROR_LOG", value = "/dev/stderr" },
        { name = "KONG_ADMIN_ACCESS_LOG", value = "/dev/stdout" },
        { name = "KONG_ADMIN_ERROR_LOG", value = "/dev/stderr" },
        { name = "KONG_LOG_LEVEL", value = "info" },
        { name = "KONG_PLUGINS", value = "bundled,pii-removal" },
        { name = "KONG_DECLARATIVE_CONFIG_STRING", value = local.kong_ai_declarative_config },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.kong_ai[0].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "kong-ai"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "kong health"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-kong-ai"
  })
}

# -----------------------------------------------------------------------------
# ALB Target Group
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "kong_ai" {
  count = var.enable_kong_ai ? 1 : 0

  name        = "${local.name_prefix}-kong-ai-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/status"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-kong-ai-tg"
  })
}

# -----------------------------------------------------------------------------
# ALB Listener Rule (host_header: ai.tower.yourorg.com.br)
# -----------------------------------------------------------------------------
resource "aws_lb_listener_rule" "kong_ai" {
  count = var.enable_kong_ai ? 1 : 0

  listener_arn = aws_lb_listener.https.arn
  priority     = 120

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kong_ai[0].arn
  }

  condition {
    host_header {
      values = ["ai.${var.domain_name}"]
    }
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-kong-ai-rule"
  })
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------
resource "aws_security_group" "kong_ai" {
  count = var.enable_kong_ai ? 1 : 0

  name        = "${local.name_prefix}-kong-ai-sg"
  description = "Security group for Kong AI Gateway"
  vpc_id      = local.vpc_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-kong-ai-sg"
  })
}

# Ingress: ALB → Kong AI (proxy port 8000)
resource "aws_security_group_rule" "kong_ai_from_alb" {
  count = var.enable_kong_ai ? 1 : 0

  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.kong_ai[0].id
  source_security_group_id = module.alb_sg.id
  description              = "Allow ALB to Kong AI proxy"
}

# Egress: Kong AI → LiteLLM (port 4000 via ECS tasks SG)
resource "aws_security_group_rule" "kong_ai_to_litellm" {
  count = var.enable_kong_ai ? 1 : 0

  type                     = "egress"
  from_port                = 4000
  to_port                  = 4000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.kong_ai[0].id
  source_security_group_id = module.ecs_tasks_sg.id
  description              = "Allow Kong AI to reach LiteLLM"
}

# Egress: Kong AI → DNS (UDP 53 for CloudMap resolution)
resource "aws_security_group_rule" "kong_ai_dns" {
  count = var.enable_kong_ai ? 1 : 0

  type              = "egress"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  security_group_id = aws_security_group.kong_ai[0].id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow DNS resolution (CloudMap)"
}

# Ingress: ECS tasks (chainlit) → Kong AI (allow internal access on 8000)
resource "aws_security_group_rule" "kong_ai_from_ecs" {
  count = var.enable_kong_ai ? 1 : 0

  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.kong_ai[0].id
  source_security_group_id = module.ecs_tasks_sg.id
  description              = "Allow ECS tasks (chainlit) to Kong AI"
}

# Ingress on LiteLLM SG: allow Kong AI → LiteLLM
resource "aws_security_group_rule" "litellm_from_kong_ai" {
  count = var.enable_kong_ai ? 1 : 0

  type                     = "ingress"
  from_port                = 4000
  to_port                  = 4000
  protocol                 = "tcp"
  security_group_id        = module.ecs_tasks_sg.id
  source_security_group_id = aws_security_group.kong_ai[0].id
  description              = "Allow Kong AI to reach LiteLLM"
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "kong_ai" {
  count = var.enable_kong_ai ? 1 : 0

  name            = "${local.name_prefix}-kong-ai"
  cluster         = module.ecs_cluster.cluster_id
  task_definition = aws_ecs_task_definition.kong_ai[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  enable_execute_command = true
  force_new_deployment   = true

  health_check_grace_period_seconds = 60

  network_configuration {
    subnets         = local.private_subnet_ids
    security_groups = [aws_security_group.kong_ai[0].id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.kong_ai[0].arn
    container_name   = "kong-ai"
    container_port   = 8000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-kong-ai"
  })

  depends_on = [
    aws_lb_listener_rule.kong_ai,
    aws_cloudwatch_log_group.kong_ai,
  ]
}

# -----------------------------------------------------------------------------
# Route53 — ai.tower.yourorg.com.br
# -----------------------------------------------------------------------------
resource "aws_route53_record" "kong_ai" {
  count = var.enable_kong_ai ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = "ai.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb.lb_dns_name
    zone_id                = module.alb.lb_zone_id
    evaluate_target_health = true
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "kong_ai_url" {
  description = "URL do Kong AI Gateway"
  value       = var.enable_kong_ai ? "https://ai.${var.domain_name}" : null
}

output "kong_ai_internal_url" {
  description = "URL interna do Kong AI Gateway (para chainlit-chat)"
  value       = var.enable_kong_ai ? "http://kong-ai.${var.cloudmap_namespace}:8000" : null
}
