output "sns_topic_arn" {
  description = "ARN of the SNS topic receiving all cost alerts"
  value       = aws_sns_topic.cost_alerts.arn
}

output "budget_name" {
  description = "Name of the AWS Budget created"
  value       = aws_budgets_budget.monthly_cost.name
}

output "lambda_function_name" {
  description = "Name of the idle instance checker Lambda function"
  value       = aws_lambda_function.stop_idle_instances.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.stop_idle_instances.arn
}

output "cloudwatch_dashboard_url" {
  description = "Direct URL to the CloudWatch cost dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.cost_optimizer.dashboard_name}"
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket with lifecycle policies"
  value       = aws_s3_bucket.cost_optimizer_assets.bucket
}

output "tagging_policy_arn" {
  description = "ARN of the IAM tagging enforcement policy"
  value       = aws_iam_policy.require_tags.arn
}

output "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  value       = "$${var.monthly_budget_limit}"
}

output "alert_email" {
  description = "Email address receiving all cost alerts"
  value       = var.alert_email
}

output "invoke_lambda_command" {
  description = "PowerShell-safe AWS CLI command to manually invoke the Lambda function and print the response"
  value       = "aws lambda invoke --function-name ${aws_lambda_function.stop_idle_instances.function_name} --region ${var.aws_region} response.json; Get-Content response.json"
}

output "destroy_command" {
  description = "Command to destroy all resources when done"
  value       = "terraform destroy --auto-approve"
}
