# Third-party notices

The compiler and its native providers carry third-party code, so a binary or
provider built from them is a distribution of those selected copies. Their
licenses ask that notices travel with the copies, which is what this directory
provides for both the pinned C sources and the locked Rust dependency graph.

Ship `NOTICE.md` and `notices/` beside a binary the way a release archive ships
a README. Native sources are fetched at build time, so their notices would
otherwise exist only inside somebody's toolchain cache. Lunajson is committed
under `src/nupp/runtime/vendor`; its notice is repeated here so the release
notices remain complete in one place.

| Dependency | Pinned at | License | Notice |
| --- | --- | --- | --- |
| [LuaJIT](https://luajit.org/) | `1edc3e52b67eaf6ce5f809be8e17d6862594b8bc` | MIT | [notices/LuaJIT-COPYRIGHT.txt](notices/LuaJIT-COPYRIGHT.txt) |
| [LPeg](https://www.inf.puc-rio.br/~roberto/lpeg/) | `1.1.0` | MIT | [notices/LPeg-LICENSE.txt](notices/LPeg-LICENSE.txt) |
| [luautf8](https://github.com/starwing/luautf8) | `0.2.1` | MIT | [notices/luautf8-LICENSE.txt](notices/luautf8-LICENSE.txt) |
| [Lunajson](https://github.com/grafi-tt/lunajson) | `1.2.3` | MIT | [notices/lunajson-LICENSE.txt](notices/lunajson-LICENSE.txt) |
| Rust dependency graph | `Cargo.lock` | Mixed permissive licenses | [notices/Rust-dependencies.html](notices/Rust-dependencies.html) |

LuaJIT's notice also carries the public-domain statement for dlmalloc, which
LuaJIT includes; it is reproduced there rather than summarised here.

A copy here that no longer matches the source it came from is worse than none,
because it is a claim about what was distributed. `scripts/toolchain` compares
each file against the notice in the source it just verified. LPeg publishes its
notice inside HTML, so that check verifies the identifying copyright, grant and
warranty terms in both copies. Bumping a pin without updating the notice beside
it therefore stops the build rather than shipping the wrong text.

LuaJIT is in every compiler host. LPeg and `luautf8` are selected host features,
and the locked Rust graph supplies feature-selected native providers including
networking and TLS. A build that selects none of those does not distribute them;
the notices stay here because each binary's features are decided independently.
Lunajson's decoder and encoder are vendored into the portable compiler runtime.

The Rust notice deliberately covers every third-party package in `Cargo.lock`,
including target-specific, build and development dependencies. This is broader
than any one provider binary, but makes the same notice set correct for every
feature and supported platform. Maintainers refresh it with cargo-about 0.9.2
and `scripts/rust-dependency-notices --write`; ordinary builds and releases use
the committed result and do not need `cargo-about` or network access.
