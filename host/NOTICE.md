# Third-party notices

The stub links four MIT-licensed projects into itself, so a binary stamped
from it is a distribution of them. MIT asks that their copyright and permission
notices travel with the copies, which is what this directory is: the notice
files carried by the pinned sources.

Ship `NOTICE.md` and `notices/` beside a binary the way a release archive ships
a README. Nothing else in the tree carries them: the sources themselves are
fetched at build time rather than committed, so without this the notices would
exist only inside somebody's `target/` directory.

| Dependency | Pinned at | License | Notice |
| --- | --- | --- | --- |
| [LuaJIT](https://luajit.org/) | `1edc3e52b67eaf6ce5f809be8e17d6862594b8bc` | MIT | [notices/LuaJIT-COPYRIGHT.txt](notices/LuaJIT-COPYRIGHT.txt) |
| [lua-cjson](https://github.com/openresty/lua-cjson) | `2.1.0.14` | MIT | [notices/lua-cjson-LICENSE.txt](notices/lua-cjson-LICENSE.txt) |
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

`cjson`, LPeg and `luautf8` are behind Cargo features. A host built without one does
not link it and does not distribute it; the notice stays here either way,
because which features a given binary carries is decided per build.
