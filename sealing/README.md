# Sealed composefs boot

This example builds a RHEL 10.2 Image Mode system that boots with the
[bootc composefs backend](https://bootc.dev/bootc/experimental-composefs.html). A signed Unified Kernel Image (UKI) embeds the composefs digest of the root filesystem. At boot:

1. UEFI Secure Boot verifies the UKI signature against enrolled keys
2. The kernel starts with `composefs=<digest>` in the command line
3. The initramfs mounts the root as a composefs overlay with `verity=require`
4. Every file access is verified against its fs-verity digest

Note that this support is Tech Preview in RHEL 10.2. But we are interested
in feedback.

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
│     ├── Install packages (systemd-boot, sbsigntools, systemd-ukify)
│     ├── Sign systemd-boot with db key (secret: db.key, public: keys/db.crt)
│     ├── Rebuild initramfs with bootc dracut module
│     └── FROM scratch flatten (deterministic composefs digest)
├── bootc container ukify
│     ├── Compute composefs SHA-512 digest from flattened rootfs
│     ├── Embed digest + kargs in UKI command line
│     └── Sign UKI with db key
└── COPY --from=kernel /boot /boot

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
