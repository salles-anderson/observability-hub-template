# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------
output "environment" {
  description = "Ambiente"
  value       = var.environment
}

output "aws_region" {
  description = "Regiao AWS"
  value       = var.aws_region
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
output "vpc_id" {
  description = "ID da VPC"
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas"
  value       = local.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs das subnets publicas"
  value       = local.public_subnet_ids
}

# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------
output "ecs_cluster_id" {
  description = "ID do cluster ECS"
  value       = module.ecs_cluster.cluster_id
}

output "ecs_cluster_name" {
  description = "Nome do cluster ECS"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_cluster_arn" {
  description = "ARN do cluster ECS"
  value       = module.ecs_cluster.cluster_arn
}

# -----------------------------------------------------------------------------
# ALB
# -----------------------------------------------------------------------------
output "alb_arn" {
  description = "ARN do ALB"
  value       = module.alb.lb_arn
}

output "alb_dns_name" {
  description = "DNS name do ALB"
  value       = module.alb.lb_dns_name
}

output "alb_zone_id" {
  description = "Zone ID do ALB"
  value       = module.alb.lb_zone_id
}

output "alb_http_listener_arn" {
  description = "ARN do listener HTTP"
  value       = aws_lb_listener.http.arn
}

output "alb_https_listener_arn" {
  description = "ARN do listener HTTPS"
  value       = aws_lb_listener.https.arn
}

# -----------------------------------------------------------------------------
# Storage - S3
# -----------------------------------------------------------------------------
output "s3_bucket_id" {
  description = "ID do bucket S3"
  value       = module.s3_bucket.bucket_id
}

output "s3_bucket_arn" {
  description = "ARN do bucket S3"
  value       = module.s3_bucket.bucket_arn
}

# -----------------------------------------------------------------------------
# Storage - EFS
# -----------------------------------------------------------------------------
output "efs_id" {
  description = "ID do EFS"
  value       = try(aws_efs_file_system.this[0].id, null)
}

output "efs_arn" {
  description = "ARN do EFS"
  value       = try(aws_efs_file_system.this[0].arn, null)
}

# -----------------------------------------------------------------------------
# Security - KMS
# -----------------------------------------------------------------------------
output "kms_key_id" {
  description = "ID da KMS key"
  value       = module.kms.key_id
}

output "kms_key_arn" {
  description = "ARN da KMS key"
  value       = module.kms.key_arn
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
output "alb_security_group_id" {
  description = "ID do Security Group do ALB"
  value       = module.alb_sg.id
}

output "ecs_tasks_security_group_id" {
  description = "ID do Security Group das ECS tasks"
  value       = module.ecs_tasks_sg.id
}

output "efs_security_group_id" {
  description = "ID do Security Group do EFS"
  value       = try(module.efs_sg[0].id, null)
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------
output "ecs_task_execution_role_arn" {
  description = "ARN da role de execucao ECS"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN da role das tasks ECS"
  value       = aws_iam_role.ecs_task.arn
}

# -----------------------------------------------------------------------------
# ACM
# -----------------------------------------------------------------------------
output "acm_certificate_arn" {
  description = "ARN do certificado ACM"
  value       = module.acm.arn
}

# -----------------------------------------------------------------------------
# Grafana
# -----------------------------------------------------------------------------
output "grafana_url" {
  description = "URL do Grafana"
  value       = "https://grafana.${var.domain_name}"
}

output "grafana_target_group_arn" {
  description = "ARN do Target Group do Grafana"
  value       = aws_lb_target_group.grafana.arn
}

output "grafana_service_name" {
  description = "Nome do ECS Service do Grafana"
  value       = aws_ecs_service.grafana.name
}

output "grafana_service_id" {
  description = "ID do ECS Service do Grafana"
  value       = aws_ecs_service.grafana.id
}

output "grafana_task_definition_arn" {
  description = "ARN da Task Definition do Grafana"
  value       = aws_ecs_task_definition.grafana.arn
}

output "grafana_admin_password_secret_arn" {
  description = "ARN do SSM Parameter com a senha admin do Grafana"
  value       = aws_ssm_parameter.grafana_admin_password.arn
}

# -----------------------------------------------------------------------------
# Prometheus
# -----------------------------------------------------------------------------
output "prometheus_task_definition_arn" {
  description = "ARN da Task Definition do Prometheus"
  value       = aws_ecs_task_definition.prometheus.arn
}

output "prometheus_service_id" {
  description = "ID do ECS Service do Prometheus"
  value       = aws_ecs_service.prometheus.id
}

output "prometheus_service_name" {
  description = "Nome do ECS Service do Prometheus"
  value       = aws_ecs_service.prometheus.name
}

output "prometheus_config_ssm_arn" {
  description = "ARN do SSM Parameter com a config do Prometheus"
  value       = aws_ssm_parameter.prometheus_config.arn
}

# -----------------------------------------------------------------------------
# AlertManager
# -----------------------------------------------------------------------------
output "alertmanager_task_definition_arn" {
  description = "ARN da Task Definition do AlertManager"
  value       = aws_ecs_task_definition.alertmanager.arn
}

output "alertmanager_service_id" {
  description = "ID do ECS Service do AlertManager"
  value       = aws_ecs_service.alertmanager.id
}

output "alertmanager_service_name" {
  description = "Nome do ECS Service do AlertManager"
  value       = aws_ecs_service.alertmanager.name
}

output "alertmanager_config_ssm_arn" {
  description = "ARN do SSM Parameter com a config do AlertManager"
  value       = aws_ssm_parameter.alertmanager_config.arn
}

# -----------------------------------------------------------------------------
# Loki
# -----------------------------------------------------------------------------
output "loki_task_definition_arn" {
  description = "ARN da Task Definition do Loki"
  value       = aws_ecs_task_definition.loki.arn
}

output "loki_service_id" {
  description = "ID do ECS Service do Loki"
  value       = aws_ecs_service.loki.id
}

output "loki_service_name" {
  description = "Nome do ECS Service do Loki"
  value       = aws_ecs_service.loki.name
}

output "loki_config_ssm_arn" {
  description = "ARN do SSM Parameter com a config do Loki"
  value       = aws_ssm_parameter.loki_config.arn
}

# -----------------------------------------------------------------------------
# Tempo
# -----------------------------------------------------------------------------
output "tempo_task_definition_arn" {
  description = "ARN da Task Definition do Tempo"
  value       = aws_ecs_task_definition.tempo.arn
}

output "tempo_service_id" {
  description = "ID do ECS Service do Tempo"
  value       = aws_ecs_service.tempo.id
}

output "tempo_service_name" {
  description = "Nome do ECS Service do Tempo"
  value       = aws_ecs_service.tempo.name
}

output "tempo_config_ssm_arn" {
  description = "ARN do SSM Parameter com a config do Tempo"
  value       = aws_ssm_parameter.tempo_config.arn
}

# -----------------------------------------------------------------------------
# Grafana Alloy
# -----------------------------------------------------------------------------
output "alloy_task_definition_arn" {
  description = "ARN da Task Definition do Grafana Alloy"
  value       = aws_ecs_task_definition.alloy.arn
}

output "alloy_service_id" {
  description = "ID do ECS Service do Grafana Alloy"
  value       = aws_ecs_service.alloy.id
}

output "alloy_service_name" {
  description = "Nome do ECS Service do Grafana Alloy"
  value       = aws_ecs_service.alloy.name
}

# -----------------------------------------------------------------------------
# Aurora PostgreSQL Cluster
# -----------------------------------------------------------------------------
output "rds_endpoint" {
  description = "Writer endpoint do Aurora cluster"
  value       = module.rds_observability.writer_endpoint
}

output "rds_reader_endpoint" {
  description = "Reader endpoint do Aurora cluster"
  value       = module.rds_observability.reader_endpoint
}

output "rds_port" {
  description = "Porta do Aurora cluster"
  value       = module.rds_observability.port
}

output "rds_security_group_id" {
  description = "ID do Security Group do RDS"
  value       = module.rds_sg.id
}

# -----------------------------------------------------------------------------
# EFS Access Points
# -----------------------------------------------------------------------------
output "efs_access_point_grafana_id" {
  description = "ID do EFS Access Point do Grafana"
  value       = aws_efs_access_point.grafana.id
}

output "efs_access_point_grafana_arn" {
  description = "ARN do EFS Access Point do Grafana"
  value       = aws_efs_access_point.grafana.arn
}

output "efs_access_point_prometheus_id" {
  description = "ID do EFS Access Point do Prometheus"
  value       = try(aws_efs_access_point.prometheus[0].id, null)
}

output "efs_access_point_prometheus_arn" {
  description = "ARN do EFS Access Point do Prometheus"
  value       = try(aws_efs_access_point.prometheus[0].arn, null)
}

output "efs_access_point_alertmanager_id" {
  description = "ID do EFS Access Point do AlertManager"
  value       = try(aws_efs_access_point.alertmanager[0].id, null)
}

output "efs_access_point_alertmanager_arn" {
  description = "ARN do EFS Access Point do AlertManager"
  value       = try(aws_efs_access_point.alertmanager[0].arn, null)
}

# -----------------------------------------------------------------------------
# Service Discovery (Cloud Map)
# -----------------------------------------------------------------------------
output "cloudmap_namespace_id" {
  description = "ID do namespace Cloud Map"
  value       = aws_service_discovery_private_dns_namespace.observability.id
}

output "cloudmap_namespace_arn" {
  description = "ARN do namespace Cloud Map"
  value       = aws_service_discovery_private_dns_namespace.observability.arn
}

output "cloudmap_namespace_name" {
  description = "Nome do namespace Cloud Map"
  value       = aws_service_discovery_private_dns_namespace.observability.name
}

output "service_discovery_services" {
  description = "Map dos servicos de Service Discovery"
  value = {
    for k, v in aws_service_discovery_service.services : k => {
      id   = v.id
      arn  = v.arn
      name = v.name
    }
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups
# -----------------------------------------------------------------------------
output "cloudwatch_log_groups" {
  description = "Map dos CloudWatch Log Groups dos servicos"
  value = {
    for k, v in aws_cloudwatch_log_group.services : k => {
      name = v.name
      arn  = v.arn
    }
  }
}
