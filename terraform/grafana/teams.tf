# -----------------------------------------------------------------------------
# Grafana Teams - Tecksign
# -----------------------------------------------------------------------------
# NOTA: Membros removidos pois recursos de usuários requerem basic auth.
# Adicione membros manualmente via UI do Grafana ou configure basic auth.
# -----------------------------------------------------------------------------

resource "grafana_team" "example-api_admins" {
  name    = "example-api-admins"
  email   = "example-api-admins@yourorg.com.br"
  members = []
}

resource "grafana_team" "example-api_developers" {
  name    = "example-api-developers"
  email   = "example-api-developers@yourorg.com.br"
  members = []
}

resource "grafana_team" "example-api_viewers" {
  name    = "example-api-viewers"
  email   = "example-api-viewers@yourorg.com.br"
  members = []
}

resource "grafana_team" "example-api_oncall" {
  name    = "example-api-oncall"
  email   = "example-api-oncall@yourorg.com.br"
  members = []
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "teams" {
  description = "Teams criados"
  value = {
    example-api_admins     = grafana_team.example-api_admins.id
    example-api_developers = grafana_team.example-api_developers.id
    example-api_viewers    = grafana_team.example-api_viewers.id
    example-api_oncall     = grafana_team.example-api_oncall.id
  }
}
