# -----------------------------------------------------------------------------
# Security Group - Redis (LiteLLM cache)
# -----------------------------------------------------------------------------
# Extraído de litellm-redis.tf do monolito. SOMENTE o SG migra para o cimento;
# o ElastiCache (module.litellm_redis) fica no build (recurso de serviço).
# Gated por var.enable_grafana_llm (= true em prod → instância [0]).
# -----------------------------------------------------------------------------
module "redis_sg" {
  count  = var.enable_grafana_llm ? 1 : 0
  source = "git@github.com:YourOrg/terraform-aws-modules.git//modules/security/security-group?ref=v20260123110212-6e54d81"

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
