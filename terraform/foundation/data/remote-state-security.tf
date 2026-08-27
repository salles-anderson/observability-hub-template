# -----------------------------------------------------------------------------
# Remote State - Foundation Security (o "cimento")
# -----------------------------------------------------------------------------
# Os recursos de data plane (RDS Aurora, EFS, S3, ElastiCache Redis) consomem o
# cimento transversal (KMS key + Security Groups rds/efs/redis) read-only do
# workspace `hub-foundation-security`, em vez de gerencia-lo. Mesmo padrao que o
# build usa em terraform/environment/build/remote-state-security.tf.
data "terraform_remote_state" "security" {
  backend = "remote"
  config = {
    organization = "YourOrg"
    workspaces = {
      name = "hub-foundation-security"
    }
  }
}

locals {
  security = data.terraform_remote_state.security.outputs
}
