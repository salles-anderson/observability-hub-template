# -----------------------------------------------------------------------------
# CloudWatch Metric Streams
# -----------------------------------------------------------------------------
# Envia métricas AWS nativas para Prometheus via Kinesis Firehose
# Formato: OpenTelemetry 1.0
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# CloudWatch Log Group para Firehose (erros)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "firehose_metrics" {
  count = var.enable_metric_streams ? 1 : 0

  name              = "/aws/firehose/${local.name_prefix}-metrics"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-firehose-metrics-logs"
  })
}

resource "aws_cloudwatch_log_stream" "firehose_metrics" {
  count = var.enable_metric_streams ? 1 : 0

  name           = "delivery-errors"
  log_group_name = aws_cloudwatch_log_group.firehose_metrics[0].name
}

# -----------------------------------------------------------------------------
# Kinesis Firehose Delivery Stream
# -----------------------------------------------------------------------------
resource "aws_kinesis_firehose_delivery_stream" "metrics" {
  count = var.enable_metric_streams ? 1 : 0

  name        = "${local.name_prefix}-metrics-stream"
  destination = "http_endpoint"

  http_endpoint_configuration {
    url                = "https://prometheus.${var.domain_name}/api/v1/write"
    name               = "prometheus-remote-write"
    buffering_size     = 1
    buffering_interval = 60
    role_arn           = aws_iam_role.firehose_metrics[0].arn

    request_configuration {
      content_encoding = "GZIP"
    }

    s3_backup_mode = "FailedDataOnly"

    s3_configuration {
      role_arn           = aws_iam_role.firehose_metrics[0].arn
      bucket_arn         = module.s3_bucket.bucket_arn
      prefix             = "metric-streams/failed/"
      compression_format = "GZIP"
      buffering_size     = 5
      buffering_interval = 300

      cloudwatch_logging_options {
        enabled         = true
        log_group_name  = aws_cloudwatch_log_group.firehose_metrics[0].name
        log_stream_name = aws_cloudwatch_log_stream.firehose_metrics[0].name
      }
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_metrics[0].name
      log_stream_name = aws_cloudwatch_log_stream.firehose_metrics[0].name
    }
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-metrics-stream"
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Metric Stream
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_stream" "observability" {
  count = var.enable_metric_streams ? 1 : 0

  name          = "${local.name_prefix}-metrics"
  role_arn      = aws_iam_role.metric_stream[0].arn
  firehose_arn  = aws_kinesis_firehose_delivery_stream.metrics[0].arn
  output_format = "opentelemetry1.0"

  # Métricas ECS
  include_filter {
    namespace    = "AWS/ECS"
    metric_names = []
  }

  # Container Insights
  include_filter {
    namespace    = "ECS/ContainerInsights"
    metric_names = []
  }

  # Application Load Balancer
  include_filter {
    namespace    = "AWS/ApplicationELB"
    metric_names = []
  }

  # RDS
  include_filter {
    namespace    = "AWS/RDS"
    metric_names = []
  }

  # S3
  include_filter {
    namespace    = "AWS/S3"
    metric_names = ["BucketSizeBytes", "NumberOfObjects"]
  }

  # EFS
  include_filter {
    namespace    = "AWS/EFS"
    metric_names = []
  }

  # SQS (para aplicações)
  include_filter {
    namespace    = "AWS/SQS"
    metric_names = []
  }

  # Lambda
  include_filter {
    namespace    = "AWS/Lambda"
    metric_names = []
  }

  # API Gateway
  include_filter {
    namespace    = "AWS/ApiGateway"
    metric_names = []
  }

  # Cognito
  include_filter {
    namespace    = "AWS/Cognito"
    metric_names = []
  }

  # Estatísticas adicionais para latência
  statistics_configuration {
    additional_statistics = ["p50", "p90", "p99"]
    include_metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "TargetResponseTime"
    }
  }

  statistics_configuration {
    additional_statistics = ["p50", "p90", "p99"]
    include_metric {
      namespace   = "AWS/ECS"
      metric_name = "CPUUtilization"
    }
  }

  statistics_configuration {
    additional_statistics = ["p50", "p90", "p99"]
    include_metric {
      namespace   = "AWS/ECS"
      metric_name = "MemoryUtilization"
    }
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-metric-stream"
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "metric_stream_arn" {
  description = "ARN do CloudWatch Metric Stream"
  value       = var.enable_metric_streams ? aws_cloudwatch_metric_stream.observability[0].arn : null
}

output "firehose_arn" {
  description = "ARN do Kinesis Firehose para métricas"
  value       = var.enable_metric_streams ? aws_kinesis_firehose_delivery_stream.metrics[0].arn : null
}
