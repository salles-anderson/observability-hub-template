# -----------------------------------------------------------------------------
# K6 - Load Testing Platform
# -----------------------------------------------------------------------------
# Sprint 11: Plataforma de testes de carga integrada ao observability hub
# Executa testes sob demanda via ECS Tasks
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Feature Flag - Habilitar K6
# -----------------------------------------------------------------------------
# Descomente enable_k6 = true no terraform.tfvars para ativar

# -----------------------------------------------------------------------------
# CloudWatch Log Group - K6
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "k6" {
  count = var.enable_k6 ? 1 : 0

  name              = "/ecs/${local.name_prefix}/k6"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-k6-logs"
  })
}

# -----------------------------------------------------------------------------
# IAM Role - K6 Task Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "k6_task" {
  count = var.enable_k6 ? 1 : 0

  name = "${local.name_prefix}-k6-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-k6-task-role"
  })
}

# Policy para K6 acessar S3 (scripts de teste)
resource "aws_iam_role_policy" "k6_s3" {
  count = var.enable_k6 ? 1 : 0

  name = "${local.name_prefix}-k6-s3-policy"
  role = aws_iam_role.k6_task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.s3_bucket.bucket_arn,
          "${module.s3_bucket.bucket_arn}/k6-scripts/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = [
          "${module.s3_bucket.bucket_arn}/k6-results/*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# ECS Task Definition - K6
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "k6" {
  count = var.enable_k6 ? 1 : 0

  family                   = "${local.name_prefix}-k6"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.k6_cpu
  memory                   = var.k6_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.k6_task[0].arn

  container_definitions = jsonencode([
    {
      name      = "k6"
      image     = local.images.k6
      essential = true

      environment = [
        # Prometheus Remote Write Output
        {
          name  = "K6_PROMETHEUS_RW_SERVER_URL"
          value = "http://prometheus.${var.cloudmap_namespace}:9090/api/v1/write"
        },
        {
          name  = "K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM"
          value = "true"
        },
        {
          name  = "K6_PROMETHEUS_RW_TREND_STATS"
          value = "p(95),p(99),min,max,avg"
        },
        # Tags padrao
        {
          name  = "K6_TAGS"
          value = "environment=${var.environment},cluster=${local.name_prefix}"
        },
        # S3 para scripts
        {
          name  = "K6_SCRIPTS_BUCKET"
          value = module.s3_bucket.bucket_id
        },
        {
          name  = "K6_SCRIPTS_PREFIX"
          value = "k6-scripts/"
        },
        {
          name  = "K6_RESULTS_PREFIX"
          value = "k6-results/"
        }
      ]

      # Comando padrao - sera sobrescrito via task overrides
      command = ["run", "--out", "experimental-prometheus-rw", "/scripts/default.js"]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.k6[0].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "k6"
        }
      }
    }
  ])

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-k6-task"
  })
}

# -----------------------------------------------------------------------------
# EventBridge Rule - Scheduled Load Tests (Opcional)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "k6_scheduled" {
  count = var.enable_k6 && var.k6_scheduled_tests ? 1 : 0

  name                = "${local.name_prefix}-k6-scheduled"
  description         = "Executa testes de carga agendados"
  schedule_expression = var.k6_schedule_expression

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-k6-scheduled-rule"
  })
}

resource "aws_cloudwatch_event_target" "k6_scheduled" {
  count = var.enable_k6 && var.k6_scheduled_tests ? 1 : 0

  rule      = aws_cloudwatch_event_rule.k6_scheduled[0].name
  target_id = "k6-scheduled-test"
  arn       = module.ecs_cluster.cluster_arn
  role_arn  = aws_iam_role.eventbridge_ecs[0].arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.k6[0].arn
    launch_type         = "FARGATE"
    platform_version    = "LATEST"

    network_configuration {
      subnets          = local.private_subnet_ids
      security_groups  = [module.ecs_tasks_sg.id]
      assign_public_ip = false
    }
  }

  input = jsonencode({
    containerOverrides = [
      {
        name    = "k6"
        command = ["run", "--out", "experimental-prometheus-rw", "/scripts/smoke-test.js"]
      }
    ]
  })
}

# IAM Role para EventBridge executar ECS Tasks
resource "aws_iam_role" "eventbridge_ecs" {
  count = var.enable_k6 && var.k6_scheduled_tests ? 1 : 0

  name = "${local.name_prefix}-eventbridge-ecs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eventbridge-ecs-role"
  })
}

resource "aws_iam_role_policy" "eventbridge_ecs" {
  count = var.enable_k6 && var.k6_scheduled_tests ? 1 : 0

  name = "${local.name_prefix}-eventbridge-ecs-policy"
  role = aws_iam_role.eventbridge_ecs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecs:RunTask"
        Resource = aws_ecs_task_definition.k6[0].arn
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [
          aws_iam_role.ecs_task_execution.arn,
          aws_iam_role.k6_task[0].arn
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "k6_task_definition_arn" {
  description = "ARN da task definition K6"
  value       = var.enable_k6 ? aws_ecs_task_definition.k6[0].arn : null
}

output "k6_scripts_bucket_path" {
  description = "Path S3 para upload de scripts K6"
  value       = var.enable_k6 ? "s3://${module.s3_bucket.bucket_id}/k6-scripts/" : null
}

output "k6_run_command" {
  description = "Comando para executar teste K6 manualmente"
  value       = var.enable_k6 ? local.k6_run_command : null
}

output "k6_usage_guide" {
  description = "Guia de uso do K6"
  value       = var.enable_k6 ? local.k6_usage_guide : null
}

locals {
  k6_run_command = <<-EOT
    # Executar teste K6 via AWS CLI:
    aws ecs run-task \
      --cluster ${module.ecs_cluster.cluster_id} \
      --task-definition ${local.name_prefix}-k6 \
      --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[${join(",", local.private_subnet_ids)}],securityGroups=[${module.ecs_tasks_sg.id}],assignPublicIp=DISABLED}" \
      --overrides '{
        "containerOverrides": [{
          "name": "k6",
          "command": ["run", "--out", "experimental-prometheus-rw", "/scripts/seu-teste.js"],
          "environment": [
            {"name": "TARGET_URL", "value": "https://api.exemplo.com"},
            {"name": "ENVIRONMENT", "value": "dev"}
          ]
        }]
      }'
  EOT

  k6_usage_guide = <<-EOT
    # ==========================================================================
    # K6 - Guia de Uso
    # ==========================================================================

    ## 1. Upload de Scripts

    # Upload script para S3:
    aws s3 cp meu-teste.js s3://${module.s3_bucket.bucket_id}/k6-scripts/

    ## 2. Executar Teste

    # Via AWS CLI:
    aws ecs run-task \
      --cluster ${module.ecs_cluster.cluster_id} \
      --task-definition ${local.name_prefix}-k6 \
      --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[SUBNET_ID],securityGroups=[SG_ID],assignPublicIp=DISABLED}" \
      --overrides '{
        "containerOverrides": [{
          "name": "k6",
          "command": ["run", "--out", "experimental-prometheus-rw", "s3://${module.s3_bucket.bucket_id}/k6-scripts/meu-teste.js"]
        }]
      }'

    ## 3. Visualizar Resultados

    # Metricas disponiveis no Prometheus:
    - k6_http_req_duration_seconds (histogram)
    - k6_http_reqs_total (counter)
    - k6_vus (gauge)
    - k6_iterations_total (counter)

    # Dashboard Grafana:
    - Importar dashboard ID: 18030 (K6 Load Testing Results)

    ## 4. Exemplo de Script

    ```javascript
    import http from 'k6/http';
    import { check, sleep } from 'k6';

    export const options = {
      stages: [
        { duration: '1m', target: 10 },
        { duration: '3m', target: 50 },
        { duration: '1m', target: 0 },
      ],
      thresholds: {
        http_req_duration: ['p(95)<500'],
        http_req_failed: ['rate<0.01'],
      },
    };

    export default function () {
      const res = http.get(__ENV.TARGET_URL + '/health');
      check(res, {
        'status is 200': (r) => r.status === 200,
      });
      sleep(1);
    }
    ```
  EOT
}
