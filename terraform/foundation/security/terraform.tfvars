# =============================================================================
# hub-foundation-security — valores NÃO-SENSÍVEIS.
# Os 7 secrets (anthropic/gemini/deepseek/grafana_sa/tfc/github/sonarqube)
# são Terraform variables SENSÍVEIS setadas no workspace TFC, NÃO aqui.
# =============================================================================

# -----------------------------------------------------------------------------
# General (idêntico a build/terraform.tfvars)
# -----------------------------------------------------------------------------
project      = "teck-obs-hub"
environment  = "prod"
owner        = "DevOps"
account_id   = "111111111111"
account_name = "teck-observability"
aws_region   = "us-east-1"

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
bastion_sg_id = "sg-00000000000000006"
efs_enabled   = true

# spoke_vpc_cidrs — byte-idêntico a build/terraform.tfvars (mesma ordem).
# Alimenta as regras OTLP/Loki do ecs_tasks_sg via concat com tgw_spoke_vpc_cidrs.
spoke_vpc_cidrs = [
  # "172.18.0.0/16", # YourOrg-Homolog (333333333333) - movido para tgw_spoke_vpc_cidrs (conflito CIDR com ABC Card)
  # "172.19.0.0/16", # YourOrg-Dev (222222222222) - migrado para TGW
  "172.20.0.0/16",  # YourOrg-Prod (444444444444)
  "172.21.0.0/16",  # CloudTrail (121212121212)
  "172.22.0.0/16",  # Admin (131313131313)
  "172.23.0.0/16",  # Capital-Dev (888888888888)
  "172.24.0.0/16",  # Capital-Homolog (888888888888)
  "172.25.0.0/16",  # Capital-Prod (888888888888)
  "172.26.0.0/16",  # HubDigital-Dev (999999999999)
  "172.27.0.0/16",  # HubDigital-Homolog (999999999999)
  "172.28.0.0/16",  # HubDigital-Prod (999999999999)
  "172.29.0.0/16",  # Infra (555555555555)
  "10.239.15.0/25", # edge apus dock (666666666666)
  "10.239.45.0/25", # edge capital dock (888888888888)
]

# tgw_spoke_vpc_cidrs — byte-idêntico a build/terraform.tfvars (mesma ordem).
tgw_spoke_vpc_cidrs = [
  "172.16.0.0/16", # akrk-dev prod (vpc-core-infra-prod)
  "172.17.0.0/16", # akrk-dev homolog (vpc-core-infra-homolog)
  "172.18.0.0/16", # abc-card prod (vpc-core-infra-prod) - 666666666666
  "172.19.0.0/16", # YourOrg-Dev (222222222222) - migrado de peering
]

# -----------------------------------------------------------------------------
# KMS
# -----------------------------------------------------------------------------
kms_deletion_window = 7

# -----------------------------------------------------------------------------
# Feature flags (paridade com o state do monolito → secrets/SGs corretos)
# -----------------------------------------------------------------------------
enable_grafana_llm = true
enable_agent_sdk   = true
enable_chainlit    = true
enable_qdrant      = true # prod tem access point qdrant (efs_access_point_qdrant_arn setado)

# -----------------------------------------------------------------------------
# Cross-account (IAM ecs_task) — espelha o default do monolito (10 contas spoke)
# -----------------------------------------------------------------------------
spoke_account_ids = [
  "777777777777", # AKRK-Dev (FrontConsig)
  "222222222222", # YourOrg-Dev
  "333333333333", # YourOrg-Homolog
  "444444444444", # YourOrg-Prod
  "888888888888", # Capital
  "999999999999", # HubDigital
  "121212121212", # CloudTrail
  "131313131313", # Admin
  "555555555555", # Infra
  "666666666666", # ABC Card
]
spoke_role_name = "teck-obs-hub-spoke-role"

# -----------------------------------------------------------------------------
# ARNs EXTERNOS p/ inline policies do ecs_task (read-only AWS 2026-06-15).
# Recursos donos vivem em outros workspaces; passados como literais conhecidos.
# -----------------------------------------------------------------------------
app_s3_bucket_arn            = "arn:aws:s3:::teck-obs-hub-prod-storage"
efs_arn                      = "arn:aws:elasticfilesystem:us-east-1:111111111111:file-system/fs-00000000000000001"
efs_access_point_grafana_arn = "arn:aws:elasticfilesystem:us-east-1:111111111111:access-point/fsap-00000000000000004"
efs_access_point_qdrant_arn  = "arn:aws:elasticfilesystem:us-east-1:111111111111:access-point/fsap-00000000000000003"
sonar_ecs_sg_id              = "sg-00000000000000007"
skills_bucket_id             = "teck-obs-hub-prod-skills"

# chainlit_auth_secret fica no build (vai com o serviço chainlit); aqui só o ARN.
chainlit_auth_secret_arn = "arn:aws:ssm:us-east-1:111111111111:parameter/teck-obs-hub-prod/chainlit/auth-secret"

# -----------------------------------------------------------------------------
# Tags (paridade com build — fecha plan no-op: recursos importados têm Team=DevOps)
# -----------------------------------------------------------------------------
tags = {
  Team = "DevOps"
}
