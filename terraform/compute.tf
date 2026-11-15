# -----------------------------------------------------------------------------
# Launch Template + Auto Scaling Group (web tier, private subnets, both AZs)
# -----------------------------------------------------------------------------

locals {
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    region                = var.region
    artifact_bucket       = aws_s3_bucket.artifacts.id
    artifact_key          = aws_s3_object.app.key
    db_host               = aws_db_instance.main.address
    db_name               = aws_db_instance.main.db_name
    db_secret_arn         = aws_db_instance.main.master_user_secret[0].secret_arn
    load_endpoint_enabled = var.enable_load_endpoint
    app_version           = var.app_version
  })
}

resource "aws_launch_template" "app" {
  name_prefix   = "${local.name}-"
  description   = "Ops Board web tier"
  image_id      = "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  instance_type = var.instance_type

  update_default_version = true
  user_data              = base64encode(local.user_data)

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  # IMDSv2 only: blocks the classic SSRF-to-credentials attack path.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # 1-minute metrics so target tracking reacts in minutes, not tens of minutes.
  monitoring {
    enabled = true
  }

  # "standard" credits (default): a burstable instance throttles instead of billing surplus credits.
  dynamic "credit_specification" {
    for_each = startswith(var.instance_type, "t") ? [1] : []
    content {
      cpu_credits = var.cpu_credits
    }
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.name}-web" }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${local.name}-web" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name_prefix         = "${local.name}-"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]

  # ELB health checks: an instance that fails /health is replaced, not just removed from rotation.
  health_check_type         = "ELB"
  health_check_grace_period = 300

  default_instance_warmup   = 120
  wait_for_capacity_timeout = "15m"
  min_elb_capacity          = var.asg_min_size

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # A new app bundle or user_data changes the launch template, which rolls instances one by one.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupTotalInstances",
  ]

  tag {
    key                 = "Name"
    value               = "${local.name}-web"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity] # the scaling policies own this value after creation
  }

  depends_on = [aws_lb_listener.http]
}

# ------------------------------------------------------------ scaling policies

# 1) Target tracking on CPU: the primary policy, handles both scale-out and scale-in.
resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${local.name}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = var.target_cpu_utilization
  }
}

# 2) Step scaling on user-visible latency: a safety net that adds capacity faster
#    when p90 response time is far above normal, in steps proportional to the breach.
resource "aws_autoscaling_policy" "latency_step_out" {
  name                      = "${local.name}-latency-step-out"
  autoscaling_group_name    = aws_autoscaling_group.app.name
  policy_type               = "StepScaling"
  adjustment_type           = "ChangeInCapacity"
  metric_aggregation_type   = "Maximum"
  estimated_instance_warmup = 120

  step_adjustment {
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 5
    scaling_adjustment          = 1
  }

  step_adjustment {
    metric_interval_lower_bound = 5
    scaling_adjustment          = 2
  }
}

resource "aws_cloudwatch_metric_alarm" "latency_high" {
  alarm_name          = "${local.name}-latency-p90-high"
  alarm_description   = "p90 target response time above 5 s: triggers step scaling out"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p90"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_autoscaling_policy.latency_step_out.arn, aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
