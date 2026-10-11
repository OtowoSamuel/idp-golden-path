mock_provider "aws" {}

run "creates_log_group_with_retention" {
  command = plan

  variables {
    service_name       = "payments-api"
    team               = "payments"
    log_retention_days = 14
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 14
    error_message = "Log retention must honor the variable"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/service/payments-api/dev"
    error_message = "Log group name must follow /service/<name>/<env> convention"
  }
}

run "alarm_disabled_by_default_override" {
  command = plan

  variables {
    service_name  = "payments-api"
    team          = "payments"
    alarm_enabled = false
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.http_5xx) == 0
    error_message = "alarm_enabled=false must create no alarm"
  }
}

run "alarm_created_when_enabled" {
  command = plan

  variables {
    service_name        = "payments-api"
    team                = "payments"
    alarm_enabled       = true
    alarm_5xx_threshold = 5
    load_balancer_name  = "a765917d4efb946b091b4dd8e1a09e0e"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.http_5xx[0].threshold == 5
    error_message = "Alarm threshold must honor the variable"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.http_5xx[0].treat_missing_data == "notBreaching"
    error_message = "Missing data must not breach (avoids false alarms on idle services)"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.http_5xx[0].namespace == "AWS/EC2"
    error_message = "Classic ELB (EKS default) must use AWS/EC2 namespace"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.http_5xx[0].dimensions["LoadBalancerName"] == "a765917d4efb946b091b4dd8e1a09e0e"
    error_message = "Classic ELB alarm must use LoadBalancerName dimension"
  }
}

run "alb_uses_applicationelb_namespace" {
  command = plan

  variables {
    service_name        = "payments-api"
    team                = "payments"
    alarm_enabled       = true
    load_balancer_name  = "app/golden-path-demo/1114911460"
    load_balancer_type  = "alb"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.http_5xx[0].namespace == "AWS/ApplicationELB"
    error_message = "ALB must use AWS/ApplicationELB namespace"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.http_5xx[0].dimensions["LoadBalancer"] == "app/golden-path-demo/1114911460"
    error_message = "ALB alarm must use LoadBalancer dimension"
  }
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    service_name = "payments-api"
    team         = "payments"
    environment  = "qa"
  }

  expect_failures = [var.environment]
}
