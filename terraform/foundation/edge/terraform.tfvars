# =============================================================================
# hub-foundation-edge — valores NAO-SENSIVEIS (identicos a build/terraform.tfvars).
# =============================================================================

# -----------------------------------------------------------------------------
# General (identico a build/terraform.tfvars)
# -----------------------------------------------------------------------------
project      = "teck-obs-hub"
environment  = "prod"
owner        = "DevOps"
account_id   = "111111111111"
account_name = "teck-observability"
aws_region   = "us-east-1"

# -----------------------------------------------------------------------------
# ALB (identico a build)
# -----------------------------------------------------------------------------
alb_name     = "obs-hub-alb"
alb_internal = false

# -----------------------------------------------------------------------------
# ACM + Route53 (identico a build)
# -----------------------------------------------------------------------------
hosted_zone_id = "Z0000000000001EXAMPLE"
domain_name    = "observability.tower.yourorg.com.br"

# -----------------------------------------------------------------------------
# WAFv2 — Hub ALB allowlist
# -----------------------------------------------------------------------------
# RECONCILIADO 2026-06-25 (Terraform vira fonte da verdade): removido o
# ignore_changes[addresses] do waf.tf; esta lista agora reflete EXATAMENTE o
# estado desejado e e aplicada via TFC.
# ATUALIZADO 2026-07-21: reconciliado com o estado vivo do ip-set (15 entradas
# na AWS vs 12 no tfvars) + adicionado o novo IP do Wendeel. Drift reintegrado:
#   - 186.204.122.207 (Nader 2) e 179.101.156.49 estavam vivos no WAF mas fora
#     do tfvars; mantidos aqui para o plan nao remover acesso.
#   - ADICIONADO: 189.111.100.236 e 177.137.66.18 (Wendeel — IPs novos).
#   - Tethering Anderson mantido em /29 (como no state/AWS), nao /28.
# ATUALIZADO 2026-07-22: add 187.102.190.232/32 (Anderson tethering, fora do /29
#   224-231; nao coberto pela faixa existente).
# Total final: 18 entradas.
waf_allowed_cidrs = [
  "155.204.219.254/32", # Escritorio Teck
  "187.75.237.248/32",  # Escritorio Teck 2
  "155.204.202.214/32", # VPN EQX SP
  "155.204.219.244/32", # ABC Office — Matheus/Roberto (Grafana)
  "179.191.44.85/32",   # Home Office Anderson
  "191.32.144.60/32",   # Home Office Anderson (IP dinâmico)
  "187.102.190.224/29", # Tethering Anderson — faixa /29 (IPs 224-231)
  "189.40.73.105/32",   # Anderson — IP antigo (review para remocao)
  "189.120.72.145/32",  # Home Office Nader
  "186.204.122.207/32", # Nader 2 (reintegrado do estado vivo 2026-07-21)
  "177.129.116.217/32", # Home Office Edmário Oliveira
  "179.116.0.64/32",    # Home Office Eric Castro
  "179.101.156.49/32",  # (sem label — vivo no WAF, revisar dono)
  "177.137.67.90/32",   # Wendeel Marinho (wendeel.butel@yourorg.com.br) — Teck AI/Grafana
  "189.111.100.236/32", # Wendeel Marinho — IP novo (add 2026-07-21, telesp/dsl)
  "177.137.66.18/32",   # Wendeel Marinho — 2o IP (add 2026-07-21, via console)
  "181.77.150.199/32",  # Anderson — IP atual (add 2026-07-20, conta Infra)
  "187.102.190.232/32", # Anderson — tethering (add 2026-07-22, fora do /29)
]

# -----------------------------------------------------------------------------
# Feature flags (paridade com o state do monolito → counts corretos)
# -----------------------------------------------------------------------------
enable_chainlit = true

# -----------------------------------------------------------------------------
# Tags (paridade com build — fecha plan no-op: recursos importados tem Team=DevOps)
# -----------------------------------------------------------------------------
tags = {
  Team = "DevOps"
}
