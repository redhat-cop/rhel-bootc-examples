#!/bin/bash
# Verify a sealed composefs boot. Runs on the booted host: bcvk-test passes
# it as a `bash -c` argument, aws-test feeds it to `bash -s` over ssh.
#
# FAIL messages go to stderr: when the command fails, `bcvk libvirt ssh`
# prints only the remote stderr.
set -euo pipefail

fail() {
    echo "  FAIL: $*" >&2
    exit 1
}

echo "--- kernel ---"
uname -r

echo "--- secure boot ---"
SB_STATUS=$(bootctl status 2>/dev/null | grep "Secure Boot:" | head -1 | sed "s/^ *//" || true)
echo "  $SB_STATUS"
case "$SB_STATUS" in
    *"Secure Boot: enabled"*) echo "  OK: Secure Boot is enabled" ;;
    *) fail "Secure Boot is not enabled (bootctl: ${SB_STATUS:-no output})" ;;
esac

echo "--- root mount ---"
ROOT_SOURCE=$(findmnt -no SOURCE /)
ROOT_OPTIONS=$(findmnt -no OPTIONS /)
echo "  $ROOT_SOURCE ($ROOT_OPTIONS)"
case "$ROOT_SOURCE" in
    composefs:*) ;;
    *) fail "root is not a composefs mount: $ROOT_SOURCE" ;;
esac
case ",$ROOT_OPTIONS," in
    *,verity=require,*) echo "  OK: composefs root with verity=require" ;;
    *) fail "composefs root lacks verity=require: $ROOT_OPTIONS" ;;
esac

echo "--- cmdline ---"
CMDLINE=$(cat /proc/cmdline)
echo "  $CMDLINE"
DIGEST=${ROOT_SOURCE#composefs:}
[ -n "$DIGEST" ] || fail "no composefs digest in root source: $ROOT_SOURCE"
case "$CMDLINE" in
    *"$DIGEST"*) echo "  OK: root composefs digest is in the (UKI) kernel command line" ;;
    *) fail "root composefs digest $DIGEST is not in the kernel command line" ;;
esac

echo ""
echo "=== COMPOSEFS BOOT VERIFIED ==="
