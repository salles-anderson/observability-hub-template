# -----------------------------------------------------------------------------
# Grafana Notification Policies - Alertas via Slack (DEV / HML / PRD / Hub)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Variables - Slack Configuration
# -----------------------------------------------------------------------------
variable "slack_webhook_url" {
  description = "Slack Webhook URL para notificações de alertas"
  type        = string
  sensitive   = true
}

variable "slack_channel" {
  description = "Canal do Slack para alertas de produção"
  type        = string
  default     = "#observability-alerts"
}

variable "slack_username" {
  description = "Nome do bot no Slack"
  type        = string
  default     = "Grafana Alerts"
}

# -----------------------------------------------------------------------------
# Contact Point - Slack (Produção)
# -----------------------------------------------------------------------------
resource "grafana_contact_point" "slack_prod" {
  name = "slack-prod-alerts"

  slack {
    url                     = var.slack_webhook_url
    recipient               = var.slack_channel
    username                = var.slack_username
    icon_emoji              = "{{ if eq .Status \"firing\" }}:rotating_light:{{ else }}:white_check_mark:{{ end }}"
    text                    = <<-EOT
      {{ range .Alerts }}
      *Alert:* `{{ .Labels.alertname }}`
      *Status:* {{ .Status | toUpper }}
      *Severity:* {{ .Labels.severity }}
      *Project:* {{ .Labels.project }}
      *Summary:* {{ .Annotations.summary }}
      *Description:* {{ .Annotations.description }}
      {{ if .Annotations.runbook_url }}:book: <{{ .Annotations.runbook_url }}|View Runbook>{{ end }}
      ---
      {{ end }}
    EOT
    title                   = "{{ if eq .Status \"firing\" }}:fire:{{ else }}:white_check_mark:{{ end }} [PRD] {{ .Status | toUpper }}: {{ .GroupLabels.alertname }}"
    mention_channel         = "channel"
    disable_resolve_message = false
  }
}

# -----------------------------------------------------------------------------
# Contact Point - Slack (Dev)
# -----------------------------------------------------------------------------
resource "grafana_contact_point" "slack_dev" {
  name = "slack-dev-alerts"

  slack {
    url                     = var.slack_webhook_url
    recipient               = var.slack_channel
    username                = var.slack_username
    icon_emoji              = "{{ if eq .Status \"firing\" }}:rotating_light:{{ else }}:white_check_mark:{{ end }}"
    text                    = <<-EOT
      {{ range .Alerts }}
      *Alert:* `{{ .Labels.alertname }}`
      *Status:* {{ .Status | toUpper }}
      *Severity:* {{ .Labels.severity }}
      *Project:* {{ .Labels.project }}
      *Summary:* {{ .Annotations.summary }}
      *Description:* {{ .Annotations.description }}
      {{ if .Annotations.runbook_url }}:book: <{{ .Annotations.runbook_url }}|View Runbook>{{ end }}
      ---
      {{ end }}
    EOT
    title                   = "{{ if eq .Status \"firing\" }}:fire:{{ else }}:white_check_mark:{{ end }} [DEV] {{ .Status | toUpper }}: {{ .GroupLabels.alertname }}"
    mention_channel         = ""
    disable_resolve_message = false
  }
}

# -----------------------------------------------------------------------------
# Contact Point - Webhook AIOps Agent (AI Enrichment - Sprint 7B)
# -----------------------------------------------------------------------------
# Envia alertas para o Agent SDK via API Gateway. O Agent enriquece com AI
# (root cause, evidencias, recomendacoes) e posta no Slack com Block Kit.
# Condicional: so cria se a URL estiver configurada.
# -----------------------------------------------------------------------------
resource "grafana_contact_point" "webhook_aiops" {
  count = var.aiops_webhook_url != "" ? 1 : 0

  name = "webhook-aiops-agent"

  webhook {
    url                     = var.aiops_webhook_url
    http_method             = "POST"
    max_alerts              = 5
    disable_resolve_message = false
  }
}

# -----------------------------------------------------------------------------
# Notification Policy - Multi-Environment Routing
# -----------------------------------------------------------------------------
# Ordem de avaliacao (first match wins):
#   1. project=observability → Slack direto (safety net: se Agent cair, alerta chega)
#   2. alert_type=anomaly → Slack dev (informativo)
#   3. severity=critical → webhook AIOps (AI enrichment via Agent SDK)
#   4. alert_type=burn_rate (warning) → Slack prod (slow burn, nao precisa AI)
#   5. alert_type=latency_slo → Slack prod
#   6. environment=dev → Slack dev
#   Root fallback → Slack prod
# -----------------------------------------------------------------------------
resource "grafana_notification_policy" "main" {
  contact_point   = grafana_contact_point.slack_prod.name
  group_by        = ["alertname", "severity", "environment"]
  group_wait      = "30s"
  group_interval  = "5m"
  repeat_interval = "4h"

  # -----------------------------------------------------------------------
  # 1. Hub (project=observability) - Safety net
  # Alertas do proprio hub (Agent Down, Memory, 5xx, LLM Fallback).
  # Roteados DIRETO para Slack — se o Agent estiver down, esses alertas
  # ainda chegam. Prioridade mais alta para evitar roteamento circular.
  # -----------------------------------------------------------------------
  policy {
    matcher {
      label = "project"
      match = "="
      value = "observability"
    }
    contact_point   = grafana_contact_point.slack_prod.name
    mute_timings    = [grafana_mute_timing.maintenance_window.name]
    group_wait      = "30s"
    group_interval  = "5m"
    repeat_interval = "4h"
    continue        = false
  }

  # -----------------------------------------------------------------------
  # 2. Anomaly Detection - Informativo (z-score > 3σ)
  # -----------------------------------------------------------------------
  policy {
    matcher {
      label = "alert_type"
      match = "="
      value = "anomaly"
    }
    contact_point   = grafana_contact_point.slack_dev.name
    mute_timings    = [grafana_mute_timing.maintenance_window.name]
    group_wait      = "1m"
    group_interval  = "10m"
    repeat_interval = "4h"
    continue        = false
  }

  # -----------------------------------------------------------------------
  # 3. Critical Alerts → AI Enrichment via Agent SDK
  # Todos os alertas severity=critical (exceto observability, ja capturado
  # acima) sao enviados ao Agent SDK para analise com Claude + MCP.
  # O Agent posta no Slack com root cause, evidencias e recomendacoes.
  # Se webhook nao configurado, fallback para Slack direto.
  # -----------------------------------------------------------------------
  policy {
    matcher {
      label = "severity"
      match = "="
      value = "critical"
    }
    contact_point   = var.aiops_webhook_url != "" ? grafana_contact_point.webhook_aiops[0].name : grafana_contact_point.slack_prod.name
    mute_timings    = [grafana_mute_timing.maintenance_window.name]
    group_wait      = "10s"
    group_interval  = "1m"
    repeat_interval = "30m"
    continue        = false
  }

  # -----------------------------------------------------------------------
  # 4. SLO Burn Rate - Warning (Slow Burn)
  # -----------------------------------------------------------------------
  policy {
    matcher {
      label = "alert_type"
      match = "="
      value = "burn_rate"
    }
    matcher {
      label = "severity"
      match = "="
      value = "warning"
    }
    contact_point   = grafana_contact_point.slack_prod.name
    mute_timings    = [grafana_mute_timing.maintenance_window.name]
    group_wait      = "1m"
    group_interval  = "10m"
    repeat_interval = "4h"
    continue        = false
  }

  # -----------------------------------------------------------------------
  # 5. SLO Latency alerts
  # -----------------------------------------------------------------------
  policy {
    matcher {
      label = "alert_type"
      match = "="
      value = "latency_slo"
    }
    contact_point   = grafana_contact_point.slack_prod.name
    mute_timings    = [grafana_mute_timing.maintenance_window.name]
    group_wait      = "1m"
    group_interval  = "5m"
    repeat_interval = "4h"
    continue        = false
  }

  # -----------------------------------------------------------------------
  # 6. DEV - Timings mais relaxados
  # -----------------------------------------------------------------------
  policy {
    matcher {
      label = "environment"
      match = "="
      value = "dev"
    }
    contact_point   = grafana_contact_point.slack_dev.name
    mute_timings    = [grafana_mute_timing.maintenance_window.name]
    group_wait      = "1m"
    group_interval  = "10m"
    repeat_interval = "8h"

    # Sub-policy: critical dev - roteado para webhook se disponivel
    policy {
      matcher {
        label = "severity"
        match = "="
        value = "critical"
      }
      contact_point   = var.aiops_webhook_url != "" ? grafana_contact_point.webhook_aiops[0].name : grafana_contact_point.slack_dev.name
      group_wait      = "30s"
      group_interval  = "5m"
      repeat_interval = "4h"
      continue        = false
    }

    continue = false
  }
}

# -----------------------------------------------------------------------------
# Mute Timings - Janela de Manutenção (opcional)
# -----------------------------------------------------------------------------
resource "grafana_mute_timing" "maintenance_window" {
  name = "maintenance-window"

  intervals {
    weekdays = ["sunday"]
    times {
      start = "02:00"
      end   = "06:00"
    }
  }
}

# no_infra_environments mute timing removido na PoC cleanup

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "slack_contact_point_prod" {
  description = "Contact point Slack configurado para producao"
  value       = grafana_contact_point.slack_prod.name
}

output "slack_contact_point_dev" {
  description = "Contact point Slack configurado para dev"
  value       = grafana_contact_point.slack_dev.name
}

output "webhook_contact_point_aiops" {
  description = "Contact point webhook para AI enrichment (Agent SDK)"
  value       = var.aiops_webhook_url != "" ? grafana_contact_point.webhook_aiops[0].name : null
}
