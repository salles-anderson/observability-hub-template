# -----------------------------------------------------------------------------
# Spoke DNS - Associar Cloud Map PHZ com VPCs de spoke accounts
# Permite que containers em spoke VPCs resolvam *.observability.local
# -----------------------------------------------------------------------------
#
# IMPORTANTE: Para cada VPC adicionada, executar na conta dona da VPC:
#
#   aws route53 associate-vpc-with-hosted-zone \
#     --hosted-zone-id <output.cloudmap_hosted_zone_id> \
#     --vpc VPCRegion=us-east-1,VPCId=<VPC_ID>
#
# O authorization abaixo apenas PERMITE a associacao; nao a executa.
# A associacao precisa ser feita com credenciais da conta que possui a VPC.
# -----------------------------------------------------------------------------

resource "aws_route53_vpc_association_authorization" "spoke" {
  for_each = var.spoke_vpc_dns_associations

  vpc_id  = each.value
  zone_id = aws_service_discovery_private_dns_namespace.observability.hosted_zone

  lifecycle {
    create_before_destroy = true
  }
}

output "cloudmap_hosted_zone_id" {
  description = "Hosted Zone ID do Cloud Map (para associacao cross-account)"
  value       = aws_service_discovery_private_dns_namespace.observability.hosted_zone
}
