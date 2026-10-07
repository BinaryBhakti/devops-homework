# The AWS provider, aimed at LocalStack. See ../README.md for why each flag exists.
# To target real AWS: delete access_key/secret_key, the skip_* flags,
# s3_use_path_style and the endpoints block.
provider "aws" {
  region     = var.aws_region
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    ec2 = var.localstack_endpoint
    iam = var.localstack_endpoint
    s3  = var.localstack_endpoint
    sts = var.localstack_endpoint
  }

  # Tags stamped on every resource this provider creates.
  default_tags {
    tags = {
      Project   = var.project
      Session   = "19"
      ManagedBy = "Terraform"
    }
  }
}

provider "random" {}
