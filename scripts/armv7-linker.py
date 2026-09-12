#!/usr/bin/env python3
import os
from pathlib import Path
import struct
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
developer = Path(os.environ.get("DEVELOPER_DIR", "/Applications/Xcode-beta.app/Contents/Developer"))
clang = developer / "Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
linker = Path(os.environ.get("CODEX_IOS_ARMV7_LD", "/Library/Developer/CommandLineTools/usr/bin/ld-classic"))
if not linker.is_file():
    raise SystemExit("Set CODEX_IOS_ARMV7_LD to an ld64 classic linker with ARM branch-island support")
args = sys.argv[1:]
args = [arg for index, arg in enumerate(args)
        if not (arg == "-framework" and index + 1 < len(args) and args[index + 1] == "UserNotifications")
        and not (arg == "UserNotifications" and index and args[index - 1] == "-framework")]
for index, arg in enumerate(args):
    if index and args[index - 1] == "-arch":
        args[index] = "armv7s"
    if index and args[index - 1] == "-target":
        args[index] = "armv7s-apple-ios9.0"
    if arg.startswith("-miphoneos-version-min="):
        args[index] = "-miphoneos-version-min=9.0"
args.extend(["-marm", "-Wl,-segalign,0x1000", str(root / ".build/ios9-compat.o"), str(root / ".build/ring-ios9/libring-ios9.a")])
args.append("-fuse-ld=" + str(linker))
result = subprocess.run([str(clang), *args])
if result.returncode:
    raise SystemExit(result.returncode)
output = Path(args[args.index("-o") + 1])
data = bytearray(output.read_bytes())
if struct.unpack_from("<II", data) != (0xFEEDFACE, 12):
    raise SystemExit("Expected a 32-bit ARM Mach-O executable")
struct.pack_into("<I", data, 8, 9)
output.write_bytes(data)
