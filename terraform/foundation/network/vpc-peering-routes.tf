# -----------------------------------------------------------------------------
# VPC Peering Routes (REMOVIDO - migrado 100% para Transit Gateway)
# -----------------------------------------------------------------------------
# As rotas spoke deste Hub sao geridas via TGW pelo workspace
# vpc-core-infra-observability-prod (aws_route.hub_private/public_to_spoke_tgw).
# O peering pcx-0bbea so alcancava 172.19; as rotas peering deste ws eram drift
# (172.20/172.29 ja migradas p/ TGW por outro dono) ou blackhole (172.22-28).
#
# O bloco removed{} abaixo SOLTA o aws_route.spoke_vpc do state SEM destruir na
# AWS (destroy=false): as rotas TGW reais (dono = vpc-core) ficam intactas e as
# peering mortas ficam orfas inofensivas. Ver systematic-debugging 2026-07-16.
# -----------------------------------------------------------------------------

variable "vpc_peering_connection_id" {
  description = "DEPRECATED (nao usado; peering desativado, tudo via TGW)"
  type        = string
  default     = null
}

removed {
  from = aws_route.spoke_vpc

  lifecycle {
    destroy = false
  }
}
