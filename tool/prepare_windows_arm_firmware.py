#!/usr/bin/env python3
"""Prepare pinned UTM ARM64 Secure Boot firmware for Quickgui on Apple Silicon.

Downloads firmware and copyright notices only. Existing files and VM NVRAM are
never replaced. Requires ARM Homebrew qemu-img; does not install the UTM app.
"""
import bz2
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request

COMMIT = 'b44153a4b6aabf86edebf92199b14aec26e15d59'
BASE_URL = f'https://raw.githubusercontent.com/utmapp/qemu/{COMMIT}/pc-bios/'
QEMU_IMG = '/opt/homebrew/bin/qemu-img'
DESTINATION = Path.home() / 'Library/Application Support/Quickgui/Firmware/utm-b44153a4'
SOURCES = {
    'edk2-aarch64-secure-code.fd.bz2': ('uefi-code.fd', '89206fa3bce0a43161e6d8dc143c6246ac03f095ce9873a1243cdb99efe4ee63'),
    'edk2-arm-secure-vars.fd.bz2': ('uefi-vars.qcow2', '4dba10d7c7169b52a7b7bb8e0cef1c0b630312ff13725eff10d4711f21d9f373'),
    'edk2-licenses.txt': ('COPYRIGHT', '1ddeaed2e7d2e9ecb960bdfc1b8ee45387aff70d056d985d145949af3951657c'),
}
HASHES = {
    'uefi-code.fd': 'c85a57de1ac39e550a6529bd66a4214eb1d8c14dcda7e22dedf72566a769fbc7',
    'uefi-vars.fd': '8203a22c79a52ec6c34320e58bae8a63b890a76bf62167b2e7551e88b974dc77',
    'COPYRIGHT': '1ddeaed2e7d2e9ecb960bdfc1b8ee45387aff70d056d985d145949af3951657c',
}


def verify(folder):
    if folder.is_symlink():
        raise ValueError('Firmware directory must not be a symbolic link.')
    for name, expected in HASHES.items():
        path = folder / name
        if path.is_symlink() or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f'Firmware differs or is missing; left unchanged: {path}')


def unpack(source, data):
    if hashlib.sha256(data).hexdigest() != SOURCES[source][1]:
        raise ValueError(f'Firmware checksum mismatch: {source}')
    if source.endswith('.bz2'):
        decompressor = bz2.BZ2Decompressor()
        data = decompressor.decompress(data, max_length=64 * 1024 * 1024 + 1)
        if not decompressor.eof or len(data) > 64 * 1024 * 1024:
            raise ValueError('Unexpected firmware image size.')
    return data


def main():
    if DESTINATION.exists():
        verify(DESTINATION)
        print(f'Existing firmware verified: {DESTINATION}')
        return
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix='.quickgui-firmware-', dir=DESTINATION.parent))
    try:
        for source, (name, _) in SOURCES.items():
            with urllib.request.urlopen(BASE_URL + source, timeout=60) as response:
                if not response.url.startswith('https://'):
                    raise ValueError('Firmware download must use HTTPS.')
                data = response.read(16 * 1024 * 1024 + 1)
            if len(data) > 16 * 1024 * 1024:
                raise ValueError('Unexpected firmware download size.')
            (staging / name).write_bytes(unpack(source, data))
        # UTM distributes the enrolled variable template as QCOW2. Convert only
        # this verified template; each VM subsequently owns its raw NVRAM copy.
        variables = staging / 'uefi-vars.qcow2'
        info = json.loads(subprocess.check_output([QEMU_IMG, 'info', '--output=json', '-f', 'qcow2', str(variables)], timeout=30))
        if info.get('backing-filename') or info.get('virtual-size') != 64 * 1024 * 1024:
            raise ValueError('Unexpected firmware variable image layout.')
        subprocess.run([QEMU_IMG, 'convert', '-f', 'qcow2', '-O', 'raw', str(variables), str(staging / 'uefi-vars.fd')], check=True, timeout=30)
        variables.unlink()
        verify(staging)
        manifest = {'source': 'utmapp/qemu', 'commit': COMMIT, 'files': HASHES, 'downloads': SOURCES,
                    'variables': 'QCOW2 template converted to raw; enrolled keys unchanged'}
        (staging / 'firmware.json').write_text(json.dumps(manifest, indent=2) + '\n')
        for path in staging.iterdir():
            path.chmod(0o600)
        # Exclusive destination creation prevents replacing an existing folder.
        DESTINATION.mkdir(mode=0o700)
        for path in staging.iterdir():
            path.rename(DESTINATION / path.name)
        print(f'Secure Boot firmware prepared: {DESTINATION}')
    finally:
        shutil.rmtree(staging)


if __name__ == '__main__':
    main()
