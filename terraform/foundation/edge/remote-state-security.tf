# -----------------------------------------------------------------------------
# Remote State - Foundation Security (o "cimento")
# -----------------------------------------------------------------------------
# Os recursos de edge (ALB + listeners + ACM + WAF + route53) consomem o cimento
# transversal read-only do workspace `hub-foundation-security`. Especificamente o
# ALB usa `local.security.alb_sg_id` (Security Group do ALB) via security_group_ids.
# Mesmo padrao que o build usa em terraform/environment/build/remote-state-security.tf.
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
