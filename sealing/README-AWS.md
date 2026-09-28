# Sealed bootc on AWS EC2

This document describes how to test a sealed bootc image on AWS EC2 with
UEFI Secure Boot.  The flow builds a disk image locally, uploads it to
AWS, registers it as an AMI with custom UEFI Secure Boot keys, launches
an EC2 instance, and verifies that the root filesystem is mounted as
composefs with `verity=require`.

## Quick start

```bash
just aws-test
```

This runs the full chain: build, create disk, upload to S3, import
snapshot, register AMI with UEFI Secure Boot keys, launch instance,
verify composefs, and clean up all AWS resources.

## Prerequisites

### Tools

| Tool | Purpose | Install |
|------|---------|---------|
| `aws` | AWS CLI | [Install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| `jq` | JSON processing | `dnf install jq` |
| `bcvk` | Disk image creation | [github.com/bootc-dev/bcvk](https://github.com/bootc-dev/bcvk) |
| `cert-to-efi-sig-list` | Convert PEM certs to EFI Signature Lists | `dnf install efitools` |
| `uefivars` | Generate AWS UEFI variable store blobs | `pip install git+https://github.com/awslabs/python-uefivars.git` |
| `podman` | Container image build | `dnf install podman` |
| `openssl` | Key generation | `dnf install openssl` |

The `just _check-aws-deps` recipe (run automatically at the start of
every AWS recipe) will verify all tools are present and provide install
hints for any that are missing.

### AWS credentials

Your AWS credentials must be configured.  Any method supported by the AWS
CLI works (environment variables, `~/.aws/credentials`, SSO, instance
profile, etc.).  Verify with:

```bash
aws sts get-caller-identity
```

### IAM: the `vmimport` service role

AWS VM Import/Export requires an IAM role named `vmimport` in your account.
This is a **one-time per-account setup** -- the recipes will not create it
for you.  It may already exist if anyone in your AWS organization has
previously used VM Import/Export.  Check with:

```bash
aws iam get-role --role-name vmimport
```

If the role exists, skip this section.  If not, create it:

1. Create `trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "vmie.amazonaws.com" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:Externalid": "vmimport"
        }
      }
    }
  ]
}
```

2. Create the role:

```bash
aws iam create-role --role-name vmimport \
    --assume-role-policy-document file://trust-policy.json
```

3. Create `role-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:ModifySnapshotAttribute",
        "ec2:CopySnapshot",
        "ec2:RegisterImage",
        "ec2:Describe*"
      ],
      "Resource": "*"
    }
  ]
}
```

4. Attach the policy:

```bash
aws iam put-role-policy --role-name vmimport \
    --policy-name vmimport \
    --policy-document file://role-policy.json
```

**Note:** S3 access for the `vmimport` role is handled automatically by
the `aws-upload` recipe, which applies a bucket policy granting the role
`s3:GetObject` and `s3:GetBucketLocation` on the upload bucket.  If you
provide your own bucket via `AWS_S3_BUCKET`, the calling IAM user needs
`s3:PutBucketPolicy` permission on that bucket, or you must configure
access to the bucket for the `vmimport` role yourself.

For full details see the
[AWS VM Import/Export documentation](https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html#vmimport-role).

## Environment variables

All environment variables are optional.  Sensible defaults are used when
they are not set.

| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_REGION` | From `aws configure get region` | AWS region for all operations |
| `AWS_S3_BUCKET` | Auto-create ephemeral bucket | S3 bucket for disk image upload.  If not set, a temporary bucket is created and destroyed during cleanup. |
| `AWS_INSTANCE_TYPE` | `m5.large` | EC2 instance type (must support UEFI boot mode) |
| `AWS_SUBNET_ID` | First default subnet | Subnet to launch the instance in |
| `AWS_SECURITY_GROUP_ID` | Auto-create ephemeral SG | Security group with SSH access.  If not set, a temporary SG is created in the default VPC. |
| `AWS_SSH_USER` | `cloud-user` | SSH username (cloud-init default for RHEL) |

## Recipes

The recipes form a dependency chain.  Each step is idempotent -- it
checks whether its output already exists before doing work.  If a step
fails, re-running the same (or a downstream) recipe resumes from the
point of failure.

```
aws-test
  \-- aws-launch         Launch instance, wait for SSH
        \-- aws-register  Register AMI with UEFI Secure Boot keys
              \-- aws-import   Import EBS snapshot from S3
                    \-- aws-upload  Upload raw disk to S3
                          \-- aws-disk   Create raw disk via bcvk to-disk
                                \-- aws-build  Build AWS container image
                                      \-- _check-aws-deps
```

| Recipe | Description |
|--------|-------------|
| `just aws-build` | Build the sealed container image with `cloud-init` and `ttyS0` console |
| `just aws-disk` | Create a raw disk image from the container image |
| `just aws-upload` | Upload the disk image to S3 |
| `just aws-import` | Import the S3 object as an EBS snapshot |
| `just aws-register` | Generate UEFI variable store blob and register an AMI |
| `just aws-launch` | Create key pair, security group, and launch an EC2 instance |
| `just aws-ssh` | Open an interactive SSH session to the running instance |
| `just aws-test` | Run the full chain, verify composefs, and clean up on exit |
| `just aws-clean` | Tear down all AWS resources tracked in `target/aws-resources.json` |

### Running individual steps

You can run any step individually.  For example, to just build the disk
image without touching AWS:

```bash
just aws-disk
# output: target/aws-disk.raw
```

Or to upload and import without launching:

```bash
just aws-import
```

### Manual cleanup

If something goes wrong and the automatic cleanup in `aws-test` does not
run (e.g., the process was killed), you can clean up manually:

```bash
just aws-clean
```

This reads `target/aws-resources.json` and tears down all tracked
resources in the correct order.

## How it works

### Image differences from the local (bcvk) build

The AWS image is built from the same Containerfile with two overrides:

- `--build-arg console_kargs="console=ttyS0,115200"` -- EC2 x86_64
  instances use `ttyS0` for serial console (the local build uses `hvc0`)
- `--build-arg extra_packages="cloud-init"` -- Enables SSH key injection
  via EC2 instance metadata

These arguments are baked into the signed UKI at build time, so the AWS
image has a different composefs digest than the local image.

### UEFI Secure Boot on EC2

EC2 supports UEFI Secure Boot, but the custom keys used to sign our
bootloader and UKI must be enrolled in the UEFI variable store.  The
recipes handle this using
[python-uefivars](https://github.com/awslabs/python-uefivars) from AWS
Labs:

1. Our PK, KEK, and db certificates are converted to EFI Signature Lists
   using `cert-to-efi-sig-list` (from `efitools`)
2. `uefivars` assembles these into an AWS-format UEFI variable store blob
3. The blob is passed to `aws ec2 register-image --uefi-data` when
   registering the AMI

This follows
[AWS documentation for custom UEFI Secure Boot keys](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-ami-with-uefi-secure-boot.html)
(Option B: pre-filled variable store).

### State tracking

All created AWS resources are tracked in `target/aws-resources.json`.
This file maps resource types to their IDs and records whether ephemeral
resources (S3 bucket, security group) were created by the recipes or
provided by the user.  The `aws-clean` recipe reads this file to
determine what to tear down.

## Troubleshooting

### "IAM role 'vmimport' not found"

You need to create the vmimport service role.  See the
[IAM setup section](#iam-the-vmimport-service-role) above.

### "No default VPC found"

Your AWS account does not have a default VPC in the configured region.
Either create one or set `AWS_SECURITY_GROUP_ID` and `AWS_SUBNET_ID` to
point to existing resources.

### Snapshot import is slow

The `import-snapshot` step typically takes 5-15 minutes depending on disk
image size and AWS region load.  The recipe polls every 15 seconds and
prints progress.

### SSH timeout

If SSH does not become available within 10 minutes, cloud-init may have
failed or the security group may not allow SSH.  Check:
- The security group allows TCP port 22 inbound
- The instance has a public IP (requires a subnet with auto-assign public IP)
- cloud-init logs on the instance via EC2 serial console

### Instance type does not support UEFI

Not all instance types support UEFI boot mode.  The default `m5.large`
does.  See the
[AWS documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/launch-instance-boot-mode.html)
for a list of supported types.
