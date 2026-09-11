#!/usr/bin/env python3
"""Verify two independent SSH authentications to an installed Windows ARM64 VM.

The host key must already be verified and stored in --known-hosts. Passwords
remain interactive in the caller's terminal; they are never arguments or logs.
No guest configuration is changed. Public evidence excludes the login name.
"""
import argparse
import base64
import json
from pathlib import Path
import subprocess
import time

COMMAND = r"""
$ErrorActionPreference = 'Stop'
try {
  $os = Get-CimInstance Win32_OperatingSystem
  $cpu = @(Get-CimInstance Win32_Processor | Select-Object -ExpandProperty Architecture -Unique)
  if ($os.Caption -notlike '*Windows*' -or $cpu.Count -ne 1 -or $cpu[0] -ne 12) {
    throw 'Expected Windows on ARM64'
  }
  [ordered]@{os=$os.Caption; version=$os.Version; build=$os.BuildNumber;
    architecture='ARM64'; processorArchitectureCode=[int]$cpu[0]} | ConvertTo-Json -Compress
  exit 0
} catch { exit 1 }
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', required=True, type=int)
    parser.add_argument('--user', help='Omit to enter the guest login name privately in the terminal')
    parser.add_argument('--known-hosts', required=True, type=Path)
    parser.add_argument('--identity', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.user is None:
        args.user = input('Windows SSH login name: ').strip()
    if not 1024 <= args.port <= 65535 or not args.user or args.user.startswith('-'):
        parser.error('Select a nonprivileged port and a valid guest login name')
    if not args.known_hosts.is_file():
        parser.error('Verify the guest host key and prepare --known-hosts first')
    command = ['ssh', '-T', '-S', 'none', '-o', 'ControlMaster=no',
               '-o', 'ControlPath=none', '-o', 'StrictHostKeyChecking=yes',
               '-o', f'UserKnownHostsFile={args.known_hosts.resolve()}',
               '-o', 'ConnectTimeout=10', '-o', 'ConnectionAttempts=1',
               '-o', 'ServerAliveInterval=10', '-o', 'ServerAliveCountMax=2',
               '-p', str(args.port), '-l', args.user]
    if args.identity:
        command += ['-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes',
                    '-i', str(args.identity.resolve())]
    encoded = base64.b64encode(COMMAND.encode('utf-16le')).decode('ascii')
    command += ['127.0.0.1', 'powershell.exe -NoProfile -NonInteractive -EncodedCommand ' + encoded]
    evidence = {'schema': 1, 'guest': 'Windows ARM64', 'host': '127.0.0.1',
                'port': args.port, 'independentAuthentications': True, 'sessions': []}
    for label in ['sshLogin', 'sshReconnect']:
        print(f'{label}: authenticate in this terminal if prompted.', flush=True)
        record = {'name': label, 'checkedAt': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}
        try:
            result = subprocess.run(command, stdout=subprocess.PIPE, timeout=180)
            record['exitCode'] = result.returncode
            if result.returncode != 0:
                raise ValueError('SSH or guest command failed')
            guest = json.loads(result.stdout.decode('utf-8-sig').strip())
            if guest.get('architecture') != 'ARM64' or guest.get('processorArchitectureCode') != 12:
                raise ValueError('Guest architecture was not verified')
            record.update(status='pass', guest=guest)
        except (ValueError, UnicodeError, subprocess.TimeoutExpired):
            record['status'] = 'fail'
        evidence['sessions'].append(record)
        # Save each completed attempt, even if the next session is interrupted.
        args.output.write_text(json.dumps(evidence, indent=2) + '\n')
        if record['status'] != 'pass':
            return 1
    print('PASS: two separate SSH authentications and Windows ARM64 commands.', flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
