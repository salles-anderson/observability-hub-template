# -----------------------------------------------------------------------------
# Route 53 Records
# -----------------------------------------------------------------------------
module "route53_records" {
  source = "git@github.com:YOUR_ORG/terraform-aws-modules.git//modules/networking/route53?ref=v20260123110212-6e54d81"

  zone_id = var.hosted_zone_id

  records = {
    # Record A (Alias) para Grafana apontando para o ALB
    grafana = {
      name = "grafana"
      type = "A"
      alias = {
        name                   = module.alb.lb_dns_name
        zone_id                = module.alb.lb_zone_id
        evaluate_target_health = true
      }
    }
  }
}
