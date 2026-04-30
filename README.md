# RHEL bootc examples

Welcome to the examples repository for RHEL bootc!

The [`rhel10/rhel-bootc`](https://catalog.redhat.com/en/software/containers/rhel10/rhel-bootc/6707d29f27f63a06f7873ee2)
and [`rhel9/rhel-bootc`](https://catalog.redhat.com/en/software/containers/rhel9/rhel-bootc/6605573d4dbfe41c3d839c69)
container images represent a new mechanism to configure Red Hat Enterprise
Linux via container images — also known as "image mode for RHEL".

You can define your systems via a container build, generate disk images from
the containers, or deploy them directly via Anaconda or `bootc install`.

Thereafter, the systems can be upgraded in-place with transactional
updates/rollbacks and maintained in a GitOps fashion, or with live changes
applied out of band.

This git repository contains representative examples of configuring a Linux
system via containers.

## Documentation & Resources

- [Using image mode for RHEL to build, deploy, and manage operating systems (RHEL 10)](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/index) — official Red Hat documentation
- [bootc upstream project](https://github.com/containers/bootc) — the open source engine behind image mode for RHEL
- [Fedora bootc community examples](https://gitlab.com/fedora/bootc/examples) — broader set of community-contributed examples

## General guidance

A very significant percentage of Linux system configuration boils down to
writing configuration files. For example, kernel parameters can be changed
by writing to `/usr/lib/sysctl.d`.

In general, configuration like this will Just Work when done in a container
build.

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

- [aws, kubevirt, openstack](cloud-init) - these all simply add cloud-init,
  which many use cases (but not all) will want.
- [azure](azure) - Installs and enables the Azure Linux VM Agent.
- [gcp](gcp) - Installs GCP guest environment packages for running in Google Cloud.
- [vmware](vmware) - Usage of the open-vm-tools agent is often required.

### Security

- [sealing](sealing) - Builds a bootc host that boots with composefs and a
  signed Unified Kernel Image (UKI); UEFI Secure Boot verifies the UKI,
  and every file access is verified against its fs-verity digest. Experimental.
