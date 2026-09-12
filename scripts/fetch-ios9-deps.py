#!/usr/bin/env python3
import hashlib
from pathlib import Path
import subprocess
import urllib.request

root = Path(__file__).resolve().parent.parent
dest = root / '.build/ios9-deps'
dest.mkdir(parents=True, exist_ok=True)
packages = {
    'hashbangcommon_1.14.deb': 'be57913670d797137c7c8ef980cc1bfe9bbd2b8b02d3598d63215d83fc42014b',
    'com.rpetrich.rocketbootstrap_1.0.10_beta1.deb': 'd06e18eefbfcb40f3e3b215bfbccaf34091fb30b2ccb1e4f6c519aa91d2b7248',
    'localeutf8_1.0-1.deb': '6339ffcaf3e44f4c1e3821405032cfb961e0952940f8a1b76a357a9dbecdf548',
    'jp.ashikase.techsupport_1.5.0.1-1_iphoneos-arm.deb': 'f24f4c319d717e9a611a2c58eb79d0ff1a760c54eff286cc5abbf67bb51d6634',
    'jp.ashikase.libpackageinfo_1.1.0.1-1_iphoneos-arm.deb': '4ad8e1e5995e13d94ed110d9af48dbeb7be51f674173678fabac07f7df4fb548',
}
for name, digest in packages.items():
    path = dest / name
    if not path.is_file():
        with urllib.request.urlopen('http://apt.thebigboss.org/repofiles/cydia/debs2.0/' + name, timeout=30) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != digest:
            raise SystemExit('Checksum mismatch: ' + name)
        path.write_bytes(data)
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise SystemExit('Checksum mismatch: ' + name)
subprocess.run(['dpkg-deb', '-x', str(dest / 'hashbangcommon_1.14.deb'), str(dest / 'cephei')], check=True)
