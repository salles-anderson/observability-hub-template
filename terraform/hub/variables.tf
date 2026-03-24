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

# -----------------------------------------------------------------------------
# VPC Remote State
# -----------------------------------------------------------------------------
variable "vpc_workspace_name" {
  description = "Nome do workspace da VPC no TFC"
  type        = string
  default     = "vpc-core-infra-observability-prod"
}

variable "bastion_sg_id" {
  description = "Security Group ID do bastion para acesso ao RDS"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------
variable "ecs_cluster_name" {
  description = "Nome do cluster ECS"
  type        = string
  default     = "cluster-prod"
}

variable "container_insights" {
  description = "Habilitar Container Insights"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# ALB
# -----------------------------------------------------------------------------
variable "alb_name" {
  description = "Nome do Application Load Balancer"
  type        = string
  default     = "obs-hub-alb"
}

variable "alb_internal" {
  description = "Se o ALB e interno"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Storage - S3
# -----------------------------------------------------------------------------
variable "s3_bucket_name" {
  description = "Nome do bucket S3"
  type        = string
  default     = "teck-obs-hub-storage"
}

variable "s3_versioning" {
  description = "Habilitar versionamento no S3"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Storage - EFS
# -----------------------------------------------------------------------------
variable "efs_enabled" {
  description = "Habilitar EFS"
  type        = bool
  default     = true
}

variable "efs_name" {
  description = "Nome do EFS"
  type        = string
  default     = "obs-hub-efs"
}

variable "efs_encrypted" {
  description = "Habilitar criptografia no EFS"
  type        = bool
  default     = true
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
# DNS e Certificado
# -----------------------------------------------------------------------------
variable "hosted_zone_id" {
  description = "ID da Hosted Zone no Route53"
  type        = string
}

variable "domain_name" {
  description = "Dominio base para o Observability Hub (ex: observability.tower.yourorg.com.br)"
  type        = string
}

# -----------------------------------------------------------------------------
# Grafana
# -----------------------------------------------------------------------------
variable "grafana_image" {
  description = "Imagem Docker do Grafana"
  type        = string
  default     = "grafana/grafana:11.4.0"
}

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
# Prometheus
# -----------------------------------------------------------------------------
variable "prometheus_image" {
  description = "Imagem Docker do Prometheus"
  type        = string
  default     = "prom/prometheus:v2.54.1"
}

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
# Loki
# -----------------------------------------------------------------------------
variable "loki_image" {
  description = "Imagem Docker do Loki"
  type        = string
  default     = "grafana/loki:2.9.10"
}

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
variable "tempo_image" {
  description = "Imagem Docker do Tempo"
  type        = string
  default     = "grafana/tempo:2.4.0"
}

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
# Grafana Alloy (substitui OTel Collector)
# -----------------------------------------------------------------------------
variable "alloy_image" {
  description = "Imagem Docker do Grafana Alloy"
  type        = string
  default     = "grafana/alloy:v1.8.1"
}

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
# AlertManager
# -----------------------------------------------------------------------------
variable "alertmanager_image" {
  description = "Imagem Docker do AlertManager"
  type        = string
  default     = "prom/alertmanager:v0.27.0"
}

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

variable "slack_webhook_url" {
  description = "Slack Webhook URL para notificacoes do AlertManager"
  type        = string
  sensitive   = true
  default     = ""
}

variable "slack_signing_secret" {
  description = "Slack App Signing Secret para verificacao de requests do /ask-hub"
  type        = string
  sensitive   = true
  default     = ""
}

variable "slack_bot_token" {
  description = "Slack Bot OAuth Token (xoxb-...) para /ask-hub"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# RDS
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

# -----------------------------------------------------------------------------
# CloudWatch Logs
# -----------------------------------------------------------------------------
variable "log_retention_days" {
  description = "Dias de retencao dos logs no CloudWatch (max 30 dias conforme politica)"
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# Service Discovery (Cloud Map)
# -----------------------------------------------------------------------------
variable "cloudmap_namespace" {
  description = "Nome do namespace privado para service discovery"
  type        = string
  default     = "observability.local"
}

# -----------------------------------------------------------------------------
# Spoke Accounts (VPCs que enviam telemetria)
# -----------------------------------------------------------------------------
# spoke_vpc_cidrs: VPCs conectadas via VPC Peering (rotas criadas aqui)
# tgw_spoke_vpc_cidrs: VPCs conectadas via Transit Gateway (rotas no vpc-core)
# Ambas as listas sao usadas para regras de Security Group OTel
# -----------------------------------------------------------------------------
variable "spoke_vpc_cidrs" {
  description = "CIDRs das VPCs spoke via VPC Peering (usado para rotas e SG)"
  type        = list(string)
  default = [
    "172.17.0.0/16",  # Solis (cluster-homolog/cluster-prod)
    "172.18.0.0/16",  # YOUR_ORG-Homolog
    "172.19.0.0/16",  # YOUR_ORG-Dev
    "172.20.0.0/16",  # YOUR_ORG-Prod
    "172.21.0.0/16",  # CloudTrail
    "172.22.0.0/16",  # Admin
    "172.23.0.0/16",  # Capital-Dev
    "172.24.0.0/16",  # Capital-Homolog
    "172.25.0.0/16",  # Capital-Prod
    "172.26.0.0/16",  # HubDigital-Dev
    "172.27.0.0/16",  # HubDigital-Homolog
    "172.28.0.0/16",  # HubDigital-Prod
    "172.29.0.0/16",  # Infra
  ]
}

variable "tgw_spoke_vpc_cidrs" {
  description = "CIDRs das VPCs spoke via Transit Gateway (usado apenas para SG, rotas no vpc-core)"
  type        = list(string)
  default     = []
}

variable "spoke_vpc_dns_associations" {
  description = "Map de spoke VPCs para associar com a PHZ do Cloud Map (nome => VPC ID)"
  type        = map(string)
  default     = {}
}

variable "spoke_account_ids" {
  description = "Lista de Account IDs das contas spoke para AWS RAM e cross-account"
  type        = list(string)
  default = [
    "YOUR_AKRK_ACCOUNT_ID",  # Solis
    "YOUR_DEV_ACCOUNT_ID",  # YOUR_ORG-Dev
    "YOUR_HML_ACCOUNT_ID",  # YOUR_ORG-Homolog
    "YOUR_PRD_ACCOUNT_ID",  # YOUR_ORG-Prod
    "YOUR_CAPITAL_ACCOUNT_ID",  # Capital
    "131602690665",  # HubDigital
    "823557601977",  # CloudTrail
    "195835301200",  # Admin
    "YOUR_INFRA_ACCOUNT_ID",  # Infra
  ]
}

variable "spoke_role_name" {
  description = "Name of the read-only IAM role in spoke accounts for Chainlit cross-account"
  type        = string
  default     = "obs-hub-readonly"
}

# -----------------------------------------------------------------------------
# Tags adicionais
# -----------------------------------------------------------------------------
variable "tags" {
  description = "Tags adicionais para os recursos"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# CloudWatch Metric Streams
# -----------------------------------------------------------------------------
variable "enable_metric_streams" {
  description = "Habilitar CloudWatch Metric Streams para enviar metricas AWS ao Prometheus"
  type        = bool
  default     = false
}


# -----------------------------------------------------------------------------
# K6 - Load Testing (Sprint 11)
# -----------------------------------------------------------------------------
variable "enable_k6" {
  description = "Habilitar K6 para testes de carga"
  type        = bool
  default     = false
}

variable "k6_image" {
  description = "Imagem Docker do K6"
  type        = string
  default     = "grafana/k6:0.54.0"
}

variable "k6_cpu" {
  description = "CPU units para o K6"
  type        = number
  default     = 1024
}

variable "k6_memory" {
  description = "Memoria em MiB para o K6"
  type        = number
  default     = 2048
}

variable "k6_scheduled_tests" {
  description = "Habilitar testes agendados via EventBridge"
  type        = bool
  default     = false
}

variable "k6_schedule_expression" {
  description = "Expressao cron para testes agendados (ex: cron(0 6 * * ? *))"
  type        = string
  default     = "cron(0 6 * * ? *)"
}

# -----------------------------------------------------------------------------
# AIOps - Anomaly Detection + Alert Enrichment (Sprint 4)
# -----------------------------------------------------------------------------
variable "enable_aiops" {
  description = "Habilitar AIOps (DevOps Guru + CloudWatch Anomaly + LLM Alert Enrichment)"
  type        = bool
  default     = false
}

variable "enable_aws_anomaly_detection" {
  description = "Habilitar DevOps Guru + CloudWatch Anomaly Alarms (custo ~$30/mes)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Grafana LLM - LiteLLM Proxy + Anthropic API (Sprint 5)
# -----------------------------------------------------------------------------
variable "enable_grafana_llm" {
  description = "Habilitar LiteLLM proxy para Grafana AI features (grafana-llm-app plugin)"
  type        = bool
  default     = false
}

variable "anthropic_api_key" {
  description = "Anthropic API key para LiteLLM proxy (Claude via api.anthropic.com)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "gemini_api_key" {
  description = "Google Gemini API key para LiteLLM proxy (Gemini via aistudio.google.com)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "deepseek_api_key" {
  description = "DeepSeek API key para LiteLLM proxy (DeepSeek V3 via platform.deepseek.com)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "redis_node_type" {
  description = "Tipo de instancia ElastiCache Redis para LiteLLM cache"
  type        = string
  default     = "cache.t3.micro"
}

variable "litellm_image" {
  description = "Imagem Docker do LiteLLM (source para ECR)"
  type        = string
  default     = "ghcr.io/berriai/litellm:main-stable"
}

variable "litellm_cpu" {
  description = "CPU units para o LiteLLM"
  type        = number
  default     = 256
}

variable "litellm_memory" {
  description = "Memoria em MiB para o LiteLLM"
  type        = number
  default     = 512
}

# -----------------------------------------------------------------------------
# Agent SDK + mcp-grafana - AIOps Autonomous Agents (Sprint 6)
# -----------------------------------------------------------------------------
variable "enable_agent_sdk" {
  description = "Habilitar AIOps Agent SDK com mcp-grafana (ECS Fargate)"
  type        = bool
  default     = false
}

variable "grafana_service_account_token" {
  description = "Token do service account Grafana para mcp-grafana (gerado no workspace grafana-dashboards)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mcp_grafana_version" {
  description = "Versao da imagem mcp-grafana"
  type        = string
  default     = "v0.11.0"
}

variable "aiops_agent_version" {
  description = "Versao da imagem aiops-agent"
  type        = string
  default     = "latest"
}

variable "aiops_agent_cpu" {
  description = "CPU units para o AIOps Agent (recomendado 1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "aiops_agent_memory" {
  description = "Memoria em MiB para o AIOps Agent (recomendado 2048)"
  type        = number
  default     = 2048
}

# -----------------------------------------------------------------------------
# Chainlit Chat (Sprint 9A)
# -----------------------------------------------------------------------------
variable "enable_chainlit" {
  description = "Habilitar Chainlit Chat UI (Teck Observability Assistant)"
  type        = bool
  default     = false
}

variable "chainlit_cpu" {
  description = "CPU units para o Chainlit Chat (inclui MCP sidecars)"
  type        = number
  default     = 2048
}

variable "chainlit_memory" {
  description = "Memoria em MiB para o Chainlit Chat (inclui MCP sidecars)"
  type        = number
  default     = 4096
}

variable "chainlit_agent_version" {
  description = "Versao do pipeline: ag1 (single orchestrator), ag2 (multi-agent), ag5 (Claude + MCP)"
  type        = string
  default     = "ag2"
}

variable "tfc_api_token" {
  description = "Terraform Cloud API token para Chainlit TFC shortcuts (read-only team token)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_token_obs_hub" {
  description = "GitHub Personal Access Token (fine-grained, read-only) para Chainlit GitHub tools"
  type        = string
  sensitive   = true
  default     = ""
}

variable "sonarqube_token" {
  description = "SonarQube API token (read-only) para Chainlit Code Agent tools"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Qdrant - Vector Store for RAG (Sprint S11)
# -----------------------------------------------------------------------------
variable "enable_qdrant" {
  description = "Habilitar Qdrant vector store para RAG runbooks"
  type        = bool
  default     = false
}

variable "qdrant_cpu" {
  description = "CPU units para o Qdrant (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "qdrant_memory" {
  description = "Memoria em MiB para o Qdrant"
  type        = number
  default     = 512
}

# -----------------------------------------------------------------------------
# Kong AI Gateway (Sprint AG-2.1)
# -----------------------------------------------------------------------------
variable "enable_kong_ai" {
  description = "Habilitar Kong AI Gateway (proxy chainlit -> LiteLLM com PII removal)"
  type        = bool
  default     = false
}

variable "enable_alert_investigation" {
  description = "Enable AG-3 proactive alert investigation (AlertManager -> AG-2 -> Slack)"
  type        = bool
  default     = false
}

variable "waf_allowed_cidrs" {
  description = "CIDRs permitidos para acessar o Hub ALB (Grafana, SonarQube, Chainlit). Vazio = WAF desativado."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# MCP Servers — Confluence + Eraser (Sprint DOC-AUTO)
# -----------------------------------------------------------------------------
variable "confluence_api_token" {
  description = "Confluence API token for mcp-confluence MCP server"
  type        = string
  sensitive   = true
  default     = ""
}

variable "eraser_api_token" {
  description = "Eraser API token for mcp-eraser MCP server (DiagramGPT)"
  type        = string
  sensitive   = true
  default     = ""
}
