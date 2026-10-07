# 01 — IAM: Identity and Access Management (Governance)

**IAM answers one question for every AWS API call: _is this principal allowed to perform this
action on this resource, right now?_** Every `s3 cp`, every `ec2 run-instances`, every Terraform
`apply` gets that check first, and the default answer is no.

The practical parts below ran against **LocalStack 4.14.0** (community edition) on
`localhost:4566`. All output blocks are verbatim from [`../outputs/01-iam.txt`](../outputs/01-iam.txt).
The two policy files used are in this folder:
[`research-s3-read.json`](research-s3-read.json) and [`research-ec2-trust.json`](research-ec2-trust.json).

> **Know this before reading the output.** LocalStack community **stores** IAM objects
> faithfully, but it **does not enforce** them. Users, groups, roles and policies are created
> and attached exactly as on AWS, but any credential can still do anything. That is proven
> below rather than assumed, and it is the most important thing to know when testing IAM
> locally.

---

## The building blocks

| Thing | What it is | Has credentials? | Typical owner |
|---|---|---|---|
| **Root user** | the email address that created the account | yes, unlimited, and **cannot be restricted by IAM policy** | nobody, day to day; lock it away with MFA |
| **User** | a long-lived identity for one person or one legacy system | password and/or access keys | a human (ideally via SSO instead) |
| **Group** | a collection of users; **only** a way to attach policies to many users at once | **no**, and it can't be a principal | a team: `developers`, `auditors` |
| **Role** | an identity with **no permanent credentials** that a trusted principal *assumes* for temporary credentials | temporary only (STS) | EC2 instances, Lambda, CI pipelines, other accounts, SSO users |
| **Policy** | a JSON document of `Allow`/`Deny` statements | — | attached to users, groups, roles (identity-based) or to resources (resource-based) |
| **Permission** | the effective result: what the policies, taken together, allow | — | computed at request time |

```
                 ┌──────────── account 000000000000 ────────────┐
                 │                                              │
  person ──────► │  user research-alice ──► group research-developers
                 │                                │             │
                 │                       policy research-s3-read-reports
                 │                                │             │
  EC2 service ─► │  role research-ec2-app ◄───────┘             │
   (trust policy │     │                                        │
    lets it      │     └─► instance profile ─► EC2 instance     │
    assume)      │            (temp creds via STS, auto-rotated)│
                 └──────────────────────────────────────────────┘
```

---

## Users and groups

```console
$ awslocal sts get-caller-identity
{
    "UserId": "AKIAIOSFODNN7EXAMPLE",
    "Account": "000000000000",
    "Arn": "arn:aws:iam::000000000000:root"
}
```

`get-caller-identity` is the first command to run whenever IAM confuses you. It tells you *who
AWS thinks you are*. Here it's the LocalStack root of the fake account `000000000000`.

```console
$ awslocal iam create-group --group-name research-developers --query 'Group.Arn' --output text
arn:aws:iam::000000000000:group/research-developers
$ awslocal iam create-user --user-name research-alice --query 'User.Arn' --output text
arn:aws:iam::000000000000:user/research-alice
$ awslocal iam add-user-to-group --group-name research-developers --user-name research-alice
$ awslocal iam get-group --group-name research-developers --query 'Users[].UserName' --output text
research-alice
```

Every IAM object gets an **ARN** (Amazon Resource Name), and the ARN is how policies refer to
it: `arn:aws:iam::<account>:user/<name>`. IAM is a **global** service, so its ARNs have no
region field (the empty `::`).

---

## Policies and permissions

A policy is a list of statements. Each statement has an **Effect**, an **Action**, a
**Resource** and, optionally, a **Condition**:

```console
$ cat research-s3-read.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListOneBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::research-reports"
    },
    {
      "Sid": "ReadObjectsInThatBucket",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::research-reports/*"
    }
  ]
}
```

Note the **two different resources**. `s3:ListBucket` acts on the *bucket*
(`arn:aws:s3:::research-reports`), and `s3:GetObject` acts on *objects*
(`arn:aws:s3:::research-reports/*`). A single statement with only `research-reports/*` makes
`aws s3 ls` fail with AccessDenied. This is the most common S3 policy mistake.

```console
$ awslocal iam create-policy --policy-name research-s3-read-reports --policy-document file://research-s3-read.json --query 'Policy.[PolicyName,Arn,DefaultVersionId]' --output text
research-s3-read-reports	arn:aws:iam::000000000000:policy/research-s3-read-reports	v1
```

`v1`: a managed policy is **versioned**. AWS keeps up to 5 versions, so a bad edit can be rolled
back with `set-default-policy-version`.

### Attach to the group, not the user

```console
$ awslocal iam attach-group-policy --group-name research-developers --policy-arn arn:aws:iam::000000000000:policy/research-s3-read-reports
$ awslocal iam list-attached-group-policies --group-name research-developers --output table
-------------------------------------------------------------------------------
|                          ListAttachedGroupPolicies                          |
+-----------------------------------------------------------------------------+
||                             AttachedPolicies                              ||
|+------------+--------------------------------------------------------------+|
||  PolicyArn |  arn:aws:iam::000000000000:policy/research-s3-read-reports   ||
||  PolicyName|  research-s3-read-reports                                    ||
|+------------+--------------------------------------------------------------+|
$ awslocal iam list-attached-user-policies --user-name research-alice --output table
--------------------------
|ListAttachedUserPolicies|
+------------------------+
```

The user has **nothing attached directly**, yet gets the group's permissions. When Alice moves
teams, you change one group membership and no policy at all.

### Types of policy

| Type | Attached to | Example | Note |
|---|---|---|---|
| **AWS managed** | identities | `ReadOnlyAccess`, `AmazonS3FullAccess` | maintained by AWS; convenient but usually broader than you need |
| **Customer managed** | identities | `research-s3-read-reports` above | yours, versioned, reusable. **The default choice** |
| **Inline** | exactly one identity | `put-user-policy` | deleted with the identity; hard to audit; avoid except for strict 1:1 cases |
| **Resource-based** | a resource | S3 bucket policy, KMS key policy, SQS queue policy | has a `Principal` field; can grant **cross-account** access |
| **Trust policy** | a role | `research-ec2-trust.json` below | a resource policy on the role: *who* may assume it |
| **Permissions boundary** | a user/role | caps the maximum a role can ever get | delegation safety net |
| **SCP** (Organizations) | an account/OU | "no one in this account may leave `ap-south-1`" | caps whole accounts; grants nothing on its own |

### How AWS evaluates a request

```
           request (principal, action, resource, context)
                              │
                ┌─────────────▼──────────────┐
                │ any explicit "Deny" match? │──yes──► DENY   (nothing overrides this)
                └─────────────┬──────────────┘
                              │no
                ┌─────────────▼──────────────┐
                │ SCP / boundary allow it?   │──no───► DENY
                └─────────────┬──────────────┘
                              │yes
                ┌─────────────▼──────────────┐
                │ any "Allow" match?         │──no───► DENY   ("implicit deny", the default)
                └─────────────┬──────────────┘
                              │yes
                            ALLOW
```

There are three rules. **Default deny**: nothing is allowed until something allows it. **An
explicit Deny always wins**, whatever allows it elsewhere. **Allows add up** across all policies
that apply.

---

## Roles: trust policy plus permission policy

A role has two independent policies, and both have to be right:

```console
$ cat research-ec2-trust.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
$ awslocal iam create-role --role-name research-ec2-app --assume-role-policy-document file://research-ec2-trust.json --query 'Role.[RoleName,Arn]' --output text
research-ec2-app	arn:aws:iam::000000000000:role/research-ec2-app
$ awslocal iam attach-role-policy --role-name research-ec2-app --policy-arn arn:aws:iam::000000000000:policy/research-s3-read-reports
```

| | Trust policy | Permission policy |
|---|---|---|
| Answers | **who** may become this role | **what** the role may do once assumed |
| Here | the EC2 service | read `research-reports` |
| Failure symptom | `AccessDenied ... sts:AssumeRole` | `AccessDenied ... s3:GetObject` |

EC2 can't take a role directly. It takes an **instance profile** that wraps the role:

```console
$ awslocal iam create-instance-profile --instance-profile-name research-ec2-app --query 'InstanceProfile.Arn' --output text
arn:aws:iam::000000000000:instance-profile/research-ec2-app
$ awslocal iam add-role-to-instance-profile --instance-profile-name research-ec2-app --role-name research-ec2-app
```

Assuming the role through STS returns **temporary** credentials that carry an expiry:

```console
$ awslocal sts assume-role --role-arn arn:aws:iam::000000000000:role/research-ec2-app --role-session-name demo --query 'Credentials.[AccessKeyId,Expiration]' --output text
LSIAQAAAAAAALZKNJQMT	2026-10-07T16:42:00.166234Z
```

One hour later those keys are useless, so a leaked copy has a short shelf life. On a real
instance the SDK fetches and refreshes these from the instance metadata service automatically,
and **no key is ever written to disk or into code**. That's why roles beat access keys.

![IAM: a least-privilege policy attached to a group and a role](../screenshots/01-iam-least-privilege-policy.png)
*IAM: a least-privilege policy attached to a group and a role*

---

## Least privilege, and testing it locally

**Least privilege** means granting exactly the actions, on exactly the resources, that a task
needs, and nothing "just in case". The policy above is an example: one bucket, two read
actions. A `"Action": "s3:*", "Resource": "*"` policy would also "work", and would also let a
compromised app delete every bucket in the account.

Normally you verify a policy with the IAM policy simulator. Here is what LocalStack does with
it:

```console
$ awslocal iam simulate-principal-policy --policy-source-arn arn:aws:iam::000000000000:user/research-alice --action-names s3:GetObject s3:ListBucket s3:DeleteObject --resource-arns 'arn:aws:s3:::research-reports/q3.csv' --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output table
-------------------------------------
|      SimulatePrincipalPolicy      |
+------------------+----------------+
|  s3:GetObject    |  explicitDeny  |
|  s3:ListBucket   |  explicitDeny  |
|  s3:DeleteObject |  explicitDeny  |
+------------------+----------------+

$ awslocal iam simulate-custom-policy --policy-input-list file://research-s3-read.json --action-names s3:GetObject s3:DeleteObject --resource-arns 'arn:aws:s3:::research-reports/q3.csv' --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output table

An error occurred (InternalFailure) when calling the SimulateCustomPolicy operation: The simulate_custom_policy action has not been implemented
```

**Both results are wrong, and that's the finding.** Real AWS would answer `allowed` for
`s3:GetObject`. The `ListBucket` row would be `implicitDeny`, because that action is granted on
the *bucket* ARN and the simulation was asked about an *object* ARN. `s3:DeleteObject` would be
`implicitDeny` too (not `explicitDeny`, since no statement denies it; nothing allows it). The
LocalStack simulator returns `explicitDeny` for everything, so it can't be used to test
policies. `simulate-custom-policy` isn't implemented at all.

Then the decisive test: act **as Alice**, with her own access key, and do something her policy
never allows:

```console
$ awslocal s3 mb s3://research-reports && echo 'q3 numbers' | awslocal s3 cp - s3://research-reports/q3.csv
make_bucket: research-reports

$ AWS_ACCESS_KEY_ID=$ALICE_KEY AWS_SECRET_ACCESS_KEY=$ALICE_SECRET awslocal sts get-caller-identity --query Arn --output text
arn:aws:iam::000000000000:user/research-alice

$ AWS_ACCESS_KEY_ID=$ALICE_KEY AWS_SECRET_ACCESS_KEY=$ALICE_SECRET awslocal s3 rm s3://research-reports/q3.csv
delete: s3://research-reports/q3.csv
```

LocalStack knows the caller is Alice, and still lets her delete. **The policy is stored but not
enforced.** Enforcement (`ENFORCE_IAM=1`) is a LocalStack Pro feature. On AWS that `rm` fails
with `AccessDenied`.

What this means in practice: **LocalStack community is good for checking that your IAM
*resources* are well-formed and wired together** (Terraform plans, ARNs, attachments). It **can't
tell you whether a policy is right**. For that you need real AWS (the policy simulator, IAM
Access Analyzer policy validation) or LocalStack Pro.

![IAM: temporary role credentials, and what LocalStack does not enforce](../screenshots/01b-iam-sts-and-enforcement.png)
*IAM: temporary role credentials, and what LocalStack does not enforce*

### Clean-up order matters

```console
$ awslocal iam list-users --query 'length(Users)'; awslocal iam list-policies --scope Local --query 'length(Policies)'
0
0
```

IAM refuses to delete anything that's still attached: a group with members, a role inside an
instance profile, a policy attached somewhere. So teardown runs in reverse: keys → instance
profile → role policies → role → group policies → membership → user → group → policy. The full
sequence is in the transcript. Terraform works this order out for you from the dependency graph.

---

## IAM best practices

| # | Practice | Why |
|---|---|---|
| 1 | **Lock away the root user**: hardware MFA, no access keys, use only for the handful of root-only tasks | root bypasses every IAM policy; an SCP is the only thing that limits it |
| 2 | **Humans use federation/SSO (IAM Identity Center), not IAM users** | central joiner/leaver process, short-lived credentials, no keys on laptops |
| 3 | **Workloads use roles**: instance profiles, IRSA/Pod Identity on EKS, OIDC for GitHub Actions | temporary, auto-rotated credentials; nothing to leak into Git |
| 4 | **MFA everywhere** a human signs in; require it with a condition for sensitive actions | stops the stolen-password case |
| 5 | **Least privilege**: start from nothing, add what the task needs, scope `Resource` to ARNs | limits the blast radius of a compromise |
| 6 | **Permissions via groups/roles, never per-user** | auditable, and a move between teams is one change |
| 7 | **Customer-managed over inline** policies | versioned, reusable, reviewable |
| 8 | **Rotate and remove**: no access keys older than 90 days; delete unused users, roles and keys (use "last accessed" data) | stale credentials are the classic breach path |
| 9 | **Use conditions**: `aws:SourceIp`, `aws:SecureTransport`, `aws:PrincipalOrgID`, `aws:RequestedRegion` | narrows a policy beyond action and resource |
| 10 | **Guardrails at the top**: SCPs and permissions boundaries | even an admin in a member account can't turn off CloudTrail |
| 11 | **Audit**: CloudTrail on in all regions, IAM Access Analyzer, credential report | you can't secure what you can't see |
| 12 | **Test policies on the real evaluator** (policy simulator or Access Analyzer), not an emulator | as shown above |

### Gotchas

- **`AccessDenied` doesn't tell you which policy denied it.** Debug with
  `sts get-caller-identity` (right principal?), then the policy simulator, then CloudTrail's
  `errorCode`/`errorMessage`.
- **Bucket vs object ARN** for S3, as above.
- **IAM is eventually consistent.** A freshly attached policy can take seconds to apply.
  Scripts that create a role and use it immediately sometimes fail on the first try.
- **`NotAction` with `Allow` is dangerous.** It means "everything except", including services
  that don't exist yet.
- **Wildcards in `Principal` on a resource policy** (`"Principal": "*"`) make that resource
  public unless a condition narrows it.

---

## Common use cases

| Use case | IAM construct |
|---|---|
| A team of developers gets read access to logs | group + customer-managed policy |
| An EC2 app reads one S3 bucket | role + instance profile (the lab above) |
| GitHub Actions deploys to AWS with no stored keys | role with an **OIDC** trust policy for `token.actions.githubusercontent.com`, scoped to `repo:<org>/<repo>:ref:refs/heads/main` |
| Pods on EKS each get their own AWS permissions | IRSA / EKS Pod Identity (role per service account) |
| The security team audits a production account | cross-account role assumed from the security account |
| A contractor needs access for two weeks | SSO permission set with session duration limits, removed at the end |
| No one in a sandbox account may launch GPU instances | SCP with `Deny ec2:RunInstances` + condition on `ec2:InstanceType` |
| Terraform runs in CI | dedicated deploy role; state bucket access scoped to its key prefix |

---

## Files

```
01-iam/
├── README.md
├── research-s3-read.json      the least-privilege permission policy
└── research-ec2-trust.json    the EC2 trust policy
../outputs/01-iam.txt          full transcript, including cleanup
../screenshots/01-*.png
```
