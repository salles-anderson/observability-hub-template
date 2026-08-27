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
# -----------------------------------------------------------------------------
variable "spoke_vpc_cidrs" {
  description = "CIDRs das VPCs spoke via VPC Peering (usado para rotas e SG)"
  type        = list(string)
  # default vazio forca tfvars como fonte de verdade; evita rotas peering
  # nao-gerenciadas (ver review 2026-06-13)
  default = []
}

variable "spoke_vpc_dns_associations" {
  description = "Map de spoke VPCs para associar com a PHZ do Cloud Map (nome => VPC ID)"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Transit Gateway Integration
# -----------------------------------------------------------------------------
# NOTA: declarada aqui (e nao em transit-gateway.tf como no monolito) porque
# vpc-peering-routes.tf referencia var.enable_tgw_attachment em
# local.use_vpc_peering, e o dominio de TGW nao faz parte deste workspace.
# -----------------------------------------------------------------------------
variable "enable_tgw_attachment" {
  description = "Habilitar attachment do Hub VPC ao Transit Gateway"
  type        = bool
  default     = false
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
# Grafana LLM - LiteLLM Proxy + Anthropic API (Sprint 5)
# -----------------------------------------------------------------------------
variable "enable_grafana_llm" {
  description = "Habilitar LiteLLM proxy para Grafana AI features (grafana-llm-app plugin)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Agent SDK + mcp-grafana - AIOps Autonomous Agents (Sprint 6)
# -----------------------------------------------------------------------------
variable "enable_agent_sdk" {
  description = "Habilitar AIOps Agent SDK com mcp-grafana (ECS Fargate)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Chainlit Chat (Sprint 9A)
# -----------------------------------------------------------------------------
variable "enable_chainlit" {
  description = "Habilitar Chainlit Chat UI (Teck Observability Assistant)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Qdrant - Vector Store for RAG (Sprint S11)
# -----------------------------------------------------------------------------
variable "enable_qdrant" {
  description = "Habilitar Qdrant vector store para RAG runbooks"
  type        = bool
  default     = false
}

variable "enable_agents_api" {
  description = "Habilita o service discovery do agents-api"
  type        = bool
  default     = false
}
