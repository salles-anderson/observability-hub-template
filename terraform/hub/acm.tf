# -----------------------------------------------------------------------------
# ACM Certificate
# -----------------------------------------------------------------------------
module "acm" {
  source = "git@github.com:YOUR_ORG/terraform-aws-modules.git//modules/security/acm?ref=v20260123110212-6e54d81"

  domain_name               = "*.${var.domain_name}"
  subject_alternative_names = [var.domain_name]
  hosted_zone_id            = var.hosted_zone_id

  tags = local.tags
}
