#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stage="$repo_root/.build/package-armv7"
dist="$repo_root/dist/armv7"
test -x "$dist/codex"
mkdir -p "$stage/DEBIAN" "$stage/var/lib/codex-ios/bin" "$stage/usr/bin"
cp "$dist/codex" "$stage/var/lib/codex-ios/bin/codex"
rm -f "$stage/usr/bin/codex"
cp "$repo_root/native/codex-launch" "$stage/usr/bin/codex"
cat > "$stage/DEBIAN/control" <<'EOF'
Package: com.brycemcole.codex-ios-armv7
Name: Codex for iPhone 4S
Version: 0.147.0-1
Architecture: iphoneos-arm
Description: Native OpenAI Codex CLI for jailbroken armv7 iOS 9 devices
Maintainer: Bryce Cole
Author: OpenAI and contributors
Section: Utilities
Depends: firmware (>= 9.0), bash, ca-certificates
Conflicts: com.brycemcole.codex-ios
Homepage: https://github.com/brycemcole/codex-ios
EOF
cat > "$stage/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
mkdir -p /var/mobile/.codex/packages/standalone/current
chown mobile:mobile /var/mobile/.codex /var/mobile/.codex/packages /var/mobile/.codex/packages/standalone /var/mobile/.codex/packages/standalone/current
chmod 700 /var/mobile/.codex
ln -sf /usr/bin/codex /var/mobile/.codex/packages/standalone/current/codex
EOF
cp "$repo_root/packaging/codex/DEBIAN/postrm" "$stage/DEBIAN/postrm"
chmod 755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/postrm" "$stage/var/lib/codex-ios/bin/codex"
chmod 755 "$stage/usr/bin/codex"
dpkg-deb --root-owner-group -Zgzip --build "$stage" "$dist/com.brycemcole.codex-ios-armv7_0.147.0-1_iphoneos-arm.deb"
cd "$dist"
shasum -a 256 ./*.deb > SHA256SUMS
