# Per-service baseline: ECR repository + logs + 5xx alarm.
# This is what the golden-path template points generated services at;
# run once per service per environment.
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "idp-golden-path"
      ManagedBy = "terraform"
    }
  }
}

module "payments_api" {
  source = "../../terraform-modules/service-baseline"

  service_name = var.service_name
  environment  = var.environment
  team         = var.team
}

module "payments_api_observability" {
  source = "../../terraform-modules/observability-baseline"

  service_name = var.service_name
  environment  = var.environment
  team         = var.team
}
