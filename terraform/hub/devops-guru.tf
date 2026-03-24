# -----------------------------------------------------------------------------
# Amazon DevOps Guru - ML-powered Anomaly Detection (Sprint 4 - AIOps)
# -----------------------------------------------------------------------------
# Analisa automaticamente metricas CloudWatch, Container Insights, CloudTrail
# para detectar anomalias operacionais e gerar insights/recomendacoes ML.
# Custo: ~$3/resource/mes (Group B: ECS, RDS, ALB)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Locals - ECS Services para CloudWatch Anomaly Detection
# -----------------------------------------------------------------------------
locals {
  ecs_core_services = toset([
    "grafana",
    "prometheus",
    "loki",
    "tempo",
    "alloy",
    "alertmanager",
  ])

  ecs_monitored_services = local.ecs_core_services

  # RDS cluster identifier
  rds_cluster_id = "${local.name_prefix}-db"

  # ALB ARN suffix para CloudWatch metrics (extraido do ARN)
  alb_arn_suffix = var.enable_aws_anomaly_detection ? regex("loadbalancer/(.*)", module.alb.lb_arn)[0] : ""
}

# -----------------------------------------------------------------------------
# SNS Topic - DevOps Guru + CloudWatch Anomaly Alarms
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "aiops" {
  count = var.enable_aiops ? 1 : 0

  name = "${local.name_prefix}-aiops-alerts"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-aiops-alerts"
  })
}

resource "aws_sns_topic_policy" "aiops" {
  count = var.enable_aiops ? 1 : 0

  arn = aws_sns_topic.aiops[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowDevOpsGuru"
        Effect    = "Allow"
        Principal = { Service = "devops-guru.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.aiops[0].arn
      },
      {
        Sid       = "AllowCloudWatch"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.aiops[0].arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# DevOps Guru - Resource Collection (Tag-based)
# -----------------------------------------------------------------------------
resource "aws_devopsguru_resource_collection" "this" {
  count = var.enable_aws_anomaly_detection ? 1 : 0

  type = "AWS_TAGS"

  tags {
    app_boundary_key = "Project"
    tag_values       = [var.project]
  }
}

# -----------------------------------------------------------------------------
# DevOps Guru - Notification Channel (SNS)
# -----------------------------------------------------------------------------
resource "aws_devopsguru_notification_channel" "this" {
  count = var.enable_aws_anomaly_detection ? 1 : 0

  sns {
    topic_arn = aws_sns_topic.aiops[0].arn
  }

  filters {
    message_types = [
      "NEW_INSIGHT",
      "CLOSED_INSIGHT",
      "SEVERITY_UPGRADED",
    ]
    severities = ["MEDIUM", "HIGH"]
  }

  depends_on = [aws_sns_topic_policy.aiops]
}

# -----------------------------------------------------------------------------
# DevOps Guru - Service Integration
# -----------------------------------------------------------------------------
# NOTA: Gerenciado via AWS CLI (provider bug hashicorp/aws#XXXXX)
# aws devops-guru update-service-integration --service-integration \
#   '{LogsAnomalyDetection:{OptInStatus:ENABLED},OpsCenter:{OptInStatus:ENABLED}}'
# Para importar futuramente: terraform import aws_devopsguru_service_integration.this ""

# =============================================================================
# CloudWatch Anomaly Detection Alarms
# =============================================================================
# Usa ANOMALY_DETECTION_BAND (ML) para detectar anomalias automaticamente.
# Banda = 2 stddev. CloudWatch precisa ~14 dias para treinar o modelo.
# =============================================================================

# -----------------------------------------------------------------------------
# ECS CPU Anomaly - por servico
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_anomaly" {
  for_each = var.enable_aws_anomaly_detection ? local.ecs_monitored_services : toset([])

  alarm_name          = "${local.name_prefix}-${each.key}-cpu-anomaly"
  alarm_description   = "CPU anomaly detected for ECS service ${each.key}"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  threshold_metric_id = "ad1"

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      metric_name = "CPUUtilization"
      namespace   = "AWS/ECS"
      period      = 300
      stat        = "Average"

      dimensions = {
        ClusterName = var.ecs_cluster_name
        ServiceName = "${local.name_prefix}-${each.key}"
      }
    }
  }

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "CPUUtilization (Expected)"
    return_data = true
  }

  alarm_actions = [aws_sns_topic.aiops[0].arn]
  ok_actions    = [aws_sns_topic.aiops[0].arn]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${each.key}-cpu-anomaly"
  })
}

# -----------------------------------------------------------------------------
# ECS Memory Anomaly - por servico
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_memory_anomaly" {
  for_each = var.enable_aws_anomaly_detection ? local.ecs_monitored_services : toset([])

  alarm_name          = "${local.name_prefix}-${each.key}-memory-anomaly"
  alarm_description   = "Memory anomaly detected for ECS service ${each.key}"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  threshold_metric_id = "ad1"

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      metric_name = "MemoryUtilization"
      namespace   = "AWS/ECS"
      period      = 300
      stat        = "Average"

      dimensions = {
        ClusterName = var.ecs_cluster_name
        ServiceName = "${local.name_prefix}-${each.key}"
      }
    }
  }

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "MemoryUtilization (Expected)"
    return_data = true
  }

  alarm_actions = [aws_sns_topic.aiops[0].arn]
  ok_actions    = [aws_sns_topic.aiops[0].arn]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${each.key}-memory-anomaly"
  })
}

# -----------------------------------------------------------------------------
# ALB Latency Anomaly (TargetResponseTime P99)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_latency_anomaly" {
  count = var.enable_aws_anomaly_detection ? 1 : 0

  alarm_name          = "${local.name_prefix}-alb-latency-anomaly"
  alarm_description   = "ALB latency anomaly detected (TargetResponseTime p99)"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  threshold_metric_id = "ad1"

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      metric_name = "TargetResponseTime"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "p99"

      dimensions = {
        LoadBalancer = local.alb_arn_suffix
      }
    }
  }

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "TargetResponseTime (Expected)"
    return_data = true
  }

  alarm_actions = [aws_sns_topic.aiops[0].arn]
  ok_actions    = [aws_sns_topic.aiops[0].arn]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alb-latency-anomaly"
  })
}

# -----------------------------------------------------------------------------
# ALB 5xx Anomaly
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_5xx_anomaly" {
  count = var.enable_aws_anomaly_detection ? 1 : 0

  alarm_name          = "${local.name_prefix}-alb-5xx-anomaly"
  alarm_description   = "ALB 5xx error count anomaly detected"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  threshold_metric_id = "ad1"

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      metric_name = "HTTPCode_ELB_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"

      dimensions = {
        LoadBalancer = local.alb_arn_suffix
      }
    }
  }

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "5xx Count (Expected)"
    return_data = true
  }

  alarm_actions = [aws_sns_topic.aiops[0].arn]
  ok_actions    = [aws_sns_topic.aiops[0].arn]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alb-5xx-anomaly"
  })
}

# -----------------------------------------------------------------------------
# ALB Request Count Anomaly
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_requests_anomaly" {
  count = var.enable_aws_anomaly_detection ? 1 : 0

  alarm_name          = "${local.name_prefix}-alb-requests-anomaly"
  alarm_description   = "ALB request count anomaly detected (traffic spike/drop)"
  comparison_operator = "LessThanLowerOrGreaterThanUpperThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  threshold_metric_id = "ad1"

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"

      dimensions = {
        LoadBalancer = local.alb_arn_suffix
      }
    }
  }

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "RequestCount (Expected)"
    return_data = true
  }

  alarm_actions = [aws_sns_topic.aiops[0].arn]
  ok_actions    = [aws_sns_topic.aiops[0].arn]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alb-requests-anomaly"
  })
}

# -----------------------------------------------------------------------------
# RDS CPU Anomaly
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu_anomaly" {
  count = var.enable_aws_anomaly_detection ? 1 : 0

  alarm_name          = "${local.name_prefix}-rds-cpu-anomaly"
  alarm_description   = "RDS Aurora CPU anomaly detected"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  threshold_metric_id = "ad1"

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      metric_name = "CPUUtilization"
      namespace   = "AWS/RDS"
      period      = 300
      stat        = "Average"

      dimensions = {
        DBClusterIdentifier = local.rds_cluster_id
      }
    }
  }

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "CPUUtilization (Expected)"
    return_data = true
  }

  alarm_actions = [aws_sns_topic.aiops[0].arn]
  ok_actions    = [aws_sns_topic.aiops[0].arn]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rds-cpu-anomaly"
  })
}

# -----------------------------------------------------------------------------
# RDS Database Connections Anomaly
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_connections_anomaly" {
  count = var.enable_aws_anomaly_detection ? 1 : 0

  alarm_name          = "${local.name_prefix}-rds-connections-anomaly"
  alarm_description   = "RDS Aurora database connections anomaly detected"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  threshold_metric_id = "ad1"

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      metric_name = "DatabaseConnections"
      namespace   = "AWS/RDS"
      period      = 300
      stat        = "Average"

      dimensions = {
        DBClusterIdentifier = local.rds_cluster_id
      }
    }
  }

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "DatabaseConnections (Expected)"
    return_data = true
  }

  alarm_actions = [aws_sns_topic.aiops[0].arn]
  ok_actions    = [aws_sns_topic.aiops[0].arn]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rds-connections-anomaly"
  })
}
