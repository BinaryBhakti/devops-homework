output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnets (one per AZ)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnets (one per AZ)"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.main.id
}

output "security_group_ids" {
  value = { web = aws_security_group.web.id, db = aws_security_group.db.id }
}

output "backup_bucket" {
  description = "Bucket for PostgreSQL backups"
  value       = aws_s3_bucket.backups.bucket
}

output "backup_role_arn" {
  value = aws_iam_role.backup.arn
}

output "tf_lock_table" {
  value = aws_dynamodb_table.tf_lock.name
}
