#!/usr/bin/env python3
import hashlib
from pathlib import Path
import shutil
import subprocess
import urllib.request
import sys

root = Path(__file__).resolve().parent.parent
build = root / '.build/ios9-tools'
build.mkdir(parents=True, exist_ok=True)
packages = {
    'coreutils_8.12-13_iphoneos-arm.deb': 'fe1966e5f72064c8a0dbe0a00591f7be0803d36194aed1e03bd7c959b1043247',
    'expat_2.0.1-3_iphoneos-arm.deb': '9c187fd9bf69e217faec8bcb4f98df32c35c64bd4f9a7e348041e69cc53957b8',
    'git_2.8.1-5_iphoneos-arm.deb': '9356d45144672ce51d555292f3395fe3cbf31333cfb70723a33abab9f950ff8b',
}
for name, digest in packages.items():
    path = build / name
    if not path.exists():
        with urllib.request.urlopen('http://apt.saurik.com/debs/' + name, timeout=30) as response:
            path.write_bytes(response.read())
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise SystemExit('Checksum mismatch: ' + name)
    subprocess.run(['dpkg-deb', '-x', str(path), str(build / 'root')], check=True)

subprocess.run([sys.executable, str(root / 'scripts/build-curl-ios9.py')], check=True)

stage = build / 'package'
payload = stage / 'var/lib/codex-ios/tools/usr'
shutil.copytree(build / 'root/usr', payload, dirs_exist_ok=True, symlinks=True)
commands = stage / 'usr/local/bin'
commands.mkdir(parents=True, exist_ok=True)
for binary in (payload / 'bin').iterdir():
    link = commands / binary.name
    if binary.name == 'git':
        if link.is_symlink():
            link.unlink()
        link.write_text('#!/bin/sh\nexport GIT_EXEC_PATH=/var/lib/codex-ios/tools/usr/libexec/git-core\nexport GIT_TEMPLATE_DIR=/var/lib/codex-ios/tools/usr/share/git-core/templates\nexec /var/lib/codex-ios/tools/usr/bin/git "$@"\n')
        link.chmod(0o755)
    elif not link.exists() and not link.is_symlink():
        link.symlink_to('/var/lib/codex-ios/tools/usr/bin/' + binary.name)
libraries = stage / 'usr/lib'
libraries.mkdir(parents=True, exist_ok=True)
for name in ['libcurl.4.dylib', 'libexpat.1.dylib']:
    link = libraries / name
    if not link.is_symlink():
        link.symlink_to('/var/lib/codex-ios/tools/usr/lib/' + name)
control = stage / 'DEBIAN'
control.mkdir(parents=True, exist_ok=True)
(control / 'control').write_text('Package: com.brycemcole.codex-ios-tools\nName: Codex iOS 9 Shell Tools\nVersion: 1.0-1\nArchitecture: iphoneos-arm\nMaintainer: Bryce Cole\nSection: Utilities\nDepends: bash, openssl\nDescription: Shell utilities installed on the data partition for Codex\n')
dist = root / 'dist/armv7'
dist.mkdir(parents=True, exist_ok=True)
subprocess.run(['dpkg-deb', '--root-owner-group', '-Zgzip', '--build', str(stage), str(dist / 'com.brycemcole.codex-ios-tools_1.0-1_iphoneos-arm.deb')], check=True)
