# -----------------------------------------------------------------------------
# Import blocks (strangler) — adoção dos recursos do domínio DATA
# -----------------------------------------------------------------------------
# O workspace hub-foundation-data ASSUME os recursos já criados pelo monolito
# teck-observability-hub-prod (state serial 443), SEM recriar.
# Resultado esperado no `terraform plan` (TFC): SÓ imports, ZERO create/destroy/replace.
#
# Fonte: docs/plans/2026-06-15-sprint3-data-import-ids.md (verificado read-only no
# state + cruzado com a AWS). Total: 30 instâncias.
#   RDS:         3  (cluster + instance[0] + subnet_group)
#   S3 storage:  6  (bucket + policy[0] + PAB + SSE + versioning + lifecycle top-level)
#   S3 skills:   5  (bucket + policy[0] + PAB + SSE + versioning)
#   S3 chainlit: 6  (module[0]: bucket + policy[0] + PAB + SSE + versioning + lifecycle[0])
#   EFS:         7  (file_system[0] + 2 mount_targets + 4 access_points)
#   ElastiCache: 2  (replication_group + subnet_group)
#
# NÃO importar (ficam no build): 62 aws_s3_object (conteúdo/filemd5), IAM/ECS do
# chainlit-data, random_password.grafana_db (senha via var.db_password).
# -----------------------------------------------------------------------------

# ---------- RDS Aurora ----------
import {
  to = module.rds_observability.aws_rds_cluster.this
  id = "teck-obs-hub-prod-db"
}
import {
  to = module.rds_observability.aws_rds_cluster_instance.this[0]
  id = "teck-obs-hub-prod-db-01"
}
import {
  to = module.rds_observability.aws_db_subnet_group.this
  id = "teck-obs-hub-prod-db-sng"
}

# ---------- S3 bucket: storage ----------
import {
  to = module.s3_bucket.aws_s3_bucket.this
  id = "teck-obs-hub-prod-storage"
}
import {
  to = module.s3_bucket.aws_s3_bucket_policy.this[0]
  id = "teck-obs-hub-prod-storage"
}
import {
  to = module.s3_bucket.aws_s3_bucket_public_access_block.this
  id = "teck-obs-hub-prod-storage"
}
import {
  to = module.s3_bucket.aws_s3_bucket_server_side_encryption_configuration.this
  id = "teck-obs-hub-prod-storage"
}
import {
  to = module.s3_bucket.aws_s3_bucket_versioning.this
  id = "teck-obs-hub-prod-storage"
}
import {
  to = aws_s3_bucket_lifecycle_configuration.storage
  id = "teck-obs-hub-prod-storage"
}

# ---------- S3 bucket: skills ----------
import {
  to = module.skills_bucket.aws_s3_bucket.this
  id = "teck-obs-hub-prod-skills"
}
import {
  to = module.skills_bucket.aws_s3_bucket_policy.this[0]
  id = "teck-obs-hub-prod-skills"
}
import {
  to = module.skills_bucket.aws_s3_bucket_public_access_block.this
  id = "teck-obs-hub-prod-skills"
}
import {
  to = module.skills_bucket.aws_s3_bucket_server_side_encryption_configuration.this
  id = "teck-obs-hub-prod-skills"
}
import {
  to = module.skills_bucket.aws_s3_bucket_versioning.this
  id = "teck-obs-hub-prod-skills"
}

# ---------- S3 bucket: chainlit_data (module count [0]) ----------
import {
  to = module.chainlit_data[0].aws_s3_bucket.this
  id = "teck-obs-hub-prod-chainlit-data"
}
import {
  to = module.chainlit_data[0].aws_s3_bucket_policy.this[0]
  id = "teck-obs-hub-prod-chainlit-data"
}
import {
  to = module.chainlit_data[0].aws_s3_bucket_public_access_block.this
  id = "teck-obs-hub-prod-chainlit-data"
}
import {
  to = module.chainlit_data[0].aws_s3_bucket_server_side_encryption_configuration.this
  id = "teck-obs-hub-prod-chainlit-data"
}
import {
  to = module.chainlit_data[0].aws_s3_bucket_versioning.this
  id = "teck-obs-hub-prod-chainlit-data"
}
import {
  to = aws_s3_bucket_lifecycle_configuration.chainlit_data[0]
  id = "teck-obs-hub-prod-chainlit-data"
}

# ---------- EFS ----------
import {
  to = aws_efs_file_system.this[0]
  id = "fs-00000000000000001"
}
import {
  to = aws_efs_mount_target.this["subnet-00000000000000001"]
  id = "fsmt-09cb3dcf889b07b39"
}
import {
  to = aws_efs_mount_target.this["subnet-00000000000000002"]
  id = "fsmt-0021cab50e9b7019e"
}
import {
  to = aws_efs_access_point.prometheus[0]
  id = "fsap-00000000000000001"
}
import {
  to = aws_efs_access_point.alertmanager[0]
  id = "fsap-00000000000000002"
}
import {
  to = aws_efs_access_point.qdrant[0]
  id = "fsap-00000000000000003"
}
import {
  to = aws_efs_access_point.grafana
  id = "fsap-00000000000000004"
}

# ---------- ElastiCache Redis (module count [0]) ----------
import {
  to = module.litellm_redis[0].aws_elasticache_replication_group.this
  id = "teck-obs-hub-prod-litellm-cache"
}
import {
  to = module.litellm_redis[0].aws_elasticache_subnet_group.this
  id = "teck-obs-hub-prod-litellm-cache-sng"
}
