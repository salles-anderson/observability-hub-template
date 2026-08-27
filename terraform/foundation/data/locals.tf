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
# VPC / Subnets (hardcoded — paridade no-op com o monolito)
# -----------------------------------------------------------------------------
# WORKAROUND: Valores hardcoded (extraidos do state em 2026-01-27).
# VPC Workspace: vpc-core-infra-observability-prod
# Replicado EXATO do monolito (terraform/environment/build/locals.tf, linha 41)
# para garantir paridade no-op nos recursos data (subnet_ids do RDS/EFS/Redis
# e mount targets do EFS devem bater byte-a-byte com o state importado).
locals {
  private_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002"]
}
