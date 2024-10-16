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

locals {
  data_sources = yamldecode(file("infra.yaml")).data_sources
  # this will read the yaml file and parse it into
  resources = yamldecode(file("infra.yaml")).resources
}

# aws --profile localstack ec2 describe-vpcs | jq
data "aws_vpc" "vpcs" {
  for_each = local.data_sources.vpcs
  tags = {
    Name = each.value.name
  }
}

# aws --profile localstack ec2 describe-images --owners "591542846629"
data "aws_subnet" "subnets" {
  for_each = local.data_sources.subnets
  vpc_id   = lookup(data.aws_vpc.vpcs, each.value.vpc).id

  tags = {
    Name = each.value.name
  }
}

# aws --profile localstack route53 create-hosted-zone --name example.com --caller-reference r1 | jq
data "aws_route53_zone" "route53_zones" {
  for_each     = local.data_sources.route53_zones
  name         = each.value.name
  private_zone = each.value.private
}

data "aws_ami" "amis" {
  for_each    = local.data_sources.amis
  most_recent = true

  dynamic "filter" {
    for_each = try(each.value.filters, {})
    content {
      name   = filter.key
      values = filter.value
    }
  }

  owners = each.value.owners
}

data "aws_security_group" "security_groups" {
  for_each = local.data_sources.security_groups
  tags = {
    Name = each.value.name
  }
}

# aws --profile localstack s3api list-buckets
resource "aws_s3_bucket" "bucket" {
  for_each = { for i in local.resources.s3 : i.name => i }

  bucket              = each.value.name
  force_destroy       = each.value.force_destroy
  object_lock_enabled = each.value.object_lock_enabled
}

# aws --profile localstack ec2 describe-security-groups --filters "Name=tag:env,Values=dev" | jq
resource "aws_security_group" "security_groups" {
  for_each = local.resources.security_groups

  name        = each.key
  description = each.value.description
  vpc_id      = lookup(data.aws_vpc.vpcs, each.value.vpc).id

  dynamic "ingress" {
    for_each = try(each.value.ingress, [])
    content {
      from_port = ingress.value.from
      to_port   = ingress.value.from
      protocol  = ingress.value.protocol

      cidr_blocks = flatten([
        [
          for block in ingress.value.cidr_blocks : lookup(data.aws_vpc.vpcs, block).cidr_block
          if lookup(data.aws_vpc.vpcs, block, null) != null
        ],
        [
          for block in ingress.value.cidr_blocks : block
          if lookup(data.aws_vpc.vpcs, block, null) == null
        ]
      ])
    }
  }

  dynamic "egress" {
    for_each = try(each.value.egress, [])
    content {
      from_port = egress.value.from
      to_port   = egress.value.from
      protocol  = egress.value.protocol

      cidr_blocks = flatten([
        [
          for block in egress.value.cidr_blocks : lookup(data.aws_vpc.vpcs, block).cidr_block
          if lookup(data.aws_vpc.vpcs, block, null) != null
        ],
        [
          for block in egress.value.cidr_blocks : block
          if lookup(data.aws_vpc.vpcs, block, null) == null
        ]
      ])
    }
  }

  tags = merge({
    env = var.environment,
    }, {
    Name = each.key
  })
}


resource "aws_instance" "instances" {
  for_each = local.resources.instances

  ami           = lookup(data.aws_ami.amis, each.value.ami).id
  instance_type = each.value.size

  # === Networking details ===
  subnet_id = lookup(data.aws_subnet.subnets, each.value.subnet).id
  security_groups = flatten([
    [
      for sg in each.value.security_groups : lookup(aws_security_group.security_groups, sg).id
      if lookup(aws_security_group.security_groups, sg, null) != null
    ],
    [
      for sg in each.value.security_groups : lookup(data.aws_security_group.security_groups, sg).id
      if lookup(data.aws_security_group.security_groups, sg, null) != null
    ],
  ])
  associate_public_ip_address = try(each.value.public_ip, false)

  tags = merge({
    env = var.environment,
    }, {
    Name = each.key
  })
}
