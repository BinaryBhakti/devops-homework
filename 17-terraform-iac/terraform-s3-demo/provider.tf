terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Points the AWS provider at LocalStack instead of real AWS.
# Everything below the region line exists only because LocalStack is not AWS:
#   - fake static credentials (LocalStack accepts any key)
#   - skip the STS / account-ID / region lookups real AWS would answer
#   - path-style S3 URLs, because <bucket>.localhost does not resolve
#   - every service endpoint redirected to the LocalStack edge port
# Remove the endpoints block and the skip_* flags and this file targets real AWS.
provider "aws" {
  region     = var.aws_region
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = var.localstack_endpoint
    sts = var.localstack_endpoint
    iam = var.localstack_endpoint
  }
}
