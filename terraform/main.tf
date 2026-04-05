provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Owner       = var.owner
      Project     = var.project_name
      CostCenter  = var.cost_center
      ManagedBy   = "terraform"
    }
  }
}

# -------------------------------------------------------
# DATA SOURCES
# -------------------------------------------------------
data "aws_caller_identity" "current" {}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/stop_idle_instances.py"
  output_path = "${path.module}/../lambda/stop_idle_instances.zip"
}

# -------------------------------------------------------
# SNS TOPIC — receives all cost alerts and Lambda reports
# -------------------------------------------------------
resource "aws_sns_topic" "cost_alerts" {
  name = "${var.project_name}-cost-alerts"

  tags = {
    Name = "${var.project_name}-cost-alerts"
  }
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# -------------------------------------------------------
# AWS BUDGETS — $20/month with alerts at 50%, 80%, 100%
# -------------------------------------------------------
resource "aws_budgets_budget" "monthly_cost" {
  name         = "${var.project_name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts.arn]
  }
}

# -------------------------------------------------------
# IAM ROLE FOR LAMBDA
# -------------------------------------------------------
resource "aws_iam_role" "lambda_cost_optimizer" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_cost_optimizer_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_cost_optimizer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2ReadAndStop"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:StopInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchMetricsRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData"
        ]
        Resource = "*"
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.cost_alerts.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid    = "CostExplorerRead"
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetCostForecast",
          "ce:GetReservationUtilization",
          "ce:GetSavingsPlansUtilization"
        ]
        Resource = "*"
      }
    ]
  })
}

# -------------------------------------------------------
# LAMBDA FUNCTION — stops idle EC2 instances
# -------------------------------------------------------
resource "aws_lambda_function" "stop_idle_instances" {
  function_name    = "${var.project_name}-stop-idle-instances"
  role             = aws_iam_role.lambda_cost_optimizer.arn
  handler          = "stop_idle_instances.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 300
  memory_size      = 256

  environment {
    variables = {
      SNS_TOPIC_ARN        = aws_sns_topic.cost_alerts.arn
      CPU_IDLE_THRESHOLD   = tostring(var.cpu_idle_threshold_percent)
      IDLE_HOURS_THRESHOLD = tostring(var.idle_instance_threshold_hours)
      AWS_ACCOUNT_ID       = data.aws_caller_identity.current.account_id
      ENVIRONMENT          = var.environment
    }
  }

  tags = {
    Name = "${var.project_name}-stop-idle-instances"
  }
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.stop_idle_instances.function_name}"
  retention_in_days = 14
}

# -------------------------------------------------------
# EVENTBRIDGE RULE — triggers Lambda every 24 hours
# -------------------------------------------------------
resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  name                = "${var.project_name}-idle-check-schedule"
  description         = "Triggers idle instance checker Lambda every 24 hours"
  schedule_expression = var.lambda_schedule

  tags = {
    Name = "${var.project_name}-idle-check-schedule"
  }
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.lambda_schedule.name
  target_id = "StopIdleInstances"
  arn       = aws_lambda_function.stop_idle_instances.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_idle_instances.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_schedule.arn
}

# -------------------------------------------------------
# S3 BUCKET — with combined lifecycle policy
# -------------------------------------------------------
resource "aws_s3_bucket" "cost_optimizer_assets" {
  bucket = "${var.project_name}-assets-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-assets"
  }
}

resource "aws_s3_bucket_versioning" "assets_versioning" {
  bucket = aws_s3_bucket.cost_optimizer_assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets_encryption" {
  bucket = aws_s3_bucket.cost_optimizer_assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets_public_access" {
  bucket                  = aws_s3_bucket.cost_optimizer_assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Combined S3 lifecycle policy
resource "aws_s3_bucket_lifecycle_configuration" "assets_lifecycle" {
  bucket = aws_s3_bucket.cost_optimizer_assets.id

  # Rule 1 — transition current objects to Standard-IA then Glacier
  rule {
    id     = "transition-to-cheaper-storage"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }

  # Rule 2 — clean up incomplete multipart uploads after 7 days
  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Rule 3 — expire old versions after 90 days
  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.assets_versioning]
}

# -------------------------------------------------------
# CLOUDWATCH DASHBOARD — unified cost visibility
# -------------------------------------------------------
resource "aws_cloudwatch_dashboard" "cost_optimizer" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "EC2 CPU Utilization — All Instances"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/EC2", "CPUUtilization",
              { stat = "Average", period = 3600, label = "Average CPU %" }
            ]
          ]
          period = 3600
          region = var.aws_region
          yAxis = {
            left = { min = 0, max = 100 }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Lambda Invocations — Idle Instance Checker"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/Lambda",
              "Invocations",
              "FunctionName",
              "${var.project_name}-stop-idle-instances",
              { stat = "Sum", period = 86400, label = "Daily Invocations" }
            ],
            ["AWS/Lambda",
              "Errors",
              "FunctionName",
              "${var.project_name}-stop-idle-instances",
              { stat = "Sum", period = 86400, label = "Errors" }
            ]
          ]
          period = 86400
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Lambda Duration — Cost Optimizer"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/Lambda",
              "Duration",
              "FunctionName",
              "${var.project_name}-stop-idle-instances",
              { stat = "Average", period = 86400, label = "Avg Duration (ms)" }
            ]
          ]
          period = 86400
          region = var.aws_region
        }
      },
      {
        type   = "alarm"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title = "Active Cost Alarms"
          alarms = [
            "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${var.project_name}-lambda-errors"
          ]
        }
      }
    ]
  })
}

# -------------------------------------------------------
# CLOUDWATCH ALARM — Lambda error rate alert
# -------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 86400
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Lambda cost optimizer function returned errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.stop_idle_instances.function_name
  }

  alarm_actions = [aws_sns_topic.cost_alerts.arn]
  ok_actions    = [aws_sns_topic.cost_alerts.arn]

  tags = {
    Name = "${var.project_name}-lambda-errors"
  }
}

# -------------------------------------------------------
# IAM TAGGING ENFORCEMENT POLICY
# -------------------------------------------------------
resource "aws_iam_policy" "require_tags" {
  name        = "${var.project_name}-require-tags-policy"
  description = "Denies resource creation without required tags: Environment, Owner, Project, CostCenter"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyEC2WithoutRequiredTags"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot"
        ]
        Resource = [
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ec2:*:*:volume/*"
        ]
        Condition = {
          "Null" = {
            "aws:RequestTag/Environment" = "true"
            "aws:RequestTag/Owner"       = "true"
            "aws:RequestTag/Project"     = "true"
            "aws:RequestTag/CostCenter"  = "true"
          }
        }
      },
      {
        Sid      = "DenyS3WithoutRequiredTags"
        Effect   = "Deny"
        Action   = ["s3:CreateBucket"]
        Resource = "*"
        Condition = {
          "Null" = {
            "aws:RequestTag/Environment" = "true"
            "aws:RequestTag/Owner"       = "true"
            "aws:RequestTag/Project"     = "true"
            "aws:RequestTag/CostCenter"  = "true"
          }
        }
      },
      {
        Sid    = "DenyRDSWithoutRequiredTags"
        Effect = "Deny"
        Action = [
          "rds:CreateDBInstance",
          "rds:CreateDBCluster"
        ]
        Resource = "*"
        Condition = {
          "Null" = {
            "aws:RequestTag/Environment" = "true"
            "aws:RequestTag/Owner"       = "true"
            "aws:RequestTag/Project"     = "true"
            "aws:RequestTag/CostCenter"  = "true"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-require-tags-policy"
  }
}