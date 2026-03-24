# -----------------------------------------------------------------------------
# Spoke VPC Security Group Rules
# -----------------------------------------------------------------------------
# NOTA: Regras movidas para dentro do modulo ecs_tasks_sg em security.tf
# para evitar conflito entre inline rules e aws_security_group_rule standalone.
# Ver: local.spoke_grpc_rules e local.spoke_http_rules
