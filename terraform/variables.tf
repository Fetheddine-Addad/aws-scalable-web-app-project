variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for resource names and tags."
  type        = string
  default     = "opsboard"
}

variable "environment" {
  description = "Environment tag."
  type        = string
  default     = "demo"
}

# ------------------------------------------------------------------ network

variable "vpc_cidr" {
  description = "CIDR of the VPC. Subnets are carved out of it with cidrsubnet()."
  type        = string
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "true = one NAT Gateway (cheap, single point of failure). false = one per AZ (production)."
  type        = bool
  default     = true
}

variable "restrict_alb_to_cloudfront" {
  description = "Only allow CloudFront origin-facing IPs to reach the ALB. Breaks direct ALB access and the Route 53 alias demo, so default is false."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------ compute

variable "instance_type" {
  description = "EC2 instance type for the web tier."
  type        = string
  default     = "t3.micro"
}

variable "cpu_credits" {
  description = "T-family CPU credit mode. standard = throttles when credits run out (no surprise cost). unlimited = keeps bursting and bills surplus credits (about $0.05 per vCPU-hour), useful for a long scaling demo."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "unlimited"], var.cpu_credits)
    error_message = "cpu_credits must be standard or unlimited."
  }
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "target_cpu_utilization" {
  description = "Target average CPU (%) for the target tracking policy."
  type        = number
  default     = 50
}

variable "enable_load_endpoint" {
  description = "Expose POST /api/load (CPU burner) so you can demo scaling. Turn off for anything real."
  type        = bool
  default     = true
}

variable "app_version" {
  description = "Shown in the UI and /api/info. Bump it to see a rolling instance refresh."
  type        = string
  default     = "1.0.0"
}

# ----------------------------------------------------------------- database

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "db_allocated_storage" {
  description = "GiB."
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Synchronous standby in the second AZ with automatic failover (the point of this project)."
  type        = bool
  default     = true
}

# ----------------------------------------------------------------- security

variable "waf_rate_limit" {
  description = "Max requests per 5 minutes per source IP before WAF blocks."
  type        = number
  default     = 2000
}

# --------------------------------------------------------------- monitoring

variable "alarm_email" {
  description = "Email address for the SNS subscription. Leave empty to skip. You must confirm the subscription email."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------- dns (opt)

variable "domain_name" {
  description = "Optional FQDN (e.g. app.example.com) for the Route 53 alias to the ALB. Leave empty to skip Route 53."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Existing Route 53 hosted zone ID that contains domain_name. Required when domain_name is set."
  type        = string
  default     = ""

  validation {
    condition     = var.domain_name == "" || var.hosted_zone_id != ""
    error_message = "hosted_zone_id is required when domain_name is set."
  }
}
