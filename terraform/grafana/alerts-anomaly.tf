# -----------------------------------------------------------------------------
# Grafana Alert Rules - Anomaly Detection (Z-Score 3σ)
# -----------------------------------------------------------------------------
# Alertas baseados em deteccao estatistica de anomalias usando z-score.
# Disparam quando uma metrica desvia mais de 3 desvios-padrao da media (1h window).
#
# Recording rules fonte (prometheus-rules.yml):
#   anomaly:http_error_rate:zscore_1h   = z-score do error rate (media/stddev 1h)
#   anomaly:http_latency_p95:zscore_1h  = z-score da latencia P95 (media/stddev 1h)
#   anomaly:http_throughput:zscore_1h   = z-score do throughput (media/stddev 1h)
#
# Um z-score > 3 indica que o valor atual esta 3σ acima da media = anomalia.
# Um z-score < -3 indica queda abrupta (ex: throughput drop).
# -----------------------------------------------------------------------------

# Folder dedicada para alertas de anomaly detection
resource "grafana_folder" "anomaly" {
  title = "Anomaly Detection"
  uid   = "anomaly-detection"
}

# -----------------------------------------------------------------------------
# Anomaly Detection Alerts
# Avalia z-scores 1h para error rate, latencia P95 e throughput.
# Usa o mesmo padrao 3-part query chain (Prometheus -> Reduce -> Threshold).
# -----------------------------------------------------------------------------
resource "grafana_rule_group" "anomaly_detection" {
  name             = "anomaly-detection"
  folder_uid       = grafana_folder.anomaly.uid
  interval_seconds = 60

  # -------------------------------------------------------------------------
  # Anomaly: Error Rate (z-score > 3)
  # Error rate significativamente acima da media historica de 1h.
  # -------------------------------------------------------------------------
  rule {
    name      = "Anomaly Error Rate - Z-Score > 3σ"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Anomalia detectada: Error Rate com z-score {{ $values.B.Value | printf \"%.2f\" }} (>3σ)"
      description = "O error rate atual esta {{ $values.B.Value | printf \"%.2f\" }} desvios-padrao acima da media de 1h. Um z-score > 3 indica que o valor esta fora de 99.7% da distribuicao normal, sugerindo um comportamento anomalo que requer investigacao."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/anomaly/error-rate"
    }

    labels = {
      severity  = "warning"
      project   = "example-api"
      team      = "devops"
      alert_type = "anomaly"
      detection = "zscore_3sigma"
    }

    # Query A: Z-score do error rate (recording rule)
    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 3600
        to   = 0
      }

      model = jsonencode({
        expr          = "anomaly:http_error_rate:zscore_1h"
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

    # Threshold: z-score > 3
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
              params = [3]
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "OK"
  }

  # -------------------------------------------------------------------------
  # Anomaly: Latency P95 (z-score > 3)
  # Latencia P95 significativamente acima da media historica de 1h.
  # -------------------------------------------------------------------------
  rule {
    name      = "Anomaly Latency P95 - Z-Score > 3σ"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Anomalia detectada: Latency P95 com z-score {{ $values.B.Value | printf \"%.2f\" }} (>3σ)"
      description = "A latencia P95 atual esta {{ $values.B.Value | printf \"%.2f\" }} desvios-padrao acima da media de 1h. Um z-score > 3 indica degradacao de performance significativa, possivelmente causada por carga elevada, dependencia lenta ou problema de infraestrutura."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/anomaly/latency-p95"
    }

    labels = {
      severity   = "warning"
      project    = "example-api"
      team       = "devops"
      alert_type = "anomaly"
      detection  = "zscore_3sigma"
    }

    # Query A: Z-score da latencia P95 (recording rule)
    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 3600
        to   = 0
      }

      model = jsonencode({
        expr          = "anomaly:http_latency_p95:zscore_1h"
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

    # Threshold: z-score > 3
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
              params = [3]
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "OK"
  }

  # -------------------------------------------------------------------------
  # Anomaly: Throughput Drop (z-score < -3)
  # Queda abrupta no throughput - pode indicar outage parcial ou desvio de trafego.
  # -------------------------------------------------------------------------
  rule {
    name      = "Anomaly Throughput Drop - Z-Score < -3σ"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Anomalia detectada: Throughput com z-score {{ $values.B.Value | printf \"%.2f\" }} (<-3σ)"
      description = "O throughput atual esta {{ $values.B.Value | printf \"%.2f\" }} desvios-padrao abaixo da media de 1h. Um z-score < -3 indica queda abrupta de trafego, possivelmente causada por falha no load balancer, deploy com erro, ou indisponibilidade parcial do servico."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/anomaly/throughput-drop"
    }

    labels = {
      severity   = "warning"
      project    = "example-api"
      team       = "devops"
      alert_type = "anomaly"
      detection  = "zscore_3sigma"
    }

    # Query A: Z-score do throughput (recording rule)
    data {
      ref_id         = "A"
      datasource_uid = var.datasources.prometheus

      relative_time_range {
        from = 3600
        to   = 0
      }

      model = jsonencode({
        expr          = "anomaly:http_throughput:zscore_1h"
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

    # Threshold: z-score < -3
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
              params = [-3]
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "OK"
  }
}
