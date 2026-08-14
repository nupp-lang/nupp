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

No design document in the tree, and nothing is implemented: no `.tl` handling
in module resolution, no translator subcommand, no `.tl` build input mode.

- [ ] source translator CLI (eject model, visible residue comments, `any`
      fallbacks), translating metamethod declarations, `record X is Y`,
      bounded generics, nested type namespaces, and `self` directly into their
      landed nupp forms

## Formatting

Settled. The formatter is the specification and the tree was brought to it: 107
of 179 sources were rewritten, `fixpoint --update-bootstrap` refreshed the
tracked `bootstrap/nupp.lua` in the same commit, and `tests/fmttreetest.lua`
holds the tree there. That gate runs `nupp fmt --check` through the binary
rather than formatting the tree in process, which is the difference between a
quarter of a second and half a minute on every test run.

Four defects were fixed on the way, since a tree cannot be held to rules that
are wrong. A docblock's trailing annotation no longer takes the blank line that
belongs after the declaration it documents, so `@drop` stays with its field. A
comment that is the whole of an `if` arm indents inside the arm rather than
under the `elseif` that follows it. `borrows (p)` and a closure's `takes (a, b)`
keep the space that says they are clauses rather than calls of a function named
`borrows`. And a bare `;` terminates the statement before it instead of taking a
line of its own.

Two rules were added, both about lists that outgrow their line. An argument list
now spreads one argument per line whenever it stops fitting -- by width, by a
comment inside it, or by an argument whose own body is a block -- with the
exception that a call's trailing function or table hugs the line that opens the
call while what precedes its body still fits there. A table constructor spreads
on the same terms and has nothing to hug. Both are in
[fmt.md](../docs/tooling/fmt.md).

Coverage is `tests/fmtcorpus`, forty golden pairs across eleven categories, each
checked for exact output, for formatting its own output unchanged, and for the
token sequence surviving. `tests/fmtfuzztest.lua` makes the same three claims
about programs nobody wrote down, minimizes what it finds, and prints it ready
to be checked in under `tests/fmtcorpus/regressions/`.

- [ ] **A shape type with one field still breaks across three lines.** `Shape
      types always put each field on its own line` reads well for a record-like
      type and badly for `{string: any}` in a parameter list, which is twelve
      sites in this tree and every one of them worse for it. The rule is
      deliberate, documented and tested (`tests/fmtwidthtest.lua:143`), so
      changing it is another taste decision rather than a defect: either a
      one-field shape is exempt, or the rule holds and these read as they read.

## Performance and incrementality

Landed: cache keys are digested with XXH64 rather than a pure-Lua SHA-256, the
prelude no longer builds the project index on the way to every command, project
headers are stored between commands (`nupp.compiler.build.store`, plain data via
`string.buffer`, in the gitignored build directory), `nupp check` reuses
unchanged modules and replays their diagnostics, bundled module declarations are
checked when something asks for one, `nupp fmt` stores each file's formatting
verdict, the editor session writes what it worked out on shutdown, the project
scan prunes dot-directories instead of walking the whole checkout and discarding
it, the cross-process cutoff runs off what a dependent actually read rather than
off the whole project index, a warm command spawns no processes of its own, and
`nupp check FILE` reuses what the last check worked out about that file.

The cutoff used to be the largest item here. A module records the project queries
it asked and the fingerprint each answered with (`inc.projectDependencies`,
`src/nupp/compiler/incremental.nupp`), and reuse compares those one by one, so an
edit to an exported type declaration invalidates the modules that read that
declaration instead of every module in the project. The digest is
`declarationSignature` (`src/nupp/compiler/env.nupp`), which walks tokens and so
carries no trivia: reformatting a docblock above a record changes nothing.
`typeFingerprint` still declines to expand a nominal's members, which is correct,
and the keyed project dependency is what notices the changed record. Its
predecessor, a whole-project `projectIndexHash`, is gone rather than merely
unused: it was digesting every declaration of every header on every command and
being compared by nobody.

Discovery walks `nupp.io.files` on every platform now, pruning dot-directories at
the directory rather than at the path, and each root is listed once per
environment rather than once per question asked about it. That was eight `find`
subprocesses on a warm no-op check, four on `lsp inspect`, two on `check FILE`.
`process.capture`'s `os.tmpname` file turned out never to have been on this path
-- every caller is dependency resolution, native building or packaging. What is
left is `bin/nupp`'s own `find | head`, which stays: it is a shell script asking
whether any source is newer than the build stamp before it decides whether to
run the compiler at all, and there is no portable shell answer to that question
that is not `find`.

`nupp check FILE` goes through the project's own incremental check, seeded at the
named files rather than at the source set (`modules.Narrow`). It reuses records
on the same terms a whole-project check does, reports the named files rather than
everything the walk reached, and carries the rest of the stored state forward
untouched so that one narrow check does not throw away what the last full one
learned. A file the project does not reach -- a declaration file, a `.lua`, a
file from outside, or every file when there is no manifest -- is still parsed and
checked on its own.

What that bought, measured on a loaded machine and so in CPU time rather than
wall clock: a second `nupp check src/nupp/compiler/env.nupp` costs 0.22 s where
the August 7 note has the old path costing 0.82--0.93 s on every warm run. The
first one costs more than it used to, because it now checks and records the
file's whole dependency closure, and that warms the project check as well.

Historical August 7 measurements, before native file adoption and the later
type-system work: whole-project check 0.15 s against 1.26 s cold; `fmt --check`
0.15 s; no-op build 0.18 s; `lsp inspect` 0.13 s. The measured startup floor was
23 ms, against 2 ms for a bare `luajit -e ""`. These are stale; remeasure on an
otherwise idle machine before using them as current priorities.

A closure in a loop now has all three defences. `gen` refuses to build a function
inside a loop unless the site says why it cannot be declared once
(`src/nupp/compiler/gen.nupp`), `nupp bc --check` reads the bytecode of anything
and reports the same thing without running it, and user code is `NUPP2505` where
the closure lifts out unchanged and `jit-loop-closure` (`NUPP2515`) where it
reads the iteration and cannot. The second is off until a project asks for it,
because it reports correct code with no mechanical fix; what gives it teeth is
that it goes out through `c.jitHazards`, so a function annotated `@jit` promised
that it compiles and gets `NUPP2707` whatever the lint's level, and `jit.off` on
the enclosing function says nothing.

It found fifteen sites in this compiler and twelve of them are gone: a function
that reads the iteration is written above the loop and told what varies, which
in a few places also made what it does clearer. The three that remain are one
shape -- `nupp.compiler.comptime` and the two registration loops in
`nupp.compiler.materialize.peg` build a function *as* an identity, one object per
entry, so there is nothing to hoist. Each says so where it is written. They run
once, over a handful of entries.

Two of the twelve were loops `nupp bc --check` had not reported, and they are
the same shape: a `while` whose condition is a chain of tests, which leaves a
forward branch over the body, which is what the checker reads as "some branch
can skip this" and declines to report. That is the deliberately weak half of
that heuristic doing what it was written to do, and it is the case the source
lint answers, because a name that varies per pass is visible in the source
whatever the branches do.

The lint stays out of this project's own `nupp.lua` for a reason worth knowing
before trying: a manifest naming a lint the tracked `bootstrap/nupp.lua` has
never heard of cannot be read by the bootstrap, so a checkout with only the
bootstrap could not build. Enabling it here waits on
`fixpoint --update-bootstrap`.

What is left:

- [ ] **The store never shrinks below what a run touched.** `KEEP_COLD = 2048`
      (`src/nupp/compiler/build/store.nupp:36`) bounds the cold entries, which is fine
      for a project this size and unmeasured for a large one.
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

## Tecs

### Subsystem acceptance port

Translating and running `internal/ffi/FFIStorage` and its components is the
v0.1 gate, and it is the acceptance corpus several items above name: bounded
generic metatable receivers, bounds-carrying spans, the callback `jit.off`
lint, and dialect-interop runtime equivalence.

The port has started: `tests/acceptance/tecs` holds it, with `PORT.md` logging
what fought back. It is a running port, not a reading exercise — `run.nupp`
exercises the translated modules, and two compiler bugs were found by running
what checked clean.

```
 file                     lines  state
 ───────────────────────  ─────  ────────────────
 schema.tl                   49  ported, runs
 StableChunkedArray.tl       94  ported, runs
 init.tl                    111  not started
 EpochArena.tl              116  not started
 FFIEvents.tl               200  not started
 FFIStorage.tl              706  not started
```

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
