# -----------------------------------------------------------------------------
# Grafana Folders - Account > Project > Environment
# -----------------------------------------------------------------------------

locals {
  # Flatten: account > project
  account_projects = merge([
    for account_key, account in var.accounts : {
      for project_key, project in account.projects :
      "${account_key}-${project_key}" => {
        account_key = account_key
        project_key = project_key
        project     = project
      }
    }
  ]...)

  # Flatten: account > project > environment
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

# 1. Root folders (12 accounts)
resource "grafana_folder" "account" {
  for_each = var.accounts
  title    = each.value.name
  uid      = "acct-${each.key}"
}

# 2. Project subfolders
resource "grafana_folder" "account_project" {
  for_each          = local.account_projects
  title             = each.value.project.name
  uid               = "acct-${each.key}"
  parent_folder_uid = grafana_folder.account[each.value.account_key].uid
}

# 4. Environment sub-subfolders
resource "grafana_folder" "account_project_env" {
  for_each          = local.account_project_envs
  title             = upper(each.value.environment)
  uid               = "acct-${each.key}"
  parent_folder_uid = grafana_folder.account_project["${each.value.account_key}-${each.value.project_key}"].uid
}
