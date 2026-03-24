# -----------------------------------------------------------------------------
# DynamoDB - Incident Correlation Table (Sprint 5)
# -----------------------------------------------------------------------------
# Armazena incidentes correlacionados com lifecycle, timeline, MTTR e AI context.
# TTL de 90 dias para limpeza automatica de incidentes antigos.
# GSIs para queries por status e severity com ordering por created_at.
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "incidents" {
  count = var.enable_aiops ? 1 : 0

  name         = "${local.name_prefix}-incidents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "incident_id"

  attribute {
    name = "incident_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  attribute {
    name = "severity"
    type = "S"
  }

  global_secondary_index {
    name            = "status-created_at-index"
    hash_key        = "status"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "severity-created_at-index"
    hash_key        = "severity"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-incidents"
  })
}
