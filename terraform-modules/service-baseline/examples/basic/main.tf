terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      Example = "service-baseline"
    }
  }
}

module "payments_api" {
  source = "../.."

  service_name = "payments-api"
  environment  = "dev"
  team         = "payments"
}

output "repository_url" {
  value = module.payments_api.repository_url
}
