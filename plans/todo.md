# Nupp TODO

Grouped by the part of the system a change lands in. Nothing here is
prioritised by tier; the ordering inside a section is roughly the order the
work makes sense in.

## Build, codegen and distribution

- [ ] **Single-binary host.** LuaJIT, lua-cjson, LPeg and luautf8 are pinned by
      revision and SHA-256 and built from source by `host/build.rs`, not
      committed. LPeg is a small optional host feature used by direct LPeg calls
      and every `nupp.peg` matcher; Nupp's typed graph and selected kernels sit
      above it. The native modules are registered for `require`; the binary
      container, trailer, stamping, pinned
      revision metadata, and a compiler-built current-platform `stub = "nupp"`
      are implemented. Their MIT notices ship in `host/NOTICE.md` and
      `host/notices/`, and the build fails when a committed copy stops
      matching the archive it just verified. `tests/hostbinarytest.lua`
      damages a stamped binary twenty ways, feeds its language server nine
      malformed sessions, and replays a recorded editor session through it
      against the same session through `bin/nupp`. What remains:
  - [ ] decide whether pinned-and-fetched is enough or the sources should be
        vendored in-tree; a build still needs `curl` and the network, which a
        vendored tree would not
  - [ ] strict JSON numbers and explicit empty array/object semantics are set
        per call site on the Nupp side, not in the host
  - [ ] cross-target stub selection and shipped per-platform stubs; a binary
        target still has no target list or cross-build selection
- [ ] Hot-reload typing; the `nupp-cargo` Rust helper.
- [ ] **Investigate `@native` compilation for Nupp-authored tight loops.** This
      is a separate project from checked external kernels and
      `countedBy(count)`. Define the restricted whole-function contract over
      ordinary Nupp structs, `Span<T>`, and `WriteSpan<T>`; lower it through a
      checked native IR; and compare an invisible AOT C/Clang backend with
      direct machine-code generation. The user-facing model must require no
      `cdef`, duplicated C struct, or handwritten C. Specify layout validation,
      alias assumptions, CPU dispatch, caching, diagnostics for rejected
      operations, and performance gates before choosing a backend. The full
      design and its comparison with portable vectors are in
      [native-functions.md](native-functions.md).

## Dialect interop (`import-tl`)

- [ ] source translator CLI (eject model, visible residue comments, `any`
      fallbacks), translating metamethod declarations, `record X is Y`,
      bounded generics, nested type namespaces, and `self` directly into their
      landed nupp forms

## Formatting

- [ ] **A shape type with one field still breaks across three lines.** `Shape
      types always put each field on its own line` reads well for a record-like
      type and badly for `{string: any}` in a parameter list, which is twelve
      sites in this tree and every one of them worse for it. The rule is
      deliberate, documented and tested (`tests/fmtwidthtest.lua:143`), so
      changing it is another taste decision rather than a defect: either a
      one-field shape is exempt, or the rule holds and these read as they read.

## Performance and incrementality

- [ ] **A cleanup region inside a loop still builds a function every iteration.**
      An owned binding needs its body run under `xpcall`, and `xpcall` takes a
      function. Where that function is built per entry, the loop holding it
      never compiles, for the same reason `jit-loop-closure` reports — and
      acquiring a resource per iteration is an ordinary thing to write, not a
      corner case.
      Half of this is already handled and the half that is left is bigger than
      it looks. `gen` caches the region function in a module table and passes
      the binding in, building it on first entry and reusing it after
      (`src/nupp/compiler/gen.nupp`, the `shared` path); nine of the twenty-three
      regions in this compiler's own source take it, and `nupp bc --check`
      correctly says those loops compile.
      What gates the rest is `automaticCaptures`: a body naming anything defined
      before the region — which includes every module-level function, so any
      body that calls something — cannot be lifted to a module-level table,
      because the name would not be in scope there.
      Moving the region's own bookkeeping into a table passed to the function
      does **not** unblock this, which is worth writing down because it looks
      like it should. `xpcall` does forward extra arguments, so the count, the
      owners and the active flags could travel that way and still be readable
      after an error. The free variables cannot: the body reads and sometimes
      writes names belonging to the enclosing function, and passing those means
      lambda lifting with write-back, not an extra parameter.
      So this is a transformation rather than a lowering change, and it lands in
      the machinery where being wrong means a leak or a double free. It wants
      its own design pass. Until then `nupp bc --check` names the loops it
      affects, and hoisting the acquisition out of the loop avoids it where the
      resource does not have to be per-iteration.

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

---

## Tecs

### Subsystem acceptance port

- [ ] **Translate the four remaining files.** 143 of 1276 lines are done, and
      they are the two with the least FFI in them, so nothing about reification
      or a struct not being a table has come up yet. `FFIStorage.tl` is the
      schema-to-cdata layer and the file the gate actually names; `FFIEvents.tl`
      is the event storage the metatable and prototype work was aimed at; and
      `EpochArena.tl` is the owned growable buffer the bounds-carrying spans
      item above wants.
- [ ] **Two frictions the port logged and nobody has fixed.** No table literal
      infers into a tuple type in any position, including a directly annotated
      binding, so every Teal-idiomatic `{string, string}` needs a cast at each
      site. And integer arithmetic widens, so a `%` result cannot key a
      `{[integer]: _}` without `as integer`. Both are in `PORT.md` with repros.
- [ ] Focused fixtures cover tecs-style nested event records, bounded
      registration, late `__call` installation, generic `__index`/`__newindex`,
      and arithmetic contracts (`tests/gentest.lua:152`,
      `tests/checktest.lua:276`).

### Library adoption

- [ ] **Buffer adoption.** Port tecs `Buffer`, `ByteView`, `WriteRange`,
      compression, process-I/O, mapped-buffer, and pointer-plus-length call
      sites to Nupp's bounds-carrying spans and buffer implementation.
- [ ] **HTTP adoption** ([design](http.md)): Tecs keeps its ECS policy and
      SDL-owned loop, installs its existing suspension adapter per task, polls
      Nupp without sleeping before and between scheduler rounds, and deletes
      its per-client transport pump and private upload scheduler after
      adoption. A close/count-only facade registry may remain for Teal
      lifecycle compatibility.
- [ ] **Files adoption** ([design](files.md)): `nupp.io.files`, its native
      provider, bounded request lane, suspension integration, and compiler
      adoption have landed. The remaining project is tecs adoption: delete
      `io/files`, `internal/fileasync`, `platform/storagebackend` and its
      atomic-write worker in favor of the shared facility.
  - [ ] F4b: tecs adoption, deferred as its own integration project. `tecs`
        is Teal and `nupp.io.files` is an ambient global rather than a module a
        `.tl` file can require, so it needs the bootstrap chunk in tecs's
        runtime, a `.d.tl` surface, the cdylib, `nupp/suspension.lua` staged for
        a consumer nothing stages it for, and its already-landed suspension
        adapter joined to the files readiness source.
