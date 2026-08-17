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
  - [x] strict JSON numbers and explicit empty array/object semantics are set
        per call site on the Nupp side, not in the host. The host never set
        them: `host/build.rs` compiles lua-cjson with no policy defines, for the
        reason its own comment gives about `ENABLE_CJSON_GLOBAL`. The Nupp side
        was the half-finished part -- eight of the sixteen files holding a codec
        inherited whichever cjson the interpreter had loaded.
        The one that matters is `decode_invalid_numbers`, which defaults to
        accepting `NaN` and `Infinity` where encoding refuses them, so a
        document could be read in and then fail to be written back out.
        `tests/jsonpolicytest.lua` walks the sources and fails naming any codec
        that leaves a setting to the default, so a codec added later is held to
        the same rule on the run that adds it
  - [ ] shipped per-platform stubs
        ([plan](043-cross-target-binaries.md)). Selection is built: `platforms`
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
- [x] **Hot reload is the one part of the compiler that runs untyped.** Both
      files are `.nupp` now and hold to the strict floor, so nothing under `src`
      opts out of it. `--strict` named six exports rather than the five recorded
      here -- `policy` was missing from the list -- and each has a real signature.
      `nupp.HotReload.poll` answers `nupp.HotReloadPoll`, whose docblock says
      which of the four `kind` values carries which fields, so a host branches on
      a documented answer instead of on `any`.
      The specified types were written where the code puts them rather than where
      the plan guessed: `prepare` answers `Prepared | Rejected | Restart |
      Unchanged` as specified, but `Restart` also carries the `reason` naming the
      boundary that refused the change, `initial` tags its result `kind =
      "initial"`, and `loaded` and `committed` answer with the unverified-library
      notices rather than nothing. `plans/036-hot-reload.md:106` is now behind the
      code on all four points.
      Two things stayed `any` on purpose and one had to. The slot vectors are
      `{hotreload.Implementation}` where an implementation is
      `function(...: any): any`, because generated code writes them and generated
      code calls them; the loaded patch chunk and `debug.upvaluejoin` are
      untypeable by nature; and a manifest is plain data the generator alone
      decides the shape of, so typing it here would be claiming a shape this
      module does not own.
      The public poll result is a record with optional fields rather than a union
      of four records. A union would be better, and the reason it is not is that
      a prelude record is not nameable as a type from another module -- referring
      to `nupp.HotReloadPrepared` from `cli/run.nupp` reports NUPP2101. Worth
      revisiting when prelude types can be named across modules.
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
      [aot-functions.md](038-aot-functions.md), and the rejected alternatives are
      recorded in [portable-vectors.md](037-portable-vectors.md).
      The fixed-width intrinsic identities now come from
      `nupp.compiler.scalar_intrinsics` rather than a second table, so aliasing
      a standard member cannot mean one thing to the checker and another to the
      backend. What is still text-based is the lookup itself: it resolves a
      written dotted path, so an alias bound to a local name is not recognised.
      That needs the checker's resolved identity, which is part of the handoff
      above.
- [ ] **Finish the SPMD gang-width decision.** The spike selects eight 32-bit
      lanes or four binary64 ones from the widths a loop's varying values need,
      and lowers the released `nupp.math.f32` and `nupp.math.i32` operations to
      native instructions. On Apple arm64 at 1024x768 and 256 iterations the
      binary32 Mandelbrot runs at about 119 MPix/s against 72 for the binary64
      body and 35 for forced-scalar C, which is the same for both kernels --
      the gain is lane density, not cheaper arithmetic. What is unfinished:
  - [x] withdraw `@aot(simd = true)`. Done: the annotation is gone from the
        language, the lane pass runs on every `@aot` function whose shape admits
        it, `lanes = true` and `lanes = false` override the estimate in either
        direction, and `nupp aot --check` exits 1 for a map loop that lowered
        scalar, naming the construct that stopped it.
        The original entry follows.
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
  - [x] **No gang fits x86-64 below AVX.** Closed by giving the backend a target
      model: a triple and a CPU feature tier decide which gangs exist, x86-64
      defaults to the baseline tier and therefore to no gang, and a target with
      none refuses by name rather than going quietly scalar. `nupp aot --target`
      and `--features` select one. What is still open is the 16-byte gang itself,
      which would give the x86-64 baseline lanes rather than a refusal, and the
      choice between pinning one baseline at build time and multiversioning with
      runtime dispatch.
      The original entry follows.
- [x] **No gang fits x86-64 below AVX.** Closed. The shapes come in 16 and 32
      bytes now, a target takes every one that fits its widest register class,
      and plain x86-64 runs two binary64 lanes or four 32-bit ones instead of
      refusing. `aotFeatures` on a target selects a wider tier, and the tier is
      part of the artifact key. CI runs the differential at the baseline with no
      `-mavx2`, which is the combination most users get and the one that found
      the mask type nobody had given a C spelling.
      What is left of it is multiversioning, below.
      The original entry follows.
- [ ] **No gang fits x86-64 below AVX.** Both shapes are 32 bytes, which is one
      AVX register and two NEON registers. Below AVX on x86-64 a 32-byte vector
      has no register class: it compiles, because the compiler splits it, but it
      has no stable ABI at a function boundary and Clang says so through
      `-Wpsabi`. The generated helpers are `static inline` and never actually
      cross one, so nothing is wrong today -- but a target tier the shapes do not
      fit is a tier with no gang, and there is no 16-byte shape to fall back to.
      Found by the first native x86-64 CI run. Apple Clang does not emit
      `-Wpsabi` at all, so the same code cross-compiled and emulated locally was
      silent; only the native run said anything, which is the argument for the
      job existing.
      What this needs is the feature tier the delivery plan already asks the
      cache key to carry: a 16-byte gang for the x86-64 baseline, or a stated
      refusal to compile `@aot` lanes below AVX. `crosscheck.sh` targets the AVX
      tier on x86-64 in the meantime and lets a forced lower one warn.
- [x] mixed-width gangs. The rounding half is done; the lane-count half is not,
        and is now known to be the smaller of the two.
        `mixed4` and `mixed2` replace the binary64 gangs and carry each value at
        its own element width, so an explicit binary32 operation is a native
        single-precision instruction rather than a wide one rounded back. A
        widening became a real conversion, a comparison produces a mask as wide
        as what it compared, and the mask algebra stays at one width and converts
        at comparisons and selects.
        `bench/kernel-subset-spike/mixedwidth.sh` builds one loop three ways and
        reports each against its own forced-scalar body:

            mixedwidth      mixed4   1.06x -> 2.57x
            mixedwidth_f64  mixed4   2.46x -> 2.45x
            mixedwidth_f32  f32x8    4.72x -> 4.72x

        The kernel that mixes widths now runs at what the same loop runs at with
        nothing to round. Of the 4.5x the all-or-nothing rule had been costing,
        rounding was 2.3x and the lane count 1.9x -- so the larger half is closed
        and the plan's phrase "gang sizing" named the smaller one.
        What remains is eight lanes with a binary64 value in the loop, and the
        way to get there is now known to be narrower than it looked. A binary64
        value needs 64-bit lanes whatever else the loop holds, so eight of them
        is a 64-byte vector.

        Letting one value span two registers does not work. Clang refuses a
        64-byte vector on x86-64 at both feature tiers:

            AVX vector return of type 'f64x8' (vector of 8 'double' values)
            without 'avx512f' enabled changes the ABI [-Wpsabi]

        and it says so at the call site of a `static inline` helper, so the
        reasoning the target model rested on -- that inline helpers never cross
        an ABI boundary -- does not hold for the diagnostic. arm64 compiles the
        same file clean, which is the blind spot that hid the 32-byte version of
        this until a native x86-64 run reported it.

        So this wants an `avx512f` tier whose register class is 64 bytes, and a
        gang that exists only there. That extends the rule the target model
        already enforces rather than making an exception to it: a vector wider
        than the register class is not a gang. It also means the eight-lane
        binary64 gang is AVX-512 hardware or nothing, which is a much smaller
        claim than "a wider register file or two registers per value" -- and one
        no machine in CI can currently execute, so admitting it needs a way to
        check it that is not "it compiled".
        The original entry follows.
- [ ] mixed-width gangs. Half of this is done and the half that is left is
        smaller than it was.
        The sharp edge was not lane count: a loop mixing explicit binary32 with
        one binary64 value got **no gang at all**, because the 32-bit gang
        refused the binary64 value and the binary64 gang refused the explicit
        binary32 operations. `mixedwidth.nupp` is that shape. It now lowers to
        four lanes: the binary64 gang performs each binary32 operation in its own
        lanes and rounds the result once, which is bit-identical to the native
        instruction by the argument the scalar lowering already rests on.
        `mixedwidth_main.lua` proves that over 4001 bodies across three bodies
        from one source, with 688 taking the divergent exit.
        Measured at 1.14x over forced scalar, against about 2x for a gang that
        carries its element exactly -- a rounded operation is three instructions
        where an exact one is one. That gap is what real mixed-width gangs would
        close, and the IR now records `lanes.rounded` so `nupp aot` says when a
        body paid it rather than leaving the operation count to imply otherwise.
        What remains is the lane count: fix a gang size from aggregate register
        pressure and let each value occupy however many registers its element
        needs, so a binary64 value in a gang of eight is four NEON registers and
        a binary32 one is two. That needs mask widths to convert, which nothing
        does yet.
  - [ ] **Multiversion the feature tier.** A build pins one. Dispatching between
        several at run time, so one binary uses AVX2 where it is present and the
        16-byte gangs where it is not, is what would let x86-64 have the wide
        gangs without a project promising instructions its users may not have.
        Until then the conservative default costs half the lanes on the most
        common target, which is a real price and a stated one.
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
  - [ ] admit `nupp.math.f32.min`, `max`, and `fma`. The admitted operations are
        exact because a binary32 operation over binary32 operands computed in
        binary64 and rounded once is bit-identical to the native instruction
        (53 >= 2 * 24 + 2). These three are not covered by that argument: their
        `nupp.math` implementations canonicalize NaNs and compensate rounding in
        ways `fmin`, `fmax` and `fmadd` may not match. Each owes a differential
        test over signed zero, NaN payloads, and subnormals before it enters.
  - [x] account for the gap to the historical explicit-vector result. There is
        no gap: the model was wrong, not the lowering. `divergence.lua` read each
        pixel's reported iteration count, but the kernel's interior test sets
        that to the cap and then runs the loop zero times, so the whole cardioid
        counted as maximally expensive. Since the cardioid is contiguous, that
        made every gang touching it look equally slow at four lanes and at
        eight, and hid exactly the divergence widening introduces. Costing an
        interior pixel at zero, the eight-lane ceiling is 1.81x at cap 64, 1.68x
        at 256, 1.60x at 1024 and 1.58x at 4096 -- against measured ratios of
        1.72, 1.60, 1.52 and 1.42. The lowering runs at 90 to 95 percent of what
        the algorithm allows, and the remainder is the per-pixel gather and
        scatter, which costs the same however many lanes share it.
        Replacing the lane-extract-and-or in `ks_any` with
        `__builtin_reduce_or` was tried and is not worth it: Clang already
        lowers the extract chain, and the generated function grew from 225 to
        232 instructions.

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
