# RHEL bootc examples

Welcome to the examples repository for RHEL bootc (image mode for RHEL)!

The `registry.redhat.io/rhel10/rhel-bootc:10.1` (and `rhel9/rhel-bootc:9.4`)
container images represent a mechanism to configure Red Hat Enterprise Linux
as a container image. For full documentation see the [Red Hat image mode for
RHEL guide](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/index).

You can define your systems via a container build, generate
disk images from the containers or deploy them directly via
Anaconda or `bootc install`.

Thereafter, the systems can be upgraded in-place with
transactional updates/rollbacks and maintained in a git-ops
fashion, or with live changes applied out of band.

This git repository contains just a few representative
examples of configuring a Linux system via containers.

## Building

A root `Justfile` is provided. To build a single example:

```
just build <example>
```

To build all examples that contain a `Containerfile`:

```
just build-all
```

If an example subdirectory has its own `Justfile` (e.g. for passing secrets),
its `build` recipe is used instead of a plain `podman build`.

## General guidance

A very significant percentage of Linux system configuration
boils down to writing configuration files.  For example,
kernel parameters can be changed by writing to `/usr/lib/sysctl.d`.

In general, configuration like this will Just Work when
done in a container build.

As a result, this example repository focuses on two things:

- Additional software patterns (especially for public clouds)
- Subtle and less obvious cases, such as SSH key management

## Examples

### Systems management

- [insights](insights) - Configure the booted container to register to Insights

### Systems configuration

- [container-auth](container-auth) - Currently, authentication file locations
  for `bootc` and `podman` differ, and there are some subtleties in the `podman`
  location; this writes a pull secret to a central location embedded in the container
  (underneath `/usr` as part of the immutable state).

### Cloud and virtualization

- [aws](aws) - AWS: adds cloud-init for instance metadata (SSH keys, etc.)
- [azure](azure) - Azure: adds cloud-init and Azure-specific configuration
- [gcp](gcp) - Google Cloud Platform: adds GCP guest packages and cloud-init
- [openstack](openstack) - OpenStack: adds cloud-init
- [cloud-init](cloud-init) - Generic cloud-init example for other hypervisors/clouds
- [kubevirt](kubevirt) - KubeVirt: adds cloud-init and the QEMU guest agent
- [vmware](vmware) - VMware: usage of the VMware Tools agent is often required

Note: most examples target `rhel10/rhel-bootc:10.1`. The azure and gcp examples
currently remain on `rhel9/rhel-bootc:9.4` pending RHEL 10 package availability.

### Security

- [sealing](sealing) - Composefs sealed UKI boot: builds a bootc host where a
  signed Unified Kernel Image embeds the composefs digest of the root filesystem.
  UEFI Secure Boot verifies the UKI, which in turn verifies every file on the
  root via fs-verity. *Note: experimental.*

## More examples

There are more community-contributed examples available in the [upstream Fedora-bootc project](https://gitlab.com/fedora/bootc/examples).
