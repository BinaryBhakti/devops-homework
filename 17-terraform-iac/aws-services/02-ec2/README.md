# 02 — EC2: Elastic Compute Cloud (Compute)

**EC2 rents you virtual machines (instances) by the second.** You choose what they boot from
(**AMI**), how big they are (**instance type**), how you log in (**key pair**), what traffic can
reach them (**security group**), and what disks they have (**EBS**). AWS runs the hypervisor,
the hardware and the data centre.

The practical parts ran against **LocalStack 4.14.0** (community). All output blocks are
verbatim from [`../outputs/02-ec2.txt`](../outputs/02-ec2.txt).

> **LocalStack EC2 is a mock.** The API behaves like EC2: IDs, states, IPs, volumes,
> attachments. But **no virtual machine exists**, there's nothing to SSH into, and the IPs
> route nowhere. That's proven at the end of the lifecycle section. It's good for learning the
> API and testing Terraform, but not for testing what runs *on* an instance.

---

## Where EC2 sits

```
 Region us-east-1
 └── VPC 172.31.0.0/16 (default VPC)
     └── Subnet (one AZ, e.g. us-east-1a)
         └── ENI (network interface) ── private IP 10.x.x.x, optional public IP
             │        └── Security Group(s)  ← stateful firewall
             └── EC2 instance  (AMI + instance type + key pair + IAM instance profile)
                     ├── root EBS volume  /dev/sda1  (from the AMI's snapshot)
                     └── data EBS volume  /dev/sdf   (created + attached separately)
```

---

## AMI: Amazon Machine Image

An AMI is the **template disk image plus launch metadata** an instance boots from: OS, any
preinstalled software, architecture (`x86_64`/`arm64`), virtualisation type, and the snapshot
behind the root volume.

```console
$ awslocal ec2 describe-images --query 'length(Images)'
1159
$ awslocal ec2 describe-images --filters 'Name=name,Values=ubuntu*' --query 'Images[:4].[ImageId,Name,Architecture]' --output table
-----------------------------------------------------------------------------------------------
|                                       DescribeImages                                        |
+--------------+-------------------------------------------------------------------+----------+
|  ami-1e749f67|  ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-20170727  |  x86_64  |
|  ami-785db401|  ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-20170721  |  x86_64  |
+--------------+-------------------------------------------------------------------+----------+
```

| Kind | Source | Example |
|---|---|---|
| AWS-provided | Amazon | Amazon Linux 2023, Windows Server |
| Marketplace | vendors, sometimes with a licence fee | hardened CIS images, firewalls |
| Community | anyone, publicly shared | Ubuntu (Canonical publishes these) |
| Your own ("golden AMI") | `create-image` from a configured instance, or built with Packer | the app pre-baked, so boot is fast |

**AMI IDs are per region.** The same Ubuntu release has a different `ami-…` in every region,
which is why Terraform code looks AMIs up with a `data "aws_ami"` filter, or reads them from
SSM public parameters, instead of hard-coding IDs. (LocalStack's catalogue is a fixed list of
old real IDs, as the 2017 Ubuntu builds above show.)

---

## Instance types

The name encodes the shape: **`m5.xlarge`** is family `m` (general purpose), generation `5`,
size `xlarge`. Suffix letters add attributes: `g` Graviton/arm64, `a` AMD, `n` faster
networking, `d` local NVMe.

```console
$ awslocal ec2 describe-instance-types --instance-types t3.micro t3.large m5.xlarge c5.2xlarge r5.large --query 'InstanceTypes[].[InstanceType,VCpuInfo.DefaultVCpus,MemoryInfo.SizeInMiB]' --output table
------------------------------
|    DescribeInstanceTypes   |
+-------------+----+---------+
|  c5.2xlarge |  8 |  16384  |
|  m5.xlarge  |  4 |  16384  |
|  r5.large   |  2 |  16384  |
|  t3.large   |  2 |  8192   |
|  t3.micro   |  2 |  1024   |
+-------------+----+---------+
```

Read across the rows. `c5.2xlarge` and `m5.xlarge` have the same 16 GiB, but the compute family
gives you twice the vCPUs. `r5.large` puts 16 GiB behind just 2 vCPUs, which is the
memory-optimised ratio.

| Family | Optimised for | vCPU : GiB | Typical workload |
|---|---|---|---|
| **T** (t3, t4g) | burstable: earns CPU credits while idle, spends them under load | varies | dev boxes, small sites, low-traffic APIs |
| **M** (m5, m7g) | general purpose, balanced | 1 : 4 | app servers, most things |
| **C** (c5, c7g) | compute | 1 : 2 | batch, encoding, CI runners, game servers |
| **R / X** | memory | 1 : 8 and up | in-memory caches, big databases |
| **I / D** | storage (local NVMe) | — | high-IOPS databases, Kafka |
| **P / G / Inf / Trn** | accelerators | — | ML training and inference, graphics |

**Gotcha: T-family credits.** A `t3` running flat-out spends its credits and is throttled to
its baseline (10% for `t3.micro`), unless it's in `unlimited` mode, which bills the surplus.
"The server got slow every afternoon" is often this.

---

## Key pairs

```console
$ awslocal ec2 create-key-pair --key-name research-key --query 'KeyMaterial' --output text > research-key.pem && chmod 400 research-key.pem && head -1 research-key.pem && ls -l research-key.pem | awk '{print $1, $NF}'
-----BEGIN RSA PRIVATE KEY-----
-r--------@ research-key.pem
$ awslocal ec2 describe-key-pairs --key-names research-key --query 'KeyPairs[].[KeyName,KeyFingerprint]' --output text
research-key	62:ea:c0:68:b9:a1:5b:b1:ee:a1:69:f0:c9:a9:fb:d2:bb:4d:04:ef
```

- AWS keeps **only the public key** and installs it in `~/.ssh/authorized_keys` on first boot
  (via cloud-init).
- The private key is shown **exactly once**, at creation. Lose it and you can't recover it.
  You need a new key pair, and a way to put its public key onto the instance.
- `chmod 400` isn't optional: `ssh` refuses a private key that others can read
  ("UNPROTECTED PRIVATE KEY FILE").
- The modern alternative is **no key pair at all**: SSM Session Manager or EC2 Instance Connect,
  so port 22 is never opened.

---

## Security groups

A security group is a **stateful, allow-only** firewall attached to an instance's network
interface (ENI).

```console
$ awslocal ec2 create-security-group --group-name research-web-sg --description 'web: 22 from one IP, 80 from anywhere' --query GroupId --output text
sg-0141c9c4729b69695
$ SG=$(awslocal ec2 describe-security-groups --group-names research-web-sg --query 'SecurityGroups[0].GroupId' --output text)
awslocal ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 22 --cidr 203.0.113.10/32 --query 'SecurityGroupRules[].[IpProtocol,FromPort,CidrIpv4]' --output text
awslocal ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 80 --cidr 0.0.0.0/0 --query 'SecurityGroupRules[].[IpProtocol,FromPort,CidrIpv4]' --output text
tcp	22	203.0.113.10/32
tcp	80	0.0.0.0/0
$ awslocal ec2 describe-security-groups --group-names research-web-sg --query 'SecurityGroups[0].{in:IpPermissions[].[FromPort,IpRanges[0].CidrIp],out:IpPermissionsEgress[].[IpProtocol,IpRanges[0].CidrIp]}' --output json
{
    "in": [
        [
            22,
            "203.0.113.10/32"
        ],
        [
            80,
            "0.0.0.0/0"
        ]
    ],
    "out": [
        [
            "-1",
            "0.0.0.0/0"
        ]
    ]
}
```

| Property | Meaning |
|---|---|
| **Default inbound** | nothing allowed; every rule you add is an `allow` |
| **Default outbound** | the `"-1", "0.0.0.0/0"` rule above means all protocols, anywhere |
| **Stateful** | the reply to an allowed request is allowed back automatically, so no ephemeral-port rules |
| **No deny rules** | to block one bad IP you need a network ACL (see [04-vpc](../04-vpc)) |
| **Source can be another SG** | "allow 5432 from `sg-app`" means *any instance in the app tier*, however IPs change. This is the right way to wire tiers |

SSH here is open only to one `/32`. `22` open to `0.0.0.0/0` is the single most common EC2
finding in every security scanner.

---

## Launching, and public vs private IP

```console
$ AMI=$(awslocal ec2 describe-images --filters 'Name=name,Values=ubuntu*' --query 'Images[0].ImageId' --output text)
awslocal ec2 run-instances --image-id $AMI --instance-type t3.micro --key-name research-key --security-groups research-web-sg --count 1 --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=research-web}]' --query 'Instances[0].[InstanceId,State.Name,InstanceType]' --output text
i-fd2b36145f2fa992a	pending	t3.micro
$ ID=$(awslocal ec2 describe-instances --filters Name=tag:Name,Values=research-web Name=instance-state-name,Values=pending,running --query 'Reservations[0].Instances[0].InstanceId' --output text)
awslocal ec2 describe-instances --instance-ids $ID --query 'Reservations[0].Instances[0].{id:InstanceId,state:State.Name,privateIp:PrivateIpAddress,publicIp:PublicIpAddress,privateDns:PrivateDnsName,subnet:SubnetId,rootDevice:RootDeviceName}' --output json
{
    "id": "i-fd2b36145f2fa992a",
    "state": "running",
    "privateIp": "10.150.115.112",
    "publicIp": "54.214.69.239",
    "privateDns": "ip-10-150-115-112.ec2.internal",
    "subnet": "subnet-f74bec6ce228388c8",
    "rootDevice": "/dev/sda1"
}
```

Every instance gets a **private IP** from its subnet's range. That address is used for all
traffic inside the VPC. It may also get a **public IP**, if the subnet auto-assigns one. Then
watch what happens across a stop/start:

```console
$ AMI=$(awslocal ec2 describe-images --filters 'Name=name,Values=ubuntu*' --query 'Images[0].ImageId' --output text)
ID=$(awslocal ec2 run-instances --image-id $AMI --instance-type t3.micro --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=research-ip}]' --query 'Instances[0].InstanceId' --output text)
q() { awslocal ec2 describe-instances --instance-ids $ID --query 'Reservations[0].Instances[0].[State.Name,PrivateIpAddress,PublicIpAddress]' --output text; }
echo "before stop : $(q)"
awslocal ec2 stop-instances --instance-ids $ID >/dev/null; echo "stopped     : $(q)"
awslocal ec2 start-instances --instance-ids $ID >/dev/null; echo "after start : $(q)"
awslocal ec2 terminate-instances --instance-ids $ID >/dev/null; echo "terminated  : $(q)"
before stop : running	10.41.196.65	54.214.202.211
stopped     : stopped	10.41.196.65	None
after start : running	10.41.196.65	54.214.69.232
terminated  : terminated	10.41.196.65	None
```

**The private IP survives. The public IP is released on stop, and a different one is assigned on
start** (`…202.211` became `…69.232`). Anything that pinned the old address (a DNS A record, a
partner's firewall allow-list) is now broken.

| | Private IP | Auto-assigned public IP | Elastic IP |
|---|---|---|---|
| Reachable from | inside the VPC (and peered/VPN networks) | the internet, through the IGW | the internet |
| Survives stop/start | **yes** | **no**, a new one each start | **yes**, it's yours until released |
| Cost | free | charged per hour (since Feb 2024, all public IPv4 is billed) | charged per hour, attached or not |
| Seen by the instance OS | yes, on `eth0` | **no**, it's 1:1 NAT at the internet gateway | no, same NAT |

The last row surprises people: `ip addr` on an EC2 instance never shows the public IP, because
the internet gateway translates it. That's covered in [04-vpc](../04-vpc).

![EC2: key pair, security group, launch](../screenshots/02-ec2-sg-and-launch.png)
*EC2: key pair, security group, launch*

---

## EBS: Elastic Block Store

EBS volumes are **network-attached block devices**. The disk isn't in the host, so it survives
the instance, can be detached and re-attached, and can be snapshotted to S3.

```console
$ awslocal ec2 describe-volumes --query 'Volumes[].[VolumeId,Size,VolumeType,State,Attachments[0].Device]' --output table
--------------------------------------------------------------
|                       DescribeVolumes                      |
+------------------------+----+------+---------+-------------+
|  vol-0dbb8f846e8d3d1d6 |  8 |  gp2 |  in-use |  /dev/sda1  |
+------------------------+----+------+---------+-------------+
$ AZ=$(awslocal ec2 describe-instances --filters Name=tag:Name,Values=research-web --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text); echo AZ=$AZ
VOL=$(awslocal ec2 create-volume --availability-zone $AZ --size 20 --volume-type gp3 --query VolumeId --output text); echo created $VOL
ID=$(awslocal ec2 describe-instances --filters Name=tag:Name,Values=research-web --query 'Reservations[0].Instances[0].InstanceId' --output text)
awslocal ec2 attach-volume --volume-id $VOL --instance-id $ID --device /dev/sdf --query '[Device,State]' --output text
AZ=us-east-1a
created vol-b78515a4e2660568e
/dev/sdf	attaching
$ awslocal ec2 describe-volumes --query 'Volumes[].[VolumeId,Size,VolumeType,State,Attachments[0].Device]' --output table
---------------------------------------------------------------
|                       DescribeVolumes                       |
+------------------------+-----+------+---------+-------------+
|  vol-0dbb8f846e8d3d1d6 |  8  |  gp2 |  in-use |  /dev/sda1  |
|  vol-b78515a4e2660568e |  20 |  gp3 |  in-use |  /dev/sdf   |
+------------------------+-----+------+---------+-------------+
```

Note why the script looks up the instance's AZ first: **an EBS volume lives in one Availability
Zone and can only attach to an instance in the same AZ.** To move data across AZs, snapshot it
(snapshots are regional) and create a new volume from the snapshot.

| Type | Media | Use | Note |
|---|---|---|---|
| **gp3** | SSD | default for almost everything | 3,000 IOPS / 125 MB/s baseline, tunable separately from size. ~20% cheaper than gp2 |
| gp2 | SSD | legacy default (the root volume above) | IOPS tied to size (3/GiB), so people over-provision GiB to get IOPS |
| **io2 / io2 Block Express** | SSD | databases that need guaranteed IOPS | provisioned IOPS, 99.999% durability, multi-attach |
| st1 | HDD | big sequential throughput: logs, data lakes | can't be a boot volume |
| sc1 | HDD | cold, rarely read | cheapest |
| *Instance store* | local NVMe | scratch, caches | **not EBS**: physically in the host, **lost on stop** |

**Delete on termination:** the root volume defaults to `DeleteOnTermination=true`. Volumes you
attach later default to `false`. After the instance below was terminated, the root volume had
gone with it:

```console
$ awslocal ec2 describe-volumes --query 'Volumes[].[VolumeId,Size,State]' --output text; echo "volumes: $(awslocal ec2 describe-volumes --query 'length(Volumes)')"
volumes: 0
```

(The 20 GiB data volume had already been deleted explicitly during cleanup, before this check.
On AWS a detached data volume stays, and keeps billing, until you delete it. Orphaned volumes
are a classic line on the bill.)

---

## The instance lifecycle

```
                 run-instances
                      │
                  ┌───▼────┐
                  │pending │
                  └───┬────┘
                      │                       reboot (same host, same IPs, RAM lost)
                  ┌───▼────┐ ◄───────────────────────┐
     ┌──────────► │running │ ────────────────────────┘
     │            └─┬───┬──┘
     │      stop    │   │  terminate
     │         ┌────▼─┐ └───────────────────┐
     │         │stopping                    │
     │         └────┬─┘                ┌────▼───────┐
     │         ┌────▼──┐ terminate     │shutting-down│
     └─start── │stopped│ ─────────────►└────┬───────┘
  (new host,   └───────┘                ┌────▼─────┐
   new public IP;                       │terminated│  (visible ~1 h, then gone; irreversible)
   EBS kept; billing for                └──────────┘
   compute stops)
```

```console
$ ID=$(awslocal ec2 describe-instances --filters Name=tag:Name,Values=research-web --query 'Reservations[0].Instances[0].InstanceId' --output text)
awslocal ec2 stop-instances --instance-ids $ID --query 'StoppingInstances[0].[PreviousState.Name,CurrentState.Name]' --output text
awslocal ec2 describe-instances --instance-ids $ID --query 'Reservations[0].Instances[0].State.Name' --output text
awslocal ec2 start-instances --instance-ids $ID --query 'StartingInstances[0].[PreviousState.Name,CurrentState.Name]' --output text
awslocal ec2 describe-instances --instance-ids $ID --query 'Reservations[0].Instances[0].State.Name' --output text
awslocal ec2 terminate-instances --instance-ids $ID --query 'TerminatingInstances[0].[PreviousState.Name,CurrentState.Name]' --output text
running	stopping
stopped
stopped	pending
running
running	shutting-down
$ awslocal ec2 describe-instances --filters Name=tag:Name,Values=research-web --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text
i-fd2b36145f2fa992a	terminated
```

Each API call returns a `[previous, current]` pair. The transitional states (`stopping`,
`pending`, `shutting-down`) take seconds to minutes on AWS. LocalStack moves through them
instantly.

| Action | Compute billed? | EBS billed? | RAM | Public IP | Instance-store data |
|---|---|---|---|---|---|
| reboot | yes | yes | lost | **kept** | kept |
| stop → start | not while stopped | **yes** | lost | **changes** | **lost** |
| hibernate | not while stopped | yes (RAM is saved to root EBS) | restored | changes | lost |
| terminate | no | root deleted by default | — | released | lost |

And the proof that nothing really ran:

```console
$ docker ps --format '{{.Names}}  {{.Image}}' | grep -iv minikube
localstack  localstack/localstack:4.14.0
sst-mess-db  postgres:17-alpine
booking-prod-db  postgres:16-alpine
```

Two instances "ran" in this lab, and the only process involved is the LocalStack container.
EC2 here is state in a mock, not a VM.

![EC2: EBS volumes, the instance lifecycle, public vs private IP](../screenshots/02b-ec2-ebs-lifecycle-ips.png)
*EC2: EBS volumes, the instance lifecycle, public vs private IP*

---

## Buying options (cost)

| Option | Discount vs on-demand | Commitment | Good for |
|---|---|---|---|
| On-Demand | — | none | spiky, short-lived, unknown |
| Savings Plans / Reserved | up to ~72% | 1 or 3 years of $/hour | the steady baseline |
| **Spot** | up to ~90% | none, but AWS can reclaim with **2 minutes' notice** | stateless, fault-tolerant: CI, batch, k8s workers |
| Dedicated Hosts | — | — | licensing tied to physical cores |

---

## Common use cases

| Use case | Typical setup |
|---|---|
| Web/app servers | Auto Scaling Group across 2+ AZs behind an Application Load Balancer, built from a golden AMI |
| Kubernetes worker nodes | EKS managed node groups (often a Spot + On-Demand mix) |
| CI/CD runners | self-hosted GitHub Actions runners on Spot `c`-family |
| Lift-and-shift legacy apps | one instance per old VM, EBS for state, snapshots for backup |
| Bastion / jump host | tiny `t` instance in a public subnet, or better, none at all, using SSM Session Manager |
| HPC / ML training | `c`/`p`/`trn` families in a cluster placement group |
| Self-managed databases | `r`/`i` family + io2, when RDS doesn't support the engine or version |

---

## Files

```
02-ec2/README.md
../outputs/02-ec2.txt           full transcript, including cleanup
../screenshots/02-*.png
```
