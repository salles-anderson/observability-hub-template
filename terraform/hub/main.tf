# =============================================================================
# Observability Hub — Main Terraform Configuration
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  cloud {
    organization = "YOUR_ORG"
    workspaces {
      name = "observability-hub-prod"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# =============================================================================
# Locals
# =============================================================================
locals {
  name_prefix = "${var.project}-${var.environment}"
  ecr_prefix  = "${var.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/obs-hub"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "platform-engineering"
  }
}
