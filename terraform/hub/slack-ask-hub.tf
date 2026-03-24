# -----------------------------------------------------------------------------
# Slack /ask-hub — Lambda + API Gateway (Sprint Full Agent)
# -----------------------------------------------------------------------------
# Lambda recebe slash command /ask-hub do Slack, chama LiteLLM via VPC,
# e posta a resposta de volta no canal.
#
# Setup no Slack:
#   1. Criar Slack App em api.slack.com/apps
#   2. Adicionar Slash Command: /ask-hub → URL do API Gateway
#   3. Copiar Signing Secret → TFC var slack_signing_secret
#   4. Instalar app no workspace
# -----------------------------------------------------------------------------

variable "enable_slack_bot" {
  description = "Habilita o Slack /ask-hub bot (Lambda + API Gateway)"
  type        = bool
  default     = false
}

# slack_signing_secret and slack_bot_token declared in variables.tf

# -----------------------------------------------------------------------------
# Lambda Function
# -----------------------------------------------------------------------------
data "archive_file" "slack_ask_hub" {
  count       = var.enable_slack_bot ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/lambda/slack-ask-hub"
  output_path = "${path.module}/lambda/slack-ask-hub.zip"
}

resource "aws_lambda_function" "slack_ask_hub" {
  count = var.enable_slack_bot ? 1 : 0

  function_name = "${local.name_prefix}-slack-ask-hub"
  description   = "Slack /ask-hub slash command handler"
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.slack_ask_hub[0].output_path
  source_code_hash = data.archive_file.slack_ask_hub[0].output_base64sha256

  role = aws_iam_role.slack_ask_hub[0].arn

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [module.ecs_tasks_sg.id]
  }

  environment {
    variables = {
      SLACK_SIGNING_SECRET = var.slack_signing_secret
      SLACK_BOT_TOKEN      = var.slack_bot_token
      LITELLM_URL          = "http://litellm.${var.cloudmap_namespace}:4000"
    }
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-slack-ask-hub"
  })
}

# -----------------------------------------------------------------------------
# IAM Role for Lambda
# -----------------------------------------------------------------------------
resource "aws_iam_role" "slack_ask_hub" {
  count = var.enable_slack_bot ? 1 : 0

  name = "${local.name_prefix}-slack-ask-hub-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "slack_ask_hub_basic" {
  count      = var.enable_slack_bot ? 1 : 0
  role       = aws_iam_role.slack_ask_hub[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# -----------------------------------------------------------------------------
# API Gateway v2 (HTTP API)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "slack_ask_hub" {
  count = var.enable_slack_bot ? 1 : 0

  name          = "${local.name_prefix}-slack-ask-hub"
  protocol_type = "HTTP"
  description   = "Slack /ask-hub slash command endpoint"

  tags = local.tags
}

resource "aws_apigatewayv2_integration" "slack_ask_hub" {
  count = var.enable_slack_bot ? 1 : 0

  api_id                 = aws_apigatewayv2_api.slack_ask_hub[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.slack_ask_hub[0].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "slack_ask_hub" {
  count = var.enable_slack_bot ? 1 : 0

  api_id    = aws_apigatewayv2_api.slack_ask_hub[0].id
  route_key = "POST /slack/ask-hub"
  target    = "integrations/${aws_apigatewayv2_integration.slack_ask_hub[0].id}"
}

resource "aws_apigatewayv2_stage" "slack_ask_hub" {
  count = var.enable_slack_bot ? 1 : 0

  api_id      = aws_apigatewayv2_api.slack_ask_hub[0].id
  name        = "prod"
  auto_deploy = true

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Lambda Permission (API Gateway → Lambda)
# -----------------------------------------------------------------------------
resource "aws_lambda_permission" "slack_ask_hub" {
  count = var.enable_slack_bot ? 1 : 0

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_ask_hub[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.slack_ask_hub[0].execution_arn}/*/*"
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "slack_ask_hub" {
  count = var.enable_slack_bot ? 1 : 0

  name              = "/aws/lambda/${local.name_prefix}-slack-ask-hub"
  retention_in_days = var.log_retention_days

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "slack_ask_hub_url" {
  description = "URL para configurar no Slack como Request URL do slash command"
  value       = var.enable_slack_bot ? "${aws_apigatewayv2_stage.slack_ask_hub[0].invoke_url}/slack/ask-hub" : null
}
