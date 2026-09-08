"""Disposable x86 SPICE framebuffer, keyboard and reconnect acceptance check."""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import socket
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--qemu', required=True, type=Path)
    parser.add_argument('--capture', required=True, type=Path)
    parser.add_argument('--viewer', required=True, type=Path)
    parser.add_argument('--firmware', required=True, type=Path)
    parser.add_argument('--registry', type=Path)
    parser.add_argument('--display-only', action='store_true')
    parser.add_argument('--keep-running', action='store_true')
    args = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix='qgs-', dir='/tmp')).resolve()
    root.chmod(0o700)
    print(f'Evidence: {root}', flush=True)
    environment = {**os.environ, 'XDG_CONFIG_HOME': str(root / 'client-config')}
    if args.registry:
        environment['GST_REGISTRY_1_0'] = str(args.registry.resolve())
    if args.display_only:
        environment.update(GST_PLUGIN_SYSTEM_PATH_1_0='', GST_PLUGIN_PATH_1_0='',
                           GST_REGISTRY_1_0=str(root / 'gst-registry.bin'))
    disk = root / 'input.img'
    subprocess.run(['nasm', '-f', 'bin', str(Path(__file__).with_name('input-probe.asm')),
                    '-o', str(disk)], check=True)
    with disk.open('r+b') as file:
        file.truncate(16 * 1024 * 1024)
    # These files allow a read-only Quickgui VmRepository inspection too.
    (root / 'spice-smoke.conf').write_text(f'guest_os="linux"\ndisk_img="{disk}"\n')
    spice, qmp = root / 'display %한.sock', root / 'qmp.sock'
    (root / 'spice-smoke.ports').write_text(f'unix,{spice}\n')
    accelerator, cpu = ('hvf', 'host') if platform.system() == 'Darwin' else ('tcg', 'max')
    with (root / 'qemu.log').open('w') as log:
        qemu = subprocess.Popen([
            str(args.qemu.resolve()), '-L', str(args.firmware.resolve()),
            '-machine', f'q35,accel={accelerator}', '-cpu', cpu, '-m', '256', '-smp', '1',
            '-nodefaults', '-device', 'vmware-svga', '-display', 'none',
            '-drive', f'file={disk},if=ide,format=raw,snapshot=on',
            '-spice', f'unix=on,addr={spice},disable-ticketing=on',
            '-qmp', f'unix:{qmp},server=on,wait=off',
            '-pidfile', str(root / 'spice-smoke.pid'),
            '-monitor', 'none', '-serial', 'none', '-nic', 'none',
            '-boot', 'order=c,strict=on', '-no-reboot',
        ], stdout=log, stderr=subprocess.STDOUT)
        viewer = None
        try:
            for _ in range(100):
                if qemu.poll() is not None:
                    raise RuntimeError((root / 'qemu.log').read_text())
                if qmp.exists():
                    break
                time.sleep(0.1)
            with socket.socket(socket.AF_UNIX) as sock:
                sock.settimeout(10)
                sock.connect(str(qmp))
                stream = sock.makefile('rwb', buffering=0)
                print('QMP:', stream.readline().decode().strip(), flush=True)

                def command(name, arguments=None):
                    request = {'execute': name}
                    if arguments is not None:
                        request['arguments'] = arguments
                    stream.write(json.dumps(request).encode() + b'\n')
                    while True:
                        line = stream.readline()
                        if not line:
                            raise RuntimeError('QMP connection closed')
                        response = json.loads(line)
                        if 'error' in response:
                            raise RuntimeError(response)
                        if 'return' in response:
                            return response['return']

                command('qmp_capabilities')
                print('SPICE server:', command('query-spice'), flush=True)
                time.sleep(3)
                for attempt in (1, 2):
                    subprocess.run([
                        str(args.capture.resolve()), f'spice+unix://{spice}',
                        str(root / f'spice-frame-{attempt}.png'),
                        *(['--send-k'] if attempt == 2 else []),
                    ], check=True, timeout=20, env=environment)
                    memory = command('human-monitor-command', {'command-line': 'xp /1bx 0x500'})
                    if not re.search(r':\s*0x0' + str(attempt - 1), memory):
                        raise RuntimeError(f'Unexpected keyboard probe result: {memory}')
                    print(f'Frame/keyboard/reconnect {attempt}: PASS', flush=True)
                    time.sleep(1)
                with (root / 'spicy.log').open('w') as viewer_log:
                    viewer = subprocess.Popen([
                        str(args.viewer.resolve()), f'--uri=spice+unix://{spice}',
                        '--title=Quickgui SPICE validation',
                    ], stdout=viewer_log, stderr=subprocess.STDOUT, env=environment)
                    for _ in range(45):
                        time.sleep(1)
                        state = command('query-spice')
                        types = {c.get('channel-type') for c in state.get('channels', [])}
                        if {1, 2, 3, 4}.issubset(types) or viewer.poll() is not None:
                            break
                    (root / 'spice-channels.json').write_text(json.dumps(state, indent=2))
                    if not {1, 2, 3, 4}.issubset(types) or viewer.poll() is not None:
                        raise RuntimeError(f'Viewer connection failed: {state}')
                    print('spicy main/display/input/cursor channels: PASS', flush=True)
                    (root / 'ready').touch()
                    if args.keep_running:
                        print(f'Create {root}/finish to stop this disposable VM.', flush=True)
                        while not (root / 'finish').exists():
                            if qemu.poll() is not None:
                                raise RuntimeError('Disposable VM exited unexpectedly')
                            time.sleep(1)
                    command('quit')
        finally:
            for process in (viewer, qemu):
                if process is not None and process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)


if __name__ == '__main__':
    main()
