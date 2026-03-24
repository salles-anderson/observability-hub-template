# -----------------------------------------------------------------------------
# Cognito User Pool — Chainlit Auth (Sprint 9A.2)
# -----------------------------------------------------------------------------
# AWS Cognito para autenticacao do Chainlit via OAuth/OIDC.
# Dual auth: usuarios podem logar via Cognito OU via senha (bcrypt/SSM).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# User Pool
# -----------------------------------------------------------------------------
resource "aws_cognito_user_pool" "chainlit" {
  count = var.enable_chainlit ? 1 : 0

  name = "${local.name_prefix}-chainlit-users"

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  # Auto-verify email
  auto_verified_attributes = ["email"]

  # Account recovery via email
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Schema
  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  schema {
    name                     = "name"
    attribute_data_type      = "String"
    required                 = false
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  # MFA obrigatorio (TOTP — Google Authenticator, Authy, etc.)
  mfa_configuration = "ON"

  software_token_mfa_configuration {
    enabled = true
  }

  # Username config — allow email as username
  username_configuration {
    case_sensitive = false
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-chainlit-users"
  })
}

# -----------------------------------------------------------------------------
# User Pool Domain (Cognito Hosted UI)
# -----------------------------------------------------------------------------
resource "aws_cognito_user_pool_domain" "chainlit" {
  count = var.enable_chainlit ? 1 : 0

  domain       = "teck-obs-chainlit"
  user_pool_id = aws_cognito_user_pool.chainlit[0].id
}

# -----------------------------------------------------------------------------
# App Client (confidential — with client_secret)
# -----------------------------------------------------------------------------
resource "aws_cognito_user_pool_client" "chainlit" {
  count = var.enable_chainlit ? 1 : 0

  name         = "${local.name_prefix}-chainlit-app"
  user_pool_id = aws_cognito_user_pool.chainlit[0].id

  generate_secret = true

  # OAuth config
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "profile", "email"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = [
    "https://assistant.${var.domain_name}/auth/oauth/aws-cognito/callback"
  ]

  logout_urls = [
    "https://assistant.${var.domain_name}"
  ]

  # Token validity
  access_token_validity  = 1  # hours
  id_token_validity      = 1  # hours
  refresh_token_validity = 7 # days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]
}

# -----------------------------------------------------------------------------
# SSM Parameter — Cognito Client Secret
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "cognito_client_secret" {
  count = var.enable_chainlit ? 1 : 0

  name        = "/${local.name_prefix}/chainlit/cognito-client-secret"
  description = "Cognito App Client secret for Chainlit OAuth"
  type        = "SecureString"
  value       = aws_cognito_user_pool_client.chainlit[0].client_secret
  key_id      = module.kms.key_id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-cognito-client-secret"
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID for Chainlit"
  value       = var.enable_chainlit ? aws_cognito_user_pool.chainlit[0].id : null
}

output "cognito_user_pool_domain" {
  description = "Cognito Hosted UI domain"
  value       = var.enable_chainlit ? "${aws_cognito_user_pool_domain.chainlit[0].domain}.auth.us-east-1.amazoncognito.com" : null
}
