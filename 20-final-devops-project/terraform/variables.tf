variable "aws_region" {
  description = "AWS region (LocalStack honours it for ARNs and AZ names)."
  type        = string
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  description = "LocalStack edge endpoint."
  type        = string
  default     = "http://localhost:4566"
}

variable "project" {
  description = "Name prefix for every resource."
  type        = string
  default     = "incidentdesk"
}

variable "environment" {
  description = "dev | staging | prod"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "VPC address space."
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "Two availability zones: one public + one private subnet in each."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "backup_retention_days" {
  description = "Days before database backups are deleted."
  type        = number
  default     = 90
}
