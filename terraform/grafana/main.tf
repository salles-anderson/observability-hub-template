# =============================================================================
# Grafana Dashboards — Main Configuration
# =============================================================================
# Separate workspace from hub infrastructure.
# Manages: dashboards, alerts, folders, teams, notifications.
# =============================================================================

# Locals for project-environment mapping
locals {
  account_project_envs = merge([
    for account_key, account in var.accounts : merge([
      for project_key, project in account.projects : {
        for env in project.environments :
        "${account_key}-${project_key}-${env}" => {
          account_key = account_key
          project_key = project_key
          project     = project
          environment = env
        }
      }
    ]...)
  ]...)
}
