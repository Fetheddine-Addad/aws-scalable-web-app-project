# -----------------------------------------------------------------------------
# Application Load Balancer: Layer 7 routing and health checks
# -----------------------------------------------------------------------------

resource "aws_lb" "main" {
  name_prefix        = "ob-"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  drop_invalid_header_fields = true
  idle_timeout               = 60
  enable_deletion_protection = false

  tags = { Name = "${local.name}-alb" }
}

resource "aws_lb_target_group" "app" {
  name_prefix          = "ob-"
  port                 = 8000
  protocol             = "HTTP"
  vpc_id               = aws_vpc.main.id
  target_type          = "instance"
  deregistration_delay = 30

  # Shallow check on purpose: it must keep passing during an RDS failover.
  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${local.name}-tg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Layer 7 rule 1: paths that must never be reachable from the internet get a 403 at the ALB,
# before a request ever reaches an instance.
resource "aws_lb_listener_rule" "block_internal" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"forbidden\"}"
      status_code  = "403"
    }
  }

  condition {
    path_pattern {
      values = ["/internal/*", "/admin/*"]
    }
  }
}

# Layer 7 rule 2: API traffic is routed explicitly. This is where a second target group
# (for example a separate API fleet) would be attached without touching the web tier.
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}
