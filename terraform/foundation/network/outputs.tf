# -----------------------------------------------------------------------------
# Outputs - foundation/network
# Consumidos pelo workspace `build` via data.terraform_remote_state.network
# -----------------------------------------------------------------------------

# ECS Cluster
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

# Service Discovery (Cloud Map)
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
output "cloudmap_hosted_zone_id" {
  description = "Hosted Zone ID do Cloud Map (para associacao cross-account)"
  value       = aws_service_discovery_private_dns_namespace.observability.hosted_zone
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
output "aiops_agent_apigw_service_arn" {
  description = "ARN do service discovery do aiops-agent-apigw (count[0])"
  value       = aws_service_discovery_service.aiops_agent_apigw[0].arn
}
output "agents_api_service_arn" {
  description = "ARN do service discovery do agents-api (Cloud Map)"
  value       = var.enable_agents_api ? aws_service_discovery_service.services["agents_api"].arn : null
}
