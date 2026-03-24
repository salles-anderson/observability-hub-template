# -----------------------------------------------------------------------------
# Transit Gateway Integration
# -----------------------------------------------------------------------------
# Integra o Hub de Observabilidade com o Transit Gateway existente
# TGW centraliza o roteamento entre todas as VPCs da organizacao
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
variable "transit_gateway_id" {
  description = "ID do Transit Gateway existente (deixar vazio para desabilitar)"
  type        = string
  default     = null
}

variable "enable_tgw_attachment" {
  description = "Habilitar attachment do Hub VPC ao Transit Gateway"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Data Source - Transit Gateway existente
# -----------------------------------------------------------------------------
data "aws_ec2_transit_gateway" "hub" {
  count = var.enable_tgw_attachment && var.transit_gateway_id != null ? 1 : 0

  id = var.transit_gateway_id
}

# -----------------------------------------------------------------------------
# TGW Attachment - Hub VPC
# -----------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  count = var.enable_tgw_attachment && var.transit_gateway_id != null ? 1 : 0

  subnet_ids         = local.private_subnet_ids
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = local.vpc_id

  dns_support                                     = "enable"
  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-hub-tgw-attachment"
  })
}

# -----------------------------------------------------------------------------
# VPC Routes para Transit Gateway
# Rotas das spoke VPCs via TGW (desacoplado do attachment — attachment
# gerenciado pelo workspace vpc-core-infra-observability-prod)
# -----------------------------------------------------------------------------
# Get route tables from VPC
data "aws_route_tables" "vpc_for_tgw" {
  count  = var.transit_gateway_id != null ? 1 : 0
  vpc_id = local.vpc_id
}

# Create routes to spoke VPCs via TGW
resource "aws_route" "spoke_vpc_via_tgw" {
  for_each = var.transit_gateway_id != null ? toset(flatten([
    for rt in data.aws_route_tables.vpc_for_tgw[0].ids : [
      for cidr in var.spoke_vpc_cidrs : "${rt}:${cidr}"
    ]
  ])) : toset([])

  route_table_id         = split(":", each.key)[0]
  destination_cidr_block = split(":", each.key)[1]
  transit_gateway_id     = var.transit_gateway_id

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "transit_gateway_id" {
  description = "ID do Transit Gateway utilizado"
  value       = var.transit_gateway_id
}

output "tgw_attachment_id" {
  description = "ID do attachment do Hub VPC ao TGW"
  value       = var.enable_tgw_attachment && var.transit_gateway_id != null ? aws_ec2_transit_gateway_vpc_attachment.hub[0].id : null
}

output "tgw_attachment_vpc_owner" {
  description = "Owner ID da VPC attachada ao TGW"
  value       = var.enable_tgw_attachment && var.transit_gateway_id != null ? aws_ec2_transit_gateway_vpc_attachment.hub[0].vpc_owner_id : null
}
