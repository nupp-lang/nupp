# Wasm host sources

`nupp_host.c` is the filesystem-free Lua 5.1 host used by the playground.
It accepts only the content-hashed compiler bundle built and tested in the
same invocation.

`sha-256.c` and `sha-256.h` are pinned from Alain Mosnier's `sha-2` repository
at commit `565f65009bdd98267361b17d50cddd7c9beb3e6c`. The source is offered under
the Unlicense or Zero-Clause BSD license; `SHA-2-LICENSE.md` carries the
upstream license text. `sha256-vectors.c` holds the NIST examples exercised by
the playground build before the digest implementation is linked into Wasm.
