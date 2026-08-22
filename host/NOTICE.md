# Third-party notices

The stub links four third-party projects into itself, so a binary stamped from
it is a distribution of them. Their licenses ask that notices travel with the
copies, which is what this directory is: the notice files carried by the pinned
sources.

Ship `NOTICE.md` and `notices/` beside a binary the way a release archive ships
a README. Nothing else in the tree carries them: the sources themselves are
fetched at build time rather than committed, so without this the notices would
exist only inside somebody's `target/` directory.

| Dependency | Pinned at | License | Notice |
| --- | --- | --- | --- |
| [LuaJIT](https://luajit.org/) | `1edc3e52b67eaf6ce5f809be8e17d6862594b8bc` | MIT | [notices/LuaJIT-COPYRIGHT.txt](notices/LuaJIT-COPYRIGHT.txt) |
| [simdjson](https://github.com/simdjson/simdjson) | `4.6.4` | Apache-2.0 | [notices/simdjson-LICENSE.txt](notices/simdjson-LICENSE.txt) |
| [LPeg](https://www.inf.puc-rio.br/~roberto/lpeg/) | `1.1.0` | MIT | [notices/LPeg-LICENSE.txt](notices/LPeg-LICENSE.txt) |
| [luautf8](https://github.com/starwing/luautf8) | `0.2.1` | MIT | [notices/luautf8-LICENSE.txt](notices/luautf8-LICENSE.txt) |

LuaJIT's notice also carries the public-domain statement for dlmalloc, which
LuaJIT includes; it is reproduced there rather than summarised here.

A copy here that no longer matches the source it came from is worse than none,
because it is a claim about what was distributed. `host/build.rs` compares each
file against the notice in the archive it just verified. LPeg publishes its
notice inside HTML, so that check verifies the identifying copyright, grant and
warranty terms in both copies. Bumping a pin without updating the notice beside
it therefore stops the build rather than shipping the wrong text.

`json`, LPeg and `luautf8` are selected features. A host built without one does
not link it and does not distribute it; the notice stays here either way,
because which features a given binary carries is decided per build.
