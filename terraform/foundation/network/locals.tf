# -----------------------------------------------------------------------------
# Naming Convention
# -----------------------------------------------------------------------------
locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      AccountID   = var.account_id
      AccountName = var.account_name
      Workspace   = "teck-observability-hub-prod"
      Layer       = "observability"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# VPC Data (Remote State) - TEMPORARIAMENTE DESABILITADO (TFC 503)
# -----------------------------------------------------------------------------
# WORKAROUND: Valores hardcoded (extraídos do state em 2026-01-27)
# VPC Workspace: vpc-core-infra-observability-prod
locals {
  vpc_id             = "vpc-00000000000000008"
  vpc_cidr           = "172.31.0.0/16"
  private_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002"]
  public_subnet_ids  = ["subnet-00000000000000003", "subnet-00000000000000004"]
}
