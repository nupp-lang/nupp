# Complete C header interoperation

Status: active — host direct imports and C-dependency bridges implemented;
target extraction and cross-target completion remain planned

## Decision

Extend C imports along two explicit lowering paths:

1. declarations with an externally addressable symbol continue to bind directly
   through LuaJIT FFI;
2. header-only callables use a deterministic generated C bridge compiled as part
   of a declared native dependency.

Both paths consume one target-aware semantic declaration graph and expose the
same Nupp types, ownership modes, effects, diagnostics and module shape. A user
does not have to know whether an imported callable reached an exported symbol or
a compiler-generated bridge, but build output and inspection always say which
one it used.

The first bridge consumers are named `static inline` functions and explicitly
typed expression-like function macros. Fixed arrays, function pointers in every
C-legal position, typedef-named anonymous aggregates, exact enum storage and
standard pointer nullability improve on the direct path without requiring a
bridge.

This is not a goal to accept every program Clang accepts. C++ templates,
arbitrary preprocessor programs, statement macros, anonymous-member promotion,
compiler vector extensions, `long double`, `_Complex`, inline assembly and
unmodelled calling conventions remain visible refusals. A declaration is
direct, bridged, or skipped for one specific reported reason; no unsupported
shape silently becomes `any`, `voidptr`, or a guessed ABI.

## Why

Nupp already covers the common C boundary well:

- `cdef` gives a small API an exact checked declaration;
- `cheader` types a header in place through the C parser LuaJIT itself uses;
- `import-c` emits a committed, hand-editable Nupp module;
- `export-c` publishes deterministic target-aware Nupp struct layouts;
- C and Cargo manifest dependencies build native implementations and feed their
  headers through `import-c`;
- ownership modes, counted pointers, pins, affine results, effects and JIT
  boundary diagnostics describe facts a C prototype cannot.

The remaining gaps fall into two different categories which the implementation
currently treats alike:

- **Representable ABI, incomplete projection.** LuaJIT already parsed enough to
  call the declaration, but the neutral model or Nupp emitter drops a fixed
  array, a callback field or result, a typedef-named anonymous aggregate, or an
  enum whose physical storage is not signed 32-bit.
- **No addressable symbol.** A `static inline` function or function-like macro
  exists only while C compiles the header. LuaJIT FFI cannot load it by name no
  matter how completely Nupp models its type.

The first category needs a better semantic model. The second needs a compiled
wrapper, not a more permissive FFI declaration. Keeping those solutions
separate prevents a parser improvement from pretending it manufactured a
symbol and prevents every ordinary import from acquiring a compiler and native
artifact.

## Governing invariants

1. **LuaJIT remains the direct-call ABI authority.** A direct binding is emitted
   only when the physical declaration is accepted by the selected LuaJIT FFI
   profile.
2. **The selected C compiler remains the bridge authority.** A bridge callable
   is accepted only after that compiler parses the original header and compiles
   the generated call for the selected target.
3. **One semantic graph feeds every consumer.** `cheader`, `import-c`, manifest
   bindings, generated bridge signatures, documentation, LSP types, ownership
   auditing and cache keys do not independently reconstruct declarations.
4. **The header is not an ownership specification.** `const`, nullability and
   physical calling convention may come from C. `borrows`, `takes`, `retains`,
   `releases`, cleanup identity, counted relationships and effects remain
   explicit Nupp contracts.
5. **No optimistic fallback.** An unknown width, calling convention, aggregate,
   macro type or attribute is skipped with a stable reason. It never becomes a
   compatible-looking declaration.
6. **Arguments evaluate once.** A Nupp call evaluates every argument once before
   crossing the boundary. A generated function-macro wrapper receives those
   values as C parameters; a macro may mention a parameter repeatedly, but it
   cannot re-evaluate the Nupp expression which produced it.
7. **Target facts come from the target.** Cross-target imports use the target
   compiler, sysroot, preprocessor definitions and layout model. They never
   inspect the build host and relabel the answer.
8. **Generated artifacts are deterministic and inspectable.** Source, symbol
   names, declaration ordering, cache keys and reports contain no timestamp,
   process identity or temporary path.
9. **No hidden native build from source checking.** `cheader` may preprocess only
   when its existing explicit mode requests that work. It never compiles or
   loads a bridge. Native wrapper compilation belongs to `nupp build` or an
   explicit `import-c` bridge emission request.
10. **Imported code remains foreign code.** Compiling a wrapper does not make the
    implementation checked Nupp, safe C, pure, non-raising or AOT IR.

## User surface

### Direct imports remain unchanged

The existing forms keep their meaning and output when no newly supported
declaration is present:

```nupp
local api = cheader("native/api.h", "api")
```

```sh
nupp import-c native/api.h --lib api -o src/native/api.nupp
```

The source-compatible default matters. A project that upgrades Nupp does not
start compiling a bridge, acquire a new shared library or change a direct symbol
to a wrapper merely because the compiler learned that wrappers exist.

`cheader` gains the direct-path type improvements from this plan. It continues
to omit header-only callables because there is no symbol to load and no manifest
dependency in which to place one.

### Manifest bridge bindings

A C dependency opts into bridge generation at the binding it already owns:

```lua
dependencies = {
   image = {
      kind = "c",
      sources = {"native/image.c"},
      includeDirs = {"native/include"},
      bindings = {
         header = "native/include/image.h",
         bridge = true,
         macros = {
            IMAGE_CLAMP = {
               parameters = {"int32", "int32", "int32"},
               result = "int32",
            },
         },
      },
   },
}
```

`bridge = true` wraps eligible named `static inline` functions declared by the
selected header itself. It does not sweep callables from the include closure.
The compiler discovers their signatures; no signature is repeated in the
manifest.

Function-like macros have no C type, so each requested macro supplies one. The
type spellings use Nupp's existing C-compatible type grammar rather than raw C
declarator strings. Parameters are positional because a macro parameter name is
not an ABI fact. A `nil` result means the wrapper is a statement returning no
value. Generic, variadic and overloaded macro recipes do not exist.

The generated Nupp module exports `image_scale` or `IMAGE_CLAMP` under the
header's written name. Its private physical binding names a collision-safe
wrapper symbol derived from the dependency, header, declaration identity,
signature and bridge schema. The generated C symbol is not a public ABI.

### Explicit bridge emission

The standalone command may emit, but does not compile, the same bridge:

```sh
nupp import-c native/image.h --lib image \
   -o src/native/image.nupp --bridge-out build/generated/image_bridge.c
```

Without `--bridge-out`, static inline functions remain skipped with a repair
that points to manifest bridge bindings or the explicit flag. The command does
not invent a library name or compiler invocation. Function-macro recipes are
accepted from a checked project configuration rather than command-line type
strings; a standalone command without a manifest can bridge static inline
functions but reports that macros need a configured signature.

`--json` reports the Nupp module, optional bridge source, target, toolchain
identity, direct count, bridge count, skip count and one structured disposition
per declaration.

### No new source-level foreign language

This plan does not add `cwrap`, `cdef macro`, embedded C blocks or string-valued
C expressions to `.nupp` syntax. The header contains the C implementation, the
manifest selects build behavior, and generated C is private build output.
Ownership and effect refinements remain edits to the generated Nupp module or a
hand-written `cdef` declaration, where they are visible and checked today.

## Canonical C import graph

Introduce one bounded, serializable `CImportGraph` independent of LuaJIT ctype
ids and compiler AST pointers. It contains:

- target triple, data-layout key, ABI schema and endianness;
- preprocessor/compiler executable identity, version and behavior-affecting
  arguments;
- the direct header and ordered transitive file dependencies with content
  digests;
- target-header declaration order and source references;
- typedef, tag and synthetic nested identities;
- aggregate kind, size, alignment, fields, offsets, bit widths and field types;
- enum storage width, signedness and ordered constants;
- callable parameters, result, varargs, calling convention and linkage;
- pointer pointee, depth, `const` and standard nullability;
- fixed-array element and count at every nesting level;
- whether a declaration has an addressable external symbol, requires a bridge,
  or has no supported lowering;
- the exact reason and contributing source reference for every refusal.

Names are semantic identities, not merely display strings. A typedef-named
anonymous aggregate uses its typedef as its public identity. A nested anonymous
aggregate receives a deterministic private identity from the owning declaration
and field path, but is not exposed until Nupp can preserve its C member access
semantics.

The graph has explicit node, edge, field, parameter, string and encoded-byte
limits. Recursive pointers form graph edges. By-value recursion is refused by
the same cycle rule used by C layout and `export-c`.

### Extraction and validation

The direct baseline continues to use LuaJIT's parser and `ffi.typeinfo`. Extend
`nupp.compiler.cdecl` so it preserves every fact LuaJIT exposes instead of
prematurely mapping unsupported shapes to `voidptr` or `any`.

Rich imports use a selected Clang-compatible compiler's JSON AST only as an
extraction input. Normalize the admitted subset immediately into
`CImportGraph`; raw AST nodes, ids and spelling quirks never cross the extractor
boundary or enter a module interface. The complete compiler version and target
arguments enter the extraction cache key. An unknown AST shape is a bounded
refusal rather than a best-effort traversal.

Clang extraction is not sufficient evidence for an ABI. Generate a private
layout witness translation unit containing `_Static_assert` checks for every
admitted aggregate size, alignment and named field offset, plus typed
assignments for every callable signature. The target compiler must accept that
witness before bridge compilation or cross-target binding emission. Direct
host imports independently compare the normalized graph against LuaJIT's own
ctype answers.

If a non-Clang C compiler builds the dependency, a configured Clang may extract
the graph only when both target the same declared ABI and the final dependency
compiler accepts the witness and bridge. Otherwise rich extraction is
unavailable and the report names the missing capability. Nupp does not claim
that two compilers with the same target triple share every extension ABI.

## Direct-path additions

### Fixed arrays

Preserve array element type and count recursively. A fixed array field imports
as `T[N]`; nested fixed arrays remain nested. A parameter written as an array in
C is normalized to its adjusted pointer parameter before Nupp sees the callable
signature, while an array behind a pointer retains its bound.

Flexible array members and variable-length arrays remain unsupported. The
diagnostic distinguishes them from a fixed array whose element type is the
unsupported part.

### Function pointers

Admit function pointers in parameters, results, aggregate fields, arrays and
pointer nesting wherever LuaJIT can represent the complete callable ABI. Every
function pointer imported from a header is nullable unless standard
nullability says otherwise.

Calling one retains the existing callback/JIT treatment. A function pointer
stored by C is not inferred to keep a Lua callback alive; passing a Lua function
through a retaining API still requires an explicit pin and retention contract.
An unsupported calling convention refuses the containing declaration rather
than erasing it from the nested callable.

### Typedef-named anonymous aggregates

Import this common C form under `Point`:

```c
typedef struct {
    float x;
    float y;
} Point;
```

The semantic identity is the typedef, while the physical declaration emitted to
LuaJIT retains a representation it accepts. Multiple typedefs of one anonymous
aggregate remain aliases of one C identity, not distinct nominal structs.

Anonymous aggregate fields with names, and unnamed aggregates whose members are
promoted into their owner, are deferred. Supporting them requires either nested
aggregate syntax or explicit promoted-member semantics in Nupp; inventing a
synthetic public field would make valid C member access compile differently.

### Enums and nullability

Preserve the target compiler's enum storage width and signedness in function and
aggregate ABI positions. Enum members remain ordinary named numeric constants;
this plan does not introduce nominal enum checking.

Honor `_Nonnull`, `_Nullable` and `_Null_unspecified` when the selected compiler
gives them their standard pointer meaning. An unannotated C pointer stays
nullable. `restrict` is recorded for diagnostics but never becomes Nupp
exclusivity or `noalias`; the ownership checker needs a proof stronger than a C
optimizer promise.

## Bridge lowering

### Static inline functions

For each eligible target-header `static inline` function, emit one wrapper:

```c
NUPP_BRIDGE_EXPORT int32_t
__nupp_bridge_<fingerprint>(int32_t value) {
    return image_scale(value);
}
```

The wrapper includes the original header and repeats no implementation or
aggregate layout. Parameters and results use the canonical signature graph.
Void results emit a statement followed by `return`; aggregate results are
admitted only when LuaJIT supports the same by-value ABI. Inline functions with
unsupported parameters, effects on compiler-only types, unavailable target
features or an ambiguous address remain skipped.

`inline` and `extern inline` have language-mode-dependent linkage rules. The
first release automatically bridges only internal-linkage definitions for which
the compiler AST identifies one body. An externally addressable inline function
uses the direct symbol when the built library proves it exports one; otherwise
it reports that its linkage is not eligible instead of guessing.

### Function-like macros

A requested macro wrapper is generated only from an explicit checked signature:

```c
NUPP_BRIDGE_EXPORT int32_t
__nupp_bridge_<fingerprint>(int32_t arg0, int32_t arg1, int32_t arg2) {
    return IMAGE_CLAMP(arg0, arg1, arg2);
}
```

Nupp does not parse or translate the macro body. The target preprocessor and C
compiler decide what it means. Compilation therefore validates arity, result
convertibility, lvalue requirements and target availability against the exact
configuration which builds the dependency.

The first release admits expression-like fixed-arity macros whose arguments and
result have C-compatible value types. It rejects:

- variadic macros;
- type, declaration or initializer macros;
- macros requested with pointer ownership hidden behind an unrefined signature;
- results requiring `typeof`, statement expressions or a compiler extension not
  enabled for the dependency;
- recipes whose generated wrapper warns under the dependency's required warning
  policy or fails the ABI witness.

Stringification and token pasting are not rejected merely by spelling: if the
explicit value signature makes the generated wrapper valid C with the requested
result, the compiler may accept it. They receive no special Nupp semantics.

### Physical and logical identities

The imported Nupp member retains the header name, signature and documentation
origin. Its physical FFI declaration names the wrapper symbol. The call checker
uses the logical declaration for ownership, effects, counted relationships and
diagnostics, then lowering uses the physical signature from the same graph.

This is the same separation `export-c` uses for an ordinary Nupp struct pointer:
source meaning stays typed while compiler-owned glue chooses an ABI spelling.
No generated bridge name is user-addressable or stable across incompatible
schema changes.

## Build, cache and distribution

The bridge is one deterministic translation unit per native dependency and
target. It is compiled with that dependency's include directories, definitions,
language standard, target, sysroot and required C flags. Nupp adds hidden symbol
visibility by default and exports only bridge entry points needed by the
generated binding.

The bridge key includes:

- canonical `CImportGraph` and schema;
- original header and include-closure digests;
- macro recipes and Nupp ownership/effect refinements which affect wrappers;
- target triple, layout and CPU requirements;
- preprocessor and compiler identities and flags;
- generated-C schema and wrapper symbol set;
- native dependency identity and output kind.

Changing an implementation `.c` file rebuilds the native library without
changing the Nupp module interface when its binding graph is unchanged. Changing
a header, macro definition, compiler target or bridge recipe re-extracts the
graph and invalidates exactly its consumers.

A module target stages the bridge in the dependency library it already ships. A
compiler-owned binary stub may link it under the existing native-feature rules.
A plain bundle cannot hide a new shared-library requirement and is refused the
same way it is for other native dependencies.

Watch mode may rebuild a bridge candidate but never patches it into a process
which loaded the old native image. Any graph or native-artifact change returns a
restart decision. Body-only Nupp edits keep their existing patch behavior.

Cross-target `emit` may produce the Nupp module, graph, witness and bridge C
without executing target code. A target object or library is produced only by a
configured compiler/sysroot. The host never loads a cross-target bridge for
validation.

## Diagnostics and inspection

Every target-header declaration receives one disposition:

- `direct`: bound to an exported C symbol;
- `bridge-inline`: wrapped from a static inline definition;
- `bridge-macro`: wrapped from an explicit macro recipe;
- `type-only`: imported aggregate, enum, typedef or callback type;
- `skipped`: no supported semantic or physical lowering.

Text output summarizes counts and prints skipped declarations as the generated
module does today. JSON adds stable reason identities, source references,
logical and physical signatures, bridge symbol fingerprints, target/toolchain
facts and suggested repairs.

Stable refusal classes cover at least:

- parse or extractor failure;
- unsupported scalar width or calling convention;
- flexible, variable or indeterminate array bound;
- unsupported anonymous-member promotion;
- incomplete or by-value recursive aggregate;
- direct symbol unavailable;
- inline linkage or body unavailable;
- macro signature missing or invalid;
- macro wrapper compilation failure;
- LuaJIT physical declaration refusal;
- target/compiler/layout mismatch;
- graph, source, compiler-output or generated-artifact resource limit.

Add an inspection form which does no build work:

```sh
nupp import-c native/image.h --inspect --json
```

It reports what a direct import can model and which declarations would need a
configured bridge. With a manifest target it also resolves the bridge recipes
and compiler but does not compile them. This makes header coverage reviewable
without diffing generated source or discovering omissions at link time.

## Security and resource bounds

Headers and native dependencies already execute with the user's build
authority, but their outputs remain untrusted compiler inputs.

- All compiler and preprocessor invocations use argv, never a shell.
- Extraction, preprocessing, AST JSON, diagnostics, dependency lists, graph
  nodes, generated source and compiler output have independent byte and count
  limits.
- Compiler timeouts terminate the child process and report the exact phase.
- Paths recorded from line markers and AST locations are canonicalized beneath
  declared roots before they become dependencies or diagnostics.
- Generated wrapper names contain hashes and fixed ASCII prefixes, never raw
  macro text or an unchecked path.
- Cache hits revalidate schema, digest, target and artifact metadata before use.
- A malformed or corrupt graph is regenerated or rejected; it is never handed
  to code generation as trusted IR.
- No bridge constructor, TLS object, writable global or unexpected exported
  symbol is admitted into a compiler-owned artifact.

## Delivery

### C0: Corpus and disposition inventory

- Build a checked-in header corpus from project-owned fixtures covering each
  currently supported and skipped declaration family.
- Record the current direct, skipped and mis-modelled dispositions in structured
  tests.
- Add representative real-header slices for zlib, SQLite, SDL-style callbacks
  and one macro-heavy single-header library without vendoring entire upstream
  projects.
- Specify graph and diagnostic resource limits before accepting external AST
  output.

Exit gate: every gap named by this plan has a minimal fixture and a stable
expected disposition; no implementation milestone starts from an anecdotal
header failure.

### C1: Complete the LuaJIT-backed declaration graph

- Introduce the versioned `CImportGraph` and make `cdecl`, `cheader` and
  `import-c` consume it.
- Preserve fixed arrays and recursive nested declarators.
- Admit function pointers in fields, results, arrays and pointer nesting.
- Preserve enum storage and standard nullability.
- Import typedef-named anonymous aggregates.
- Keep generated bytes identical for the already supported corpus.

Exit gate: all newly direct declarations compile and run through LuaJIT on each
host ABI in CI; unsupported declarations retain precise skips rather than wider
fallback types.

### C2: Rich target extraction and ABI witnesses

- Add the bounded Clang JSON extractor and normalization boundary.
- Attribute declarations to the selected header while retaining include-closure
  type dependencies.
- Generate and compile layout/signature witnesses for host and cross targets.
- Reconcile the rich graph with LuaJIT's host answers and report discrepancies
  before module emission.
- Include compiler, target, sysroot, definitions and header closure in cache and
  build observations.

Exit gate: the same header and toolchain configuration produces byte-identical
graphs; deliberate target, packing, enum and calling-convention mismatches fail
at the contributing declaration.

### C3: Static-inline bridges

- Select eligible target-header internal-linkage inline definitions.
- Emit deterministic private wrapper C and logical-to-physical bindings.
- Integrate bridge compilation with `kind = "c"` dependencies.
- Add explicit standalone `--bridge-out` emission.
- Stage, cache, inspect and restart native artifacts under existing build rules.

Exit gate: a static-inline-only API imports, builds and calls from Nupp without a
handwritten shim; disabling the bridge produces a specific skipped disposition,
not a link failure.

### C4: Explicit function-macro bridges

- Validate manifest macro recipes against Nupp's C-compatible type grammar.
- Emit expression and void-result wrappers with once-evaluated Nupp arguments.
- Map compiler diagnostics back to the recipe and macro definition where
  available.
- Audit pointer-bearing recipes through the existing ownership report.
- Reject unsupported macro families without parsing their bodies in Nupp.

Exit gate: arithmetic, flag, accessor and void-result macros have differential C
and Nupp tests; repeated-argument macros prove the caller expression ran once;
invalid lvalue, type and arity recipes fail before any generated module is used.

### C5: Cargo, cross-target and tooling completion

- Feed cbindgen headers through the same graph and bridge pipeline.
- Carry target compilers and sysroots through C and Cargo dependency providers.
- Finish JSON schema, `--inspect`, LSP hover origins, generated documentation,
  ownership audit entries and hot-reload restart reasons.
- Compile emitted bridge C with Clang, GCC and MSVC-family toolchains where the
  target catalog supports them.
- Document direct versus bridge costs and how to replace a bridge recipe with a
  handwritten native API when desired.

Exit gate: C and Cargo providers share one binding result schema; host and
cross-target builds report the same logical API; all artifacts and diagnostics
remain deterministic under fixpoint and clean rebuilds.

## Verification matrix

Focused tests cover:

- direct `cdef`, `cheader`, `import-c` and manifest-generated bindings;
- fixed and nested arrays, callback parameters/results/fields and recursive
  pointers;
- typedef-named anonymous structs and unions;
- signed and unsigned enum storage across 32-bit and 64-bit targets;
- nullable, nonnull, const and unannotated pointers;
- static inline scalar, pointer, struct and void-result calls;
- function macros which mention an argument zero, one and several times;
- macro expressions with flags, casts, ternaries, stringification and token
  pasting where the explicit signature makes valid C;
- every refused anonymous, flexible-array, width and calling-convention shape;
- header include attribution, symlink/canonical-path changes and macro
  definition changes;
- compiler warnings, syntax errors, timeouts, oversized AST output and corrupted
  graph/cache artifacts;
- host direct-versus-bridge differential calls;
- target layout witnesses without target execution;
- module, binary, bundle, C dependency and Cargo dependency packaging;
- ownership, callback/JIT, hot-reload and documentation consumers.

Every compiler change runs the focused suites, the full `nupp test` suite and
`nupp fixpoint`. Generated modules, graphs, witness C and bridge C have golden
byte fixtures. ABI tests independently compile the witness rather than trusting
the graph which generated it.

## Release gates

The feature is complete when:

1. existing supported headers generate byte-identical Nupp unless a documented
   correctness improvement changes their type;
2. every declaration in the corpus has one structured disposition and no
   declaration silently becomes gradual;
3. direct and bridged calls agree with an independently compiled C caller over
   the differential corpus;
4. bridge calls add one ordinary FFI transition and no per-call allocation or
   dynamic symbol lookup;
5. a bridge-disabled build has no generated C, compiler probe or native artifact
   attributable to this feature;
6. cross-target output depends only on selected target inputs and never executes
   target code;
7. changing an included header or macro definition invalidates every affected
   graph and no unaffected module;
8. watch mode never continues through a changed loaded native image;
9. malformed external-tool output cannot crash the compiler or enter a trusted
   cache;
10. documentation states the exact direct, bridged and unsupported C subsets.

## Rejected alternatives

### Parse all of C in Nupp

C declaration and preprocessor dialects track compiler extensions, target ABIs
and system headers. Reimplementing them would create a second authority which
still could not manufacture symbols for inline functions or macros. Normalize a
bounded external semantic graph and validate it against the actual compiler
instead.

### Replace LuaJIT's parser with Clang for direct calls

Clang accepting a prototype does not prove LuaJIT FFI can declare or call it.
The runtime parser remains the physical authority for direct bindings. Rich
extraction supplies facts it does not expose and the bridge handles callables it
cannot address.

### Automatically wrap every function-like macro

A macro has tokens and parameters, not a callable type. Inferring one from uses
would be context-dependent and importing it as `any` would move failure to the
ABI boundary. Require one explicit finite signature per requested macro.

### Translate macro bodies into Nupp

That would duplicate C promotions, evaluation, lvalues, target extensions and
undefined behavior in a source generator. Compile the original macro once in a
small C wrapper and keep it visibly foreign.

### Compile bridges from `cheader`

It would make type checking invoke a native compiler, create an artifact and
change runtime packaging from a source expression. `cheader` remains the direct,
no-generated-file route; bridge work belongs to explicit build configuration.

### Expose generated wrapper symbols as a stable C ABI

Their names and signatures are private consequences of one header, target and
schema. Applications call the logical imported member. A stable exported C API
is authored C or a separate Nupp native-library feature, not an importer side
effect.

### Infer ownership from `const`, `restrict` or names

Those facts do not say who retains, releases or destroys an object. Preserve
physical mutability and nullability, but require the existing explicit ownership
contracts for lifetime and aliasing guarantees.

### Hide skipped declarations

An apparently successful partial binding is dangerous when the missing member
is discovered only by a user or link step. Retain editable residue in generated
source and make the complete disposition inventory available as structured
output.
