# =============================================================================
# hub-foundation-lgtm — outputs
# =============================================================================
# YAGNI: nenhum output e exposto neste momento.
#
# JUSTIFICATIVA (grep em todo terraform/, 2026-06-17): nenhum workspace consome o
# lgtm via data.terraform_remote_state — o dominio LGTM e folha na cadeia de
# dependencias (consome network/security/data/edge/ai-platform, ninguem o consome
# de volta).
#
# O contrato do build com a stack LGTM e puramente de RUNTIME via DNS / service
# discovery (Cloud Map): os ECS services LGTM se registram nos
# service_discovery_services do ws network (grafana/loki/tempo/prometheus/
# alertmanager/otel), e outros servicos resolvem esses endpoints por DNS interno
# (ex.: <service>.observability.local), NAO via outputs Terraform. Portanto a
# religação do build (Task L5) NAO precisa de nenhum output deste ws.
#
# Diferente do ws ai-platform, que EXPOE alert_webhook_api_endpoint porque o build
# monta uma string de SSM/AlertManager a partir dele — o lgtm nao tem analogo.
#
# Adicionar outputs aqui SOMENTE quando um consumidor real (build ou outro ws)
# precisar referenciar um recurso LGTM por Terraform.
# =============================================================================
