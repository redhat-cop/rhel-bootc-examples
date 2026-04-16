#!/usr/bin/env python3
"""Generate Secure Boot keys for composefs sealed boot.

Usage:
    keys.py generate [--output-dir DIR]

Generates a Secure Boot key hierarchy (PK → KEK → db). The db keypair
signs systemd-boot and the UKI; PK and KEK are only needed for
enrolling keys into UEFI firmware (e.g. via bcvk or virt-fw-vars).

Only db.key is secret — db.crt is committed to the repo so the
Containerfile can embed it without build secrets.
"""

import argparse
import subprocess
import sys
import uuid
from pathlib import Path

DEFAULT_KEYS_DIR = "target/keys"


def run(cmd, **kwargs):
    """Run a command, raising on failure."""
    return subprocess.run(cmd, check=True, **kwargs)


def openssl(*args):
    run(["openssl", *args], stdout=subprocess.DEVNULL)


def generate_keys(output_dir: Path):
    """Generate Secure Boot PK, KEK, and db keypairs."""
    output_dir.mkdir(parents=True, exist_ok=True)

    for name, cn in [
        ("PK", "Secure Boot Platform Key"),
        ("KEK", "Secure Boot Key Exchange Key"),
        ("db", "Secure Boot Signature Database"),
    ]:
        key = output_dir / f"sb-{name}.key"
        crt = output_dir / f"sb-{name}.crt"
        if key.exists():
            print(f"  skip  sb-{name} (already exists)")
            continue
        print(f"  create sb-{name} keypair")
        openssl(
            "req",
            "-new",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-keyout",
            str(key),
            "-out",
            str(crt),
            "-days",
            "3650",
            "-subj",
            f"/CN={cn}",
        )

    # GUID (required by bcvk for firmware enrollment)
    guid_file = output_dir / "GUID.txt"
    if not guid_file.exists():
        guid_file.write_text(str(uuid.uuid4()) + "\n")
        print(f"  create GUID.txt")

    # Create bcvk-compatible symlinks (bcvk expects PK.crt, not sb-PK.crt)
    for name in ("PK", "KEK", "db"):
        for ext in ("key", "crt"):
            link = output_dir / f"{name}.{ext}"
            target = f"sb-{name}.{ext}"
            if not link.exists():
                link.symlink_to(target)

    print(f"\nKeys written to {output_dir}/")


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    gen = sub.add_parser("generate", help="Generate Secure Boot keys")
    gen.add_argument(
        "--output-dir",
        type=Path,
        default=Path(DEFAULT_KEYS_DIR),
        help=f"Directory to write keys to (default: {DEFAULT_KEYS_DIR})",
    )

    args = parser.parse_args()

    if args.command == "generate":
        print("Generating Secure Boot keys...\n")
        generate_keys(args.output_dir)


if __name__ == "__main__":
    main()
