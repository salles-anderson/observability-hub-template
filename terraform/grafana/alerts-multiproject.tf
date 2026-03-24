# -----------------------------------------------------------------------------
# Grafana Alert Rules - Multi-Project API Alerts
# -----------------------------------------------------------------------------
# Expande alertas basicos de API (error rate, latency, service down) para
# todos os projetos e ambientes usando for_each.
#
# Cada projeto/ambiente que envia metricas OTel recebe automaticamente:
# - High Error Rate (5xx > 5%)
# - High Latency P95 (> 2s)
# - Service Down (0 requests)
# - High Client Error Rate (4xx > 10%)
# -----------------------------------------------------------------------------

locals {
  # ---------------------------------------------------------------------------
  # Catalogo de servicos que enviam metricas OTel HTTP
  # Chave: job label no Prometheus (convencao: {projeto}-{servico}-{ambiente})
  # Nota: example-api-api-dev excluido pois ja tem alertas dedicados em alerts.tf
  #
  # Para onboardar um servico: descomentar a entrada e executar terraform apply.
  # Cada entrada gera 4 alert rules automaticamente (error rate, latency, down, 4xx).
  # ---------------------------------------------------------------------------
  api_services = {
    # --- YOUR_ORG-Dev (YOUR_DEV_ACCOUNT_ID) ---
    # SKIP: example-api-api-dev - alertas dedicados em alerts.tf

    # HML/PRD api_services removidos na PoC cleanup (sem infra provisionada)
    # Para restaurar: git revert deste commit

    # --- ABC Card (381491855323) ---
    # "abccard-api-prd" = {
    #   display_name = "ABC Card API PRD"
    #   project      = "abccard"
    #   environment  = "prd"
    #   account_id   = "381491855323"
    #   folder_uid   = grafana_folder.account_project["abccard-abccard"].uid
    #   team         = "backend"
    #   tier         = "tier2"
    # }

    # --- akrk-dev (YOUR_AKRK_ACCOUNT_ID) - inclui Solis ---
    # "solis-api-hml" = {
    #   display_name = "Solis API HML"
    #   project      = "solis"
    #   environment  = "hml"
    #   account_id   = "YOUR_AKRK_ACCOUNT_ID"
    #   folder_uid   = grafana_folder.account_project["akrk-dev-solis"].uid
    #   team         = "backend"
    #   tier         = "tier3"
    # }
    # "solis-api-prd" = {
    #   display_name = "Solis API PRD"
    #   project      = "solis"
    #   environment  = "prd"
    #   account_id   = "YOUR_AKRK_ACCOUNT_ID"
    #   folder_uid   = grafana_folder.account_project["akrk-dev-solis"].uid
    #   team         = "backend"
    #   tier         = "tier2"
    # }

    # sistema-akrk removido — conta SISTEMA_AKRK (829743355814) excluida do Grafana
  }

  # Thresholds por tier
  tier_config = {
    tier1 = {
      error_rate_threshold  = 5    # 5%
      latency_p95_threshold = 2000 # 2s
      latency_p99_threshold = 500  # 500ms (SLO)
    }
    tier2 = {
      error_rate_threshold  = 5
      latency_p95_threshold = 3000 # 3s
      latency_p99_threshold = 1000 # 1s
    }
    tier3 = {
      error_rate_threshold  = 10   # 10% - mais tolerante
      latency_p95_threshold = 5000 # 5s
      latency_p99_threshold = 2000 # 2s
    }
  }
}

# -----------------------------------------------------------------------------
# API Alerts por servico (Error Rate + Latency + Service Down)
# Substitui o pattern hardcoded do alerts.tf original
# -----------------------------------------------------------------------------
resource "grafana_rule_group" "api_alerts" {
  for_each = local.api_services

  name             = "${each.key}-alerts"
  folder_uid       = each.value.folder_uid
  interval_seconds = 60

  # Alert: High Error Rate (5xx)
  rule {
    name      = "High Error Rate - ${each.value.display_name}"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Taxa de erro acima de ${local.tier_config[each.value.tier].error_rate_threshold}% na ${each.value.display_name}"
      description = "A taxa de erros HTTP 5xx esta em {{ $values.B.Value | printf \"%.2f\" }}% nos ultimos 5 minutos"
      runbook_url = "https://wiki.yourorg.com.br/runbooks/${each.value.project}/high-error-rate"
    }

    labels = {
      severity    = "critical"
      project     = each.value.project
      team        = each.value.team
      environment = each.value.environment
      account_id  = each.value.account_id
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = <<-EOT
          (
            sum(rate(http_server_duration_milliseconds_count{job="${each.key}",http_status_code=~"5.."}[5m]))
            /
            sum(rate(http_server_duration_milliseconds_count{job="${each.key}"}[5m]))
          ) * 100 or vector(0)
        EOT
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
              params = [local.tier_config[each.value.tier].error_rate_threshold]
            }
          }
        ]
      })
    }

    no_data_state  = "NoData"
    exec_err_state = "Alerting"
  }

  # Alert: High Latency P95
  rule {
    name      = "High Latency P95 - ${each.value.display_name}"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Latencia P95 acima de ${local.tier_config[each.value.tier].latency_p95_threshold}ms na ${each.value.display_name}"
      description = "A latencia P95 esta em {{ $values.B.Value | printf \"%.0f\" }}ms nos ultimos 5 minutos"
      runbook_url = "https://wiki.yourorg.com.br/runbooks/${each.value.project}/high-latency"
    }

    labels = {
      severity    = "warning"
      project     = each.value.project
      team        = each.value.team
      environment = each.value.environment
      account_id  = each.value.account_id
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = <<-EOT
          histogram_quantile(0.95,
            sum(rate(http_server_duration_milliseconds_bucket{job="${each.key}"}[5m])) by (le)
          ) or vector(0)
        EOT
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
              params = [local.tier_config[each.value.tier].latency_p95_threshold]
            }
          }
        ]
      })
    }

    no_data_state  = "NoData"
    exec_err_state = "Alerting"
  }

  # Alert: Service Down (No Requests)
  rule {
    name      = "Service Down - ${each.value.display_name}"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "${each.value.display_name} nao esta recebendo requisicoes"
      description = "Nenhuma requisicao HTTP foi registrada nos ultimos 5 minutos. A API pode estar fora do ar."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/${each.value.project}/service-down"
    }

    labels = {
      severity    = "critical"
      project     = each.value.project
      team        = "platform"
      environment = each.value.environment
      account_id  = each.value.account_id
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = "sum(rate(http_server_duration_milliseconds_count{job=\"${each.key}\"}[5m])) or vector(0)"
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
              type   = "lt"
              params = [0.001]
            }
          }
        ]
      })
    }

    no_data_state  = "Alerting"
    exec_err_state = "Alerting"
  }

  # Alert: High Client Error Rate (4xx)
  rule {
    name      = "High Client Error Rate - ${each.value.display_name}"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Taxa de erros 4xx acima de 10% na ${each.value.display_name}"
      description = "A taxa de erros HTTP 4xx esta em {{ $values.B.Value | printf \"%.2f\" }}%. Pode indicar problemas de integracao ou clientes mal configurados."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/${each.value.project}/client-errors"
    }

    labels = {
      severity    = "info"
      project     = each.value.project
      team        = each.value.team
      environment = each.value.environment
      account_id  = each.value.account_id
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = <<-EOT
          (
            sum(rate(http_server_duration_milliseconds_count{job="${each.key}",http_status_code=~"4.."}[5m]))
            /
            sum(rate(http_server_duration_milliseconds_count{job="${each.key}"}[5m]))
          ) * 100 or vector(0)
        EOT
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
              params = [10]
            }
          }
        ]
      })
    }

    no_data_state  = "NoData"
    exec_err_state = "OK"
  }
}

# -----------------------------------------------------------------------------
# Hub Health Alerts - Monitoramento dos componentes do proprio Hub
# -----------------------------------------------------------------------------
resource "grafana_rule_group" "hub_health" {
  name             = "observability-hub-health"
  folder_uid       = "cfb091sktvmdcd" # Observability folder
  interval_seconds = 60

  # Alert: Prometheus Down
  rule {
    name      = "Prometheus Down"
    condition = "C"
    for       = "2m"

    annotations = {
      summary     = "Prometheus nao esta respondendo"
      description = "O Prometheus nao retornou metricas nos ultimos 2 minutos. Verificar ECS task e logs."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/hub/prometheus-down"
    }

    labels = {
      severity = "critical"
      project  = "observability"
      team     = "platform"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 120
        to   = 0
      }

      model = jsonencode({
        expr          = "up{job=\"prometheus\"}"
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
              type   = "lt"
              params = [1]
            }
          }
        ]
      })
    }

    no_data_state  = "Alerting"
    exec_err_state = "Alerting"
  }

  # Alert: Loki Down
  rule {
    name      = "Loki Down"
    condition = "C"
    for       = "2m"

    annotations = {
      summary     = "Loki nao esta respondendo"
      description = "O Loki nao retornou metricas nos ultimos 2 minutos. Logs podem estar sendo perdidos."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/hub/loki-down"
    }

    labels = {
      severity = "critical"
      project  = "observability"
      team     = "platform"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 120
        to   = 0
      }

      model = jsonencode({
        expr          = "up{job=\"loki\"}"
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
              type   = "lt"
              params = [1]
            }
          }
        ]
      })
    }

    no_data_state  = "Alerting"
    exec_err_state = "Alerting"
  }

  # Alert: Tempo Down
  rule {
    name      = "Tempo Down"
    condition = "C"
    for       = "2m"

    annotations = {
      summary     = "Tempo nao esta respondendo"
      description = "O Tempo nao retornou metricas nos ultimos 2 minutos. Traces podem estar sendo perdidos."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/hub/tempo-down"
    }

    labels = {
      severity = "warning"
      project  = "observability"
      team     = "platform"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 120
        to   = 0
      }

      model = jsonencode({
        expr          = "up{job=\"tempo\"}"
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
              type   = "lt"
              params = [1]
            }
          }
        ]
      })
    }

    no_data_state  = "Alerting"
    exec_err_state = "Alerting"
  }

  # Alert: AlertManager Down
  rule {
    name      = "AlertManager Down"
    condition = "C"
    for       = "2m"

    annotations = {
      summary     = "AlertManager nao esta respondendo"
      description = "O AlertManager nao retornou metricas nos ultimos 2 minutos. Alertas podem nao ser roteados."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/hub/alertmanager-down"
    }

    labels = {
      severity = "critical"
      project  = "observability"
      team     = "platform"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 120
        to   = 0
      }

      model = jsonencode({
        expr          = "up{job=\"alertmanager\"}"
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
              type   = "lt"
              params = [1]
            }
          }
        ]
      })
    }

    no_data_state  = "Alerting"
    exec_err_state = "Alerting"
  }

  # Alert: Alloy Down
  rule {
    name      = "Alloy Down"
    condition = "C"
    for       = "2m"

    annotations = {
      summary     = "Alloy nao esta respondendo"
      description = "O Alloy nao retornou metricas nos ultimos 2 minutos. Telemetria (logs, traces, metricas) pode estar sendo perdida."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/hub/alloy-down"
    }

    labels = {
      severity = "critical"
      project  = "observability"
      team     = "platform"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 120
        to   = 0
      }

      model = jsonencode({
        expr          = "up{job=\"alloy\"}"
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
              type   = "lt"
              params = [1]
            }
          }
        ]
      })
    }

    no_data_state  = "Alerting"
    exec_err_state = "Alerting"
  }

  # Alert: Grafana Down
  rule {
    name      = "Grafana Down"
    condition = "C"
    for       = "2m"

    annotations = {
      summary     = "Grafana nao esta respondendo"
      description = "O Grafana nao retornou metricas nos ultimos 2 minutos. Dashboards e alertas visuais indisponiveis."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/hub/grafana-down"
    }

    labels = {
      severity = "critical"
      project  = "observability"
      team     = "platform"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 120
        to   = 0
      }

      model = jsonencode({
        expr          = "up{job=\"grafana\"}"
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
              type   = "lt"
              params = [1]
            }
          }
        ]
      })
    }

    no_data_state  = "Alerting"
    exec_err_state = "Alerting"
  }
}

# -----------------------------------------------------------------------------
# Hub Performance Alerts - Monitoramento de performance dos componentes
# -----------------------------------------------------------------------------
resource "grafana_rule_group" "hub_performance" {
  name             = "observability-hub-performance"
  folder_uid       = "cfb091sktvmdcd" # Observability folder
  interval_seconds = 60

  # Alert: Loki Ingestion Errors
  rule {
    name      = "Loki Ingestion Errors"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Loki esta rejeitando logs"
      description = "Loki esta retornando erros de ingestao. Logs podem estar sendo descartados."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/hub/loki-ingestion-errors"
    }

    labels = {
      severity = "warning"
      project  = "observability"
      team     = "platform"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = "rate(loki_distributor_lines_received_total{status_code!=\"200\"}[5m])"
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
              params = [0]
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Alerting"
  }

  # Alert: Prometheus Scrape Failures
  rule {
    name      = "Prometheus Scrape Failures"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Multiplos targets do Prometheus estao down"
      description = "Mais de 1 scrape target esta falhando. Metricas podem estar incompletas."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/hub/prometheus-scrape-failures"
    }

    labels = {
      severity = "warning"
      project  = "observability"
      team     = "platform"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = "count(up == 0)"
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
    exec_err_state = "Alerting"
  }

  # Alert: Tempo Ingestion Errors
  rule {
    name      = "Tempo Ingestion Errors"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Tempo esta com erros de ingestao"
      description = "O Tempo esta falhando ao ingerir traces. Traces podem estar sendo perdidos."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/hub/tempo-ingestion-errors"
    }

    labels = {
      severity = "warning"
      project  = "observability"
      team     = "platform"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = "rate(tempo_distributor_ingester_append_failures_total[5m])"
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
              params = [0]
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Alerting"
  }

  # Alert: Alloy Exporter Failures
  rule {
    name      = "Alloy Exporter Failures"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Alloy esta falhando ao exportar telemetria"
      description = "O Alloy esta com falhas de exportacao. Dados podem nao estar chegando aos backends (Prometheus, Loki, Tempo)."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/hub/alloy-exporter-failures"
    }

    labels = {
      severity = "warning"
      project  = "observability"
      team     = "platform"
    }

    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = "sum(rate(otelcol_exporter_send_failed_metric_points[5m]) or vector(0)) + sum(rate(otelcol_exporter_send_failed_log_records[5m]) or vector(0)) + sum(rate(otelcol_exporter_send_failed_spans[5m]) or vector(0))"
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
              params = [0]
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
# Anomaly Detection Alerts (Sprint 4 - AIOps)
# -----------------------------------------------------------------------------
# Movido para alerts-anomaly.tf com labels padronizados (alert_type, detection).
# -----------------------------------------------------------------------------
