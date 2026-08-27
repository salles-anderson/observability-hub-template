# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------
project      = "teck-obs-hub"
environment  = "prod"
owner        = "DevOps"
account_id   = "111111111111"
account_name = "teck-observability"
aws_region   = "us-east-1"

# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------
ecs_cluster_name   = "cluster-prod"
container_insights = true

# -----------------------------------------------------------------------------
# Spoke VPCs (enviam telemetria para o Hub)
# VPCs conectadas via VPC Peering (spoke_vpc_cidrs)
# NOTA: VPCs akrk-dev (172.16.0.0/16 e 172.17.0.0/16) são gerenciadas via
#       Transit Gateway no repositório vpc-core, NÃO adicionar aqui.
# -----------------------------------------------------------------------------
spoke_vpc_cidrs = [
  # "172.18.0.0/16", # YourOrg-Homolog (333333333333) - movido para tgw_spoke_vpc_cidrs (conflito CIDR com ABC Card)
  # "172.19.0.0/16", # YourOrg-Dev (222222222222) - migrado para TGW
  "172.20.0.0/16", # YourOrg-Prod (444444444444)
  "172.22.0.0/16", # Admin (131313131313)
  "172.23.0.0/16", # Capital-Dev (888888888888)
  "172.24.0.0/16", # Capital-Homolog (888888888888)
  "172.25.0.0/16", # Capital-Prod (888888888888)
  "172.26.0.0/16", # HubDigital-Dev (999999999999)
  "172.27.0.0/16", # HubDigital-Homolog (999999999999)
  "172.28.0.0/16", # HubDigital-Prod (999999999999)
  "172.29.0.0/16", # Infra (555555555555)
]

# Peering atual (sera substituido por Transit Gateway na Sprint 3)
# NOTA: a variable vpc_peering_connection_id e declarada inline em
#       vpc-peering-routes.tf, que chega na Task 2 deste split.
vpc_peering_connection_id = "pcx-00000000000000001"

# Spoke VPCs que precisam resolver *.observability.local (Cloud Map PHZ)
# Adicionar VPC IDs conforme accounts forem onboarded com sidecars OTel
spoke_vpc_dns_associations = {
  yourorg-dev     = "vpc-00000000000000004" # 222222222222
  abccard-prod         = "vpc-00000000000000003" # 666666666666
  yourorg-homolog = "vpc-00000000000000022" # 333333333333 (VPC tecksign)
  platform-homolog     = "vpc-00000000000000006" # 333333333333 (VPC gestao-cartao platform-homolog)
  apus-dock-homolog    = "vpc-00000000000000018" # 666666666666 (edge apus dock)
  capital-dock-homolog = "vpc-00000000000000020" # 888888888888 (edge capital dock)
  # yourorg-prod    = "vpc-xxx"          # 444444444444
  # capital-dev          = "vpc-xxx"          # 888888888888
  # hubdigital-dev       = "vpc-xxx"          # 999999999999
}

# -----------------------------------------------------------------------------
# Grafana LLM - LiteLLM Proxy + Bedrock (Sprint 5)
# -----------------------------------------------------------------------------
enable_grafana_llm = true

# -----------------------------------------------------------------------------
# Qdrant - Vector Store for RAG (Sprint S11)
# -----------------------------------------------------------------------------
enable_qdrant = true

# -----------------------------------------------------------------------------
# Flags que no monolito vinham de TFC workspace variables (nao do tfvars).
# Setadas aqui explicitamente para que o for_each de
# local.service_discovery_services produza os MESMOS 11 services do state
# (chainlit_chat + mcp_servers + mcp_sre via enable_chainlit; aiops-agent-apigw
# via enable_agent_sdk) -> garante plan no-op no novo workspace.
# -----------------------------------------------------------------------------
enable_chainlit  = true
enable_agent_sdk = true

# -----------------------------------------------------------------------------
# Tags adicionais (paridade com build/terraform.tfvars — fecha plan no-op:
# os 14 recursos de rede importados carregam Team=DevOps na AWS)
# -----------------------------------------------------------------------------
tags = {
  Team = "DevOps"
}

# Rollout agents-api (Plano B / Task 8) — liga o service discovery agents-api.observability.local
enable_agents_api = true
