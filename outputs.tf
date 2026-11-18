output "group_name" {
  value = aws_iam_group.developers.name
}

output "developer_users" {
  value = [for u in aws_iam_user.developer : u.name]
}

output "attached_policies" {
  value = [
    aws_iam_policy.ec2.name,
    aws_iam_policy.s3.name,
    aws_iam_policy.ebs.name,
    aws_iam_policy.enforce_mfa.name
  ]
}

output "cloudtrail_name" {
  value = aws_cloudtrail.main.name
}

output "dev_bucket" {
  value = aws_s3_bucket.dev_data.id
}
