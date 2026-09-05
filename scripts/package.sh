#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stage="$repo_root/.build/package"
dist="$repo_root/dist"

test -x "$dist/codex"
test -f "$dist/NewTermCompatShim.dylib"
rm -rf "$stage"

mkdir -p "$stage/codex/DEBIAN" "$stage/codex/usr/bin" "$stage/codex/usr/local/bin"
cp "$repo_root/packaging/codex/DEBIAN/control" "$stage/codex/DEBIAN/control"
cp "$repo_root/packaging/codex/DEBIAN/postinst" "$stage/codex/DEBIAN/postinst"
cp "$repo_root/packaging/codex/DEBIAN/postrm" "$stage/codex/DEBIAN/postrm"
cp "$dist/codex" "$stage/codex/usr/bin/codex"
ln -s /usr/bin/codex "$stage/codex/usr/local/bin/codex"
chmod 0755 "$stage/codex/DEBIAN/postinst" "$stage/codex/DEBIAN/postrm" "$stage/codex/usr/bin/codex"

mkdir -p "$stage/newterm/DEBIAN" "$stage/newterm/Library/MobileSubstrate/DynamicLibraries"
cp "$repo_root/packaging/newterm-compat/DEBIAN/control" "$stage/newterm/DEBIAN/control"
cp "$dist/NewTermCompatShim.dylib" "$stage/newterm/Library/MobileSubstrate/DynamicLibraries/NewTermCompatShim.dylib"
cp "$repo_root/newterm/NewTermCompatShim.plist" "$stage/newterm/Library/MobileSubstrate/DynamicLibraries/NewTermCompatShim.plist"
chmod 0644 "$stage/newterm/Library/MobileSubstrate/DynamicLibraries/NewTermCompatShim.plist"
chmod 0755 "$stage/newterm/Library/MobileSubstrate/DynamicLibraries/NewTermCompatShim.dylib"

dpkg-deb --root-owner-group --build "$stage/codex" "$dist/com.brycemcole.codex-ios_0.147.0-1_iphoneos-arm.deb"
dpkg-deb --root-owner-group --build "$stage/newterm" "$dist/com.brycemcole.codex-newterm-compat_1.0.0-1_iphoneos-arm.deb"

cd "$dist"
shasum -a 256 com.brycemcole.codex-ios_0.147.0-1_iphoneos-arm.deb \
    com.brycemcole.codex-newterm-compat_1.0.0-1_iphoneos-arm.deb > SHA256SUMS
