# Sealed composefs boot

This example builds a RHEL 10.2 Image Mode system that boots with the
[bootc composefs backend](https://bootc.dev/bootc/experimental-composefs.html). A signed Unified Kernel Image (UKI) embeds the composefs digest of the root filesystem. At boot:

1. UEFI Secure Boot verifies the UKI signature against enrolled keys
2. The kernel starts with `composefs=<digest>` in the command line
3. The initramfs mounts the root as a composefs overlay with `verity=require`
4. Every file access is verified against its fs-verity digest

Note that this support is Tech Preview in RHEL 10.2. But we are interested
in feedback.

## Prerequisites

- `podman`, `just`, `openssl` and `python3` (for `just keygen`) to
  build; for the local VM, also [bcvk](https://github.com/bootc-dev/bcvk)
  and `virt-fw-vars` (`dnf install python3-virt-firmware`), which bcvk
  uses to enroll the Secure Boot keys.
- Access to RHEL content. The base image comes from `registry.redhat.io`,
  so log in first (`podman login registry.redhat.io`), and the build runs
  `dnf` inside it, which needs the build host to be registered with a Red
  Hat subscription: podman passes the host's entitlement certificates into
  the build. A
  [no-cost developer subscription](https://developers.redhat.com/register)
  is sufficient. Without it the build finds no enabled repositories and
  fails. On a Fedora build host, install `subscription-manager`
  and register (`sudo subscription-manager register`). To check:

  ```sh
  podman run --rm registry.redhat.io/rhel10/rhel-bootc:10.2 dnf repolist
  ```

  If the output lists RHEL repositories, the entitlements are in place.

## Quick start with bcvk

### 1. Generate Secure Boot keys

```sh
just keygen
```

This generates PK, KEK, and db keypairs in `target/keys/` and copies
`db.crt` into `keys/` for committing. PK and KEK are only used for
firmware enrollment (bcvk handles this); db signs the boot artifacts.

It's important to understand that it is *your* Secure Boot keys used to sign the entire boot chain, and that [shim](https://github.com/rhboot/shim) is not used by default.

### 2. Build and boot

```sh
just bcvk-ssh
```

This single command builds the sealed container image and boots a VM with Secure Boot and the composefs backend.

### 3. Manual exploration

The `Justfile` is a relatively straightforward wrapper for `podman build` to generate the container image, and `bcvk` to run it as a local VM.

You can separate build and run steps:

```sh
just build
bcvk libvirt run --detach --ssh-wait --name sealed-demo \
    --secure-boot-keys target/keys \
    localhost/sealed-host:latest
bcvk libvirt ssh sealed-demo
```

Inside the VM:

```sh
mount | grep ' / '
# composefs:<digest> on / type overlay (ro,verity=require)

cat /proc/cmdline
# composefs=<digest> rw ...
```

Clean up:

```sh
bcvk libvirt rm --stop --force sealed-demo
```

## How it works

```
Build time
├── Containerfile
│     ├── Compose the rootfs from scratch (bootc-base-imagectl build-rootfs)
│     ├── Swap bootupd and shim for systemd-boot-unsigned
│     ├── Sign systemd-boot with db key (systemd-sbsign; secrets: db key + cert)
│     └── Scrub /var so the tree is ready to seal
├── bootc container ukify (the target's own bootc, ukify from a tools stage)
│     ├── Compute composefs SHA-512 digest from the sealed tree
│     ├── Embed digest + kargs in UKI command line
│     └── Sign UKI with db key
└── COPY --from=sealer /out/boot /boot

Boot time (UEFI → systemd-boot → UKI → composefs)
├── UEFI verifies systemd-boot signature against enrolled db cert
├── systemd-boot loads UKI
├── Kernel starts with composefs=<digest> in cmdline
├── initramfs: bootc-root-setup.service
│     ├── Mounts ext4 root partition
│     ├── Mounts EROFS metadata image (composefs image)
│     ├── Sets up overlayfs with verity=require
│     └── Bind-mounts /etc and /var from state
└── switch-root into composefs overlay
```

## AWS testing

See [README-AWS.md](README-AWS.md) for instructions on testing the sealed
image on AWS EC2 with UEFI Secure Boot.  The short version:

```sh
just aws-test
```

## Key management

Only one secret: the Secure Boot db private key (`db.key`). Everything
else is public or derived:

| File | Secret? | Where | Purpose |
|---|---|---|---|
| `keys/db.crt` | No | Committed to repo | Public cert; used by `sbsign` and enrolled in firmware |
| `db.key` | **Yes** | CI secret / local `target/keys/` | Signs systemd-boot and UKI |
| `PK.key`, `KEK.key` | Local only | `target/keys/` | Firmware enrollment (bcvk, virt-fw-vars, or cloud API) |

For CI, set one GitHub Actions secret:

| Secret | Description |
|---|---|
| `SECUREBOOT_DB_KEY` | Secure Boot db private key (PEM) |

PR builds use ephemeral keys so no secrets are needed for CI validation.
