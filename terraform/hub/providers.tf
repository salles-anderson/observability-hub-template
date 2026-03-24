# -----------------------------------------------------------------------------
# Terraform Configuration
# -----------------------------------------------------------------------------
terraform {
  cloud {
    organization = "YOUR_ORG"

    workspaces {
      name = "teck-observability-hub-prod"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
  }
}

# -----------------------------------------------------------------------------
# AWS Provider
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}
