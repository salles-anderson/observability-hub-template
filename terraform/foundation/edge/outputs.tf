# =============================================================================
# hub-foundation-edge — outputs consumidos pelos workspaces de servico (build)
# via data.terraform_remote_state.edge (Task E5).
#
# Nomes de atributo CONFIRMADOS contra os outputs dos modulos e o build:
#   module.alb (networking/alb) : lb_arn, lb_dns_name, lb_zone_id
#   module.acm (security/acm)   : arn  (build usa module.acm.arn)
#   listeners                   : aws_lb_listener.{http,https}.arn (top-level)
#   waf                         : aws_wafv2_web_acl.hub[0].arn (gated por count)
# =============================================================================

# --- ALB ---
output "alb_arn" {
  description = "ARN do ALB"
  value       = module.alb.lb_arn
}

# Alias de alb_arn — alguns consumidores referenciam lb_arn (nome do output do modulo).
output "lb_arn" {
  description = "ARN do ALB (alias de alb_arn)"
  value       = module.alb.lb_arn
}

output "alb_dns_name" {
  description = "DNS name do ALB"
  value       = module.alb.lb_dns_name
}

output "alb_zone_id" {
  description = "Zone ID do ALB"
  value       = module.alb.lb_zone_id
}

# --- Listeners ---
output "http_listener_arn" {
  description = "ARN do listener HTTP (:80 redirect -> HTTPS)"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN do listener HTTPS (:443)"
  value       = aws_lb_listener.https.arn
}

# --- ACM ---
output "acm_certificate_arn" {
  description = "ARN do certificado ACM"
  value       = module.acm.arn
}

# --- WAF ---
output "waf_web_acl_arn" {
  description = "ARN do Web ACL do WAF (null quando waf_allowed_cidrs vazio)"
  value       = try(aws_wafv2_web_acl.hub[0].arn, null)
}

# --- Route53 ---
output "route53_zone_id" {
  description = "ID da Hosted Zone usada pelos records do edge"
  value       = var.hosted_zone_id
}
