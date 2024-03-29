## From bootc OCI image, create an Amazon Machine Image (AMI) and launch an ec2 instance

### Create a custom centos-bootc:stream9 image

#### Configure user in Containerfile with sudo access

The simple way to build a custom OS image with a configured user is to build from this
[Containerfile](../useradd-ssh/Containerfile). A default `exampleuser` with passwordless sudo access is created.

#### Configure machine image with cloud-init

Cloud-init can also be used to add users and configuratiom to an AWS cloud image.
See [the cloud-init example](../cloud-init/Containerfile) for more details.

### Build the bootable OCI image

This example assumes you will deploy on an x86_64 AWS machine.
To build the derived bootc image for x86_64 architecture:

Using the [useradd-ssh/Containerfile](../useradd-ssh/Containerfile):

```
cd useradd-ssh
podman build --build-arg "sshpubkey=$(cat ~/.ssh/id_rsa.pub)" --platform linux/amd64 -t quay.io/yourrepo/youros:tag .
podman push quay.io/yourrepo/youros:tag
```

### Run bootc-image-builder to create an AMI from a bootc OCI image

Notice here we are adding the `--target-arch x86_64` since we built an `x86_64 (amd64)` bootc image above.

`bootc-image-builder` will use your aws credentials to push and register an AMI after building it.
This command will build an AMI and upload the AMI to a given AWS s3 bucket. The bucket must exist within
your AWS account.

```
 $ sudo podman run \
  --rm \
  -it \
  --privileged \
  --pull=newer \
  -v $HOME/.aws:/root/.aws:ro \
  --env AWS_PROFILE=default \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type ami \
  --aws-ami-name centos-bootc-x86 \
  --aws-bucket centos-bootc-bucket \
  --aws-region us-east-1 \
  --target-arch x86_64 \
quay.io/yourrepo/youros:tag
```

### Launch an ec2 instance with terraform

This assumes an AMI `centos-bootc-x86` exists in your AWS account and
you have terraform and AWS CLI `aws` installed on your local system.
There is a sample [terraform file](./terraform/main.tf). Customize this
based on the AWS account details. The example assumes a user `exampleuser` is configured.
Then:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

#### Accessing the instance

```bash
ssh -i /path/to/private/ssh-key exampleuser@ip-address
```

#### Destroying instance and associated AWS resources (will not destroy the AMI)

```bash
terraform destroy
```

### AMI & partitioning note

Workaround for this issue: https://github.com/osbuild/bootc-image-builder/issues/52 where filesystem size doesn't match
root disk size of your ec2-instance:

With this change, https://github.com/CentOS/centos-bootc/pull/397
you can now use growpart like so:

```bash
$ ssh exampleuser@IP-address
bash-5.1# sudo su
bash-5.1# lsblk
NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
loop0         7:0    0   7.5M  1 loop
zram0       252:0    0     8G  0 disk [SWAP]
nvme0n1     259:0    0    90G  0 disk
├─nvme0n1p1 259:2    0     1M  0 part
├─nvme0n1p2 259:3    0   501M  0 part /boot/efi
├─nvme0n1p3 259:4    0     1G  0 part /boot
└─nvme0n1p4 259:5    0   8.5G  0 part /var
                                      /sysroot/ostree/deploy/default/var
                                      /etc
                                      /sysroot
bash-5.1# growpart /dev/nvme0n1 4
CHANGED: partition=4 start=3127296 old: size=17844191 end=20971486 new: size=185616351 end=188743646

bash-5.1# lsblk
NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
loop0         7:0    0   7.5M  1 loop
zram0       252:0    0     8G  0 disk [SWAP]
nvme0n1     259:0    0    90G  0 disk
├─nvme0n1p1 259:2    0     1M  0 part
├─nvme0n1p2 259:3    0   501M  0 part /boot/efi
├─nvme0n1p3 259:4    0     1G  0 part /boot
└─nvme0n1p4 259:5    0  88.5G  0 part /var
                                      /sysroot/ostree/deploy/default/var
                                      /etc
                                      /sysroot
```
