# RHEL bootc examples

Welcome to the examples repository for RHEL bootc!

The `registry.redhat.io/rhel9/rhel-bootc:9.4` container image
represents a new mechanism to configure Red Hat Enterprise Linux.

You can define your systems via a container build, generate
disk images from the containers or deploy them directly via
Anaconda or `bootc install`.

Thereafter, the systems can be upgraded in-place with
transactional updates/rollbacks and maintained in a git-ops
fashion, or with live changes applied out of band.

This git repository contains just a few representative
examples of configuring a Linux system via containers.

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
  for `bootc` and `podman` different, and there are some subtleties in the `podman`
  location; this writes a pull secret to a central location embedded in the container
  (underneath `/usr` as part of the immutable state).

### Cloud and virtualization

- [aws, kubevirt, openstack](cloud-init) - these all simply add cloud-init,
  which many use cases (but not all) will want.
- [vmware](vmware) - Usage of this agent is often required.

## More examples

There are more community-contributed examples available in the [upstream Fedora-bootc project](https://gitlab.com/fedora/bootc/examples).

