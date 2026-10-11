variable "service_name" {
  description = "Name of the service this baseline belongs to"
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
  description = "Owning team, applied as a tag"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days (0 = never expire)"
  type        = number
  default     = 30
}

variable "alarm_5xx_threshold" {
  description = "HTTP 5xx count per 5 minutes that triggers the alarm"
  type        = number
  default     = 10
}

variable "alarm_enabled" {
  description = "Create the 5xx CloudWatch alarm (disable for cost-sensitive dev)"
  type        = bool
  default     = true
}

variable "alarm_topic_arn" {
  description = "SNS topic ARN for alarm notifications; null skips subscription"
  type        = string
  default     = null
}

variable "load_balancer_name" {
  description = "Name of the load balancer to monitor (e.g. from kubectl get svc). Required when alarm_enabled=true."
  type        = string
  default     = null
}

variable "load_balancer_type" {
  description = "LB type: 'classic' (EKS default, AWS/EC2 namespace) or 'alb' (AWS/ApplicationELB namespace)"
  type        = string
  default     = "classic"

  validation {
    condition     = contains(["classic", "alb"], var.load_balancer_type)
    error_message = "load_balancer_type must be 'classic' or 'alb'."
  }
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}
