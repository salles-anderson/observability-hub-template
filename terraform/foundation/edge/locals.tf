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
# Replicado EXATO do monolito (terraform/environment/build/locals.tf, linhas
# 39-42) para garantir paridade no-op no module.alb (vpc_id + subnet_ids do ALB
# devem bater byte-a-byte com o state importado). O ALB usa public_subnet_ids
# quando alb_internal=false (caso prod) e private_subnet_ids quando true.
locals {
  vpc_id             = "vpc-00000000000000008"
  private_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002"]
  public_subnet_ids  = ["subnet-00000000000000003", "subnet-00000000000000004"]
}
