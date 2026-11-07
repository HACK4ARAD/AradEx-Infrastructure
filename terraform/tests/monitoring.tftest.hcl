mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:eu-north-1:712710404828:aradex-alerts" }
  }
}

variables {
  alert_email             = "a@b.ro"
  api_desired_count       = 1
  alb_arn_suffix          = "app/aradex-api/0123456789abcdef"
  target_group_arn_suffix = "targetgroup/aradex-api/0123456789abcdef"
  cluster_name            = "aradex"
  service_name            = "aradex-api"
  pipeline_arns = [
    "arn:aws:codepipeline:eu-north-1:712710404828:aradex-backend",
    "arn:aws:codepipeline:eu-north-1:712710404828:aradex-frontend",
  ]
}

run "monitoring" {
  command = apply
  module {
    source = "./modules/monitoring"
  }

  assert {
    condition     = aws_sns_topic.alerts.name == "aradex-alerts" && aws_sns_topic_subscription.email.protocol == "email" && aws_sns_topic_subscription.email.endpoint == "a@b.ro"
    error_message = "email subscription"
  }
  assert {
    condition     = toset(flatten([for s in jsondecode(aws_sns_topic_policy.alerts.policy).Statement : s.Principal.Service])) == toset(["codestar-notifications.amazonaws.com", "cloudwatch.amazonaws.com"])
    error_message = "topic policy allows codestar-notifications and cloudwatch"
  }
  assert {
    condition = (
      length(aws_cloudwatch_metric_alarm.healthy_hosts) == 1 &&
      aws_cloudwatch_metric_alarm.healthy_hosts[0].metric_name == "HealthyHostCount" &&
      aws_cloudwatch_metric_alarm.healthy_hosts[0].comparison_operator == "LessThanThreshold" &&
      aws_cloudwatch_metric_alarm.healthy_hosts[0].threshold == 1 &&
      aws_cloudwatch_metric_alarm.healthy_hosts[0].evaluation_periods == 2 &&
      aws_cloudwatch_metric_alarm.healthy_hosts[0].period == 60 &&
      aws_cloudwatch_metric_alarm.healthy_hosts[0].treat_missing_data == "breaching" &&
      aws_cloudwatch_metric_alarm.healthy_hosts[0].dimensions["TargetGroup"] == var.target_group_arn_suffix
    )
    error_message = "healthy hosts alarm"
  }
  assert {
    condition = (
      aws_cloudwatch_metric_alarm.target_5xx.metric_name == "HTTPCode_Target_5XX_Count" &&
      aws_cloudwatch_metric_alarm.target_5xx.statistic == "Sum" &&
      aws_cloudwatch_metric_alarm.target_5xx.period == 300 &&
      aws_cloudwatch_metric_alarm.target_5xx.threshold == 10 &&
      aws_cloudwatch_metric_alarm.target_5xx.comparison_operator == "GreaterThanOrEqualToThreshold" &&
      aws_cloudwatch_metric_alarm.target_5xx.treat_missing_data == "notBreaching"
    )
    error_message = "5xx alarm"
  }
  assert {
    condition = (
      aws_cloudwatch_metric_alarm.cpu.metric_name == "CPUUtilization" &&
      aws_cloudwatch_metric_alarm.cpu.namespace == "AWS/ECS" &&
      aws_cloudwatch_metric_alarm.cpu.threshold == 85 &&
      aws_cloudwatch_metric_alarm.cpu.evaluation_periods == 2 &&
      aws_cloudwatch_metric_alarm.cpu.period == 300
    )
    error_message = "cpu alarm"
  }
  assert {
    condition     = alltrue([for a in concat(aws_cloudwatch_metric_alarm.healthy_hosts, [aws_cloudwatch_metric_alarm.target_5xx, aws_cloudwatch_metric_alarm.cpu]) : contains(tolist(a.alarm_actions), "arn:aws:sns:eu-north-1:712710404828:aradex-alerts")])
    error_message = "alarms notify the topic"
  }
  assert {
    condition = (
      length(aws_codestarnotifications_notification_rule.pipeline) == 2 &&
      alltrue([for r in aws_codestarnotifications_notification_rule.pipeline : r.event_type_ids == toset(["codepipeline-pipeline-pipeline-execution-failed", "codepipeline-pipeline-pipeline-execution-succeeded"])])
    )
    error_message = "pipeline notification rules"
  }
  assert {
    condition = (
      aws_budgets_budget.monthly.limit_amount == "50" &&
      aws_budgets_budget.monthly.limit_unit == "USD" &&
      toset([for n in aws_budgets_budget.monthly.notification : n.threshold]) == toset([40, 100]) &&
      alltrue([for n in aws_budgets_budget.monthly.notification : n.threshold_type == "PERCENTAGE" && n.notification_type == "ACTUAL" && n.subscriber_email_addresses == toset(["a@b.ro"])])
    )
    error_message = "budget 50 USD with alerts at 40% and 100%"
  }
}

run "no_healthy_alarm_when_stopped" {
  command = apply
  module {
    source = "./modules/monitoring"
  }
  variables {
    api_desired_count = 0
    pipeline_arns     = []
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.healthy_hosts) == 0 && length(aws_codestarnotifications_notification_rule.pipeline) == 0
    error_message = "no healthy-host alarm at 0 tasks, no pipeline rules without pipelines"
  }
}
