output "bucket_name" {
  description = "Name of the S3 bucket."
  value       = aws_s3_bucket.demo.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = aws_s3_bucket.demo.arn
}

output "bucket_region" {
  description = "Region the bucket lives in."
  value       = aws_s3_bucket.demo.region
}

output "versioning_status" {
  description = "Versioning state of the bucket."
  value       = aws_s3_bucket_versioning.demo.versioning_configuration[0].status
}

output "object_url" {
  description = "LocalStack path-style URL of the uploaded object."
  value       = "${var.localstack_endpoint}/${aws_s3_bucket.demo.id}/${aws_s3_object.readme.key}"
}

output "object_version_id" {
  description = "Version ID S3 assigned to the uploaded object."
  value       = aws_s3_object.readme.version_id
}
