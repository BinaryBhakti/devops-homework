# terraform-s3-demo

An S3 bucket built with Terraform and run against **LocalStack 4.14.0** (an AWS API emulator on
`localhost:4566`). The bucket is versioned, encrypted, blocked from public access, has a
lifecycle rule, and holds one object.

The full write-up, with the captured output of every command, is in
[`../README.md`](../README.md). This file is the quick reference.

## Files

| File | Contents |
|---|---|
| [`provider.tf`](provider.tf) | `terraform {}` block pinning `hashicorp/aws ~> 6.0`, and the AWS provider pointed at LocalStack |
| [`variables.tf`](variables.tf) | `aws_region`, `localstack_endpoint`, `bucket_name` (validated), `environment`, `noncurrent_version_days` |
| [`terraform.tfvars`](terraform.tfvars) | the values used for this run |
| [`main.tf`](main.tf) | 6 resources: bucket, versioning, SSE, public-access block, lifecycle rule, `docs/hello.txt` |
| [`outputs.tf`](outputs.tf) | bucket name / ARN / region, versioning status, object URL, object version ID |
| `.terraform.lock.hcl` | provider version and hashes (committed) |
| `.gitignore` | `.terraform/`, `*.tfstate*`, `*.tfplan` — never commit state |

## Architecture

```
terraform.tfvars ──► variables.tf ──► main.tf ──► provider "aws" ──► LocalStack :4566 (S3 API)
                                         │
              aws_s3_bucket.demo ◄───────┤
                 ├── aws_s3_bucket_versioning.demo ─────────► aws_s3_bucket_lifecycle_configuration.demo
                 ├── aws_s3_bucket_server_side_encryption_configuration.demo ──► aws_s3_object.readme
                 └── aws_s3_bucket_public_access_block.demo
                                         │
                                    outputs.tf
```

Arrows to the right of the bucket are `depends_on` edges. The lifecycle rule waits for
versioning, and the object waits for encryption so it is written encrypted.

## Prerequisites

```bash
docker run -d --name localstack -p 4566:4566 \
  -e SERVICES=s3,ec2,iam,sts,dynamodb localstack/localstack:4.14.0   # last licence-free image
pip3 install --user awscli awscli-local                              # only for verification
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
```

## Workflow

| Step | Command | What it does | Result in this run |
|---|---|---|---|
| 1 | `terraform init` | downloads the provider, writes the lock file | `hashicorp/aws v6.67.0` |
| 2 | `terraform fmt -check -diff` | finds formatting problems; exit 3 if any | caught 2 deliberately broken lines |
| 3 | `terraform validate` | checks syntax and references, no API calls | `Success! The configuration is valid.` |
| 4 | `terraform plan -out=s3.tfplan` | computes and saves the change set | `Plan: 6 to add, 0 to change, 0 to destroy.` |
| 5 | `terraform apply s3.tfplan` | executes exactly the saved plan | `Apply complete! Resources: 6 added` |
| 6 | `terraform show` / `state list` | what Terraform believes exists | 6 resources |
| 7 | `terraform output [-raw\|-json]` | values for people and scripts | 6 outputs |
| 8 | `terraform destroy` | removes everything, in reverse order | `Destroy complete! Resources: 6 destroyed.` |

Verification against the API, independent of Terraform:

```bash
awslocal s3 ls
awslocal s3api get-bucket-versioning  --bucket binarybhakti-session18-demo
awslocal s3api get-bucket-encryption  --bucket binarybhakti-session18-demo
awslocal s3api head-object            --bucket binarybhakti-session18-demo --key docs/hello.txt
curl -s "$(terraform output -raw object_url)"
```

## Lifecycle

```
 .tf files ─► init ─► fmt ─► validate ─► plan ─► apply ─► S3 (LocalStack)
                                                   │
                                          terraform.tfstate ─► show / output
                                                   │
                                                destroy ─► state empty, bucket 404
```

## Real AWS instead of LocalStack

In `provider.tf`, delete `access_key`, `secret_key`, the `skip_*` flags, `s3_use_path_style` and
the `endpoints {}` block. Run `aws configure`. Then change `bucket_name` in `terraform.tfvars`,
because bucket names are global across all AWS accounts.
