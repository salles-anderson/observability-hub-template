# -----------------------------------------------------------------------------
# K6 Self-Service Portal
# -----------------------------------------------------------------------------
# Portal para QAs e Tech Leads executarem testes de carga de forma autônoma
# Componentes: API Gateway + Lambda + Step Functions + DynamoDB
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Feature Flag
# -----------------------------------------------------------------------------
# Ativar com enable_k6_selfservice = true no terraform.tfvars

# -----------------------------------------------------------------------------
# DynamoDB - Histórico de Testes
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "k6_results" {
  count = var.enable_k6 ? 1 : 0

  name         = "${local.name_prefix}-k6-results"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "test_id"

  attribute {
    name = "test_id"
    type = "S"
  }

  attribute {
    name = "project"
    type = "S"
  }

  attribute {
    name = "started_at"
    type = "S"
  }

  global_secondary_index {
    name            = "project-started_at-index"
    hash_key        = "project"
    range_key       = "started_at"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-k6-results"
  })
}

# -----------------------------------------------------------------------------
# Lambda Function - K6 Executor
# -----------------------------------------------------------------------------
data "archive_file" "k6_executor" {
  count = var.enable_k6 ? 1 : 0

  type        = "zip"
  source_dir  = "${path.module}/lambda/k6-executor"
  output_path = "${path.module}/lambda/k6-executor.zip"
}

resource "aws_lambda_function" "k6_executor" {
  count = var.enable_k6 ? 1 : 0

  function_name = "${local.name_prefix}-k6-executor"
  role          = aws_iam_role.k6_lambda[0].arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.k6_executor[0].output_path
  source_code_hash = data.archive_file.k6_executor[0].output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER_NAME   = module.ecs_cluster.cluster_id
      K6_TASK_DEFINITION = var.enable_k6 ? aws_ecs_task_definition.k6[0].arn : ""
      SUBNETS            = join(",", local.private_subnet_ids)
      SECURITY_GROUPS    = module.ecs_tasks_sg.id
      SCRIPTS_BUCKET     = module.s3_bucket.bucket_id
      RESULTS_TABLE      = var.enable_k6 ? aws_dynamodb_table.k6_results[0].name : ""
    }
  }

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [module.ecs_tasks_sg.id]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-k6-executor"
  })
}

# -----------------------------------------------------------------------------
# IAM Role - Lambda
# -----------------------------------------------------------------------------
resource "aws_iam_role" "k6_lambda" {
  count = var.enable_k6 ? 1 : 0

  name = "${local.name_prefix}-k6-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-k6-lambda-role"
  })
}

resource "aws_iam_role_policy" "k6_lambda" {
  count = var.enable_k6 ? 1 : 0

  name = "${local.name_prefix}-k6-lambda-policy"
  role = aws_iam_role.k6_lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSRunTask"
        Effect = "Allow"
        Action = [
          "ecs:RunTask",
          "ecs:DescribeTasks",
          "ecs:StopTask"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "ecs:cluster" = module.ecs_cluster.cluster_arn
          }
        }
      },
      {
        Sid    = "PassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          aws_iam_role.ecs_task_execution.arn,
          var.enable_k6 ? aws_iam_role.k6_task[0].arn : aws_iam_role.ecs_task.arn
        ]
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:HeadObject"
        ]
        Resource = [
          module.s3_bucket.bucket_arn,
          "${module.s3_bucket.bucket_arn}/k6-scripts/*"
        ]
      },
      {
        Sid    = "DynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = var.enable_k6 ? [
          aws_dynamodb_table.k6_results[0].arn,
          "${aws_dynamodb_table.k6_results[0].arn}/index/*"
        ] : []
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:*"
      },
      {
        Sid    = "VPCAccess"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# API Gateway - REST API
# -----------------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "k6" {
  count = var.enable_k6 ? 1 : 0

  name        = "${local.name_prefix}-k6-api"
  description = "K6 Load Testing Self-Service API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-k6-api"
  })
}

# /tests resource
resource "aws_api_gateway_resource" "tests" {
  count = var.enable_k6 ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.k6[0].id
  parent_id   = aws_api_gateway_rest_api.k6[0].root_resource_id
  path_part   = "tests"
}

# POST /tests - Executar teste
resource "aws_api_gateway_method" "post_tests" {
  count = var.enable_k6 ? 1 : 0

  rest_api_id   = aws_api_gateway_rest_api.k6[0].id
  resource_id   = aws_api_gateway_resource.tests[0].id
  http_method   = "POST"
  authorization = "NONE" # TODO: Adicionar Cognito/IAM auth
}

resource "aws_api_gateway_integration" "post_tests" {
  count = var.enable_k6 ? 1 : 0

  rest_api_id             = aws_api_gateway_rest_api.k6[0].id
  resource_id             = aws_api_gateway_resource.tests[0].id
  http_method             = aws_api_gateway_method.post_tests[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.k6_executor[0].invoke_arn
}

# /tests/validate resource
resource "aws_api_gateway_resource" "validate" {
  count = var.enable_k6 ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.k6[0].id
  parent_id   = aws_api_gateway_resource.tests[0].id
  path_part   = "validate"
}

# POST /tests/validate - Validar teste
resource "aws_api_gateway_method" "post_validate" {
  count = var.enable_k6 ? 1 : 0

  rest_api_id   = aws_api_gateway_rest_api.k6[0].id
  resource_id   = aws_api_gateway_resource.validate[0].id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post_validate" {
  count = var.enable_k6 ? 1 : 0

  rest_api_id             = aws_api_gateway_rest_api.k6[0].id
  resource_id             = aws_api_gateway_resource.validate[0].id
  http_method             = aws_api_gateway_method.post_validate[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.k6_executor[0].invoke_arn

  request_templates = {
    "application/json" = jsonencode({
      action = "validate"
    })
  }
}

# /projects resource
resource "aws_api_gateway_resource" "projects" {
  count = var.enable_k6 ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.k6[0].id
  parent_id   = aws_api_gateway_rest_api.k6[0].root_resource_id
  path_part   = "projects"
}

# GET /projects - Listar projetos
resource "aws_api_gateway_method" "get_projects" {
  count = var.enable_k6 ? 1 : 0

  rest_api_id   = aws_api_gateway_rest_api.k6[0].id
  resource_id   = aws_api_gateway_resource.projects[0].id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_projects" {
  count = var.enable_k6 ? 1 : 0

  rest_api_id             = aws_api_gateway_rest_api.k6[0].id
  resource_id             = aws_api_gateway_resource.projects[0].id
  http_method             = aws_api_gateway_method.get_projects[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.k6_executor[0].invoke_arn

  request_templates = {
    "application/json" = jsonencode({
      action = "list_projects"
    })
  }
}

# CORS
resource "aws_api_gateway_method" "options_tests" {
  count = var.enable_k6 ? 1 : 0

  rest_api_id   = aws_api_gateway_rest_api.k6[0].id
  resource_id   = aws_api_gateway_resource.tests[0].id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_tests" {
  count = var.enable_k6 ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.k6[0].id
  resource_id = aws_api_gateway_resource.tests[0].id
  http_method = aws_api_gateway_method.options_tests[0].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_tests" {
  count = var.enable_k6 ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.k6[0].id
  resource_id = aws_api_gateway_resource.tests[0].id
  http_method = aws_api_gateway_method.options_tests[0].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_tests" {
  count = var.enable_k6 ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.k6[0].id
  resource_id = aws_api_gateway_resource.tests[0].id
  http_method = aws_api_gateway_method.options_tests[0].http_method
  status_code = aws_api_gateway_method_response.options_tests[0].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Deploy
resource "aws_api_gateway_deployment" "k6" {
  count = var.enable_k6 ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.k6[0].id

  depends_on = [
    aws_api_gateway_integration.post_tests,
    aws_api_gateway_integration.post_validate,
    aws_api_gateway_integration.get_projects
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "k6" {
  count = var.enable_k6 ? 1 : 0

  deployment_id = aws_api_gateway_deployment.k6[0].id
  rest_api_id   = aws_api_gateway_rest_api.k6[0].id
  stage_name    = var.environment

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-k6-api-stage"
  })
}

# Lambda Permission
resource "aws_lambda_permission" "api_gateway" {
  count = var.enable_k6 ? 1 : 0

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.k6_executor[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.k6[0].execution_arn}/*/*"
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group - Lambda
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "k6_lambda" {
  count = var.enable_k6 ? 1 : 0

  name              = "/aws/lambda/${local.name_prefix}-k6-executor"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-k6-lambda-logs"
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "k6_api_endpoint" {
  description = "Endpoint da API K6 Self-Service"
  value       = var.enable_k6 ? "${aws_api_gateway_stage.k6[0].invoke_url}" : null
}

output "k6_api_usage" {
  description = "Exemplos de uso da API K6"
  value       = var.enable_k6 ? local.k6_api_usage : null
}

locals {
  k6_api_usage = <<-EOT
    # ==========================================================================
    # K6 Self-Service API - Guia de Uso
    # ==========================================================================

    ## Endpoint Base
    ${var.enable_k6 ? aws_api_gateway_stage.k6[0].invoke_url : "N/A"}

    ## 1. Listar Projetos Disponíveis
    curl -X GET ${var.enable_k6 ? aws_api_gateway_stage.k6[0].invoke_url : "API_URL"}/projects

    ## 2. Validar Teste (sem executar)
    curl -X POST ${var.enable_k6 ? aws_api_gateway_stage.k6[0].invoke_url : "API_URL"}/tests/validate \
      -H "Content-Type: application/json" \
      -d '{
        "project": "example-api",
        "environment": "dev",
        "test_type": "smoke",
        "user_email": "qa@yourorg.com.br",
        "user_role": "qa"
      }'

    ## 3. Executar Teste
    curl -X POST ${var.enable_k6 ? aws_api_gateway_stage.k6[0].invoke_url : "API_URL"}/tests \
      -H "Content-Type: application/json" \
      -d '{
        "project": "example-api",
        "environment": "dev",
        "test_type": "load",
        "user_email": "qa@yourorg.com.br",
        "user_role": "qa",
        "target_url": "https://api.example-api.dev.yourorg.com.br"
      }'

    ## 4. Executar com VUs customizados
    curl -X POST ${var.enable_k6 ? aws_api_gateway_stage.k6[0].invoke_url : "API_URL"}/tests \
      -H "Content-Type: application/json" \
      -d '{
        "project": "example-api",
        "environment": "homolog",
        "test_type": "stress",
        "user_email": "techlead@yourorg.com.br",
        "user_role": "tech_lead",
        "vus": 150,
        "duration": "20m"
      }'

    ## Limites por Ambiente
    | Ambiente | Max VUs | Max Duração | Testes Permitidos     | Aprovação |
    |----------|---------|-------------|----------------------|-----------|
    | dev      | 100     | 30min       | smoke,load,stress,soak| Não       |
    | homolog  | 200     | 60min       | smoke,load,stress,soak| Não       |
    | prod     | 50      | 15min       | smoke                 | Sim       |

    ## Dashboard de Resultados
    https://grafana.observability.tower.yourorg.com.br/d/k6-results
  EOT
}
