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

resource "aws_s3_bucket" "bucket_1" {
  bucket = "${var.prefix}-bucket-${var.nickname}-1"

  tags = {
    Name = "${var.prefix}-bucket-${var.nickname}-1"
  }
}

data "aws_iam_policy_document" "bucket_1_policy_1_statement" {
  statement {
    sid    = "PublicReadGetObject"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.bucket_1.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "bucket_1_policy_1" {
  bucket = aws_s3_bucket.bucket_1.id

  policy = data.aws_iam_policy_document.bucket_1_policy_1_statement.json

  depends_on = [aws_s3_bucket_public_access_block.bucket_1_public_access_block_1]
}

resource "aws_s3_bucket_public_access_block" "bucket_1_public_access_block_1" {
  bucket = aws_s3_bucket.bucket_1.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_route53_zone" "vpc_1_zone" {
  vpc {
    vpc_id = aws_vpc.vpc_1.id
  }

  name = "vpc-1.com"
}

resource "aws_route53_record" "record_ec2-1_vpc-1_com" {
  zone_id = aws_route53_zone.vpc_1_zone.zone_id
  name    = "ec2-1.vpc-1.com"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.ec2_1.private_ip]
}

resource "aws_s3_bucket" "bucket_2" {
  bucket = "${var.prefix}-bucket-${var.nickname}-2"

  tags = {
    Name = "${var.prefix}-bucket-${var.nickname}-2"
  }
}

data "template_file" "template_file_1" {
  template = "Hello"
}

resource "aws_s3_object" "object" {
  bucket       = aws_s3_bucket.bucket_2.id
  key          = "public/index.html"
  content      = data.template_file.template_file_1.rendered
  content_type = "text/html"

  etag       = md5(data.template_file.template_file_1.rendered)
  depends_on = [aws_s3_bucket.bucket_2]
}

resource "aws_cloudfront_origin_access_control" "oac_1" {
  name                              = "oac-1"
  description                       = ""
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cd_1" {
  enabled = true

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "origin_id_1"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  origin {
    domain_name              = aws_s3_bucket.bucket_2.bucket_regional_domain_name
    origin_path              = "/public"
    origin_id                = "origin_id_1"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac_1.id
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "bucket_2_policy_1_statement" {
  statement {
    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.bucket_2.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cd_1.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "bucket_2_policy_1" {
  bucket = aws_s3_bucket.bucket_2.id

  policy = data.aws_iam_policy_document.bucket_2_policy_1_statement.json
}
