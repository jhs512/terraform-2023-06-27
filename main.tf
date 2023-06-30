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

# Configure the AWS Provider
provider "aws" {
  region = var.region
}

resource "aws_vpc" "vpc_1" {
  cidr_block = "10.0.0.0/16"

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

resource "aws_internet_gateway" "igw_1" {
  vpc_id = aws_vpc.vpc_1.id

  tags = {
    Name = "${var.prefix}-igw-1"
  }
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

resource "aws_security_group" "sg_1" {
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

# Create IAM role for EC2
resource "aws_iam_role" "ec2_role_1" {
  name = "${var.prefix}-ec2-role-1"

  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
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

resource "aws_instance" "ec2_1" {
  ami                         = "ami-04b3f91ebd5bc4f6d"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.subnet_1.id
  vpc_security_group_ids      = [aws_security_group.sg_1.id]
  associate_public_ip_address = true

  # Assign IAM role to the instance
  iam_instance_profile = aws_iam_instance_profile.instance_profile_1.name

  tags = {
    Name = "${var.prefix}-ec2-1"
  }
}

resource "aws_s3_bucket" "bucket_jhs512_1" {
  bucket = "${var.prefix}-bucket-jhs512-1"

  tags = {
    Name = "${var.prefix}-bucket-jhs512-1"
  }
}

resource "aws_s3_bucket_policy" "bucket_jhs512_1_policy_1" {
  bucket = aws_s3_bucket.bucket_jhs512_1.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::dev-bucket-jhs512-1/*"
        }
    ]
}
EOF
}