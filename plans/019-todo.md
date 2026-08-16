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
  - [x] keep the sources pinned-and-fetched without committing archive blobs;
        `NUPP_HOST_SOURCE_DIR` supplies existing verified archives,
        `NUPP_HOST_SOURCE_BASE_URL` selects a mirror, output-directory archives
        are reused, and `NUPP_HOST_OFFLINE` forbids a network fallback
  - [ ] strict JSON numbers and explicit empty array/object semantics are set
        per call site on the Nupp side, not in the host
  - [ ] cross-target stub selection and shipped per-platform stubs
        ([plan](043-cross-target-binaries.md)); a binary target still has no target
        list or cross-build selection
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
- [ ] **Hot reload is the one part of the compiler that runs untyped.**
      `src/nupp/hotreload.g.nupp` and `src/nupp/compiler/hot_session.g.nupp` are
      the only two `.g.nupp` files under `src`, so the machinery deciding
      whether an edit may reach a running program is the machinery outside the
      strict floor. `--strict` names five exported functions with no
      annotation — `module`, `define`, `stage`, `commit` and `hotSession.new` —
      and the public surface says as little: `nupp.HotReload.poll` is declared
      as returning `any` (`src/nupp/compiler/decls/prelude.d.nupp:251`), and the
      CLI's own host loop reads its `kind` strings untyped
      (`src/nupp/compiler/cli/run.nupp:123`).
      The types were specified and never written: `hot-reload.md:106` gives
      `Result = Prepared | Rejected | Restart | Unchanged`, `InitialBuild` and
      the `Session` record. Writing those, renaming both files to `.nupp` and
      widening `poll` closes this. The slot vectors, `debug.upvaluejoin` and the
      loaded patch chunk stay `any` by nature; the results and the manifests are
      where the typing is worth having.
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
      Move that IR and C backend under
      `src/`; consume the complete checked ownership, alias, effect, layout, and
      numeric facts; then add build policy, target compilation and dispatch,
      cache and artifact validation, inspection, and diagnostics.
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
      [aot-functions.md](038-aot-functions.md), and the rejected alternatives are
      recorded in [portable-vectors.md](037-portable-vectors.md).
      When the lowering moves under `src/`, take the fixed-width intrinsic
      identities from `nupp.compiler.scalar_intrinsics` rather than the second
      table the spike keeps, so aliasing a standard member cannot mean one thing
      to the checker and another to the backend.
- [ ] **Finish the SPMD gang-width decision.** The spike selects eight 32-bit
      lanes or four binary64 ones from the widths a loop's varying values need,
      and lowers the released `nupp.math.f32` and `nupp.math.i32` operations to
      native instructions. On Apple arm64 at 1024x768 and 256 iterations the
      binary32 Mandelbrot runs at about 119 MPix/s against 72 for the binary64
      body and 35 for forced-scalar C, which is the same for both kernels --
      the gain is lane density, not cheaper arithmetic. What is unfinished:
  - [ ] withdraw `@aot(simd = true)`. Decided; the reasoning and its cost are
        recorded in [portable-vectors.md](037-portable-vectors.md). The
        annotation was justified as asserting iteration independence, and in the
        admitted subset independence is a theorem: disjointness follows from
        `exclusive_borrow`, every span access must use the loop index exactly,
        and all mutable lane state is loop-local. What it actually delivers is a
        build error instead of silent scalar code, and this project already
        answers that category with `nupp bc --check`. So run the lane pass on
        every `@aot` function whose shape admits it, and add a check that exits
        1 for an `@aot` map loop that lowered scalar, naming the construct that
        stopped it. Needs an inverted marker for a deliberately scalar loop, and
        the one-top-level-map-loop shape stops being an error.
  - [ ] mixed-width gangs. Selection is all-or-nothing today: one binary64
        varying value drops the whole loop to four lanes. The rule is ISPC's --
        fix a gang size from aggregate register pressure and let each value
        occupy however many registers its element type needs, so a binary64
        value in a gang of eight is four NEON registers and a binary32 one is
        two. That needs mask widths to convert, which nothing does yet.
  - [ ] admit `nupp.math.f32.min`, `max`, and `fma`. The admitted operations are
        exact because a binary32 operation over binary32 operands computed in
        binary64 and rounded once is bit-identical to the native instruction
        (53 >= 2 * 24 + 2). These three are not covered by that argument: their
        `nupp.math` implementations canonicalize NaNs and compensate rounding in
        ways `fmin`, `fmax` and `fmadd` may not match. Each owes a differential
        test over signed zero, NaN payloads, and subnormals before it enters.
  - [ ] account for the gap to the historical explicit-vector result. Lane
        density alone predicted about 130 MPix/s and the measurement is 119.
        The remainder is unexplained; the mask and select sequence and the
        interior test are the places to look.

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
- [ ] **HTTP adoption** ([design](007-http.md)): Tecs keeps its ECS policy and
      SDL-owned loop, installs its existing suspension adapter per task, polls
      Nupp without sleeping before and between scheduler rounds, and deletes
      its per-client transport pump and private upload scheduler after
      adoption. A close/count-only facade registry may remain for Teal
      lifecycle compatibility.
- [ ] **Files adoption** ([design](006-files.md)): `nupp.io.files`, its native
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
