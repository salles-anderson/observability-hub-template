# -----------------------------------------------------------------------------
# Chainlit Data Layer — bucket S3 p/ anexos (elements)
# -----------------------------------------------------------------------------
# Sprint Chainlit UX Fase C: histórico de conversas via data layer oficial do
# Chainlit (SQLAlchemyDataLayer no RDS db_obs_prod + S3StorageClient p/ anexos).
# Os elements (arquivos/imagens enviados no chat) vão pro bucket abaixo; o
# metadado (users/threads/steps/elements/feedbacks) fica no Postgres.
#
# DECOMPOSICAO (strangler): SO o bucket (module.chainlit_data) + o lifecycle
# (aws_s3_bucket_lifecycle_configuration.chainlit_data) migram para
# hub-foundation-data. O resto do chainlit-data.tf do build — IAM
# (aws_iam_role_policy.chainlit_data_s3, depende de aws_iam_role.chainlit_task),
# log group, task def chainlit_purge, EventBridge rule/target e a role
# chainlit_purge_events — e do SERVICO chainlit e PERMANECE no build.
# -----------------------------------------------------------------------------

module "chainlit_data" {
  count = var.enable_chainlit ? 1 : 0

  source = "git@github.com:YourOrg/terraform-aws-modules.git//modules/storage/s3-bucket?ref=v20260123110212-6e54d81"

  bucket_name        = "${local.name_prefix}-chainlit-data"
  versioning_enabled = true
  force_ssl          = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-chainlit-data"
  })
}

# -----------------------------------------------------------------------------
# Lifecycle — retenção de 7 dias (Fase C6)
# -----------------------------------------------------------------------------
# O purge do histórico (DELETE em threads > 7d) limpa o Postgres e, via
# delete_thread/delete_element do data layer, os objetos S3 referenciados. Este
# lifecycle é a rede de segurança p/ anexos órfãos (ex.: linha apagada por
# cascade FK no purge SQL não aciona o delete do S3). 7 dias = mesma janela.
resource "aws_s3_bucket_lifecycle_configuration" "chainlit_data" {
  count = var.enable_chainlit ? 1 : 0

  bucket = module.chainlit_data[0].bucket_id

  rule {
    id     = "chainlit-attachments-7d"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}
