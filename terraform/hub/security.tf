# -----------------------------------------------------------------------------
# KMS Key
# -----------------------------------------------------------------------------
module "kms" {
  source = "git@github.com:YOUR_ORG/terraform-aws-modules.git//modules/security/kms-key?ref=v20260123110212-6e54d81"

  project_name            = var.project
  description             = "KMS key for ${local.name_prefix}"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  alias_name              = local.name_prefix

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Security Group - ALB
# -----------------------------------------------------------------------------
module "alb_sg" {
  source = "git@github.com:YOUR_ORG/terraform-aws-modules.git//modules/security/security-group?ref=v20260123110212-6e54d81"

  project_name = var.project
  name         = "${local.name_prefix}-alb-sg"
  vpc_id       = local.vpc_id

  ingress_rules = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow HTTP from anywhere"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow HTTPS from anywhere"
    }
  ]

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Security Group - ECS Tasks
# -----------------------------------------------------------------------------
locals {
  # Regras base do ECS Tasks SG
  ecs_tasks_base_rules = [
    {
      from_port                = 0
      to_port                  = 65535
      protocol                 = "tcp"
      source_security_group_id = module.alb_sg.id
      description              = "Allow traffic from ALB"
    },
    {
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      self        = true
      description = "Allow ECS tasks internal communication"
    }
  ]

  # Todos os CIDRs que podem enviar telemetria (VPC Peering + TGW)
  all_spoke_cidrs = concat(var.spoke_vpc_cidrs, var.tgw_spoke_vpc_cidrs)

  # Regras dinamicas para spoke VPCs (OTLP gRPC 4317)
  spoke_grpc_rules = [
    for cidr in local.all_spoke_cidrs : {
      from_port   = 4317
      to_port     = 4317
      protocol    = "tcp"
      cidr_blocks = [cidr]
      description = "Allow OTel gRPC from spoke VPC ${cidr}"
    }
  ]

  # Regras dinamicas para spoke VPCs (OTLP HTTP 4318)
  spoke_http_rules = [
    for cidr in local.all_spoke_cidrs : {
      from_port   = 4318
      to_port     = 4318
      protocol    = "tcp"
      cidr_blocks = [cidr]
      description = "Allow OTel HTTP from spoke VPC ${cidr}"
    }
  ]

  # Regras dinamicas para spoke VPCs (Loki HTTP 3100)
  spoke_loki_rules = [
    for cidr in local.all_spoke_cidrs : {
      from_port   = 3100
      to_port     = 3100
      protocol    = "tcp"
      cidr_blocks = [cidr]
      description = "Allow Loki from spoke VPC ${cidr}"
    }
  ]

  # Consolidar todas as regras
  ecs_tasks_all_rules = concat(
    local.ecs_tasks_base_rules,
    local.spoke_grpc_rules,
    local.spoke_http_rules,
    local.spoke_loki_rules
  )
}

module "ecs_tasks_sg" {
  source = "git@github.com:YOUR_ORG/terraform-aws-modules.git//modules/security/security-group?ref=v20260123110212-6e54d81"

  project_name = var.project
  name         = "${local.name_prefix}-ecs-tasks-sg"
  vpc_id       = local.vpc_id

  ingress_rules = local.ecs_tasks_all_rules

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Security Group - EFS
# -----------------------------------------------------------------------------
module "efs_sg" {
  count  = var.efs_enabled ? 1 : 0
  source = "git@github.com:YOUR_ORG/terraform-aws-modules.git//modules/security/security-group?ref=v20260123110212-6e54d81"

  project_name = var.project
  name         = "${local.name_prefix}-efs-sg"
  vpc_id       = local.vpc_id

  ingress_rules = [
    {
      from_port                = 2049
      to_port                  = 2049
      protocol                 = "tcp"
      source_security_group_id = module.ecs_tasks_sg.id
      description              = "Allow NFS from ECS tasks"
    }
  ]

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Security Group - RDS
# -----------------------------------------------------------------------------
module "rds_sg" {
  source = "git@github.com:YOUR_ORG/terraform-aws-modules.git//modules/security/security-group?ref=v20260123110212-6e54d81"

  project_name = var.project
  name         = "${local.name_prefix}-rds-sg"
  vpc_id       = local.vpc_id

  ingress_rules = concat(
    [
      {
        from_port                = 5432
        to_port                  = 5432
        protocol                 = "tcp"
        source_security_group_id = module.ecs_tasks_sg.id
        description              = "Allow PostgreSQL from ECS tasks"
      },
      {
        from_port                = 5432
        to_port                  = 5432
        protocol                 = "tcp"
        source_security_group_id = "sg-0b1957f3fecfb28e2"
        description              = "Allow PostgreSQL from Sonar ECS"
      }
    ],
    var.bastion_sg_id != null ? [
      {
        from_port                = 5432
        to_port                  = 5432
        protocol                 = "tcp"
        source_security_group_id = var.bastion_sg_id
        description              = "Allow PostgreSQL from bastion"
      }
    ] : []
  )

  tags = local.tags
}
