# Containerfile — Sealed bootc host with composefs root
#
# Builds a RHEL 10 bootc image that boots with the composefs
# backend. A signed Unified Kernel Image (UKI) embeds the composefs
# (fs-verity) digest; Secure Boot verifies the UKI, which in turn verifies
# every file on the root filesystem via fs-verity.
#
# This follows the canonical bootc "build from scratch" pattern: the target
# rootfs is reconstructed with `bootc-base-imagectl build-rootfs` and copied
# FROM scratch.
#
# Network access is confined to three early stages (`target-base`, `boot-rpms`,
# and `tools`). Every stage that contributes to the sealed tree runs with
# `--network=none`, so nothing the network sees can perturb the composefs
# digest.
#
# `systemd-ukify` (appstream) is installed in the `tools` stage for UKI
# generation and is never inherited by the final image. `systemd-sbsign`
# (part of the base `systemd` package, v257+) is already present in the
# target rootfs and is used to sign both the bootloader and the UKI — no
# EPEL or CRB repositories are required anywhere in this build.
# Only `systemd-boot-unsigned` (the boot loader binary that must be present at
# install time) is installed into the sealed tree.
#
# Both the db private key and the db certificate are passed as build
# secrets.  The cert is public, but using a secret mount avoids SELinux
# label mismatches on bind-mounted host files and keeps the cert out of
# any image layer.
#
# NOTE: `build-rootfs` runs `rpm-ostree compose` under bwrap and therefore
# needs extra capabilities at build time. The Justfile `build` recipe passes
# `--cap-add=all --security-opt=label=type:container_runtime_t --device /dev/fuse`.
#
# Build (see the Justfile `build` recipe):
#   podman build \
#     --cap-add=all --security-opt=label=type:container_runtime_t --device /dev/fuse \
#     --secret id=secureboot_key,src=target/keys/sb-db.key \
#     --secret id=secureboot_cert,src=keys/db.crt \
#     -t localhost/sealed-host:latest .

ARG base=registry.redhat.io/rhel10/rhel-bootc:10.2
FROM ${base} as base

# ---------------------------------------------------------------------------
# Stage: target-base — "from scratch" rootfs build
# ---------------------------------------------------------------------------
# See <https://docs.fedoraproject.org/en-US/bootc/building-from-scratch/>
# We presently MUST do this to drop out the /sysroot/ostree content and to avoid
# the "implicit mtime on parent dirs" https://github.com/containers/composefs-rs/issues/132
# issue.
#
# You may also want to use e.g. --install to add extra packages here.
FROM base AS target-base
# Workaround for https://github.com/coreos/rpm-ostree/pull/5597 (libdnf only
# reads the first armor block from a key file). RHEL 10's
# RPM-GPG-KEY-redhat-release contains three blocks (RSA, Ed448, ML-DSA);
# split them into individual files so rpm-ostree can import all of them.
RUN python3 - <<'EOF'
import re, pathlib
gpgdir = pathlib.Path("/etc/pki/rpm-gpg")
key = gpgdir / "RPM-GPG-KEY-redhat-release"
blocks = re.findall(
    r"-----BEGIN PGP PUBLIC KEY BLOCK-----.*?-----END PGP PUBLIC KEY BLOCK-----",
    key.read_text(), re.DOTALL)
for i, block in enumerate(blocks):
    (gpgdir / f"RPM-GPG-KEY-redhat-release-{i}").write_text(block + "\n")
EOF
RUN --mount=type=tmpfs,target=/run --mount=type=tmpfs,target=/tmp \
    /usr/libexec/bootc-base-imagectl build-rootfs --manifest=standard /target-rootfs

# ---------------------------------------------------------------------------
# Stage: boot-rpms — download the bootloader RPM that belongs in the final image
# ---------------------------------------------------------------------------
# Only systemd-boot-unsigned is needed in the sealed tree; it is the EFI
# binary that firmware loads and which bootc installs onto the EFI partition.
FROM base AS boot-rpms
RUN --mount=type=tmpfs,target=/run --mount=type=tmpfs,target=/tmp \
    mkdir -p /rpms && \
    dnf -y install --downloadonly --downloaddir=/rpms systemd-boot-unsigned && \
    dnf clean all

# ---------------------------------------------------------------------------
# Stage: tools — signing toolbox (never inherited by the final image)
# ---------------------------------------------------------------------------
# systemd-ukify is only needed at build time to assemble and sign the UKI.
# It is installed here from the RHEL 10 appstream repo — no EPEL or CRB
# required. systemd-sbsign (part of systemd v257, already in the base image)
# is used for all PE signing and is available everywhere without extra repos.
FROM base AS tools
RUN --mount=type=tmpfs,target=/run --mount=type=tmpfs,target=/tmp \
    dnf -y install systemd-ukify && \
    dnf clean all

# ---------------------------------------------------------------------------
# Stage: base-rootfs — clean rootfs + offline install of systemd-boot-unsigned
# ---------------------------------------------------------------------------
# The boot-rpms stage is bind-mounted so nothing extra lands in the sealed
# tree. Signing tools are NOT installed here.
#
# NOTE: buildah <1.43 doesn't invalidate this RUN's layer cache when the
# bind-mounted `boot-rpms` stage changes (https://github.com/containers/buildah/issues/6609,
# fixed in #6845). If you edit the boot-rpms stage and see stale results,
# delete the cached base-rootfs layer or build with --no-cache.
FROM scratch AS base-rootfs
COPY --from=target-base /target-rootfs/ /
RUN --network=none \
    --mount=type=tmpfs,target=/run --mount=type=tmpfs,target=/tmp \
    --mount=type=bind,from=boot-rpms,source=/rpms,target=/run/rpms \
    --mount=type=bind,from=boot-rpms,source=/etc/pki/rpm-gpg,target=/run/keys <<EORUN
set -xeuo pipefail
# We will use systemd-boot, so remove bootupd.
rpm -e bootupd
# Import the Red Hat signing keys up front: offline, dnf can't fetch them itself.
rpm --import /run/keys/RPM-GPG-KEY-redhat-*
# localpkg_gpgcheck enforces signatures on the local rpms (dnf leaves it off).
dnf -y install --disablerepo='*' --setopt=localpkg_gpgcheck=1 /run/rpms/*.rpm
dnf clean all
EORUN

# ---------------------------------------------------------------------------
# Stage: penultimate — local config + sign systemd-boot + scrub /var
# ---------------------------------------------------------------------------
# This stage produces the exact filesystem tree that will be sealed, EXCEPT for
# the /boot UKI which is added in the final stage from the sealer's digest.
#
# sbsign is invoked from the `tools` bind-mount rather than installed here,
# so the signing binary never becomes part of the sealed tree.
FROM base-rootfs AS penultimate

# composefs needs fs-verity, which on the root fs means ext4 here. Default to ext4
# at install time via a bootc install config drop-in.
RUN --network=none --mount=type=tmpfs,target=/run --mount=type=tmpfs,target=/tmp <<EORUN
set -xeuo pipefail
mkdir -p /usr/lib/bootc/install
cat > /usr/lib/bootc/install/00-ext4-default.toml <<'EOF'
[install.filesystem.root]
type = "ext4"
EOF
EORUN

# Sign systemd-boot with our Secure Boot key so UEFI firmware will load it.
# MUST happen before the seal so the signed binary is part of the digest.
# systemd-sbsign is part of the base systemd package (v257+) so it is already
# present in the target rootfs — no bind-mounts or extra tools needed.
RUN --network=none --mount=type=tmpfs,target=/run --mount=type=tmpfs,target=/tmp \
    --mount=type=secret,id=secureboot_key \
    --mount=type=secret,id=secureboot_cert <<EORUN
set -xeuo pipefail
/usr/lib/systemd/systemd-sbsign sign \
    --private-key /run/secrets/secureboot_key \
    --certificate /run/secrets/secureboot_cert \
    --output /tmp/systemd-bootx64.efi.signed \
    /usr/lib/systemd/boot/efi/systemd-bootx64.efi
mv /tmp/systemd-bootx64.efi.signed /usr/lib/systemd/boot/efi/systemd-bootx64.efi
EORUN

# Scrub the dnf/rpm bookkeeping the post-copy install left in /var so the tree
# is "effectively empty" at seal time and the bootc var-tmpfiles lint (run
# below) stays happy. We clear the *contents* but keep the directories: /var/lib
# in particular must ship so it seeds the runtime /var state dir already labeled.
# Removing /var/lib outright leaves first-boot to create it before SELinux policy
# is loaded, landing it unlabeled_t and breaking systemd-random-seed/tpm2-setup
# (which race ahead of the post-policy tmpfiles pass) on the very first boot.
RUN --network=none --mount=type=tmpfs,target=/run --mount=type=tmpfs,target=/tmp \
    find /var/log /var/lib /var/cache -mindepth 1 -delete

# ---------------------------------------------------------------------------
# Stage: sealer — compute composefs digest and build the signed UKI
# ---------------------------------------------------------------------------
# FROM tools so ukify, sbsign, and all their deps are natively available.
# The penultimate tree is mounted read-only; the sealer never modifies it.
FROM tools AS sealer
RUN --network=none --mount=type=tmpfs,target=/run --mount=type=tmpfs,target=/tmp \
    --mount=type=bind,from=penultimate,target=/target \
    --mount=type=secret,id=secureboot_key \
    --mount=type=secret,id=secureboot_cert <<EORUN
set -xeuo pipefail
mkdir -p /out
bootc container ukify --rootfs /target \
  --karg rw \
  --karg console=hvc0,115200 \
  --karg systemd.journald.forward_to_console=1 \
  -- \
  --signtool systemd-sbsign \
  --secureboot-private-key /run/secrets/secureboot_key \
  --secureboot-certificate /run/secrets/secureboot_cert \
  --no-sign-kernel \
  --output /out/uki.efi
ls -lh /out/
EORUN

# Place the UKI at its final /boot location, keyed by kernel version.
# Read kver from the sealed tree rather than the tools image to avoid coupling.
RUN --network=none --mount=type=tmpfs,target=/run --mount=type=tmpfs,target=/tmp \
    --mount=type=bind,from=penultimate,target=/target <<EORUN
set -xeuo pipefail
kver=$(ls /target/usr/lib/modules)
mkdir -p /out/boot/EFI/Linux
mv /out/uki.efi "/out/boot/EFI/Linux/${kver}.efi"
EORUN

# Run the linter against the sealed tree.
RUN --network=none --mount=type=tmpfs,target=/run --mount=type=tmpfs,target=/tmp \
    --mount=type=bind,from=penultimate,target=/target \
    bootc container lint --rootfs /target --fatal-warnings

# ---------------------------------------------------------------------------
# Final image: clean sealed rootfs + the signed UKI in /boot
# ---------------------------------------------------------------------------
FROM penultimate
# Add in the signed UKI. bootc's install path auto-selects its composefs
# bootloader backend (bootctl, not bootupd) when it finds a UKI at exactly
# /boot/EFI/Linux/*.efi — which is also why we can drop bootupd above.
COPY --from=sealer /out/boot /boot
# Required + suggested metadata
LABEL containers.bootc 1
ENV container=oci
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
