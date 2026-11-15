# -----------------------------------------------------------------------------
# Security groups: ALB -> app -> database, nothing else.
# Rules are separate resources so the groups can reference each other without cycles.
# -----------------------------------------------------------------------------

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name_prefix = "${local.name}-alb-"
  description = "Public ALB"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-alb-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "app" {
  name_prefix = "${local.name}-app-"
  description = "Web tier instances (private subnets)"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-app-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "db" {
  name_prefix = "${local.name}-db-"
  description = "RDS PostgreSQL (data subnets)"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-db-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# ---- ALB: HTTP from the internet (or only from CloudFront when restricted)

resource "aws_vpc_security_group_ingress_rule" "alb_http_world" {
  count             = var.restrict_alb_to_cloudfront ? 0 : 1
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_cloudfront" {
  count             = var.restrict_alb_to_cloudfront ? 1 : 0
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from CloudFront origin-facing IPs only"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "ALB to app instances"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.app.id
}

# ---- App: only the ALB may connect in; outbound is HTTPS/HTTP + PostgreSQL

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "App port from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to SSM, Secrets Manager, S3, PyPI"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP for package repository redirects"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "PostgreSQL"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.db.id
}

# ---- Database: only the app tier

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from app tier"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.app.id
}
