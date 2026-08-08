# Nupp — Language, Compiler, and Toolchain Plan

## Vision

Nupp is a gradually typed superset of LuaJIT's Lua dialect, built on a
single premise: committing to exactly one backend (LuaJIT) lets types do
things no erased-types language can do. Types lower to FFI cdata for
speed, C headers import as checked declarations, the checker can know what
the trace compiler will do, and one binary carries the compiler,
formatter, docs, and IDE server.

**Thesis:** *types make code faster, calling C is free, and the formatter,
docs, and IDE come in the box.*

**Pillars:**
- Every valid LuaJIT program is a valid (gradually typed) Nupp
  program; untyped code checks silently. Verified continuously against a
  large corpus of real-world untyped Lua (0 parse errors, byte-exact CST
  round-trip, 0 diagnostics).
- `struct` reifies to `ffi.typeof`, and `T[?]` / `T[N]` give contiguous
  arrays of them — measured 6–9x on an AoS loop written in Nupp
  (bench/aos.nupp) against the same program written with tables, and 5.6x
  on memory (docs/spike-reification.md).
- Typed C interop: a pinned header is typed at compile time by
  `cheader('path.h')` — the compiler hands it to its own `ffi.cdef` and
  reads the declarations back through `ffi.typeinfo`, so LuaJIT's C
  parser is the source of truth and the sizes are the ones this platform
  uses. No generated file, and no C compiler for a self-contained header.
  `cdef` declarations with checked signatures; `import-c`
  ejects committed, hand-editable `.nupp` binding modules from headers.
- Tooling-first architecture: lossless CST, error-tolerant parser,
  incremental query engine with interface-hash cutoff, line-count-
  invariant codegen (correct stack traces with zero sourcemaps).
- **Integration is a stated goal:** a project mixes nupp with plain Lua,
  the user's own C modules, other typed-Lua dialects, and Rust crates —
  each typed at the boundary, each a first-class build input, and all of
  it working under the self-contained binary (see §Integration).
- Self-hosted: the compiler is written in Nupp and rebuilds itself to
  a byte-identical fixpoint (`nupp fixpoint`).

**Validation target:** tecs (~/projects/tecs), a 111k-line LuaJIT game
engine (SDL3/SDL_GPU/Rapier, archetype-SoA ECS, Rust host). Porting one
subsystem (`internal/ffi/FFIStorage` + `components.tl`) is the v0.1
acceptance test; its pain points (per-component FFI declaration
triplication, thousands of casts at cdata boundaries, 53-bit entity-id
packing, variadic-FFI trace hazards) map one-to-one onto the pillar
features. The component/event language blockers are landed: nested nominal
namespaces, `record X is Y`, `<T is Bound>`, declaration-scoped `self`, and
trusted metamethod contracts. The acceptance test still requires translating
and running the real subsystem rather than only its focused fixtures.

## Status — landed

- **M0 Front end.** Lossless trivia-preserving lexer; formal ABNF grammar
  (docs/grammar.abnf, normative, CS-1..CS-10 context notes); error-
  tolerant CST parser (never drops a token; byte-exact round-trip on
  arbitrary input); fmt-v0 (idempotent whitespace/indent reprint);
  `bin/nupp` CLI.
- **M1 Checker.** Content-address interned types (equality = identity);
  subtyping with explain-why failures; inference with stable NUPP2xxx
  codes; flow narrowing (`is`, nil checks, truthiness, guard clauses,
  and/or/ternary right sides); generic nominal and function instantiation at
  call sites with upper bounds (`<T is Bound>`) and `T?`-residue handling;
  declaration-scoped `self`; stdlib prelude as a dogfooded `.d.nupp` (closed
  library shapes, string methods); bundled declarations for
  `string.buffer`, `cjson`, `cjson.safe`, and `ffi`, which a project's
  own files may shadow; module resolution with `require()` typing; module
  members reached through the table they were declared on, with stable nominal
  identity ([modules.md](../docs/modules.md)).
- **M1.5 Reification spike.** Thesis validated: 8.4x AoS loop, 3.9x
  method dispatch, 5.6x memory (bench/reification.lua).
- **Formatter.** The doctrine below, implemented: 4-space indent,
  120/88 widths, group-aware breaking (arguments, parameters, tables one
  per line; low-precedence operator fallback), docblock reflow with
  blank-line separation, and the token-fingerprint safety bail. The repo
  formats itself.
- **M2 Codegen.** Type-erasing generator under the line-count invariant;
  lazy ternary, single-eval safe navigation, short functions,
  interpolated strings, `is` → `type()`, bit ops → `bit.*`;
  `nupp build`/`nupp run`; runtime project loader for required `.nupp`,
  `.lua`, and `init` modules using the checker environment's search roots.
- **M3 Reification (complete).** `T[?]` and `T[N]` complete it:
  contiguous FFI arrays of a reified struct, zero-based, with element
  typing and a per-element-type ctype cache. bench/aos.nupp measures 6–9x
  over the same loop written with tables, from Nupp source rather
  than hand-written Lua — matching or beating the original spike. Earlier
  work: `struct` → `ffi.typeof` ($-parameterized nested and pointer fields);
  checked construction (named/positional); implicit
  zero-init; `is S` → `ffi.istype`; closed reifiable field set (NUPP2201);
  cdata numeric slots take any numeric (C conversion semantics).
- **M4 C interop.** `cdef struct`/`cdef function` with C-compat
  validation (NUPP2203); `cstring`/`voidptr` boundary types with one-way
  conversions; erased `@owned(cleanup...)` annotations describe deterministic,
  explicit cleanup without attaching `ffi.gc`; struct→`T*`
  address passing and nil-as-NULL; `import-c` pipeline (cc -E, linemarker
  filtering, normalization, LuaJIT-parser validation, `-dM` constants,
  unsupported decls ejected as comments). Affine ownership tracks
  `owned<T>`, `borrowed<T>`, and `pinned<T>` values; `takes` moves; live
  lexical borrows; managed-pointer anchors with `retains`/`releases` C
  contracts; use-after-move; raw transfer; cleanup calls; and unsafe FFI
  boundaries.
- **Incremental engine.** salsa-lite query core; fileText overlay →
  parse → checkModule → moduleInterface; interned interface identity IS
  the interface hash, so body edits recheck one file (proven by compute
  counters); overlay-derived declaration headers feed a query-owned project
  index with stable nominal identity; the LSP revalidates open files and
  republishes only dependents whose checked result changed.
- **Editor tooling.** LSP over stdio with diagnostics, definition, hover,
  completion, signature help, references, rename, semantic tokens, and
  formatting; VS Code extension in editors/vscode. The features share
  checker-owned symbol/type metadata, cover `cdef` declarations and C
  interop types, and run on the incremental engine. The extension has a
  TextMate fallback grammar and configurable server executable,
  arguments, working directory, and environment.
- **Members.** `function R:m()` and `function R.m()` attach to the named
  record or struct; the receiver is typed, call sites drop it, and arity
  and unknown members are checked. Records carry a runtime table, so
  `R{...}` builds a checked instance stamped with the record's metatable
  (its identity); struct members dispatch through `ffi.metatype`.
  Inline ordinary method bodies use the same namespaces. Trusted, erased
  [metamethod contracts](../docs/metamethods.md), `self`, `record X is Y`, and
  bounded generics type runtime protocols without taking ownership of
  metatable construction. Multi-value returns expand across an assignment's
  targets.
- **Modules at runtime.** A `package.loaders` hook compiles `require`d
  `.nupp` modules on demand, so multi-file programs run straight from
  source; `nupp build` emits the dependency closure, and built output
  runs on plain LuaJIT with no toolchain present.
- **P0 Self-hosting.** Compiler sources are `src/nupp/*.nupp` (nothing
  else); generated artifacts live in the gitignored `build/nupp/`;
  two-stage fixpoint verified (`nupp fixpoint`). A tracked stage-0 bundle
  lets a fresh clone build without an existing build tree.
- **Syntax decisions.** The whole LuaJIT 3.0 base (per LuaJIT#1475), the
  customary operators included, with additions and no subtractions:
  backtick string interpolation, `??=`, type annotations on short-function
  parameters, and one explicit type per field, always. Writing a customary
  operator raises the `customary-operator` lint, which is a house-style
  judgement rather than a restriction. `metamethod`, declaration-head
  `is`/`where`, and generic bounds are contextual additions documented in
  [metamethods.md](../docs/metamethods.md).
- **Runtime floor.** LuaJIT 2.1 backported almost all of the 3.0 syntax, so
  generated code is that syntax rather than a lowering of it, and the floor is
  2.1.1784535649. What 2.1 did not take — floor division, the named vararg —
  is still lowered, as is `??=`, which LuaJIT declined outright.

## Language design (stable decisions)

- **Structural for shape, nominal for provenance.** Inline table shapes,
  maps `{[K]: V}`, arrays, tuples, and function types are structural;
  records/classes, `struct` (ctype identity), and host handles are nominal.
  `local type` declares a transparent alias. Nominal-to-shape erosion is
  allowed; the reverse never is.
- **Runtime protocols are trusted declarations.** `record X is Interface`
  includes a nominal contract and rebinds its declaration-scoped `self`;
  undeclared satisfaction remains structural. `metamethod __call: function`
  and the other supported [metamethod contracts](../docs/metamethods.md) type
  runtime dispatch but emit no metatable setup. Ordinary Lua or a foreign
  registrar fulfills the promise. Inline ordinary methods use
  `function name(...)` and do emit onto the record or struct method namespace.
- **Declaration visibility and project linking.** A declaration says where it
  lives with the spelling Lua already uses for definitions: `local` keeps it
  to the file, a qualified name (`record models.User`) makes it a member of
  that table, and `global` publishes a project global. Naming none of the
  three is refused rather than defaulting, since plain Lua would have made the
  name a global. A member is reached through its module — `local models =
  require("models")` then `models.User`, or the module path
  `models.user.User` — so only a global is reachable without saying where it
  came from. A declaration is nameable by its simple name inside its own body,
  which is what keeps a recursive field readable. Runtime values are ordinary
  Lua: a module's type is what the file returned, and a declaration carrying a
  runtime value assigns itself onto its table, so nothing is merged in
  afterwards. Global structs still add a loader side-effect edge, `.d.nupp`
  declaration files keep bare declarations as the interface they describe, and
  ordinary bare Lua assignments retain `_G` semantics. Written up with worked
  examples in [modules.md](../docs/modules.md).
- **Lints are not type errors.** A type error says the program does not mean
  what it says it means: not configurable, not suppressible, always fatal. A
  lint says the program means something its author probably did not intend, so
  it carries a name, a category and a level (`off`/`note`/`warning`/`error`) a
  project moves in `nupp.lua` and a statement waves away with `@allow`. Only an
  error stops a build, and an editor may show a lint more quietly than a build
  enforces it. See [lints.md](../docs/lints.md).
- **Unions:** arbitrary member types are legal; narrowing is best-effort
  and succeeds exactly when members are runtime-distinguishable
  (`type()` tags, nominal identity, discriminant fields). Sum types are
  discriminated unions of shapes; constructor/exhaustiveness sugar later.
- **Numerics:** `number` (double), `float`, sized ints as real cdata
  types; cdata slots accept any numeric (C conversion); `integer` vs
  `number` stays strict.
- **Gradualness policy:** inferred bindings widen (literal shapes stay
  open, integer→number, nil→any); only annotated bindings enforce
  assignment compatibility; unknown globals/modules are `any` until
  `--strict`.
- **cdata soundness:** NULL is truthy but `== nil`; `T*` vs `T*?`;
  0-indexed FFI arrays remain distinct from 1-indexed Lua arrays.

## Roadmap

The working list, ordered by user impact, lives in **plans/todo.md**. Tier 1 and
Tier 2 language baselines are landed: manifest builds, record/struct methods,
generic nominals and upper bounds, structural and declared interface
contracts, metamethod dispatch, literal/discriminant narrowing, literal
and tagged unions,
coalescing/compound assignment, and strict mode. Active Tier 3 work includes:

- the `@jit` trace checker and variadic-FFI lint;
- deterministic
  [comptime](comptime.md) data evaluation with target-aware layout and
  read-only reflection (no macros or declaration splicing);
- stronger checking of generic metatable assembly;
- tooling completion, codegen polish, struct unions/bitfields, malloc-backed
  arrays, dialect import/translation, and import-c hardening;
- the full tecs subsystem translation and runtime-equivalence acceptance test.
- **M6 (continuous):** type the compiler itself, module by module, as
  the features it needs land; the checker fully checking `check.nupp`
  under `--strict` is the finish line.

### LSP follow-up

The current server is a usable editor baseline, not the final M5 tooling
surface. Its requests are covered by framed protocol integration tests,
but several features deliberately start with file-local or full-document
behavior. Future LSP work, in priority order:

1. **Workspace lifecycle and symbols.** The declaration index is query-owned,
   overlay-aware, and preserves stable declaration identities; dependent open
   files republish diagnostics when an exported interface changes. References
   and rename now run over the whole project rather than the open documents:
   a rename that skipped a closed file would leave the project broken with
   nothing said. Text is the filter before checking — a reference has to spell
   the name — and a symbol the project does not declare, such as one from the
   bundled prelude, is refused outright rather than half-renamed.

   Plain `function m.f` members are reached too, but not through the index.
   Nothing types the table a file returns, so a member has no interned
   declaration and no type a definition could hang from; putting its offset in
   the header would also make every keystroke above it recheck every dependent,
   because that offset moves whenever a body does. It is answered syntactically
   instead, per request: which module a name holds is recorded on that name's
   definition when it was bound to a `require`, and a file's own module local is
   the table its own members sit on. Definition, references and rename run over
   the whole project from there, and hover shows the declaration line as
   written, there being no type to render.

   The folders a session searches follow the client: `initialize` adopts the
   ones it opened, `workspace/didChangeWorkspaceFolders` adds and drops them,
   and each brings the include paths its own `nupp.lua` declares. A folder
   change rebuilds the query graph rather than patching it, hands the open
   buffers back as overlays, and republishes unconditionally — a file can be
   clean under one set of folders and not another, and the editor has no way to
   know the ground moved. Lint levels and language mode still come from the
   launch root; letting a second folder redecide them would mean the same file
   checked differently depending on which window opened it. Real multi-root
   isolation, one project per folder rather than one search path across them,
   is listed under protocol hardening below.
2. **Contextual completion.** Receiver/member completion and
   type-position filtering have landed. After a `.` or `:` the answer is
   what that receiver holds and nothing else — a record's fields, its
   methods (a `:` offers only what can be called, because a colon sends a
   message), a required module's declarations and its plain `function
   m.f` members — and an annotation offers only what can stand where a
   type is expected, a name whose kind nothing settled counting as no.
   The context is read off the token stream, because a request arrives in
   the middle of the expression it is about and `util.` is not a program;
   the types come from the last state of the file that checked, which is
   one keystroke stale and exactly right, the receiver being the part the
   author already finished. Still ahead: lexical-scope filtering of the
   ambient list, C struct fields and imported C declarations, callable
   snippets, and import/module-path completion. Add completion resolve
   only when richer documentation makes deferred work worthwhile.
3. **Richer hover and signatures.** Preserve parameter names, overloads,
   generic substitutions, ownership/cleanup information, and source
   declarations. Parse doc comments into checked nodes so `@param` names
   and `[[Type]]` links are validated once and rendered consistently by
   hover, signature help, completion, and docgen.
4. **Incremental semantic tokens.** `resultId`-based delta and range
   requests have landed. The last answer given for a document is kept, one
   revision deep, because a client asks for the delta from the answer it
   holds and the answer it holds is the last one given; an id the server no
   longer has is answered in full rather than with an edit against something
   neither of them has. A range is encoded from the range, not sliced out of
   an encoded whole: the protocol counts each token from the one before it,
   so a slice of an encoding is not the encoding of a slice.
   Still to extend: module
   namespaces, readonly values, and declaration modifiers gain checker
   semantics. Metamethod and inline-method declarations already have
   semantic tokens.
   Keep the TextMate grammar as the no-server and broken-file fallback;
   it is hand-scoped rather than generated from ABNF because ABNF defines
   syntax, not editor scope intent.
5. **Formatting evolution.** The width-aware formatter, minimal edits and
   range formatting have landed. Formatting answers with the runs of lines
   that changed rather than the whole document — a client applying one
   whole-document rewrite loses every cursor, fold and mark in the file to
   replace lines that came through untouched — and lines are the right grain
   because the formatter never joins them. A range keeps the runs that fall
   inside it; a run reaching past the selection is a change the request did
   not ask for, and a whole-document formatter cannot reformat half of one.
   Still ahead: on-type formatting where it is stable. Respect negotiated
   client formatting options only where they do not conflict with the
   project's canonical style.
6. **Editor actions and protocol hardening.** Structured diagnostic
   fix-its and code actions have landed: a diagnostic may carry named,
   machine-applicable edits (byte offsets over the file it belongs to),
   and `textDocument/codeAction` serves those as quick fixes alongside
   CST-computed refactorings. The first fixes are NUPP2119 (every
   visibility a declaration could have), NUPP2120 (add the missing
   require), NUPP2101 (spell a type through the module exporting it), and
   NUPP2603 (wrap a live owner in a `with` scope); the first refactorings
   are `with` wrap and unwrap. Both refuse rather than guess: a rewrite
   that would change control flow or hand back an owner the scope closes
   is not offered. Document and workspace symbols, highlights, folding
   ranges and selection ranges are served from the CST, so they answer in
   a file that does not check yet — which is where an outline is worth
   most. A qualified declaration is listed as its path, a fold starts at
   the line that says what is being folded rather than at the body inside
   it, and a workspace search reads the declaration index rather than
   sweeping the project. Safe spelling fixes now cover variables, types,
   fields and methods, while diagnostics requiring an author choice carry
   related locations and repair help rather than a semantic guess. Still to
   come: fixes for newly identified unambiguous diagnostics, and
   `codeAction/resolve` if refactorings grow
   expensive enough to defer. Recorded broken-code sessions
   are replayed in the suite already (`tests/lspsessions/`): a burst of
   edits has to leave the session where one edit would have, and the
   answers at the end have to be the answers a server handed only the
   final text gives. `$/cancelRequest` is understood rather than merely
   ignored, but it cannot do more than that here: this loop answers in
   the order it reads, so by the time a cancellation is read the request
   it names has already been answered, and answering normally is what the
   protocol says to do then. Cancelling work in flight needs input that
   can be read without blocking, which is the change that has to come
   first. Still to handle: that, graceful
   stale-request results, real multi-root sessions — one project per
   folder rather than one search path across them — and large-workspace
   latency budgets in CI.

## Formatter doctrine (implemented)

Zero configuration — the following are fixed properties of the language's
formatter, not settings:

- **Indentation: 4 spaces.**
- **Line width: 120 columns** for code. Existing line breaks are
  respected (the formatter never joins lines); lines that exceed the
  width are broken. Width is measured in Unicode display columns:
  combining marks occupy zero columns and East Asian wide characters two.
- **Long argument lists break one-per-line:** callee and `(` stay on the
  head line, each argument gets its own line at +1 indent with a
  trailing comma, `)` closes on its own line at the head indent. The
  same shape applies to parameter lists and table constructors.
  Overlong expressions without a breakable group break before the
  lowest-precedence operators at +1 continuation indent.
- **Docblocks are parsed and formatted.** A docblock is a run of comment
  lines whose first line starts with `---`; lines carry free text and
  `@`-annotations (`@param name desc`, `@return`, `@field`, ...). The
  formatter normalizes every line to a `---` prefix, rewraps prose and
  annotation descriptions to **88 columns** (annotation continuations
  indented under their tag), leaves fenced/indented code verbatim, and
  keeps `---` for paragraph breaks. Docblock annotations are the same
  surface later checked by the doc pipeline (`@param` names must exist)
  and rendered by docgen and LSP hover.
- **Plain line-comment runs are reflowed too.** Consecutive standalone `--`
  lines use the same 88-column prose and verbatim-code rules as docblocks,
  without acquiring docblock attachment or blank-line semantics. Trailing
  comments remain on their source line.
- **Documented declarations are set off by blank lines:** one blank line
  before the docblock and one after the documented declaration.
- **Docblock separation detail:** the blank line is omitted where a
  docblock opens a scope that just began (right after `record X`, `do`,
  `then`) and before a scope close, so a documented first or last member
  does not strand a blank against its brace.
- **Safety invariant:** formatter output must re-lex to the identical
  token sequence (kind and text) as its input, or the formatter refuses
  to rewrite the file (NUPP4001). `fmt(fmt(x)) == fmt(x)` and
  parse-stability stay tested properties.

## Integration (stated goal)

Users bring what they already have; nupp types the seams. Every row
below must work both from a source checkout and under the distributed
self-contained binary:

- **Plain Lua** — works today: `.lua` modules load unchanged and type as
  `any`; a sibling `.d.nupp` (or a shipped dialect declaration file)
  types the boundary without touching the code.
- **The user's own C** — pin the header and name it with `cheader`; it is
  typed at compile time with no generated file and no compiler. This is
  the default path (8 of 9 headers in the validation target parse
  directly, including 215 cbindgen-generated Rust declarations; the one
  that does not takes a `lua_State`, which is not FFI-callable anyway).
  `cdef` declarations and `import-c` remain for hand-written bindings and
  for headers that need repair before LuaJIT will take them. Planned: the build manifest accepts C
  source files as a native build step (compiled to a shared library via
  the system toolchain and bound through generated `cdef` declarations),
  so "drop a .c file in the project" is a supported workflow. `import-c`
  needs a C compiler only at import time (the ejected `.nupp` module is
  committed); runtime FFI needs none — the self-contained binary
  therefore imports headers when a toolchain is present and runs
  existing bindings everywhere.
- **Other typed-Lua dialects** — §Dialect interop: compiled output runs
  today; declaration reading types the boundary; `import-tl` translates
  sources; the build system accepts `.tl` inputs in mixed trees.
- **Rust** — the cbindgen pipeline: a crate exposes `extern "C"`,
  cbindgen emits the header, `import-c` ejects typed bindings, and the
  planned `nupp-cargo` helper collapses that into one step (build the
  cdylib, generate, resolve the library path). `Box<T>` returns map to
  `@owned(crate_destroy)` on the returned `T*` binding.

## Build system (design)

`nupp.lua` is the project manifest; `nupp build` with no arguments
builds the project from it. Sketch:

    return {
       include = { "src" },
       build = {
          outDir = "build",
          entries = { "src/nupp/main.nupp" },   -- roots of the module graph
          headers = {                            -- import-c artifacts
             { header = "vendor/miniz.h", out = "src/deps/miniz.d.nupp" },
          },
          bundles = {                            -- single-file amalgamations
             { out = "dist/nupp.lua", entry = "nupp.main" },
          },
          native = {                             -- user C sources -> shared lib
             { sources = { "native/fast.c" }, out = "fastlib" },
          },
          binaries = {                           -- self-contained executables
             { out = "dist/myapp", entry = "app.main",
               targets = { "macos-arm64", "linux-x64", "windows-x64" } },
          },
       },
    }

Decisions:

- **Dependencies are discovered, not declared.** The checker already
  resolves every `require()`; the build walks the module graph from the
  entries and the query engine records the edges as it goes. Only edges
  the compiler cannot see are declared: C headers behind import-c
  outputs (stale key: header content + flags + `cc --version`) and any
  copied assets.
- **Stale checks are content-addressed**, consistent with the type
  interning philosophy: a module's artifact rebuilds when the hash of
  its source or of any dependency's *interface* changes. Reachable inputs
  are always hashed, avoiding correctness holes from coarse mtimes. Build
  state lives in `outDir/.nupp-state.json` (per module: source hash,
  interface hash,
  artifact hash, dep list) — deleting it just means a cold build.
- **One graph, three consumers.** The build cache serializes the query
  engine's dependency records, so the batch CLI, the LSP daemon, and
  `nupp build` share the same incremental machinery; a warm daemon can
  hand the build a hot graph and vice versa.
- **Artifact kinds:** per-module `.lua` (line-count invariant), copied
  `.d.nupp` declarations, import-c outputs, single-file bundles
  (modules wrapped in `package.preload` around an entry), native shared
  libraries from user C sources, and **self-contained executables** —
  the flagship end-user artifact (below).
- **Self-contained binaries, cross-platform.** `nupp build` emits a
  standalone executable per declared target: the app bundle is embedded
  into a precompiled runtime stub (the same Rust-host + vendored-LuaJIT
  machinery the toolchain itself ships as). Cross-"compilation" is stub
  selection — building for another OS/arch means embedding into that
  platform's stub, no cross C toolchain required. Native FFI libraries
  remain per-platform inputs: pure nupp/Lua apps (plus system-library
  cdefs) cross-build from any host; apps with their own compiled C/Rust
  supply per-target artifacts (nupp-cargo forwards cargo's own
  cross-compilation where configured).
- **Dogfood:** the repo builds itself through `nupp build` reading this
  manifest. A tracked stage-0 bundle breaks the bootstrap cycle, the
  Makefile is gone, and `nupp fixpoint` stays the bootstrap invariant.
- Later: `--watch` (rebuild on change, sharing the LSP's overlay
  machinery) and explicit manifest build steps for generated external
  artifacts. Comptime itself performs no file or declaration generation.

## Dialect interop (design)

nupp can meet existing typed-Lua code where it lives. Three layers, all
following the import-c eject model (committed, hand-editable output —
never a black-box shim), named accordingly: `import-tl`.

- **Runtime (works today):** dialects that compile to Lua are ordinary
  modules; nupp requires their compiled output as `any`.
- **Declaration reading:** a dedicated dialect reader (never a mode on
  the nupp parser — `{string: number}` is a map in the other dialect and
  an inline shape here, so the same bytes mean different types) that
  translates the declaration subset (records, aliases, signatures,
  globals) into interned types. Wired into module resolution after
  `.d.nupp`, it types the boundary to existing libraries without
  hand-written twins. Nil-permissive declarations import as written
  (trusted, like `cdef` signatures).
- **Source translation:** `nupp import-tl <file> [-o out]` ejects `.nupp`
  from dialect sources. Mechanical rules: map types gain the indexer
  (`{K:V}` → `{[K]: V}`); multi-returns parenthesize where type position
  requires; metamethod declarations, `record X is Y`, bounded generics, and
  declaration-scoped `self` carry over one-to-one. A `where` clause carries
  over as one, since refinements are enforced and compiled; one written outside
  the subset the test admits becomes marked residue like anything else. Macro
  facilities and other declarations without a clean
  translation become clearly marked comments with `any` fallbacks so the
  output always parses and checks — residue is visible, never silent. The
  build system accepts `.tl` inputs and runs
  the translator as an artifact step, so mixed trees build while files
  are converted by hand over time.
- **Verification:** translated output must typecheck; runtime-equivalence
  suites run original and translation side by side; the tecs subsystem
  port is the real-world corpus.
- Cross-module type support is landed; mixed-tree mode still depends on the
  build system.

## Verification doctrine

- Real-world corpus oracle: large untyped Lua codebases must stay at
  0 errors / 0 diagnostics / byte-exact round-trip.
- Every lowering carries execution-semantics tests (including real libc
  calls and float32 storage behavior).
- Trusted runtime protocols carry both static-dispatch tests and a tecs-style
  late-registration execution fixture; the translated tecs subsystem remains
  the external acceptance gate.
- Line-count invariant is tested and load-bearing (traceback fidelity).
- Incrementality is asserted with compute counters, not wall clock.
- Benchmarks are tracked (bench/reification.lua) as a regression fence.
- The bootstrap fixpoint (`nupp fixpoint`) runs in CI once CI exists.
- Full testing strategy and the formatter golden corpus: plans/todo.md.

## Distribution

One binary `nupp check|fmt|build|run|import-c|lsp`. Eventually: a small
Rust host vendoring a pinned LuaJIT plus the amalgamated compiler — users
install nothing else. The toolchain VM is pinned independently of the
user's runtime; the pin is a floor as well as a version, since a stub whose
interpreter predates the syntax backport cannot load the payload it carries.
Development and bootstrap may still use a compatible external LuaJIT; release
artifacts must not require one.

The host also vendors a pinned commit of the MIT-licensed
[OpenResty lua-cjson](https://github.com/openresty/lua-cjson) fork. Its C
sources are linked into the executable and its `cjson` and `cjson.safe`
entry points are registered in `package.preload`, so there is no runtime
`.so`/`.dylib` dependency. Compiler code uses the embedded `cjson` module
directly, marks arrays with its array metatable, and configures strict
JSON numbers so acceleration cannot change JSON-RPC behavior.

Vendored dependencies are pinned by source revision, carry their license
notices in binary distributions, and are updated deliberately rather
than through the user's LuaRocks tree. Tests run the JSON corpus and
framed LSP sessions through the embedded codec; fuzzing covers Unicode
escapes, malformed input, nesting limits, sparse/empty tables, and
numeric edge cases.

Library convention: publish generated `.lua` beside `.nupp` sources so
plain-LuaJIT consumers need no toolchain.
