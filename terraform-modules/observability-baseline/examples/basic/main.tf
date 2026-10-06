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
}

module "payments_api" {
  source = "../.."

  service_name       = "payments-api"
  environment        = "dev"
  team               = "payments"
  log_retention_days = 14
  alarm_enabled      = false
}

output "log_group_name" {
  value = module.payments_api.log_group_name
}
