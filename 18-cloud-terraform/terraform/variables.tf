variable "aws_region" {
  type        = string
  description = "Region to build in."
  default     = "ap-south-1"
}

variable "localstack_endpoint" {
  type        = string
  description = "LocalStack edge URL that stands in for the AWS APIs."
  default     = "http://localhost:4566"
}

variable "project" {
  type        = string
  description = "Name prefix for every resource."
  default     = "session19"
}

variable "vpc_cidr" {
  type        = string
  description = "Address space of the VPC."
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, e.g. 10.20.0.0/16."
  }
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR of the public subnet; must sit inside vpc_cidr."
  default     = "10.20.1.0/24"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance size."
  default     = "t3.micro"
}

variable "ami_name_filter" {
  type        = string
  description = "Name pattern used to look up the AMI. The default matches an Amazon Linux image LocalStack ships."
  default     = "amzn-ami-hvm-*-x86_64-gp2"
}

variable "admin_cidr" {
  type        = string
  description = "The only source address allowed to SSH in."
  default     = "203.0.113.10/32"
}
