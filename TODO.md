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

- **Committed semantic Nupp source generators: 2; review threshold: 3.** `nupp
  import-c` ejects an editable C binding module and `nupp migrate` translates a
  foreign source file. The candidate third was release metadata, not source:
  the compiler now bundles the immutable `stub-catalog.json` directly instead
  of translating it into a Nupp module. The review kept the provider boundary
  closed; [NEP 3 records why](docs/neps/0003-comptime.md#2026-08-29-source-generator-review).
  Reconsider it again before adding a third semantic generator. The threshold
  calls for a review; it does not by itself admit source or AST macros.

## Build, codegen and distribution

- [ ] **`nupp test` can hang at the join instead of finishing.** A full run
      stops with the runner and its shell at nought per cent, no worker left
      alive, and no result written; it stays that way indefinitely. Eight of
      them were sitting on this machine at once, aged between one and two days,
      across several worktrees, so it is neither rare nor local to one tree.
      `--jobs=1` gets an answer. A run that neither passes nor fails is worse
      than one that fails, because nothing downstream can tell the difference
      between this and slow.

- [ ] **Full-suite failures that no suite reproduces on its own.** Across five
      full runs, three came back with failures that every named suite then passed
      cleanly: `aotbuildtest` twice, once for a library relinked when its key
      should have matched and once for an artifact key that moved when only a
      comment was appended, and `pegmaterializetest` for eight cases at once. Run
      alone each is 53 of 53 and 58 of 58, including under three spinning cores,
      so it is not CPU.

      What the runs had in common is other worktrees building at the same time,
      one of them AOT work. Worktrees share the repository-wide native cache by
      design, which is the obvious channel and is worth confirming or ruling out
      first. Inside the suite there is a second candidate: five `aotbuildtest`
      cases share one cached `emit-c` project and three of them mutate it -- one
      deletes the artifact, one corrupts it, one appends to the source and leaves
      it appended -- while Lua promises no order over the test table and the
      suite runs as two shards in separate processes.

      Until one of those is settled, a red full run is not evidence on its own;
      re-run the named suite before believing it. A cache that misses when
      nothing changed is still worth an answer.

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
