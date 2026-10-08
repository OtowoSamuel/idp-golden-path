output "ecr_repository_url" {
  description = "ECR repository URL for the service image"
  value       = module.payments_api.repository_url
}

output "log_group_name" {
  description = "CloudWatch log group for the service"
  value       = module.payments_api_observability.log_group_name
}

output "alarm_arns" {
  description = "CloudWatch alarm ARNs"
  value       = module.payments_api_observability.alarm_arns
}
