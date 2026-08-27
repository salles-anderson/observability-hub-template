# =============================================================================
# hub-foundation-data — variaveis do "data plane" (RDS Aurora + EFS + S3 + Redis)
#
# Tipos e defaults replicados de terraform/environment/build/variables.tf para
# garantir paridade no-op com o monolito. Valores reais vem do terraform.tfvars
# (nao-sensiveis) ou de Terraform variables SENSIVEIS setadas no TFC (db_password).
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
# RDS Aurora PostgreSQL (module.rds_observability)
# -----------------------------------------------------------------------------
variable "rds_instance_class" {
  description = "Classe da instancia Aurora"
  type        = string
  default     = "db.t3.medium"
}

variable "rds_instance_count" {
  description = "Numero de instancias no cluster Aurora (writer + readers)"
  type        = number
  default     = 1
}

variable "rds_engine_version" {
  description = "Versao do Aurora PostgreSQL"
  type        = string
  default     = "16.4"
}

variable "rds_serverlessv2_min_capacity" {
  description = "Aurora Serverless v2 minimum ACU. 0 = scale-to-zero quando idle (sem custo de compute). Apenas usado quando rds_instance_class = 'db.serverless'."
  type        = number
  default     = null
}

variable "rds_serverlessv2_max_capacity" {
  description = "Aurora Serverless v2 maximum ACU. 1 ACU = 2 GB RAM + matched compute. Apenas usado quando rds_instance_class = 'db.serverless'."
  type        = number
  default     = null
}

# Senha do RDS Aurora — no monolito vem de random_password.grafana_db.result.
# Na decomposicao, o random fica no build e o valor real e setado como Terraform
# variable SENSIVEL no workspace TFC (NAO no terraform.tfvars). Default vazio so
# para o plan validar; o valor real (mesmo do state) entra no TFC para no-op.
variable "db_password" {
  description = "Senha master do RDS Aurora (admindbprod). Setar no TFC = valor do state importado."
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Storage - S3 (module.s3_bucket + lifecycle)
# -----------------------------------------------------------------------------
variable "s3_bucket_name" {
  description = "Nome do bucket S3 (sufixo, concatenado ao name_prefix)"
  type        = string
  default     = "teck-obs-hub-storage"
}

variable "s3_versioning" {
  description = "Habilitar versionamento no S3"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Storage - EFS (aws_efs_file_system.this + mount targets)
# -----------------------------------------------------------------------------
variable "efs_enabled" {
  description = "Habilitar EFS (controla o count do file system e dos mount targets)"
  type        = bool
  default     = true
}

variable "efs_name" {
  description = "Nome do EFS (sufixo, concatenado ao name_prefix)"
  type        = string
  default     = "obs-hub-efs"
}

variable "efs_encrypted" {
  description = "Habilitar criptografia no EFS (usa local.security.kms_key_arn)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# ElastiCache Redis - LiteLLM cache (module.litellm_redis)
# -----------------------------------------------------------------------------
variable "enable_grafana_llm" {
  description = "Habilitar LiteLLM/Redis (controla o count do module.litellm_redis). Prod = true."
  type        = bool
  default     = false
}

variable "redis_node_type" {
  description = "Tipo de instancia ElastiCache Redis para LiteLLM cache"
  type        = string
  default     = "cache.t3.micro"
}

# -----------------------------------------------------------------------------
# Flags de paridade (carregadas para espelhar o monolito; nenhum recurso data
# atual depende delas, mas mantidas para evitar drift de plan caso recursos
# condicionais migrem para este workspace). enable_qdrant/enable_chainlit nao
# gateiam recursos em rds/storage/litellm-redis no estado atual.
# -----------------------------------------------------------------------------
variable "enable_qdrant" {
  description = "Habilitar Qdrant (paridade prod = true; sem efeito de count nos recursos data atuais)."
  type        = bool
  default     = false
}

variable "enable_chainlit" {
  description = "Habilitar Chainlit (paridade prod = true; sem efeito de count nos recursos data atuais)."
  type        = bool
  default     = false
}
