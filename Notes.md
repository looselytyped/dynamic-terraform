# Terraform in the Cloud workshop

This is the code for my Terraform Workshop.

## Highlights

- This **is a workshop**. Please come with a laptop that has the necessary installed software.
- Please follow **all of the installation instructions** in this document before coming to the workshop.
  Debugging Docker/Git installation takes time away from all attendees.
- **Please note** that I routinely make destructive changes (a.k.a `git push -f`) to this repository.
  If you wish to keep a copy around, I highly recommend you fork this, and `git pull upstream` judiciously.

## Agenda

- The place for, and benefits of "Everything as Code" alongside GitOps
- Terraform's architecture
- Terraform 101
  - Introduction to HCL
  - What are providers?
  - Initializing terraform and providers
- Dive right in! Creating your first resource in AWS using Terraform
- Understanding references, dependencies
- `apply`-ing terraform
- Using `output` and `data` in your terraform scripts
- Variables and the HCL type-system
- DRY with Terraform modules
- Understanding how Terraform manages state
- Using S3 as a backend
- Collaboration using Terraform
- Terraform ecosystem, testing, and GitOps
- Closing arguments, final Q/A, discussion

## Installation

You will need the following installed

- [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Docker](https://www.docker.com/get-started/)
- A good text editor.
  I highly recommend [VS Code](https://code.visualstudio.com/).
- Clone this repository

## Set up

### Create a specific profile for LocalStack

1. Open a terminal window
2. Run the following command:
    ```bash
    aws configure --profile localstack
    ```
3. Enter the following details for the `localstack` profile:
   - AWS Access Key ID: Enter `test`
   - AWS Secret Access Key: Enter `test`
   - Default region name: Enter `us-east-1`
   - Default output format: Enter `json`

4. The AWS CLI will create a new profile named `localstack` in the AWS credentials file (located at `~/.aws/credentials` on Linux/Mac or `%USERPROFILE%\.aws\credentials` on Windows) as well as storing your profile preferences in `~/.aws/config`.

    **This is VERY IMPORTANT**.
    Edit the `localstack` profile in `~/.aws/config`, and the add the following line at the bottom of the `localstack` profile:

    ```ini
    [profile localstack]
    region=us-east-1
    output=json
    endpoint_url = http://localhost:4566 # <- ADD THIS LINE
    ```
5. Run the following:
    ```bash
    docker pull ubuntu:24.04
    docker pull ubuntu:23.10
    docker tag ubuntu:24.04 localstack-ec2/ubuntu-24-04-ami:ami-edbfe74c41f8
    docker tag ubuntu:23.10 localstack-ec2/ubuntu-23-10-ami:ami-77081d4f1e72
    ```


## Testing your setup

In the directory where you cloned this repository:

```bash
# cd /path/to/terraform-workshop
❯ docker compose up --build
# You should see ...
[+] Running 1/0
 ✔ Container localstack-main  Created                                                                                          0.0s
Attaching to localstack-main
localstack-main  |
localstack-main  | LocalStack version: 3.7.1
localstack-main  | LocalStack build git hash: d4f2409a7
localstack-main  |
localstack-main  | Ready.
```

In another terminal, navigate, again, to the location where you cloned this repository:

```bash
# initialize terraform
terraform init
# see if terraform can perform it's duties
terraform plan
terraform apply
# terraform will ask if you are sure. Type `yes`
```

If all that works, you are golden.
Go back to the first terminal

```bash
# Use `Ctrl-c` to stop compose
# Clean up afterwards
docker compose down -v
```

## Demo

### Discussion: Reading YAML files into Terraform

Consider some YAML (in `infra.yaml`):

```yaml
resources:
  s3:
    - sample-bucket
    - sample-bucket1
```

Let's see how we can slurp in YAML into Terraform.
Within `terraform console`,

```hcl
# this will read the yaml file and parse it into
yamldecode(file("infra.yaml")).resources

# see what it looks like
local.resources.s3
```

Let's pull this into our Terraform script:

```
locals {
  # this will read the yaml file and parse it into
  resources = yamldecode(file("infra.yaml")).resources
}
```

### Discussion: Working with lists:

Let's try to use this to construct new S3 buckets:


```
resource "aws_s3_bucket" "bucket" {
  for_each = local.resources.s3
  bucket = each.key
}
```

`for_each` needs a map, or a _set_ of strings.
So, let's try to convert it to a set.

### Discussion: Working with sets

You can use the function `toset` to convert a list of items into a `set`:

```
resource "aws_s3_bucket" "bucket" {
  for_each = toset(local.resources.s3)
  bucket = each.key
}
```

Yay!
However, what if you want slightly more configuration backed in?

### Discussion: Working with
Let's see what we can do about something like this (again, this won't work):

```yaml
  s3:
    - name: sample-bucket
      force_destroy: true
    - name: sample-bucket1
      force_destroy: false
```

We can test this in Terraform console by inspecting `local.resources.s3`

This is _an array_ of maps.
We can try to convert this into a `map`, using the following:

```bash
# terraform console
{ for i in local.resources.s3: i.name => i.force_destroy }
```

Great!
We have a map.
Now we can use this in our HCL:

```hcl
resource "aws_s3_bucket" "bucket" {
  for_each = { for i in local.resources.s3 : i.name => i.force_destroy }

  bucket        = each.key
  force_destroy = each.value
}
```

Of course, we can do better.
This only works if you can reduce it down to a key-value pair, but you might be better served with this:

```yaml
  s3:
    - name: sample-bucket
      force_destroy: true
      object_lock_enabled: true
    - name: sample-bucket1
      force_destroy: false
      object_lock_enabled: true
```

Let's look at this in the console:

```
{ for i in local.resources.s3: i.name => i }
```

We are just using something unique to create the key, that points to the whole object.
And we can use it like this:

```
resource "aws_s3_bucket" "bucket" {
  for_each = { for i in local.resources.s3 : i.name => i }

  bucket              = each.value.name
  force_destroy       = each.value.force_destroy
  object_lock_enabled = each.value.object_lock_enabled
}
```

### Discussion: Let's look up some VPCs

We have existing infrastructure setup for us, which we'll need to reference within our script.
We can look up a VPC using tags, so first, let's create some YAML that gives us a way to record VPC names.
**Note** that we are going to create a new set of entries under `data_sources`.

```yaml
data_sources:
  vpcs:
    non_prod_vpc:
      name: my_vpc
```

Next, let's capture that as a `locals` variable:

```hcl
data_sources = yamldecode(file("infra.yaml")).data_sources
```

With this in place, we can use the console to see what this looks like:

```
local.data_sources.vpcs
```

Let's see how we can use this in our Terraform script:

```hcl
data "aws_vpc" "vpcs" {
  for_each = local.data_sources.vpcs
  tags = {
    Name = each.value.name
  }
}
```

And again, in the console:

```
data.aws_vpc.vpcs
```

### Discussion: Let's do subnets next

Subnets are associated with VPCs.
When we look up subnets, we can use their name, but we also need to know which
VPC they belong to.
So here's what the YAML looks like:

```yaml
  subnets:
    subnet_a:
      name: subnet-a
      vpc: non_prod_vpc
    subnet_b:
      name: subnet-b
      vpc: non_prod_vpc
```

Let's see what the console has to offer:

```
# notice there are a lot!
local.data_sources.subnets
```

Remember, we have to use the `Name` tag, _and_ the VPC.
We will use the `lookup` function.
Let's see this in the console:

```
lookup(data.aws_vpc.vpcs, "non_prod_vpc").id
```

Now, we will use it in our Terraform script:

```
data "aws_subnet" "subnets" {
  for_each = local.data_sources.subnets
  vpc_id   = lookup(data.aws_vpc.vpcs, each.value.vpc).id

  tags = {
    Name = each.value.name
  }
}
```

Let's make sure it worked.
Using the console:

```
 data.aws_subnet.subnets
```

### Discussion: Finish our lookups, with Route53 zones

We will need to set up routing—so we will need to look up Route 53 zones, by name.
Here's the YAML:

```yaml
  route53_zones:
    looselytyped:
      name: "looselytyped."
      private: false
```

Here's the lookup:

```hcl
data "aws_route53_zone" "route53_zones" {
  for_each     = local.data_sources.route53_zones
  name         = each.value.name
  private_zone = each.value.private
}
```

Let's make sure it worked.
Using the console:

```
data.aws_route53_zone.route53_zones
```

### Discussion: Creating security groups

Security groups in AWS belong to a VPC.
They also describe _multiple_ `ingress` and `egress` blocks that describe how traffic flows in and out of EC2 instances.
Let's see what the YAML looks like.

```yaml
  # under resources
  security_groups:
    sec_dev5_22:
      description: SSH Access
      vpc: non_prod_vpc
      ingress:
        - from: 22
          to: 22
          protocol: tcp
          cidr_blocks:
            - non_prod_vpc
        - from: -1
          to: -1
          protocol: icmp
          cidr_blocks:
            - 0.0.0.0/0
      egress:
        - from: 0
          to: 0
          protocol: -1
          cidr_blocks:
            - 0.0.0.0/0
```

Keeping it simple, let's first ignore the ingress/egress blocks.
Let's make sure we can create a security group.
Remember, we will need to `lookup` the VPC from our `data.aws_vpc`

```hcl
# aws --profile localstack ec2 describe-security-groups --filters "Name=tag:env,Values=dev" | jq
resource "aws_security_group" "security_groups" {
  for_each = local.resources.security_groups

  name        = each.key
  description = each.value.description
  vpc_id      = lookup(data.aws_vpc.vpcs, each.value.vpc).id

  tags = merge({
    env = var.environment,
    }, {
    Name = each.key
  })
}
```

For every ingress/egress block listed in the yaml, we will need to dynamically generate something that looks like this:

```hcl
  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
   }
```

Terraform gives us the `dynamic` to construct repeatable nested blocks.
The `dynamic` block allows for a nested `content` block to define the body of each block.
Let's do the bare minimum here:

```
  dynamic "ingress" {
    for_each = each.value.ingress
    content {
      from_port = ingress.value.from
      to_port   = ingress.value.from
      protocol  = ingress.value.protocol
    }
  }
```

Before we proceed, let's fix this.
What happens if we _don't_ have an `ingress` or `egress` block defined in the YAML?

We can use the `try` to provide use with an escape hatch, like so:

```hcl
  dynamic "ingress" {
    for_each = try(each.value.ingress, [])
    content {
      from_port = ingress.value.from
      to_port   = ingress.value.from
      protocol  = ingress.value.protocol
    }
  }
```

Finally, note that our `ingress` block has a list of `cidr_blocks`.
These can be a mix of referring to the `cidr_blocks` of a VPC, or inline.

The `ingress` (or `egress`) block takes an array of CIDR blocks—which means we have to construct a list from `lookup`s (from `vpcs`) _and_ inline.

To construct a new array, we can use the `for` loop.

```
[for l in ["a", "b"]: l]
```

To combine multiple arrays, we can use us the `flatten` function which combine multiple lists and flatten them together:

```
> flatten([["a", "b"], [], ["c"]])
[
  "a",
  "b",
  "c",
]

# What about a for loop?
> [for l in ["a", "b"]: l]
[
  "a",
  "b",
]

# Let's combine flatten with multiple for loops to create a combined array
> flatten([
  [
    for l in ["a", "b"]: l
  ],
  [
    for l in ["c", "d"]: l
  ]
])
[
  "a",
  "b",
  "c",
  "d",
]
```

Finally, you can combine a `for` loop with a conditional:

```
> [for name in ["neo","trinity","morpheus",]: upper(name) if length(name) < 5]
[
  "NEO",
]
```

Let's see how we can use this to pull in the `cidr_blocks`.
Recall that we can list the name of a VPC (who's `cider_block` is the one associated with this `security_group`) or a `cidr_block` inline, like `0.0.0.0/0`.

```hcl
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
```

And finally, the `egress` dynamic blocks don't look that different:

```
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
```

### Discussion: Creating EC2 instances

When creating EC2 instances, we need AMIs.
These will most likely exist in AWS, so let's write some YAML to help us look them up.

```yaml
  amis:
    ec2_deploy:
      owners:
        - 591542846629
      filters:
        name:
          - amzn2-ami-ecs-gpu-hvm-2.0.*-x86_64-ebs
        virtualization-type:
          - hvm
    amazon_linux:
      owners:
        - 591542846629
      filters:
        name:
          - amzn-ami-2018.03.*-amazon-ecs-optimized
        virtualization-type:
          - hvm
```

This YAML sets up just enough for us to use the `data` block.
Notice that here, we are using the `dynamic` block to build out multiple `filter` blocks:

```
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
```

Notice how we use the `try` expression to short-circuit out of the `for_each` in case no `filters` were supplied.

Next, if you recall, we have some existing `security_groups` created by the DBA group to allow traffic to a MariaDb instance.
Let's look those up as well.

```yaml
  security_groups:
    allow_mariadb:
      name: allow_mariadb
```

And the corresponding lookup:

```
data "aws_security_group" "security_groups" {
  for_each = local.data_sources.security_groups
  tags = {
    Name = each.value.name
  }
}
```

And we are ready.
We've see all the code necessary to pull this off before:

```hcl
resource "aws_instance" "instances" {
  for_each = local.resources.instances

  ami           = lookup(data.aws_ami.amis, each.value.ami).id
  instance_type = each.value.size

  # === Networking details ===
  subnet_id = lookup(data.aws_subnet.subnets, each.value.subnet).id
  vpc_security_group_ids = flatten([
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
```

