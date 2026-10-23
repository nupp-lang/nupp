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
| [LuaJIT](https://luajit.org/) | `1edc3e52b67eaf6ce5f809be8e17d6862594b8bc` | MIT | [notices/LuaJIT-COPYRIGHT.txt](notices/LuaJIT-COPYRIGHT.txt) |

The VM runtime is Rust, and the locked Rust graph supplies it and the native
facilities a binary links, such as compression, networking and TLS. A build
that does not link one of those does not distribute it; the notices stay here
because each binary's facilities are decided independently. Lunajson's decoder
and encoder are vendored into the compiler's runtime library.

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
