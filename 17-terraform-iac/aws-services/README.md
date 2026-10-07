# AWS Services Research — Session 18, Task 2

Five core AWS services, one README each. Each covers every topic the brief lists, as a study
write-up (concepts, comparison tables, diagrams, gotchas). Wherever the service can be exercised
locally, it includes a **real lab run against LocalStack** instead of AWS.

| # | Service | Category | Lab on LocalStack | Headline finding |
|---|---|---|---|---|
| 01 | **[IAM](01-iam)** | Governance | users, groups, a least-privilege policy, a role + instance profile, STS | policies are **stored but not enforced**: a user with read-only rights deleted an object; the policy simulator answers `explicitDeny` to everything |
| 02 | **[EC2](02-ec2)** | Compute | AMIs, instance types, key pair, security group, EBS attach, stop/start/terminate | the auto-assigned **public IP changed across stop/start** while the private IP stayed; no VM ever existed |
| 03 | **[S3](03-s3)** | Storage | objects, storage classes, versioning + delete markers, lifecycle, encryption, bucket policy | default **SSE-S3 on every object**; **SSE-KMS breaks every write** when KMS isn't available; the TLS-only bucket policy isn't enforced |
| 04 | **[VPC](04-vpc)** | Networking | VPC, two subnets, IGW, NAT gateway + EIP, public vs private route tables, SG vs NACL | CIDR and overlap validation are real; **251 usable IPs per /24**; a subnet is "public" only because of its route table |
| 05 | **[DynamoDB & RDS](05-dynamodb-rds)** | Database | DynamoDB table with partition + sort key, query vs scan vs GSI | **scan read 4 items to return 1**, the GSI read 1; **RDS isn't in LocalStack community** (error captured) |

## Environment

| | |
|---|---|
| Emulator | LocalStack **4.14.0** community (`localstack/localstack:4.14.0`), services `s3,ec2,iam,sts,dynamodb` |
| Why that tag | it's the last free release. `localstack/localstack:latest` (the 2026.x builds) now exits at start-up without a licence: *"Please check that your credentials are set up correctly and that you have an active license."* |
| CLI | `aws-cli/1.44.87` + `awslocal` (wraps `aws --endpoint-url http://localhost:4566`) |
| Credentials | dummy `test`/`test`, account `000000000000`, region `us-east-1` |

## What LocalStack community can and can't show

These labs are honest about the emulator. Every limitation below was hit and is captured in a
transcript, not just quoted from LocalStack's docs.

| Works like AWS | Doesn't |
|---|---|
| API shapes, IDs, ARNs, error codes (`InvalidSubnet.Conflict`, `ConditionalCheckFailedException`…) | **IAM and bucket-policy enforcement**: any credential can do anything (`ENFORCE_IAM` is Pro) |
| S3 versioning, lifecycle config, default encryption, storage classes | the IAM policy simulator (stub answers; `simulate-custom-policy` not implemented) |
| VPC CIDR validation, reserved addresses, route tables | **packet flow**: no NAT, no routing, no reachability |
| EC2 state machine, IP assignment, EBS attach | **EC2 instances are mocks**, with no VM or container behind them |
| DynamoDB keys, conditions, query/scan, GSIs | **RDS** (Pro only) |

The practical rule that follows: LocalStack is good for **learning the APIs and testing the
Terraform that builds infrastructure**. It **can't tell you whether a security control works**.
That still needs real AWS.

Every resource was created with a `research-` prefix and **deleted at the end of its lab**. Each
transcript ends with the cleanup and an empty listing.

## Files

```
aws-services/
├── README.md                 this index
├── 01-iam/                   README.md + the two policy JSON files
├── 02-ec2/                   README.md
├── 03-s3/                    README.md + lifecycle and bucket-policy JSON
├── 04-vpc/                   README.md
├── 05-dynamodb-rds/          README.md
├── outputs/                  01-iam.txt … 05-dynamodb-rds.txt, the raw transcripts
└── screenshots/              10 renders of those transcripts (2 per service)
```

The screenshots are **renders of the transcripts**, not captures of a live terminal. The labs
ran non-interactively, and each image names its source transcript in its subtitle bar, the same
approach as Homeworks 8–11.
