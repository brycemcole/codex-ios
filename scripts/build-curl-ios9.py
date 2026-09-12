#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import shutil
import struct
import subprocess
import urllib.request

root = Path(__file__).resolve().parent.parent
archive = root / '.build/curl-8.14.1.tar.xz'
if not archive.exists():
    with urllib.request.urlopen('https://curl.se/download/curl-8.14.1.tar.xz', timeout=60) as response:
        archive.write_bytes(response.read())
if hashlib.sha256(archive.read_bytes()).hexdigest() != 'f4619a1e2474c4bbfedc88a7c2191209c8334b48fa1f4e53fd584cc12e9120dd':
    raise SystemExit('curl source checksum mismatch')
source = root / '.build/curl-ios9'
source.mkdir(parents=True, exist_ok=True)
if not (source / 'CMakeLists.txt').exists():
    subprocess.run(['tar', '-xf', str(archive), '-C', str(source), '--strip-components=1'], check=True)
cmake = source / 'CMakeLists.txt'
text = cmake.read_text()
if 'if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")\n  find_library(CORESERVICES' not in text:
    text = text.replace('  find_library(CORESERVICES_FRAMEWORK NAMES "CoreServices")', '  if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")\n  find_library(CORESERVICES_FRAMEWORK NAMES "CoreServices")')
    text = text.replace('  list(APPEND CURL_LIBS "-framework CoreServices")', '  list(APPEND CURL_LIBS "-framework CoreServices")\n  endif()')
    cmake.write_text(text)
developer = Path(os.environ.setdefault('DEVELOPER_DIR', '/Applications/Xcode-beta.app/Contents/Developer'))
toolchain = developer / 'Toolchains/XcodeDefault.xctoolchain/usr/bin'
build = root / '.build/curl-ios9-make'
settings = {
    'CMAKE_MAKE_PROGRAM': '/usr/bin/make',
    'CMAKE_SYSTEM_NAME': 'iOS',
    'CMAKE_OSX_SYSROOT': str(root / '.build/legacy-sdks/iPhoneOS9.3.sdk'),
    'CMAKE_OSX_ARCHITECTURES': 'armv7',
    'CMAKE_OSX_DEPLOYMENT_TARGET': '9.0',
    'CMAKE_C_COMPILER': str(toolchain / 'clang'),
    'CMAKE_C_FLAGS': '-marm -mcpu=cortex-a9',
    'CMAKE_BUILD_TYPE': 'Release',
    'CMAKE_INSTALL_PREFIX': '/var/lib/codex-ios/tools/usr',
    'BUILD_SHARED_LIBS': 'ON', 'BUILD_STATIC_LIBS': 'OFF', 'BUILD_TESTING': 'OFF',
    'CURL_USE_SECTRANSP': 'ON', 'CURL_USE_OPENSSL': 'OFF', 'CURL_USE_LIBPSL': 'OFF',
    'CURL_USE_LIBSSH2': 'OFF', 'CURL_USE_LIBSSH': 'OFF', 'CURL_USE_GSSAPI': 'OFF',
    'USE_LIBIDN2': 'OFF', 'CURL_BROTLI': 'OFF', 'CURL_ZSTD': 'OFF', 'CURL_ZLIB': 'OFF',
    'USE_NGHTTP2': 'OFF', 'CURL_CA_BUNDLE': 'none', 'CURL_CA_PATH': 'none',
}
subprocess.run(['cmake', '-S', str(source), '-B', str(build), '-G', 'Unix Makefiles', *[f'-D{k}={v}' for k, v in settings.items()]], check=True)
subprocess.run(['cmake', '--build', str(build), '-j', '6'], check=True)
dest = root / '.build/ios9-tools/root/usr'
(dest / 'bin').mkdir(parents=True, exist_ok=True)
(dest / 'lib').mkdir(parents=True, exist_ok=True)
library = dest / 'lib/libcurl.4.dylib'
binary = dest / 'bin/curl'
shutil.copyfile(build / 'lib/libcurl.4.8.0.dylib', library)
shutil.copyfile(build / 'src/curl.app/curl', binary)
subprocess.run([str(toolchain / 'install_name_tool'), '-id', '/usr/lib/libcurl.4.dylib', str(library)], check=True)
subprocess.run([str(toolchain / 'install_name_tool'), '-change', '@rpath/libcurl.4.dylib', '/usr/lib/libcurl.4.dylib', str(binary)], check=True)
data = bytearray(library.read_bytes())
offset = 28
for _ in range(struct.unpack_from('<I', data, 16)[0]):
    command, size = struct.unpack_from('<II', data, offset)
    if command == 13:
        struct.pack_into('<II', data, offset + 16, 0x80000, 0x80000)
    offset += size
library.write_bytes(data)
for path in [library, binary]:
    path.chmod(0o755)
    subprocess.run(['ldid', '-S', str(path)], check=True)
licenses = dest / 'share/doc/curl'
licenses.mkdir(parents=True, exist_ok=True)
shutil.copyfile(source / 'COPYING', licenses / 'COPYING')
