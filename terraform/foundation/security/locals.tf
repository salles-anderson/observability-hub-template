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
# Replicado EXATO do monolito (terraform/environment/build/locals.tf) para
# garantir paridade no-op nos Security Groups (vpc_id) importados.
locals {
  vpc_id        = "vpc-00000000000000008"
  bastion_sg_id = var.bastion_sg_id
}
