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
- [ ] **The `nupp-cargo` helper is a manifest provider now, and what is left of
      it is two promises it does not keep.** `kind = "cargo"` builds a crate's
      cdylib into an isolated target directory, forwards `target`, `profile`,
      `features`, `locked` and `offline`, reads cargo's JSON artifact messages,
      copies the library into `outDir/lib`, runs cbindgen when
      `bindings.cbindgen` is set, and passes the header through `import-c`
      (`src/nupp/compiler/build/deps.nupp:312`, documented in
      `docs/tooling/build.md`). That was the whole of what a separate command
      was for, so the command itself is not wanted. What remains is a `Box<T>`
      return, which ejects as a raw pointer where the design said it should
      carry `Owned<T*, crate_destroy>` — cbindgen erases the box, so this needs
      a convention or a per-symbol mapping rather than a port. And the cbindgen
      path has no test: `tests/projecttest.lua:1351` asserts only that the
      cdylib was copied, and every binding assertion sits on the C provider.
- [ ] **Integrate checked `@aot` lowering for Nupp-authored tight loops.** The
      annotation, fixed-width establishment facts, structural subset checker,
      and scalar-source `@aot(simd = true)` contract exist. The spike under
      `bench/kernel-subset-spike` consumes the normal checker's annotated CST,
      lowers and verifies scalar and lane IR, emits private C, and differentially
      checks ordinary Nupp, forced-scalar C, and SIMD C. Its lane IR now proves
      nested mask stacks, pure-and-total short-circuit expressions,
      data-dependent inner `while` loops, per-lane `break`/`continue`, exact
      scalar tails, and a gang width chosen from the loop's own lane types.
      Production `nupp build` still emits the ordinary Lua body.
      The whole backend is under `src/nupp/compiler/aot/` as typed Nupp: the
      admitted subset, the front end, the IR, the verifier, the lane rewrite
      and gang selection, the C emitter, the readable IR form, and the binding
      generator. `bench/kernel-subset-spike/kernel_compiler.lua` went from
      2885 lines to 170 and is now a driver -- parse, lower, verify, select a
      gang, emit -- plus the differential harnesses. Every move was proved by
      generated C, IR and bindings staying byte-identical for every kernel,
      which is also what caught a duplicated rendering path and a
      nondeterministic emitter.
      What remains: consume the complete checked ownership, alias, effect,
      layout, and numeric facts rather than re-deriving them from written type
      text; then add build policy, target compilation and dispatch, cache and
      artifact validation, inspection, and diagnostics.
      A uniform multiple binding inside a lane body used to produce a
      `helper_result` node no verifier rule covered, so compiling such a kernel
      raised rather than declining lanes. It is not a lane form at all: the call
      produces the same results for every lane, so it stays the statement it was
      and the lane body reads its results as the uniform values they are.
      `uniformcall.nupp` is that shape.
      A file may now hold as many `@aot` functions as it likes, at whatever
      widths they each choose. They come out as one C file: a shared struct is
      declared once, each function brings its own layout reporters and its own
      pair of bodies, and each gang's prelude appears once. That needed the three
      mask helpers named for their mask -- two gangs in one file otherwise define
      `ks_any` twice with different signatures -- and the helpers no gang owns
      lifted out of the per-gang prelude. `twokernels.nupp` is two functions
      landing on four lanes and eight.
      A uniform inner loop is no longer refused. Every lane runs it the same
      number of times, so there is nothing for a mask to say and it stays
      ordinary control flow over lane-parallel statements -- masking it would
      have been correct and would have paid a select per assignment and a
      horizontal test per iteration to prove something never in doubt.
      `uniform.nupp` is that shape and it lowers to four lanes where it used to
      run one iteration at a time. Generated C is byte-identical for every kernel
      that already lowered.
      Two things about how, both learned by starting it. The backend
      re-derives facts because they are not published, not because it was
      lazy: it matched `span%.WriteSpan<(.+)>` against written type text
      because the checker computed the resolved parameter type and dropped
      the association. So each fact is published first, then consumed in the
      spike against the differentials that already exist, and only then does
      the code that used to derive it move. And the port wants vertical
      slices rather than layers -- the records only do work where producer
      and consumer are both Nupp, so a verifier ported alone still receives
      untyped tables and re-checks everything by hand. Lane rewrite, lane
      verification and lane emission move together. The public
      surface stays ordinary scalar Nupp: do not add explicit vector values or
      a second numeric operator tower. The full delivery plan is
      [aot-functions.md](docs/neps/0028-checked-aot-functions.md), and the rejected alternatives are
      recorded in [portable-vectors.md](docs/neps/0032-aot-block-kernels-and-simd.md).
      The fixed-width intrinsic identities now come from
      `nupp.compiler.scalar_intrinsics` rather than a second table, so aliasing
      a standard member cannot mean one thing to the checker and another to the
      backend. What is still text-based is the lookup itself: it resolves a
      written dotted path, so an alias bound to a local name is not recognised.
      That needs the checker's resolved identity, which is part of the handoff
      above.
  - [ ] **Multiversion the feature tier.** A build pins one. Dispatching between
        several at run time, so one binary uses AVX2 where it is present and the
        16-byte gangs where it is not, is what would let x86-64 have the wide
        gangs without a project promising instructions its users may not have.
        Until then the conservative default costs half the lanes on the most
        common target, which is a real price and a stated one.
        Scoped in [multiversioning.md](docs/neps/0028-checked-aot-functions.md), which is the
        decision this wanted before any code: one translation unit per
        `(source, tier)`, all of them linked into the one library that already
        travels, tier-suffixed symbols, and the wrapper binding the widest symbol
        the machine reports at load. The run-time feature detection this compiler
        has none of is one function the emitter writes in C and the baseline unit
        exports, rather than anything new in the runtime, the native provider or
        the FFI layer. The single-unit alternative -- `target("avx2")` per
        function -- was tried rather than assumed away: it compiles clean only
        with the attribute on every helper too, which is the cost the flag route
        does not have.
  - [ ] **Put `@aot` in front of something real.** Every measurement lives under
        `bench/kernel-subset-spike/`. Tecs is the obvious first consumer, since
        the kernel shapes were borrowed from it to begin with. A feature that
        works and a feature in use fail differently, and only the second says
        whether the admitted subset is the right subset -- whether `@aot`
        refuses things people actually write.
  - [ ] **Name a `kind = "c"` dependency's library relative to its module.**
        Compiled `@aot` code travels: the wrapper names its library with a
        leading `@`, resolved against the chunk that loads it, so a copied output
        tree runs from anywhere. An ordinary C dependency still embeds the path
        the build wrote, so it has the problem `@aot` code no longer has. The
        mechanism is general and nothing has been changed there.
## Dialect interop (`import-tl`)

- [ ] source translator CLI (eject model, visible residue comments, `any`
      fallbacks), translating metamethod declarations, `record X is Y`,
      bounded generics, nested type namespaces, and `self` directly into their
      landed nupp forms

## Performance and incrementality

- [ ] **A cleanup region whose body writes an enclosing local still builds a
      function every iteration.**
      An owned binding needs its body run under `xpcall`, and `xpcall` takes a
      function. Where that function is built per entry, the loop holding it
      never compiles, for the same reason `jit-loop-closure` reports — and
      acquiring a resource per iteration is an ordinary thing to write, not a
      corner case.
      `gen` caches the region function in a module table and passes the binding
      in, building it on first entry and reusing it after
      (`src/nupp/compiler/gen.nupp`, the `shared` path). The function is written
      where it stands and only its instance is kept, so scope never gated this:
      what gates it is whether reusing one instance would read a variable
      belonging to an earlier execution. A name the chunk's outermost block
      declares would not, so a body whose only outside reference is a call it
      makes now shares. A name from an enclosing function, block or loop would,
      and that is what is left.
      Moving the region's own bookkeeping into a table passed to the function
      does **not** unblock the rest, which is worth writing down because it
      looks like it should. `xpcall` does forward extra arguments, so the count,
      the owners and the active flags could travel that way and still be
      readable after an error. The free variables cannot: the body reads and
      sometimes writes names belonging to the enclosing function, and passing
      those means lambda lifting with write-back, not an extra parameter.
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
