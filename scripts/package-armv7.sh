#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
codex_version=${CODEX_IOS_VERSION:-0.147.0}
build_rev=${CODEX_IOS_BUILD_REV:-1}
pkg_id=${AGENT_PKG_ID:-com.brycemcole.codex-ios-armv7}
pkg_name=${AGENT_PKG_NAME:-Codex for iPhone 4S}
pkg_desc=${AGENT_PKG_DESC:-Native OpenAI Codex CLI for jailbroken armv7 iOS 9 devices}
pkg_conflicts=${AGENT_PKG_CONFLICTS:-com.brycemcole.codex-ios}
stage="$repo_root/.build/package-armv7"
dist="$repo_root/dist/armv7"
install_dir=${AGENT_INSTALL_DIR:-/var/lib/codex-ios}
launcher_name=${AGENT_LAUNCHER_NAME:-codex}
bin_name=${AGENT_BIN_NAME:-codex}
test -x "$dist/$bin_name"
mkdir -p "$stage/DEBIAN" "$stage$install_dir/bin" "$stage/usr/bin"
cp "$dist/$bin_name" "$stage$install_dir/bin/$bin_name"
rm -f "$stage/usr/bin/$launcher_name"
cp "$repo_root/native/codex-launch" "$stage/usr/bin/$launcher_name"
cat > "$stage/DEBIAN/control" <<EOF
Package: $pkg_id
Name: $pkg_name
Version: $codex_version-$build_rev
Architecture: iphoneos-arm
Description: $pkg_desc
Maintainer: Bryce Cole
Author: OpenAI and contributors
Section: Utilities
Depends: firmware (>= 9.0), bash, ca-certificates
Conflicts: $pkg_conflicts
Homepage: https://github.com/brycemcole/codex-ios
EOF
cat > "$stage/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
mkdir -p /var/mobile/.codex/packages/standalone/current
chown mobile:mobile /var/mobile/.codex /var/mobile/.codex/packages /var/mobile/.codex/packages/standalone /var/mobile/.codex/packages/standalone/current
chmod 700 /var/mobile/.codex
ln -sf /usr/bin/$launcher_name /var/mobile/.codex/packages/standalone/current/$launcher_name
EOF
cp "$repo_root/packaging/codex/DEBIAN/postrm" "$stage/DEBIAN/postrm"
chmod 755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/postrm" "$stage$install_dir/bin/$bin_name"
chmod 755 "$stage/usr/bin/$launcher_name"
dpkg-deb --root-owner-group -Zgzip --build "$stage" "$dist/${pkg_id}_${codex_version}-${build_rev}_iphoneos-arm.deb"
cd "$dist"
shasum -a 256 ./*.deb > SHA256SUMS
