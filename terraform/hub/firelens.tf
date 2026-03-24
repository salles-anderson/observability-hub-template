# -----------------------------------------------------------------------------
# FireLens - Fluent Bit Log Router Sidecar (Sprint 8A)
# -----------------------------------------------------------------------------
# Fluent Bit sidecar container que roteia logs dos containers ECS para o Loki
# via FireLens (awsfirelens log driver). Cada container app especifica as labels
# Loki inline no logConfiguration.options, sem necessidade de config file externo.
#
# Labels geradas: job=containerd, container=<nome_do_container>
# Compativel com dashboards existentes que usam {job="containerd", container="X"}
#
# NAO aplicado a: loki.tf, tempo.tf (recebem logs, enviar para si mesmos = loop)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# CloudWatch Log Group - FireLens (logs do proprio Fluent Bit)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "firelens" {
  name              = "/ecs/${local.name_prefix}/firelens"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-firelens-logs"
  })
}

# -----------------------------------------------------------------------------
# Locals - Fluent Bit Sidecar Container Definition (reutilizavel)
# -----------------------------------------------------------------------------
locals {
  # Container definition do Fluent Bit log router (FireLens)
  # Adicionado ao array de container_definitions de cada ECS task
  fluent_bit_container = {
    name      = "log-router"
    image     = local.images.fluent_bit
    essential = true

    firelensConfiguration = {
      type = "fluentbit"
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.firelens.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "firelens"
      }
    }

    memoryReservation = 50
  }
}
