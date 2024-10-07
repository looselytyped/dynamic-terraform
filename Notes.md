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
yamldecode(file("infra.yaml")).data_sources

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
