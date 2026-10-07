locals {
  common_tags = {
    Name        = var.bucket_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "Session18"
  }
}

resource "aws_s3_bucket" "demo" {
  bucket        = var.bucket_name
  force_destroy = true # lets `terraform destroy` remove a non-empty, versioned bucket
  tags          = local.common_tags
}

resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "demo" {
  bucket = aws_s3_bucket.demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_days
    }
  }

  # A lifecycle rule on noncurrent versions only means something once versioning is on.
  depends_on = [aws_s3_bucket_versioning.demo]
}

resource "aws_s3_object" "readme" {
  bucket       = aws_s3_bucket.demo.id
  key          = "docs/hello.txt"
  content      = "Hello from Terraform - Session 18 (${var.environment})\n"
  content_type = "text/plain"

  # Upload only after encryption is configured, so the object is written encrypted.
  depends_on = [aws_s3_bucket_server_side_encryption_configuration.demo]
}
