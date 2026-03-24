# -----------------------------------------------------------------------------
# AWS RAM - Resource Access Manager
# -----------------------------------------------------------------------------
# Compartilha recursos do Hub (TGW, Subnets) com contas spoke
# Permite que collectors nas spoke VPCs enviem telemetria para o Hub
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
variable "enable_ram_sharing" {
  description = "Habilitar compartilhamento de recursos via AWS RAM"
  type        = bool
  default     = false
}

variable "share_subnets" {
  description = "Compartilhar subnets privadas via RAM (para ECS tasks em outras contas)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Resource Share - Transit Gateway
# -----------------------------------------------------------------------------
resource "aws_ram_resource_share" "tgw" {
  count = var.enable_ram_sharing && var.enable_tgw_attachment && var.transit_gateway_id != null ? 1 : 0

  name                      = "${local.name_prefix}-tgw-share"
  allow_external_principals = false # Apenas dentro da Organization

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-tgw-share"
  })
}

# Associar TGW ao Resource Share
resource "aws_ram_resource_association" "tgw" {
  count = var.enable_ram_sharing && var.enable_tgw_attachment && var.transit_gateway_id != null ? 1 : 0

  resource_arn       = data.aws_ec2_transit_gateway.hub[0].arn
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}

# Compartilhar com contas spoke
resource "aws_ram_principal_association" "spoke_accounts" {
  for_each = var.enable_ram_sharing && var.enable_tgw_attachment && var.transit_gateway_id != null ? toset(var.spoke_account_ids) : toset([])

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}

# -----------------------------------------------------------------------------
# Resource Share - Subnets (opcional)
# Para cenarios onde tasks ECS de outras contas rodam nas subnets do Hub
# -----------------------------------------------------------------------------
resource "aws_ram_resource_share" "subnets" {
  count = var.enable_ram_sharing && var.share_subnets ? 1 : 0

  name                      = "${local.name_prefix}-subnets-share"
  allow_external_principals = false

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-subnets-share"
  })
}

resource "aws_ram_resource_association" "private_subnets" {
  for_each = var.enable_ram_sharing && var.share_subnets ? toset(local.private_subnet_ids) : toset([])

  resource_arn       = "arn:aws:ec2:${var.aws_region}:${var.account_id}:subnet/${each.value}"
  resource_share_arn = aws_ram_resource_share.subnets[0].arn
}

resource "aws_ram_principal_association" "spoke_accounts_subnets" {
  for_each = var.enable_ram_sharing && var.share_subnets ? toset(var.spoke_account_ids) : toset([])

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.subnets[0].arn
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "ram_tgw_share_arn" {
  description = "ARN do Resource Share do Transit Gateway"
  value       = var.enable_ram_sharing && var.enable_tgw_attachment && var.transit_gateway_id != null ? aws_ram_resource_share.tgw[0].arn : null
}

output "ram_tgw_share_id" {
  description = "ID do Resource Share do Transit Gateway"
  value       = var.enable_ram_sharing && var.enable_tgw_attachment && var.transit_gateway_id != null ? aws_ram_resource_share.tgw[0].id : null
}

output "ram_subnets_share_arn" {
  description = "ARN do Resource Share das Subnets"
  value       = var.enable_ram_sharing && var.share_subnets ? aws_ram_resource_share.subnets[0].arn : null
}

locals {
  spoke_onboarding_text = <<-EOT
    # Onboarding de Nova Conta Spoke

    ## 1. Aceitar RAM Share
    aws ram accept-resource-share-invitation \
      --resource-share-invitation-arn <ARN_DO_CONVITE>

    ## 2. Criar TGW Attachment na conta spoke
    - Transit Gateway ID: Usar o ID fornecido pelo time de Observability
    - Subnets: private subnets da VPC spoke
    - Habilitar DNS support

    ## 3. Configurar rotas para o Hub
    - Destination: CIDR da VPC do Hub (172.30.0.0/16)
    - Target: Transit Gateway Attachment

    ## 4. Configurar collector (Alloy/OTel) para enviar telemetria
    - OTLP gRPC: alloy.observability.local:4317
    - OTLP HTTP: alloy.observability.local:4318

    ## 5. Validar conectividade
    - Testar ping/telnet para os endpoints
    - Verificar logs no CloudWatch
  EOT
}

output "spoke_onboarding_instructions" {
  description = "Instrucoes para onboarding de novas contas spoke"
  value       = var.enable_ram_sharing && var.enable_tgw_attachment ? local.spoke_onboarding_text : null
}
