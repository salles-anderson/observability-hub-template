# =============================================================================
# hub-foundation-lgtm — valores NAO-SENSIVEIS (identicos a build/terraform.tfvars).
# Gitignored por *.tfvars → commitado com `git add -f`.
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
# DNS (identico a build/ai-platform — usado pela listener rule/record do grafana)
# -----------------------------------------------------------------------------
hosted_zone_id = "Z0000000002EXAMPLE"
domain_name    = "observability.tower.yourorg.com.br"

# -----------------------------------------------------------------------------
# Feature flags (paridade com o state do monolito serial 445 → counts/strings corretos)
#   enable_aiops = true  → o alertmanager_config (ssm-configs.tf) renderiza
#     aiops_webhook_url = "${local.ai_platform.alert_webhook_api_endpoint}/prod/v2/webhook/alertmanager"
#     (= build). SEM esta linha o ramo cai p/ "" e o import do SSM nao fecha no-op.
#   enable_cloudtrail_loki = true → habilita os 7 recursos cloudtrail-loki (gated [0]).
#   enable_metric_streams = false (default) → prometheus-alb ausente do state (fora de escopo).
#   enable_alert_investigation: SEM linha aqui (= build, default=false no tfvars). MAS o
#     valor vivo e TRUE via TFC workspace var (confirmado no build e no ws ai-platform) →
#     setar como TFC workspace var no ws lgtm (senao o hash da task-def alertmanager/chainlit
#     diverge). Mesma classe da mina enable_agent_sdk do S5.
# -----------------------------------------------------------------------------
enable_aiops           = true
enable_cloudtrail_loki = true

# -----------------------------------------------------------------------------
# Tags (paridade com build — fecha plan no-op: recursos importados tem Team=DevOps)
# -----------------------------------------------------------------------------
tags = {
  Team = "DevOps"
}

# =============================================================================
# ⚠️ TFC WORKSPACE VARS (setar manualmente, NAO aqui):
#   - AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (env)  → marcar SENSITIVE ao criar.
#     Se ficarem sem a flag, a API do TFC devolve o valor em texto legivel para
#     qualquer token de leitura da organizacao. Prefira OIDC a chave estatica.
#   - GIT_SSH_COMMAND (env) = "ssh -o StrictHostKeyChecking=accept-new"
#   - enable_alert_investigation = true (terraform, nao-secreta, gerenciada fora do tfvars
#     no build) → setar como TFC var.
#   - slack_webhook_url (terraform) → valor do build; idealmente SENSITIVE.
# =============================================================================
