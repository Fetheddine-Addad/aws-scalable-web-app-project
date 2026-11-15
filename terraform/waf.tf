# -----------------------------------------------------------------------------
# AWS WAF (regional) attached to the ALB.
# AWS Managed Rules cover the OWASP Top 10 classes this app is exposed to:
#   CommonRuleSet     XSS, LFI/RFI, bad bots, oversized bodies  (A03, A05, A08)
#   SQLiRuleSet       SQL injection                              (A03)
#   KnownBadInputs    Log4Shell and similar exploit patterns     (A06)
#   IpReputation      Amazon threat-intel IP list                (A01, A07)
#   rate limit        Brute force and request floods per IP      (A04, A07)
# -----------------------------------------------------------------------------

locals {
  waf_managed_rule_groups = {
    "AWSManagedRulesAmazonIpReputationList" = 10
    "AWSManagedRulesCommonRuleSet"          = 20
    "AWSManagedRulesKnownBadInputsRuleSet"  = 30
    "AWSManagedRulesSQLiRuleSet"            = 40
  }
}

resource "aws_wafv2_web_acl" "main" {
  name        = "${local.name}-web-acl"
  description = "OWASP-oriented protection for the ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = local.waf_managed_rule_groups

    content {
      name     = rule.key
      priority = rule.value

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  rule {
    name     = "RateLimitPerIp"
    priority = 50

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIp"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${local.name}-web-acl" }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
