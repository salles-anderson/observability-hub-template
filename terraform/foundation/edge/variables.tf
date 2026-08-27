# =============================================================================
# hub-foundation-edge — variaveis do "edge plane" (ALB + listeners + ACM + WAF
# + route53).
#
# Tipos e defaults replicados de terraform/environment/build/variables.tf para
# garantir paridade no-op com o monolito. Valores reais (nao-sensiveis) vem do
# terraform.tfvars. NAO inventar nomes/tipos: tudo espelha o build para que o
# import (Task E4) feche plan no-op.
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
# ALB (module.alb + aws_lb_listener.http/https)
# -----------------------------------------------------------------------------
variable "alb_name" {
  description = "Nome do Application Load Balancer (sufixo, concatenado ao name_prefix)"
  type        = string
  default     = "obs-hub-alb"
}

variable "alb_internal" {
  description = "Se o ALB e interno (controla subnet_ids: private quando true, public quando false)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# ACM + Route53 (module.acm, module.route53_records, aws_route53_record.teck_ai)
# -----------------------------------------------------------------------------
variable "hosted_zone_id" {
  description = "ID da Hosted Zone no Route53"
  type        = string
}

variable "domain_name" {
  description = "Dominio base para o Observability Hub (ex: observability.tower.yourorg.com.br). O ACM cobre *.$${domain} + apex."
  type        = string
}

# -----------------------------------------------------------------------------
# WAFv2 — Hub ALB protection (waf.tf)
# -----------------------------------------------------------------------------
# CIDRs permitidos no Hub ALB. Vazio = WAF nao e criado (count = 0).
# ⚠️ DRIFT CONHECIDO (gabarito 2026-06-15): o build tfvars tem 15 CIDRs, mas o
# state/AWS tem apenas 13 aplicados (TFC nunca reconciliou). Para o scaffold (E2)
# replicamos os 15 verbatim do build. A decisao de reconciliacao no-op
# (ignore_changes vs alinhar aos 13) e DEFERIDA para a Task E4 (religacao/import).
variable "waf_allowed_cidrs" {
  description = "CIDRs permitidos para acessar o Hub ALB (Grafana, SonarQube, Chainlit). Vazio = WAF desativado."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Feature flags de paridade
# -----------------------------------------------------------------------------
# enable_chainlit gateia o A-alias `ai.` (aws_route53_record.teck_ai[0]) — esse e
# o unico recurso edge gated por essa flag. Mantido = build para o count bater.
variable "enable_chainlit" {
  description = "Habilitar Chainlit (gateia o A-alias ai.$${domain} -> ALB em aws_route53_record.teck_ai)."
  type        = bool
  default     = false
}
