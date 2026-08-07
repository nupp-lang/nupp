# Nupp TODO

Status backdrop: M0–M4 complete, including reification end to end
(structs and C arrays), the incremental query core, self-hosting with a
tracked bootstrap, manifest-driven builds, and the FFI type-system work.
Trusted metamethod contracts, declared interface inclusion, upper-bounded
generics, declaration-scoped `self`, nested type namespaces, and inline
record/struct methods are also landed. This file tracks what remains, ordered
by how quickly a real user hits the gap. Milestone references are to
[plan.md](plan.md).

## P0 — self-hosting  ✅ untyped stage done

- [x] Compiler sources are `.nupp` (src/nupp holds nothing else);
      generated `.lua` live in the gitignored build/nupp; two-stage
      fixpoint verified (`nupp fixpoint`).
- [x] Fresh checkouts bootstrap offline from a tracked `bootstrap/nupp.lua`
      compiler bundle; `nupp fixpoint --update-bootstrap` refreshes it.
- [~] **Type the compiler** (M6, continuous): annotate modules as the
      features they need land. `cst`, `lexer`, `types`, `relations`, `query`,
      `incremental`, `parser` and `check` are typed, the CST vocabulary is
      per-kind, and the checker's dispatch core is annotated. `gen`, `fmt`,
      `lsp`, `doc` and the build modules still walk the tree gradually.
  - [x] `cst` and `lexer`, with docblocks. Typing them needed four things
        the type system did not have, all now landed and tested in
        `tests/selfhosttest.lua`: an array part on a record (`{T}` among
        the fields, which is what a CST node's children are), predicate
        return types (`x is T`, [CS-13]), nil-admitting shape fields being
        optional rather than required, and `integer` surviving a copy into
        an inferred local. It also turned up three defects: `is` on a
        record had no runtime identity, a multi-return annotation left its
        separating comma in the generated Lua, and a require cycle crashed
        the module queries instead of degrading.
  - [x] `types` and `relations`, with docblocks. `Type` is now declared:
        a tagged union written as one record, where `tag` decides which
        payload carries meaning. Two fields had to be renamed first,
        because one name meant two things: a nominal's `fields` map is now
        `byname` (matching what a shape already called it), and a literal's
        Lua value is now `constant`, freeing `value` for a map's value
        type. Six checker gaps fell out, all fixed and tested: assignment
        did not narrow, truthiness did not narrow a field path, a union
        could not be indexed (so `xs or {}` was unusable), a string-keyed
        table literal did not fit `{[string]: V}`, a module alias
        (`local T = require("m")`) could not name a type, and a numeric
        `for` over `math.min` lost its integer bound.
  - [x] `query` and `incremental`, with docblocks. `Q` is a record rather
        than a hand-rolled metatable, and the payloads crossing between
        them are declared: `Dep`, `Memo`, `CheckResult`, `Header`. Two
        gaps: a method could not be named before it was defined, and
        writing nil to a container entry was rejected though that is how
        Lua removes one. It also caught a regression in the assignment
        narrowing above, which was applied before the assignment was
        checked and so compared a target against the value being written
        to it — every assignment through a field or element passed.
  - [x] `parser`, with docblocks, and the CST vocabulary it writes. Every
        named field a node can carry is declared on `cst.Node`: what it
        means, and whether it holds a node, a token, or a list of either.
        Generic applications now use `typeArgs`, and the two meanings of
        `namedVararg` were separated. A call and an annotation still share
        `args`; that final split is tracked below. `cst.add` is generic, so a
        named field keeps its own type instead of widening to the union; that
        turned up subtraction erasing type parameters, since an unsubstituted
        one fits everything.
  - [x] `check`: its declarations (`Diagnostic`, `Facts`), its leaf functions
        and its dispatch core — `infer`, `checkStat`, `resolveType`,
        `checkBlock` — are typed against the per-kind vocabulary below. The
        migration turned up dead code (a cast branch keyed on a node kind that
        does not exist) and the `and`-chain narrowing gap below, which it
        prompted and which is now fixed.
  - [x] Narrowing reaches an aliased discriminant. `local kind = n.kind`
        then `if kind == "ifStat"` now narrows `n`, which is how every
        dispatch loop in the compiler is written. The alias is dropped as
        soon as the copy or anything it came from is assigned.
  - [x] A named field keeps a string literal, so a value of a
        discriminated union can be built at all. Numbers still widen: a
        counter initialized to 1 is not a value of the type 1. The general
        answer is checking a table constructor against an expected type;
        this is the part of it that was in the way.
  - [x] Declarations are hoisted. Every type a block declares is bound
        before any body in it is checked, so declarations may name each
        other whatever the order. A nominal is created by the pre-pass and
        filled in at its own statement; an alias waits until something
        names it, and one that names itself is NUPP2115.
  - [x] `Type` is a real sum type: seventeen records with `tag` a literal
        on each, and `Type` their union. Reading a field belonging to
        another tag is now an error rather than a nil at run time. The
        migration took seven adjustments across a thousand lines of
        tag-dispatching code — the narrowing carried the rest.
  - [x] Narrowing survives an elseif chain and an `or`. A narrowed copy
        keeps the field it came from, so every arm of a chain narrows, not
        just the first. An `or` proves the union of what its sides prove
        on the truthy side, and what they left in common on the falsy one.
  - [x] Per-kind node types. Ninety-two records, one per production, with
        `kind` a literal on each and `Node` their union; the parser builds them
        by name rather than through a generic constructor. Reading a field that
        belongs to another kind is an error, and every field a kind can carry
        is documented on it. What later passes leave on a node — the resolved
        signature, the ownership bookkeeping, the generator's runtime names —
        belongs to no one kind, so it is declared once as `cst.Hints` and
        included by every record. Marks the parser leaves on a *token* moved
        onto `lexer.Token` for the same reason. `gen`, `fmt` and `lsp` still
        walk nodes gradually; typing them is the remaining ripple.
  - [x] `cst.Node.args` carried two meanings, a call's argument node and an
        annotation's argument list. The annotation one is now
        `annotationArgs`, so both are typed.
  - [x] Method signatures are hoisted after their owner types. Block-level
        methods may call one another before either body is checked, and inline
        record/struct method signatures are all published before the first
        inline body is checked.
- [x] noreturn functions (found during conversion: a helper that always
      throws defeated guard-clause narrowing). A body whose every path raises
      is noreturn without being told, `@noreturn` says so where the checker
      cannot see it — an imported C `abort`, a declaration file with no body,
      a loop that never ends — and a call to one leaves the block it stands in.
      Declaring it on a function that does return is NUPP2121. `error` itself
      carries it, so the name is no longer special-cased anywhere but in
      untyped code.
- [x] A narrowing reaches the later conjuncts of the `and` chain that proves
      it. Inferring the chain already narrowed each conjunct under the last;
      analyzing what it *proves* did not, so a condition ending in a bare call
      — `if a and b and f(a, b)` — checked its arguments as though nothing had
      been tested. Each side is now analyzed under what the side before it
      proved, `or` included.
- [x] Branch-join narrowing. Every path out of an `if` is snapshotted and
      the results are unioned, so a variable assigned in one arm and ruled
      out in the other is known afterwards. A key only one path speaks to
      stays at its declared type, and a branch that leaves does not reach
      the join — which is what the old guard-clause special case did, now
      subsumed.
- [x] `math.min`/`math.max` keep integers. A function type now retains the
      element type of a typed `...`, so `function<N is number>(...: N): N` says
      "one homogeneous bounded type in, the same type out". The extra arguments
      are checked against that element and bind the type parameter, which also
      makes `string.char` and the `bit` functions checked where they were not.
- [x] Boolean literal types. `true` and `false` are types and are
      writable in annotations, `boolean` is the two of them, and
      subtracting one leaves the other. Falsy in Lua is nil or false and
      nothing else, so truth-testing now removes both: a function
      returning `integer | false` narrows to `integer` when tested.

## Tier 1 — hit in the first hour (pre-M5 blockers)

- [x] **Runtime module loading.** A `package.loaders` hook compiles and loads
      required `.nupp` and `init.nupp` modules from project include roots,
      while preserving preload, plain Lua, C-module, cache, and cycle semantics.
- [x] **Build system** (design in plan.md §Build system): `build`
      section in the `nupp.lua` manifest; `nupp build` with no args
      builds the project.
  - [x] the source set is what a build compiles: every module under the include
        roots, not the closure of `entries`. Reachability answered what to
        compile, what to check and what a bundle carries with one walk, and got
        two of them wrong — an unrequired module went unchecked, and one reached
        only through a computed `require` was missing from the binary and failed
        in front of a user. Eliminating unused code is a linker's job; measured
        here the walk removed one module of seventy-one.
  - [x] content-hash build state (`outDir/.nupp-state.json`), stable
        interface fingerprints, and output hashes
  - [x] artifact emitters for per-module `.lua`, `.d.nupp` resources, and
        import-c outputs
  - [ ] single-file application bundles
  - [x] native C step: compile user .c sources to a shared library via
        the system toolchain; bind through generated cdef declarations
  - [x] Cargo step: build Rust `cdylib` crates, preserve Cargo's own
        dependency resolution, and optionally run cbindgen/import-c
  - [x] repo dogfood: tracked stage-0 bundle, bootstrap via `nupp build`,
        no Makefile, and a staged byte-identical fixpoint
  - [x] staleness tests: content-identical warm builds check and generate
        nothing; body-only edits stop at the interface boundary; interface
        changes rebuild dependents; header changes re-import bindings; and a
        corrupted or absent `.nupp-state.json` degrades to a cold build
- [x] **Record methods and construction.** `function Task:describe()`
      attaching to records; record construction without `as` casts
      (metatable identity, which also unlocks `is` narrowing between
      records); struct methods via `ffi.metatype`; and inline ordinary method
      bodies with implicit `self` for records and structs.
- [x] **Types across modules.** A declaration qualified by the table its file
      returns (`record geom.Point`) is a member of that module, reached as
      `geom.Point` through a `require` or by module path, with stable nominal
      identity keyed by declaration site. `local` stays file-private, `global`
      publishes project-wide, and naming neither is refused.
- [x] **Multi-value returns.** A trailing call in an expression list
      expands across targets, as in Lua.

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
      `borrows`/`inout`, which govern lifetime and aliasing rather than member
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
      yet, so `nupp lints` is shorter than the idea is.
- [ ] Report an `@allow` that silenced nothing, so stale suppressions get
      removed rather than accumulating.

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
