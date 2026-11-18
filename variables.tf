variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used for naming resources"
  type        = string
  default     = "dev-onboarding"
}

variable "developers" {
  description = "IAM user names of all developers"
  type        = set(string)
  default     = ["developer001", "developer002", "developer003", "developer004","developer005"]
}

variable "alert_email" {
  description = "Email that receives CloudWatch security alerts"
  type        = string
  default     = "admin@example.com"
}
