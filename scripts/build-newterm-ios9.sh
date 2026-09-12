#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$repo_root/.build/NewTerm-ios9"
base=b40b8c2875839e66a2ce6ee25b4d6a4512c60a7e
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
export THEOS=${THEOS:-/Users/brycecole/theos}

python3 "$repo_root/scripts/prepare-legacy-sdks.py"
python3 "$repo_root/scripts/fetch-ios9-deps.py"
test -d "$repo_root/.build/NewTerm/.git"
test -f "$repo_root/.build/ios9-deps/cephei/usr/lib/Cephei.framework/Cephei"
if [ ! -d "$source_dir/NewTerm" ]; then
    mkdir -p "$source_dir"
    git -C "$repo_root/.build/NewTerm" archive "$base" | tar -x -C "$source_dir"
fi
if git -C "$source_dir" apply --check "$repo_root/patches/newterm-ios9.patch" 2>/dev/null; then
    git -C "$source_dir" apply "$repo_root/patches/newterm-ios9.patch"
else
    git -C "$source_dir" apply --reverse --check "$repo_root/patches/newterm-ios9.patch"
fi
make -C "$source_dir" package FINALPACKAGE=1 ARCHS=armv7 TARGET=iphone:clang:10.3:9.0 \
    THEOS_SDKS_PATH="$repo_root/.build/legacy-sdks" \
    ADDITIONAL_CFLAGS='-marm -Wno-error' \
    ADDITIONAL_LDFLAGS="-F$repo_root/.build/ios9-deps/cephei/usr/lib -rpath /usr/lib"
mkdir -p "$repo_root/dist/armv7"
cp "$source_dir"/packages/com.brycemcole.newterm-ios9_*.deb "$repo_root/dist/armv7/"
