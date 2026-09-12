#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$repo_root/.build/codex"
sdk_path="$repo_root/.build/legacy-sdks/iPhoneOS9.3.sdk"
toolchain=${RUST_TOOLCHAIN:-1.94.0}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
export IPHONEOS_DEPLOYMENT_TARGET=9.0
export RUSTC_BOOTSTRAP=1

test -d "$source_dir/codex-rs"
python3 "$repo_root/scripts/prepare-legacy-sdks.py"
rustup component add rust-src --toolchain "$toolchain"
rustup run "$toolchain" rustc -Z unstable-options --print target-spec-json --target armv7s-apple-ios > "$repo_root/.build/armv7-apple-ios.json"
python3 - "$repo_root" <<'PY'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
p = root / '.build/armv7-apple-ios.json'
target = json.loads(p.read_text())
target.update(cpu='cortex-a9', features='+v7,+vfp3,+neon,-vfp4', **{'has-thread-local': False})
target['metadata']['description'] = 'ARMv7-A iPhone 4S iOS 9, Cortex-A9 code generation'
target['linker'] = str(root / 'scripts/armv7-linker.py')
target['pre-link-args'] = {'darwin-cc': ['-isysroot', str(root / '.build/legacy-sdks/iPhoneOS9.3.sdk')]}
p.write_text(json.dumps(target, indent=2) + '\n')
p = root / '.build/legacy-sdks/iPhoneOS9.3.sdk/usr/lib/libSystem.B.tbd'
text = p.read_text()
if '_memcpy,' not in text:
    text = text.replace('symbols:            [ ___System_BVersionNumber', 'symbols:            [ _memcpy, _memcmp, _memset, _memmove, _bzero, ___System_BVersionNumber')
    p.write_text(text)
PY

xcrun clang -target armv7s-apple-ios9.0 -mcpu=cortex-a9 -marm -O2 -isysroot "$sdk_path" \
    -c "$repo_root/native/ios9-compat.c" -o "$repo_root/.build/ios9-compat.o"

export CARGO_HOME="$repo_root/.build/cargo-home"
export CARGO_TARGET_DIR="$repo_root/.build/target-armv7"
cd "$source_dir/codex-rs"
rustup run "$toolchain" cargo fetch --locked
python3 - "$CARGO_HOME" <<'PY'
from pathlib import Path
import sys
for p in Path(sys.argv[1]).glob('registry/src/*/aws-lc-sys-0.39.0/aws-lc/crypto/internal.h'):
    text = p.read_text()
    if 'defined(OPENSSL_C11_ATOMIC) && !defined(__APPLE__)' not in text:
        p.write_text(text.replace('#if defined(OPENSSL_C11_ATOMIC)', '#if defined(OPENSSL_C11_ATOMIC) && !defined(__APPLE__)', 1))
for p in Path(sys.argv[1]).glob('registry/src/*/aws-lc-sys-0.39.0/aws-lc/third_party/jitterentropy/jitterentropy-library/jitterentropy-base-user.h'):
    text = p.read_text()
    include = '#include <CoreServices/CoreServices.h>'
    if '#if !defined(__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__)' not in text:
        p.write_text(text.replace(include, '#if !defined(__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__)\n' + include + '\n#endif'))
for p in Path(sys.argv[1]).glob('registry/src/*/aws-lc-sys-0.39.0/aws-lc/crypto/rand_extra/ccrandomgeneratebytes.c'):
    text = p.read_text()
    if '#include <CommonCrypto/CommonCryptor.h>' not in text:
        p.write_text(text.replace('#include <CommonCrypto/CommonRandom.h>', '#include <CommonCrypto/CommonCryptor.h>\n#include <CommonCrypto/CommonRandom.h>'))
for p in Path(sys.argv[1]).glob('registry/src/*/pagable-0.4.1/src/pagable_arc.rs'):
    text = p.read_text()
    original = '#[cfg(target_pointer_width = "32")]\nstatic_assertions::assert_eq_size!(PagableArcInner<[usize; 4]>, [usize; 12]);'
    replacement = '#[cfg(all(target_pointer_width = "32", not(target_vendor = "apple")))]\nstatic_assertions::assert_eq_size!(PagableArcInner<[usize; 4]>, [usize; 12]);\n#[cfg(all(target_pointer_width = "32", target_vendor = "apple"))]\nstatic_assertions::assert_eq_size!(PagableArcInner<[usize; 4]>, [usize; 10]);'
    p.write_text(text.replace(original, replacement))
for p in Path(sys.argv[1]).glob('registry/src/*/serial2-0.2.33/src/sys/unix/apple.rs'):
    p.write_text(p.read_text().replace('const IOCTL_IOSSIOSPEED: u64', 'const IOCTL_IOSSIOSPEED: libc::c_ulong'))
PY
export CFLAGS_armv7_apple_ios="-target armv7s-apple-ios9.0 -mcpu=cortex-a9 -marm -isysroot $sdk_path"
export CXXFLAGS_armv7_apple_ios="$CFLAGS_armv7_apple_ios"
export AWS_LC_SYS_CFLAGS_armv7_apple_ios="$CFLAGS_armv7_apple_ios"
export BINDGEN_EXTRA_CLANG_ARGS_armv7_apple_ios="$CFLAGS_armv7_apple_ios"
export CARGO_PROFILE_A7_FAST_OPT_LEVEL=2
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-6}

cd "$source_dir/codex-rs"
python3 "$repo_root/scripts/build-ring-ios9.py"
rustup run "$toolchain" cargo build --locked -Z build-std=std,panic_abort \
    --profile a7-fast --target "$repo_root/.build/armv7-apple-ios.json" --bin codex
mkdir -p "$repo_root/dist/armv7"
cp "$CARGO_TARGET_DIR/armv7-apple-ios/a7-fast/codex" "$repo_root/dist/armv7/codex"
xcrun strip -x "$repo_root/dist/armv7/codex"
ldid -S "$repo_root/dist/armv7/codex"
