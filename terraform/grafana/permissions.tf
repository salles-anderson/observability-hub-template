# -----------------------------------------------------------------------------
# Grafana Folder Permissions - Tecksign
# -----------------------------------------------------------------------------

# DEV - Admins: Admin, Developers: Viewer, Viewers: Viewer
resource "grafana_folder_permission" "example-api_dev" {
  folder_uid = grafana_folder.account_project_env["yourorg-dev-example-api-dev"].uid

  permissions {
    team_id    = grafana_team.example-api_admins.id
    permission = "Admin"
  }

  permissions {
    team_id    = grafana_team.example-api_developers.id
    permission = "View"
  }

  permissions {
    team_id    = grafana_team.example-api_viewers.id
    permission = "View"
  }
}

# HML/PRD permissions removidas na PoC cleanup (sem infra provisionada)
# Para restaurar: git revert deste commit
