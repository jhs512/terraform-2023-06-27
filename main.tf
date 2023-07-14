terraform {
  // 이 부분은 terraform cloud에서 설정한 workspace의 이름과 동일해야 함
  // 이 부분은 terraform login 후에 사용가능함
  cloud {
    organization = "og-1"

    workspaces {
      name = "ws-1"
    }
  }

  // 자바의 import 와 비슷함
  // aws 라이브러리 불러옴
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# AWS 설정 시작
provider "aws" {
  region = var.region
}
# AWS 설정 끝

# VPC 설정 시작
resource "aws_vpc" "vpc_1" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.prefix}-vpc-1"
  }
}

resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.vpc_1.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.prefix}-subnet-1"
  }
}

resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.vpc_1.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.prefix}-subnet-2"
  }
}

resource "aws_internet_gateway" "igw_1" {
  vpc_id = aws_vpc.vpc_1.id

  tags = {
    Name = "${var.prefix}-igw-1"
  }
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id          = aws_vpc.vpc_1.id
  service_name    = "com.amazonaws.${var.region}.s3"
  route_table_ids = [aws_route_table.rt_1.id]
}

resource "aws_route_table" "rt_1" {
  vpc_id = aws_vpc.vpc_1.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_1.id
  }

  tags = {
    Name = "${var.prefix}-rt-1"
  }
}

resource "aws_route_table_association" "association_1" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.rt_1.id
}

resource "aws_route_table_association" "association_2" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.rt_1.id
}

resource "aws_security_group" "sg_1" {
  name = "${var.prefix}-sg-1"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "all"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "all"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.vpc_1.id

  tags = {
    Name = "${var.prefix}-sg-1"
  }
}
# VPC 설정 끝

# ROUTE 53 설정 시작
resource "aws_route53_zone" "vpc_1_zone" {
  vpc {
    vpc_id = aws_vpc.vpc_1.id
  }
  name = "vpc-1.com"
}
# ROUTE 53 설정 끝

# EC2 설정 시작
resource "aws_iam_role" "ec2_role_1" {
  name = "${var.prefix}-ec2-role-1"

  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "",
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Effect": "Allow"
      }
    ]
  }
  EOF
}

# Attach AmazonS3FullAccess policy to the EC2 role
resource "aws_iam_role_policy_attachment" "s3_full_access" {
  role       = aws_iam_role.ec2_role_1.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Attach AmazonEC2RoleforSSM policy to the EC2 role
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role_1.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
}

resource "aws_iam_instance_profile" "instance_profile_1" {
  name = "${var.prefix}-instance-profile-1"
  role = aws_iam_role.ec2_role_1.name
}

variable "ec2_user_data" {
  description = "User data to be used on these instances"
  type        = string
  default     = <<-END_OF_FILE
#!/bin/bash
yum install docker -y
systemctl enable docker
systemctl start docker

cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

# Set SELinux in permissive mode (effectively disabling it)
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable --now kubelet

# Disable swap
swapoff -a
sed -i '/swap/s/^/#/' /etc/fstab

END_OF_FILE
}

resource "aws_instance" "ec2_1" {
  ami                         = "ami-04b3f91ebd5bc4f6d"
  instance_type               = "t2.large"
  subnet_id                   = aws_subnet.subnet_1.id
  vpc_security_group_ids      = [aws_security_group.sg_1.id]
  associate_public_ip_address = true

  # Assign IAM role to the instance
  iam_instance_profile = aws_iam_instance_profile.instance_profile_1.name

  tags = {
    Name = "${var.prefix}-ec2-1"
  }

  user_data = var.ec2_user_data
}

# ec2-1 에 private 도메인 연결
resource "aws_route53_record" "record_ec2-1_vpc-1_com" {
  zone_id = aws_route53_zone.vpc_1_zone.zone_id
  name    = "ec2-1.vpc-1.com"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.ec2_1.private_ip]
}

# ec2-1 에 public 도메인 연결
resource "aws_route53_record" "domain_1_ec2_1" {
  zone_id = var.domain_1_zone_id
  name    = "ec2-1.${var.domain_1}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.ec2_1.public_ip]
}

resource "aws_instance" "ec2_2" {
  ami                         = "ami-04b3f91ebd5bc4f6d"
  instance_type               = "t2.large"
  subnet_id                   = aws_subnet.subnet_1.id
  vpc_security_group_ids      = [aws_security_group.sg_1.id]
  associate_public_ip_address = true

  # Assign IAM role to the instance
  iam_instance_profile = aws_iam_instance_profile.instance_profile_1.name

  tags = {
    Name = "${var.prefix}-ec2-2"
  }

  user_data = var.ec2_user_data
}

# ec2-1 에 private 도메인 연결
resource "aws_route53_record" "record_ec2-2_vpc-1_com" {
  zone_id = aws_route53_zone.vpc_1_zone.zone_id
  name    = "ec2-2.vpc-1.com"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.ec2_2.private_ip]
}

# ec2-1 에 public 도메인 연결
resource "aws_route53_record" "domain_1_ec2_2" {
  zone_id = var.domain_1_zone_id
  name    = "ec2-2.${var.domain_1}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.ec2_2.public_ip]
}

resource "aws_instance" "ec2_3" {
  ami                         = "ami-04b3f91ebd5bc4f6d"
  instance_type               = "t2.large"
  subnet_id                   = aws_subnet.subnet_1.id
  vpc_security_group_ids      = [aws_security_group.sg_1.id]
  associate_public_ip_address = true

  # Assign IAM role to the instance
  iam_instance_profile = aws_iam_instance_profile.instance_profile_1.name

  tags = {
    Name = "${var.prefix}-ec2-3"
  }

  user_data = var.ec2_user_data
}

# ec2-1 에 private 도메인 연결
resource "aws_route53_record" "record_ec2-3_vpc-1_com" {
  zone_id = aws_route53_zone.vpc_1_zone.zone_id
  name    = "ec2-3.vpc-1.com"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.ec2_3.private_ip]
}

# ec2-1 에 public 도메인 연결
resource "aws_route53_record" "domain_1_ec2_3" {
  zone_id = var.domain_1_zone_id
  name    = "ec2-3.${var.domain_1}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.ec2_3.public_ip]
}
# EC2 설정 끝