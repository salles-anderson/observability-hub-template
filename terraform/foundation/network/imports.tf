# -----------------------------------------------------------------------------
# Import blocks (strangler) — adocao dos 47 recursos de rede existentes
# -----------------------------------------------------------------------------
# Objetivo: o workspace hub-foundation-network ASSUME os recursos ja criados
# pelo monolito teck-observability-hub-prod (state serial 440), SEM recriar.
# Resultado esperado no `terraform plan` (rodado no TFC): SO imports, ZERO
# create/destroy/replace.
#
# Fonte dos IDs: docs/plans/2026-06-13-sprint1-import-ids-gabarito.md
#
# Total: 47 instancias
#   1  module.ecs_cluster.aws_ecs_cluster.this
#   1  module.ecs_cluster.aws_ecs_cluster_capacity_providers.this[0]
#   1  aws_service_discovery_private_dns_namespace.observability
#   1  aws_service_discovery_service.aiops_agent_apigw[0]
#  11  aws_service_discovery_service.services[*]
#   2  aws_route53_vpc_association_authorization.spoke[*]
#  30  aws_route.spoke_vpc[*]
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Mapas-fonte de import IDs
# -----------------------------------------------------------------------------
locals {
  # Service Discovery services (for_each — chave casa local.service_discovery_services)
  sd_service_import_ids = {
    alertmanager  = "srv-xezg7wvz7mj46rpq"
    chainlit_chat = "srv-h2mpfa7olpkvcrmi"
    grafana       = "srv-zngy77rsxtdva2ev"
    litellm       = "srv-khzbwswcppzbasf5"
    loki          = "srv-7trxkt3ot34vyqzx"
    mcp_servers   = "srv-xadrabwg2t5fulzv"
    mcp_sre       = "srv-t4hlxccsu663vyyu"
    otel          = "srv-datiwhafrwoqmljf"
    prometheus    = "srv-gt67cqu3yxl7tvha"
    qdrant        = "srv-r5jvhwykbnwwg6bh"
    tempo         = "srv-bpri5vp2faztyzzx"
  }

  # Route53 VPC association authorizations (for_each — chave casa var.spoke_vpc_dns_associations)
  # ID = "<zone_id>:<vpc_id>"
  spoke_assoc_import_ids = {
    abccard-prod     = "Z0000000000002EXAMPLE:vpc-00000000000000003"
    yourorg-dev = "Z0000000000002EXAMPLE:vpc-00000000000000004"
  }

  # (Spoke VPC routes removidas: peering desativado, rotas geridas via TGW pelo
  # workspace vpc-core-infra-observability-prod. Ver vpc-peering-routes.tf removed{}.)
}

# -----------------------------------------------------------------------------
# ECS Cluster (modulo, singletons)
# -----------------------------------------------------------------------------
import {
  to = module.ecs_cluster.aws_ecs_cluster.this
  # aws_ecs_cluster importa pelo NOME do cluster, nao pelo ARN
  # (passar o ARN faz o provider prefixar "cluster/" e duplicar -> InvalidParameterException)
  id = "cluster-prod"
}

import {
  to = module.ecs_cluster.aws_ecs_cluster_capacity_providers.this[0]
  id = "cluster-prod"
}

# -----------------------------------------------------------------------------
# Service Discovery — namespace (singleton)
# -----------------------------------------------------------------------------
import {
  to = aws_service_discovery_private_dns_namespace.observability
  # private_dns_namespace importa no formato NAMESPACE_ID:VPC_ID
  # vpc do hub = local.vpc_id (vpc-00000000000000008)
  id = "ns-rvvzfuqazpx664lh:vpc-00000000000000008"
}

# -----------------------------------------------------------------------------
# Service Discovery — aiops_agent_apigw (count, indice 0)
# -----------------------------------------------------------------------------
import {
  to = aws_service_discovery_service.aiops_agent_apigw[0]
  id = "srv-d6t4gxoziieeygkx"
}

# -----------------------------------------------------------------------------
# Service Discovery — services (for_each, x11)
# -----------------------------------------------------------------------------
import {
  for_each = local.sd_service_import_ids
  to       = aws_service_discovery_service.services[each.key]
  id       = each.value
}

# -----------------------------------------------------------------------------
# Route53 VPC association authorizations (for_each, x2)
# -----------------------------------------------------------------------------
import {
  for_each = local.spoke_assoc_import_ids
  to       = aws_route53_vpc_association_authorization.spoke[each.key]
  id       = each.value
}

# (Import de aws_route.spoke_vpc removido: recurso saiu de gerenciamento via
#  removed{} em vpc-peering-routes.tf; rotas spoke agora sao TGW no vpc-core.)
