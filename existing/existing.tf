terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.68.0"
    }
  }
}

provider "aws" {
  access_key = "test"
  secret_key = "test"
  region     = "us-east-1"
  profile    = "localstack"

  endpoints {
    ec2      = "http://localhost:4566"
    s3       = "http://s3.localhost.localstack.cloud:4566"
    dynamodb = "http://localhost:4566"
    # s3  = "http://localhost:4566"
    route53         = "http://localhost:4566"
    route53resolver = "http://localhost:4566"
  }
}

resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "my_vpc"
  }
}

resource "aws_subnet" "subnet_a" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "subnet-a"
  }
}

resource "aws_subnet" "subnet_b" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "subnet-b"
  }
}

resource "aws_security_group" "allow_mariadb" {
  name        = "allow_mariadb"
  description = "Allows connections to DB from EC2 instances"
  vpc_id      = aws_vpc.my_vpc.id
  tags = {
    Name = "allow_mariadb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_inbound_mariadb" {
  security_group_id = aws_security_group.allow_mariadb.id

  cidr_ipv4   = aws_vpc.my_vpc.cidr_block
  from_port   = 3306
  ip_protocol = "tcp"
  to_port     = 3306
}

resource "aws_vpc_security_group_egress_rule" "allow_outbound_mariadb" {
  security_group_id = aws_security_group.allow_mariadb.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 0
  ip_protocol = "-1"
  to_port     = 0
}


resource "aws_route53_zone" "public" {
  name = "looselytyped"
}
