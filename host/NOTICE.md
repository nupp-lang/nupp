# Third-party notices

The compiler and the VM runtime it is stamped onto carry third-party code, so a
binary built from them is a distribution of those selected copies. Their
licenses ask that notices travel with the copies, which is what this directory
provides.

Ship `NOTICE.md` and `notices/` beside a binary the way a release archive ships
a README. Lunajson is committed under `src/nupp/runtime/vendor`; its notice is
repeated here so the release notices remain complete in one place.

| Dependency | Pinned at | License | Notice |
| --- | --- | --- | --- |
| [Lunajson](https://github.com/grafi-tt/lunajson) | `1.2.3` | MIT | [notices/lunajson-LICENSE.txt](notices/lunajson-LICENSE.txt) |
| Rust dependency graph | `Cargo.lock` | Mixed permissive licenses | [notices/Rust-dependencies.html](notices/Rust-dependencies.html) |
| [libffi](https://sourceware.org/libffi/) | as `libffi-sys` 4.2.2 bundles it | MIT | [notices/libffi-LICENSE.txt](notices/libffi-LICENSE.txt) |
| [libffi core C API](https://github.com/libffi/libffi) | `3.8.0` | MIT | [notices/libffi-core-LICENSE.txt](notices/libffi-core-LICENSE.txt) |
| [LuaJIT](https://luajit.org/) | `1edc3e52b67eaf6ce5f809be8e17d6862594b8bc` | MIT | [notices/LuaJIT-COPYRIGHT.txt](notices/LuaJIT-COPYRIGHT.txt) |
| [wgpu-native](https://github.com/gfx-rs/wgpu-native) | `v29.0.1.1` | MIT or Apache-2.0, plus dependency licenses | [MIT](notices/wgpu-native-LICENSE.MIT.txt), [Apache-2.0](notices/wgpu-native-LICENSE.APACHE.txt), [dependencies](notices/wgpu-native-Rust-dependencies.html) |
| [zlib](https://zlib.net/) | `1.4` | zlib | [notices/zlib-LICENSE.txt](notices/zlib-LICENSE.txt) |
| [OpenSSL](https://openssl-library.org/) | `3.5.9` | Apache-2.0 | [notices/OpenSSL-LICENSE.txt](notices/OpenSSL-LICENSE.txt) |
| [libcurl](https://curl.se/libcurl/) | `8.23.0` | curl | [notices/libcurl-LICENSE.txt](notices/libcurl-LICENSE.txt) |

`scripts/toolchain zlib`, `openssl` and `libcurl` build digest-pinned shared C
libraries with matched headers and notices. Curl uses those exact OpenSSL and
zlib artifacts. These are separate from the frozen VM's Rust dependencies;
provisioning them does not switch the VM's providers.

`scripts/wgpu-native` fetches an upstream prebuilt library and its matched
headers. Its independently pinned notice files travel with each cached copy.
This removes local Rust compilation from the GPU conformance jobs; the upstream
library still contains Rust code.

The VM runtime is Rust, and the locked Rust graph supplies it and the native
facilities a binary links, such as compression, networking and TLS. A build
that does not link one of those does not distribute it; the notices stay here
because each binary's facilities are decided independently. Lunajson's decoder
and encoder are vendored into the compiler's runtime library.

The runtime calls C through libffi, which the `libffi-sys` crate builds from the
C sources it bundles and links statically. The Rust notice covers the crate;
libffi's own notice is the C library's, copied from the source that crate
bundles.

LuaJIT is not part of a Nupp binary. `scripts/toolchain` builds the pinned
LuaJIT only as the interpreter LuaRocks runs on when a project installs a rock
dependency. Its notice also carries the public-domain statement for dlmalloc,
which LuaJIT includes; it is reproduced there rather than summarized here.

A copy here that no longer matches the source it came from is worse than none,
because it is a claim about what was distributed. `scripts/toolchain` compares
the LuaJIT notice against the one in the source it just verified. Bumping the
pin without updating the notice beside it therefore stops the build rather than
shipping the wrong text.

The Rust notice deliberately covers every third-party package in `Cargo.lock`,
including target-specific, build and development dependencies. This is broader
than any one binary, but makes the same notice set correct for every facility
and supported platform. Maintainers refresh it with cargo-about 0.9.2 and
`scripts/rust-dependency-notices --write`; ordinary builds and releases use the
committed result and do not need `cargo-about` or network access.
