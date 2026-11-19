# Third-party notices

The compiler and the runtime it is stamped onto carry third-party code, so a
binary built from them is a distribution of those copies. Their licenses ask
that the notices travel with the copies, which is what this directory provides.

Ship `NOTICE.md` and `notices/` beside a binary the way a release archive ships
a README.

| Dependency | Pinned at | License | Carried by | Notice |
| --- | --- | --- | --- | --- |
| Rust dependency graph | `Cargo.lock` | Mixed permissive licenses | VM runtime | [notices/Rust-dependencies.html](notices/Rust-dependencies.html) |
| [libffi](https://sourceware.org/libffi/), through `libffi-sys` | `libffi-sys` 4.2.2 | MIT | VM runtime | [notices/libffi-LICENSE.txt](notices/libffi-LICENSE.txt) |
| [ISA-L](https://github.com/intel/isa-l) | `2.32.1` | BSD-3-Clause | VM runtime, checksums | [license](notices/ISA-L-LICENSE.txt), [CRC notices](notices/ISA-L-CRC-LICENSE.txt) |
| [Lunajson](https://github.com/grafi-tt/lunajson) | `1.2.3` | MIT | Compiler runtime library | [notices/lunajson-LICENSE.txt](notices/lunajson-LICENSE.txt) |
| [libffi](https://github.com/libffi/libffi) | `3.8.0` | MIT | Native core foreign calls | [notices/libffi-core-LICENSE.txt](notices/libffi-core-LICENSE.txt) |
| [libuv](https://libuv.org/) | `1.53.0` | MIT | Native core TCP and DNS | [license](notices/libuv-LICENSE.txt), [Joyent-derived parts](notices/libuv-LICENSE-extra.txt) |
| [libcurl](https://curl.se/libcurl/) | `8.23.0` | curl | Native HTTP | [notices/libcurl-LICENSE.txt](notices/libcurl-LICENSE.txt) |
| [OpenSSL](https://openssl-library.org/) | `3.5.9` | Apache-2.0 | Native HTTP | [notices/OpenSSL-LICENSE.txt](notices/OpenSSL-LICENSE.txt) |
| [zlib](https://zlib.net/) | `1.4` | zlib | Compression, native HTTP | [notices/zlib-LICENSE.txt](notices/zlib-LICENSE.txt) |
| [cmark-gfm](https://github.com/github/cmark-gfm) | `27d942c8b0a62d192f616e5bf3578f4b6a89e180` | BSD-2-Clause and others | Native Markdown | [notices/cmark-gfm-LICENSE.txt](notices/cmark-gfm-LICENSE.txt) |
| [wgpu-native](https://github.com/gfx-rs/wgpu-native) | `v29.0.1.1` | MIT or Apache-2.0, plus dependency licenses | GPU provider | [MIT](notices/wgpu-native-LICENSE.MIT.txt), [Apache-2.0](notices/wgpu-native-LICENSE.APACHE.txt), [dependencies](notices/wgpu-native-Rust-dependencies.html) |
| [LuaJIT](https://luajit.org/) | `1edc3e52b67eaf6ce5f809be8e17d6862594b8bc` | MIT | Toolchain only | [notices/LuaJIT-COPYRIGHT.txt](notices/LuaJIT-COPYRIGHT.txt) |

A binary carries only the facilities it links. The notices stay together here
because each binary's facilities are decided independently, so one set is
correct for all of them.

The VM runtime is Rust. Its notice deliberately covers every third-party
package in `Cargo.lock`, including target-specific, build and development
dependencies, which is broader than any one binary. The `libffi-sys` crate
builds libffi from the C sources it bundles and links it statically; the Rust
notice covers the crate, and `libffi-LICENSE.txt` is the C library's own,
copied from the source that crate bundles. The VM also links the ISA-L static
archive for persistence. Maintainers refresh the Rust notice with cargo-about
0.9.2 and `scripts/rust-dependency-notices --write`; ordinary builds and
releases use the committed result and need neither `cargo-about` nor network
access.

Lunajson is committed under `src/nupp/runtime/vendor` and compiled into the
compiler's runtime library. Its notice is repeated here so the release notices
are complete in one place.

`scripts/native-libraries` builds the pinned C libraries -- libffi, libuv,
libcurl, OpenSSL, zlib, ISA-L and cmark-gfm -- with matched headers, and copies
each notice into the artifact's own `notices/`. Curl is built against those
exact OpenSSL and zlib artifacts. The libuv artifact also carries the BSD and
ISC notices of individual upstream sources; ship that artifact's `notices/`
alongside this directory.

`scripts/wgpu-native` fetches an upstream prebuilt library and its matched
headers. Its independently pinned notice files travel with each cached copy.
The library contains Rust code, which its own dependency notice covers.

LuaJIT is not part of a Nupp binary. `scripts/toolchain` builds the pinned
LuaJIT only as the interpreter LuaRocks runs on when a project installs a rock
dependency. Its notice also carries the public-domain statement for dlmalloc,
which LuaJIT includes.

A copy here that no longer matches the source it came from is worse than none,
because it is a claim about what was distributed. The C library and LuaJIT
notices are compared byte for byte against the source just verified by digest,
the wgpu-native notices are pinned by digest, and the Rust notice is checked
against `Cargo.lock`. Bumping a pin without updating the notice beside it
therefore stops the build rather than shipping the wrong text.
