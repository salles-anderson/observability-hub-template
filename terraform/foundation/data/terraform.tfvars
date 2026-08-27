# =============================================================================
# hub-foundation-data — valores NAO-SENSIVEIS.
# db_password e Terraform variable SENSIVEL setada no workspace TFC, NAO aqui.
# =============================================================================

# -----------------------------------------------------------------------------
# General (identico a build/terraform.tfvars)
# -----------------------------------------------------------------------------
project      = "teck-obs-hub"
environment  = "prod"
owner        = "DevOps"
account_id   = "111111111111"
account_name = "teck-observability"
aws_region   = "us-east-1"

# -----------------------------------------------------------------------------
# RDS Aurora PostgreSQL — Serverless v2 (scale-to-zero) — identico a build
# -----------------------------------------------------------------------------
rds_instance_class            = "db.serverless"
rds_instance_count            = 1
rds_engine_version            = "16.11"
rds_serverlessv2_min_capacity = 0 # scale-to-zero quando idle (5min)
rds_serverlessv2_max_capacity = 2 # max 2 ACU = 4 GB RAM

# -----------------------------------------------------------------------------
# Storage - S3 (identico a build: bucket_name = "${name_prefix}-storage")
# -----------------------------------------------------------------------------
s3_bucket_name = "storage"
s3_versioning  = true

# -----------------------------------------------------------------------------
# Storage - EFS (identico a build)
# -----------------------------------------------------------------------------
efs_enabled   = true
efs_name      = "efs"
efs_encrypted = true

# -----------------------------------------------------------------------------
# ElastiCache Redis - LiteLLM cache
# -----------------------------------------------------------------------------
redis_node_type = "cache.t3.micro"

# -----------------------------------------------------------------------------
# Feature flags (paridade com o state do monolito → counts corretos)
# -----------------------------------------------------------------------------
enable_grafana_llm = true
enable_chainlit    = true
enable_qdrant      = true

# -----------------------------------------------------------------------------
# Tags (paridade com build — fecha plan no-op: recursos importados tem Team=DevOps)
# -----------------------------------------------------------------------------
tags = {
  Team = "DevOps"
}
