# =============================================================================
# hub-foundation-data — outputs consumidos pelos workspaces de servico (build).
#
# Nomes de atributo CONFIRMADOS contra outputs.tf dos modulos:
#   rds-aurora-cluster : cluster_id, writer_endpoint, reader_endpoint (NAO ha
#                        "cluster_endpoint"; o build usa writer_endpoint).
#   elasticache-redis  : primary_endpoint, port (NAO ha "primary_endpoint_address").
#   s3-bucket          : bucket_id, bucket_arn.
# =============================================================================

# --- RDS Aurora ---
output "rds_cluster_endpoint" { value = module.rds_observability.writer_endpoint }
output "rds_cluster_id" { value = module.rds_observability.cluster_id }
output "rds_reader_endpoint" { value = try(module.rds_observability.reader_endpoint, null) }
output "rds_port" { value = module.rds_observability.port }

# --- S3 buckets ---
output "s3_bucket_id" { value = module.s3_bucket.bucket_id }
output "s3_bucket_arn" { value = module.s3_bucket.bucket_arn }
output "skills_bucket_id" { value = module.skills_bucket.bucket_id }
output "skills_bucket_arn" { value = module.skills_bucket.bucket_arn }
output "chainlit_data_bucket_id" { value = try(module.chainlit_data[0].bucket_id, null) }
output "chainlit_data_bucket_arn" { value = try(module.chainlit_data[0].bucket_arn, null) }

# --- EFS ---
output "efs_id" { value = try(aws_efs_file_system.this[0].id, null) }
output "efs_arn" { value = try(aws_efs_file_system.this[0].arn, null) }
output "efs_ap_grafana_arn" { value = aws_efs_access_point.grafana.arn }
output "efs_ap_grafana_id" { value = aws_efs_access_point.grafana.id }
output "efs_ap_qdrant_arn" { value = try(aws_efs_access_point.qdrant[0].arn, null) }
output "efs_ap_qdrant_id" { value = try(aws_efs_access_point.qdrant[0].id, null) }
output "efs_ap_prometheus_arn" { value = try(aws_efs_access_point.prometheus[0].arn, null) }
output "efs_ap_prometheus_id" { value = try(aws_efs_access_point.prometheus[0].id, null) }
output "efs_ap_alertmanager_arn" { value = try(aws_efs_access_point.alertmanager[0].arn, null) }
output "efs_ap_alertmanager_id" { value = try(aws_efs_access_point.alertmanager[0].id, null) }

# --- ElastiCache Redis ---
output "redis_endpoint" { value = try(module.litellm_redis[0].primary_endpoint, null) }
output "redis_port" { value = try(module.litellm_redis[0].port, null) }
