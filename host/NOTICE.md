# Third-party notices

The compiler and its native providers carry eight third-party projects, so a
binary or provider built from them is a distribution of those selected copies.
Their licenses ask that notices travel with the copies, which is what this
directory is: the notice files carried by the pinned sources.

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
| [ada](https://github.com/ada-url/ada) | `4.0.0` | MIT | [notices/ada-LICENSE.txt](notices/ada-LICENSE.txt) |
| [libuv](https://libuv.org/) | `1.52.1` | MIT | [notices/libuv-LICENSE.txt](notices/libuv-LICENSE.txt) |
| [libcurl](https://curl.se/libcurl/) | `8.11.1` | curl license | [notices/curl-COPYING.txt](notices/curl-COPYING.txt) |
| [mbedTLS](https://www.trustedfirmware.org/projects/mbed-tls/) | `3.6.2` | Apache-2.0 or GPL-2.0-or-later | [notices/mbedtls-LICENSE.txt](notices/mbedtls-LICENSE.txt) |
| [Lunajson](https://github.com/grafi-tt/lunajson) | `1.2.3` | MIT | [notices/lunajson-LICENSE.txt](notices/lunajson-LICENSE.txt) |

LuaJIT's notice also carries the public-domain statement for dlmalloc, which
LuaJIT includes; it is reproduced there rather than summarised here.

A copy here that no longer matches the source it came from is worse than none,
because it is a claim about what was distributed. `scripts/toolchain` compares
each file against the notice in the source it just verified. LPeg publishes its
notice inside HTML, so that check verifies the identifying copyright, grant and
warranty terms in both copies. Bumping a pin without updating the notice beside
it therefore stops the build rather than shipping the wrong text.

LuaJIT and libuv are in every compiler host. LPeg and `luautf8` are selected
host features; ada belongs to the URI provider, and libcurl and mbedTLS
belong to HTTP. A build that selects none of those does not distribute them; the
notices stay here because each binary's features are decided independently.
Lunajson's decoder and encoder are vendored into the portable compiler runtime.
