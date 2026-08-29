# Nupp TODO

A living list, not a design record. Items are checked off in place, so the boxes
below are the status; nothing here is a commitment or a schedule. Why something
is designed the way it is belongs in [an enhancement proposal](docs/neps/).

The ahead-of-time backend and the native codec path above it have their own
list in [aot-todo.md](aot-todo.md), because that work has a running order and
this file deliberately does not.

Grouped by the part of the system a change lands in. Nothing here is
prioritised by tier; the ordering inside a section is roughly the order the
work makes sense in.

## Build, codegen and distribution

- [ ] **Single-binary host.** LuaJIT, LPeg, luautf8, libuv, ada,
      libcurl and mbedTLS are pinned by revision and SHA-256 and built from
      source by `scripts/toolchain`, not committed. LPeg is a small optional
      host feature used by direct LPeg calls and every `nupp.peg` matcher;
      Nupp's typed graph and selected kernels sit above it. The native modules
      are registered for `require`; the binary container, trailer, stamping,
      pinned revision metadata, and a compiler-built current-platform
      `stub = "nupp"` are implemented. Their notices ship in `host/NOTICE.md`
      and `host/notices/`, and the build fails when a committed copy stops
      matching the source it just verified. `tests/hostbinarytest.lua`
      damages a stamped binary twenty ways, feeds its language server nine
      malformed sessions, and replays a recorded editor session through it
      against the same session through `bin/nupp`. What remains:
  - [ ] shipped per-platform stubs
        Selection is built: `platforms` is a validated binary-target field,
        `--platform NAME|all` is on `build`,
        `check` and `clean`, `build/stubs.nupp` authenticates a stub by SHA-256,
        size and `hostAbi`, and release CI builds a stub, its notices and its
        catalog record on all three native runners, then assembles and validates
        an immutable `stub-catalog.json`. The compiler carries that artifact
        directly; `src/nupp/compiler/build/stub-catalog.json` is the development
        catalog with no stubs in it. By the release-order constraint the plan
        states it has to stay that way -- release N publishes the stubs and this
        JSON artifact, release N+1 commits those same bytes, and a compiler may
        only name assets that already exist. So cross-target stamping is a
        second-release feature whatever happens now; no source translation step
        remains to land before it.

## Transport security

- [ ] **Session resumption.** Tickets and session IDs, so a client reconnecting
      to a server it has met before skips the asymmetric work. Client side is a
      cache keyed by host, port, ALPN and certificate; server side is a store or
      ticket keys and their rotation. Decide where the cache lives, given that
      lanes are shared-nothing and a client reconnecting on another lane misses.
      `mbedtls_ssl_get_session`/`set_session` and `mbedtls_ssl_ticket_setup`.
      Leave TLS 1.3 early data out until replay is answered.
- [ ] **A platform trust store.** `tls.ClientOptions.authority` is PEM the
      caller supplies, so verifying against the public web PKI needs roots from
      somewhere. Three designs, and they fail differently: extract the
      platform's roots and verify with mbedTLS, delegate verification to the
      platform (Security.framework, CryptoAPI), or ship a bundled list. Linux
      has no API and the file location varies by distribution.
- [ ] **Kernel TLS offload.** Hand the session keys to the kernel after the
      handshake so records are encrypted on the socket. Removes the encryption
      ceiling a single I/O lane runs into, and is what makes `sendfile` useful
      for a TLS server. Linux `TLS_TX`/`TLS_RX`; not portable.
- [ ] **DTLS.** `nupp.io.tls` is stream-only. Datagram sessions need mbedTLS's
      `MBEDTLS_SSL_TRANSPORT_DATAGRAM`, its own timer callbacks, and a cookie
      exchange the server drives. Wanted by the same use that wanted datagrams.

## Testing and CI

- [ ] **Complete the operator-contract matrix.** Only `__add` has a direct
      contract test (`tests/checktest.lua:319`); no test anywhere mentions
      `__unm`, `__sub`, `__mul`, `__div`, `__mod`, `__pow`, `__lt`, `__le`,
      `__concat` or `__eq` dispatch. The table under test is
      `operators.metamethod`/`contractMetamethod`
      (`src/nupp/compiler/check/operators.nupp:45`). Needed: unary minus, subtraction,
      multiplication, division, modulo, power, right-hand fallback, and
      comparison reversal/`__lt` fallback for `<=`.
- [ ] **CI matrix** (GitHub Actions). The process-only Windows job is the first
      executable slice; the project-wide matrix remains. Add macOS + Linux,
      LuaJIT 2.1 rolling (2.1.1784535649 is the floor) + (when released) 3.0;
      run `./tests/run`, the tl.lua oracle, and import-c fixture tests; track
      `bench/reification.lua` and `bench/aos.nupp` numbers as an artifact per
      commit (regression fence around the reification speedup).
- [ ] **Fuzzing.** No corpus exists — `tests/corpustest.lua` is an oracle over
      two hardcoded external paths, skipped when absent. Grow a random-input
      corpus for lexer/parser round-trip and fmt idempotency (`fmt∘fmt = fmt`,
      `parse∘fmt = parse`); minimize and check in failures as regression
      fixtures.
