# -----------------------------------------------------------------------------
# Fork LOCAL do módulo YourOrg/terraform-aws-modules//database/elasticache-redis
# (ref v20260226165556-0ca4b10), com 1 ÚNICO acréscimo:
#   lifecycle { ignore_changes = [auth_token, auth_token_update_strategy] }
#
# Motivo (S3/data import): o ElastiCache importado tem auth_token="" +
# auth_token_update_strategy="ROTATE" (default do provider) no state. Sem auth
# (transit-encryption off), o provider tenta ModifyReplicationGroup de auth e a
# AWS rejeita ("AUTH token modification is only supported when
# encryption-in-transit is enabled"). ignore_changes suprime o diff espúrio sem
# tocar o recurso real. NÃO há mudança funcional vs o módulo central.
# Reverter para o módulo central quando ele expuser ignore/strategy nativamente.
# -----------------------------------------------------------------------------
locals {
  tags = merge(
    {
      Project = var.project_name
    },
    var.tags,
  )
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.replication_group_id}-sng"
  subnet_ids = var.subnet_ids

  tags = merge(
    local.tags,
    {
      Name = "${var.replication_group_id}-sng"
    },
  )
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id        = var.replication_group_id
  description                 = var.description
  engine                      = "redis"
  engine_version              = var.engine_version
  node_type                   = var.node_type
  num_cache_clusters          = var.num_cache_clusters
  port                        = var.port
  maintenance_window          = var.maintenance_window
  snapshot_window             = var.snapshot_window
  snapshot_retention_limit    = var.snapshot_retention_limit
  subnet_group_name           = aws_elasticache_subnet_group.this.name
  security_group_ids          = var.security_group_ids
  parameter_group_name        = var.parameter_group_name
  apply_immediately           = var.apply_immediately
  at_rest_encryption_enabled  = var.at_rest_encryption_enabled
  transit_encryption_enabled  = var.transit_encryption_enabled
  auth_token                  = var.auth_token
  multi_az_enabled            = var.multi_az_enabled
  automatic_failover_enabled  = var.automatic_failover_enabled
  preferred_cache_cluster_azs = var.preferred_cache_cluster_azs
  kms_key_id                  = var.kms_key_id

  lifecycle {
    ignore_changes = [auth_token, auth_token_update_strategy]
  }

  tags = merge(
    local.tags,
    {
      Name = var.replication_group_id
    },
  )
}
