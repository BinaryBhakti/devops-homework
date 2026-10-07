output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "Address space of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet."
  value       = aws_subnet.public.id
}

output "internet_gateway_id" {
  description = "ID of the internet gateway."
  value       = aws_internet_gateway.main.id
}

output "security_group_id" {
  description = "ID of the web security group."
  value       = aws_security_group.web.id
}

output "ami_id" {
  description = "AMI the data source resolved."
  value       = data.aws_ami.linux.id
}

output "instance_id" {
  description = "ID of the EC2 instance."
  value       = aws_instance.web.id
}

output "instance_private_ip" {
  description = "Private address inside the subnet."
  value       = aws_instance.web.private_ip
}

output "instance_public_ip" {
  description = "Public address (assigned because the subnet maps public IPs on launch)."
  value       = aws_instance.web.public_ip
}

output "site_bucket" {
  description = "S3 bucket holding the site content."
  value       = aws_s3_bucket.site.id
}
