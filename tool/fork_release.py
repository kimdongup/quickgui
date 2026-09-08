#!/usr/bin/env python3
"""Build-only by default. A publish request must resolve an existing exact tag."""
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tarfile


def release_tag(version):
    match = re.fullmatch(r'(\d+\.\d+\.\d+)\+(\d+)', version)
    if not match:
        raise ValueError('Expected pubspec version X.Y.Z+N')
    return f'fork-v{match[1]}.{match[2]}'


def checked_tag(version, tag):
    expected = release_tag(version)
    if tag != expected:
        raise ValueError(f'Expected tag {expected}, received {tag!r}')
    return expected


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def prepare():
    version = re.search(r'^version:\s*(\S+)', Path('pubspec.yaml').read_text(), re.M)[1]
    tag = os.environ.get('RELEASE_TAG') or release_tag(version)
    checked_tag(version, tag)
    sha = git('rev-parse', 'HEAD')
    publish = os.environ.get('PUBLISH_RELEASE') == 'true'
    if publish:
        if os.environ.get('GITHUB_REPOSITORY') != 'kimdongup/quickgui':
            raise ValueError('Fork publication is restricted to kimdongup/quickgui')
        if git('rev-parse', f'refs/tags/{tag}^{{commit}}') != sha:
            raise ValueError('Release tag does not point to the checked-out commit')
    values = dict(tag=tag, sha=sha, version=version, publish=str(publish).lower())
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.writelines(f'{key}={value}\n' for key, value in values.items())
    print(json.dumps(values))


def package():
    tag = os.environ['RELEASE_TAG']
    if not re.fullmatch(r'fork-v\d+\.\d+\.\d+\.\d+', tag):
        raise ValueError('Invalid fork release tag')
    target = Path('dist/fork')
    target.mkdir(parents=True, exist_ok=True)
    arch = {'x86_64': 'x64', 'aarch64': 'arm64'}.get(platform.machine(), platform.machine())
    if sys.platform == 'darwin':
        source = Path('build/macos/Build/Products/Release/quickgui.app')
        if not source.is_dir():
            raise FileNotFoundError(source)
        archive = target / f'quickgui-{tag}-macos-{arch}.zip'
        subprocess.run(['ditto', '-c', '-k', '--keepParent', str(source), str(archive)], check=True)
    elif sys.platform == 'linux':
        source = Path(f'build/linux/{arch}/release/bundle')
        if not (source / 'quickgui').is_file():
            raise FileNotFoundError(source)
        archive = target / f'quickgui-{tag}-linux-{arch}.tar.gz'
        with tarfile.open(archive, 'w:gz') as output:
            output.add(source, arcname='quickgui')
    else:
        raise ValueError('Unsupported release platform')
    if archive.stat().st_size == 0:
        raise ValueError('Empty build artifact')
    print(archive)


def manifest():
    directory = Path('dist/fork')
    archives = sorted(directory.glob('quickgui-fork-v*'))
    if len(archives) != 2 or not any('-macos-' in p.name for p in archives) or not any('-linux-' in p.name for p in archives):
        raise ValueError('Expected one Linux archive and one macOS archive')
    lines = [f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n' for path in archives]
    (directory / 'SHA256SUMS').write_text(''.join(lines))
    (directory / 'BUILD.json').write_text(json.dumps({
        'repository': os.environ['GITHUB_REPOSITORY'], 'sha': os.environ['RELEASE_SHA'],
        'tag': os.environ['RELEASE_TAG'], 'flutter': '3.47.2',
        'quickemu_tested': '4.9.9', 'status': 'candidate',
        'notes': 'Unsigned archives. Full guest installation and SSH/SPICE UI acceptance remain a release gate.',
    }, indent=2) + '\n')


if __name__ == '__main__':
    {'prepare': prepare, 'package': package, 'manifest': manifest}[sys.argv[1]]()
