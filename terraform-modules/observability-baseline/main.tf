locals {
  tags = merge({
    Service     = var.service_name
    Environment = var.environment
    Team        = var.team
    ManagedBy   = "terraform"
    Project     = "idp-golden-path"
  }, var.tags)
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/service/${var.service_name}/${var.environment}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  count = var.alarm_enabled ? 1 : 0

  alarm_name          = "${var.service_name}-${var.environment}-http-5xx"
  alarm_description   = "5xx errors above threshold for ${var.service_name}"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.alarm_5xx_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Service = var.service_name
  }

  alarm_actions = var.alarm_topic_arn != null ? [var.alarm_topic_arn] : []
  tags          = local.tags
}
