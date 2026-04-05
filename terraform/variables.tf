variable "aws_region" {
  description = "AWS region where all resources are deployed"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "cost-optimizer"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "owner" {
  description = "Owner tag value applied to all resources"
  type        = string
  default     = "emmanuel-ubani"
}

variable "cost_center" {
  description = "Cost center tag value applied to all resources"
  type        = string
  default     = "devops-engineering"
}

variable "alert_email" {
  description = "Email address that receives all cost alerts and Lambda notifications"
  type        = string
  default     = "devops-alerts@gmail.com"
}

variable "monthly_budget_limit" {
  description = "Monthly AWS spend budget limit in USD"
  type        = string
  default     = "20"
}

variable "idle_instance_threshold_hours" {
  description = "Number of hours of CPU inactivity before instance is considered idle"
  type        = number
  default     = 24
}

variable "cpu_idle_threshold_percent" {
  description = "CPU utilization percentage below which an instance is considered idle"
  type        = number
  default     = 5
}

variable "lambda_schedule" {
  description = "EventBridge cron schedule for Lambda idle instance checker"
  type        = string
  default     = "rate(24 hours)"
}

variable "s3_lifecycle_bucket_name" {
  description = "Name of the S3 bucket to apply lifecycle policies to"
  type        = string
  default     = "cost-optimizer-assets"
}