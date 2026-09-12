#!/usr/bin/env python3
"""Install pinned, SMM-protected Secure Boot OVMF for Intel macOS/TCG.

Intel HVF does not provide SMM; use TCG with SMM for this firmware. Existing
VM NVRAM and TPM state must never be overwritten by this provisioning tool.
"""
import argparse
import hashlib
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import urllib.request

URL = 'https://deb.debian.org/debian/pool/main/e/edk2/ovmf_2025.02-8+deb13u1_all.deb'
PACKAGE_SHA256 = '78e0d54df11fc77406cb7a0bc9a39e5bca6d1cbe06556b91d9a73491c52decdf'
FILES = {
    'OVMF_CODE_4M.secboot.fd': '1a46295574430cfb7f825ee3e4dc64b052acbef08e310377ed7c64cb757a9dc1',
    'OVMF_VARS_4M.ms.fd': '0d12f9839018a68f4b13c9819cbf607b8b62d566f9c9dd7966550d93335f06b2',
}


def install(package, destination):
    package = Path(package)
    if hashlib.sha256(package.read_bytes()).hexdigest() != PACKAGE_SHA256:
        raise ValueError('OVMF package checksum mismatch')
    payload = subprocess.check_output(['ar', '-p', str(package), 'data.tar.xz'])
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(payload), mode='r:xz') as archive:
        for name, digest in FILES.items():
            data = archive.extractfile('./usr/share/OVMF/' + name).read()
            if hashlib.sha256(data).hexdigest() != digest:
                raise ValueError('Firmware checksum mismatch: ' + name)
            target = destination / name
            if target.is_symlink():
                raise ValueError('Refusing firmware symlink: ' + str(target))
            if target.exists():
                if hashlib.sha256(target.read_bytes()).hexdigest() != digest:
                    raise ValueError('Preserving different existing firmware: ' + str(target))
                continue
            descriptor, staging = tempfile.mkstemp(prefix='.ovmf-', dir=destination)
            try:
                with os.fdopen(descriptor, 'wb') as stream:
                    stream.write(data)
                os.chmod(staging, 0o644)
                os.link(staging, target)  # Atomic create; never replace a file.
            finally:
                os.unlink(staging)
    print('Prepared SMM-protected Secure Boot UEFI for TCG:', destination)


def patch_quickemu(path):
    path = Path(path).resolve(strict=True)
    original = path.read_bytes()
    before = b'    DISPLAY_RENDER=""\n    EFI_CODE=""\n    EFI_VARS=""'
    after = b'    DISPLAY_RENDER=""\n    EFI_CODE="${EFI_CODE:-}"\n    EFI_VARS=""'
    if after in original:
        print('Quickemu already preserves configured EFI_CODE:', path)
        return
    if original.count(before) != 1:
        raise ValueError('Unrecognized Quickemu initialization; no changes made')
    backup = path.with_name(path.name + '.before-quickgui-efi-' + hashlib.sha256(original).hexdigest()[:12])
    if not backup.exists():
        with backup.open('xb') as stream:
            stream.write(original)
    elif backup.read_bytes() != original:
        raise ValueError('Existing backup differs; no changes made')
    mode = path.stat().st_mode & 0o777
    descriptor, staging = tempfile.mkstemp(prefix='.quickgui-efi-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(original.replace(before, after))
        os.chmod(staging, mode)
        os.replace(staging, path)
    finally:
        if os.path.exists(staging):
            os.unlink(staging)
    print('Quickemu EFI override fixed; original preserved:', backup)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, help='Use a previously downloaded Debian package')
    parser.add_argument('--directory', type=Path, default=Path.home() / '.local/share/quickgui/firmware/windows-x64')
    parser.add_argument('--quickemu', type=Path, help='Back up and fix the known Quickemu 4.9.9 EFI override reset')
    args = parser.parse_args()
    if args.package:
        install(args.package, args.directory)
    else:
        with tempfile.TemporaryDirectory(prefix='quickgui-ovmf-') as temporary:
            package = Path(temporary) / 'ovmf.deb'
            with urllib.request.urlopen(URL, timeout=60) as response:
                data = response.read(32 * 1024 * 1024 + 1)
            if len(data) > 32 * 1024 * 1024:
                raise ValueError('Unexpectedly large OVMF package')
            package.write_bytes(data)
            install(package, args.directory)
    if args.quickemu:
        patch_quickemu(args.quickemu)


if __name__ == '__main__':
    main()
