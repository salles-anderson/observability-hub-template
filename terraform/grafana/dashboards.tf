# -----------------------------------------------------------------------------
# Grafana Dashboards - Templated + Static
# -----------------------------------------------------------------------------

locals {
  # Template variants per dashboard type and project
  template_variants = {
    ecs-metrics = { example-api = "ecs-metrics-cloudwatch", default = "ecs-metrics-cloudwatch" }
    logs        = { example-api = "logs-example-api", default = "logs" }
  }

  # Mapeamento account_key -> datasource CloudWatch
  account_cloudwatch_ds = {
    "yourorg-dev"     = var.datasources.cloudwatch_dev
    "yourorg-homolog" = var.datasources.cloudwatch_homolog
    "yourorg-prod"    = var.datasources.cloudwatch_prod
    "yourorg-infra"   = var.datasources.cloudwatch_infra
    "akrk-dev"             = var.datasources.cloudwatch_akrkdev
    "abccard"              = var.datasources.cloudwatch_abccard
  }

  # Resolve service_job per environment:
  # dev -> service_job as-is, hml/prd -> service_job-{env}
  resolve_service_job = {
    for key, config in local.account_project_envs :
    key => config.environment == "dev" ? config.project.service_job : "${config.project.service_job}-${config.environment}"
  }

  # 4 templated dashboards per project-env
  templated_dashboards = merge([
    for key, config in local.account_project_envs : {
      for tpl in config.project.templates :
      "tpl-${key}-${tpl}" => {
        key           = key
        template_file = lookup(lookup(local.template_variants, tpl, {}), config.project_key, lookup(lookup(local.template_variants, tpl, {}), "default", tpl))
        dashboard_uid = "${config.project_key}-${config.environment}-${tpl}"
        title         = "${config.project.name} ${title(replace(tpl, "-", " "))} (${upper(config.environment)})"
        tags          = jsonencode([config.project_key, split("-", tpl)[0], config.environment])
        service_job   = local.resolve_service_job[key]
        ds_prometheus = var.datasources.prometheus
        ds_loki       = var.datasources.loki
        ds_tempo      = var.datasources.tempo
        ds_cloudwatch    = lookup(local.account_cloudwatch_ds, config.account_key, var.datasources.cloudwatch_dev)
        ecs_cluster_name = config.project.ecs_cluster_name
        ecs_service_name = config.environment == "dev" ? config.project.ecs_service_name : (config.project.ecs_service_name != "" ? "${config.project.ecs_service_name}" : "")
        alb_arn_suffix   = config.project.alb_arn_suffix
        rds_instance_id  = config.project.rds_instance_id
        redis_cluster_id = config.project.redis_cluster_id
        sqs_queue_name   = config.project.sqs_queue_name
        sqs_dlq_name     = config.project.sqs_dlq_name
      }
    }
  ]...)

  # Static dashboards: JSONs that are NOT one of the 4 templated types
  templated_types = toset(["api-overview.json", "logs.json", "traces.json", "ecs-metrics.json"])

  static_dashboards = merge([
    for key, config in local.account_project_envs : {
      for file in setsubtract(
        try(fileset("${path.module}/dashboards/${config.account_key}/${config.project_key}/${config.environment}", "*.json"), toset([])),
        local.templated_types
        ) : "static-${key}-${trimsuffix(file, ".json")}" => {
        key  = key
        path = "${path.module}/dashboards/${config.account_key}/${config.project_key}/${config.environment}/${file}"
      }
    }
  ]...)
}

resource "grafana_dashboard" "templated" {
  for_each = local.templated_dashboards
  folder   = grafana_folder.account_project_env[each.value.key].id
  config_json = templatefile(
    "${path.module}/dashboards/templates/${each.value.template_file}.json.tftpl",
    {
      dashboard_uid    = each.value.dashboard_uid
      title            = each.value.title
      tags             = each.value.tags
      service_job      = each.value.service_job
      ds_prometheus    = each.value.ds_prometheus
      ds_loki          = each.value.ds_loki
      ds_tempo         = each.value.ds_tempo
      ds_cloudwatch    = each.value.ds_cloudwatch
      ecs_cluster_name = each.value.ecs_cluster_name
      ecs_service_name = each.value.ecs_service_name
      alb_arn_suffix   = each.value.alb_arn_suffix
      rds_instance_id  = each.value.rds_instance_id
      redis_cluster_id = each.value.redis_cluster_id
      sqs_queue_name   = each.value.sqs_queue_name
      sqs_dlq_name     = each.value.sqs_dlq_name
    }
  )
  overwrite = true
}

resource "grafana_dashboard" "static" {
  for_each    = local.static_dashboards
  folder      = grafana_folder.account_project_env[each.value.key].id
  config_json = file(each.value.path)
  overwrite   = true
}

# Output para debug
output "dashboards_created" {
  description = "Lista de dashboards criados"
  value = merge(
    {
      for k, v in grafana_dashboard.templated : k => {
        title  = jsondecode(v.config_json).title
        folder = v.folder
        uid    = v.uid
      }
    },
    {
      for k, v in grafana_dashboard.static : k => {
        title  = jsondecode(v.config_json).title
        folder = v.folder
        uid    = v.uid
      }
    }
  )
}
