# Pinned libuv C SDK

`scripts/toolchain libuv` prints the verified SDK prefix without invoking
Cargo, rustc, rustup or cargo-c. It uses the same source/artifact cache as
the other pinned C libraries. `NUPP_NATIVE_JOBS` bounds build concurrency;
`NUPP_TOOLCHAIN_DIR`, `NUPP_HOST_SOURCE_DIR` and `NUPP_HOST_OFFLINE=1`
select a shared cache and offline archives. Cross-target requests refuse
instead of returning host output.

The pin is unchanged upstream libuv 1.53.0, from
[dist.libuv.org](https://dist.libuv.org/dist/v1.53.0/libuv-v1.53.0.tar.gz),
SHA-256 `cb0d6dd2128d5a95bd242c6cc982a24fe608fa93da57b6b4ec763b0018c53e64`.
The [latest release](https://github.com/libuv/libuv/releases/latest),
[security policy](https://github.com/libuv/libuv/blob/v1.53.0/SECURITY.md)
and [published advisories](https://github.com/libuv/libuv/security/advisories)
were checked November 17, 2026. The policy supports the latest v1.x release.
The published domain-lookup advisory GHSA-f74f-cvh7-c6q6 names 1.48.0 as
its patched version. This pin is later; recheck advisories on every upgrade.
The archive digest was verified over HTTPS; detached signatures were not verified.

CMake builds C11 shared libuv with upstream tests and benchmarks disabled.
The SDK carries `uv.h`, `uv/*`, shared libraries, Windows import libraries,
upstream CMake exports and the static archive those exports reference.
The pkg-config metadata uses its installed location, not a build-time prefix.
`identity` records the source, target, compiler/SDK/configuration digest and
recipe identity. `files.sha256` covers the matched headers, binaries, loader
aliases and notices. Altered cached files refuse; each target has its own key.

Upstream's MIT `LICENSE` and `LICENSE-extra` are compared byte for byte with
committed notices. The artifact also includes the complete BSD tree and ISC
address-conversion source notices. Ship the artifact's `notices/` with binaries.

The supported host triples are macOS ARM64/x64, GNU Linux ARM64/x64 and
Windows MSVC x64. Upstream requires macOS 11+, Linux 3.10+/glibc 2.17+, or
Windows 10+/VS2017+. Actual deployment requirements also depend on the SDK
and compiler used to build each artifact; no older-system compatibility is
inferred from a newer CI runner.

Use upstream's `find_package(libuv 1.53.0 EXACT CONFIG REQUIRED)` with
`libuv_DIR` set to `<prefix>/lib/cmake/libuv`, then link `libuv::uv`.
The fixture under `tests/fixtures/libuv` shows this C-only consumer.
For Nupp's existing configured native-library path, use library name `uv`
and set its environment override to the verified shared file:

| Target | Shared file |
| --- | --- |
| macOS | `<prefix>/lib/libuv.dylib` |
| GNU Linux | `<prefix>/lib/libuv.so` |
| Windows | `<prefix>/bin/uv.dll` |

The existing project resolver and build-library staging code can carry this
file as `@lib/<filename>` and fingerprint its bytes. Do not add another
loader or sidecar packager. ELF/CMake consumers also need the versioned
loader aliases; preserve the SDK's `lib/` symlinks when moving a full SDK.

`sh .github/scripts/test-libuv.sh` verifies offline warm reuse, corrupt
header/manifest refusal, version/target refusal, the upstream relocatable
CMake export, matching runtime/header ABI sizes, one timer and close drain,
and a moved package loading the exact sidecar. Fail-fast Rust tool shims
cover provisioning, configuration, compilation and execution. The existing
five-target C-library workflow runs it and uploads bounded ABI, identity,
manifest and timing receipts.

This provides SDK build and consumption only. Reactor, process, file, network,
browser and final Rust-deletion integration need their own acceptance tests.
