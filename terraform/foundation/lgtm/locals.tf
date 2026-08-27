# -----------------------------------------------------------------------------
# Naming Convention
# -----------------------------------------------------------------------------
locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      AccountID   = var.account_id
      AccountName = var.account_name
      Workspace   = "teck-observability-hub-prod"
      Layer       = "observability"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# VPC / Subnets (hardcoded — paridade no-op com o monolito)
# -----------------------------------------------------------------------------
# WORKAROUND: Valores hardcoded (extraidos do state em 2026-01-27).
# VPC Workspace: vpc-core-infra-observability-prod
# Replicado EXATO do monolito (terraform/environment/build/locals.tf) e dos ws
# edge/ai-platform (terraform/foundation/{edge,ai-platform}/locals.tf) para garantir
# paridade no-op. No dominio LGTM: grafana.tf/prometheus-alb.tf usam local.vpc_id
# (target groups); loki/tempo/prometheus/alertmanager/alloy/grafana services usam
# local.private_subnet_ids (network_configuration). O ALB/subnets em si sao do edge
# (consumidos via local.edge.*). public_subnet_ids NAO e referenciado por nenhum
# recurso LGTM (omitido por YAGNI).
locals {
  vpc_id             = "vpc-00000000000000008"
  private_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002"]
}

# -----------------------------------------------------------------------------
# ECR prefix + imagens (intra-ws — portado de build/locals.tf:47-74)
# -----------------------------------------------------------------------------
# `ecr_prefix` portado VERBATIM (build/locals.tf:47). `images` portado mas TRIMADO
# apenas para as chaves que os arquivos do dominio LGTM realmente referenciam:
# grafana/loki/tempo/prometheus/alertmanager/alloy (os 6 servicos) + busybox
# (init container do prometheus) + fluent_bit (sidecar FireLens, ver
# local.fluent_bit_container abaixo). As chaves de AI-PLATFORM (litellm/qdrant/
# aiops_agent/os 11 mcp_*) e k6 NAO entram: nenhum recurso LGTM as usa.
locals {
  ecr_prefix = "${var.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/obs-hub"

  images = {
    grafana      = "${local.ecr_prefix}/grafana:${split(":", var.grafana_image)[1]}"
    prometheus   = "${local.ecr_prefix}/prometheus:${split(":", var.prometheus_image)[1]}"
    loki         = "${local.ecr_prefix}/loki:${split(":", var.loki_image)[1]}"
    tempo        = "${local.ecr_prefix}/tempo:${split(":", var.tempo_image)[1]}"
    alloy        = "${local.ecr_prefix}/alloy:${split(":", var.alloy_image)[1]}"
    alertmanager = "${local.ecr_prefix}/alertmanager:${split(":", var.alertmanager_image)[1]}"
    busybox      = "${local.ecr_prefix}/busybox:1.36"
    fluent_bit   = "${local.ecr_prefix}/fluent-bit:3.2"
  }
}

# -----------------------------------------------------------------------------
# FireLens - Fluent Bit Log Router Sidecar (definicao reutilizavel)
# -----------------------------------------------------------------------------
# Portado de terraform/environment/build/firelens.tf (bloco local.fluent_bit_container).
# No dominio LGTM, a task-def do Grafana (grafana.tf) inclui este container sidecar
# no array de container_definitions (loki/tempo recebem logs => nao roteiam para si).
#
# ⚠️ DECISAO (user — Option 1, string literal): o CloudWatch Log Group do FireLens
# (aws_cloudwatch_log_group.firelens) e infra de LOGGING COMPARTILHADA por TODAS as
# tasks ECS do hub (LGTM + AI-PLATFORM). Ele PERMANECE no workspace build e NAO e
# importado para o lgtm. Para evitar uma dependencia cross-ws REVERSA (lgtm -> build),
# referenciamos o LG pelo seu NOME LITERAL determinístico
# ("/ecs/${local.name_prefix}/firelens") — exatamente o mesmo valor que
# aws_cloudwatch_log_group.firelens.name produz no build (firelens.tf:18). Valor
# identico => import das task-defs (L3) fecha no-op. Mesma classe dos locals
# hardcoded de vpc/subnets (paridade no-op com o monolito) e identico ao approach do
# ws ai-platform (terraform/foundation/ai-platform/firelens-container.tf).
#
# NAO criar aqui o recurso aws_cloudwatch_log_group.firelens (fica no build).
locals {
  # Container definition do Fluent Bit log router (FireLens)
  # Adicionado ao array de container_definitions de cada ECS task
  fluent_bit_container = {
    name = "log-router"
    # Imagem oficial fluent/fluent-bit:3.2 é distroless — sem sh nem kill.
    # Health check via shell falha. Solução: essential=true (ECS exige pelo
    # menos 1 essential) + SEM health check. ECS marca como UNKNOWN, mas
    # combinado com min_healthy_percent=0 e circuit_breaker enabled, o
    # rollout não fica bloqueado.
    image     = local.images.fluent_bit
    essential = true

    firelensConfiguration = {
      type = "fluentbit"
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        # String literal (= aws_cloudwatch_log_group.firelens.name no build) —
        # o LG e logging compartilhado e fica no build. Ver cabecalho.
        "awslogs-group"         = "/ecs/${local.name_prefix}/firelens"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "firelens"
      }
    }

    memoryReservation = 50
  }
}
