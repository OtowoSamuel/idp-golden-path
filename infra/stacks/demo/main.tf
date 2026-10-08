# Minimal demo VPC + EKS cluster, entirely in Terraform.
# Public-only subnets keep the demo cheap (no NAT gateway); production
# would add private node subnets + NAT — same module, different subnet list.
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "idp-golden-path"
      ManagedBy = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 4, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.cluster_name}-public-${data.aws_availability_zones.available.names[count.index]}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.cluster_name}-public"
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  endpoint_public_access = true
  # The caller (platform engineer) gets an EKS access entry automatically —
  # no aws-auth ConfigMap editing.
  enable_cluster_creator_admin_permissions = true

  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.public[*].id

  eks_managed_node_groups = {
    workers = {
      instance_types = var.node_instance_types
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = 2
      max_size       = 3
      desired_size   = var.node_desired_size
    }
  }
}
