# -----------------------------------------------------------------------------
# Aurora PostgreSQL Cluster - Observability Hub
# -----------------------------------------------------------------------------
module "rds_observability" {
  source = "git@github.com:YOUR_ORG/terraform-aws-modules.git//modules/database/rds-aurora-cluster?ref=v20260123110212-6e54d81"

  project_name = var.project
  identifier   = "${local.name_prefix}-db"

  engine         = "aurora-postgresql"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class
  instance_count = var.rds_instance_count

  db_name  = "db_obs_prod"
  username = "admindbprod"
  password = random_password.grafana_db.result

  subnet_ids             = local.private_subnet_ids
  vpc_security_group_ids = [module.rds_sg.id]
  publicly_accessible    = false

  storage_encrypted         = true
  backup_retention_period   = 7
  deletion_protection       = false
  skip_final_snapshot       = var.environment == "prod" ? false : true
  final_snapshot_identifier = "${local.name_prefix}-grafana-final"

  tags = local.tags
}
