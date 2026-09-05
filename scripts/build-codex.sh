#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$repo_root/.build/codex"
cargo_home="$repo_root/.build/cargo-home"
target_dir="$repo_root/.build/target"
developer_dir=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
toolchain=${RUST_TOOLCHAIN:-1.94.0}

test -d "$source_dir/codex-rs"
export DEVELOPER_DIR="$developer_dir"
export IPHONEOS_DEPLOYMENT_TARGET=13.0

rustup toolchain install "$toolchain" --profile minimal
rustup target add aarch64-apple-ios --toolchain "$toolchain"
xcrun --sdk iphoneos clang -target arm64-apple-ios13.0 -c "$repo_root/native/chkstk.c" -o "$repo_root/.build/chkstk.o"

export CARGO_HOME="$cargo_home"
export CARGO_TARGET_DIR="$target_dir"

cd "$source_dir/codex-rs"
rustup run "$toolchain" cargo fetch --locked

aws_header=$(find "$cargo_home/registry/src" -path '*/aws-lc-sys-0.39.0/aws-lc/crypto/internal.h' -print -quit)
test -n "$aws_header"
if ! grep -q 'defined(OPENSSL_C11_ATOMIC) && !defined(__APPLE__)' "$aws_header"; then
    perl -0pi -e 's/#if defined\(OPENSSL_C11_ATOMIC\)/#if defined(OPENSSL_C11_ATOMIC) \&\& !defined(__APPLE__)/' "$aws_header"
fi

flags='-target arm64-apple-ios13.0 -march=armv8-a+crypto -mno-outline-atomics'
export AWS_LC_SYS_CFLAGS_aarch64_apple_ios="$flags"
export CFLAGS_aarch64_apple_ios="$flags"
export TARGET_CFLAGS_aarch64_apple_ios="$flags"
export RUSTFLAGS="-C target-cpu=apple-a7 -C link-arg=$repo_root/.build/chkstk.o"

rustup run "$toolchain" cargo build --locked --profile a7-fast --target aarch64-apple-ios --bin codex
mkdir -p "$repo_root/dist"
cp "$target_dir/aarch64-apple-ios/a7-fast/codex" "$repo_root/dist/codex"
xcrun strip -x "$repo_root/dist/codex"
ldid -S "$repo_root/dist/codex"
