# -----------------------------------------------------------------------------
# Spoke Read-Only Role for Observability Hub Cross-Account Access
# -----------------------------------------------------------------------------
# Deploy this module in EACH spoke account to allow the Hub's Chainlit
# task role to assume a read-only role for AWS queries.
#
# Usage (in spoke account Terraform):
#   module "obs_hub_readonly" {
#     source         = "../../modules/spoke-readonly-role"
#     hub_account_id = "111111111111"
#     external_id    = "teck-observability-hub-2024"
#   }
# -----------------------------------------------------------------------------

variable "hub_account_id" {
  description = "AWS Account ID of the Observability Hub (assumes role FROM here)"
  type        = string
  default     = "111111111111"
}

variable "external_id" {
  description = "External ID for STS AssumeRole (shared secret between Hub and spoke)"
  type        = string
  default     = "teck-observability-hub-2024"
}

variable "role_name" {
  description = "Name of the read-only role created in spoke account"
  type        = string
  default     = "obs-hub-readonly"
}

# -----------------------------------------------------------------------------
# IAM Role — trusted by Hub account
# -----------------------------------------------------------------------------
resource "aws_iam_role" "obs_hub_readonly" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.hub_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.external_id
          }
        }
      }
    ]
  })

  tags = {
    Name        = var.role_name
    ManagedBy   = "terraform"
    Purpose     = "observability-hub-cross-account-readonly"
    HubAccount  = var.hub_account_id
  }
}

# -----------------------------------------------------------------------------
# Permissions — ReadOnlyAccess (AWS managed)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.obs_hub_readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# -----------------------------------------------------------------------------
# Extra permissions not in ReadOnlyAccess
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "extras" {
  name = "${var.role_name}-extras"
  role = aws_iam_role.obs_hub_readonly.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CostExplorer"
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetCostForecast",
          "ce:GetRightsizingRecommendation",
          "ce:GetAnomalies",
          "ce:GetSavingsPlansCoverage",
          "ce:GetSavingsPlansUtilization",
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Explicit DENY — block sensitive data access (same guardrails as Hub)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "deny_sensitive" {
  name = "${var.role_name}-deny-sensitive"
  role = aws_iam_role.obs_hub_readonly.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenySensitiveData"
        Effect = "Deny"
        Action = [
          "secretsmanager:GetSecretValue",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "s3:GetObject",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "role_arn" {
  description = "ARN of the read-only role for Hub to assume"
  value       = aws_iam_role.obs_hub_readonly.arn
}

output "role_name" {
  description = "Name of the read-only role"
  value       = aws_iam_role.obs_hub_readonly.name
}
