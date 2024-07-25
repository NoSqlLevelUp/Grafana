terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1" 
}

resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = "true"
  enable_dns_support = "true"

  tags = {
    Name = "main_vpc"
  }
}

resource "aws_subnet" "subnet_1" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-1a"
  map_public_ip_on_launch = "true"

  tags = {
    Name = "Public subnet"
  }
}

resource "aws_subnet" "subnet_2" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-west-1b"

  tags = {
    Name = "Private subnet"
  }
}

resource "aws_db_subnet_group" "default_group" {
  name       = "main"
  subnet_ids = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]

  tags = {
    Name = "Subnet group"
  }
}

resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "main_igw"
  }
}

resource "aws_route_table" "main_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "main_rt"
  }
}

resource "aws_route_table_association" "main_rta" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.main_rt.id
}

resource "aws_iam_policy" "timestream_access_policy" {
  name        = "TimestreamAccessPolicy"
  description = "Policy for accessing Amazon Timestream"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "*",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "grafana_role" {
  name               = "GrafanaRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
           AWS = "*"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_role_policy" {
  role       = aws_iam_role.grafana_role.name
  policy_arn = aws_iam_policy.timestream_access_policy.arn
}

resource "aws_instance" "grafana" {
  ami           = "ami-05842291b9a0bd79f"  # Amazon Linux 2023 AMI
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet_1.id  
  vpc_security_group_ids = [aws_security_group.grafana_sg.id]
  iam_instance_profile  = aws_iam_instance_profile.grafana_instance_profile.name

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y https://dl.grafana.com/oss/release/grafana-9.4.7-1.x86_64.rpm
              sudo grafana-cli plugins install grafana-timestream-datasource
              sudo systemctl start grafana-server
              sudo systemctl enable grafana-server
              EOF

  tags = {
    Name = "Grafana-Server"
  }
}

resource "aws_security_group" "grafana_sg" {
  name        = "grafana-security-group"
  description = "Security group for Grafana instance"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_eip" "grafana_eip" {
  instance = aws_instance.grafana.id
  domain   = "vpc"
}

resource "aws_eip_association" "grafana_eip_assoc" {
  instance_id   = aws_instance.grafana.id
  allocation_id = aws_eip.grafana_eip.id
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "grafana_instance_profile" {
  name = "GrafanaInstanceProfile"
  role = aws_iam_role.grafana_role.name
}
