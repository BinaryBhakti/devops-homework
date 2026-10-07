# Homework 17 — Terraform & Infrastructure as Code

Course session: **`session18-terraform-iac`**.

Two tasks: a Terraform project that builds an S3 bucket and walks it through the full
`init → fmt → validate → plan → apply → show → output → destroy` lifecycle, and a written study
of five core AWS services.

**All output blocks are extracted verbatim** from the transcripts in [`outputs/`](outputs).

The screenshots are **renders of those transcripts**, not captures of a live terminal — every lab ran non-interactively, so there was no window to photograph. Each image names its source transcript in the title bar; see [`screenshots/`](screenshots).

## Where the brief is answered

| Session 18 brief | Where |
|---|---|
| Task 1 — `terraform-s3-demo/` with `main.tf`, `variables.tf`, `outputs.tf`, `provider.tf`, `terraform.tfvars`, `README.md` | [`terraform-s3-demo/`](terraform-s3-demo) |
| Task 1 — `init`, `fmt`, `validate`, `plan`, `apply`, `show`, `output`, `destroy` | Tasks 1–8 below |
| Task 2 — IAM, EC2, S3, VPC, DynamoDB & RDS research | [`aws-services/`](aws-services) — see the [last section](#task-2--aws-services-research) |

---

## LocalStack instead of AWS

Every AWS call in this homework goes to **[LocalStack](https://github.com/localstack/localstack)**,
an AWS API emulator running as a Docker container on `localhost:4566`. No AWS account, no bill,
and the Terraform code is the same code that would run against real AWS — only the provider
block differs.

One thing worth knowing before you try to reproduce this: **`localstack/localstack:latest` no
longer starts without a paid licence.** The 2026.x images print
`Please check that your credentials are set up correctly and that you have an active license`
and exit. The last image that runs as free Community edition is **`4.14.0`** (built 2026-02-26),
so that is the tag pinned here.

```console
$ docker ps --filter name=localstack --format "{{.Names}}  {{.Image}}  {{.Status}}  {{.Ports}}"
localstack  localstack/localstack:4.14.0  Up 5 minutes (healthy)  0.0.0.0:4566->4566/tcp, [::]:4566->4566/tcp

$ curl -s localhost:4566/_localstack/info | python3 -m json.tool | grep -E "\"(version|edition|is_license_activated)\""
    "version": "4.14.0:3d5a0c70e",
    "edition": "community",
    "is_license_activated": false,

$ awslocal sts get-caller-identity
{
    "UserId": "AKIAIOSFODNN7EXAMPLE",
    "Account": "000000000000",
    "Arn": "arn:aws:iam::000000000000:root"
}
```

Account `000000000000` is LocalStack's fixed fake account. `awslocal` is a thin wrapper around
the real AWS CLI (`aws-cli/1.44.87`) that adds `--endpoint-url=http://localhost:4566`.

![LocalStack 4.14.0 community as the AWS endpoint](screenshots/01-localstack-community.png)
*LocalStack 4.14.0 community as the AWS endpoint*

### Why a provider block and not `tflocal`

There are two ways to point Terraform at LocalStack. `tflocal` is a wrapper that generates an
override file with LocalStack endpoints at run time. The alternative, used here, is to write the
endpoints into [`provider.tf`](terraform-s3-demo/provider.tf):

```hcl
provider "aws" {
  region     = var.aws_region
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = var.localstack_endpoint
    sts = var.localstack_endpoint
    iam = var.localstack_endpoint
  }
}
```

| Setting | Why it is there |
|---|---|
| `access_key` / `secret_key = "test"` | LocalStack accepts any credentials; hard-coding fake ones means no `aws configure` is needed |
| `skip_credentials_validation` | otherwise the provider calls real STS to check the keys |
| `skip_requesting_account_id` | otherwise it asks IAM/STS for the account ID at start-up |
| `s3_use_path_style` | builds `localhost:4566/<bucket>` URLs; the virtual-host form `<bucket>.localhost` does not resolve |
| `endpoints { ... }` | sends each service's API calls to LocalStack instead of `*.amazonaws.com` |

Writing it out means plain `terraform` works, nothing is hidden in a wrapper, and the file
documents exactly what changes between LocalStack and real AWS — delete the `endpoints` block
and the `skip_*` flags and it targets AWS.

---

## The project

```
terraform-s3-demo/
├── provider.tf        terraform {} block (aws ~> 6.0) + the provider aimed at LocalStack
├── variables.tf       region, endpoint, bucket_name (with a validation rule), environment, retention days
├── terraform.tfvars   the values for this run
├── main.tf            bucket + versioning + encryption + public-access block + lifecycle + one object
├── outputs.tf         name, ARN, region, versioning status, object URL, object version ID
└── README.md
```

The course demo creates a bare bucket. This one creates **six resources**, because a bare bucket
is not what anyone should deploy:

| Resource | What it adds |
|---|---|
| `aws_s3_bucket.demo` | the bucket, tagged, `force_destroy = true` so a non-empty versioned bucket can be destroyed |
| `aws_s3_bucket_versioning.demo` | every overwrite keeps the old version |
| `aws_s3_bucket_server_side_encryption_configuration.demo` | AES-256 encryption at rest by default |
| `aws_s3_bucket_public_access_block.demo` | all four public-access switches on |
| `aws_s3_bucket_lifecycle_configuration.demo` | superseded versions expire after 30 days, so versioning does not grow forever |
| `aws_s3_object.readme` | an object, to prove the bucket actually stores data |

In AWS provider v4 and later these settings are **separate resources**, not arguments of
`aws_s3_bucket`. That is why there are six.

---

# Task 1 — `terraform init`

```console
$ terraform init -no-color
Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.67.0...
- Installed hashicorp/aws v6.67.0 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!
```

`init` resolved the constraint `~> 6.0` to **v6.67.0**, downloaded the provider binary into
`.terraform/`, and wrote the exact version and its hashes to `.terraform.lock.hcl`:

```console
$ ls -a; cat .terraform.lock.hcl | head -8
.
..
.gitignore
.terraform
.terraform.lock.hcl
main.tf
outputs.tf
provider.tf
terraform.tfvars
variables.tf
# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/hashicorp/aws" {
  version     = "6.67.0"
  constraints = "~> 6.0"
  hashes = [
    "h1:OgdIUAQDtJBxlKjoPgChD1w57vl6hm6PyJHiBYgsgQA=",
```

The **lock file is committed**; `.terraform/` (756 MB of provider binary) and the state files
are in `.gitignore`. That way a teammate gets the same provider version, not just one that
matches `~> 6.0`.

![terraform init — provider download and lock file](screenshots/02-terraform-init.png)
*terraform init — provider download and lock file*

---

# Task 2 — `terraform fmt`

The files were already in canonical format, so `fmt -check` had nothing to say:

```console
$ terraform fmt -check -recursive; echo "exit code: $?"
exit code: 0
```

To see it actually work, two lines were broken on purpose:

```console
$ terraform fmt -check -diff; echo "exit code: $?"
main.tf
--- old/main.tf
+++ new/main.tf
@@ -9,7 +9,7 @@
 
 resource "aws_s3_bucket" "demo" {
   bucket        = var.bucket_name
-      force_destroy=true # lets `terraform destroy` remove a non-empty, versioned bucket
+  force_destroy = true # lets `terraform destroy` remove a non-empty, versioned bucket
   tags          = local.common_tags
 }
 
terraform.tfvars
--- old/terraform.tfvars
+++ new/terraform.tfvars
@@ -1,4 +1,4 @@
 aws_region              = "ap-south-1"
 bucket_name             = "binarybhakti-session18-demo"
-environment="dev"
+environment             = "dev"
 noncurrent_version_days = 30
exit code: 3

$ terraform fmt; echo "exit code: $?"
main.tf
terraform.tfvars
exit code: 0
```

| Command | Behaviour | Use it in |
|---|---|---|
| `terraform fmt` | rewrites files in place, prints the names it changed | your editor / pre-commit |
| `terraform fmt -check` | changes nothing; **exit code 3** if anything is unformatted | CI — fails the build |
| `terraform fmt -check -diff` | same, and shows the diff | CI logs, so the author sees why |

`fmt` also aligns the `=` signs in a block, which is why `environment` gained padding to line up
with `noncurrent_version_days`.

![terraform fmt — check, diff, rewrite](screenshots/03-terraform-fmt.png)
*terraform fmt — check, diff, rewrite*

---

# Task 3 — `terraform validate`

```console
$ terraform validate -no-color
Success! The configuration is valid.
```

A success message proves little on its own, so here is what `validate` catches. In a scratch
copy of the project, one reference was changed to a resource that does not exist:

```console
$ mkdir -p /tmp/tf-broken && cp *.tf /tmp/tf-broken/ && cp -r .terraform .terraform.lock.hcl /tmp/tf-broken/ && sed -i "" "s/aws_s3_bucket.demo.id/aws_s3_bucket.missing.id/" /tmp/tf-broken/main.tf && cd /tmp/tf-broken && terraform validate -no-color; echo "exit code: $?"

Error: Reference to undeclared resource

  on main.tf line 17, in resource "aws_s3_bucket_versioning" "demo":
  17:   bucket = aws_s3_bucket.missing.id

A managed resource "aws_s3_bucket" "missing" has not been declared in the
root module.
```

(The same error repeats for every resource that referenced the bucket; exit code `1`.)

`validate` checks syntax, references and argument types **without any API calls**. It does not
check the *values* you will supply. That is the job of `validation {}` rules on variables, which
run at plan time:

```console
$ terraform plan -no-color -var="bucket_name=Bad_Bucket_Name" 2>&1 | head -12

Planning failed. Terraform encountered an error while generating this plan.


Error: Invalid value for variable

  on variables.tf line 13:
  13: variable "bucket_name" {
    ├────────────────
    │ var.bucket_name is "Bad_Bucket_Name"

Bucket names must be 3-63 chars of lowercase letters, digits, dots and
```

S3 would have rejected `Bad_Bucket_Name` too, but only after Terraform had started creating
things. The rule fails it before any API call.

![terraform validate — and what it catches](screenshots/04-terraform-validate.png)
*terraform validate — and what it catches*

---

# Task 4 — `terraform plan`

```console
$ terraform plan -no-color -out=s3.tfplan

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # aws_s3_bucket.demo will be created
  + resource "aws_s3_bucket" "demo" {
      + acceleration_status         = (known after apply)
      + acl                         = (known after apply)
      + arn                         = (known after apply)
      + bucket                      = "binarybhakti-session18-demo"
      ...
```

The full plan is 162 lines ([`outputs/task4-plan.txt`](outputs/task4-plan.txt)). It ends with:

```console
Plan: 6 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + bucket_arn        = (known after apply)
  + bucket_name       = "binarybhakti-session18-demo"
  + bucket_region     = "ap-south-1"
  + object_url        = (known after apply)
  + object_version_id = (known after apply)
  + versioning_status = "Enabled"
```

Two things to read in a plan:

- **`(known after apply)`** — values the cloud assigns, such as the ARN or the object's version
  ID. Terraform cannot know them until the resource exists. `bucket_name` and `versioning_status`
  come straight from configuration, so they are known now.
- **`-out=s3.tfplan`** — saves this exact plan. `terraform apply s3.tfplan` then applies these
  six changes and nothing else, even if the code or the cloud changed in between. Running a
  plain `terraform apply` would re-plan, and the result could differ from what was reviewed.

![terraform plan — 6 to add](screenshots/05-terraform-plan.png)
*terraform plan — 6 to add*

---

# Task 5 — `terraform apply`

```console
$ terraform apply -no-color s3.tfplan
aws_s3_bucket.demo: Creating...
aws_s3_bucket.demo: Creation complete after 2s [id=binarybhakti-session18-demo]
aws_s3_bucket_versioning.demo: Creating...
aws_s3_bucket_public_access_block.demo: Creating...
aws_s3_bucket_server_side_encryption_configuration.demo: Creating...
aws_s3_bucket_server_side_encryption_configuration.demo: Creation complete after 1s [id=binarybhakti-session18-demo]
aws_s3_bucket_public_access_block.demo: Creation complete after 1s [id=binarybhakti-session18-demo]
aws_s3_object.readme: Creating...
aws_s3_object.readme: Creation complete after 0s [id=binarybhakti-session18-demo/docs/hello.txt]
aws_s3_bucket_versioning.demo: Creation complete after 1s [id=binarybhakti-session18-demo]
aws_s3_bucket_lifecycle_configuration.demo: Creating...
aws_s3_bucket_lifecycle_configuration.demo: Still creating... [00m10s elapsed]
aws_s3_bucket_lifecycle_configuration.demo: Still creating... [00m20s elapsed]
aws_s3_bucket_lifecycle_configuration.demo: Still creating... [00m30s elapsed]
aws_s3_bucket_lifecycle_configuration.demo: Still creating... [00m40s elapsed]
aws_s3_bucket_lifecycle_configuration.demo: Still creating... [00m50s elapsed]
aws_s3_bucket_lifecycle_configuration.demo: Still creating... [01m00s elapsed]
aws_s3_bucket_lifecycle_configuration.demo: Creation complete after 1m2s [id=binarybhakti-session18-demo]

Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:

bucket_arn = "arn:aws:s3:::binarybhakti-session18-demo"
bucket_name = "binarybhakti-session18-demo"
bucket_region = "ap-south-1"
object_url = "http://localhost:4566/binarybhakti-session18-demo/docs/hello.txt"
object_version_id = "AaEXDD1VOY102oDB40euBc4Fu5Qhb7Ao"
versioning_status = "Enabled"
```

Read the order. The bucket comes first because every other resource references
`aws_s3_bucket.demo.id`. Then three resources start **in parallel**. Two of them are gated by the
`depends_on` lines in [`main.tf`](terraform-s3-demo/main.tf):

- `aws_s3_object.readme` waited for **encryption**, not just the bucket. It does not reference the
  encryption resource, but an object uploaded before default encryption is set is stored
  unencrypted.
- `aws_s3_bucket_lifecycle_configuration.demo` waited for **versioning**. A rule that expires
  *noncurrent versions* means nothing on an unversioned bucket.

The 62-second lifecycle rule is investigated [below](#gotcha--the-lifecycle-rule-that-took-a-minute).

![terraform apply — 6 resources in dependency order](screenshots/06-terraform-apply.png)
*terraform apply — 6 resources in dependency order*

## Verified through the S3 API, not through Terraform

Terraform saying "6 added" is Terraform's own view. Here is the bucket checked directly through
the S3 API:

```console
$ awslocal s3 ls
2026-10-07 21:17:42 binarybhakti-session18-demo

$ awslocal s3api get-bucket-versioning --bucket binarybhakti-session18-demo
{
    "Status": "Enabled"
}

$ awslocal s3api get-bucket-encryption --bucket binarybhakti-session18-demo
{
    "ServerSideEncryptionConfiguration": {
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": false
            }
        ]
    }
}

$ awslocal s3api get-public-access-block --bucket binarybhakti-session18-demo
{
    "PublicAccessBlockConfiguration": {
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }
}

$ awslocal s3api get-bucket-lifecycle-configuration --bucket binarybhakti-session18-demo
{
    "TransitionDefaultMinimumObjectSize": "all_storage_classes_128K",
    "Rules": [
        {
            "ID": "expire-old-versions",
            "Filter": {
                "Prefix": ""
            },
            "Status": "Enabled",
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 30
            }
        }
    ]
}
```

And the object. It is readable, and it was **stored encrypted**, which shows the `depends_on`
ordering mattered:

```console
$ awslocal s3 cp s3://binarybhakti-session18-demo/docs/hello.txt -
Hello from Terraform - Session 18 (dev)

$ awslocal s3api head-object --bucket binarybhakti-session18-demo --key docs/hello.txt
{
    "AcceptRanges": "bytes",
    "LastModified": "Wed, 07 Oct 2026 15:47:43 GMT",
    "ContentLength": 40,
    "ETag": "\"b4222fd50d92030a2632c1cdbad0677d\"",
    "VersionId": "AaEXDD1VOY102oDB40euBc4Fu5Qhb7Ao",
    "ContentType": "text/plain",
    "ServerSideEncryption": "AES256",
    "Metadata": {}
}
```

The object's `VersionId` matches the `object_version_id` output exactly.

Finally, **idempotence**. A second plan against the unchanged configuration has nothing to do:

```console
$ terraform plan -no-color -detailed-exitcode | tail -3; echo "exit code: ${PIPESTATUS[0]}"

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
exit code: 0
```

`-detailed-exitcode` gives `0` for no changes, `2` for changes pending and `1` for an error. A
nightly CI job can run it to detect drift.

![the bucket, verified through the S3 API](screenshots/07-verify-with-aws-cli.png)
*the bucket, verified through the S3 API*

---

# Task 6 — `terraform show` and the state file

```console
$ terraform state list
aws_s3_bucket.demo
aws_s3_bucket_lifecycle_configuration.demo
aws_s3_bucket_public_access_block.demo
aws_s3_bucket_server_side_encryption_configuration.demo
aws_s3_bucket_versioning.demo
aws_s3_object.readme
```

`terraform show` prints everything in state in HCL form. The bucket alone is 70 lines
([full transcript](outputs/task6-show-and-state.txt)); one resource can be shown on its own:

```console
$ terraform state show -no-color aws_s3_object.readme
# aws_s3_object.readme:
resource "aws_s3_object" "readme" {
    arn                           = "arn:aws:s3:::binarybhakti-session18-demo/docs/hello.txt"
    bucket                        = "binarybhakti-session18-demo"
    ...
    etag                          = "b4222fd50d92030a2632c1cdbad0677d"
    ...
    server_side_encryption        = "AES256"
    storage_class                 = "STANDARD"
    ...
    version_id                    = "AaEXDD1VOY102oDB40euBc4Fu5Qhb7Ao"
}
```

*(Lines elided with `...` for length; the transcript has all of them.)*

The state is a JSON file on disk:

```console
$ ls -l terraform.tfstate*
-rw-r--r--@ 1 ashmit  staff  11817 Oct  7 21:22 terraform.tfstate
-rw-r--r--@ 1 ashmit  staff  11318 Oct  7 21:21 terraform.tfstate.backup

$ python3 -c "import json; s=json.load(open(\"terraform.tfstate\")); print(\"serial:\", s[\"serial\"], \" terraform_version:\", s[\"terraform_version\"]); [print(\" \", r[\"type\"]+\".\"+r[\"name\"]) for r in s[\"resources\"]]"
serial: 10  terraform_version: 1.16.5
  aws_s3_bucket.demo
  aws_s3_bucket_lifecycle_configuration.demo
  aws_s3_bucket_public_access_block.demo
  aws_s3_bucket_server_side_encryption_configuration.demo
  aws_s3_bucket_versioning.demo
  aws_s3_object.readme
```

`serial` goes up every time state is written. It is **10**, not 1, because of the extra debug
apply in the [gotcha](#gotcha--the-lifecycle-rule-that-took-a-minute) plus the refreshes done by
each plan. `.backup` is the previous version.

**Why the state file is in `.gitignore`.** It holds every attribute of every resource in plain
text. For S3 that is harmless, but for a database it includes the master password. In a team,
state belongs in a remote backend with locking — an S3 bucket plus DynamoDB lock table, or
Terraform Cloud — never in Git. Two people running `apply` against two local copies of the state
is how infrastructure gets created twice.

![terraform show and the state file](screenshots/08-terraform-show-state.png)
*terraform show and the state file*

---

# Task 7 — `terraform output`

```console
$ terraform output -no-color
bucket_arn = "arn:aws:s3:::binarybhakti-session18-demo"
bucket_name = "binarybhakti-session18-demo"
bucket_region = "ap-south-1"
object_url = "http://localhost:4566/binarybhakti-session18-demo/docs/hello.txt"
object_version_id = "AaEXDD1VOY102oDB40euBc4Fu5Qhb7Ao"
versioning_status = "Enabled"

$ terraform output -raw bucket_name; echo
binarybhakti-session18-demo
```

`-raw` drops the quotes, so it is the form to use in shell scripts. Here an output is used as
input to another command:

```console
$ curl -s "$(terraform output -raw object_url)"
Hello from Terraform - Session 18 (dev)
```

`-json` gives value, type and sensitivity, for tools:

```console
$ terraform output -json | python3 -m json.tool | head -12
{
    "bucket_arn": {
        "sensitive": false,
        "type": "string",
        "value": "arn:aws:s3:::binarybhakti-session18-demo"
    },
    "bucket_name": {
        "sensitive": false,
        "type": "string",
        "value": "binarybhakti-session18-demo"
    },
    "bucket_region": {
```

![terraform output — human, raw, JSON](screenshots/09-terraform-output.png)
*terraform output — human, raw, JSON*

---

# Task 8 — `terraform destroy`

Preview first:

```console
$ terraform plan -destroy -no-color | tail -12
        # (13 unchanged attributes hidden)
    }

Plan: 0 to add, 0 to change, 6 to destroy.
```

Then destroy, shown here from the point where Terraform starts executing:

```console
aws_s3_bucket_public_access_block.demo: Destroying... [id=binarybhakti-session18-demo]
aws_s3_object.readme: Destroying... [id=binarybhakti-session18-demo/docs/hello.txt]
aws_s3_bucket_lifecycle_configuration.demo: Destroying... [id=binarybhakti-session18-demo]
aws_s3_bucket_lifecycle_configuration.demo: Destruction complete after 1s
aws_s3_bucket_public_access_block.demo: Destruction complete after 1s
aws_s3_object.readme: Destruction complete after 1s
aws_s3_bucket_versioning.demo: Destroying... [id=binarybhakti-session18-demo]
aws_s3_bucket_server_side_encryption_configuration.demo: Destroying... [id=binarybhakti-session18-demo]
aws_s3_bucket_server_side_encryption_configuration.demo: Destruction complete after 0s
aws_s3_bucket_versioning.demo: Destruction complete after 0s
aws_s3_bucket.demo: Destroying... [id=binarybhakti-session18-demo]
aws_s3_bucket.demo: Destruction complete after 0s

Destroy complete! Resources: 6 destroyed.
```

This is the **apply order reversed**: the lifecycle rule and the object go first, versioning and
encryption next (their dependants are gone), and the bucket last.

Then checked from the API side:

```console
$ awslocal s3 ls; echo "(exit $?, bucket list is empty)"
(exit 0, bucket list is empty)

$ awslocal s3api head-bucket --bucket binarybhakti-session18-demo; echo "exit code: $?"

An error occurred (404) when calling the HeadBucket operation: Not Found
exit code: 255

$ terraform state list; echo "(exit $?, state is empty)"
(exit 0, state is empty)

$ terraform show -no-color
The state file is empty. No resources are represented.
```

The bucket still held `docs/hello.txt` when it was destroyed. That worked only because of
`force_destroy = true`. Without it, S3 refuses to delete a non-empty bucket and `destroy` fails
with `BucketNotEmpty`.

![terraform destroy — and proof the bucket is gone](screenshots/10-terraform-destroy.png)
*terraform destroy — and proof the bucket is gone*

---

## Gotcha — the lifecycle rule that took a minute

Every resource took 0–2 seconds, except the lifecycle rule: **1m2s**. LocalStack answers in
milliseconds, so the time was not spent in the API. To find out where it went, the rule alone was
re-created with debug logging on:

```console
# every other resource took 0-2 s. The lifecycle rule alone was re-created with debug logging, using:
#   TF_LOG=DEBUG terraform apply -auto-approve -replace=aws_s3_bucket_lifecycle_configuration.demo > /tmp/tf-debug.log 2>&1
$ grep -E "Creation complete|Destruction complete" /tmp/tf-debug.log
aws_s3_bucket_lifecycle_configuration.demo: Destruction complete after 0s
aws_s3_bucket_lifecycle_configuration.demo: Creation complete after 57s [id=binarybhakti-session18-demo]

$ grep "rpc.method=S3/PutBucketLifecycleConfiguration" /tmp/tf-debug.log | grep -oE "^[0-9T:.-]+" | cut -c12-23 | head -1
21:21:47.741

$ grep "rpc.method=S3/GetBucketLifecycleConfiguration" /tmp/tf-debug.log | grep "tf_rpc=ApplyResourceChange" | grep -oE "^[0-9T:.-]+" | cut -c12-19 | uniq -c
   4 21:21:47
   3 21:21:58
   4 21:22:03
   3 21:22:08
   3 21:22:13
   3 21:22:18
   3 21:22:23
   1 21:22:24
   4 21:22:29
   3 21:22:34
   4 21:22:39
   4 21:22:44
```

The configuration is **written once, at 21:21:47**. For the next 57 seconds the provider **reads
it back every ~5 seconds** before it reports the resource as created.

That is a propagation waiter. AWS documents that a new lifecycle configuration can take time to
apply across S3, so the provider keeps confirming the rule is readable before it declares
success. Against real S3 the wait is useful. Against LocalStack, which is consistent at once, it
is pure waiting. It is not an error, and nothing in the configuration is wrong. But on the first
apply it looks like a hang, and it is the reason this `apply` took a minute instead of five
seconds.

![why the lifecycle rule took a minute](screenshots/11-lifecycle-62s-gotcha.png)
*why the lifecycle rule took a minute*

---

# Task 2 — AWS services research

The five research write-ups live in **[`aws-services/`](aws-services)**, one README per service
plus an [index](aws-services/README.md). Each one covers every topic the brief lists, and each
includes a real lab run against the same LocalStack container, with transcripts in
[`aws-services/outputs/`](aws-services/outputs) and screenshots in
[`aws-services/screenshots/`](aws-services/screenshots).

| # | Service | Category | Write-up | Headline finding from the lab |
|---|---|---|---|---|
| 01 | IAM | Governance | [`aws-services/01-iam`](aws-services/01-iam) | policies are stored but **not enforced** in LocalStack community: a read-only user deleted an object |
| 02 | EC2 | Compute | [`aws-services/02-ec2`](aws-services/02-ec2) | the public IP changed across stop/start, the private IP did not |
| 03 | S3 | Storage | [`aws-services/03-s3`](aws-services/03-s3) | SSE-S3 by default on every object; SSE-KMS breaks every write when KMS is not running |
| 04 | VPC | Networking | [`aws-services/04-vpc`](aws-services/04-vpc) | 251 usable IPs per /24; a subnet is "public" only because of its route table |
| 05 | DynamoDB & RDS | Database | [`aws-services/05-dynamodb-rds`](aws-services/05-dynamodb-rds) | a scan read 4 items to return 1, the GSI read 1; RDS is not in LocalStack community |

---

## Reproducing this

```bash
# 1. LocalStack — pin 4.14.0; newer images need a licence
docker run -d --name localstack -p 4566:4566 \
  -e SERVICES=s3,ec2,iam,sts,dynamodb localstack/localstack:4.14.0
curl -s localhost:4566/_localstack/health

# 2. AWS CLI + the awslocal wrapper (only needed for the verification commands)
pip3 install --user awscli awscli-local
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1

# 3. The lifecycle
cd 17-terraform-iac/terraform-s3-demo
terraform init
terraform fmt -check
terraform validate
terraform plan -out=s3.tfplan
terraform apply s3.tfplan
awslocal s3api get-bucket-versioning --bucket binarybhakti-session18-demo
terraform show
terraform output
terraform destroy
```

To run against **real AWS** instead: delete the `access_key`/`secret_key` lines, the four
`skip_*`/`s3_use_path_style` flags and the `endpoints` block from `provider.tf`, run
`aws configure`, and change `bucket_name` — S3 names are global, so someone may already own
this one.

---

## Files

```
17-terraform-iac/
├── README.md
├── terraform-s3-demo/
│   ├── provider.tf  variables.tf  main.tf  outputs.tf  terraform.tfvars
│   ├── .terraform.lock.hcl       committed: pins aws provider 6.67.0
│   ├── .gitignore                .terraform/, *.tfstate*, *.tfplan
│   └── README.md
├── aws-services/                 Task 2 — five research READMEs + labs
├── outputs/
│   ├── task0-localstack-and-tools.txt
│   ├── task1-init.txt
│   ├── task2-fmt.txt
│   ├── task3-validate.txt
│   ├── task4-plan.txt
│   ├── task5-apply.txt
│   ├── task6-show-and-state.txt
│   ├── task7-output.txt
│   ├── task8-destroy.txt
│   └── gotcha-lifecycle-62s.txt
└── screenshots/                  11 renders, see screenshots/README.md
```
