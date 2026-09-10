#!/usr/bin/env python3
"""Prepare a network-only Windows ARM64 driver CD from verified UTM media."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

SOURCE = 'https://github.com/utmapp/qemu/releases/download/v10.0.2-utm/utm-guest-tools-0.1.271.iso'
SOURCE_HASH = '65b6a69b392ee01dd314c10f3dad9ebbf9c4160be43f5f0dd6bb715944d9095b'
DESTINATION = Path.home() / 'Library/Application Support/Quickgui/Drivers/netkvm-0.1.271-arm64'
FILES = {
    'netkvm.inf': '0d8bcd89cb1022cf3fe185b252c77257d5c6a0957613be034c6d463d44d95c5f',
    'netkvm.cat': '2141ca89df27f585a067f637c9a0e24923d0eaf2da6704c4224cb0dc5e04f088',
    'netkvm.sys': '46df2bc1f2b31a0df4b8d5b056d018cf5b6cdc7b25299523243a31cd02e5086d',
    'netkvmp.exe': '261d52ec38bcfbb2a28a4b0d874736ca12387b1ce64bd5803eaf5a055e745ecc',
}


def digest(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f'Expected a regular file: {path}')
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def verify(folder):
    if folder.is_symlink():
        raise ValueError('Driver directory must not be a symbolic link.')
    manifest_path = folder / 'network.json'
    digest(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    image = folder / 'network-drivers.iso'
    if (manifest.get('schema') != 1 or manifest.get('sourceSHA256') != SOURCE_HASH
            or manifest.get('files') != FILES
            or not 0 < image.stat().st_size <= 16 * 1024 * 1024
            or digest(image) != manifest.get('imageSHA256')):
        raise ValueError('Network driver media differs; existing files left unchanged.')


def prepare(source_iso=None, destination=DESTINATION):
    if destination.exists() or destination.is_symlink():
        verify(destination)
        print(f'Existing network driver CD verified: {destination}')
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.quickgui-network-', dir=destination.parent) as temp:
        staging = Path(temp)
        source = Path(source_iso) if source_iso else staging / 'utm.iso'
        if not source_iso:
            subprocess.run(['/usr/bin/curl', '--fail', '--location', '--silent', '--show-error',
                            '--proto', '=https', '--proto-redir', '=https', '--max-time', '180',
                            '--max-filesize', '134217728', '--output', str(source), SOURCE],
                           check=True, timeout=190)
        if digest(source) != SOURCE_HASH:
            raise ValueError('UTM source ISO checksum mismatch.')
        # Keep the mount outside recursive staging cleanup, even if detach fails.
        mount = Path(tempfile.mkdtemp(prefix='quickgui-network-mount-'))
        try:
            subprocess.run(['/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen',
                            '-mountpoint', str(mount), str(source)], check=True, timeout=60)
        except Exception:
            # rmdir cannot descend into (or erase files on) a mount.
            try:
                mount.rmdir()
            except OSError:
                pass
            raise
        content = staging / 'content'
        drivers = content / 'NetKVM'
        drivers.mkdir(parents=True)
        try:
            for name, expected in FILES.items():
                path = mount / 'Drivers/NetKVM/w11/ARM64' / name
                if digest(path) != expected:
                    raise ValueError(f'ARM64 driver checksum mismatch: {name}')
                shutil.copyfile(path, drivers / name)
            license_path = mount / 'virtio-win_license.txt'
            if digest(license_path) != 'accd84cb35eff899d619ff40e6fea8074305cdf0e7191db71a5d9c3a015e3b02':
                raise ValueError('Driver license checksum mismatch.')
            shutil.copyfile(license_path, content / 'LICENSE.txt')
        finally:
            # Never recursively clean a still-mounted source volume.
            try:
                subprocess.run(['/usr/bin/hdiutil', 'detach', str(mount)], check=True, timeout=30)
            except Exception:
                subprocess.run(['/usr/bin/hdiutil', 'detach', '-force', str(mount)], check=True, timeout=30)
            mount.rmdir()
        (content / 'README.txt').write_text(
            'Quickgui Windows 11 ARM64 network driver\r\n'
            'In Windows network setup, select Install driver and this CD / NetKVM.\r\n'
            'Alternatively, in an Administrator command prompt run:\r\n'
            'pnputil /add-driver D:\\NetKVM\\netkvm.inf /install\r\n'
            'Replace D: with the drive letter of the QGNET CD.\r\n'
            'This CD contains only the Microsoft-catalog-signed ARM64 NetKVM driver.\r\n'
            'No automatic setup answers, display drivers, or SPICE installer are included.\r\n'
            f'Source media: {SOURCE}\r\n'
            'Driver source: https://github.com/virtio-win/kvm-guest-drivers-windows\r\n'
        )
        output = staging / 'output'
        output.mkdir()
        image = output / 'network-drivers.iso'
        subprocess.run(['/usr/bin/hdiutil', 'makehybrid', '-iso', '-joliet', '-iso-volume-name',
                        'QGNET', '-joliet-volume-name', 'QGNET', '-o', str(image), str(content)],
                       check=True, timeout=60)
        (output / 'network.json').write_text(json.dumps({
            'schema': 1, 'source': SOURCE, 'sourceSHA256': SOURCE_HASH,
            'files': FILES, 'imageSHA256': digest(image),
        }, indent=2) + '\n')
        verify(output)
        # No replacement of an existing prepared driver folder.
        destination.mkdir(mode=0o700)
        for path in output.iterdir():
            path.chmod(0o600)
            path.rename(destination / path.name)
    print(f'Network driver CD prepared: {destination}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-iso', type=Path, help='Reuse a downloaded, checksum-verified UTM ISO')
    prepare(parser.parse_args().source_iso)
