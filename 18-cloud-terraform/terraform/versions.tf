terraform {
  required_version = ">= 1.6.0"

  # Two providers from the registry: aws for the infrastructure,
  # random for a collision-proof S3 bucket suffix.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
