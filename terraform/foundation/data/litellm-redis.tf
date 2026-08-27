# -----------------------------------------------------------------------------
# ElastiCache Redis — LiteLLM Cache (Sprint 1 AI Platform)
# -----------------------------------------------------------------------------
# Cache de responses LLM para reduzir custo de tokens.
# Single-node (cache.t3.micro) — ~$13/mes, sem HA (e so cache).
# Acesso restrito ao SG das ECS tasks (rede interna).
#
# DECOMPOSICAO (strangler): o module.redis_sg ja migrou para
# hub-foundation-security na S2; aqui consumimos read-only via
# local.security.redis_sg_id e local.security.kms_key_arn.
# -----------------------------------------------------------------------------

module "litellm_redis" {
  count = var.enable_grafana_llm ? 1 : 0
  # Fork LOCAL (./modules/elasticache-redis) = cópia fiel do módulo central
  # v20260226165556-0ca4b10 + ignore_changes[auth_token,auth_token_update_strategy]
  # p/ o import no-op (ver modules/elasticache-redis/main.tf). Endereço dos
  # recursos inalterado → state importado (serial 1) segue válido.
  source = "./modules/elasticache-redis"

  project_name         = var.project
  replication_group_id = "${local.name_prefix}-litellm-cache"
  description          = "LiteLLM response cache for AI Platform"

  engine_version = "7.1"
  node_type      = var.redis_node_type
  port           = 6379

  # Single-node (cache only, no HA needed)
  num_cache_clusters         = 1
  multi_az_enabled           = false
  automatic_failover_enabled = false

  # Network
  subnet_ids         = local.private_subnet_ids
  security_group_ids = [local.security.redis_sg_id]

  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false
  kms_key_id                 = local.security.kms_key_arn

  # Backup (minimal for cache)
  snapshot_retention_limit = 1

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-litellm-cache"
  })
}
