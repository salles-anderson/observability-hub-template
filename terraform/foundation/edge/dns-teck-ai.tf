# -----------------------------------------------------------------------------
# ai.${var.domain_name} -> ALB (Fase 2)
# -----------------------------------------------------------------------------
# Historico: na Fase 1 o ai. era servido por um app Amplify (SPA Next.js de
# login). Na Fase 2 o login passou pro ALB authenticate-cognito (Hosted UI do
# Cognito) + Chainlit header_auth, entao o Amplify foi DECOMISSIONADO:
# aws_amplify_app.teck_ai_login + aws_amplify_branch.main removidos (estavam no
# state, via import) e o docker/teck-ai-login/amplify.yml apagado. O codigo do
# SPA (docker/teck-ai-login) fica como repo morto (referencia de paleta/logo pra
# estilizacao futura). O client publico aws_cognito_user_pool_client.teck_ai_login_spa
# ficou orfao (sem consumidor) — remover numa limpeza futura se nao for reaproveitado.
#
# Abaixo, o A-alias que faz ai. apontar pro ALB (ACM wildcard ja cobre ai.).
# -----------------------------------------------------------------------------
resource "aws_route53_record" "teck_ai" {
  count = var.enable_chainlit ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = "ai.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb.lb_dns_name
    zone_id                = module.alb.lb_zone_id
    evaluate_target_health = true
  }
}
