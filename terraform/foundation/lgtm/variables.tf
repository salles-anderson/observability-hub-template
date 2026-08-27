# =============================================================================
# hub-foundation-lgtm — variaveis do dominio LGTM (Grafana, Loki, Tempo,
# Prometheus, Alertmanager, Alloy + log groups compartilhados + SSM de config).
#
# Tipos/defaults replicados VERBATIM de terraform/environment/build/variables.tf
# para garantir paridade no-op com o monolito. Valores nao-sensiveis vem do
# terraform.tfvars; slack_webhook_url (sensitive) entra como TFC workspace var
# (passo manual do user — Task L4). NAO inventar nomes/tipos: tudo espelha o build
# para que o import (L3) feche no-op.
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
# Container images (portado VERBATIM de build/variables.tf — referenciado em
# locals.tf no map `local.images`; type/description/default identicos ao build).
# -----------------------------------------------------------------------------
variable "grafana_image" {
  description = "Imagem Docker do Grafana"
  type        = string
  default     = "grafana/grafana:11.4.0"
}

variable "prometheus_image" {
  description = "Imagem Docker do Prometheus"
  type        = string
  default     = "prom/prometheus:v2.54.1"
}

variable "loki_image" {
  description = "Imagem Docker do Loki"
  type        = string
  default     = "grafana/loki:2.9.10"
}

variable "tempo_image" {
  description = "Imagem Docker do Tempo"
  type        = string
  default     = "grafana/tempo:2.4.0"
}

variable "alloy_image" {
  description = "Imagem Docker do Grafana Alloy"
  type        = string
  default     = "grafana/alloy:v1.8.1"
}

variable "alertmanager_image" {
  description = "Imagem Docker do AlertManager"
  type        = string
  default     = "prom/alertmanager:v0.27.0"
}

# -----------------------------------------------------------------------------
# DNS / Service Discovery
# -----------------------------------------------------------------------------
variable "hosted_zone_id" {
  description = "ID da Hosted Zone no Route53"
  type        = string
}

variable "domain_name" {
  description = "Dominio base para o Observability Hub (ex: observability.tower.yourorg.com.br)"
  type        = string
}

variable "cloudmap_namespace" {
  description = "Nome do namespace privado para service discovery"
  type        = string
  default     = "observability.local"
}

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
variable "log_retention_days" {
  description = "Dias de retencao dos logs no CloudWatch (max 30 dias conforme politica)"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# Feature flags
# -----------------------------------------------------------------------------
variable "enable_metric_streams" {
  description = "Habilitar CloudWatch Metric Streams para enviar metricas AWS ao Prometheus"
  type        = bool
  default     = false
}

variable "enable_aiops" {
  description = "Habilitar AIOps (DevOps Guru + CloudWatch Anomaly + LLM Alert Enrichment)"
  type        = bool
  default     = false
}

variable "enable_alert_investigation" {
  description = "Enable AG-3 proactive alert investigation (AlertManager -> AG-2 -> Slack)"
  type        = bool
  default     = false
}

variable "enable_grafana_llm" {
  description = "Habilitar LiteLLM proxy para Grafana AI features (grafana-llm-app plugin)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Grafana
# -----------------------------------------------------------------------------
variable "grafana_cpu" {
  description = "CPU units para o Grafana (1 vCPU = 1024)"
  type        = number
  default     = 512
}

variable "grafana_memory" {
  description = "Memoria em MiB para o Grafana"
  type        = number
  default     = 1024
}

# -----------------------------------------------------------------------------
# Loki
# -----------------------------------------------------------------------------
variable "loki_cpu" {
  description = "CPU units para o Loki"
  type        = number
  default     = 512
}

variable "loki_memory" {
  description = "Memoria em MiB para o Loki"
  type        = number
  default     = 1024
}

# -----------------------------------------------------------------------------
# Tempo
# -----------------------------------------------------------------------------
variable "tempo_cpu" {
  description = "CPU units para o Tempo"
  type        = number
  default     = 512
}

variable "tempo_memory" {
  description = "Memoria em MiB para o Tempo"
  type        = number
  default     = 1024
}

# -----------------------------------------------------------------------------
# Prometheus
# -----------------------------------------------------------------------------
variable "prometheus_cpu" {
  description = "CPU units para o Prometheus"
  type        = number
  default     = 512
}

variable "prometheus_memory" {
  description = "Memoria em MiB para o Prometheus"
  type        = number
  default     = 1024
}

variable "prometheus_retention_days" {
  description = "Dias de retencao das metricas no Prometheus"
  type        = number
  default     = 15
}

# -----------------------------------------------------------------------------
# Alertmanager
# -----------------------------------------------------------------------------
variable "alertmanager_cpu" {
  description = "CPU units para o AlertManager"
  type        = number
  default     = 256
}

variable "alertmanager_memory" {
  description = "Memoria em MiB para o AlertManager"
  type        = number
  default     = 512
}

# -----------------------------------------------------------------------------
# Alloy
# -----------------------------------------------------------------------------
variable "alloy_cpu" {
  description = "CPU units para o Grafana Alloy"
  type        = number
  default     = 256
}

variable "alloy_memory" {
  description = "Memoria em MiB para o Grafana Alloy"
  type        = number
  default     = 512
}

# -----------------------------------------------------------------------------
# Secrets (TFC workspace var sensitive — NAO no tfvars)
# -----------------------------------------------------------------------------
# slack_webhook_url: no build foi movido para TFC sensitive variable
# (build/terraform.tfvars:150 "slack_webhook_url movido para TFC sensitive
# variable"). Consumido por alertmanager.tf + ssm-configs.tf. Setar como TFC
# workspace var sensitive no ws lgtm (Task L4).
variable "slack_webhook_url" {
  description = "Slack Webhook URL para notificacoes do AlertManager"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# CloudTrail → Loki (OBS-SEC-1) — portado VERBATIM de
# terraform/environment/build/cloudtrail-loki.tf (header) e
# terraform/environment/build/variables.tf (spoke_role_name).
# enable_cloudtrail_loki=true sera setado como TFC ws var (Task L7).
# -----------------------------------------------------------------------------
variable "cloudtrail_s3_bucket" {
  description = "S3 bucket name where CloudTrail Organization Trail logs are stored (Control Tower)"
  type        = string
  default     = "aws-controltower-cloudtrail-logs-121212121212-iad-oam"
}

variable "cloudtrail_account_id" {
  description = "Account ID hosting the central CloudTrail Organization Trail"
  type        = string
  default     = "121212121212"
}

variable "enable_cloudtrail_loki" {
  description = "Enable CloudTrail → Loki Lambda processor"
  type        = bool
  default     = true
}

variable "spoke_role_name" {
  description = "Name of the read-only IAM role in spoke accounts for Chainlit cross-account"
  type        = string
  default     = "teck-obs-hub-spoke-role"
}
