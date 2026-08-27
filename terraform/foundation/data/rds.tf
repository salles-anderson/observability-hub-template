# -----------------------------------------------------------------------------
# Aurora PostgreSQL Cluster - Observability Hub
# -----------------------------------------------------------------------------
# 2026-05-05: migrado de provisioned (db.t3.medium) para Serverless v2
# (db.serverless) com scale-to-zero. CPU 12% medio em 7d + storage 117 MB
# justificou serverless. Economia projetada ~$40-50/mes.
#
# Storage e dados preservados — apenas o tipo de compute (instance) muda.
# Cluster ID, endpoint, schemas, tables, users — tudo identico.
#
# DECOMPOSICAO (strangler): no monolito o password vinha de
# random_password.grafana_db.result. O random_password foi eliminado na S2
# (hub-foundation-security via var sensivel) — aqui o valor master entra como
# Terraform variable SENSIVEL (var.db_password) setada no workspace TFC com o
# MESMO valor do state importado, para plan no-op. NAO ha como aplicar
# lifecycle{ignore_changes} num module call; a senha do RDS e write-only no
# refresh (a AWS nao retorna o master password), entao o import nao detecta
# drift de senha mesmo sem ignore_changes. O controller valida no plan da D4.
# -----------------------------------------------------------------------------
module "rds_observability" {
  source = "git@github.com:YourOrg/terraform-aws-modules.git//modules/database/rds-aurora-cluster?ref=v20260505124450-72ae8b3"

  project_name = var.project
  identifier   = "${local.name_prefix}-db"

  engine         = "aurora-postgresql"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class
  instance_count = var.rds_instance_count

  # Aurora Serverless v2 — scale-to-zero (idle = sem custo de compute)
  serverlessv2_min_capacity = var.rds_serverlessv2_min_capacity
  serverlessv2_max_capacity = var.rds_serverlessv2_max_capacity

  db_name  = "db_obs_prod"
  username = "admindbprod"
  password = var.db_password

  subnet_ids             = local.private_subnet_ids
  vpc_security_group_ids = [local.security.rds_sg_id]
  publicly_accessible    = false

  storage_encrypted         = true
  backup_retention_period   = 7
  deletion_protection       = false
  skip_final_snapshot       = var.environment == "prod" ? false : true
  final_snapshot_identifier = "${local.name_prefix}-grafana-final"

  tags = local.tags
}
