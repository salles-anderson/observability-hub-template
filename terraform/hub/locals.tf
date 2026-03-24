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
# TODO: Reativar quando TFC estabilizar
# data "terraform_remote_state" "vpc" {
#   backend = "remote"
#   config = {
#     organization = "YOUR_ORG"
#     workspaces = {
#       name = var.vpc_workspace_name
#     }
#   }
# }

# WORKAROUND: Valores hardcoded (extraídos do state em 2026-01-27)
# VPC Workspace: vpc-core-infra-observability-prod
locals {
  vpc_id             = "vpc-0ca161a6a51e276d1"
  vpc_cidr           = "172.31.0.0/16"
  private_subnet_ids = ["subnet-0731553d6902c9a78", "subnet-07a6fba6392e8f11d"]
  public_subnet_ids  = ["subnet-083404aa1faa972fd", "subnet-011197372bfb0e296"]
  bastion_sg_id      = var.bastion_sg_id
  vpce_sg_id         = null

  # ECR prefix para imagens do Observability Hub
  ecr_prefix = "${var.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/obs-hub"

  # Imagens via ECR (zero dependencia do Docker Hub)
  images = {
    grafana      = "${local.ecr_prefix}/grafana:${split(":", var.grafana_image)[1]}"
    prometheus   = "${local.ecr_prefix}/prometheus:${split(":", var.prometheus_image)[1]}"
    loki         = "${local.ecr_prefix}/loki:${split(":", var.loki_image)[1]}"
    tempo        = "${local.ecr_prefix}/tempo:${split(":", var.tempo_image)[1]}"
    alloy        = "${local.ecr_prefix}/alloy:${split(":", var.alloy_image)[1]}"
    alertmanager = "${local.ecr_prefix}/alertmanager:${split(":", var.alertmanager_image)[1]}"
    k6           = "${local.ecr_prefix}/k6:${split(":", var.k6_image)[1]}"
    litellm      = "${local.ecr_prefix}/litellm:${split(":", var.litellm_image)[1]}"
    mcp_grafana  = "${local.ecr_prefix}/mcp-grafana:${var.mcp_grafana_version}"
    aiops_agent  = "${local.ecr_prefix}/aiops-agent:${var.aiops_agent_version}"
    fluent_bit   = "${local.ecr_prefix}/fluent-bit:3.2"
    busybox      = "${local.ecr_prefix}/busybox:1.36"
    qdrant       = "${local.ecr_prefix}/qdrant:v1.13.2"
  }
}
