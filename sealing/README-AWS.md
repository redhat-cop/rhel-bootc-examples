# Sealed bootc on AWS EC2

This document describes how to test a sealed bootc image on AWS EC2 with
UEFI Secure Boot.  The flow builds a disk image locally, uploads it
directly as an EBS snapshot, registers it as an AMI with custom UEFI
Secure Boot keys, launches an EC2 instance, and verifies that the root
filesystem is mounted as composefs with `verity=require`.

## Quick start

```bash
just keygen
just aws-test
```

This runs the full chain: build, create disk, upload snapshot via
coldsnap, register AMI with UEFI Secure Boot keys, launch instance,
verify composefs, and clean up all AWS resources.

## Prerequisites

### Tools

| Tool | Purpose | Install |
|------|---------|---------|
| `aws` | AWS CLI | [Install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| `jq` | JSON processing | `dnf install jq` |
| `bcvk` | Disk image creation | [github.com/bootc-dev/bcvk](https://github.com/bootc-dev/bcvk) |
| `coldsnap` | Upload disk images as EBS snapshots | `cargo install --locked coldsnap` (requires `cargo`: `dnf install cargo`) |
| `cert-to-efi-sig-list` | Convert PEM certs to EFI Signature Lists | `dnf install efitools` |
| `uefivars` | Generate AWS UEFI variable store blobs | `pip install git+https://github.com/awslabs/python-uefivars.git` (requires `pip`: `dnf install python3-pip`) |
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

## Environment variables

All environment variables are optional.  Sensible defaults are used when
they are not set.

| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_REGION` | From `aws configure get region` | AWS region for all operations |
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
  \-- aws-launch           Launch instance, wait for SSH
        \-- aws-register    Register AMI with UEFI Secure Boot keys
              \-- aws-snapshot  Upload raw disk as EBS snapshot via coldsnap
                    \-- aws-disk     Create raw disk via bcvk to-disk
                          \-- aws-build   Build AWS container image
                                \-- _check-aws-deps
```

| Recipe | Description |
|--------|-------------|
| `just aws-build` | Build the sealed container image with `cloud-init` and `ttyS0` console |
| `just aws-disk` | Create a raw disk image from the container image |
| `just aws-snapshot` | Upload the disk image directly as an EBS snapshot via coldsnap |
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

Or to create the snapshot without launching:

```bash
just aws-snapshot
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

### Snapshot upload with coldsnap

The raw disk image is uploaded directly as an EBS snapshot using
[coldsnap](https://github.com/awslabs/coldsnap), a CLI tool from AWS
Labs that uses the EBS direct APIs (`ebs:StartSnapshot`,
`ebs:PutSnapshotBlock`, `ebs:CompleteSnapshot`).  This bypasses the
traditional VM Import/Export path (`aws ec2 import-snapshot`), which
requires an S3 bucket, the `vmimport` IAM service role, and
`iam:PassRole` permission -- none of which are needed with coldsnap.

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
resources (security group) were created by the recipes or provided by
the user.  The `aws-clean` recipe reads this file to determine what to
tear down.

## Troubleshooting

### "No default VPC found"

Your AWS account does not have a default VPC in the configured region.
Either create one or set `AWS_SECURITY_GROUP_ID` and `AWS_SUBNET_ID` to
point to existing resources.

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
