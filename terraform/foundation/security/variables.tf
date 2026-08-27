# =============================================================================
# hub-foundation-security — variáveis do "cimento" transversal
# (KMS + Security Groups + IAM ecs_task/ecs_task_execution + 9 secrets SSM)
#
# Tipos e defaults replicados de terraform/environment/build/variables.tf para
# garantir paridade no-op com o monolito. Valores reais vêm do terraform.tfvars
# (não-sensíveis) ou de Terraform variables SENSÍVEIS setadas no TFC.
# =============================================================================

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------
variable "project" {
  description = "Nome do projeto"
  type        = string
  default     = "teck-obs-hub"
}

variable "environment" {
  description = "Ambiente (develop, homolog, production)"
  type        = string
  default     = "prod"
}

variable "owner" {
  description = "Dono do projeto"
  type        = string
  default     = "DevOps"
}

variable "account_id" {
  description = "ID da conta AWS"
  type        = string
}

variable "account_name" {
  description = "Nome da conta AWS"
  type        = string
}

variable "aws_region" {
  description = "Regiao AWS"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Tags adicionais para os recursos"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Security Groups — fontes de regras (ECS tasks SG + RDS SG)
# -----------------------------------------------------------------------------
# spoke_vpc_cidrs + tgw_spoke_vpc_cidrs alimentam local.all_spoke_cidrs no
# ecs_tasks_sg (OTLP 4317/4318 + Loki 3100). DEVEM ser byte-idênticos e na MESMA
# ordem do monolito para o SG importar no-op.
variable "spoke_vpc_cidrs" {
  description = "CIDRs das VPCs spoke via VPC Peering (usado para regras de SG OTel)"
  type        = list(string)
  default     = []
}

variable "tgw_spoke_vpc_cidrs" {
  description = "CIDRs das VPCs spoke via Transit Gateway (usado apenas para regras de SG)"
  type        = list(string)
  default     = []
}

variable "kong_vpc_cidrs" {
  description = "CIDRs das subnets privadas do Kong (Infra 172.29) autorizados a alcancar tasks internas"
  type        = list(string)
  default     = ["172.29.32.0/20", "172.29.48.0/20", "172.29.80.0/20"]
}

variable "bastion_sg_id" {
  description = "Security Group ID do bastion para acesso ao RDS (null = sem regra de bastion)"
  type        = string
  default     = null
}

variable "efs_enabled" {
  description = "Habilitar EFS (controla o count do efs_sg)"
  type        = bool
  default     = true
}

variable "enable_qdrant" {
  description = "Habilitar Qdrant (controla a condition do access point qdrant na policy ecs_task_efs). Prod = true (access point existe)."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Security - KMS
# -----------------------------------------------------------------------------
variable "kms_deletion_window" {
  description = "Dias para deletar KMS key"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# Feature flags que controlam count de SGs e dos 9 secrets SSM
# -----------------------------------------------------------------------------
variable "enable_grafana_llm" {
  description = "Habilitar LiteLLM/Redis (controla count do redis_sg + secrets anthropic/gemini/deepseek)"
  type        = bool
  default     = false
}

variable "enable_agent_sdk" {
  description = "Habilitar Agent SDK (controla count dos secrets grafana_sa_token + anthropic_api_key_agent)"
  type        = bool
  default     = false
}

variable "enable_chainlit" {
  description = "Habilitar Chainlit (controla count dos secrets chainlit_auth_secret/tfc/github/sonarqube)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Flags de presença dos secrets (SSM des-escopados do S2 → ficam no build/S5).
# A policy transversal ecs_task_execution_ssm monta a lista de ARNs por path
# literal, mas as CONDIÇÕES `var.X != ""` decidem quais entram — então estas 4
# variáveis SENSÍVEIS precisam continuar setadas no TFC (mesmo valor do build)
# para a policy sair byte-idêntica (no-op). As demais (db/admin/anthropic/gemini/
# grafana_sa) saíram com o de-escopo dos secrets — entram incondicionalmente na
# policy, não precisam de flag.
# -----------------------------------------------------------------------------
variable "deepseek_api_key" {
  description = "Flag de presença (DeepSeek key) — condiciona o ARN deepseek na policy. Setar no TFC = build."
  type        = string
  sensitive   = true
  default     = ""
}

variable "tfc_api_token" {
  description = "Flag de presença (TFC token) — condiciona o ARN tfc-api-token na policy. Setar no TFC = build."
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_token_obs_hub" {
  description = "Flag de presença (GitHub PAT) — condiciona o ARN github-token na policy. Setar no TFC = build."
  type        = string
  sensitive   = true
  default     = ""
}

variable "sonarqube_token" {
  description = "Flag de presença (SonarQube token) — condiciona o ARN sonarqube. Vazio em prod (count=0)."
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Cross-account (IAM ecs_task) — AssumeRole para spokes (MCP AWS)
# -----------------------------------------------------------------------------
variable "spoke_account_ids" {
  description = "Lista de Account IDs das contas spoke (cross-account AssumeRole do ecs_task)"
  type        = list(string)
  default     = []
}

variable "spoke_role_name" {
  description = "Nome do IAM role read-only nas contas spoke"
  type        = string
  default     = "teck-obs-hub-spoke-role"
}

# -----------------------------------------------------------------------------
# ARNs EXTERNOS referenciados pelas inline policies do ecs_task.
# DECISÃO DO USUÁRIO: passados como VARIÁVEIS (literais conhecidos via tfvars),
# NÃO via terraform_remote_state. Os recursos donos vivem em outros workspaces:
#   - app_s3_bucket_arn          -> module.s3_bucket (storage.tf, futuro ws de storage)
#   - efs_arn / efs_*_arn        -> aws_efs_file_system.this + access points (storage)
# Valores reais (sg-/arn:) entram no terraform.tfvars na Task 3.
# -----------------------------------------------------------------------------
variable "app_s3_bucket_arn" {
  description = "ARN do bucket S3 principal (module.s3_bucket) — policy ecs_task_s3"
  type        = string
  default     = ""
}

variable "efs_arn" {
  description = "ARN do EFS file system (aws_efs_file_system.this) — policy ecs_task_efs"
  type        = string
  default     = ""
}

variable "efs_access_point_grafana_arn" {
  description = "ARN do EFS access point do Grafana — condition da policy ecs_task_efs"
  type        = string
  default     = ""
}

variable "skills_bucket_id" {
  description = "Nome (bucket_id) do bucket S3 de skills (module.skills_bucket) — policy ecs_task_skills_s3. Recurso dono fica no build/skills.tf."
  type        = string
  default     = ""
}

variable "efs_access_point_qdrant_arn" {
  description = "ARN do EFS access point do Qdrant — condition da policy ecs_task_efs (só quando enable_qdrant)"
  type        = string
  default     = ""
}

variable "sonar_ecs_sg_id" {
  description = "SG ID das ECS tasks do Sonar (ingress 5432 no rds_sg). Monolito usa literal sg-00000000000000007."
  type        = string
  default     = "sg-00000000000000007"
}

# -----------------------------------------------------------------------------
# ARN externo do chainlit_auth_secret — SSM SecureString que fica no build
# (chainlit-data.tf / vai com o serviço chainlit), NÃO migra para o cimento.
# A policy ecs_task_execution_ssm referencia o ARN dele; resolvido por variável
# (mesma decisão dos outros ARNs externos). Valor real no terraform.tfvars.
# -----------------------------------------------------------------------------
variable "chainlit_auth_secret_arn" {
  description = "ARN do SSM SecureString chainlit/auth-secret (fica no build) — policy ecs_task_execution_ssm"
  type        = string
  default     = ""
}
