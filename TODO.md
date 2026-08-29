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

## Architecture tripwires

- **Committed Nupp source generators: 1; review threshold: 3.** `nupp import-c`
  is the one current tool that writes Nupp source. `scripts/release.nupp`
  writes JSON today and joins the count only when its pending half writes
  `stub_catalog.nupp`. Before adding a third committed source generator,
  inventory what all three need that a closed declaration provider cannot
  express and reconsider that boundary. The threshold calls for a review; it
  does not by itself admit source or AST macros.

## Build, codegen and distribution

- [ ] **`aotbuildtest` relinks under a loaded full-suite run.**
      `theLibraryIsNotRelinkedWhenNothingChanged` records the AOT library's
      modification time, rebuilds, and asks that it is unchanged. Twice during
      full runs it was not, the two stamps 44 and 59 seconds apart; the suite
      passes 53 of 53 on its own, and under three spinning cores. What relinks is
      `previousLibraryKey ~= key or not fs.exists(library)`, which is
      deterministic, and the key covers the artifact keys, the toolchain's
      version line, the flags and the linkage -- none of which a busy machine
      moves. So either the state file it reads the previous key from was not
      what the earlier build wrote, or the library was not there to find. The
      suite runs as two shards in separate processes, and the fixture cache is
      per process, so the two do not share a directory; the repository-wide
      native cache they both link against is shared. Worth an answer before it
      is dismissed as load, because a relink that nothing asked for is the cache
      missing.

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
        an immutable `stub-catalog.json`. What is missing is the catalog itself:
        `src/nupp/compiler/build/stub_catalog.nupp` is a development placeholder
        with no stubs in it, and by the release-order constraint the plan states
        it has to stay that way -- release N publishes the stubs, release N+1
        names them, and a compiler may only name assets that already exist. So
        cross-target stamping is a second-release feature whatever happens now.
        The one piece that has to land before then: `scripts/release.nupp`
        has `record` and `catalog` but nothing that turns a published
        `stub-catalog.json` back into `stub_catalog.nupp`
- [ ] **A `lua51` cleanup region hides an installed suspension handler.** The
      region runs its body on a coroutine of its own, so the body can still yield
      through what is a protected call underneath. Anything keyed by the running
      coroutine is invisible in there, and an installed suspension handler is:
      code that suspends inside a `with` extent finds none, parks on the host
      instead of on whoever is scheduling it, and starves the siblings that were
      supposed to make it ready. `nupp.tasks` hit exactly this, and the way out
      was to stop `nupp.runtime.provider.browsersuspension.install` returning an
      affine value so its block has no region at all -- which works for that one
      caller and leaves the rule wrong. The wrapper's coroutine wants the
      inheritance `suspension.create` performs, and generated code has no way to
      ask a provider for it; the shape of that hook is the open question.

- [ ] **A compiler rebuilt mid-run fails whatever was building against it.**
      `bin/nupp` rebuilds `build/nupp/compiler` whenever a source is newer than
      the completion stamp, and a build removes that stamp before it writes
      anything. A full `nupp test` rebuilds two or three times while it runs --
      the stamp's mtime changes that often, and a watcher catches it missing --
      and a suite compiling native artifacts through its own `nupp build`
      subprocess reads a tree that is being rewritten under it. What comes out
      is not a hang but a wrong answer: `aotbuildtest` reports a `-Werror`
      unused parameter in generated C, an artifact rewritten under an unchanged
      key, or C written outside the output directory, a different one or two
      each run, and every one of them passes when the suite runs alone.
      Reproduces on a clean `main`, so it is the harness rather than any change
      standing on it. What is missing first is why the rebuilds happen at all:
      nothing in a test run should be making a source newer than the stamp
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
- [ ] **Every lint has to be exercised, by construction.** All twelve have a
      test today, but nothing enforces it: the next one can land untested and
      the suite stays green. `tests/allowtest.lua:everyLintIsWellFormed`
      already iterates `check.lints` to check each entry's shape, so the missing
      half is a fixture table keyed by code — one source that must report it,
      one neighbouring source that must not — driven off the same registry, so
      a lint with no fixture fails the run rather than being noticed later.

      Both halves matter. `reifiable-record` was written whitelist-first and
      the silent cases are most of its value; a lint with only a positive test
      passes while firing on everything.
- [ ] **`tests/profiletest.lua traceRecordsWhereTheCompilerGaveUp` is
      flaky.** Recorded failing once in six runs with "unrecordable bytecode
      must be reported"; it depends on the JIT attempting and aborting a trace
      within 3000 iterations after `jit.flush()`. Sixteen consecutive runs pass
      today, so the rate is lower than recorded or machine-dependent — but a
      test whose result depends on trace timing will keep costing somebody a
      bisect.
