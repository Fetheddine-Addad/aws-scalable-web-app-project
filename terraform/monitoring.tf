# -----------------------------------------------------------------------------
# CloudWatch dashboard, alarms and SNS notifications
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name}-alb-5xx"
  alarm_description   = "Five or more 5xx responses in a minute (ELB or targets)"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name}-unhealthy-hosts"
  alarm_description   = "At least one target is failing ALB health checks"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "asg_cpu_high" {
  alarm_name          = "${local.name}-asg-cpu-high"
  alarm_description   = "Fleet average CPU above 80% for 3 minutes (scaling is not keeping up or is at max)"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${local.name}-rds-cpu-high"
  alarm_description   = "Database CPU above 80% for 5 minutes"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${local.name}-rds-storage-low"
  alarm_description   = "Less than 2 GiB of free database storage"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2147483648
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

# ---------------------------------------------------------------- dashboard

locals {
  dashboard_widgets = [
    {
      type = "metric", x = 0, y = 0, width = 12, height = 6
      properties = {
        title  = "ALB requests and 5xx"
        region = var.region
        stat   = "Sum"
        period = 60
        view   = "timeSeries"
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix],
          [".", "HTTPCode_Target_5XX_Count", ".", ".", { color = "#d62728" }],
          [".", "HTTPCode_ELB_5XX_Count", ".", ".", { color = "#ff7f0e" }],
        ]
      }
    },
    {
      type = "metric", x = 12, y = 0, width = 12, height = 6
      properties = {
        title  = "Target response time (p50 / p90)"
        region = var.region
        period = 60
        view   = "timeSeries"
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix, { stat = "p50", label = "p50" }],
          ["...", { stat = "p90", label = "p90" }],
        ]
      }
    },
    {
      type = "metric", x = 0, y = 6, width = 12, height = 6
      properties = {
        title  = "Auto Scaling: instances in service vs desired"
        region = var.region
        stat   = "Average"
        period = 60
        view   = "timeSeries"
        metrics = [
          ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", aws_autoscaling_group.app.name],
          [".", "GroupDesiredCapacity", ".", "."],
          [".", "GroupMaxSize", ".", ".", { color = "#999999" }],
        ]
      }
    },
    {
      type = "metric", x = 12, y = 6, width = 12, height = 6
      properties = {
        title  = "Fleet CPU vs target tracking goal"
        region = var.region
        stat   = "Average"
        period = 60
        view   = "timeSeries"
        metrics = [
          ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.app.name],
        ]
        annotations = {
          horizontal = [{ label = "target", value = var.target_cpu_utilization }]
        }
      }
    },
    {
      type = "metric", x = 0, y = 12, width = 8, height = 6
      properties = {
        title  = "Healthy / unhealthy targets"
        region = var.region
        stat   = "Average"
        period = 60
        view   = "timeSeries"
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", aws_lb.main.arn_suffix, "TargetGroup", aws_lb_target_group.app.arn_suffix],
          [".", "UnHealthyHostCount", ".", ".", ".", ".", { color = "#d62728" }],
        ]
      }
    },
    {
      type = "metric", x = 8, y = 12, width = 8, height = 6
      properties = {
        title  = "RDS CPU and connections"
        region = var.region
        stat   = "Average"
        period = 60
        view   = "timeSeries"
        metrics = [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.main.identifier],
          [".", "DatabaseConnections", ".", ".", { yAxis = "right" }],
        ]
      }
    },
    {
      type = "metric", x = 16, y = 12, width = 8, height = 6
      properties = {
        title  = "WAF allowed vs blocked"
        region = var.region
        stat   = "Sum"
        period = 60
        view   = "timeSeries"
        metrics = [
          ["AWS/WAFV2", "AllowedRequests", "WebACL", aws_wafv2_web_acl.main.name, "Region", var.region, "Rule", "ALL"],
          [".", "BlockedRequests", ".", ".", ".", ".", ".", ".", { color = "#d62728" }],
        ]
      }
    },
    {
      type = "metric", x = 0, y = 18, width = 24, height = 6
      properties = {
        title  = "CloudFront requests and cache hit rate (us-east-1)"
        region = "us-east-1"
        period = 300
        view   = "timeSeries"
        metrics = [
          ["AWS/CloudFront", "Requests", "DistributionId", aws_cloudfront_distribution.main.id, "Region", "Global", { stat = "Sum" }],
          [".", "CacheHitRate", ".", ".", ".", ".", { stat = "Average", yAxis = "right" }],
        ]
      }
    },
  ]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name}-overview"
  dashboard_body = jsonencode({ widgets = local.dashboard_widgets })
}
