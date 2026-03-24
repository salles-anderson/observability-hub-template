# -----------------------------------------------------------------------------
# Terraform and Provider Configuration
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
  }

  cloud {
    organization = "YOUR_ORG"
    workspaces {
      name = "grafana-dashboards"
    }
  }
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_auth
}

# NOTE: Basic auth provider removed — grafana_user resource has a bug
# in provider v3.25.9 (TextConsumer parse error). Users managed via API.
# TODO: Re-add when provider fixes the bug or migrate to Cognito OAuth.
