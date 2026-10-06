output "log_group_name" {
  description = "CloudWatch Log Group receiving this service's logs"
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.this.arn
}

output "alarm_arns" {
  description = "ARNs of created alarms (empty if alarm_enabled is false)"
  value       = aws_cloudwatch_metric_alarm.http_5xx[*].arn
}
