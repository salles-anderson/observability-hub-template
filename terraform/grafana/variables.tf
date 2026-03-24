# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "grafana_url" {
  description = "URL do Grafana"
  type        = string
  default     = "https://grafana.observability.tower.yourorg.com.br"
}

variable "grafana_auth" {
  description = "Token de autenticacao do Grafana (Service Account)"
  type        = string
  sensitive   = true
}

variable "accounts" {
  description = "AWS accounts com seus projetos e ambientes"
  type = map(object({
    name = string
    id   = string
    projects = map(object({
      name             = string
      environments     = list(string)
      service_job      = string
      ecs_cluster_name = optional(string, "")
      ecs_service_name = optional(string, "")
      templates        = optional(list(string), ["api-overview", "logs", "traces", "ecs-metrics"])
      alb_arn_suffix   = optional(string, "")
      rds_instance_id  = optional(string, "")
      redis_cluster_id = optional(string, "")
      sqs_queue_name   = optional(string, "")
      sqs_dlq_name     = optional(string, "")
    }))
  }))
  default = {
    yourorg-dev = {
      name = "YOUR_ORG-Dev"
      id   = "YOUR_DEV_ACCOUNT_ID"
      projects = {
        example-api = {
          name             = "Tecksign"
          environments     = ["dev"]
          service_job      = "example-api-api"
          ecs_cluster_name = "cluster-dev"
          ecs_service_name = "example-api-dev-api"
          rds_instance_id  = "example-api-dev-rds"
          redis_cluster_id = "example-api-dev-redis-001"
        }
        gestao-cartao = {
          name             = "Gestao Cartao"
          environments     = ["dev"]
          service_job      = "gestao-cartao-api"
          ecs_cluster_name = "cluster-dev"
          ecs_service_name = "gestao-cartao-web-api-dev"
          templates        = ["ecs-metrics", "logs"]
        }
      }
    }
    yourorg-homolog = {
      name = "YOUR_ORG-Homolog"
      id   = "YOUR_HML_ACCOUNT_ID"
      projects = {
        example-api = {
          name             = "Tecksign"
          environments     = ["hml"]
          service_job      = "example-api-api"
          ecs_cluster_name = "cluster-homolog"
          ecs_service_name = "example-api-homolog-api"
          rds_instance_id  = "example-api-homolog-rds"
          redis_cluster_id = "example-api-homolog-redis-001"
        }
      }
    }
    yourorg-prod = {
      name = "YOUR_ORG-Prod"
      id   = "YOUR_PRD_ACCOUNT_ID"
      projects = {
        example-api = {
          name             = "Tecksign"
          environments     = ["prd"]
          service_job      = "example-api-api"
          ecs_cluster_name = "cluster-prod"
          ecs_service_name = "example-api-prod-api"
          rds_instance_id  = "example-api-prod-rds"
          redis_cluster_id = "example-api-prod-redis-001"
        }
      }
    }
    yourorg-infra = {
      name = "YOUR_ORG-Infra"
      id   = "YOUR_INFRA_ACCOUNT_ID"
      projects = {
        kong = {
          name             = "Kong Gateway"
          environments     = ["prod"]
          service_job      = "kong-gateway"
          ecs_cluster_name = "cluster-prod"
          ecs_service_name = "kong-gateway-prod"
          templates        = ["ecs-metrics", "traces"]
        }
      }
    }
    abccard = {
      name = "ABC-Card"
      id   = "381491855323"
      projects = {
        unico-web-api = {
          name             = "Unico Web API"
          environments     = ["prod"]
          service_job      = "unico-web-api"
          ecs_cluster_name = "unico-web-api-abc-prod"
          ecs_service_name = "unico-web-api-abc-prod-api"
          templates        = ["api-overview", "logs", "traces", "ecs-metrics"]
        }
      }
    }
    akrk-dev = {
      name = "AKRK-Dev"
      id   = "YOUR_AKRK_ACCOUNT_ID"
      projects = {
        solis = {
          name             = "Solis"
          environments     = ["prod"]
          service_job      = "solis"
          ecs_cluster_name = "cluster-prod"
          ecs_service_name = "solis-prod-api"
          templates        = ["api-overview", "logs", "traces", "ecs-metrics", "alb", "rds", "elasticache-redis", "sqs"]
          alb_arn_suffix   = "app/solis-prod-alb/0d3eb93e00545077"
          rds_instance_id  = "solis-prod-cluster-01"
          redis_cluster_id = "solis-prod-redis"
          sqs_queue_name   = "solis-queue"
          sqs_dlq_name     = "solis-dlq"
        }
        unico-webhook = {
          name             = "Unico Webhook"
          environments     = ["prod"]
          service_job      = "frontconsig-unico-webhook"
          ecs_cluster_name = "cluster-prod"
          ecs_service_name = "frontconsig-unico-webhook-prod"
          templates        = ["api-overview", "logs", "traces", "ecs-metrics", "alb"]
          alb_arn_suffix   = "app/lb-fc-unico-webhook-prod/9ea0318d8ff2396b"
        }
        consulta-rf = {
          name             = "Consulta Receita Federal"
          environments     = ["prod"]
          service_job      = "frontconsig-consulta-rf-api"
          ecs_cluster_name = "cluster-prod"
          ecs_service_name = "frontconsig-consulta-receitafederal-web-api-api"
          templates        = ["api-overview", "logs", "traces", "ecs-metrics", "alb", "rds"]
          alb_arn_suffix   = "app/frontconsig-rf-api-alb/a686b99f43eae08b"
          rds_instance_id  = "frontconsig-consulta-rf-web-api"
        }
      }
    }
  }
}

variable "datasources" {
  description = "UIDs dos datasources do Grafana"
  type = object({
    prometheus              = string
    tempo                   = string
    loki                    = string
    cloudwatch_dev          = string
    cloudwatch_homolog      = string
    cloudwatch_prod         = string
    cloudwatch_infra        = string
    cloudwatch_observability = string
    cloudwatch_akrkdev      = string
    cloudwatch_abccard      = string
  })
  default = {
    prometheus               = "dfayih0fcmozkc"
    tempo                    = "dfaygwy06ufi8f"
    loki                     = "afayiiplslon4a"
    cloudwatch_dev           = "cfazk5yq2muwwc"
    cloudwatch_homolog       = "bfazl2wvdcohsc"
    cloudwatch_prod          = "bfazl4ay9kd1cd"
    cloudwatch_infra         = "dfazl8pi4jlkwa"
    cloudwatch_observability = "cloudwatch-observability"
    cloudwatch_akrkdev       = "cloudwatch-akrkdev"
    cloudwatch_abccard       = "cloudwatch-abccard"
  }
}

# -----------------------------------------------------------------------------
# Incidents API (Sprint 5C)
# -----------------------------------------------------------------------------
variable "incidents_api_url" {
  description = "URL base da API de incidentes (API Gateway GET /incidents)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Smart Query Assistant API (Sprint 5D)
# -----------------------------------------------------------------------------
variable "query_assist_api_url" {
  description = "URL base da API Smart Query Assistant (API Gateway POST /query-assist)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# PostgreSQL - Example API DEV (Business Metrics Dashboard)
# -----------------------------------------------------------------------------
variable "example-api_dev_db_password" {
  description = "Password for grafana_readonly user on example-api-dev-rds (SELECT-only)"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Grafana Admin (Basic Auth — for user management)
# -----------------------------------------------------------------------------
variable "grafana_admin_user" {
  description = "Grafana admin username for user management (basic auth)"
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana admin password for user management (basic auth)"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# AIOps Agent - API Gateway ID (Sprint 7A)
# -----------------------------------------------------------------------------
variable "aiops_apigw_api_id" {
  description = "ID do API Gateway v2 (para metricas CloudWatch no dashboard do Agent)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# AIOps Agent - Webhook URL (Sprint 7B - Alert Enrichment)
# -----------------------------------------------------------------------------
variable "aiops_webhook_url" {
  description = "URL do webhook v2 do AIOps Agent (API GW POST /v2/webhook/alertmanager)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Grafana Users
# -----------------------------------------------------------------------------
# Variavel removida: grafana_user resources requerem basic auth no provider.
# Usuarios sao gerenciados diretamente na UI do Grafana.

# -----------------------------------------------------------------------------
# PostgreSQL Credentials (desabilitado temporariamente)
# -----------------------------------------------------------------------------
# variable "postgresql_dev_username" {
#   description = "Username do PostgreSQL DEV"
#   type        = string
#   default     = "grafana_readonly"
# }
#
# variable "postgresql_dev_password" {
#   description = "Password do PostgreSQL DEV"
#   type        = string
#   sensitive   = true
# }
