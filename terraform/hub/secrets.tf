# -----------------------------------------------------------------------------
# SSM Parameter Store - Observability DB Password
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "observability_db_password" {
  name        = "/${local.name_prefix}/observability/db-password"
  description = "Observability Hub database password"
  type        = "SecureString"
  value       = random_password.grafana_db.result
  key_id      = module.kms.key_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-observability-db-password"
  })
}

resource "aws_ssm_parameter" "grafana_admin_password" {
  name        = "/${local.name_prefix}/grafana/admin-password"
  description = "Grafana admin password"
  type        = "SecureString"
  value       = random_password.grafana_admin.result
  key_id      = module.kms.key_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-grafana-admin-password"
  })
}

# -----------------------------------------------------------------------------
# Random Passwords
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# SSM Parameter Store - Anthropic API Key (LiteLLM)
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "anthropic_api_key" {
  count = var.enable_grafana_llm ? 1 : 0

  name        = "/${local.name_prefix}/litellm/anthropic-api-key"
  description = "Anthropic API key for LiteLLM proxy (Claude via api.anthropic.com)"
  type        = "SecureString"
  value       = var.anthropic_api_key
  key_id      = module.kms.key_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-anthropic-api-key"
  })
}

resource "aws_ssm_parameter" "gemini_api_key" {
  count = var.enable_grafana_llm ? 1 : 0

  name        = "/${local.name_prefix}/litellm/gemini-api-key"
  description = "Google Gemini API key for LiteLLM proxy (Gemini via aistudio.google.com)"
  type        = "SecureString"
  value       = var.gemini_api_key
  key_id      = module.kms.key_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-gemini-api-key"
  })
}

resource "aws_ssm_parameter" "deepseek_api_key" {
  count = var.enable_grafana_llm && var.deepseek_api_key != "" ? 1 : 0

  name        = "/${local.name_prefix}/litellm/deepseek-api-key"
  description = "DeepSeek API key for LiteLLM proxy (DeepSeek V3 via platform.deepseek.com)"
  type        = "SecureString"
  value       = var.deepseek_api_key
  key_id      = module.kms.key_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-deepseek-api-key"
  })
}

# -----------------------------------------------------------------------------
# SSM Parameter Store - Grafana Service Account Token (Agent SDK / mcp-grafana)
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "grafana_sa_token" {
  count = var.enable_agent_sdk ? 1 : 0

  name        = "/${local.name_prefix}/agent-sdk/grafana-sa-token"
  description = "Grafana service account token for mcp-grafana (Agent SDK)"
  type        = "SecureString"
  value       = var.grafana_service_account_token
  key_id      = module.kms.key_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-grafana-sa-token"
  })
}

# -----------------------------------------------------------------------------
# SSM Parameter Store - Anthropic API Key (Agent SDK - direto, sem proxy)
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "anthropic_api_key_agent" {
  count = var.enable_agent_sdk ? 1 : 0

  name        = "/${local.name_prefix}/agent-sdk/anthropic-api-key"
  description = "Anthropic API key for Agent SDK (direct, no proxy)"
  type        = "SecureString"
  value       = var.anthropic_api_key
  key_id      = module.kms.key_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-agent-sdk-anthropic-api-key"
  })
}

# -----------------------------------------------------------------------------
# SSM Parameter Store - TFC API Token (Chainlit → Terraform Cloud shortcuts)
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "tfc_api_token" {
  count = var.enable_chainlit && var.tfc_api_token != "" ? 1 : 0

  name        = "/${local.name_prefix}/chainlit/tfc-api-token"
  description = "Terraform Cloud API token for Chainlit TFC shortcuts (read-only)"
  type        = "SecureString"
  value       = var.tfc_api_token
  key_id      = module.kms.key_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-tfc-api-token"
  })
}

# -----------------------------------------------------------------------------
# SSM Parameter Store - GitHub Token (Chainlit → GitHub read-only tools)
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "github_token" {
  count = var.enable_chainlit && var.github_token_obs_hub != "" ? 1 : 0

  name        = "/${local.name_prefix}/chainlit/github-token"
  description = "GitHub PAT (fine-grained, read-only) for Chainlit GitHub code analysis tools"
  type        = "SecureString"
  value       = var.github_token_obs_hub
  key_id      = module.kms.key_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-github-token"
  })
}

# -----------------------------------------------------------------------------
# SSM Parameter Store - SonarQube Token (Chainlit → SonarQube read-only tools)
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "sonarqube_token" {
  count = var.enable_chainlit && var.sonarqube_token != "" ? 1 : 0

  name        = "/${local.name_prefix}/chainlit/sonarqube-token"
  description = "SonarQube API token (read-only) for Chainlit Code Agent quality analysis tools"
  type        = "SecureString"
  value       = var.sonarqube_token
  key_id      = module.kms.key_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-sonarqube-token"
  })
}

resource "random_password" "grafana_db" {
  length  = 32
  special = false
}

resource "random_password" "grafana_admin" {
  length  = 16
  special = false
}
