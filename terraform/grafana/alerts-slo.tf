# -----------------------------------------------------------------------------
# Grafana Alert Rules - SLO Burn Rate Alerts
# -----------------------------------------------------------------------------
# Multi-window, multi-burn-rate alerts baseados em recording rules do Prometheus.
# Usa a abordagem Google SRE para deteccao de violacao de SLO.
#
# Catalogo SLO por Tier:
#   Tier 1 (99.9%): example-api-api (ATIVO), abccard-api (futuro)
#   Tier 2 (99.5%): capital-api, hubdigital-api, solis-api, akrk-api, funcao-api (todos futuros)
#   Tier 3 (99.0%): todos os ambientes HML/DEV (futuros)
# -----------------------------------------------------------------------------

# Folder dedicada para alertas SLO
resource "grafana_folder" "slo" {
  title = "SLO"
  uid   = "slo-alerts"
}

# -----------------------------------------------------------------------------
# SLO Tier 1: 99.9% Availability (error_budget = 0.001)
# Servicos criticos de producao
# -----------------------------------------------------------------------------
locals {
  slo_tier1_services = {
    "example-api-api" = {
      display_name = "Tecksign API"
      project      = "example-api"
      team         = "backend"
    }
    # Futuros Tier 1 (99.9%):
    # "abccard-api" = {
    #   display_name = "ABC Card API"
    #   project      = "abccard"
    #   team         = "backend"
    # }
  }

  slo_tier2_services = {
    # Futuros Tier 2 (99.5%):
    # "capital-api" = {
    #   display_name = "Capital API"
    #   project      = "yourorg"
    #   team         = "backend"
    # }
    # "hubdigital-api" = {
    #   display_name = "HubDigital API"
    #   project      = "yourorg"
    #   team         = "backend"
    # }
    # "solis-api" = {
    #   display_name = "Solis API"
    #   project      = "solis"
    #   team         = "backend"
    # }
    # "akrk-api" = {
    #   display_name = "AKRK API"
    #   project      = "akrk"
    #   team         = "backend"
    # }
    # "funcao-api" = {
    #   display_name = "Funcao API"
    #   project      = "funcao"
    #   team         = "backend"
    # }
  }
}

# -----------------------------------------------------------------------------
# Burn Rate Alerts - Tier 1 (SLO 99.9%)
# Fast burn: 1h window, burn_rate > 14.4 = esgota budget em ~2h
# Slow burn: 6h window, burn_rate > 6 = esgota budget em ~5h
# Chronic:  1d window, burn_rate > 1 = consumo constante acima do SLO
# -----------------------------------------------------------------------------
resource "grafana_rule_group" "slo_burn_rate_tier1" {
  for_each = local.slo_tier1_services

  name             = "slo-burn-rate-${each.key}"
  folder_uid       = grafana_folder.slo.uid
  interval_seconds = 60

  # Fast Burn Alert (CRITICAL)
  # Se burn_rate_1h > 14.4 E burn_rate_5m > 14.4 (confirmacao)
  rule {
    name      = "SLO Fast Burn - ${each.value.display_name}"
    condition = "C"
    for       = "2m"

    annotations = {
      summary     = "Burn rate critico para ${each.value.display_name} - error budget esgota em ~2h"
      description = "Burn rate 1h: {{ $values.B.Value | printf \"%.1f\" }}x (threshold: 14.4x). O error budget do SLO 99.9% sera totalmente consumido em aproximadamente 2 horas neste ritmo."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/slo/fast-burn"
    }

    labels = {
      severity    = "critical"
      project     = each.value.project
      team        = each.value.team
      slo_tier    = "tier1"
      alert_type  = "burn_rate"
      burn_window = "fast"
    }

    # Query A: Burn rate 1h (recording rule)
    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 3600
        to   = 0
      }

      model = jsonencode({
        expr          = "slo:burn_rate_tier1:1h{job=\"${each.key}\"}"
        refId         = "A"
        intervalMs    = 1000
        maxDataPoints = 43200
      })
    }

    # Reduce to single value
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

    # Threshold: burn_rate > 14.4
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
        refId      = "C"
        conditions = [
          {
            evaluator = {
              type   = "gt"
              params = [14.4]
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Alerting"
  }

  # Slow Burn Alert (WARNING)
  # Se burn_rate_6h > 6
  rule {
    name      = "SLO Slow Burn - ${each.value.display_name}"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Burn rate elevado para ${each.value.display_name} - error budget esgota em ~5h"
      description = "Burn rate 6h: {{ $values.B.Value | printf \"%.1f\" }}x (threshold: 6x). O error budget do SLO 99.9% sera consumido em aproximadamente 5 horas neste ritmo."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/slo/slow-burn"
    }

    labels = {
      severity    = "warning"
      project     = each.value.project
      team        = each.value.team
      slo_tier    = "tier1"
      alert_type  = "burn_rate"
      burn_window = "slow"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 21600
        to   = 0
      }

      model = jsonencode({
        expr          = "slo:burn_rate_tier1:6h{job=\"${each.key}\"}"
        refId         = "A"
        intervalMs    = 1000
        maxDataPoints = 43200
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
        refId      = "C"
        conditions = [
          {
            evaluator = {
              type   = "gt"
              params = [6]
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Alerting"
  }

  # Chronic Burn Alert (INFO)
  # Se burn_rate_1d > 1 (consumindo budget acima do esperado consistentemente)
  rule {
    name      = "SLO Chronic Burn - ${each.value.display_name}"
    condition = "C"
    for       = "30m"

    annotations = {
      summary     = "Consumo cronico de error budget para ${each.value.display_name}"
      description = "Burn rate 1d: {{ $values.B.Value | printf \"%.2f\" }}x (threshold: 1x). O servico esta consistentemente acima do SLO target de 99.9%."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/slo/chronic-burn"
    }

    labels = {
      severity    = "info"
      project     = each.value.project
      team        = each.value.team
      slo_tier    = "tier1"
      alert_type  = "burn_rate"
      burn_window = "chronic"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 86400
        to   = 0
      }

      model = jsonencode({
        expr          = "slo:burn_rate_tier1:1d{job=\"${each.key}\"}"
        refId         = "A"
        intervalMs    = 1000
        maxDataPoints = 43200
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
        refId      = "C"
        conditions = [
          {
            evaluator = {
              type   = "gt"
              params = [1]
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "OK"
  }

  # Latency SLO Alert - P99 > 500ms por 5min
  rule {
    name      = "SLO Latency P99 - ${each.value.display_name}"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Latencia P99 acima do SLO para ${each.value.display_name}"
      description = "Latencia P99: {{ $values.B.Value | printf \"%.0f\" }}ms (SLO: < 500ms). Performance degradada."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/slo/latency-breach"
    }

    labels = {
      severity   = "warning"
      project    = each.value.project
      team       = each.value.team
      slo_tier   = "tier1"
      alert_type = "latency_slo"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = "sli:http_latency_p99:5m{job=\"${each.key}\"}"
        refId         = "A"
        intervalMs    = 1000
        maxDataPoints = 43200
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
        refId      = "C"
        conditions = [
          {
            evaluator = {
              type   = "gt"
              params = [500]
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Alerting"
  }
}

# -----------------------------------------------------------------------------
# Burn Rate Alerts - Tier 2 (SLO 99.5%)
# Thresholds mais relaxados para servicos nao-criticos
# Fast burn: burn_rate > 14.4, Slow burn: burn_rate > 6
# -----------------------------------------------------------------------------
resource "grafana_rule_group" "slo_burn_rate_tier2" {
  for_each = local.slo_tier2_services

  name             = "slo-burn-rate-${each.key}"
  folder_uid       = grafana_folder.slo.uid
  interval_seconds = 60

  # Fast Burn Alert (WARNING - nao critical para tier 2)
  rule {
    name      = "SLO Fast Burn - ${each.value.display_name}"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Burn rate elevado para ${each.value.display_name}"
      description = "Burn rate 1h: {{ $values.B.Value | printf \"%.1f\" }}x (threshold: 14.4x). Error budget do SLO 99.5% em risco."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/slo/fast-burn"
    }

    labels = {
      severity    = "warning"
      project     = each.value.project
      team        = each.value.team
      slo_tier    = "tier2"
      alert_type  = "burn_rate"
      burn_window = "fast"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 3600
        to   = 0
      }

      model = jsonencode({
        expr          = "slo:burn_rate_tier2:1h{job=\"${each.key}\"}"
        refId         = "A"
        intervalMs    = 1000
        maxDataPoints = 43200
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
        refId      = "C"
        conditions = [
          {
            evaluator = {
              type   = "gt"
              params = [14.4]
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Alerting"
  }

  # Slow Burn Alert (INFO para tier 2)
  rule {
    name      = "SLO Slow Burn - ${each.value.display_name}"
    condition = "C"
    for       = "15m"

    annotations = {
      summary     = "Consumo elevado de error budget para ${each.value.display_name}"
      description = "Burn rate 6h: {{ $values.B.Value | printf \"%.1f\" }}x (threshold: 6x). SLO 99.5% em risco."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/slo/slow-burn"
    }

    labels = {
      severity    = "info"
      project     = each.value.project
      team        = each.value.team
      slo_tier    = "tier2"
      alert_type  = "burn_rate"
      burn_window = "slow"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 21600
        to   = 0
      }

      model = jsonencode({
        expr          = "slo:burn_rate_tier2:6h{job=\"${each.key}\"}"
        refId         = "A"
        intervalMs    = 1000
        maxDataPoints = 43200
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
        refId      = "C"
        conditions = [
          {
            evaluator = {
              type   = "gt"
              params = [6]
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "OK"
  }
}

# -----------------------------------------------------------------------------
# Notification Policy: atualizada em notifications.tf (singleton resource)
# -----------------------------------------------------------------------------
