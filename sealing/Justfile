# Justfile for sealed composefs UKI boot
#
# Builds a RHEL 10 bootc host that boots with the composefs
# backend (UKI + composefs digest + Secure Boot).
#
# Prerequisites: podman, openssl, just
# For VM testing: bcvk (from bootc-dev/bcvk), virt-firmware (pip)

# Local image name
host_image := "localhost/sealed-host:latest"

# Key material directory (for local dev; CI uses secrets)
keys_dir := justfile_directory() + "/target/keys"

# Generate Secure Boot keys (PK/KEK for enrollment, db for signing).
# Copies db.crt into keys/ for committing to the repo.
keygen:
    #!/bin/bash
    set -euo pipefail
    python3 util/keys.py generate --output-dir "{{keys_dir}}"
    mkdir -p keys/
    cp "{{keys_dir}}/sb-db.crt" keys/db.crt
    echo "keys/db.crt updated — commit it to the repo"

# Build the sealed host image (composefs backend with signed UKI).
# If no persistent key exists under target/keys/, an ephemeral key+cert pair
# is generated automatically (suitable for CI and local smoke-testing).
build:
    #!/bin/bash
    set -euo pipefail
    KEY="{{keys_dir}}/sb-db.key"
    CERT="keys/db.crt"

    if [ ! -f "${KEY}" ]; then
        echo "No persistent key found — generating ephemeral key+cert for this build."
        mkdir -p "{{keys_dir}}"
        openssl req -x509 -newkey rsa:2048 -nodes \
            -keyout "${KEY}" -out "${CERT}" \
            -days 1 -subj '/CN=bootc-ci-ephemeral/'
    fi

    # build-rootfs runs `rpm-ostree compose` under bwrap, which needs extra
    # capabilities and /dev/fuse. The composefs/UKI build also uses fuse.
    podman build \
        --cap-add=all --security-opt=label=type:container_runtime_t --device /dev/fuse \
        --secret id=secureboot_key,src="${KEY}" \
        --secret id=secureboot_cert,src="${CERT}" \
        -t "{{host_image}}" .
    echo "Host image built: {{host_image}}"

# Internal: boot the VM (used by bcvk-ssh and bcvk-test).
[private]
bcvk-boot: build
    #!/bin/bash
    set -euo pipefail

    VM_NAME="sealed-demo"

    # Clean up any previous VM with this name
    bcvk libvirt rm --stop --force "${VM_NAME}" 2>/dev/null || true

    set -x
    bcvk libvirt run  --name "${VM_NAME}" \
        --filesystem=ext4 \
        --secure-boot-keys "{{keys_dir}}" \
        "{{host_image}}"

# Boot a VM and open an interactive SSH session.
bcvk-ssh: bcvk-boot
    #!/bin/bash
    set -euo pipefail
    VM_NAME="sealed-demo"
    bcvk libvirt ssh "${VM_NAME}"

# Boot a VM, verify composefs, and tear down.
bcvk-test: bcvk-boot
    #!/bin/bash
    set -euo pipefail

    VM_NAME="sealed-demo"
    trap 'echo "==> Cleaning up VM..."; bcvk libvirt rm --stop --force "${VM_NAME}"; echo "Done."' EXIT

    echo "==> Running checks..."
    bcvk libvirt ssh "${VM_NAME}" -- bash -c '
        set -euo pipefail

        echo "--- kernel ---"
        uname -r

        echo "--- root mount ---"
        mount | grep " / " || true
        if mount | grep -q "verity=require"; then
            echo "  OK: composefs root with verity=require"
        else
            echo "  FAIL: composefs root not detected"
            exit 1
        fi

        echo "--- cmdline ---"
        cat /proc/cmdline

        echo ""
        echo "=== COMPOSEFS BOOT VERIFIED ==="
    '

# Clean generated artifacts and VM
clean:
    #!/bin/bash
    set -euo pipefail
    bcvk libvirt rm --stop --force sealed-demo 2>/dev/null || true
    rm -rf target/
    podman rmi -f "{{host_image}}" 2>/dev/null || true
    echo "Cleaned"
