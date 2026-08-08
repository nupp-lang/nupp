# Nupp TODO

## Tier 2 — hit in the first week

- [ ] enforce parsed `where` predicates rather than only preserving, formatting, documenting, and highlighting them
- [ ] validate the value types in a direct `metatable<T>` literal against `T`'s declared contracts, not only unknown `__` key spellings
- [ ] model metatable contents through a bounded generic receiver so a registrar such as `newEvent<E is Event>` checks its own metatable body
      instead of relying on checked concrete call sites

## Tier 3 — deliberate roadmap (plan §6 M5–M7)

- [ ] **Read and write property capabilities.** Add member-level `read` and
      `write` views to shapes, interfaces, records, and their indexers. A
      read-only property is covariant and cannot be assigned through that
      view; a write-only property is contravariant and cannot be read. Permit
      the same property to declare distinct read and write types, with an
      ordinary read-write property remaining invariant. Keep this separate
      from `const T`, which makes a whole value read-only, and from
      `borrows`/`exclusive`, which govern lifetime and aliasing rather than member
      access. The first validation cases are declaration-file APIs, immutable
      snapshots, output-style interfaces, and the tecs `ByteView` surface.
- [ ] **`unknown` and a real `never` bottom type.** `unknown` is the safe top
      type: any value fits it, but it must be narrowed or explicitly cast
      before use; `any` remains the deliberate opt-out. Use `unknown` for
      genuinely untyped inputs such as JSON/reflection results and, under
      strict checking, plain Lua modules without declarations. Nupp currently
      has `@noreturn` control-flow tracking but no `never` type in the type
      lattice; add the bottom type for impossible branches, exhaustive
      narrowing, and generic cases such as `Result<T, never>`, then express
      noreturn results through it instead of a parallel special case where
      practical.
- [ ] **Intersection types, including overloads as function intersections.**
      Add `A & B` with normalization, subtyping, useful emptiness diagnostics,
      and member composition. An intersection of callable types is the
      overload set: a call selects a compatible signature and applies that
      signature's return, ownership, borrowing, and C-boundary effects. Do not
      add a second overload-only type construct unless intersections prove
      unable to give declaration files, the prelude, metamethods, and host APIs
      precise call surfaces.
- [ ] **First-class type packs and variadic generics.** Represent function
      parameters and results as value sequences rather than ordinary tuple
      types, with a fixed head and optional homogeneous or generic tail. Add
      generic pack binders such as `A...`/`R...` so forwarding functions
      preserve heterogeneous argument and result lists. Model Lua's exact
      expansion, truncation, last-expression, and parenthesized single-value
      rules in calls, assignments, and returns. Use packs to type `pcall`,
      `xpcall`, `select`, `unpack`, coroutine resume/yield, and generic
      adapters without collapsing to `any`; success/failure APIs need
      correlated unions of result packs. Every pack element retains its
      ownership mode and borrow provenance, and an affine result may not be
      silently truncated or discarded by generic forwarding.
- [ ] **`@jit` trace checker.** NYI analysis behind the pragma. (The
      variadic-FFI/callback `jit.off` lint is tracked under §FFI in the
      type system, where the marking it needs lives.)
- [ ] **Comptime** ([design](comptime.md)): deterministic data evaluation,
      deliberately not a macro or declaration-generation system.
  - [ ] C1: `comptime do ... end` expression blocks; compile-time-known
        literals and `const` bindings; capability-limited evaluation; canonical
        literal/table quoting; line-count-preserving generation; in-memory
        query caching and equal-result cutoff.
  - [ ] C2: target-aware `sizeof`/`alignof`/`offsetof`; immutable
        `reflect(T)` descriptors; semantic type fingerprints and module
        interface dependencies.
  - [ ] C3: file-private `@comptime` functions with ordinary type checking,
        erased runtime output, bounded recursion, and comptime call stacks.
  - [ ] C4: isolated evaluator worker, cancellation/resource limits, LSP
        hardening, and eventual manifest build-cache persistence.
- [ ] **M5 tooling completion:** ~~LSP project indexing~~,
      ~~contextual/member completion~~ (landed: after a `.` or `:` the answer is
      what that receiver holds and nothing else — a record's fields and methods,
      a required module's declarations and its plain `function m.f` members —
      and an annotation offers only what can stand where a type is expected.
      Types come from the last state of the file that checked, because a file
      being typed into does not parse for most of its life. Still ahead:
      lexical-scope filtering of the ambient list, C struct fields and imported
      declarations, callable snippets, and module-path completion),
      checked docs,
      ~~semantic-token deltas~~ (landed: `resultId`-keyed deltas one revision
      deep, an unknown revision answered in full rather than with an edit
      against nothing, and range requests encoded from the range because the
      protocol counts each token from the one before it),
      ~~minimal/range formatting~~ (landed: formatting answers with the runs of
      lines that changed rather than the whole document, and a range keeps the
      runs that fall inside it — a run reaching past the selection is a change
      the request did not ask for), ~~code actions~~
      (landed: quick fixes from checker fix-its, `with` wrap/unwrap
      refactorings), and
      protocol hardening (partly landed: document and workspace symbols,
      highlights, folding ranges and selection ranges from the CST, so they
      answer in a file that does not check yet, and `$/cancelRequest` is
      understood rather than merely ignored. Cancelling work in flight needs
      input readable without blocking, which this loop does not have; that,
      graceful stale-request results and real multi-root sessions remain —
      see [plan.md](plan.md#lsp-follow-up));
      doc comments as checked grammar
      (`@param` names verified, `[[Type]]` cross-refs resolved); docgen
      (static HTML plus a JSON output mode so external site generators
      can consume it); ~~width-aware formatter~~ (landed: 120/88, 4-space
      indent, one-arg-per-line, docblock reflow, safety bail; repo
      reformatted);
      **tecs subsystem port** (`internal/ffi/FFIStorage` + components) =
      the v0.1 acceptance test. Focused fixtures now cover tecs-style nested
      event records, bounded registration, late `__call` installation,
      generic `__index`/`__newindex`, and arithmetic contracts; translating
      and running the real files remains the gate.
- [ ] **Codegen polish:** `--gen-target` guardrails for struct
      modules (plan §4: no silent erasure).
- [ ] **M7:** ~~fixed arrays `T[N]`~~ (landed), struct unions/bitfields
      (tagged C union lowering), malloc-backed big arrays, `nupp-cargo`
      Rust helper, hot-reload typing.
- [ ] **Dialect interop / `import-tl`** (design in plan.md §Dialect
      interop): declaration reader (.d.tl subset → interned types, wired
      into module resolution); source translator CLI (eject model,
      visible residue comments, `any` fallbacks); build-system `.tl`
      input mode for mixed trees; runtime-equivalence verification
      against the tecs subsystem corpus.
  - [ ] translate metamethod declarations, `record X is Y`, bounded generics,
        nested type namespaces, and `self` directly into their landed nupp
        forms
  - [ ] preserve `where` with an explicit unchecked-residue marker until its
        predicates are enforced
  - [ ] expose macroexp-produced protocol declarations explicitly during
        translation; tecs's generated `DoubleArray.__len` must become a
        visible contract rather than being attributed to comptime
- [ ] **import-c hardening:** ~~typedef handling~~, ~~`from "lib"`
      clauses with `ffi.load`~~, ~~const byte pointers as `cstring`~~
      (landed; zlib.h imports and calls correctly), ~~function-pointer
      params as typed callbacks~~ (landed through the shared header model),
      ~~struct-by-value arguments~~, ~~enums as constants~~ (landed: members
      arrive as named `int32` constants, anonymous enums included, negatives
      read back through the C namespace because LuaJIT keeps the value where
      -1 means "no size"). Remaining: the real-header sweep, which was never
      about asm renames or attributes — those were already stripped. Two
      other things were stopping every system header, and both are fixed:
      typedefs were declared in sorted rather than source order, and one
      unusable link in that chain failed the whole import. What is left is
      visible now that headers parse:
  - [ ] a target LuaJIT rejects wholesale still produces nothing. `fcntl.h`
        fails on an incomplete type and loses the other declarations with it,
        where a per-statement parse would eject that one as a comment and keep
        the rest — the module's stated bargain everywhere else
  - [ ] declarations reached only through a private sibling header are
        invisible: macOS puts `strlen` in `_string.h`, so importing `string.h`
        correctly yields nothing. Whether to follow a `_`-prefixed sibling is a
        design call, not a bug
  - [ ] `#define` constants are read from the target file's own text, so
        `errno.h`, which defines `EPERM` in `sys/errno.h`, imports no
        constants at all — the same boundary question as above

## Testing

- [ ] Complete the operator-contract matrix with direct tests for unary minus,
      subtraction, multiplication, division, modulo, power, right-hand
      fallback, and comparison reversal/`__lt` fallback for `<=`.
- [ ] **CI matrix** (GitHub Actions): macOS + Linux, LuaJIT 2.1 rolling
      (2.1.1784535649 is the floor) + (when released) 3.0; run
      `./tests/run`, the tl.lua oracle, and
      import-c fixture tests; track `bench/reification.lua` and
      `bench/aos.nupp` numbers as an artifact per commit (regression fence
      around the reification speedup).
- [ ] **Fuzzing:** grow the random-input corpus for lexer/parser
      round-trip and fmt idempotency (`fmt∘fmt = fmt`,
      `parse∘fmt = parse`); minimize and check in failures as regression
      fixtures.

## FFI in the type system

- [ ] **The callback `jit.off` lint.** Passing a Lua function where C
      will call it creates an FFI callback, and a variadic FFI call or a
      callback that runs on a compiled trace corrupts or panics — but
      only past the trace threshold, so it survives every test that runs
      the path fewer than ~56 times. The check needs C-derived function
      types *marked*: our function types are structurally interned, so a
      C callback is today indistinguishable from an ordinary Lua
      function. Mark them where they are built (cdef signatures,
      `cheader` exports, C function pointers), then flag a Lua function
      reaching one without `jit.off`. This is the validation target's
      real production bug class, so it is worth the marking pass rather
      than a heuristic that guesses from argument shape.
- [~] **String-pointer escape analysis.** String literals still receive the
      NUPP2501 lint. A pointer cast from a named string binding now becomes a
      lexical borrow: it cannot be returned, stored, or used after its source
      changes. Arbitrary string-valued expressions, aliases, and call results
      still need provenance propagation rather than collapsing to a raw
      pointer.
- [ ] **Bounds-carrying spans, driven by the tecs buffer port.** Do not add a
      second byte-buffer runtime to Nupp: tecs already has the owned growable
      `Buffer`, retained immutable `ByteView`, and exclusive `WriteRange`.
      First express those APIs with Nupp ownership: owned/disposable buffers
      and views, consuming `commit`/`close`, a write range that prevents its
      source buffer from moving, closing, resizing, or detaching while live,
      and FFI pointers whose provenance is tied to the buffer/view/range.
      Then decide whether the repeated lower-level shape warrants a generic
      `span<T>`/`span<const T>` carrying pointer, runtime element count, and
      provenance. Safe indexing and slicing must check bounds; conversion to a
      raw pointer or unchecked bulk copy remains an explicit `unsafe`
      boundary. Use the real tecs compression, process-I/O, mapped-buffer, and
      pointer-plus-length APIs as the acceptance corpus.

## Formatter corpus (remaining golden cases)

Golden cases to collect in `tests/fmtcorpus/` — each is input + expected
under the PLAN formatter doctrine (120/88/4, one-arg-per-line), run
through idempotency and parse-stability in addition to exact match:

- [ ] Comment placement: leading, trailing, between `if`/`elseif` arms,
      inside table constructors, doc-comment blocks before declarations,
      comment-only files.
- [ ] Blank-line policy: around functions, between record fields, top of
      file, collapse of 3+ blank lines.
- [ ] Long lines: call-argument wrapping, chained method calls
      (`report:put(...):putf(...)`), long binary-op chains with mixed
      precedence, long ternaries (wrap at `?` and `:`), long union type
      annotations, long generic parameter lists.
- [ ] Tables: short tables inline vs multiline threshold, nested tables,
      mixed array/named fields, trailing separators, aligned vs
      non-aligned values (pick a doctrine and pin it).
- [ ] Typed layer: annotation colon spacing in every position (locals,
      params, returns, fields, shapes, maps), `T?`/`S*?` tightness,
      generics `<K, V>` and `<T is Bound>`, `record X is Y`, `where`,
      metamethod contracts, inline methods, function types with parenthesized
      multi-returns, and cdef blocks (C-name fields with underscores stay
      untouched).
- [ ] Short functions: pipe spacing, single-param form, `-> do` blocks,
      shortfn as call argument, nested/curried chains.
- [ ] Interpolated strings: `${expr}` tightness, multiline templates
      (never reflowed), nested templates, escapes.
- [ ] Statements: guard clauses on one line vs expanded, semicolon
      statements, labels/goto, numeric-for spacing.
- [ ] Pathological: deeply nested expressions at the wrap boundary,
      one-line whole programs, files with only comments/hashbang, CRLF
      input, unicode in strings and comments.
- [ ] Idempotency fuzz: formatter output of every corpus file re-enters
      the formatter unchanged; parse-stability against the token-kind
      fingerprint.

## Diagnostics

- [ ] **`@deprecated` API metadata.** Allow functions, methods, fields, types,
      and module members to name an optional reason and replacement. Report a
      suppressible use-site lint; carry the metadata through module
      interfaces; expose the LSP `deprecated` tag/modifier in completion,
      hover, and semantic tokens; and render it in generated documentation.
      The annotation affects tooling only and emits no runtime behavior.
- [ ] Grow the registry: the `style` and `pedantic` categories have no members
      yet, so `nupp lints` is shorter than the idea is. `pedantic` currently has
      none at all, so setting it in `nupp.lua` moves nothing.
- [ ] Report an `@allow` that silenced nothing, so stale suppressions get
      removed rather than accumulating.
- [ ] **Grow the worked examples in `explain.nupp`.** Seven codes carry a
      `wrong`/`right` pair; every other code answers through its family, which
      states the rule but cannot show the mistake. Two things now lean on that
      table: `nupp explain` is the retrieval path a reader reaches from a
      diagnostic's `docs` anchor, and `nupp reference` lists the codes an
      example can say more about. Both get better per entry added, and
      `tests/explaintest.lua` already compiles each pair, so an entry cannot be
      added wrongly. The eleven the reference cites and cannot yet expand are
      NUPP2002, NUPP2101, NUPP2108, NUPP2118, NUPP2120, NUPP2203, NUPP2504,
      NUPP2506, NUPP2603, NUPP2610 and NUPP2615: a reader is pointed at those
      having just met the construct, so they are worth the most per entry.

## Explicit resource scopes

- [ ] **A cleanup is a spelling, not a resolved reference.** `Type.cleanups` is
      `{string}`, so every reader re-resolves it in its own scope: the checker
      through `lookupVar`, the generator as a bare identifier. They agree only
      inside the declaring module, which is why letting an owner cross produced
      a program that checked clean and crashed. It is a linking problem wearing
      a codegen costume — source spellings written into object files and
      resolved again at each use.

      Resolve it once, at the declaration, and store what it resolved to. The
      generator already emits two such forms: `@method:` calls through the
      owner, `@field|` through one of its fields. Both travel with the value and
      cross boundaries free. The missing third is a free function, which needs
      to name where it lives.

      Prefer a registry over an exported path. A module-qualified reference
      would work, but forces the cleanup public — and a cleanup is the other
      half of a contract, not surface anyone should call. Instead let the
      declaring module register the function object under a key it already owns,
      and let a consumer hoist one lookup at load:

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

      Landing this removes the NUPP2620 restriction, removes the `allowUnknown`
      suppression at both discharge sites, and unblocks the standard library
      item below. `@dispose` should still be the documented default for a type
      you define; the free-function form is for foreign types — `LuaFile`, C
      pointers, cdata — that cannot carry a method.
- [ ] **`@dispose` on a record method double-registers when the module is
      reached through a consumer.** `check` and `build` disagree:

          $ nupp check --strict main.nupp     # clean
          $ nupp run main.nupp
          res.nupp:12:2: error: NUPP2602: bare @owned has multiple inherited
          @dispose operations; choose one with @owned(cleanup)

      There is exactly one `@dispose`. The build path appears to check the
      declaring module a second time and append again to the same nominal's
      `defaultDisposers`, so the count reaches two. Two things make this worth
      doing early: a diagnostic that only appears on one of two commands is the
      kind nobody trusts, and `@dispose` is the repair NUPP2620 tells people to
      reach for, so it has to work across modules before that advice is honest.
- [ ] **A cleanup takes the owner and nothing else.** `@owned(cleanup)` emits
      `cleanup(owner)`, so a cleanup needing context — an allocator, an arena, a
      parent handle, `ctx_free(ctx, ptr)` — has nowhere to put it. Capturing the
      context would mean a closure per owner, which is the allocation this model
      exists to avoid. Real in FFI and unaddressed; worth a design before
      someone hits it, and independent of the reference question above.
- [ ] **A standard-library owner cannot be discharged yet.** Its wrappers return
      owners whose cleanups are module-local free functions, so acquiring one
      reports NUPP2620 — the contract crosses, and there is no way to name the
      cleanup from the acquiring module. `LuaFile` is a builtin, so the
      `@dispose` repair is not open to it either.

      Everything short of discharge works: arguments and results are checked,
      and an owner that is never discharged is still NUPP2603. This clears when
      a cleanup becomes a resolved reference, above; there is nothing separate
      to do here. `with.md`, the README and the tour all teach a locally
      declared producer, so no page depends on it.

## Documentation

The site was restructured into Getting started, Type system, Tooling,
Reference and the generated API. What that pass turned up:

- [ ] **The tree is not `fmt`-clean, and it is not obvious which side is
      wrong.** `nupp fmt --check` lists 101 of 109 sources, almost entirely
      single-line `if ... then return end`, which the compiler is written in
      throughout and which the formatter breaks across lines by a rule its own
      source calls deliberate. So either the house style or the rule has to
      give, and it is a taste decision rather than a defect.

      Reformatting is not a free mechanical pass, which is the part worth
      knowing before starting: generated Lua preserves the source line count,
      so moving a statement to a new line changes every artifact the compiler
      emits, which changes the compiler's own build, which means
      `fixpoint --update-bootstrap` and a new tracked `bootstrap/nupp.lua` in
      the same commit. Until it is settled, `nupp fmt` cannot gate this
      repository.
- [ ] **`nupp doc` never removes what it stopped writing.** A module build
      records its outputs and deletes the ones a later build did not produce; a
      docs build returns before any of that runs, so a page keeps its rendered
      HTML after its route changes or its source is deleted. Restructuring this
      site left a whole `build/docs/guide/` tree behind, still serving pages
      whose links pointed at files that had moved — a link checker run over the
      output found them and they looked real.

      A reader who lands on an old URL gets a stale page rather than a 404,
      which is worse than either. `nupp build` already has the machinery: the
      docs path needs to record what it wrote and remove the difference, and
      `doc.build` now collects its written paths for `--json`, so the list is
      already in hand.

## Incrementality across commands

Landed: cache keys are digested with XXH64 rather than a pure-Lua SHA-256,
the prelude no longer builds the project index on the way to every command,
project headers are stored between commands (`nupp.build.store`, plain data
via `string.buffer`, in the gitignored build directory), `nupp check` reuses
unchanged modules and replays their diagnostics, bundled module declarations
are checked when something asks for one, `nupp fmt` stores each file's
formatting verdict, the editor session writes what it worked out on shutdown,
and the project scan prunes dot-directories instead of walking the whole
checkout and discarding it.

Measured on this compiler, warm against cold: whole-project check 0.15 s
against 1.26 s; `fmt --check` 0.13 s against 1.99 s; no-op build 0.17 s;
one named file 0.14 s; `lsp inspect` 0.14 s. The startup floor is 20 ms.

What is left, in the order the numbers justify:

- [ ] **Five subprocesses per command, about 75 ms of the remaining 130.**
      A warm check is 20 ms of interpreter start, about 45 ms of actual work,
      and five `find` invocations. `nupp.fs` shells out because Lua has no
      directory API and the FFI would need one implementation per platform;
      that reasoning still holds, but the price is now most of what a warm
      command costs. Two of the five are the same listing asked for twice,
      which memoizing per environment would remove -- except that an editor
      session lives for hours and files appear in it, so the memo needs an
      invalidation story before it is safe.
- [ ] **`fmt --check` says 103 of this project's ~110 files are not
      formatted.** Unrelated to caching and worth knowing on its own: the
      formatter and the committed source disagree almost everywhere, so
      `fmt --check` cannot be used as a gate here until somebody decides
      which is right.

- [ ] **The prelude image, if 11 ms is worth it.** `env.new` is 11.7 ms and
      all of it is parsing and checking `prelude.d.nupp`, on every command.
      Storing the result means storing a cyclic type graph, which
      `string.buffer.encode` cannot do — it rejects cycles and does not
      preserve sharing — so it needs a codec that assigns object ids and
      rebuilds by reference. The delicate part is not the codec but
      `types.nupp`'s arena: every structural type is interned under its
      canonical `id`, and a restored graph has to be rewritten to whatever
      the arena already holds before anything compares two types by
      identity. Get that wrong and the interface cutoff either stops cutting
      off or starts cutting off things that differ. Eleven milliseconds
      against the most identity-sensitive machinery in the compiler is a bad
      trade today; it becomes a good one if the floor drops further or the
      graph grows.
- [ ] **Cross-process cutoff is at the module, not the interface.** A body
      edit stops at an unchanged interface, because the interface digest is
      recorded and compared. But any edit to an exported *type declaration*
      changes `projectIndexHash`, which disables reuse for the whole project
      — the digest covers every declaration's source text, so reformatting a
      docblock above a record rechecks everything. Narrowing it to the parts
      of a header a dependent can actually observe would make type edits
      incremental too.
- [ ] **`typeFingerprint` describes a nominal by its declaration.** That is
      correct — a nominal is its declaration site — but it means the
      interface digest leans entirely on `projectIndexHash` to notice a
      changed record. The two should be one mechanism rather than two that
      happen to cover each other.
- [ ] **The store never shrinks below what a run touched.** `KEEP_COLD`
      bounds the cold entries at 2048, which is fine for a project this size
      and unmeasured for a large one.
- [ ] **The parser accepts statements after a top-level `return`.** Found
      while writing cache tests: appending `local function f() end` after
      `return m` parses clean and checks clean, where Lua rejects it. Either
      a deliberate superset choice that is undocumented, or a gap.
- [ ] **`tests/profiletest.lua traceRecordsWhereTheCompilerGaveUp` is
      flaky.** Observed failing once in six runs with "unrecordable bytecode
      must be reported"; it depends on the JIT attempting and aborting a
      trace within 3000 iterations after `jit.flush()`. Unrelated to
      caching, but it will keep costing somebody a bisect.

## Housekeeping

- [ ] **`nupp doc` picks between two docs targets by hash order.** With no
      top-level `docs` table, `manifestSettings` takes the first `kind = "docs"`
      target `pairs()` reaches, and `pairs()` does not promise an order. Two
      targets named `alpha` and `zulu` sent five consecutive runs to
      `out-zulu`, `out-alpha`, `out-zulu`, `out-alpha`, `out-alpha`. The
      command has no `--target`, so there is no way to say which was meant
      either. Either sort and take the first, prefer `build.default` when it
      names a docs target, or refuse and ask — but not this.
- [ ] An unknown key elsewhere in the manifest is still ignored. The docs
      target got a closed set because the generator reads keys the build's
      validation knows nothing about; the same argument is weaker everywhere
      else, but "this configures nothing" is worth saying wherever it is true.
- [ ] `nupp.lua` project config: honor `syntax` and `runtimeTarget` fields end
      to end. `strict` is consumed by builds, direct checks, the incremental
      checker, and LSP sessions; the remaining language-mode fields are
      unimplemented.
- [ ] **Single-binary host:** vendor pinned LuaJIT and OpenResty
      lua-cjson sources in the Rust host (plan.md §Distribution) once the
      toolchain surface stabilizes; releases require neither system
      LuaJIT nor a C-module search path.
  - [ ] register `cjson` and `cjson.safe` in `package.preload`
  - [ ] configure strict JSON numbers and preserve explicit empty
        array/object semantics
  - [ ] malformed-input fuzzing and framed LSP replay
  - [ ] ship pinned revision metadata and MIT license notices
  - [ ] binary emitter: embed the app bundle into per-platform runtime
        stubs (host + vendored LuaJIT); target list in the manifest;
        cross-build = stub selection
