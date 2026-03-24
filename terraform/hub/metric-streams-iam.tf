# -----------------------------------------------------------------------------
# IAM Roles para CloudWatch Metric Streams
# -----------------------------------------------------------------------------
# Permite enviar métricas AWS nativas para Prometheus via Firehose
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# IAM Role - CloudWatch Metric Stream
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "metric_stream_assume" {
  count = var.enable_metric_streams ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["streams.metrics.cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "metric_stream" {
  count = var.enable_metric_streams ? 1 : 0

  name               = "${local.name_prefix}-metric-stream-role"
  assume_role_policy = data.aws_iam_policy_document.metric_stream_assume[0].json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-metric-stream-role"
  })
}

data "aws_iam_policy_document" "metric_stream_firehose" {
  count = var.enable_metric_streams ? 1 : 0

  statement {
    actions = [
      "firehose:PutRecord",
      "firehose:PutRecordBatch"
    ]
    resources = [aws_kinesis_firehose_delivery_stream.metrics[0].arn]
  }
}

resource "aws_iam_role_policy" "metric_stream_firehose" {
  count = var.enable_metric_streams ? 1 : 0

  name   = "${local.name_prefix}-metric-stream-firehose"
  role   = aws_iam_role.metric_stream[0].id
  policy = data.aws_iam_policy_document.metric_stream_firehose[0].json
}

# -----------------------------------------------------------------------------
# IAM Role - Kinesis Firehose
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "firehose_assume" {
  count = var.enable_metric_streams ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose_metrics" {
  count = var.enable_metric_streams ? 1 : 0

  name               = "${local.name_prefix}-firehose-metrics-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume[0].json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-firehose-metrics-role"
  })
}

data "aws_iam_policy_document" "firehose_s3_backup" {
  count = var.enable_metric_streams ? 1 : 0

  statement {
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      module.s3_bucket.bucket_arn,
      "${module.s3_bucket.bucket_arn}/metric-streams/*"
    ]
  }

  statement {
    actions = [
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.firehose_metrics[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "firehose_s3" {
  count = var.enable_metric_streams ? 1 : 0

  name   = "${local.name_prefix}-firehose-s3-backup"
  role   = aws_iam_role.firehose_metrics[0].id
  policy = data.aws_iam_policy_document.firehose_s3_backup[0].json
}
