# -----------------------------------------------------------------------------
# Import blocks (strangler) — adoção dos recursos do domínio EDGE
# -----------------------------------------------------------------------------
# O workspace hub-foundation-edge ASSUME os recursos já criados pelo monolito
# teck-observability-hub-prod (state serial 444), SEM recriar.
# Resultado esperado no `terraform plan` (TFC): SÓ imports, ZERO create/destroy/replace.
#
# Fonte: docs/plans/2026-06-15-sprint3-edge-import-ids.md (verificado read-only no
# state + cruzado com a AWS). Total: 12 instâncias.
#   ALB:       1  (aws_lb)
#   Listeners: 2  (http redirect + https fixed-response 404)
#   ACM:       4  (cert + cert_validation + 2 DNS validation records — wildcard + apex)
#   WAF:       3  (ip_set[0] + web_acl[0] + association[0], gated por CIDRs)
#   route53:   2  (grafana A-alias + teck_ai[0] A-alias)
#
# NÃO importar (ficam no build / S5): aws_lb_listener_rule.* + aws_lb_target_group.*
# de SERVIÇO (chainlit/grafana), aws_route53_record.chainlit_chat[0],
# authenticate-cognito (S5), prometheus-alb.tf (gated off, ausente do state).
# -----------------------------------------------------------------------------

# ---------- ALB — Application Load Balancer (module.alb) ----------
import {
  to = module.alb.aws_lb.this
  id = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/teck-obs-hub-prod-obs-hub-alb/6b45960787f54459"
}

# ---------- ALB Listeners — HTTP + HTTPS (top-level) ----------
import {
  to = aws_lb_listener.http
  id = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/app/teck-obs-hub-prod-obs-hub-alb/6b45960787f54459/c72a4f9b29df3bf3"
}
import {
  to = aws_lb_listener.https
  id = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/app/teck-obs-hub-prod-obs-hub-alb/6b45960787f54459/221782d0dfad981d"
}

# ---------- ACM — Certificate + validation (module.acm) ----------
# Os DOIS records de validação (wildcard + apex) compartilham o MESMO Import ID:
# wildcard e apex resolvem para o mesmo CNAME de validação → 1 único record DNS.
import {
  to = module.acm.aws_acm_certificate.this
  id = "arn:aws:acm:us-east-1:111111111111:certificate/066d8f3a-a3da-4fba-80f8-cf6f0ef3bb70"
}
import {
  to = module.acm.aws_route53_record.validation["*.observability.tower.yourorg.com.br"]
  id = "Z0000000000001EXAMPLE__0000000000000000000000000000abcd.observability.tower.yourorg.com.br._CNAME"
}
import {
  to = module.acm.aws_route53_record.validation["observability.tower.yourorg.com.br"]
  id = "Z0000000000001EXAMPLE__0000000000000000000000000000abcd.observability.tower.yourorg.com.br._CNAME"
}
# NOTA: aws_acm_certificate_validation NAO entra em import block — é um recurso
# LÓGICO/sintético do Terraform (so aguarda o cert ficar ISSUED), e o provider
# AWS retorna "resource aws_acm_certificate_validation doesn't support import".
# Deixamos o module.acm.aws_acm_certificate_validation.this ser CRIADO no apply:
# nao toca a AWS (o cert ja esta ISSUED), so registra a espera no state. Por isso
# o total importavel real e 11 (nao 12). Verificado no GATE#1 (run-5X9mtAbu932ojFEF).

# ---------- WAFv2 — Hub ALB protection (gated por CIDRs → índice [0]) ----------
import {
  to = aws_wafv2_ip_set.hub_allowlist[0]
  id = "8633d1da-e586-490f-947e-000ee56e686d/teck-obs-hub-prod-hub-allowlist/REGIONAL"
}
import {
  to = aws_wafv2_web_acl.hub[0]
  id = "c22c991f-7b2b-48d7-ac35-e325a8f05241/teck-obs-hub-prod-hub-waf/REGIONAL"
}
import {
  to = aws_wafv2_web_acl_association.hub[0]
  id = "arn:aws:wafv2:us-east-1:111111111111:regional/webacl/teck-obs-hub-prod-hub-waf/c22c991f-7b2b-48d7-ac35-e325a8f05241,arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/teck-obs-hub-prod-obs-hub-alb/6b45960787f54459"
}

# ---------- Route53 — A-alias records (grafana + teck_ai) ----------
import {
  to = module.route53_records.aws_route53_record.this["grafana"]
  id = "Z0000000000001EXAMPLE_grafana_A"
}
import {
  to = aws_route53_record.teck_ai[0]
  id = "Z0000000000001EXAMPLE_ai.observability.tower.yourorg.com.br_A"
}
