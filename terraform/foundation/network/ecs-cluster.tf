# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------
module "ecs_cluster" {
  source = "git@github.com:YourOrg/terraform-aws-modules.git//modules/compute/ecs-cluster?ref=v20260123110212-6e54d81"

  project_name              = var.project
  cluster_name              = var.ecs_cluster_name
  enable_container_insights = var.container_insights

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE"
      weight            = 100
      base              = 1
    }
  ]

  tags = local.tags
}
