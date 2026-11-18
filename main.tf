terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}


resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 12
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 5
}

resource "aws_iam_group" "developers" {
  name = "Developers"
}
resource "aws_iam_user" "developer" {
  for_each = var.developers
  name     = each.value
  tags     = local.tags
}

resource "aws_iam_group_membership" "developers" {
  name  = "developers-membership"
  group = aws_iam_group.developers.name
  users = [for u in aws_iam_user.developer : u.name]
}

resource "aws_s3_bucket" "dev_data" {
  bucket = "${var.project_name}-dev-data-${local.account_id}"
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "dev_data" {
  bucket                  = aws_s3_bucket.dev_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_iam_policy" "ec2" {
  name        = "Developer-EC2-Policy"
  description = "Developers can describe, start and stop EC2 instances"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:DescribeInstances", "ec2:StartInstances", "ec2:StopInstances"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_policy" "s3" {
  name        = "Developer-S3-Policy"
  description = "Developers can list, read and write objects in the dev bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.dev_data.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.dev_data.arn}/*"
      }
    ]
  })
}

resource "aws_iam_policy" "ebs" {
  name        = "Developer-EBS-Policy"
  description = "Developers can manage EBS volumes (EBS uses ec2 actions)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeVolumes",
        "ec2:CreateVolume",
        "ec2:AttachVolume",
        "ec2:DetachVolume"
      ]
      Resource = "*"
    }]
  })
}
resource "aws_iam_policy" "enforce_mfa" {
  name        = "Developer-Enforce-MFA"
  description = "Users can manage their own MFA; all else is denied until MFA is used"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowManageOwnMFA"
        Effect = "Allow"
        Action = [
          "iam:ListMFADevices",
          "iam:CreateVirtualMFADevice",
          "iam:EnableMFADevice",
          "iam:ResyncMFADevice",
          "iam:GetUser",
          "iam:ChangePassword"
        ]
        Resource = [
          "arn:aws:iam::${local.account_id}:user/$${aws:username}",
          "arn:aws:iam::${local.account_id}:mfa/$${aws:username}"
        ]
      },
      {
        Sid      = "AllowListVirtualMFA"
        Effect   = "Allow"
        Action   = ["iam:ListVirtualMFADevices"]
        Resource = "*"
      },
      {
        Sid    = "DenyAllExceptMFASetupWithoutMFA"
        Effect = "Deny"
        NotAction = [
          "iam:CreateVirtualMFADevice",
          "iam:EnableMFADevice",
          "iam:ListMFADevices",
          "iam:ListVirtualMFADevices",
          "iam:ResyncMFADevice",
          "iam:GetUser",
          "iam:ChangePassword",
          "sts:GetSessionToken"
        ]
        Resource = "*"
        Condition = {
          BoolIfExists = { "aws:MultiFactorAuthPresent" = "false" }
        }
      }
    ]
  })
}
resource "aws_iam_group_policy_attachment" "ec2" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.ec2.arn
}

resource "aws_iam_group_policy_attachment" "s3" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.s3.arn
}

resource "aws_iam_group_policy_attachment" "ebs" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.ebs.arn
}

resource "aws_iam_group_policy_attachment" "mfa" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.enforce_mfa.arn
}

resource "aws_s3_bucket" "trail_logs" {
  bucket        = "${var.project_name}-cloudtrail-${local.account_id}"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "trail_logs" {
  bucket                  = aws_s3_bucket.trail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "trail_logs" {
  bucket = aws_s3_bucket.trail_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail_logs.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail_logs.arn}/AWSLogs/${local.account_id}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "trail" {
  name              = "/aws/cloudtrail/${var.project_name}"
  retention_in_days = 90
  tags              = local.tags
}

resource "aws_iam_role" "trail_to_cw" {
  name = "${var.project_name}-cloudtrail-to-cw"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "trail_to_cw" {
  name = "write-to-cloudwatch-logs"
  role = aws_iam_role.trail_to_cw.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.trail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_to_cw.arn
  tags                          = local.tags

  depends_on = [aws_s3_bucket_policy.trail_logs, aws_iam_role_policy.trail_to_cw]
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-security-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_log_metric_filter" "unauthorized" {
  name           = "UnauthorizedApiCalls"
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"

  metric_transformation {
    name      = "UnauthorizedApiCallCount"
    namespace = "DevRBAC"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "unauthorized" {
  alarm_name          = "${var.project_name}-unauthorized-api-calls"
  alarm_description   = "Fires when developers make denied API calls"
  namespace           = "DevRBAC"
  metric_name         = "UnauthorizedApiCallCount"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  depends_on = [aws_cloudwatch_log_metric_filter.unauthorized]
}
