# Wasm host sources

`nupp_host.c` is the filesystem-free Lua 5.1 host used by the playground.
It accepts only the content-hashed compiler bundle built and tested in the
same invocation.

It carries no digest implementation. The bundle is fetched by
`src/wasm-runtime.js`, which checks it with `crypto.subtle` against the
constant `nupp_bundle_sha256` publishes, before a byte of it is handed over.
The check used to be here, in C, over a SHA-256 this host carried for that one
call; the caller is what decides which bytes arrive, so the check is no weaker
for being written where the bytes already are.

Nothing here could have used `nupp.data.sha256` instead. This is Lua 5.1, which
has no bitwise operators, so the portable substitute computes each one with a
loop: measured at 382 ns an operation, which is 0.17 MB/s for SHA-256, which is
a minute of boot for a ten megabyte bundle.
