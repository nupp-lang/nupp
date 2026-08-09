# Nupp TODO

Grouped by the part of the system a change lands in. Nothing here is
prioritised by tier; the ordering inside a section is roughly the order the
work makes sense in.

## Type system

- [x] **Enforce `where` predicates.** A refinement is read into plain data on
      the nominal (`src/nupp/predicate.nupp`), held to the declaration's own
      fields, and compiled: `x is T` becomes the test. That gives an interface a
      runtime identity it never had — `is` on one was NUPP3001 — so a value this
      program did not build can answer `is`, which a stamped metatable cannot
      do. NUPP2122 now means the refinement cannot be enforced, naming what was
      written. The dialect translator no longer needs its unchecked-residue
      marker; a `where` in a declaration head says it moved into the body.

      Left open: the subset is comparisons against literals, `type()` tests and
      the boolean operators, so a refinement cannot yet say `#self.items > 0`.
      Nothing checks that a union's members have refinements that can tell each
      other apart, and nothing checks a construction against the refinement of
      what it builds — `new Circle {kind = "square"}` passes.
- [x] **Settle what `is` means, and let an interface carry defaults**
      ([design](identity.md)). A record is nominal and answers through its
      prototype, so an instance a constructor linked back rather than stamped —
      tecs's events — is one. An interface is a contract: a test its own type
      already proves is not run, a tagged one derives its test from the literal
      fields it declares, and a `matches` block says what neither can. A
      refinement is an interface's alone, so `is R` means one thing for every
      record. An interface may implement what it declares, with `@override`
      required to replace a default and two providers of one name refused.

      Conformance markers are deliberately not built. Giving every interface a
      runtime table and every declaration a `__nuppIs` set, so `is I` could be
      exact, buys one case: an *untagged* interface against a subject whose type
      does not prove conformance. A tag, static knowledge, or a `matches` block
      answers everything else, and NUPP3001 now names all three where it fires.
      That is a better trade than paying runtime weight across the language for
      the case a reader can resolve by writing one of the three.
- [x] **Check metatable bodies, not just key spellings**
      ([design](metatables.md)). A declared contract is held to the value that
      fulfils it, wherever a literal meets a `metatable<T>`: a call argument, an
      annotated binding or assignment, and a bounded receiver, which needed no
      new mechanism because `ops.metamethodOf` already resolves through a bound.
      A registrar taking `E is Event` therefore checks its own body rather than
      relying on its call sites. Where a declaration contracts for nothing,
      LuaJIT's own requirements are held instead, and a table written under
      `__index` is checked against the members it stands in for. NUPP2123 is the
      new code; unknown keys keep NUPP2118 and its spelling repair, now applied
      wherever a literal appears rather than at `setmetatable` alone.

      The fourth position was a live wrong answer rather than a gap.
      `I64.__tostring = <correct function>` was refused as "no field", and a
      typo got the same message. Installing on a record's own table is now the
      installation it reads as, and a double-underscore name that matches
      nothing is spelled against the contracts the receiver declares, so the two
      mistakes no longer read alike.

      Left open: a contract that is declared and never installed is legal and
      unreported. It would have to be a lint rather than an error, since
      installation may be split across statements or modules, which is the tecs
      shape.
- [x] **Type a record's own table** ([design](prototype-types.md)). A record
      bound its name twice, as a type and as the runtime table, and both held
      the same type — so the table and the instances it stamps were
      interchangeable, though the runtime never agreed: `is` compiles to
      `getmetatable(x)?.__index == R`. The value binding now holds
      `metatable<R>`, which is what that table is, and so do a nested record
      reached through its owner and one exported from another module.

      That closes `setmetatable(t, R)` — the oldest way to write a class in Lua,
      and the one use of a metatable the checker refused — and lets a metamethod
      written on an instance be refused, where the function would land somewhere
      the operator never looks. `R is R` is answered without running.

      A registrar says which it takes: `newEvent<E is Event>(event: metatable<E>)`
      rather than `event: E`. There is no deprecation path, so anything written
      to the old shape needs the edit; in this tree it was four sites.

      Left open: `metatable<R>` exposes instance fields as well as what lives on
      the table, because the tecs registrar fills a declared field (`event.init`)
      on it. Separating the two would catch `R.field` as the nil read it is, but
      needs a way to say a field is filled on the table after declaration.
      Structs keep their bare nominal: their identity is a ctype and
      `ffi.istype` already answers it exactly.
- [x] **Intersection types, including overloads as function intersections**
      ([design](intersections.md)).
      Add `A & B` with normalization, subtyping, useful emptiness diagnostics,
      and read/write/indexer composition. An intersection of function types is
      the overload set: infer arguments once, probe candidates without mutating
      checker state, require exactly one survivor, and only then apply its
      return, ownership, borrowing, predicate, `noreturn`, and C-boundary
      contracts. **NUPP2124** reports proven emptiness, **NUPP2125** no matching
      overload, and **NUPP2126** ambiguity. The selector consumes the landed
      pack representation directly, preserving generic tails, correlated
      alternatives, ownership modes, and result provenance.

      Declarations retain ordered constructor provenance alongside the callable
      intersection, select statically, and emit a direct call to the indexed
      function minted for the winner. Constructor effect analysis follows that
      selected body; nothing is dispatched at run time.
- [x] **First-class type packs and variadic generics**
      ([design](type-packs.md)). Represent function
      parameters and results as value sequences rather than ordinary tuple
      types, with a fixed head and optional homogeneous or generic tail. Add
      generic pack binders such as `A...`/`R...` so forwarding functions
      preserve heterogeneous argument and result lists. Model Lua's exact
      expansion, truncation, last-expression, and parenthesized single-value
      rules in calls, assignments, and returns. Use packs to type `pcall`,
      `xpcall`, `select`, `unpack`, coroutine resume/yield, and generic
      adapters without collapsing to `any`; success/failure APIs use correlated
      unions of result packs. Every pack element retains its
      ownership mode and borrow provenance, and an affine result may not be
      silently truncated or discarded by generic forwarding.
- [ ] **Comptime** ([design](comptime.md)): deterministic data evaluation,
      deliberately not a macro or declaration-generation system. Unstarted —
      `comptime` is not a token, and `@comptime` is a reserved annotation that
      errors with NUPP2113 (`src/nupp/annotations.nupp:214`).
  - [ ] C1: `comptime do ... end` expression blocks; compile-time-known
        literals and `const` bindings; capability-limited evaluation; canonical
        literal/table quoting; line-count-preserving generation; in-memory
        query caching and equal-result cutoff.
  - [ ] C2: target-aware `sizeof`/`alignof`/`offsetof`; immutable `reflect(T)`
        descriptors; semantic type fingerprints and module interface
        dependencies.
  - [ ] C3: file-private `@comptime` functions with ordinary type checking,
        erased runtime output, bounded recursion, and comptime call stacks.
  - [ ] C4: isolated evaluator worker, cancellation/resource limits, LSP
        hardening, and eventual manifest build-cache persistence.

## FFI and the C boundary

- [ ] **`import-c` stops at the file it was pointed at.** One boundary
      question wearing two faces, and it is a design call rather than a bug.
      Declarations reached only through a private sibling header are invisible:
      macOS puts `strlen` in `_string.h`, so importing `string.h` correctly
      yields nothing (`filterToHeader`, `src/nupp/importc.nupp:41`). The same
      cut applies to constants, which are read from the target file's own text
      (`headerMacroNames`, `src/nupp/importc.nupp:213`), so `errno.h` — which
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
      `unsafe` (`src/nupp/check/ffi.nupp:113`). The real check needs C function
      types *marked*: types are structurally interned, and `cheader` builds a
      plain `T.func` (`src/nupp/cheader.nupp:93`), so a C callback is today
      indistinguishable from an ordinary Lua function. Mark them where they are
      built — cdef signatures, `cheader` exports, C function pointers — then
      flag a Lua function reaching one without `jit.off`, and the variadic FFI
      call with it. This is the validation target's real production bug class,
      so it is worth the marking pass rather than a heuristic that guesses from
      argument shape.
- [ ] **Propagate string-pointer provenance past a bare name.** A pointer cast
      from a named string binding is a lexical borrow already
      (`src/nupp/check/ffi.nupp:107`), and string literals get the NUPP2501
      lint. But `ownershipEntry` unwraps only `paren`/`castExpr` and then
      requires a `name` (`src/nupp/check/ownership.nupp:196`), so a concat, an
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
      likewise reserved and erroring today (`src/nupp/annotations.nupp:208`).
      Depends on nothing above except the marking pass it shares with the
      callback lint.
- [ ] Struct unions and bitfields (tagged C union lowering); malloc-backed big
      arrays. Fixed arrays `T[N]` landed.
- [ ] **Struct layout reflection** ([design](layout.md)). What reifying broke,
      answered without imposing a format: field names in declaration order,
      each field's C type, offset, size and padding, the struct's size, and a
      fingerprint. `layoutof(T)` lowers at the call site, so a program that
      never asks pays nothing. tecs is the workload and draws the line — its
      166-line runtime codec generator is what this makes unnecessary, and its
      2411-line snapshot format is what nupp should not try to see.
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

- [ ] **A cleanup is a spelling, not a resolved reference.** `Type.cleanups` is
      `{string}` (`src/nupp/types.nupp:110`), so every reader re-resolves it in
      its own scope: the checker through `lookupVar`
      (`src/nupp/check/ownership.nupp:96`), the generator as a bare identifier
      (`src/nupp/gen.nupp:752`). They agree only inside the declaring module,
      which is why letting an owner cross produced a program that checked clean
      and crashed. It is a linking problem wearing a codegen costume — source
      spellings written into object files and resolved again at each use.

      Resolve it once, at the declaration, and store what it resolved to. The
      generator already emits two such forms: `@method:` calls through the
      owner, `@field|` through one of its fields. Both travel with the value
      and cross boundaries free. The missing third is a free function, which
      needs to name where it lives.

      Prefer a registry over an exported path. A module-qualified reference
      would work, but forces the cleanup public — and a cleanup is the other
      half of a contract, not surface anyone should call. Instead let the
      declaring module register the function object under a key it already
      owns, and let a consumer hoist one lookup at load:

          -- in nupp.std.resources, at load
          __nupp_cleanup["nupp.std.resources#close_file"] = close_file

          -- in the consumer, once per module
          local __c1 = __nupp_cleanup["nupp.std.resources#close_file"]
          ...
          pcall(__c1, handle)

      The key is the module plus the name, not a counter: separate compilation
      has no link step to hand out globally unique integers, and two modules
      would both mint the same one. Hoisting keeps the discharge a direct call
      on an upvalue, so this costs one table read per consuming module rather
      than anything per discharge — which is the only version compatible with
      ownership lowering to nothing.

      Landing this removes the NUPP2620 restriction and the `allowUnknown`
      suppression at both discharge sites. It is also the whole of the
      standard-library problem: a stdlib wrapper returns owners whose cleanups
      are module-local free functions, so acquiring one reports NUPP2620 today
      (confirmed), and `LuaFile` is a builtin so the `@dispose` repair is not
      open to it either. Everything short of discharge already works — argument
      and result checking, and NUPP2603 for an owner that is never discharged —
      and `with.md`, the README and the tour all teach a locally declared
      producer, so no page depends on it. `@dispose` should still be the
      documented default for a type you define; the free-function form is for
      foreign types — `LuaFile`, C pointers, cdata — that cannot carry a
      method.
- [ ] **`@dispose` on a record method double-registers across modules.** Still
      reproduces, and the cause is located. `check` and `build` disagree:

          $ nupp check --strict main.nupp     # clean
          $ nupp run main.nupp
          res.nupp:11:2: error: NUPP2602: bare @owned has multiple inherited
          @dispose operations; choose one with @owned(cleanup)

      `src/nupp/check/declare.nupp:394` appends `"@method:" .. name` to
      `n.defaultDisposers` unconditionally, where the free-function path
      `own.registerDefaultDisposer` (`src/nupp/check/ownership.nupp:188`)
      dedups first. Re-checking the declaring module against the same nominal
      appends twice and `ownership.nupp:169` fires on `#defaults > 1`. It needs
      the record to be a table member (`record res.File`) to show up; a
      `local record` does not reproduce. Worth doing early on two counts: a
      diagnostic that only appears on one of two commands is the kind nobody
      trusts, and `@dispose` is the repair NUPP2620 tells people to reach for,
      so it has to work across modules before that advice is honest.
- [ ] **A cleanup takes the owner and nothing else.** `@owned(cleanup)` emits
      exactly `cleanup(__p)` (`src/nupp/gen.nupp:737`), and the annotation
      accepts only function names (`src/nupp/check/pragma.nupp:102`), so a
      cleanup needing context — an allocator, an arena, a parent handle,
      `ctx_free(ctx, ptr)` — has nowhere to put it. Capturing the context would
      mean a closure per owner, which is the allocation this model exists to
      avoid. Real in FFI and unaddressed; worth a design before someone hits
      it, and independent of the reference question above.

## Editor and docs tooling

- [ ] **Completion is receiver-correct but scope-blind.** After a `.` or `:`
      the answer is already what that receiver holds and nothing else. What is
      left: lexical-scope filtering of the ambient list — `complete.nupp:205`
      filters by source offset alone, so every file symbol is offered
      regardless of enclosing block; imported declarations and import-c
      namespaces, which `resolveReceiver` cannot reach
      (`src/nupp/lsp/navigate.nupp:314`) even though cdef structs already carry
      `byname`; callable snippets, which need `insertTextFormat` and are
      absent entirely; and module-path completion inside a `require` string.
- [ ] **Cancellation, stale results and multi-root.** `$/cancelRequest` is
      registered as a no-op (`src/nupp/lsp/init.nupp:868`), so it is understood
      only in the sense of not erroring; cancelling work in flight needs input
      readable without blocking, which this loop does not have. Graceful
      stale-request results need request-id tracking, which nothing does.
      Workspace folders are read and re-root correctly but collapse into one
      session, so real multi-root remains — see
      [plan.md](plan.md#lsp-follow-up).
- [ ] **Doc comments as checked grammar.** `@param` parses
      (`src/nupp/docblock.nupp:23`) and renders, but nothing verifies the names
      against the real parameter list — `@raises` is the only tag any checker
      reads. `[[Type]]` cross-references do not exist as syntax yet.
- [ ] **Docgen JSON output mode.** Static HTML landed (`nupp doc site`,
      `src/nupp/doc/html.nupp`). What external site generators need is a
      doc-model JSON emitter; `--format json` today is only the CLI's own
      report shape, which `src/nupp/cli/doc.nupp:43` says outright.
- [ ] **`nupp doc` never removes what it stopped writing.** A module build
      records its outputs and deletes the ones a later build did not produce
      (`src/nupp/build/project.nupp:202`); the docs target returns at line 93,
      before any of that runs. So a page keeps its rendered HTML after its
      route changes or its source is deleted. Restructuring this site left a
      whole `build/docs/guide/` tree behind, still serving pages whose links
      pointed at files that had moved — a link checker run over the output
      found them and they looked real, which is worse than a 404. The list is
      already in hand: `doc.files.collect` (`src/nupp/doc/files.nupp:20`)
      records every written path for `--json`. The docs path needs to store it
      and remove the difference.

## Build, codegen and distribution

- [ ] **`--gen-target` guardrails for struct modules** (plan §4: no silent
      erasure). No such flag exists yet; the only target flag is the manifest's
      `--target`.
- [ ] **`nupp doc` picks between two docs targets by hash order.** With no
      top-level `docs` table, `manifestSettings` returns the first
      `kind = "docs"` target `pairs()` reaches
      (`src/nupp/doc/init.nupp:392`), and `pairs()` does not promise an order.
      Two targets named `alpha` and `zulu` sent five consecutive runs to
      `out-zulu`, `out-alpha`, `out-zulu`, `out-alpha`, `out-alpha`. The
      command has no `--target`, so there is no way to say which was meant
      either. Either sort and take the first, prefer `build.default` when it
      names a docs target, or refuse and ask — but not this.
- [ ] **An unknown key in most of the manifest is still ignored.** Closed key
      sets cover the docs target, its pages, hero actions, features, and
      `config.fmt` (`src/nupp/build/manifest.nupp:75,97,228`). Everywhere else
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
      implemented (`src/nupp/build/package.nupp:154`, `host/src/payload.rs`).
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
      fired (`src/nupp/check/pragma.nupp:226`).
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
headers are stored between commands (`nupp.build.store`, plain data via
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
      (`src/nupp/env.nupp:95`, `src/nupp/fs.nupp:85`), and `bin/nupp` spawns
      about four more before it execs. `process.capture` also creates and
      removes an `os.tmpname` file per call. `nupp.fs` shells out because Lua
      has no directory API and the FFI would need one implementation per
      platform; that reasoning still holds, but the price is now most of what a
      warm command costs. Memoizing per environment removes the duplicates —
      except that an editor session lives for hours and files appear in it, so
      the memo needs an invalidation story before it is safe.
- [ ] **`nupp check FILE` has no per-module reuse at all.**
      `src/nupp/cli/check.nupp:76` re-parses and re-checks the named file
      unconditionally; only the header index is cached. The 0.14 s figure is
      the startup-plus-index floor measured on a small file — `src/nupp/env.nupp`
      costs 0.82–0.93 s on every warm run. This is the largest single number
      left and the one an editor hits most.
- [ ] **Cross-process cutoff is at the module, not the interface.** A body edit
      stops at an unchanged interface, because the interface digest is recorded
      and compared. But any edit to an exported *type declaration* changes
      `projectIndexHash`, which disables reuse for the whole project: the digest
      covers each declaration's `cst.textOf` (`src/nupp/env.nupp:299`), which
      emits leading trivia, so reformatting a docblock above a record rechecks
      everything. The other half of the same mechanism is `typeFingerprint`,
      which describes a nominal by its declaration kind and name and
      deliberately does not expand members (`src/nupp/build/modules.nupp:37`) —
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
      (`src/nupp/build/store.nupp:35`) bounds the cold entries, which is fine
      for a project this size and unmeasured for a large one.

## Testing and CI

- [ ] **Complete the operator-contract matrix.** Only `__add` has a direct
      contract test (`tests/checktest.lua:200`); no test anywhere mentions
      `__unm`, `__sub`, `__mul`, `__div`, `__mod`, `__pow`, `__lt`, `__le`,
      `__concat` or `__eq` dispatch. The table under test is
      `operators.metamethod`/`contractMetamethod`
      (`src/nupp/check/operators.nupp:45`). Needed: unary minus, subtraction,
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
- [x] **Permute the passes and compare behaviour, not output.**
      `tests/passpermutationtest.lua`. Every subset of the `OPT-n` passes is
      built and run, and all of them have to agree on the answer. The subsets
      come from `optimize.passes` rather than a list in the test, so a pass
      added tomorrow is swept the day it lands, and `everyPassIsInTheSweep`
      fails if the registry and the sweep ever disagree.

      Exhaustive while the subset count stays under 256, singles-and-pairs
      beyond that, and the mode is named in every failure so a sweep that
      stopped being exhaustive cannot read like one that still is.

      Verified against the bug that motivated it: with the OPT-2 branch's
      concat finish removed, the sweep fails and names `OPT-2+OPT-5`, while the
      54-test optimizer suite passes. Two hundred milliseconds for the whole
      sweep.

      Left open: the programs are hand-written, so coverage is only as good as
      they are. The generated corpus above is what makes this worth much beyond
      the shapes someone thought to write down.
- [ ] **A segfault in `luajit tests/run.lua`, seen once, not reproduced.**
      `Segmentation fault: 11` partway through a full run, on the run that
      followed a compiler rebuild; four full runs and six of `profiletest`
      immediately afterwards were clean, and `fixpoint` passed. Recorded rather
      than chased because a crash in the suite is worth a note even without a
      reproduction, and because the entry below already says trace-timing makes
      one test non-deterministic — the same machinery is the first place to
      look. If it recurs, run under `MallocStackLogging` or a LuaJIT built with
      assertions rather than re-running the suite.
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

- [ ] Focused fixtures cover tecs-style nested event records, bounded
      registration, late `__call` installation, generic `__index`/`__newindex`,
      and arithmetic contracts (`tests/gentest.lua:84`,
      `tests/checktest.lua:163,191`). No tecs source file has been translated;
      `FFIStorage` appears only in these plans. Translating and running the
      real files remains the gate.
