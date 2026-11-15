# -----------------------------------------------------------------------------
# Route 53 (optional): alias record to the ALB plus an HTTP health check.
# Only created when var.domain_name is set. Needs an existing hosted zone.
# -----------------------------------------------------------------------------

locals {
  use_dns = var.domain_name != ""
}

resource "aws_route53_record" "app" {
  count   = local.use_dns ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_health_check" "app" {
  count             = local.use_dns ? 1 : 0
  fqdn              = aws_lb.main.dns_name
  type              = "HTTP"
  port              = 80
  resource_path     = "/health"
  request_interval  = 30
  failure_threshold = 3

  tags = { Name = "${local.name}-alb-health" }
}
