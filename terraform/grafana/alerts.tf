# -----------------------------------------------------------------------------
# Grafana Alert Rules - Tecksign
# -----------------------------------------------------------------------------
# Alertas usando métricas OpenTelemetry corretas:
# - http_server_duration_milliseconds_count
# - http_server_duration_milliseconds_bucket
# -----------------------------------------------------------------------------

locals {
  # Folder Tecksign project (dentro da account YOUR_ORG-Dev)
  alerts_folder_uid = grafana_folder.account_project["yourorg-dev-example-api"].uid

  # Datasource UID do Prometheus
  prometheus_uid = var.datasources.prometheus
}

# -----------------------------------------------------------------------------
# Alert: High Error Rate (>5% em 5min)
# -----------------------------------------------------------------------------
resource "grafana_rule_group" "example-api_api_alerts" {
  name             = "example-api-api-alerts"
  folder_uid       = local.alerts_folder_uid
  interval_seconds = 60

  # Alert 1: High Error Rate
  rule {
    name      = "High Error Rate - Tecksign API"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Taxa de erro acima de 5% na API Tecksign"
      description = "A taxa de erros HTTP 5xx está em {{ $values.B.Value | printf \"%.2f\" }}% nos últimos 5 minutos"
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/high-error-rate"
    }

    labels = {
      severity    = "critical"
      project     = "example-api"
      team        = "backend"
      environment = "dev"
    }

    # Query A: Error rate percentage
    data {
      ref_id         = "A"
      datasource_uid = local.prometheus_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = <<-EOT
          (
            sum(rate(http_server_duration_milliseconds_count{job="example-api-api",http_status_code=~"5.."}[5m]))
            /
            sum(rate(http_server_duration_milliseconds_count{job="example-api-api"}[5m]))
          ) * 100 or vector(0)
        EOT
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

    # Threshold: > 5%
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
              params = [5]
            }
          }
        ]
      })
    }

    no_data_state  = "NoData"
    exec_err_state = "Alerting"
  }

  # Alert 2: High Latency P95
  rule {
    name      = "High Latency P95 - Tecksign API"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Latência P95 acima de 2s na API Tecksign"
      description = "A latência P95 está em {{ $values.B.Value | printf \"%.0f\" }}ms nos últimos 5 minutos"
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/high-latency"
    }

    labels = {
      severity    = "warning"
      project     = "example-api"
      team        = "backend"
      environment = "dev"
    }

    # Query A: P95 latency in milliseconds
    data {
      ref_id         = "A"
      datasource_uid = local.prometheus_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = <<-EOT
          histogram_quantile(0.95,
            sum(rate(http_server_duration_milliseconds_bucket{job="example-api-api"}[5m])) by (le)
          ) or vector(0)
        EOT
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

    # Threshold: > 2000ms (2 seconds)
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
              params = [2000]
            }
          }
        ]
      })
    }

    no_data_state  = "NoData"
    exec_err_state = "Alerting"
  }

  # Alert 3: Service Down (No Requests)
  rule {
    name      = "Service Down - Tecksign API"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "API Tecksign não está recebendo requisições"
      description = "Nenhuma requisição HTTP foi registrada nos últimos 5 minutos. A API pode estar fora do ar."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/service-down"
    }

    labels = {
      severity    = "critical"
      project     = "example-api"
      team        = "platform"
      environment = "dev"
    }

    # Query A: Request rate
    data {
      ref_id         = "A"
      datasource_uid = local.prometheus_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = "sum(rate(http_server_duration_milliseconds_count{job=\"example-api-api\"}[5m])) or vector(0)"
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

    # Threshold: == 0 (no requests)
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

  # Alert 4: High Request Rate (possible attack)
  rule {
    name      = "High Request Rate - Tecksign API"
    condition = "C"
    for       = "2m"

    annotations = {
      summary     = "Taxa de requisições muito alta na API Tecksign"
      description = "A taxa de requisições está em {{ $values.B.Value | printf \"%.0f\" }} req/s. Possível ataque DDoS ou problema de cliente."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/high-request-rate"
    }

    labels = {
      severity    = "warning"
      project     = "example-api"
      team        = "security"
      environment = "dev"
    }

    # Query A: Request rate per second
    data {
      ref_id         = "A"
      datasource_uid = local.prometheus_uid

      relative_time_range {
        from = 60
        to   = 0
      }

      model = jsonencode({
        expr          = "sum(rate(http_server_duration_milliseconds_count{job=\"example-api-api\"}[1m]))"
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

    # Threshold: > 1000 req/s
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
              params = [1000]
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Alerting"
  }

  # Alert 5: High 4xx Client Errors
  rule {
    name      = "High Client Error Rate - Tecksign API"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Taxa de erros 4xx acima de 10% na API Tecksign"
      description = "A taxa de erros HTTP 4xx está em {{ $values.B.Value | printf \"%.2f\" }}%. Pode indicar problemas de integração ou clientes mal configurados."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/client-errors"
    }

    labels = {
      severity    = "info"
      project     = "example-api"
      team        = "backend"
      environment = "dev"
    }

    # Query A: 4xx error rate percentage
    data {
      ref_id         = "A"
      datasource_uid = local.prometheus_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        expr          = <<-EOT
          (
            sum(rate(http_server_duration_milliseconds_count{job="example-api-api",http_status_code=~"4.."}[5m]))
            /
            sum(rate(http_server_duration_milliseconds_count{job="example-api-api"}[5m]))
          ) * 100 or vector(0)
        EOT
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

    # Threshold: > 10%
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
# Alert Rules - Infrastructure (CloudWatch)
# RDS, Redis, SQS, SES
# -----------------------------------------------------------------------------

locals {
  cloudwatch_dev_uid = var.datasources.cloudwatch_dev
}

resource "grafana_rule_group" "example-api_infra_alerts" {
  name             = "example-api-infra-alerts"
  folder_uid       = local.alerts_folder_uid
  interval_seconds = 60

  # Alert: RDS CPU High
  rule {
    name      = "RDS CPU High - Tecksign DEV"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "CPU do RDS acima de 80%"
      description = "O banco de dados RDS example-api-dev-rds está com CPU em {{ $values.B.Value | printf \"%.1f\" }}%"
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/rds-cpu-high"
    }

    labels = {
      severity    = "warning"
      project     = "example-api"
      team        = "platform"
      resource    = "rds"
      environment = "dev"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.cloudwatch_dev_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/RDS"
        metricName = "CPUUtilization"
        dimensions = {
          DBInstanceIdentifier = "example-api-dev-rds"
        }
        statistic = "Average"
        region    = "us-east-1"
        refId     = "A"
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
              params = [80]
            }
          }
        ]
      })
    }

    no_data_state  = "NoData"
    exec_err_state = "Alerting"
  }

  # Alert: RDS Connections High
  rule {
    name      = "RDS Connections High - Tecksign DEV"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Conexoes do RDS acima de 80"
      description = "O banco de dados RDS tem {{ $values.B.Value | printf \"%.0f\" }} conexoes ativas"
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/rds-connections-high"
    }

    labels = {
      severity    = "warning"
      project     = "example-api"
      team        = "backend"
      resource    = "rds"
      environment = "dev"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.cloudwatch_dev_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/RDS"
        metricName = "DatabaseConnections"
        dimensions = {
          DBInstanceIdentifier = "example-api-dev-rds"
        }
        statistic = "Average"
        region    = "us-east-1"
        refId     = "A"
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
              params = [80]
            }
          }
        ]
      })
    }

    no_data_state  = "NoData"
    exec_err_state = "Alerting"
  }

  # Alert: RDS Storage Low
  rule {
    name      = "RDS Storage Low - Tecksign DEV"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Storage do RDS abaixo de 5GB"
      description = "O banco de dados RDS tem apenas {{ $values.B.Value | humanize1024 }}B de espaco livre"
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/rds-storage-low"
    }

    labels = {
      severity    = "critical"
      project     = "example-api"
      team        = "platform"
      resource    = "rds"
      environment = "dev"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.cloudwatch_dev_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/RDS"
        metricName = "FreeStorageSpace"
        dimensions = {
          DBInstanceIdentifier = "example-api-dev-rds"
        }
        statistic = "Average"
        region    = "us-east-1"
        refId     = "A"
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
              params = [5368709120] # 5GB in bytes
            }
          }
        ]
      })
    }

    no_data_state  = "NoData"
    exec_err_state = "Alerting"
  }

  # Alert: Redis CPU High
  rule {
    name      = "Redis CPU High - Tecksign DEV"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "CPU do Redis acima de 80%"
      description = "O cache Redis example-api-dev-redis-001 esta com CPU em {{ $values.B.Value | printf \"%.1f\" }}%"
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/redis-cpu-high"
    }

    labels = {
      severity    = "warning"
      project     = "example-api"
      team        = "platform"
      resource    = "redis"
      environment = "dev"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.cloudwatch_dev_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/ElastiCache"
        metricName = "CPUUtilization"
        dimensions = {
          CacheClusterId = "example-api-dev-redis-001"
        }
        statistic = "Average"
        region    = "us-east-1"
        refId     = "A"
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
              params = [80]
            }
          }
        ]
      })
    }

    no_data_state  = "NoData"
    exec_err_state = "Alerting"
  }

  # Alert: Redis Memory High
  rule {
    name      = "Redis Memory High - Tecksign DEV"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Memoria do Redis acima de 80%"
      description = "O cache Redis esta com {{ $values.B.Value | printf \"%.1f\" }}% de memoria utilizada"
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/redis-memory-high"
    }

    labels = {
      severity    = "warning"
      project     = "example-api"
      team        = "platform"
      resource    = "redis"
      environment = "dev"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.cloudwatch_dev_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/ElastiCache"
        metricName = "DatabaseMemoryUsagePercentage"
        dimensions = {
          CacheClusterId = "example-api-dev-redis-001"
        }
        statistic = "Average"
        region    = "us-east-1"
        refId     = "A"
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
              params = [80]
            }
          }
        ]
      })
    }

    no_data_state  = "NoData"
    exec_err_state = "Alerting"
  }

  # Alert: Redis Evictions
  rule {
    name      = "Redis Evictions - Tecksign DEV"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Redis esta fazendo evictions"
      description = "O cache Redis esta removendo chaves por falta de memoria. {{ $values.B.Value | printf \"%.0f\" }} evictions detectadas."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/redis-evictions"
    }

    labels = {
      severity    = "critical"
      project     = "example-api"
      team        = "platform"
      resource    = "redis"
      environment = "dev"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.cloudwatch_dev_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/ElastiCache"
        metricName = "Evictions"
        dimensions = {
          CacheClusterId = "example-api-dev-redis-001"
        }
        statistic = "Sum"
        region    = "us-east-1"
        refId     = "A"
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

  # Alert: SQS DLQ Messages
  rule {
    name      = "SQS DLQ Messages - Tecksign DEV"
    condition = "C"
    for       = "1m"

    annotations = {
      summary     = "Mensagens na DLQ do SQS"
      description = "Existem {{ $values.B.Value | printf \"%.0f\" }} mensagens na fila DLQ. Verifique erros de processamento."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/sqs-dlq"
    }

    labels = {
      severity    = "critical"
      project     = "example-api"
      team        = "backend"
      resource    = "sqs"
      environment = "dev"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.cloudwatch_dev_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/SQS"
        metricName = "ApproximateNumberOfMessagesVisible"
        dimensions = {
          QueueName = "example-api-dev-events-dlq"
        }
        statistic = "Average"
        region    = "us-east-1"
        refId     = "A"
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

  # Alert: SQS Queue Depth High
  rule {
    name      = "SQS Queue Depth High - Tecksign DEV"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Fila SQS com muitas mensagens pendentes"
      description = "A fila example-api-dev-events tem {{ $values.B.Value | printf \"%.0f\" }} mensagens aguardando processamento"
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/sqs-depth-high"
    }

    labels = {
      severity    = "warning"
      project     = "example-api"
      team        = "backend"
      resource    = "sqs"
      environment = "dev"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.cloudwatch_dev_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/SQS"
        metricName = "ApproximateNumberOfMessagesVisible"
        dimensions = {
          QueueName = "example-api-dev-events"
        }
        statistic = "Average"
        region    = "us-east-1"
        refId     = "A"
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
              params = [1000]
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Alerting"
  }

  # Alert: SQS Message Age High
  rule {
    name      = "SQS Message Age High - Tecksign DEV"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Mensagens antigas na fila SQS"
      description = "A mensagem mais antiga na fila tem {{ $values.B.Value | printf \"%.0f\" }} segundos. Possivel problema de processamento."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/sqs-age-high"
    }

    labels = {
      severity    = "warning"
      project     = "example-api"
      team        = "backend"
      resource    = "sqs"
      environment = "dev"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.cloudwatch_dev_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/SQS"
        metricName = "ApproximateAgeOfOldestMessage"
        dimensions = {
          QueueName = "example-api-dev-events"
        }
        statistic = "Maximum"
        region    = "us-east-1"
        refId     = "A"
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
              params = [900] # 15 minutes
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Alerting"
  }

  # Alert: SES Bounce Rate High
  rule {
    name      = "SES Bounce Rate High - Tecksign DEV"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Taxa de bounce do SES acima de 5%"
      description = "A taxa de bounce de emails esta em {{ $values.B.Value | printf \"%.2f\" }}%. AWS pode suspender a conta se ultrapassar 10%."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/ses-bounce-high"
    }

    labels = {
      severity    = "critical"
      project     = "example-api"
      team        = "backend"
      resource    = "ses"
      environment = "dev"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.cloudwatch_dev_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/SES"
        metricName = "Reputation.BounceRate"
        dimensions = {}
        statistic  = "Average"
        region     = "us-east-1"
        refId      = "A"
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
              params = [0.05] # 5%
            }
          }
        ]
      })
    }

    no_data_state  = "OK"
    exec_err_state = "Alerting"
  }

  # Alert: SES Complaint Rate High
  rule {
    name      = "SES Complaint Rate High - Tecksign DEV"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Taxa de complaint do SES acima de 0.1%"
      description = "A taxa de complaints de emails esta em {{ $values.B.Value | printf \"%.3f\" }}%. AWS pode suspender a conta se ultrapassar 0.5%."
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/ses-complaint-high"
    }

    labels = {
      severity    = "critical"
      project     = "example-api"
      team        = "backend"
      resource    = "ses"
      environment = "dev"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.cloudwatch_dev_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/SES"
        metricName = "Reputation.ComplaintRate"
        dimensions = {}
        statistic  = "Average"
        region     = "us-east-1"
        refId      = "A"
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
              params = [0.001] # 0.1%
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
# Alert Rules - ECS (CloudWatch)
# -----------------------------------------------------------------------------

resource "grafana_rule_group" "example-api_ecs_alerts" {
  name             = "example-api-ecs-alerts"
  folder_uid       = local.alerts_folder_uid
  interval_seconds = 60

  # Alert: ECS CPU High
  rule {
    name      = "ECS CPU High - Tecksign DEV"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "CPU do ECS acima de 80%"
      description = "O servico ECS example-api-dev-api esta com CPU em {{ $values.B.Value | printf \"%.1f\" }}%"
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/ecs-cpu-high"
    }

    labels = {
      severity    = "warning"
      project     = "example-api"
      team        = "platform"
      resource    = "ecs"
      environment = "dev"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.cloudwatch_dev_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/ECS"
        metricName = "CPUUtilization"
        dimensions = {
          ClusterName = "cluster-dev"
          ServiceName = "example-api-dev-api"
        }
        statistic = "Average"
        region    = "us-east-1"
        refId     = "A"
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
              params = [80]
            }
          }
        ]
      })
    }

    no_data_state  = "NoData"
    exec_err_state = "Alerting"
  }

  # Alert: ECS Memory High
  rule {
    name      = "ECS Memory High - Tecksign DEV"
    condition = "C"
    for       = "5m"

    annotations = {
      summary     = "Memoria do ECS acima de 80%"
      description = "O servico ECS example-api-dev-api esta com memoria em {{ $values.B.Value | printf \"%.1f\" }}%"
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/ecs-memory-high"
    }

    labels = {
      severity    = "warning"
      project     = "example-api"
      team        = "platform"
      resource    = "ecs"
      environment = "dev"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.cloudwatch_dev_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/ECS"
        metricName = "MemoryUtilization"
        dimensions = {
          ClusterName = "cluster-dev"
          ServiceName = "example-api-dev-api"
        }
        statistic = "Average"
        region    = "us-east-1"
        refId     = "A"
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
              params = [80]
            }
          }
        ]
      })
    }

    no_data_state  = "NoData"
    exec_err_state = "Alerting"
  }

  # Alert: ECS Task Count Low (Service Unhealthy)
  rule {
    name      = "ECS Tasks Unhealthy - Tecksign DEV"
    condition = "C"
    for       = "2m"

    annotations = {
      summary     = "Tasks ECS abaixo do desejado"
      description = "O servico ECS example-api-dev-api tem {{ $values.B.Value | printf \"%.0f\" }} tasks rodando, menos que o desejado"
      runbook_url = "https://wiki.yourorg.com.br/runbooks/example-api/ecs-tasks-unhealthy"
    }

    labels = {
      severity    = "critical"
      project     = "example-api"
      team        = "platform"
      resource    = "ecs"
      environment = "dev"
    }

    data {
      ref_id         = "A"
      datasource_uid = local.cloudwatch_dev_uid

      relative_time_range {
        from = 300
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/ECS"
        metricName = "RunningTaskCount"
        dimensions = {
          ClusterName = "cluster-dev"
          ServiceName = "example-api-dev-api"
        }
        statistic = "Average"
        region    = "us-east-1"
        refId     = "A"
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
# Output
# -----------------------------------------------------------------------------
output "alert_rules_created" {
  description = "Alertas criados"
  value = {
    api_alerts = {
      folder_uid = local.alerts_folder_uid
      rule_group = grafana_rule_group.example-api_api_alerts.name
      rules      = [for r in grafana_rule_group.example-api_api_alerts.rule : r.name]
    }
    infra_alerts = {
      folder_uid = local.alerts_folder_uid
      rule_group = grafana_rule_group.example-api_infra_alerts.name
      rules      = [for r in grafana_rule_group.example-api_infra_alerts.rule : r.name]
    }
    ecs_alerts = {
      folder_uid = local.alerts_folder_uid
      rule_group = grafana_rule_group.example-api_ecs_alerts.name
      rules      = [for r in grafana_rule_group.example-api_ecs_alerts.rule : r.name]
    }
  }
}
