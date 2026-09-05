#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$repo_root/.build/NewTerm"
developer_dir=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
commit=6201e1bdd3f56b9dae8af8a27ee45f09b28e1040

mkdir -p "$repo_root/.build" "$repo_root/dist"
if [ ! -d "$source_dir/.git" ]; then
    git clone https://github.com/hbang/NewTerm.git "$source_dir"
fi
git -C "$source_dir" fetch origin
git -C "$source_dir" checkout --detach "$commit"

export DEVELOPER_DIR="$developer_dir"
sdk_path=$(xcrun --sdk iphoneos --show-sdk-path)
raw="$repo_root/.build/NewTermCompatShim.raw.dylib"

xcrun clang -dynamiclib -arch arm64 -isysroot "$sdk_path" -miphoneos-version-min=13.0 \
    -fobjc-arc -fobjc-exceptions -fmodules -O2 \
    -I"$source_dir/Common" -I"$source_dir/Common/VT100" -I"$source_dir/Common/Supporting Files" \
    -framework Foundation -framework UIKit \
    -Wl,-install_name,/Library/MobileSubstrate/DynamicLibraries/NewTermCompatShim.dylib \
    -undefined dynamic_lookup "$repo_root/newterm/NewTermCompatShim.m" -o "$raw"

xcrun vtool -set-build-version ios 13.0 27.0 \
    -output "$repo_root/dist/NewTermCompatShim.dylib" "$raw"
ldid -S "$repo_root/dist/NewTermCompatShim.dylib"
