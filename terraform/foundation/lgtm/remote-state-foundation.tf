# =============================================================================
# Remote State - Foundation (network + security + data + edge + ai-platform)
# =============================================================================
# O dominio LGTM consome read-only os outputs das 5 foundation ws ja extraidas do
# monolito (S1 network, S2 security, S3-data data, S3-edge edge, S5 ai-platform).
# Mapeamento do que cada uma fornece ao lgtm (grep dos arquivos LGTM do build):
#
#   network    → ecs_cluster_id, service_discovery_services[grafana/loki/tempo/
#                prometheus/alertmanager/otel].arn (registries dos 6 ECS services).
#   security   → ecs_task_execution_role_arn, ecs_task_role_arn, ecs_tasks_sg_id
#                (consumidos pelas task-defs/services).
#   data       → efs_id, efs_ap_grafana_id, efs_ap_prometheus_id,
#                efs_ap_alertmanager_id (volumes EFS das task-defs),
#                rds_cluster_endpoint, rds_port (DB Grafana → SSM de config).
#   edge       → https_listener_arn (listener rule do Grafana), alb_dns_name,
#                alb_zone_id (route53 record grafana.).
#   ai_platform→ alert_webhook_api_endpoint (Alertmanager → AG-3 alert_investigator;
#                consumido em alertmanager.tf / ssm-configs.tf). Decisao do
#                controller: o webhook vive no ws ai-platform (S5).
#
# Mesmo padrao de terraform/foundation/ai-platform/remote-state-foundation.tf,
# expandido para incluir ai-platform. Os remote-state-consumers
# (network/security/data/edge/ai-platform → lgtm) sao autorizados via API TFC no
# setup do ws (Task L4).
# =============================================================================

data "terraform_remote_state" "network" {
  backend = "remote"
  config = {
    organization = "YourOrg"
    workspaces = {
      name = "hub-foundation-network"
    }
  }
}

data "terraform_remote_state" "security" {
  backend = "remote"
  config = {
    organization = "YourOrg"
    workspaces = {
      name = "hub-foundation-security"
    }
  }
}

data "terraform_remote_state" "data" {
  backend = "remote"
  config = {
    organization = "YourOrg"
    workspaces = {
      name = "hub-foundation-data"
    }
  }
}

data "terraform_remote_state" "edge" {
  backend = "remote"
  config = {
    organization = "YourOrg"
    workspaces = {
      name = "hub-foundation-edge"
    }
  }
}

data "terraform_remote_state" "ai_platform" {
  backend = "remote"
  config = {
    organization = "YourOrg"
    workspaces = {
      name = "hub-foundation-ai-platform"
    }
  }
}

locals {
  network     = data.terraform_remote_state.network.outputs
  security    = data.terraform_remote_state.security.outputs
  data        = data.terraform_remote_state.data.outputs
  edge        = data.terraform_remote_state.edge.outputs
  ai_platform = data.terraform_remote_state.ai_platform.outputs
}
