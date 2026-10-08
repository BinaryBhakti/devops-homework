# Database backups bucket: private, versioned, encrypted, with a lifecycle that moves old
# backups to cheaper storage and eventually deletes them.

resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "backups" {
  bucket        = "${local.name}-db-backups-${random_id.suffix.hex}"
  force_destroy = true # lab only: lets `terraform destroy` remove a bucket that still holds objects
  tags          = { Name = "${local.name}-db-backups", Purpose = "postgres-backups" }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled" # an overwritten or deleted backup is recoverable
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3. (SSE-KMS needs KMS, which is not running in this LocalStack.)
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "tier-then-expire"
    status = "Enabled"
    filter {
      prefix = "postgres/"
    }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    expiration {
      days = var.backup_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  # the lifecycle API rejects rules on a bucket whose versioning is still being set up
  depends_on = [aws_s3_bucket_versioning.backups]
}

# State locking: `terraform` takes a lock in this table before every plan/apply, so two
# people (or two CI jobs) can never write the same state at once. See backend.tf.example.
resource "aws_dynamodb_table" "tf_lock" {
  name         = "${local.name}-tf-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = { Name = "${local.name}-tf-lock" }
}
