terraform {
  cloud {
    organization = "YourOrg"
    workspaces { name = "hub-foundation-network" }
  }
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags { tags = local.tags }
}
