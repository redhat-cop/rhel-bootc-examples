# A cloud-init image

This container image [Containerfile](Containerfile) builds on top of the
[base image](github.com/centos/centos-bootc) and adds cloud-init.  It
can be used in any virtualization/IaaS system that is
[supported by cloud-init](https://cloudinit.readthedocs.io/en/latest/reference/datasources.html)
such as [libvirt](https://blog.wikichoon.com/2020/09/virt-install-cloud-init.html),
AWS, etc.

A good example reference for cloud-init is
[the RHEL documentation](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_cloud-init_for_rhel_9/introduction-to-cloud-init_cloud-content).

### Available images

- quay.io/bootc-org/examples/cloud-init:latest

### Unpacking the disk image using oras

The [oras](https://oras.land/) project offers a handy CLI tool that can be used
like this:

```text
$ oras pull ghcr.io/centos/fedora-bootc-cloud-disk:eln
...
Pulled ghcr.io/centos/fedora-bootc-cloud-disk:eln
Digest: sha256:2bd73cc3589f6c7c28d7335a704133fd08526e4c0197a3ae038f1821c736c144
$ zstd -d fedora-bootc-cloud-eln.qcow2.zst
```

### Unpacking using skopeo

It's more common to have `skopeo` instead of `oras`, but unfortunately the ergonomics
here are currently atrocious:

```text
$ skopeo copy docker://ghcr.io/centos/fedora-bootc-cloud-disk:eln oci:disk
Getting image source signatures
Copying blob da734940e022 done
Copying config 44136fa355 done
Writing manifest to image destination
$ find disk/blobs/ -type f -size -5M | xargs -r rm
$ mv disk/blobs/sha256/* fedora-bootc-cloud-eln.qcow2.zst
$ rm -rf disk
$ zstd -d fedora-bootc-cloud-eln.qcow2.zst
fedora-bootc-cloud-eln.qcow2.zst: 790560768 bytes
$
```

## Example virt-install invocation

This is one example:

```bash
virt-install --cloud-init root-ssh-key=/path/to/your/ssh/key  --connect qemu:///system --import --name fedora-bootc-cloud --memory 4096 --disk /path/to/fedora-bootc-cloud-eln.qcow2 --os-variant rhel9-unknown
```

## Known bugs

Because today `virt-install` appears to remove the cloud-init ISO, this will
cause `cloud-init` to hang for several minutes on subsequent boots. To work
around this right now, `rm /etc/systemd/system/cloud-init.target.wants/*` in the
firstboot.
