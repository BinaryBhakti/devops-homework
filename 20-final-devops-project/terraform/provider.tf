# The cloud side of IncidentDesk, aimed at LocalStack (an AWS API emulator on localhost:4566).
#
# Why not real AWS / EKS: the course reference provisions VPC + EKS. EKS is a LocalStack *Pro*
# service and this project runs on LocalStack 4.14.0 community, so the Kubernetes cluster is a
# local Minikube; Terraform still provisions everything around it that the community edition
# can emulate — network, security groups, backup storage, IAM, and the state-lock table.
#
# To target real AWS: delete access_key/secret_key, the skip_* flags, s3_use_path_style and
# the endpoints block, and supply credentials the normal way (env vars / SSO profile).
provider "aws" {
  region     = var.aws_region
  access_key = "test" # LocalStack accepts any credentials; these are its documented dummies
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    dynamodb = var.localstack_endpoint
    ec2      = var.localstack_endpoint
    iam      = var.localstack_endpoint
    s3       = var.localstack_endpoint
    sts      = var.localstack_endpoint
  }

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
      Session     = "21"
    }
  }
}

provider "random" {}
