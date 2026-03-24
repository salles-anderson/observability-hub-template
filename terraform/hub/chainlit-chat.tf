# -----------------------------------------------------------------------------
# Chainlit Chat — Teck Observability Assistant
# -----------------------------------------------------------------------------
# ECS Fargate task com container chainlit-chat (Python/Chainlit + Agent SDK)
# porta 8501, exposto via ALB em assistant.tower.yourorg.com.br
# Agent SDK usa LiteLLM + RAG (Qdrant) + tools diretos (boto3, GitHub, TFC)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "chainlit_chat" {
  count = var.enable_chainlit ? 1 : 0

  name              = "/ecs/${local.name_prefix}/chainlit-chat"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-chainlit-chat-logs"
  })
}

# -----------------------------------------------------------------------------
# ALB Target Group
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "chainlit_chat" {
  count = var.enable_chainlit ? 1 : 0

  name        = "${local.name_prefix}-chainlit-tg"
  port        = 8501
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  # Stickiness for WebSocket support (Chainlit uses Socket.IO)
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-chainlit-tg"
  })
}

# -----------------------------------------------------------------------------
# ALB Listener Rule
# -----------------------------------------------------------------------------
resource "aws_lb_listener_rule" "chainlit_chat" {
  count = var.enable_chainlit ? 1 : 0

  listener_arn = aws_lb_listener.https.arn
  priority     = 130

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.chainlit_chat[0].arn
  }

  condition {
    host_header {
      values = ["assistant.${var.domain_name}"]
    }
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-chainlit-rule"
  })
}

# -----------------------------------------------------------------------------
# SSM Parameter — Chainlit Auth Secret
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "chainlit_auth_secret" {
  count = var.enable_chainlit ? 1 : 0

  name        = "/${local.name_prefix}/chainlit/auth-secret"
  description = "Chainlit authentication secret for session management"
  type        = "SecureString"
  value       = random_password.chainlit_auth.result
  key_id      = module.kms.key_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-chainlit-auth-secret"
  })
}

resource "random_password" "chainlit_auth" {
  length  = 64
  special = false
}

# -----------------------------------------------------------------------------
# ECS Task Definition — Chainlit Chat + mcp-grafana sidecar
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "chainlit_chat" {
  count = var.enable_chainlit ? 1 : 0

  family                   = "${local.name_prefix}-chainlit-chat"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.chainlit_cpu
  memory                   = var.chainlit_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.chainlit_task[0].arn

  container_definitions = jsonencode([for c in [
    local.fluent_bit_container,
    {
      name      = "chainlit-chat"
      image     = "${local.ecr_prefix}/chainlit-chat:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8501
          hostPort      = 8501
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "ECS_CLUSTER", value = var.ecs_cluster_name },
        { name = "GRAFANA_URL", value = "https://grafana.${var.domain_name}" },
        { name = "OAUTH_COGNITO_CLIENT_ID", value = aws_cognito_user_pool_client.chainlit[0].id },
        { name = "OAUTH_COGNITO_DOMAIN", value = "${aws_cognito_user_pool_domain.chainlit[0].domain}.auth.us-east-1.amazoncognito.com" },
        { name = "CHAINLIT_URL", value = "https://assistant.${var.domain_name}" },
        { name = "TFC_ORG", value = "YOUR_ORG" },
        { name = "QDRANT_URL", value = var.enable_qdrant ? "http://qdrant.${var.cloudmap_namespace}:6333" : "" },
        { name = "LITELLM_URL", value = "http://litellm.${var.cloudmap_namespace}:4000" },
        { name = "RAG_ENABLED", value = var.enable_qdrant ? "true" : "false" },
        { name = "SPOKE_ACCOUNT_IDS", value = jsonencode(var.spoke_account_ids) },
        { name = "SPOKE_ROLE_NAME", value = var.spoke_role_name },
        { name = "CROSS_ACCOUNT_EXTERNAL_ID", value = var.cross_account_external_id },
        { name = "AGENT_VERSION", value = var.chainlit_agent_version },
        { name = "SONARQUBE_URL", value = "http://sonarqube.${var.cloudmap_namespace}:9000" },
        { name = "KONG_AI_URL", value = var.enable_kong_ai ? "http://kong-ai.${var.cloudmap_namespace}:8000/v1" : "" },
        { name = "ENABLE_ALERT_INVESTIGATION", value = var.enable_alert_investigation ? "true" : "false" },
        { name = "SLACK_ALERT_CHANNEL", value = "#observability-alerts" },
        { name = "SLACK_BOT_TOKEN", value = var.slack_bot_token },
        # MCP Server URLs (sidecars on localhost)
        { name = "MCP_GRAFANA_URL", value = "http://localhost:8000" },
        { name = "MCP_AWS_URL", value = "http://localhost:8001" },
        { name = "MCP_GITHUB_URL", value = "http://localhost:8002" },
        { name = "MCP_TFC_URL", value = "http://localhost:8003" },
        { name = "MCP_QDRANT_URL", value = "http://localhost:8004" },
      ]

      secrets = concat(
        [
          {
            name      = "CHAINLIT_AUTH_SECRET"
            valueFrom = aws_ssm_parameter.chainlit_auth_secret[0].arn
          },
          {
            name      = "OAUTH_COGNITO_CLIENT_SECRET"
            valueFrom = aws_ssm_parameter.cognito_client_secret[0].arn
          },
        ],
        var.enable_agent_sdk ? [
          {
            name      = "ANTHROPIC_API_KEY"
            valueFrom = aws_ssm_parameter.anthropic_api_key_agent[0].arn
          },
          {
            name      = "GRAFANA_API_KEY"
            valueFrom = aws_ssm_parameter.grafana_sa_token[0].arn
          },
        ] : [],
        var.tfc_api_token != "" ? [
          {
            name      = "TFC_API_TOKEN"
            valueFrom = aws_ssm_parameter.tfc_api_token[0].arn
          },
        ] : [],
        var.github_token_obs_hub != "" ? [
          {
            name      = "GITHUB_TOKEN"
            valueFrom = aws_ssm_parameter.github_token[0].arn
          },
        ] : [],
        var.sonarqube_token != "" ? [
          {
            name      = "SONARQUBE_TOKEN"
            valueFrom = aws_ssm_parameter.sonarqube_token[0].arn
          },
        ] : [],
      )

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          "Name"        = "loki"
          "Host"        = "loki.observability.local"
          "Port"        = "3100"
          "labels"      = "job=containerd, container=chainlit-chat"
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
        command     = ["CMD-SHELL", "curl -f http://localhost:8501/ || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    },
    # -----------------------------------------------------------------
    # MCP Sidecar: mcp-aws (AG-5 — infra, finops, security tools)
    # -----------------------------------------------------------------
    {
      name      = "mcp-aws"
      image     = "${local.ecr_prefix}/mcp-aws:latest"
      essential = false

      portMappings = [{ containerPort = 8001, hostPort = 8001, protocol = "tcp" }]

      environment = [
        { name = "AWS_REGION", value = var.aws_region },
        { name = "SPOKE_ROLE_NAME", value = var.spoke_role_name },
        { name = "CROSS_ACCOUNT_EXTERNAL_ID", value = var.cross_account_external_id },
        { name = "SPOKE_ACCOUNT_IDS", value = jsonencode(var.spoke_account_ids) },
      ]

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          "Name" = "loki", "Host" = "loki.observability.local", "Port" = "3100"
          "labels" = "job=containerd, container=mcp-aws", "line_format" = "json"
        }
      }

      dependsOn = [{ containerName = "log-router", condition = "START" }]

      healthCheck = {
        command = ["CMD-SHELL", "python3 -c \"import socket; s=socket.create_connection(('localhost',8001),2); s.close()\""]
        interval = 30, timeout = 5, retries = 3, startPeriod = 15
      }
    },
    # -----------------------------------------------------------------
    # MCP Sidecar: mcp-github (AG-5 — code, PRs, SonarQube)
    # -----------------------------------------------------------------
    {
      name      = "mcp-github"
      image     = "${local.ecr_prefix}/mcp-github:latest"
      essential = false

      portMappings = [{ containerPort = 8002, hostPort = 8002, protocol = "tcp" }]

      environment = [
        { name = "GITHUB_ORG", value = "YOUR_ORG" },
        { name = "SONARQUBE_URL", value = "http://sonarqube.${var.cloudmap_namespace}:9000" },
      ]

      secrets = concat(
        var.github_token_obs_hub != "" ? [
          { name = "GITHUB_TOKEN", valueFrom = aws_ssm_parameter.github_token[0].arn },
        ] : [],
        var.sonarqube_token != "" ? [
          { name = "SONARQUBE_TOKEN", valueFrom = aws_ssm_parameter.sonarqube_token[0].arn },
        ] : [],
      )

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          "Name" = "loki", "Host" = "loki.observability.local", "Port" = "3100"
          "labels" = "job=containerd, container=mcp-github", "line_format" = "json"
        }
      }

      dependsOn = [{ containerName = "log-router", condition = "START" }]

      healthCheck = {
        command = ["CMD-SHELL", "python3 -c \"import socket; s=socket.create_connection(('localhost',8002),2); s.close()\""]
        interval = 30, timeout = 5, retries = 3, startPeriod = 15
      }
    },
    # -----------------------------------------------------------------
    # MCP Sidecar: mcp-tfc (AG-5 — Terraform Cloud)
    # -----------------------------------------------------------------
    {
      name      = "mcp-tfc"
      image     = "${local.ecr_prefix}/mcp-tfc:latest"
      essential = false

      portMappings = [{ containerPort = 8003, hostPort = 8003, protocol = "tcp" }]

      environment = [
        { name = "TFC_ORG", value = "YOUR_ORG" },
      ]

      secrets = concat(
        var.tfc_api_token != "" ? [
          { name = "TFC_API_TOKEN", valueFrom = aws_ssm_parameter.tfc_api_token[0].arn },
        ] : [],
      )

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          "Name" = "loki", "Host" = "loki.observability.local", "Port" = "3100"
          "labels" = "job=containerd, container=mcp-tfc", "line_format" = "json"
        }
      }

      dependsOn = [{ containerName = "log-router", condition = "START" }]

      healthCheck = {
        command = ["CMD-SHELL", "python3 -c \"import socket; s=socket.create_connection(('localhost',8003),2); s.close()\""]
        interval = 30, timeout = 5, retries = 3, startPeriod = 15
      }
    },
    # -----------------------------------------------------------------
    # MCP Sidecar: mcp-qdrant (AG-5 — RAG + semantic cache)
    # -----------------------------------------------------------------
    {
      name      = "mcp-qdrant"
      image     = "${local.ecr_prefix}/mcp-qdrant:latest"
      essential = false

      portMappings = [{ containerPort = 8004, hostPort = 8004, protocol = "tcp" }]

      environment = [
        { name = "QDRANT_URL", value = var.enable_qdrant ? "http://qdrant.${var.cloudmap_namespace}:6333" : "" },
        { name = "LITELLM_URL", value = "http://litellm.${var.cloudmap_namespace}:4000" },
      ]

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          "Name" = "loki", "Host" = "loki.observability.local", "Port" = "3100"
          "labels" = "job=containerd, container=mcp-qdrant", "line_format" = "json"
        }
      }

      dependsOn = [{ containerName = "log-router", condition = "START" }]

      healthCheck = {
        command = ["CMD-SHELL", "python3 -c \"import socket; s=socket.create_connection(('localhost',8004),2); s.close()\""]
        interval = 30, timeout = 5, retries = 3, startPeriod = 15
      }
    },
    # -----------------------------------------------------------------
    # MCP Sidecar: mcp-grafana (AG-5 — Prometheus, Loki, Tempo, dashboards)
    # -----------------------------------------------------------------
    {
      name      = "mcp-grafana"
      image     = "${local.ecr_prefix}/mcp-grafana:v0.11.0"
      essential = false

      portMappings = [{ containerPort = 8000, hostPort = 8000, protocol = "tcp" }]

      environment = [
        { name = "GRAFANA_URL", value = "https://grafana.${var.domain_name}" },
        { name = "GRAFANA_API_KEY", value = var.grafana_service_account_token },
      ]

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          "Name" = "loki", "Host" = "loki.observability.local", "Port" = "3100"
          "labels" = "job=containerd, container=mcp-grafana", "line_format" = "json"
        }
      }

      dependsOn = [{ containerName = "log-router", condition = "START" }]

      healthCheck = {
        command = ["CMD-SHELL", "wget -q --spider --timeout=2 http://localhost:8000/sse 2>/dev/null; exit 0"]
        interval = 30, timeout = 5, retries = 3, startPeriod = 15
      }
    },
    # -----------------------------------------------------------------
    # MCP Sidecar: mcp-confluence (AG-5 — Confluence API for documentation)
    # -----------------------------------------------------------------
    var.confluence_api_token != "" ? {
      name      = "mcp-confluence"
      image     = "${local.ecr_prefix}/mcp-confluence:latest"
      essential = false

      portMappings = [{ containerPort = 8005, hostPort = 8005, protocol = "tcp" }]

      environment = [
        { name = "CONFLUENCE_URL", value = "https://yourorg.atlassian.net" },
        { name = "CONFLUENCE_EMAIL", value = "anderson.sales@yourorg.com.br" },
        { name = "CONFLUENCE_TOKEN", value = var.confluence_api_token },
      ]

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          "Name" = "loki", "Host" = "loki.observability.local", "Port" = "3100"
          "labels" = "job=containerd, container=mcp-confluence", "line_format" = "json"
        }
      }

      dependsOn = [{ containerName = "log-router", condition = "START" }]

      healthCheck = {
        command = ["CMD-SHELL", "python3 -c \"import socket; s=socket.create_connection(('localhost',8005),2); s.close()\""]
        interval = 30, timeout = 5, retries = 3, startPeriod = 15
      }
    } : null,
    # -----------------------------------------------------------------
    # MCP Sidecar: mcp-eraser (AG-5 — DiagramGPT for architecture diagrams)
    # -----------------------------------------------------------------
    var.eraser_api_token != "" ? {
      name      = "mcp-eraser"
      image     = "${local.ecr_prefix}/mcp-eraser:latest"
      essential = false

      portMappings = [{ containerPort = 8006, hostPort = 8006, protocol = "tcp" }]

      environment = [
        { name = "ERASER_API_TOKEN", value = var.eraser_api_token },
      ]

      logConfiguration = {
        logDriver = "awsfirelens"
        options = {
          "Name" = "loki", "Host" = "loki.observability.local", "Port" = "3100"
          "labels" = "job=containerd, container=mcp-eraser", "line_format" = "json"
        }
      }

      dependsOn = [{ containerName = "log-router", condition = "START" }]

      healthCheck = {
        command = ["CMD-SHELL", "python3 -c \"import socket; s=socket.create_connection(('localhost',8006),2); s.close()\""]
        interval = 30, timeout = 5, retries = 3, startPeriod = 15
      }
    } : null
  ] : c if c != null])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-chainlit-chat"
  })
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "chainlit_chat" {
  count = var.enable_chainlit ? 1 : 0

  name            = "${local.name_prefix}-chainlit-chat"
  cluster         = module.ecs_cluster.cluster_id
  task_definition = aws_ecs_task_definition.chainlit_chat[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  enable_execute_command = true
  force_new_deployment   = true

  health_check_grace_period_seconds = 60

  network_configuration {
    subnets         = local.private_subnet_ids
    security_groups = [module.ecs_tasks_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.chainlit_chat[0].arn
    container_name   = "chainlit-chat"
    container_port   = 8501
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-chainlit-chat"
  })

  depends_on = [
    aws_lb_listener_rule.chainlit_chat,
    aws_cloudwatch_log_group.chainlit_chat,
  ]
}

# -----------------------------------------------------------------------------
# Route53 — assistant.tower.yourorg.com.br
# -----------------------------------------------------------------------------
resource "aws_route53_record" "chainlit_chat" {
  count = var.enable_chainlit ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = "assistant.${var.domain_name}"
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
output "chainlit_chat_url" {
  description = "URL publica do Teck Observability Assistant"
  value       = var.enable_chainlit ? "https://assistant.${var.domain_name}" : null
}
