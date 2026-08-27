# =============================================================================
# hub-foundation-lgtm — providers
# =============================================================================
# Workspace dedicado do dominio LGTM (stack de observabilidade: Grafana, Loki,
# Tempo, Prometheus, Alertmanager, Alloy + log groups compartilhados + SSM de
# config). Strangler: importa ~25 recursos do monolito teck-observability-hub-prod
# e prova no-op. S4 = IMPORT-PURO (todo dado stateful ja mora em hub-foundation-data;
# so a camada de servico stateless migra).
#
# Providers replicados do monolito (terraform/environment/build/providers.tf):
#   - aws ~> 5.0 : todos os recursos AWS (task-defs/services ECS, log groups,
#                  SSM de config, target group/listener rule do Grafana).
#
# ⚠️ O monolito declara TAMBEM o provider grafana/grafana ~> 3.0, usado APENAS
# por grafana-provisioning.tf (grafana_folder/grafana_dashboard/grafana_rule_group
# etc.). Esses recursos sao GATED por var.grafana_projects vazio → 0 instancias no
# state (gabarito S4 §"Provider Grafana"). grafana-provisioning.tf NAO migra para o
# ws lgtm (fora de escopo S4) → o provider grafana NAO e declarado aqui. Se uma
# task futura portar grafana-provisioning.tf, adicionar o bloco grafana ~> 3.0.
# =============================================================================
terraform {
  cloud {
    organization = "YourOrg"
    workspaces { name = "hub-foundation-lgtm" }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# AWS Provider
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}
