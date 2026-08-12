# Nupp TODO

Grouped by the part of the system a change lands in. Nothing here is
prioritised by tier; the ordering inside a section is roughly the order the
work makes sense in.

## Type system

- [ ] **Derives** ([design](derives.md)): the compiler-owned `Debug`, `Default`,
      single-field `From`, and `JSON` derives have landed as checked semantic
      additions with closed lowering recipes, never source or CST fragments.
      Generated-member tooling, path-stable fingerprints, incremental cutoff,
      bounded cancellation/recovery, build observations and internal/external
      acceptance workloads and the D5 closure gates have landed. Associated
      types are not a prerequisite.
  - [ ] D6: only after D5d, prototype one external provider against a versioned
        serialized descriptor/result envelope, then accept, narrow or reject a
        restricted semantic API in writing. Do not expose token, AST or CST
        macros, mutable compiler objects, or private lowering IR.
- [ ] **An inline method's `borrows` result is lost when its body returns
      through a cast.** Two records, the same signature
      `lend: function(self: H): thing* borrows (self)` and the same body
      `return self.slot as thing*`. Declared as a member and defined below it,
      a caller gets a borrow. Written as an inline `function lend(self)`, the
      caller gets the raw value and its first dereference reports NUPP2604.
      Nothing points at the method.

      The parts that look guilty are not. `nupp lsp inspect` prints the same
      member type both ways, `function(self: H): borrowed<thing*>`, so the
      recorded signature is right. Generics are not involved. Neither is the
      method being inline on its own: an inline body returning `self.slot`
      without a cast keeps the borrow. It is the combination, and the call site
      is where the qualifier goes missing, so look at how a method call types its
      result when the callee is an inline definition rather than a declared
      member. `resources.Set.adopt` is declared and defined apart because of
      this; its sibling `remove`, which returns no borrow, is inline.

## Editor and docs tooling

- [ ] **Stale LSP results and true multi-root.** Cancellation is no longer a
      no-op: the stdio transport reads through a child process, harvests
      `$/cancelRequest` while work is in flight, returns `RequestCancelled` for
      canceled request IDs, and lets a comptime worker stop through the same
      host (`src/nupp/compiler/lsp/init.nupp`, `src/nupp/compiler/comptime_worker.nupp`).
      Long synchronous compiler work outside that worker still has no
      cooperative cancellation checkpoints. Requests also do not retain the
      document version they began against, so a response cannot be discarded
      explicitly when a newer edit has arrived. Workspace folders re-root the
      incremental graph correctly, but all folders still share one environment
      and configuration; independent per-root sessions and result provenance
      remain.

## Build, codegen and distribution

- [ ] **Single-binary host.** LuaJIT, lua-cjson and luautf8 are pinned by
      revision and SHA-256 and built from source by `host/build.rs`, not
      committed. LPeg is no longer a host C dependency; the compatible runtime
      is generated Lua. `cjson`/`cjson.safe` are registered in
      `package.preload`; the binary container, trailer, stamping, pinned
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

## Dialect interop (`import-tl`)

No design document in the tree, and nothing is implemented: no `.tl` handling
in module resolution, no translator subcommand, no `.tl` build input mode.

- [ ] source translator CLI (eject model, visible residue comments, `any`
      fallbacks), translating metamethod declarations, `record X is Y`,
      bounded generics, nested type namespaces, and `self` directly into their
      landed nupp forms

## Formatting

- [ ] **The tree is not `fmt`-clean, and it is not obvious which side is
      wrong.** An August 10 direct formatter scan found 62 of 154 project
      sources non-clean. Only seven of those contained a same-line
      `then ... return ... end`, so the old claim that guard clauses accounted
      for almost all drift was wrong. Either the house style or formatter rules
      have to give, and that is a taste decision rather than a defect. Recount
      with the ordinary command once its bootstrap and generated compiler agree
      again rather than treating these figures as a permanent baseline.

      Reformatting is not a free mechanical pass, which is the part worth
      knowing before starting: generated Lua preserves the source line count,
      so moving a statement to a new line changes every artifact the compiler
      emits, which changes the compiler's own build, which means
      `fixpoint --update-bootstrap` and a new tracked `bootstrap/nupp.lua` in
      the same commit. Until it is settled, `nupp fmt` cannot gate this
      repository.
- [ ] **There is no formatter corpus directory.** `tests/fmtcorpus/` does not
      exist; coverage is inline assertions in `tests/fmttest.lua` and
      `tests/fmtwidthtest.lua`, `tests/typedtest.lua`, and several syntax-specific
      suites, plus a fixed 14-entry idempotency list. Collect golden input +
      expected files under the PLAN doctrine (120/88/4, one-arg-per-line), run
      through idempotency and parse-stability in addition to exact match.
      Existing inline coverage per category is noted where it exists:
  - [ ] Comment placement: have leading/trailing and comment-only files plus
        doc-comment blocks before declarations; need `if`/`elseif` arms and
        comments inside table constructors.
  - [ ] Blank-line policy: have the 3+ collapse and coverage around functions;
        need between record fields and at the top of a file.
  - [ ] Long lines: have call arguments, params, binary-op chains, ternaries;
        need chained method calls (`report:put(...):putf(...)`), long union
        annotations, long generic parameter lists.
  - [ ] Tables: have break-when-long and indentation; need the inline-vs-
        multiline threshold pinned, nested tables, mixed array/named fields,
        trailing separators, and a chosen alignment doctrine.
  - [ ] Typed layer: locals, maps, generics, return packs, optional tightness,
        record bounds and `is`/`where`, metamethods, and inline methods have
        inline coverage. Consolidate every annotation position into the corpus
        and add cdef blocks, where C-name fields with underscores stay untouched.
  - [ ] Short functions: have pipe spacing, single-param, no-param, vararg, as
        call argument; need `-> do` blocks and nested/curried chains.
  - [ ] Interpolated strings: one `${1 + 2}` assert. Need multiline templates
        (never reflowed), nested templates, escapes.
  - [ ] Statements: have guard-clause expansion, numeric-for, goto; need
        semicolon statements.
  - [ ] Pathological: have unbreakable long lines, hashbang, unicode. Need
        CRLF input (nothing in the formatter or its tests mentions `\r\n` at
        all), deeply nested expressions at the wrap boundary, one-line whole
        programs.
  - [ ] Idempotency fuzz: the current pass is a deterministic fixed list, not
        fuzz. Random input, minimized failures checked in as regression
        fixtures.

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

What is left:

- [ ] **The prelude image, if its cost becomes worth it.** `env.new` measured
      11.7 ms on August 7, all of it parsing and checking `prelude.d.nupp` on
      every command. Storing the result means storing a cyclic type graph, which
      `string.buffer.encode` cannot do — it rejects cycles and does not
      preserve sharing — so it needs a codec that assigns object ids and
      rebuilds by reference. The delicate part is not the codec but
      `types.nupp`'s arena: every structural type is interned under its
      canonical `id`, and a restored graph has to be rewritten to whatever the
      arena already holds before anything compares two types by identity. Get
      that wrong and the interface cutoff either stops cutting off or starts
      cutting off things that differ. Eleven milliseconds against the most
      identity-sensitive machinery in the compiler is a bad trade today; it
      becomes a good one if the floor drops further or the graph grows.
- [ ] **The store never shrinks below what a run touched.** `KEEP_COLD = 2048`
      (`src/nupp/compiler/build/store.nupp:36`) bounds the cold entries, which is fine
      for a project this size and unmeasured for a large one.

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
