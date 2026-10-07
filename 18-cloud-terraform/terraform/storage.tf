# S3 names are global, so a random suffix keeps re-runs and classmates from colliding.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "site" {
  bucket        = "${var.project}-site-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = { Name = "${var.project}-site" }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The page the EC2 instance pulls down and serves at boot.
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.site.id
  key          = "site/index.html"
  content      = "<h1>Hello from ${var.project} - provisioned by Terraform</h1>\n"
  content_type = "text/html"
}
