variable "service_name" {
  description = "Name of the service; used as the ECR repository name"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,39}$", var.service_name))
    error_message = "service_name must be 3-40 chars, lowercase alphanumeric and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "team" {
  description = "Owning team, applied as a tag for cost allocation and ownership"
  type        = string
}

variable "image_tag_mutability" {
  description = "IMMUTABLE prevents overwriting a pushed tag (recommended for prod)"
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Trigger ECR vulnerability scanning on every push"
  type        = bool
  default     = true
}

variable "keep_last_images" {
  description = "Lifecycle policy: number of tagged images to retain"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}
