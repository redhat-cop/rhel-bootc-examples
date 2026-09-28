#!/bin/bash
# Generate an AWS-format UEFI variable store blob with custom Secure Boot keys.
#
# Usage:
#   aws-uefi-blob.sh <keys-dir> <output-file>
#
# Converts PK, KEK, and db certificates (PEM) from <keys-dir> into EFI
# Signature Lists, then assembles them into an AWS-format UEFI variable
# store blob using python-uefivars.
#
# Prerequisites:
#   - cert-to-efi-sig-list  (from efitools)
#   - uefivars              (pip install python-uefivars)
#   - openssl

set -euo pipefail

KEYS_DIR="${1:?Usage: $0 <keys-dir> <output-file>}"
OUTPUT="${2:?Usage: $0 <keys-dir> <output-file>}"

# Resolve symlinks so we work with the actual cert files
PK_CRT="${KEYS_DIR}/PK.crt"
KEK_CRT="${KEYS_DIR}/KEK.crt"
DB_CRT="${KEYS_DIR}/db.crt"

for f in "$PK_CRT" "$KEK_CRT" "$DB_CRT"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Required certificate not found: $f" >&2
        exit 1
    fi
done

GUID_FILE="${KEYS_DIR}/GUID.txt"
if [ ! -f "$GUID_FILE" ]; then
    echo "ERROR: GUID.txt not found in $KEYS_DIR" >&2
    exit 1
fi
GUID=$(cat "$GUID_FILE" | tr -d '[:space:]')

# Create a temporary directory for intermediate .esl files
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "==> Converting certificates to EFI Signature Lists..."
cert-to-efi-sig-list -g "$GUID" "$PK_CRT"  "$TMPDIR/PK.esl"
cert-to-efi-sig-list -g "$GUID" "$KEK_CRT" "$TMPDIR/KEK.esl"
cert-to-efi-sig-list -g "$GUID" "$DB_CRT"  "$TMPDIR/db.esl"

echo "==> Generating AWS UEFI variable store blob..."
uefivars -i none -o aws \
    -P "$TMPDIR/PK.esl" \
    -K "$TMPDIR/KEK.esl" \
    --db "$TMPDIR/db.esl" \
    -O "$OUTPUT"

echo "==> UEFI variable store blob written to $OUTPUT"
