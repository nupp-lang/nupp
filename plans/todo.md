# Nupp TODO

## Tier 2 — hit in the first week

- [x] **Generic nominal instantiation.** Parameters are in scope for the
      body, arguments substitute into fields, construction infers the
      argument, applications vary covariantly, and `<T is Bound>` is enforced
      at explicit and inferred call sites.
- [x] **Interface conformance and declared inclusion.** Undeclared
      satisfaction remains structural. `record X is Interface` is a trusted
      nominal contract claim, supports multiple parents, imports fields and
      metamethod contracts, and rebinds the parent's `self` to the child.
- [x] **Metamethod contracts and inline methods.** Bodyless, erased
      `metamethod __name: function(...)` declarations type calls, indexing,
      assignment, arithmetic, concatenation, length, and comparison. Runtime
      fulfillment remains ordinary Lua. Inline ordinary methods use
      `function name(...) ... end`; nested nominal namespaces lower to nested
      runtime values. See [metamethods.md](../docs/metamethods.md).
- [ ] **Protocol-contract follow-ups.** The syntax and primary tecs use cases
      are landed; the remaining checks are deliberately visible:
  - [ ] enforce parsed `where` predicates rather than only preserving,
        formatting, documenting, and highlighting them
  - [ ] validate the value types in a direct `metatable<T>` literal against
        `T`'s declared contracts, not only unknown `__` key spellings
  - [ ] model metatable contents through a bounded generic receiver so a
        registrar such as `newEvent<E is Event>` checks its own metatable body
        instead of relying on checked concrete call sites
- [x] **Literal types + discriminant narrowing.** String and number
      literal types, writable in annotations (`tag: 'circle'`);
      narrowing through field paths and over unions of shapes by their
      discriminant; a field common to every member reads as the union of
      its types.
- [x] **Enum construction** without casts; the error names the value and
      the enum.
- [x] **Enum exhaustiveness** (NUPP2107). Reported where the code itself
      claims totality: a chain dispatching on one enum-valued subject that
      leaves through every branch — returns or raises — and has no `else`.
      Partial handling, an `else`, and chains over more than one subject
      are all left alone, so there is no guessing. The missing members are
      named. Comparisons also subtract members from the value in later
      branches, which is what makes the residual computable.
- [x] **`??` nil-coalescing** (LuaJIT 3.0; especially apt given
      NULL-vs-nil semantics), **`??=`** (a Nupp extension: LuaJIT lists it
      among the ones it declined) and **compound assignment**
      (`+= -= *= /= //= %= &= |= ~= <<= >>= ~>>= ..=`), `~=` reading as
      exclusive-or assignment in statement position and as inequality
      everywhere else.
- [x] **`--strict` mode.** Unknown names are errors (NUPP2105), and a
      module's exports must be typed (NUPP2106).

## Tier 3 — deliberate roadmap (plan §6 M5–M7)

- [x] **Reified typed arrays.** `T[?]` (variable-length) and `T[N]`
      (fixed) of a reified struct are contiguous FFI arrays: allocation,
      zero-based element access, element typing, and a per-element-type
      ctype cache. bench/aos.nupp measures 6–9x over the same loop written
      with tables, from Nupp source rather than hand-written Lua, so the
      generated code now matches or beats the original spike. A C array is
      deliberately its own type rather than `{T}`, since it is zero-based
      and a Lua array is not.
- [x] **Affine ownership and explicit scopes.** `takes` parameters,
      intra-function use-after-move/double-consumption detection, ownership
      transfer, borrows, pins, cleanup obligations, and protected `with`
      scopes are landed. Parameter-effect inference, default `@dispose`
      contracts, multi-root result provenance, affine records, C owned and
      borrowed outputs, unsafe raw-pointer use, and suspension checks are also
      implemented. Remaining lifetime work is tracked in the dedicated FFI
      and resource-scope sections below.
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
- [x] **LSP editor baseline:** hover, completion, signature help,
      references, rename, semantic tokens, formatting, and configurable
      VS Code server launch.
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
  - [x] query-owned, overlay-aware declaration/module index with stable nominal
        identities
  - [x] dependent open-file rechecks and diagnostic republication on export
        changes
  - [x] unopened-file references/rename: both run over the project, filtered
        by which files spell the name; a symbol the project does not declare
        is refused rather than half-renamed
  - [x] watched-file notifications invalidate disk-backed queries and refresh
        diagnostics for open dependents
  - [x] workspace-folder changes and watched-file conformance tests. The
        folders a session searches now follow the client: `initialize` adopts
        the ones it opened, `workspace/didChangeWorkspaceFolders` adds and drops
        them, and each brings the include paths its own `nupp.lua` declares —
        a folder whose sources sit under `src` is unreadable without them.
        A folder change rebuilds the query graph rather than patching it, hands
        the open buffers back as overlays, and republishes unconditionally,
        since a file can be clean under one set of folders and not another.
        Everything else still comes from the launch root: lint levels and
        language mode redeciding themselves per folder would mean the same file
        checked differently depending on which window opened it. Real multi-root
        isolation — one project per folder rather than one search path across
        them — stays open under protocol hardening.
        Conformance tests drive a live server over a pipe rather than a
        prewritten script, because what a notification did is only visible if
        the server was partway through when the world changed: a file created,
        changed and deleted underneath an open buffer, and events for files the
        project has nothing to do with.
  - [x] plain `function m.f` module members reach across files. Nothing types
        the table a file returns — that is what lets an untyped module keep
        working — so a member has no interned declaration and no type a
        definition could hang from. The question is answered syntactically
        instead, per request rather than indexed: which module a name holds is
        recorded on that name's definition when it was bound to a `require`,
        and a file's own module local is the table its own members sit on.
        Definition, references and rename run over the whole project on that
        basis, and hover shows the declaration line as written, there being no
        type to render. Keeping it out of the project header is deliberate: a
        member's offset moves whenever a body above it does, and putting that in
        the interface would make every keystroke recheck every dependent.
- [x] **Codegen passthrough.** ~~Hoist safe-nav/ternary IIFEs to
      statement-level temps~~ — there are no IIFEs left to hoist. LuaJIT 2.1
      backported the syntax, so `?:`, `?.`, `??`, the bit operators, compound
      assignment, `continue`, `const` and short functions are written out as
      read, and only what 2.1 did not take is lowered: `//`, `//=`, the named
      vararg, plus Nupp's own `??=` and interpolated strings. This also fixed
      `a?.b = 1`, which the old lowering emitted as a call on the left of an
      assignment.
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
- [x] **Compile-time header typing** (`cheader`): LuaJIT parses the
      pinned header, `ffi.typeinfo` supplies the types. Follow-ups: a
      `prelude` option for headers that reference an include's types
      (e.g. `lua_State`), struct types usable as annotations (`m.Point`),
      and wiring the preprocess path into the build manifest with
      query-engine caching.
- [ ] **import-c hardening:** ~~typedef handling~~, ~~`from "lib"`
      clauses with `ffi.load`~~, ~~const byte pointers as `cstring`~~
      (landed; zlib.h imports and calls correctly). Remaining: macOS
      asm-rename/attribute sweep on more real headers, ~~function-pointer
      params as typed callbacks~~ (landed through the shared header model),
      ~~struct-by-value arguments~~, enums as constants.

## Testing strategy

Standing invariants (every checker/parser change re-verifies):

- [x] **Superset/gradualness oracle:** a large corpus of real-world
      untyped Lua (1.3MB+) must parse with 0 errors, byte-exact CST
      round-trip, and check with **0 diagnostics** under the full stdlib
      env. This caught 4 idiom classes already; keep it sacred. → CI.
- [x] **Byte round-trip on garbage:** parser never drops a token
      (arbitrary-input round-trip tests).
- [x] **Line-count invariant:** generated Lua never changes line count;
      runtime tracebacks point at `.nupp` lines (golden + by-hand test).
- [x] **Execution semantics:** every lowering has behavior tests
      (ternary falsy/lazy, safe-nav single-eval, istring escapes,
      `-7 // 2`, arshift, real libc calls, struct float32 rounding).
- [x] **Incrementality by compute counters,** not wall clock: body edit
      rechecks 1 file; interface edit propagates. Extend when nominal
      identity stabilizes and when comptime lands (evaluator-result cache).

To add:

- [x] **Build staleness suite:** counters prove warm builds check and generate
      nothing, body edits stop at unchanged interfaces, interface edits reach
      dependents, header edits regenerate bindings, and corrupt state falls
      back to a cold build.
- [x] The superset oracle runs in the suite (tests/corpustest.lua):
      real-world untyped Lua must parse clean, round-trip byte for byte,
      and check clean, plus fast regression cases for every contextual
      declaration keyword.
- [x] Runtime-protocol coverage includes valid and invalid primitive
      operators, callable records, generic indexing and assignment, addition,
      concatenation, length, bounded contracts, nested runtime records, inline
      record/struct methods, literal metatable typo detection, and tecs-style
      late event registration.
- [ ] Complete the operator-contract matrix with direct tests for unary minus,
      subtraction, multiplication, division, modulo, power, right-hand
      fallback, and comparison reversal/`__lt` fallback for `<=`.
- [ ] **CI matrix** (GitHub Actions): macOS + Linux, LuaJIT 2.1 rolling
      (2.1.1784535649 is the floor) + (when released) 3.0; run
      `./tests/run`, the tl.lua oracle, and
      import-c fixture tests; track `bench/reification.lua` and
      `bench/aos.nupp` numbers as an artifact per commit (regression fence
      around the reification speedup).
- [x] **Grammar conformance.** Every LuaJIT#1475 feature is implemented and
      covered: bit operators, customary operators, floor division, `?:`, `?.`
      in all ten of its spellings, `??`, compound assignment including `~=`,
      `continue`, `const`, short functions, named varargs, and numeral
      underscores. There is no feature gate to validate, because there is no
      feature to gate.
- [ ] **Fuzzing:** grow the random-input corpus for lexer/parser
      round-trip and fmt idempotency (`fmt∘fmt = fmt`,
      `parse∘fmt = parse`); minimize and check in failures as regression
      fixtures.
- [x] **LSP session replays.** A recording in `tests/lspsessions/` is one
      session an editor could have produced: a project, the documents that were
      open, and the buffer states one of them passed through as somebody typed
      into it — mostly states that do not parse, which is what a line being
      written looks like. Each is replayed against a real server and compared
      against a second server handed only the final text. That comparison is
      what convergence means: a burst has to leave the session where one edit
      would have, or what an editor shows depends on how fast the user types.
      Four are recorded — an annotation typed a keystroke at a time, a require
      added after its use, an export renamed while a dependent is open, and a
      file deleted back to empty and retyped — and a recording that never
      breaks anything, or whose probe resolves to nothing even at rest, fails
      rather than passing vacuously.
- [x] **Checker error-message goldens:** snapshot NUPP diagnostics
      (code + message) for a curated bad-code corpus so message quality
      is reviewed in diffs, not discovered by users.

## FFI in the type system

- [x] `T[?]` / `T[N]` C array types; `nil` restricted to nullable
      pointers; imported C pointers nullable; cheader cache keyed on ABI
      and toolchain.
- [x] `ctype<T>`, and `ffi.new/cast/typeof/sizeof/alignof/istype/gc` as
      intrinsics with return types that follow their type argument;
      `ffi.istype<T>` participates in narrowing.
- [x] Interpret constant type strings, and literal `ffi.cdef` blocks, so
      existing FFI code types without a rewrite. Dynamic strings yield
      `cdata`.
- [x] `const T*` modifier, carried through from imported headers.
- [x] `ffi.C` and `ffi.load` are typed from what the program has
      declared.
- [x] Share one LuaJIT-backed C declaration model between `cheader` and
      `import-c`; the importer retains only preprocessing, macro extraction,
      and editable-module rendering.
- [x] C function pointers decode as callback types, and variadic C
      functions are recorded as such.
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
- [x] Lossy integer narrowing under `--strict` (NUPP2503), and a pointer
      taken from a string *literal* is flagged (NUPP2501).
- [~] **String-pointer escape analysis.** String literals still receive the
      NUPP2501 lint. A pointer cast from a named string binding now becomes a
      lexical borrow: it cannot be returned, stored, or used after its source
      changes. Arbitrary string-valued expressions, aliases, and call results
      still need provenance propagation rather than collapsing to a raw
      pointer.
- [x] Dynamic FFI yields `cdata`, never a silent `any`.
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

## Bundled declarations

- [x] `string.buffer`, `cjson`, `cjson.safe` ship as bundled `.d.nupp`
      declarations; project files with the same module name shadow them.
      Coverage is checked against the installed library rather than
      memory (`cjson` matched 2.1.0.10 exactly).
- [x] `ffi` itself is declared, so the explicitly-machine-level cases
      (`ffi.string` on a returned `cstring`, casts, bulk copies) are typed.
- [ ] More of the ambient ecosystem as it comes up (`lfs`, `socket`,
      `posix`, OpenResty's `ngx.*`), same pattern: describe, verify
      against the real module, let projects shadow.

## Formatter follow-ups

- [x] Measure width in Unicode display columns, including zero-column
      combining marks and double-column East Asian characters.
- [x] Reflow standalone plain `--` comment runs with the same prose and
      verbatim-code rules as docblocks.
- [x] Break before `?`/`:` in over-long ternaries.

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

- [x] **Annotations are typed, extensible metadata.** Records and structs
      annotated with `@annotation` define their members and semantic target
      limits; `@annotationValue` selects a canonical single-value spelling.
      See [annotations.md](../docs/annotations.md). Undefined, misplaced,
      malformed, and reserved annotations are errors rather than silently
      erased markers.
- [x] Every diagnostic carries a severity: `note` and `warning` are reported
      and stepped over, `error` stops the build. A lint additionally carries
      `off`. See [lints.md](../docs/lints.md).
- [x] Lints are a registry separate from type errors — name, code, category,
      default level — so a level lives in one place and `nupp lints` cannot
      drift from what the checker does.
- [x] `@allow(LINT, ...)` silences named lints for the statement it decorates,
      and nothing beyond it, by name or by code; bare `@allow` silences every
      lint there. It reaches any level, a lint being a judgement. It does not
      reach a type error: naming one is NUPP2108 and the error still stands.
- [x] Project-wide configuration of lint levels in `nupp.lua`, by name or by
      category, validated so a typo is reported rather than ignored.
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
- [x] **A rename ran through string literals**, so four diagnostics named
      `c.result` — an expression in the checker, not a word in the reader's
      program. `diagnosticgoldentest` now reads the sources rather than the
      output, because a message nothing exercises drifts the same way.
- [x] **`jit-callback` (NUPP2502) raises.** It sat in the registry with no call
      site, so `nupp lints` listed a lint nobody could trigger. It reports
      inside `unsafe`, where casting a Lua function to a C callback is
      permitted and the thing left to say is that the callback stays registered
      and no trace compiles through it. Outside `unsafe` the error says enough.
- [x] **`notes` has a first user.** A cleanup is a bare name resolved where the
      owner is consumed, so a producer in another module naming a file-local
      disposer reported at the use site with nothing to go on. The note gives
      the rule the message cannot.

## Explicit resource scopes

- [x] Implement the [`with` design](with.md): generalize ownership to user
      values, consume owners into non-escaping resource scopes, preserve manual
      `dispose` and transfer, and lower one visible protected boundary per
      `with` rather than implicitly closing every owned local.
- [x] Support multiple left-to-right acquisitions, reverse resource cleanup,
      ordered per-owner cleanup lists, partial-acquisition unwind, and cleanup
      failure aggregation.
- [x] Type `LuaFile` and provide standard owning wrappers. A Closeable-style
      interface may opt in through `@dispose`; method names alone have no
      privilege.
- [x] Reject raw coroutine suspension with live temporal obligations; cover
      rejected capture, generated line counts, incremental ownership
      fingerprints, LSP metadata, and formatter output.
- [x] **A qualified function carries its type, and so its `@owned` contract.**
      `function m.f()` recorded nothing a later reference could read back, so
      `m.f` resolved through an open table as `any` and every annotation on it
      was accepted and then meant nothing — arguments and results went
      unchecked, and `@owned` created no obligation at all. It now records the
      path the equivalent `m.f = ...` assignment does. Found through `@owned`,
      but the silence was the whole module-table surface.
- [x] **A cleanup name is resolved where it was written, not where the owner is
      acquired.** A cleanup is usually local to the module declaring the owner,
      so an acquisition in another file could not see the name and was told
      NUPP2615 about a function it could neither reach nor fix. The declaration
      site validates the contract, which is where a misspelling is reported and
      repairable; an acquisition still has to be owned (NUPP2610) and still has
      to have cleanups (NUPP2611).

      That was half a fix and the wrong half. Suppressing the complaint let the
      program through to a generator that emits the cleanup *by name*, so it
      type-checked and then died on `attempt to call a nil value`. A
      compile-time refusal became a run-time crash, and the pattern was then
      copied to `dispose`. NUPP2620 below restores the refusal.
- [x] **A discharge refuses a cleanup it cannot call.** NUPP2620, at both `with`
      and `dispose`: a cleanup named by a bare name has to resolve where the
      discharge is written, because that is what gets emitted there. The forms
      that travel with the value — a `@dispose` method, a cleanup through a
      field — are never refused. This is a restriction standing in for the
      design below, not the answer to it.
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
- [x] **`nupp.std.*` is typed outside this tree.** Module resolution searched a
      project's `include` roots and `BUNDLED` in `env.nupp`, which registered
      `ffi`, `string.buffer`, `cjson`, `cjson.safe` and the `jit.*` submodules
      and nothing else, so `require("nupp.std.zone")` in a user project yielded
      `any`. The modules reach `package.preload` and so ran; what was missing
      was anything to check a call against — `zone.pushhh("x")` was silent,
      which the profiling guide teaches both of.

      Carried as source rather than described by a `.d.nupp` overlay. That was
      the idiomatic shape and it has a blocker: `@owned` targets `function`, and
      a declaration file spells its exports as typed bindings, so a cleanup
      contract has nowhere to attach — confirmed by writing one. Source also
      avoids keeping a second copy of a surface that already exists with nothing
      holding the two together, and keeps `close_file` private, which a
      declaration naming it as a cleanup could not.

      Loaded on demand rather than per environment. Checking all of them eagerly
      doubled a small project's check — 0.04s to 0.08s — for modules it never
      required, so `env.bundled` resolves through a metatable and a project that
      names none of them pays nothing. That covers the bundled declarations too,
      which were eager before this.
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

- [x] `where` is rejected rather than ignored. It parses, formats, and reaches
      a rendered signature, and no checker code reads the expression, so a
      declaration stating a constraint got none. NUPP2122 says so. Implementing
      it is still open, and would replace that diagnostic.
- [x] `nupp doc` answers in JSON and describes what it answers, which was the
      last command producing data without either.
- [x] Usage lines name `--format` wherever the command takes it.
- [x] `EDITOR_ADVICE` and `PROTOCOL_SEVERITY` exist once.
- [x] The Claude Code plugin README no longer claims `documentSymbol` and
      `workspaceSymbol` are unimplemented.
- [x] `docs/ownership-migration.md` is gone; the rename it described finished.
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
unchanged modules and replays their diagnostics, and bundled module
declarations are checked when something asks for one.

Measured on this compiler: whole-project check 2.10 s → 0.09 s warm,
1.29 s cold; no-op build 1.45 s → 0.11 s; one named file 0.36 s → 0.08 s;
`lsp inspect` 0.30 s → 0.08 s. The startup floor is 20 ms.

What is left, in the order the numbers justify:

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

- [x] Diagnostic fix-its as structured data (plan §5) — a diagnostic may
      carry `fixes`, each a title and a list of `{offset, length, newText}`
      edits over its own file. Carried by NUPP2101, NUPP2119 and NUPP2120.
- [x] Fix-its for NUPP2118 misspelled metamethods and NUPP2503 lossy
      narrowing.
- [x] Make NUPP2102/NUPP2104 colliding project globals and NUPP2611
      acquisitions actionable. Collisions carry every declaration as related
      information and cleanup failures explain the required contract. Neither
      offers an edit because choosing visibility or cleanup changes semantics.
- [ ] **`nupp doc` picks between two docs targets by hash order.** With no
      top-level `docs` table, `manifestSettings` takes the first `kind = "docs"`
      target `pairs()` reaches, and `pairs()` does not promise an order. Two
      targets named `alpha` and `zulu` sent five consecutive runs to
      `out-zulu`, `out-alpha`, `out-zulu`, `out-alpha`, `out-alpha`. The
      command has no `--target`, so there is no way to say which was meant
      either. Either sort and take the first, prefer `build.default` when it
      names a docs target, or refuse and ask — but not this.
- [x] A docs target's keys are a closed set, checked down through its pages,
      their hero actions and their features, and a key outside it is refused
      with the nearest one it might have meant. Most of what a docs target
      configures is read by the generator rather than by the build, so
      `custmCss` used to render the default theme and exit cleanly.
- [ ] An unknown key elsewhere in the manifest is still ignored. The docs
      target got a closed set because the generator reads keys the build's
      validation knows nothing about; the same argument is weaker everywhere
      else, but "this configures nothing" is worth saying wherever it is true.
- [x] `nupp tasks` reports `all` and `includePrivate` as themselves. It printed
      `Include private` for `all`, which takes in undocumented and `local`
      declarations, while the setting that label belongs to went unreported.
- [x] A docs target with no `outDir` is reported as the directory the generator
      will actually write to, which it asks the generator for rather than
      keeping a second copy of the answer. Worse than it read when it was
      written down: for `format = "markdown"` the output is `docs/api.md`,
      nowhere near the `build` the task table named, so `nupp clean` removed an
      unrelated directory and left the generated file behind. The site case was
      only ever right by containment.
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
