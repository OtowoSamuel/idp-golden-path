variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "service_name" {
  description = "Service name (lowercase, matches the ECR/GHCR image name)"
  type        = string
  default     = "payments-api"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "team" {
  description = "Owning team (also applied as a tag)"
  type        = string
  default     = "platform"
}
