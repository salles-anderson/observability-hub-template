# -----------------------------------------------------------------------------
# VPC Peering Routes (DEPRECATED)
# -----------------------------------------------------------------------------
# NOTA: Este arquivo sera deprecado em favor do Transit Gateway.
# Quando enable_tgw_attachment = true, estas rotas serao ignoradas.
# Mantenha este arquivo para rollback em caso de problemas com TGW.
# Ver: transit-gateway.tf para a nova implementacao.
# -----------------------------------------------------------------------------

variable "vpc_peering_connection_id" {
  description = "ID da conexao VPC peering com spoke VPCs (deprecated - usar TGW)"
  type        = string
  default     = null
}

# Condição: usar peering APENAS se TGW não estiver habilitado
locals {
  use_vpc_peering = var.vpc_peering_connection_id != null && !var.enable_tgw_attachment
}

# Get route tables from VPC
data "aws_route_tables" "vpc" {
  count  = local.use_vpc_peering ? 1 : 0
  vpc_id = local.vpc_id
}

# Create routes to spoke VPCs via peering connection
resource "aws_route" "spoke_vpc" {
  for_each = local.use_vpc_peering ? toset(flatten([
    for rt in data.aws_route_tables.vpc[0].ids : [
      for cidr in var.spoke_vpc_cidrs : "${rt}:${cidr}"
    ]
  ])) : toset([])

  route_table_id            = split(":", each.key)[0]
  destination_cidr_block    = split(":", each.key)[1]
  vpc_peering_connection_id = var.vpc_peering_connection_id
}
