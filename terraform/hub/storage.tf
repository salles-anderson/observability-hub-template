# -----------------------------------------------------------------------------
# S3 Bucket
# -----------------------------------------------------------------------------
module "s3_bucket" {
  source = "git@github.com:YOUR_ORG/terraform-aws-modules.git//modules/storage/s3-bucket?ref=v20260123110212-6e54d81"

  bucket_name        = "${local.name_prefix}-${var.s3_bucket_name}"
  versioning_enabled = var.s3_versioning
  force_ssl          = true

  tags = local.tags
}

# -----------------------------------------------------------------------------
# S3 Lifecycle Policy - Retencao de dados (7-30 dias)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "storage" {
  bucket = module.s3_bucket.bucket_id

  # Regra para logs do Loki - 7 dias
  rule {
    id     = "loki-logs-retention"
    status = "Enabled"

    filter {
      prefix = "loki/"
    }

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }

  # Regra para traces do Tempo - 7 dias
  rule {
    id     = "tempo-traces-retention"
    status = "Enabled"

    filter {
      prefix = "tempo/"
    }

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }

  # Regra para logs de auditoria - 30 dias (maximo permitido)
  rule {
    id     = "audit-logs-retention"
    status = "Enabled"

    filter {
      prefix = "audit-logs/"
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  # Regra para metric streams failed - 7 dias
  rule {
    id     = "metric-streams-failed"
    status = "Enabled"

    filter {
      prefix = "metric-streams/"
    }

    expiration {
      days = 7
    }
  }

  # Regra padrao para outros objetos - 30 dias
  rule {
    id     = "default-retention"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# -----------------------------------------------------------------------------
# EFS File System
# -----------------------------------------------------------------------------
resource "aws_efs_file_system" "this" {
  count = var.efs_enabled ? 1 : 0

  creation_token = "${local.name_prefix}-${var.efs_name}"
  encrypted      = var.efs_encrypted
  kms_key_id     = var.efs_encrypted ? module.kms.key_arn : null

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${var.efs_name}"
  })
}

resource "aws_efs_mount_target" "this" {
  for_each = var.efs_enabled ? toset(local.private_subnet_ids) : []

  file_system_id  = aws_efs_file_system.this[0].id
  subnet_id       = each.value
  security_groups = [module.efs_sg[0].id]
}
