# Nupp TODO

Grouped by the part of the system a change lands in. Nothing here is
prioritised by tier; the ordering inside a section is roughly the order the
work makes sense in.

## Type system

- [ ] **Comptime** ([design](comptime.md)): deterministic data evaluation,
      deliberately not a macro or declaration-generation system. C1 has landed;
      the rest is below. Reach for it for a program that needs a generated
      table, not for one that wants a constant: those keep turning out to have
      cheaper answers, `OPT-3` having since taken `//` and the bit operators.
  - [ ] C2a: immutable `reflect(T)` descriptors over the checker's full
        structural vocabulary; semantic type fingerprints and module interface
        dependencies. Target-independent and blocked on nothing. Shared with a
        future derive phase, so it is not shaped around comptime's convenience.
  - [ ] C2b: target-aware `sizeof`/`alignof`/`offsetof`. Blocked on a
        compile-time layout model, which nupp has deliberately not built:
        `layoutof` answers the same question at run time through the FFI,
        because sizes belong to the running platform and not the compiling one.
        A separate project rather than the step after C1.
  - [ ] C3: `@comptime` functions with ordinary type checking, erased runtime
        output, bounded recursion, and comptime call stacks. File-private at
        first, but cross-module helpers are an expected extension; helpers
        taking a `TypeInfo` need nothing from the generic system.
  - [ ] C4: worker hardening beyond C1's floor — remaining resource limits,
        cancellation, LSP hardening, and eventual manifest build-cache
        persistence. Wants [suspension](suspension.md) and a real process
        library under it: a worker the language server waits on must not block
        its loop.
- [ ] **Suspension** ([design](suspension.md)): waiting as a checked, handled
      effect. One call site parks under a scheduler and blocks without one, so
      a library that waits works inside a game frame and inside a CLI without
      knowing which it is in. The analysis half exists — `yields` is inferred
      file-locally — and nothing consumes it or transports it between modules
      yet.
  - [ ] S0: serialize the `yields` bit in callable summaries, retain it through
        resolved function values, and conservatively treat an unconstrained
        callback as may-yield. No general effect rows.
  - [x] S0: the effect, transported. `noYield` is a positive guarantee on
        `types.Func`, in the interning key and in `typeFingerprint`, so both
        identity mechanisms see it. Boundary finalization qualifies each
        exported callable from its own definition after `analysis.run`, which
        is what separates two same-signature exports that interning had
        collapsed. `T.withYields` clones rather than respelling `T.func`.
        Function expressions are now summarized, without which a callable
        inside an exported table had no answer.

        A second pass closed three transport holes. Re-exporting an alias
        preserves an imported guarantee rather than erasing it, absent local
        provenance meaning nothing was learned and not that a fact was
        refuted. Every function-type reconstruction carries the qualifier --
        substitution, instantiation, receiver adjustment, and the shape
        comparison that drops a receiver. And every returned module surface is
        finalized, not only one assembled field by field, so a module that
        returns a function or a table literal is qualified too. A declared
        `yields = false` also outranks an inferred `external`, which is the
        one thing a contract exists to say.

        Left open: nominal methods are outside the qualified boundary and stay
        may-yield, since a nominal's identity survives rechecks and
        `typeFingerprint` does not expand its members, so a guarantee there
        could not be invalidated. `aNominalMethodIsNotQualified` pins that on
        the method's own type and is what should fail first when the
        effect-interface digest moves the boundary.
  - [ ] S1: `nosuspend` regions and `@effects(yields = false)`, with NUPP2701
        carrying the call chain. No run-time component, and worth landing
        alone after S0: it turns one of tecs's run-time errors into a checked
        one.
  - [ ] S2: the `suspend` operation, the `Suspension` handler interface
        with typed one-shot subscriptions and readiness contexts,
        coroutine-local handler inheritance, `handle ... with ... do`, and the
        built-in blocking fast path. tecs must retain its ready-path and frame
        performance.

        The runtime has landed (`src/nupp/suspension.nupp`): `suspend`, the
        handler interface with `canPark` and `shutdown`, per-coroutine
        installation as an affine `Installed` owner discharged by `with`,
        identity-keyed readiness sources with release handles, and the built-in
        blocking handler. 202ns and 416 bytes against tecs's 349 and 568
        (`bench/suspension-baseline.lua`).

        Two items remain, cleanly separated:
        (a) `handle suspension with h do ... end`, which elaborates to that
        `with` *and* marks its body a checked handled-suspension region. The
        mark is the point rather than the sugar: S4's resource permission rests
        on a lexical fact, not on an ambient run-time one.
        (b) coroutine handler inheritance across `create`, `resume` and `wrap`,
        with the save/switch/restore benchmarked per resumed task. Today a new
        coroutine inherits nothing, which is tested and safe but is not the
        eventual semantics.
  - [ ] S3: the C-call boundary — implicit `nosuspend` at known non-yieldable
        FFI and standard-library callback invocations, with safe metamethod and
        generic-loop suspension left alone and a named run-time failure for
        what static analysis cannot reach.
  - [ ] S4: permit handled suspension while a resource obligation is live,
        keeping NUPP2603 for raw coroutine yields. A handler owns every accepted
        park and its shutdown cancels and unwinds all parks before succeeding.
  - [ ] S5: `nupp.io.Process`. tecs's API surface — `communicate`, the
        Reader/Writer vocabulary, `Exit:succeeded` — over a new POSIX/Win32
        platform layer, since theirs is 48 SDL calls and Nupp cannot link SDL
        in order to run `nupp check`.

## FFI and the C boundary

- [ ] **`import-c` stops at the file it was pointed at.** One boundary
      question wearing two faces, and it is a design call rather than a bug.
      Declarations reached only through a private sibling header are invisible:
      macOS puts `strlen` in `_string.h`, so importing `string.h` correctly
      yields nothing (`filterToHeader`, `src/nupp/compiler/importc.nupp:41`). The same
      cut applies to constants, which are read from the target file's own text
      (`headerMacroNames`, `src/nupp/compiler/importc.nupp:213`), so `errno.h` — which
      defines `EPERM` in `sys/errno.h` — imports none at all.

      This is now the whole of the real-header sweep. Everything else that used
      to stop system headers is fixed, and a sweep of the macOS SDK confirms
      it: eight common headers all import without error, four usefully
      (`math.h` 213 functions, `unistd.h` 153, `fcntl.h` with `open`/`fcntl`,
      `zlib.h` 45), and the four empty ones — `stdio.h`, `stdlib.h`,
      `string.h`, `time.h` — are empty for exactly this reason.
- [ ] **Mark C-derived function types, then land the callback `jit.off`
      lint.** Passing a Lua function where C will call it creates an FFI
      callback, and a variadic FFI call or a callback that runs on a compiled
      trace corrupts or panics — but only past the trace threshold, so it
      survives every test that runs the path fewer than ~56 times. NUPP2502
      exists but fires only syntactically, at an `ffi.cast<ptr>(fn)` inside
      `unsafe` (`src/nupp/compiler/check/ffi.nupp:113`). The real check needs C function
      types *marked*: types are structurally interned, and `cheader` builds a
      plain `T.func` (`src/nupp/compiler/cheader.nupp:93`), so a C callback is today
      indistinguishable from an ordinary Lua function. Mark them where they are
      built — cdef signatures, `cheader` exports, C function pointers — then
      flag a Lua function reaching one without `jit.off`, and the variadic FFI
      call with it. This is the validation target's real production bug class,
      so it is worth the marking pass rather than a heuristic that guesses from
      argument shape.
- [ ] **Propagate string-pointer provenance past a bare name.** A pointer cast
      from a named string binding is a lexical borrow already
      (`src/nupp/compiler/check/ffi.nupp:107`), and string literals get the NUPP2501
      lint. But `ownershipEntry` unwraps only `paren`/`castExpr` and then
      requires a `name` (`src/nupp/compiler/check/ownership.nupp:196`), so a concat, an
      index, an alias, or a call result produces a `borrowed` type with a nil
      owner — borrowed in name, untracked in fact. Non-`local` assignments get
      no NUPP2501 at all.
- [ ] **Bounds-carrying spans, driven by the tecs buffer port.** Do not add a
      second byte-buffer runtime to Nupp: tecs already has the owned growable
      `Buffer`, retained immutable `ByteView`, and exclusive `WriteRange`.
      First express those APIs with Nupp ownership: owned/disposable buffers
      and views, consuming `commit`/`close`, a write range that prevents its
      source buffer from moving, closing, resizing, or detaching while live,
      and FFI pointers whose provenance is tied to the buffer/view/range. Then
      decide whether the repeated lower-level shape warrants a generic
      `span<T>`/`span<const T>` carrying pointer, runtime element count, and
      provenance. Safe indexing and slicing must check bounds; conversion to a
      raw pointer or unchecked bulk copy remains an explicit `unsafe` boundary.
      Use the real tecs compression, process-I/O, mapped-buffer, and
      pointer-plus-length APIs as the acceptance corpus.
- [ ] **`@jit` trace checker.** NYI analysis behind the pragma, which is
      likewise reserved and erroring today (`src/nupp/compiler/annotations.nupp:208`).
      Depends on nothing above except the marking pass it shares with the
      callback lint.
- [ ] Struct unions and bitfields (tagged C union lowering); malloc-backed big
      arrays. Fixed arrays `T[N]` landed.
- [ ] **A generalized `Serializable`, because reifying currently makes
      serializing worse.** Superseded in part by layout.md, which takes the
      reflection half; what stays open here is whether anything above it is
      wanted at all. A `struct` instance is cdata, and cdata is where the
      table-shaped world stops: `string.buffer.encode` raises `cannot serialize
      'cdata'` and offers no hook to install, `pairs` needs a `__pairs` on the
      metatype, and `type` answers `"cdata"`. So the largest speedup the
      language has is also the change that breaks the snapshot path, and
      `reifiable-record` (NUPP2509) has to warn about it rather than recommend
      it freely.

      The inversion available: nupp knows the field set and the C layout, so a
      reified value can serialize by copying its bytes rather than by walking
      its keys. Done properly, reifying makes serialization *faster* than the
      table it replaced, and the cost story turns into a reason.

      What has to be decided, roughly in order: whether the contract is an
      interface a declaration opts into or something every reifiable
      declaration gets; whether the wire form is layout-compatible bytes
      (fast, and hostage to field order, padding and endianness) or a described
      encoding that survives a layout change; how a graph with cycles and
      sharing is handled, since `string.buffer.encode` refuses both; and what
      a version skew between writer and reader is supposed to do.

      Do not design this from the declaration inward. tecs is the workload —
      "everything can serialize", world-wide snapshots, and fast — so
      `FFIStorage.tl` and `FFIEvents.tl` in the acceptance port
      (tests/acceptance/tecs) are what say which of the above actually matter.
      Two options short of it stay open meanwhile: a generated `__pairs` from
      the declared field set, which is cheap and restores iteration, and a
      generated conversion for crossing a boundary that only speaks tables.

## Ownership and resource scopes

- [x] **Cleanup functions are resolved references, not spellings.** Cleanup
      metadata is structured and carries a deterministic module-and-definition
      key. The producer registers its private function object; a consumer
      resolves it lazily on first discharge and then calls the cached upvalue.
      Lazy resolution preserves load order when a consumer module exists before
      the producer runs. This removes NUPP2620 and lets `nupp.resources` owners,
      C pointers, and other foreign values cross modules without publishing
      their cleanup functions.
- [x] **`@dispose` registration is idempotent across module rechecks.** Every
      inline, declared, external, or inherited default disposer now reaches one
      deduplicating operation. A cross-module regression runs `check`, `build`,
      and the program, proving that revisiting the exported nominal does not
      turn its one disposer into an ambiguous pair.
- [x] **Cleanup context is explicit owner state.** Ownership annotations erase,
      so a raw pointer has nowhere to retain a dynamic allocator, arena, or
      parent handle. Model `{context, value}` as a nominal record or struct and
      give it an `@dispose` method that calls `ctx_free(self.context,
      self.value)`. This uses the existing affine nominal path, preserves raw
      pointer identity, and introduces neither a hidden side table nor a closure
      per owner. The ownership reference documents the FFI pattern.

## Editor and docs tooling

- [ ] **Completion is receiver-correct but scope-blind.** After a `.` or `:`
      the answer is already what that receiver holds and nothing else. What is
      left: lexical-scope filtering of the ambient list — `complete.nupp:205`
      filters by source offset alone, so every file symbol is offered
      regardless of enclosing block; imported declarations and import-c
      namespaces, which `resolveReceiver` cannot reach
      (`src/nupp/compiler/lsp/navigate.nupp:314`) even though cdef structs already carry
      `byname`; callable snippets, which need `insertTextFormat` and are
      absent entirely; and module-path completion inside a `require` string.
- [ ] **Cancellation, stale results and multi-root.** `$/cancelRequest` is
      registered as a no-op (`src/nupp/compiler/lsp/init.nupp:868`), so it is understood
      only in the sense of not erroring; cancelling work in flight needs input
      readable without blocking, which this loop does not have. Graceful
      stale-request results need request-id tracking, which nothing does.
      Workspace folders are read and re-root correctly but collapse into one
      session, so real multi-root remains — see
      [plan.md](plan.md#lsp-follow-up).
- [ ] **Doc comments as checked grammar.** `@param` parses
      (`src/nupp/compiler/docblock.nupp:23`) and renders, but nothing verifies the names
      against the real parameter list — `@raises` is the only tag any checker
      reads. `[[Type]]` cross-references do not exist as syntax yet.
- [ ] **Docgen JSON output mode.** Static HTML landed (`nupp doc site`,
      `src/nupp/compiler/doc/html.nupp`). What external site generators need is a
      doc-model JSON emitter; `--format json` today is only the CLI's own
      report shape, which `src/nupp/compiler/cli/doc.nupp:43` says outright.
- [ ] **`nupp doc` never removes what it stopped writing.** A module build
      records its outputs and deletes the ones a later build did not produce
      (`src/nupp/compiler/build/project.nupp:202`); the docs target returns at line 93,
      before any of that runs. So a page keeps its rendered HTML after its
      route changes or its source is deleted. Restructuring this site left a
      whole `build/docs/guide/` tree behind, still serving pages whose links
      pointed at files that had moved — a link checker run over the output
      found them and they looked real, which is worse than a 404. The list is
      already in hand: `doc.files.collect` (`src/nupp/compiler/doc/files.nupp:20`)
      records every written path for `--json`. The docs path needs to store it
      and remove the difference.

## Build, codegen and distribution

- [ ] **`--gen-target` guardrails for struct modules** (plan §4: no silent
      erasure). No such flag exists yet; the only target flag is the manifest's
      `--target`.
- [ ] **`nupp doc` picks between two docs targets by hash order.** With no
      top-level `docs` table, `manifestSettings` returns the first
      `kind = "docs"` target `pairs()` reaches
      (`src/nupp/compiler/doc/init.nupp:392`), and `pairs()` does not promise an order.
      Two targets named `alpha` and `zulu` sent five consecutive runs to
      `out-zulu`, `out-alpha`, `out-zulu`, `out-alpha`, `out-alpha`. The
      command has no `--target`, so there is no way to say which was meant
      either. Either sort and take the first, prefer `build.default` when it
      names a docs target, or refuse and ask — but not this.
- [ ] **An unknown key in most of the manifest is still ignored.** Closed key
      sets cover the docs target, its pages, hero actions, features, and
      `config.fmt` (`src/nupp/compiler/build/manifest.nupp:75,97,228`). Everywhere else
      — top level, module targets, dependencies — a typo is silently accepted.
      The docs target got the closed set because the generator reads keys the
      build's validation knows nothing about; the argument is weaker elsewhere,
      but "this configures nothing" is worth saying wherever it is true.
- [ ] **`nupp.lua`'s `syntax` and `runtimeTarget` configure nothing.** Neither
      key appears anywhere in `src/`, and neither is validated, so a manifest
      setting them is a silent no-op. `strict` is honored end to end — builds,
      direct checks, the incremental checker, LSP sessions.
- [ ] **Single-binary host.** LuaJIT, lua-cjson, LPeg and luautf8 are pinned by
      revision and SHA-256 and built from source by `host/build.rs`, not
      committed; `cjson`/`cjson.safe` are registered in `package.preload`
      (`host/src/lua.rs:68`); the binary container, trailer and stamping are
      implemented (`src/nupp/compiler/build/package.nupp:154`, `host/src/payload.rs`).
      What remains:
  - [ ] decide whether pinned-and-fetched is enough or the sources should be
        vendored in-tree (plan.md §Distribution said vendored)
  - [ ] strict JSON numbers and explicit empty array/object semantics are set
        per call site on the Nupp side, not in the host
  - [ ] malformed-input fuzzing and framed LSP replay
  - [ ] pinned revision metadata and MIT license notices in `host/`
  - [ ] per-platform runtime stubs: a binary target takes a single `stub` path,
        with no target list and no cross-build stub selection, and no stubs are
        shipped
- [ ] Hot-reload typing; the `nupp-cargo` Rust helper.

## Dialect interop (`import-tl`)

Design in plan.md §Dialect interop. Nothing is implemented: no `.tl` handling
in module resolution, no translator subcommand, no `.tl` build input mode.

- [ ] declaration reader (.d.tl subset → interned types, wired into module
      resolution)
- [ ] source translator CLI (eject model, visible residue comments, `any`
      fallbacks), translating metamethod declarations, `record X is Y`,
      bounded generics, nested type namespaces, and `self` directly into their
      landed nupp forms
- [ ] build-system `.tl` input mode for mixed trees
- [ ] expose macroexp-produced protocol declarations explicitly during
      translation; tecs's generated `DoubleArray.__len` must become a visible
      contract rather than being attributed to comptime
- [ ] runtime-equivalence verification against the tecs subsystem corpus

## Diagnostics

- [ ] **`@deprecated` API metadata.** Allow functions, methods, fields, types,
      and module members to name an optional reason and replacement. Report a
      suppressible use-site lint; carry the metadata through module interfaces;
      expose the LSP `deprecated` tag/modifier in completion, hover, and
      semantic tokens; and render it in generated documentation. The annotation
      affects tooling only and emits no runtime behavior. Nothing exists today.
- [ ] **The `pedantic` category has no members**, so setting it in `nupp.lua`
      moves nothing. (`style` has one now, `customary-operator`.)
- [ ] **Report an `@allow` that silenced nothing**, so stale suppressions get
      removed rather than accumulating. Nothing tracks whether a suppression
      fired (`src/nupp/compiler/check/pragma.nupp:226`).
- [ ] **Grow the worked examples in `explain.nupp`.** Nine entries, seven with
      a `wrong`/`right` pair (NUPP1002, NUPP2001, NUPP2004, NUPP2106, NUPP2107,
      NUPP2119, NUPP2122); every other code answers through its family, which
      states the rule but cannot show the mistake. Two things lean on that
      table: `nupp explain` is the retrieval path a reader reaches from a
      diagnostic's `docs` anchor, and `nupp reference` lists the codes an
      example can say more about. Both get better per entry added, and
      `tests/explaintest.lua` already compiles each pair, so an entry cannot be
      added wrongly. The eleven the reference cites and cannot yet expand are
      NUPP2002, NUPP2101, NUPP2108, NUPP2118, NUPP2120, NUPP2203, NUPP2504,
      NUPP2506, NUPP2603, NUPP2610 and NUPP2615: a reader is pointed at those
      having just met the construct, so they are worth the most per entry.

## Formatting

- [ ] **The tree is not `fmt`-clean, and it is not obvious which side is
      wrong.** `nupp fmt --check` lists 103 of 110 sources, almost entirely
      single-line `if ... then return end`, which the compiler is written in
      throughout and which the formatter breaks across lines by a rule its own
      source calls deliberate. So either the house style or the rule has to
      give, and it is a taste decision rather than a defect. The repo was
      formatted once, when the width-aware formatter landed, and has drifted
      back since.

      Reformatting is not a free mechanical pass, which is the part worth
      knowing before starting: generated Lua preserves the source line count,
      so moving a statement to a new line changes every artifact the compiler
      emits, which changes the compiler's own build, which means
      `fixpoint --update-bootstrap` and a new tracked `bootstrap/nupp.lua` in
      the same commit. Until it is settled, `nupp fmt` cannot gate this
      repository.
- [ ] **There is no formatter corpus directory.** `tests/fmtcorpus/` does not
      exist; coverage is inline assertions in `tests/fmttest.lua` and
      `tests/fmtwidthtest.lua`, plus a fixed 14-entry idempotency list. Collect
      golden input + expected files under the PLAN doctrine (120/88/4,
      one-arg-per-line), run through idempotency and parse-stability in
      addition to exact match. Existing inline coverage per category is noted
      where it exists:
  - [ ] Comment placement: have leading/trailing and comment-only files; need
        `if`/`elseif` arms, inside table constructors, doc-comment blocks
        before declarations.
  - [ ] Blank-line policy: have the 3+ collapse; need around functions,
        between record fields, top of file.
  - [ ] Long lines: have call arguments, params, binary-op chains, ternaries;
        need chained method calls (`report:put(...):putf(...)`), long union
        annotations, long generic parameter lists.
  - [ ] Tables: have break-when-long and indentation; need the inline-vs-
        multiline threshold pinned, nested tables, mixed array/named fields,
        trailing separators, and a chosen alignment doctrine.
  - [ ] Typed layer: only a few colon-spacing asserts. Need every annotation
        position (locals, params, returns, fields, shapes, maps), `T?`/`S*?`
        tightness, generics `<K, V>` and `<T is Bound>`, `record X is Y`,
        `where`, metamethod contracts, inline methods, function types with
        parenthesized multi-returns, and cdef blocks (C-name fields with
        underscores stay untouched).
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
verdict, the editor session writes what it worked out on shutdown, and the
project scan prunes dot-directories instead of walking the whole checkout and
discarding it.

Measured warm, re-confirmed: whole-project check 0.15 s against 1.26 s cold;
`fmt --check` 0.15 s; no-op build 0.18 s; `lsp inspect` 0.13 s. The startup
floor is 23 ms, against 2 ms for a bare `luajit -e ""`.

What is left, in the order the numbers justify:

- [ ] **Seven subprocesses per warm command, and four of them are two
      listings.** A warm check is ~20 ms of interpreter start, ~45 ms of actual
      work, and six `find` invocations plus a `mkdir`. `./src` and
      `./build/generated` are each listed twice
      (`src/nupp/compiler/env.nupp:95`, `src/nupp/compiler/fs.nupp:85`), and `bin/nupp` spawns
      about four more before it execs. `process.capture` also creates and
      removes an `os.tmpname` file per call. `nupp.compiler.fs` shells out because Lua
      has no directory API and the FFI would need one implementation per
      platform; that reasoning still holds, but the price is now most of what a
      warm command costs. Memoizing per environment removes the duplicates —
      except that an editor session lives for hours and files appear in it, so
      the memo needs an invalidation story before it is safe.
- [ ] **`nupp check FILE` has no per-module reuse at all.**
      `src/nupp/compiler/cli/check.nupp:76` re-parses and re-checks the named file
      unconditionally; only the header index is cached. The 0.14 s figure is
      the startup-plus-index floor measured on a small file — `src/nupp/compiler/env.nupp`
      costs 0.82–0.93 s on every warm run. This is the largest single number
      left and the one an editor hits most.
- [ ] **Cross-process cutoff is at the module, not the interface.** A body edit
      stops at an unchanged interface, because the interface digest is recorded
      and compared. But any edit to an exported *type declaration* changes
      `projectIndexHash`, which disables reuse for the whole project: the digest
      covers each declaration's `cst.textOf` (`src/nupp/compiler/env.nupp:299`), which
      emits leading trivia, so reformatting a docblock above a record rechecks
      everything. The other half of the same mechanism is `typeFingerprint`,
      which describes a nominal by its declaration kind and name and
      deliberately does not expand members (`src/nupp/compiler/build/modules.nupp:37`) —
      correct in itself, but it means the interface digest leans entirely on
      `projectIndexHash` to notice a changed record. Narrow the digest to what
      a dependent can actually observe and make the two one mechanism rather
      than two that happen to cover each other.
- [ ] **The prelude image, if 11 ms is worth it.** `env.new` is 11.7 ms and all
      of it is parsing and checking `prelude.d.nupp`, on every command. Storing
      the result means storing a cyclic type graph, which
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
      (`src/nupp/compiler/build/store.nupp:35`) bounds the cold entries, which is fine
      for a project this size and unmeasured for a large one.

## Testing and CI

- [ ] **Complete the operator-contract matrix.** Only `__add` has a direct
      contract test (`tests/checktest.lua:200`); no test anywhere mentions
      `__unm`, `__sub`, `__mul`, `__div`, `__mod`, `__pow`, `__lt`, `__le`,
      `__concat` or `__eq` dispatch. The table under test is
      `operators.metamethod`/`contractMetamethod`
      (`src/nupp/compiler/check/operators.nupp:45`). Needed: unary minus, subtraction,
      multiplication, division, modulo, power, right-hand fallback, and
      comparison reversal/`__lt` fallback for `<=`.
- [ ] **CI matrix** (GitHub Actions). There is no `.github/` at all. macOS +
      Linux, LuaJIT 2.1 rolling (2.1.1784535649 is the floor) + (when released)
      3.0; run `./tests/run`, the tl.lua oracle, and import-c fixture tests;
      track `bench/reification.lua` and `bench/aos.nupp` numbers as an artifact
      per commit (regression fence around the reification speedup).
- [ ] **Fuzzing.** No corpus exists — `tests/corpustest.lua` is an oracle over
      two hardcoded external paths, skipped when absent. Grow a random-input
      corpus for lexer/parser round-trip and fmt idempotency (`fmt∘fmt = fmt`,
      `parse∘fmt = parse`); minimize and check in failures as regression
      fixtures.
- [ ] **Every lint has to be exercised, by construction.** All eleven have a
      test today, but nothing enforces it: the next one can land untested and
      the suite stays green. `tests/allowtest.lua:everyLintIsWellFormed`
      already iterates `check.lints` to check each entry's shape, so the missing
      half is a fixture table keyed by code — one source that must report it,
      one neighbouring source that must not — driven off the same registry, so
      a lint with no fixture fails the run rather than being noticed later.

      Both halves matter. `reifiable-record` was written whitelist-first and
      the silent cases are most of its value; a lint with only a positive test
      passes while firing on everything.
- [ ] **`luajit tests/run.lua` segfaults roughly one run in eight, in
      libunwind.** Not a nupp defect as far as the evidence goes, and not new:
      seven macOS crash reports, all one signature, the earliest from 08-08
      11:25 — between two refinement commits, days before the work that first
      noticed it.

      ```
      EXC_BAD_ACCESS  KERN_INVALID_ADDRESS at 0x8
        libunwind.dylib   unw_set_reg
        luajit            ?
        libunwind.dylib   _Unwind_RaiseException
        luajit            lua_pcall
        luajit            lua_cpcall
      ```

      So: an error being raised, unwound through the system unwinder, which
      dereferences near-null. `lua_cpcall` is the frontend's own frame, not a
      per-test one, and the runner does nothing unusual — `pcall` around a test
      body, with descriptors redirected by `dup2` either side of it. LuaJIT on
      arm64 macOS uses external unwinding for error propagation, and that is
      where this lives.

      What it is not: a wrong answer. The suite passes on the runs that
      complete, and `fixpoint` has never been affected. What it costs is a CI
      job failing at random, which is why it is worth a note rather than a
      shrug.

      Leads, in the order worth trying: reproduce under a LuaJIT built with
      assertions, or with `MallocStackLogging=1` for a real backtrace; check
      whether it correlates with the tests that deliberately raise; and see
      whether a LuaJIT newer than 2.1.1785577137 has touched arm64 unwinding.
      Re-running the suite has stopped being informative — it reproduces about
      as often as a coin lands heads three times, which is enough to be sure it
      is real and not enough to bisect by hand.
- [ ] **`tests/profiletest.lua traceRecordsWhereTheCompilerGaveUp` is
      flaky.** Recorded failing once in six runs with "unrecordable bytecode
      must be reported"; it depends on the JIT attempting and aborting a trace
      within 3000 iterations after `jit.flush()`. Sixteen consecutive runs pass
      today, so the rate is lower than recorded or machine-dependent — but a
      test whose result depends on trace timing will keep costing somebody a
      bisect.

## Acceptance: the tecs subsystem port

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
      and arithmetic contracts (`tests/gentest.lua:84`,
      `tests/checktest.lua:163,191`).
