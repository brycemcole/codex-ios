#!/usr/bin/env python3
import os
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
source = next((root / '.build/cargo-home/registry/src').glob('*/ring-0.17.14'))
dest = root / '.build/ring-ios9'
dest.mkdir(parents=True, exist_ok=True)
prelude = dest / 'enable-arm-assembly.h'
prelude.write_text('#include <ring-core/target.h>\n#undef OPENSSL_NO_ASM\n')
developer = Path(os.environ.get('DEVELOPER_DIR', '/Applications/Xcode-beta.app/Contents/Developer'))
clang = developer / 'Toolchains/XcodeDefault.xctoolchain/usr/bin/clang'
files = re.findall(r'\(&\[ARM\], "([^"]+\.pl)"\)', (source / 'build.rs').read_text())
assembly = []
for name in files:
    output = dest / (Path(name).stem + '-ios32.S')
    subprocess.run(['perl', str(source / name), 'ios32', str(output)], check=True)
    assembly.append(output)
poly = (source / 'crypto/poly1305/poly1305_arm_asm.S').read_text()
poly = poly.replace('defined(__ELF__)', 'defined(__APPLE__)')
poly = re.sub(r'^\.(?:fpu|type).*\n', '', poly, flags=re.M)
poly = poly.replace('.hidden ', '.private_extern ')
poly = re.sub(r'\bopenssl_poly1305_neon2_(blocks|addmulmod)\b', r'_openssl_poly1305_neon2_\1', poly)
output = dest / 'poly1305-ios32.S'
output.write_text(poly)
assembly.append(output)
objects = []
for source_file in assembly:
    output = source_file.with_suffix('.o')
    subprocess.run([str(clang), '-target', 'armv7s-apple-ios9.0', '-mcpu=cortex-a9', '-marm', '-O2', '-isysroot', str(root / '.build/legacy-sdks/iPhoneOS9.3.sdk'), '-I' + str(source / 'include'), '-I' + str(source / 'pregenerated'), '-include', str(prelude), '-c', str(source_file), '-o', str(output)], check=True)
    objects.append(str(output))
subprocess.run([str(developer / 'Toolchains/XcodeDefault.xctoolchain/usr/bin/libtool'), '-static', '-o', str(dest / 'libring-ios9.a'), *objects], check=True)
