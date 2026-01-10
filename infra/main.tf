terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket  = "kube-montecarlo-jobs"
    key     = "terraform/terraform.tfstate"
    region  = "us-west-2"
    encrypt = true
    # dynamodb_table = "kube-montecarlo-jobs" # optional later
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}



provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "kube-montecarlo-jobs"
      ManagedBy = "terraform"
    }
  }  
}

# If you don't want to pass AZ, you can auto-pick the first AZ in the region.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "demo"

  az = var.az != "" ? var.az : data.aws_availability_zones.available.names[0]

  vpc_cidr    = "10.0.0.0/16"
  subnet_cidr = "10.0.1.0/24"
}

resource "aws_vpc" "this" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.subnet_cidr
  availability_zone       = local.az
  map_public_ip_on_launch = true

  tags = { Name = "${local.name}-public-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${local.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name        = "${local.name}-sg"
  description = "Allow HTTP inbound"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Optional: allow HTTPS too
  # ingress {
  #   description = "HTTPS"
  #   from_port   = 443
  #   to_port     = 443
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg" }
}

# Latest Ubuntu 22.04 LTS (Jammy) AMI from Canonical
data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  associate_public_ip_address = true
  iam_instance_profile = "ec2-kube-montecarlo-jobs"

  tags = { Name = "${local.name}-ec2" }
}

output "public_ip" {
  value = aws_instance.this.public_ip
}

output "az_used" {
  value = local.az
}
