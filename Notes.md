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

### Discussion: Working with lists

```yaml
resources:
  s3:
    - sample-bucket
    - sample-bucket1
```

Before we proceed, let's see how we can slurp in YAML into Terraform.
Within `terraform console`,

```hcl
# this will read the yaml file and parse it into
yamldecode(file("infra.yaml")).data_sources
```


```hcl
# see what it looks like
local.resources.s3
```

Let's try this within our Terraform script (this won't work):

```
resource "aws_s3_bucket" "bucket" {
  bucket = each.key
}
```

`for_each` needs a map, or a _set_ of strings.
So, let's try to convert it to a set.

### Discussion: Working with maps/sets

You can use the function `toset` to convert a list of items into a `set`:

```
resource "aws_s3_bucket" "bucket" {
  for_each = toset(local.resources.s3)
  bucket = each.key
}
```

Yay!
However, what if you want slightly more configuration backed in?
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







