# Third-party notices

- OpenAI Codex is licensed under Apache-2.0. This repository distributes patched
  builds from tag `rust-v0.147.0`.
- NewTerm is licensed under GPL-2.0. For arm64 the repository does not redistribute
  the NewTerm app; it provides source for a compatibility shim and directs users to
  the official Chariz package. The armv7 release does redistribute a NewTerm 2.0
  build that targets iOS 9, including NewTerm and its VT100 sources compiled from
  upstream commit `b40b8c2875839e66a2ce6ee25b4d6a4512c60a7e` plus the patch at
  `patches/newterm-ios9.patch`; that patch and the build scripts are the complete
  corresponding source for the modifications.
- Codex dependencies retain their upstream licenses. Cargo metadata in the upstream
  source identifies the complete dependency set.
