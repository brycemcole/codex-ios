# Codex for jailbroken iOS

Native OpenAI Codex CLI 0.147.0 packages for arm64 iPhones and iPads running iOS 13 or newer.

The release contains two Debian packages:

- \`com.brycemcole.codex-ios\`: the native \`/usr/bin/codex\` executable
- \`com.brycemcole.codex-newterm-compat\`: renderer and environment fixes for NewTerm 2.5

## Compatibility

| Device | Status |
| --- | --- |
| iPhone SE (1st generation), iOS 13.1.2, rootful jailbreak | Tested |
| Other arm64 devices on rootful iOS 13 | Expected |
| Rootful iOS 14 | Expected, not yet device-tested |
| Rootless iOS 15 and 16 | Not packaged yet |
| iOS 12 or armv7 | Unsupported |

The binary targets iOS 13.0 and ARMv8.0 so it does not require newer ARM LSE instructions. NewTerm 2 itself supports iOS 10–16.2, but this Codex build requires iOS 13 or newer.

## Install

1. Add the Chariz repository to Sileo, Zebra, or Cydia.
2. Install [NewTerm 2 version 2.5](https://chariz.com/get/newterm).
3. Download both \`.deb\` files from the latest GitHub release.
4. Install the NewTerm compatibility package, then the Codex package:

\`\`\`sh
sudo dpkg -i com.brycemcole.codex-newterm-compat_1.0.0-1_iphoneos-arm.deb
sudo dpkg -i com.brycemcole.codex-ios_0.147.0-1_iphoneos-arm.deb
\`\`\`

Fully close and reopen NewTerm, then run:

\`\`\`sh
codex --version
codex login
codex
\`\`\`

\`codex login\` uses \`/usr/bin/uiopen\` to open the authentication page. The package does not include credentials and does not alter an existing \`/var/mobile/.codex\` configuration.

## Build

Requirements:

- macOS with Xcode and the iPhoneOS SDK
- Rust 1.94.0 with the \`aarch64-apple-ios\` target
- \`git\`, \`dpkg-deb\`, and \`ldid\`

\`\`\`sh
./scripts/prepare-codex.sh
./scripts/build-codex.sh
./scripts/build-newterm-shim.sh
./scripts/package.sh
\`\`\`

Artifacts are written to \`dist/\`.

The port is based on OpenAI Codex tag \`rust-v0.147.0\`, commit \`be6e8eac029b183056b7e4402879f15d2c85f61b\`. The NewTerm shim builds against HASHBANG Productions NewTerm commit \`6201e1bdd3f56b9dae8af8a27ee45f09b28e1040\`.

## Licenses

Codex patches, build scripts, and packaging are Apache-2.0. \`newterm/NewTermCompatShim.m\` is GPL-2.0-only because it integrates with NewTerm. Upstream components retain their own licenses.
