# -----------------------------------------------------------------------------
# Grafana Provider Configuration
# -----------------------------------------------------------------------------
data "aws_ssm_parameter" "grafana_admin_password" {
  name            = aws_ssm_parameter.grafana_admin_password.name
  with_decryption = true

  depends_on = [aws_ssm_parameter.grafana_admin_password]
}

provider "grafana" {
  url  = "https://grafana.${var.domain_name}"
  auth = "admin:${data.aws_ssm_parameter.grafana_admin_password.value}"
}

# -----------------------------------------------------------------------------
# Variables - Projetos Configurados
# -----------------------------------------------------------------------------
variable "grafana_projects" {
  description = "Lista de projetos para configurar no Grafana"
  type = map(object({
    name                  = string
    alert_emails          = list(string)
    environments          = list(string)
    error_rate_threshold  = optional(number, 5)
    latency_p95_threshold = optional(number, 2)
  }))
  default = {
    # Tecksign agora é gerenciado pelo módulo terraform/grafana
    # com dashboards/alertas usando métricas OTEL corretas
  }
}

# -----------------------------------------------------------------------------
# Folders - Organizacao por Projeto (Dinamico)
# -----------------------------------------------------------------------------
resource "grafana_folder" "projects" {
  for_each = var.grafana_projects

  title = each.value.name
}

resource "grafana_folder" "projects_alerts" {
  for_each = var.grafana_projects

  title = "${each.value.name} - Alerts"
}

# -----------------------------------------------------------------------------
# Dashboard - Overview (Dinamico por Projeto)
# -----------------------------------------------------------------------------
resource "grafana_dashboard" "overview" {
  for_each = var.grafana_projects

  folder = grafana_folder.projects[each.key].uid

  config_json = jsonencode({
    title = "${each.value.name} - Overview"
    uid   = "${each.key}-overview"
    tags  = [each.key, "overview"]

    templating = {
      list = [
        {
          name    = "environment"
          type    = "custom"
          current = { value = each.value.environments[0], text = each.value.environments[0] }
          options = [for env in each.value.environments : { value = env, text = env }]
        },
        {
          name       = "service"
          type       = "query"
          datasource = { type = "prometheus", uid = "prometheus" }
          query      = "label_values(up{project=\"${each.key}\"}, service)"
          refresh    = 2
          includeAll = true
          multi      = true
        }
      ]
    }

    panels = [
      # Row: Service Health
      {
        type      = "row"
        title     = "Service Health"
        gridPos   = { x = 0, y = 0, w = 24, h = 1 }
        collapsed = false
      },
      {
        type       = "stat"
        title      = "Services Up"
        gridPos    = { x = 0, y = 1, w = 6, h = 4 }
        datasource = { type = "prometheus", uid = "prometheus" }
        targets = [
          {
            expr         = "count(up{project=\"${each.key}\", environment=\"$environment\"} == 1) or vector(0)"
            legendFormat = "Up"
          }
        ]
        options = { colorMode = "background", graphMode = "none" }
        fieldConfig = {
          defaults = {
            thresholds = {
              mode = "absolute"
              steps = [
                { color = "red", value = null },
                { color = "green", value = 1 }
              ]
            }
          }
        }
      },
      {
        type       = "stat"
        title      = "Services Down"
        gridPos    = { x = 6, y = 1, w = 6, h = 4 }
        datasource = { type = "prometheus", uid = "prometheus" }
        targets = [
          {
            expr         = "count(up{project=\"${each.key}\", environment=\"$environment\"} == 0) or vector(0)"
            legendFormat = "Down"
          }
        ]
        options = { colorMode = "background", graphMode = "none" }
        fieldConfig = {
          defaults = {
            thresholds = {
              mode = "absolute"
              steps = [
                { color = "green", value = null },
                { color = "red", value = 1 }
              ]
            }
          }
        }
      },
      {
        type       = "gauge"
        title      = "Availability"
        gridPos    = { x = 12, y = 1, w = 6, h = 4 }
        datasource = { type = "prometheus", uid = "prometheus" }
        targets = [
          {
            expr         = "(avg(up{project=\"${each.key}\", environment=\"$environment\"}) or vector(1)) * 100"
            legendFormat = "Availability"
          }
        ]
        fieldConfig = {
          defaults = {
            unit = "percent"
            min  = 0
            max  = 100
            thresholds = {
              mode = "absolute"
              steps = [
                { color = "red", value = null },
                { color = "yellow", value = 90 },
                { color = "green", value = 99 }
              ]
            }
          }
        }
      },
      {
        type       = "timeseries"
        title      = "Request Rate"
        gridPos    = { x = 18, y = 1, w = 6, h = 4 }
        datasource = { type = "prometheus", uid = "prometheus" }
        targets = [
          {
            expr         = "sum(rate(http_requests_total{project=\"${each.key}\", environment=\"$environment\"}[5m])) or vector(0)"
            legendFormat = "req/s"
          }
        ]
      },

      # Row: HTTP Metrics
      {
        type      = "row"
        title     = "HTTP Metrics"
        gridPos   = { x = 0, y = 5, w = 24, h = 1 }
        collapsed = false
      },
      {
        type       = "timeseries"
        title      = "Request Rate by Service"
        gridPos    = { x = 0, y = 6, w = 12, h = 8 }
        datasource = { type = "prometheus", uid = "prometheus" }
        targets = [
          {
            expr         = "sum by (service) (rate(http_requests_total{project=\"${each.key}\", environment=\"$environment\", service=~\"$service\"}[5m]))"
            legendFormat = "{{service}}"
          }
        ]
        options = { legend = { displayMode = "table", placement = "right" } }
      },
      {
        type       = "timeseries"
        title      = "Error Rate by Service"
        gridPos    = { x = 12, y = 6, w = 12, h = 8 }
        datasource = { type = "prometheus", uid = "prometheus" }
        targets = [
          {
            expr         = "sum by (service) (rate(http_requests_total{project=\"${each.key}\", environment=\"$environment\", service=~\"$service\", status=~\"5..\"}[5m])) or vector(0)"
            legendFormat = "{{service}}"
          }
        ]
        options = { legend = { displayMode = "table", placement = "right" } }
      },
      {
        type       = "timeseries"
        title      = "Latency P95 by Service"
        gridPos    = { x = 0, y = 14, w = 12, h = 8 }
        datasource = { type = "prometheus", uid = "prometheus" }
        targets = [
          {
            expr         = "histogram_quantile(0.95, sum by (service, le) (rate(http_request_duration_seconds_bucket{project=\"${each.key}\", environment=\"$environment\", service=~\"$service\"}[5m])))"
            legendFormat = "{{service}}"
          }
        ]
        fieldConfig = { defaults = { unit = "s" } }
      },
      {
        type       = "timeseries"
        title      = "Latency P99 by Service"
        gridPos    = { x = 12, y = 14, w = 12, h = 8 }
        datasource = { type = "prometheus", uid = "prometheus" }
        targets = [
          {
            expr         = "histogram_quantile(0.99, sum by (service, le) (rate(http_request_duration_seconds_bucket{project=\"${each.key}\", environment=\"$environment\", service=~\"$service\"}[5m])))"
            legendFormat = "{{service}}"
          }
        ]
        fieldConfig = { defaults = { unit = "s" } }
      },

      # Row: Resources
      {
        type      = "row"
        title     = "Resources"
        gridPos   = { x = 0, y = 22, w = 24, h = 1 }
        collapsed = false
      },
      {
        type       = "timeseries"
        title      = "CPU Usage by Service"
        gridPos    = { x = 0, y = 23, w = 12, h = 8 }
        datasource = { type = "prometheus", uid = "prometheus" }
        targets = [
          {
            expr         = "sum by (service) (rate(process_cpu_seconds_total{project=\"${each.key}\", environment=\"$environment\", service=~\"$service\"}[5m])) * 100"
            legendFormat = "{{service}}"
          }
        ]
        fieldConfig = { defaults = { unit = "percent" } }
      },
      {
        type       = "timeseries"
        title      = "Memory Usage by Service"
        gridPos    = { x = 12, y = 23, w = 12, h = 8 }
        datasource = { type = "prometheus", uid = "prometheus" }
        targets = [
          {
            expr         = "sum by (service) (process_resident_memory_bytes{project=\"${each.key}\", environment=\"$environment\", service=~\"$service\"})"
            legendFormat = "{{service}}"
          }
        ]
        fieldConfig = { defaults = { unit = "bytes" } }
      }
    ]

    time    = { from = "now-1h", to = "now" }
    refresh = "30s"
  })
}

# -----------------------------------------------------------------------------
# Dashboard - Logs (Dinamico por Projeto)
# -----------------------------------------------------------------------------
resource "grafana_dashboard" "logs" {
  for_each = var.grafana_projects

  folder = grafana_folder.projects[each.key].uid

  config_json = jsonencode({
    title = "${each.value.name} - Logs"
    uid   = "${each.key}-logs"
    tags  = [each.key, "logs"]

    templating = {
      list = [
        {
          name    = "environment"
          type    = "custom"
          current = { value = each.value.environments[0], text = each.value.environments[0] }
          options = [for env in each.value.environments : { value = env, text = env }]
        },
        {
          name       = "service"
          type       = "query"
          datasource = { type = "loki", uid = "loki" }
          query      = "label_values({project=\"${each.key}\"}, service)"
          refresh    = 2
          includeAll = true
          multi      = true
        },
        {
          name    = "level"
          type    = "custom"
          current = { value = "", text = "All" }
          options = [
            { value = "", text = "All" },
            { value = "error", text = "Error" },
            { value = "warn", text = "Warn" },
            { value = "info", text = "Info" },
            { value = "debug", text = "Debug" }
          ]
        },
        {
          name    = "search"
          type    = "textbox"
          current = { value = "", text = "" }
        }
      ]
    }

    panels = [
      {
        type       = "logs"
        title      = "Application Logs"
        gridPos    = { x = 0, y = 0, w = 24, h = 20 }
        datasource = { type = "loki", uid = "loki" }
        targets = [
          {
            expr = "{project=\"${each.key}\", environment=\"$environment\", service=~\"$service\"} |~ \"$level\" |~ \"$search\""
          }
        ]
        options = {
          showTime           = true
          showLabels         = true
          wrapLogMessage     = true
          prettifyLogMessage = true
          enableLogDetails   = true
          sortOrder          = "Descending"
        }
      },
      {
        type       = "timeseries"
        title      = "Log Volume by Level"
        gridPos    = { x = 0, y = 20, w = 12, h = 6 }
        datasource = { type = "loki", uid = "loki" }
        targets = [
          {
            expr         = "sum by (level) (count_over_time({project=\"${each.key}\", environment=\"$environment\", service=~\"$service\"}[1m]))"
            legendFormat = "{{level}}"
          }
        ]
      },
      {
        type       = "timeseries"
        title      = "Logs by Service"
        gridPos    = { x = 12, y = 20, w = 12, h = 6 }
        datasource = { type = "loki", uid = "loki" }
        targets = [
          {
            expr         = "sum by (service) (count_over_time({project=\"${each.key}\", environment=\"$environment\", service=~\"$service\"}[1m]))"
            legendFormat = "{{service}}"
          }
        ]
      }
    ]

    time    = { from = "now-1h", to = "now" }
    refresh = "30s"
  })
}

# -----------------------------------------------------------------------------
# Dashboard - Traces (Dinamico por Projeto)
# -----------------------------------------------------------------------------
resource "grafana_dashboard" "traces" {
  for_each = var.grafana_projects

  folder = grafana_folder.projects[each.key].uid

  config_json = jsonencode({
    title = "${each.value.name} - Traces"
    uid   = "${each.key}-traces"
    tags  = [each.key, "traces"]

    templating = {
      list = [
        {
          name    = "environment"
          type    = "custom"
          current = { value = each.value.environments[0], text = each.value.environments[0] }
          options = [for env in each.value.environments : { value = env, text = env }]
        },
        {
          name       = "service"
          type       = "query"
          datasource = { type = "tempo", uid = "tempo" }
          query      = "label_values(service.name)"
          refresh    = 2
        }
      ]
    }

    panels = [
      {
        type       = "traces"
        title      = "Recent Traces"
        gridPos    = { x = 0, y = 0, w = 24, h = 16 }
        datasource = { type = "tempo", uid = "tempo" }
        targets = [
          {
            queryType = "traceql"
            query     = "{ resource.service.name=~\".*${each.key}.*\" || resource.project=\"${each.key}\" }"
            limit     = 20
          }
        ]
      },
      {
        type       = "timeseries"
        title      = "Span Duration P95"
        gridPos    = { x = 0, y = 16, w = 12, h = 8 }
        datasource = { type = "prometheus", uid = "prometheus" }
        targets = [
          {
            expr         = "histogram_quantile(0.95, sum by (service_name, le) (rate(traces_spanmetrics_latency_bucket{service_name=~\".*${each.key}.*\"}[5m])))"
            legendFormat = "{{service_name}}"
          }
        ]
        fieldConfig = { defaults = { unit = "s" } }
      },
      {
        type       = "timeseries"
        title      = "Span Rate"
        gridPos    = { x = 12, y = 16, w = 12, h = 8 }
        datasource = { type = "prometheus", uid = "prometheus" }
        targets = [
          {
            expr         = "sum by (service_name) (rate(traces_spanmetrics_calls_total{service_name=~\".*${each.key}.*\"}[5m]))"
            legendFormat = "{{service_name}}"
          }
        ]
      }
    ]

    time    = { from = "now-1h", to = "now" }
    refresh = "30s"
  })
}

# -----------------------------------------------------------------------------
# Alert Rules (Dinamico por Projeto)
# -----------------------------------------------------------------------------
resource "grafana_rule_group" "alerts" {
  for_each = var.grafana_projects

  name             = "${each.key}-alerts"
  folder_uid       = grafana_folder.projects_alerts[each.key].uid
  interval_seconds = 60
  org_id           = 1

  # Alert: High Error Rate
  rule {
    name      = "High Error Rate - ${each.value.name}"
    condition = "C"

    data {
      ref_id         = "A"
      datasource_uid = "prometheus"
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        expr  = "(sum(rate(http_requests_total{project=\"${each.key}\", status=~\"5..\"}[5m])) / sum(rate(http_requests_total{project=\"${each.key}\"}[5m]))) * 100 or vector(0)"
        refId = "A"
      })
    }

    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 0
        to   = 0
      }
      model = jsonencode({
        type       = "reduce"
        expression = "A"
        reducer    = "last"
        refId      = "B"
      })
    }

    data {
      ref_id         = "C"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 0
        to   = 0
      }
      model = jsonencode({
        type       = "threshold"
        expression = "B"
        conditions = [{ evaluator = { type = "gt", params = [each.value.error_rate_threshold] } }]
        refId      = "C"
      })
    }

    annotations = {
      summary     = "High error rate detected for ${each.value.name}"
      description = "Error rate is above ${each.value.error_rate_threshold}% for the last 5 minutes"
    }

    labels = {
      severity = "critical"
      project  = each.key
    }
  }

  # Alert: High Latency
  rule {
    name      = "High Latency P95 - ${each.value.name}"
    condition = "C"

    data {
      ref_id         = "A"
      datasource_uid = "prometheus"
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        expr  = "histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{project=\"${each.key}\"}[5m]))) or vector(0)"
        refId = "A"
      })
    }

    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 0
        to   = 0
      }
      model = jsonencode({
        type       = "reduce"
        expression = "A"
        reducer    = "last"
        refId      = "B"
      })
    }

    data {
      ref_id         = "C"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 0
        to   = 0
      }
      model = jsonencode({
        type       = "threshold"
        expression = "B"
        conditions = [{ evaluator = { type = "gt", params = [each.value.latency_p95_threshold] } }]
        refId      = "C"
      })
    }

    annotations = {
      summary     = "High latency detected for ${each.value.name}"
      description = "P95 latency is above ${each.value.latency_p95_threshold}s for the last 5 minutes"
    }

    labels = {
      severity = "warning"
      project  = each.key
    }
  }

  # Alert: Service Down
  rule {
    name      = "Service Down - ${each.value.name}"
    condition = "C"

    data {
      ref_id         = "A"
      datasource_uid = "prometheus"
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        expr  = "up{project=\"${each.key}\"}"
        refId = "A"
      })
    }

    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 0
        to   = 0
      }
      model = jsonencode({
        type       = "reduce"
        expression = "A"
        reducer    = "last"
        refId      = "B"
      })
    }

    data {
      ref_id         = "C"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 0
        to   = 0
      }
      model = jsonencode({
        type       = "threshold"
        expression = "B"
        conditions = [{ evaluator = { type = "lt", params = [1] } }]
        refId      = "C"
      })
    }

    annotations = {
      summary     = "Service down for ${each.value.name}"
      description = "One or more services are down"
    }

    labels = {
      severity = "critical"
      project  = each.key
    }
  }
}

# -----------------------------------------------------------------------------
# Contact Points (Dinamico por Projeto)
# -----------------------------------------------------------------------------
resource "grafana_contact_point" "projects" {
  for_each = var.grafana_projects

  name = "${each.key}-alerts"

  email {
    addresses               = each.value.alert_emails
    single_email            = true
    message                 = "{{ template \"default.message\" . }}"
    subject                 = "[${each.value.name}] {{ .Status | title }}: {{ .CommonLabels.alertname }}"
    disable_resolve_message = false
  }
}

# -----------------------------------------------------------------------------
# Notification Policies (Dinamico por Projeto)
# -----------------------------------------------------------------------------
# Nota: Tecksign usa alertas do módulo terraform/grafana
# Este resource só será criado quando houver projetos em grafana_projects
resource "grafana_notification_policy" "root" {
  count = length(var.grafana_projects) > 0 ? 1 : 0

  contact_point = values(grafana_contact_point.projects)[0].name
  group_by      = ["alertname", "project"]

  dynamic "policy" {
    for_each = var.grafana_projects
    content {
      matcher {
        label = "project"
        match = "="
        value = policy.key
      }
      contact_point   = grafana_contact_point.projects[policy.key].name
      group_wait      = "30s"
      group_interval  = "5m"
      repeat_interval = "4h"
    }
  }
}
