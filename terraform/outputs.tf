output "cloudfront_url" {
  description = "Primary entry point (HTTPS, cached static assets)."
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "alb_url" {
  description = "Direct ALB URL (HTTP). Route 53 aliases to this."
  value       = "http://${aws_lb.main.dns_name}"
}

output "custom_domain_url" {
  description = "Route 53 alias, if domain_name was set."
  value       = local.use_dns ? "http://${var.domain_name}" : null
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "rds_identifier" {
  description = "Use with: aws rds reboot-db-instance --force-failover"
  value       = aws_db_instance.main.identifier
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "db_secret_arn" {
  description = "RDS-managed Secrets Manager secret holding the master credentials."
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.id
}

output "session_manager_hint" {
  description = "How to open a shell on an instance without SSH or a bastion."
  value       = "aws ssm start-session --target <instance-id> --region ${var.region}"
}
