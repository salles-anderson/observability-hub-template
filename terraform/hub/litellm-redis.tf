# -----------------------------------------------------------------------------
# ElastiCache Redis — LiteLLM Cache (Sprint 1 AI Platform)
# -----------------------------------------------------------------------------
# Cache de responses LLM para reduzir custo de tokens.
# Single-node (cache.t3.micro) — ~$13/mes, sem HA (e so cache).
# Acesso restrito ao SG das ECS tasks (rede interna).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Security Group - Redis
# -----------------------------------------------------------------------------
module "redis_sg" {
  count  = var.enable_grafana_llm ? 1 : 0
  source = "git@github.com:YOUR_ORG/terraform-aws-modules.git//modules/security/security-group?ref=v20260123110212-6e54d81"

  project_name = var.project
  name         = "${local.name_prefix}-redis-sg"
  vpc_id       = local.vpc_id

  ingress_rules = [
    {
      from_port                = 6379
      to_port                  = 6379
      protocol                 = "tcp"
      source_security_group_id = module.ecs_tasks_sg.id
      description              = "Allow Redis from ECS tasks"
    }
  ]

  tags = local.tags
}

# -----------------------------------------------------------------------------
# ElastiCache Redis (modulo centralizado)
# -----------------------------------------------------------------------------
module "litellm_redis" {
  count  = var.enable_grafana_llm ? 1 : 0
  source = "git@github.com:YOUR_ORG/terraform-aws-modules.git//modules/database/elasticache-redis?ref=v20260226165556-0ca4b10"

  project_name         = var.project
  replication_group_id = "${local.name_prefix}-litellm-cache"
  description          = "LiteLLM response cache for AI Platform"

  engine_version = "7.1"
  node_type      = var.redis_node_type
  port           = 6379

  # Single-node (cache only, no HA needed)
  num_cache_clusters       = 1
  multi_az_enabled         = false
  automatic_failover_enabled = false

  # Network
  subnet_ids         = local.private_subnet_ids
  security_group_ids = [module.redis_sg[0].id]

  # Encryption
  at_rest_encryption_enabled  = true
  transit_encryption_enabled  = false
  kms_key_id                  = module.kms.key_arn

  # Backup (minimal for cache)
  snapshot_retention_limit = 1

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-litellm-cache"
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "litellm_redis_endpoint" {
  description = "Redis primary endpoint for LiteLLM cache"
  value       = var.enable_grafana_llm ? module.litellm_redis[0].primary_endpoint : null
}
