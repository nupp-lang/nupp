# Nupp TODO

A living list, not a design record. Items are checked off in place, so the boxes
below are the status; nothing here is a commitment or a schedule. Why something
is designed the way it is belongs in [an enhancement proposal](docs/neps/).

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
  - [ ] shipped per-platform stubs
        ([plan](docs/neps/0041-cross-target-binaries.md)). Selection is built: `platforms`
        is a validated binary-target field, `--platform NAME|all` is on `build`,
        `check` and `clean`, `build/stubs.nupp` authenticates a stub by SHA-256,
        size and `hostAbi`, and release CI builds a stub, its notices and its
        catalog record on all three native runners, then assembles and validates
        an immutable `stub-catalog.json`. What is missing is the catalog itself:
        `src/nupp/compiler/build/stub_catalog.nupp` is a development placeholder
        with no stubs in it, and by the release-order constraint the plan states
        it has to stay that way -- release N publishes the stubs, release N+1
        names them, and a compiler may only name assets that already exist. So
        cross-target stamping is a second-release feature whatever happens now.
        The one piece that has to land before then: `scripts/stub-catalog.py`
        has `record` and `catalog` but nothing that turns a published
        `stub-catalog.json` back into `stub_catalog.nupp`
## Type-level computation

Found while building the worker protocol generator ([NEP
16](docs/neps/0016-typed-workers.md)). None of them blocked it; each made it
longer than it had to be.

- [ ] **`nupp.types` cannot read a nominal's fields.** `nupp.types.fields(R)` for
      a record is `NUPP2415: needs a structural shape handle`, and
      `describe(R).fields` is nil, so a generator that wants a declared record has
      to switch to `nupp.reflect` and a different descriptor API. The payload a
      nominal handle carries would have to gain its fields, which the semantic
      fingerprint also reads, so this is not only a lookup change.
- [ ] **A comptime type alias has no top-level form.** `local comptime type Field
      = {name: string, read: type?, write: type?}` is rejected twice, `NUPP2119`
      for having no visibility and `NUPP2421` for naming `type` outside comptime,
      because `comptime type` is a member form. Every generator writing field
      descriptors repeats that shape inline at each use.
- [ ] **Field descriptors match exactly.** Annotating `{{name: string, read:
      type?}}` and passing it to `nupp.types.shape` is `NUPP2006` against
      `{{name: string, read: type?, write: type?}}`, so an unused optional still
      has to be named.

## Workers

- [ ] **Encode transferred values from the submitted function type.**
      A signature that can never cross is now refused where it is written
      ([NEP 22](docs/neps/0022-static-worker-signatures.md)), but the copy is
      unchanged: `unsendable` still walks every value, and `spawn` walks its
      arguments a second time inside `encode`.
      [NEP 15](docs/neps/0015-schema-driven-serde.md) has the schema and binding,
      and `nupp.reflect.fieldCodec` the materializer; what is missing is deriving
      a schema from function type packs and using its compatibility fingerprint
      as the handshake between states. Depth, cycles and repeated aliases stay
      dynamic whatever happens: a recursive shape is a valid type that builds a
      cyclic value.

- [ ] **Re-attach a record's metatable in the receiving lane.**
      Whether a record crosses depends on how the value was built: a table
      literal is a plain table and `new` carries a metatable, which the copy
      refuses. The lane already requires the module to find its entry point, so
      the metatable is `require(module)[name]` away. Until then a record cannot
      be refused or accepted from its type.

## Dialect interop (`import-tl`)

- [ ] source translator CLI (eject model, visible residue comments, `any`
      fallbacks), translating metamethod declarations, `record X is Y`,
      bounded generics, nested type namespaces, and `self` directly into their
      landed nupp forms

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
- [ ] **HTTP adoption** ([design](docs/neps/0038-http-client.md)): Tecs keeps its ECS policy and
      SDL-owned loop, installs its existing suspension adapter per task, polls
      Nupp without sleeping before and between scheduler rounds, and deletes
      its per-client transport pump and private upload scheduler after
      adoption. A close/count-only facade registry may remain for Teal
      lifecycle compatibility.
- [ ] **Files adoption** ([design](docs/neps/0037-files.md)): `nupp.io.files`, its native
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
