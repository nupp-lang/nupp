# Pinned shared C dependencies

`scripts/toolchain zlib`, `scripts/toolchain openssl` and
`scripts/toolchain libcurl` print verified installation prefixes. They build
the selected source archives with a C compiler, CMake, Perl and the platform
SDK. Windows uses the MSVC x64 developer environment and native Windows Perl
(such as Strawberry Perl) ahead of Git's MSYS Perl on `PATH`. Keep the MSVC
compiler/linker directory ahead of Git's `link.exe` too. Rust tools are
not inputs.

`scripts/toolchain isal` builds the native CRC bundle using the same contracts.
It includes upstream CPU dispatch and portable C fallback. x86 builds also
need NASM; CI provides it. See [CRC routing and state](crc-isal.md) for
the public caller path, packaged headers/static/shared libraries, tests,
and the retained browser/Rust limits.

The source digests live in `scripts/toolchain.pins`; notices are compared
byte for byte with the verified sources. A missing archive in offline mode,
wrong digest, mismatched host target, or damaged cached header/library refuses
instead of selecting a system installation. Loader symlinks are verified too.

Cache keys include the target, compiler/configuration digest, recipe, source
digest and dependency identities. Worktrees share this cache. Curl is built
against the exact provisioned OpenSSL and zlib files and carries their matching
shared sidecars. An unrelated curl recipe edit does not rebuild OpenSSL or zlib.

`NUPP_TOOLCHAIN_DIR` selects an isolated cache; `NUPP_HOST_SOURCE_DIR` supplies
verified archives offline with `NUPP_HOST_OFFLINE=1`. `NUPP_NATIVE_TARGET` must
match the host. Cross compilation requires a future explicit target adapter.

## Validation and availability

`node --test tests/tools/toolchain/clibraries.test.mjs` uses synthetic files to
test verification, corruption refusal, locking and reuse. The Nupp pin suites
run those provisioning contracts; they do not claim native execution.

`sh .github/scripts/test-c-libraries.sh` builds and executes the real upstream
C ABI probe. It checks codec round trips, digest/HMAC vectors, SSL context
construction, matching headers/runtime versions and curl capabilities. Curl
enables HTTP/HTTPS, proxy/SOCKS and zlib; alternate TLS backends, unrelated
protocols and HTTP/2/3 are disabled. File URLs must fail.

The `Pinned C libraries` workflow runs this probe on macOS ARM64/x64, Linux
GNU ARM64/x64 and Windows MSVC x64. Each target needs its own passing receipt;
one platform does not establish another. The workflow blocks Rust tool
invocations and uploads only ABI data, public dependency identities and timings.

`provisionSeconds` measures the first provisioning call in that run, which may
already have a cache. `warmReuseSeconds` measures verified reuse with no build
output. A cold source build and reuse have different costs; neither is a
prebuilt-download timing. Native TLS trust policy and HTTP client behavior need
their own adapter tests and independent peers.

These artifacts do not switch the frozen VM's providers. OpenSSL supplies one
shared dependency for later TLS, curl and crypto use; no extra C wrappers are
needed. Before enabling another primitive, recheck upstream security status and
update the explicit source pin when required.
