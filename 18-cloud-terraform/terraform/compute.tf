# Data source: read-only lookup, nothing is created.
data "aws_ami" "linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }
}

# --- IAM: let the instance read the site bucket, and nothing else ---
resource "aws_iam_role" "web" {
  name = "${var.project}-web-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "read_site" {
  name = "read-site-bucket"
  role = aws_iam_role.web.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.site.arn}/site/*" # implicit dependency on the bucket
    }]
  })
}

resource "aws_iam_instance_profile" "web" {
  name = "${var.project}-web-profile"
  role = aws_iam_role.web.name
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name

  user_data = <<-EOT
    #!/bin/bash
    yum install -y httpd
    aws s3 cp s3://${aws_s3_bucket.site.id}/${aws_s3_object.index.key} /var/www/html/index.html
    systemctl enable --now httpd
  EOT

  tags = { Name = "${var.project}-web" }

  # Explicit dependency. Nothing above references the gateway or the route table, so
  # Terraform would happily boot the instance in parallel with them. But user_data
  # needs the internet (yum) the moment the instance starts, and the role policy must
  # exist before `aws s3 cp` runs. depends_on encodes ordering Terraform cannot infer.
  depends_on = [
    aws_route_table_association.public,
    aws_iam_role_policy.read_site,
  ]
}
