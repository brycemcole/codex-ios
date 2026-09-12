# Codex for jailbroken iOS

Native OpenAI Codex CLI 0.147.0, packaged for jailbroken iPhones and iPads.

Two architectures are published, because a 64-bit iOS 13 device and a 32-bit iOS 9
device cannot run the same binary:

- `com.brycemcole.codex-ios` — arm64, iOS 13 or newer
- `com.brycemcole.codex-ios-armv7` — armv7, iOS 9

## Compatibility

### arm64 — `com.brycemcole.codex-ios`

| | |
| --- | --- |
| Minimum iOS | 13.0 (`LC_BUILD_VERSION`, verified in the load commands) |
| Architecture | arm64, built for the ARMv8.0 baseline |
| Jailbreak | rootful |
| Devices | iPhone 5s and later, iPad Air and later |

### armv7 — `com.brycemcole.codex-ios-armv7`

| | |
| --- | --- |
| Minimum iOS | 9.0 (`LC_VERSION_MIN_IPHONEOS`, verified in the load commands) |
| Architecture | armv7, Cortex-A9 code generation |
| Jailbreak | rootful |
| Devices | iPhone 4S, iPad 2, iPad 3, iPad mini (1st gen), iPod touch (5th gen) |

Together the packages cover **iOS 9.0 through iOS 14.x**. The exact packages shipped
here carry no iOS 15+ support: iOS 15 and 16 require a rootless jailbreak, which
relocates everything under `/var/jb` instead of `/usr/bin` and
`/Library/MobileSubstrate`. A rootless build would be a separate package.

iOS 12 and earlier on arm64 is out of scope (32-bit armv7 is the iOS 9 path).

### What has actually been run

| Device | OS | Status |
| --- | --- | --- |
| iPhone 4S | iOS 9.3.6 | Verified. `com.brycemcole.codex-ios-armv7`, `codex --version` reports `codex-cli 0.147.0`, ChatGPT login succeeded, and a real request round-tripped to OpenAI |
| iPhone SE (1st gen) | iOS 13.1.2 | An equivalent arm64 build ran here previously; these exact packages have not been reinstalled on it since |
| Other arm64 devices, rootful iOS 13 and 14 | | Expected, not individually device-tested |
| Rootless iOS 15 and 16 | | Not packaged and not tested |

Build-side verification for these packages: the arm64 executable and the NewTerm shim
report an iOS 13.0 minimum in their Mach-O load commands, the armv7 executable reports
an iOS 9.0 minimum with a plain `armv7` CPU subtype, and the arm64 executable
disassembles with no ARMv8.1 LSE atomics in its code (so pre-A12 devices are not
required to implement them).

## Install

### iOS 13 or newer (arm64)

1. Add the Chariz repository to Sileo, Zebra, or Cydia.
2. Install [NewTerm 2 version 2.5](https://chariz.com/get/newterm).
3. Download both arm64 `.deb` files from the latest GitHub release.
4. Install the NewTerm compatibility package, then the Codex package:

```sh
sudo dpkg -i com.brycemcole.codex-newterm-compat_1.0.0-1_iphoneos-arm.deb
sudo dpkg -i com.brycemcole.codex-ios_0.147.0-1_iphoneos-arm.deb
```

### iOS 9 (armv7)

The stock NewTerm packages require iOS 10 or newer, so the release also carries a
NewTerm 2.0 build that targets iOS 9. It replaces `ws.hbang.newterm2` and is built
from the GPL-2.0 NewTerm source in this repository's build scripts.

1. Download the two armv7 `.deb` files from the latest GitHub release.
2. Install NewTerm for iOS 9, then the Codex package:

```sh
sudo dpkg -i com.brycemcole.newterm-ios9_2.0~beta3+codex1_iphoneos-arm.deb
sudo dpkg -i com.brycemcole.codex-ios-armv7_0.147.0-1_iphoneos-arm.deb
```

The armv7 Codex package installs the executable under `/var/lib/codex-ios/bin` and
puts a small launcher at `/usr/bin/codex`, because the jailbreak refuses to execute
new binaries copied directly into a managed data directory.

### First run

Fully close and reopen NewTerm, then run:

```sh
codex --version
codex login
codex
```

`codex login` uses `/usr/bin/uiopen` to open the authentication page. The packages do
not include credentials and do not alter an existing `/var/mobile/.codex` configuration.

## Build

Common requirements: macOS with Xcode and an iPhoneOS SDK, `git`, `dpkg-deb`, and `ldid`.

### arm64

Rust 1.94.0 with the `aarch64-apple-ios` target.

```sh
./scripts/prepare-codex.sh
./scripts/build-codex.sh
./scripts/build-newterm-shim.sh
./scripts/package.sh
```

### armv7

Rust 1.94.0 with `rust-src`, the iOS 9.3 SDK, and Theos for the NewTerm fork.

```sh
CODEX_IOS_ARCH=armv7 ./scripts/build-codex.sh
./scripts/build-newterm-ios9.sh
./scripts/package-armv7.sh
```

## Third-party components

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
