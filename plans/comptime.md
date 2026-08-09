# Nupp comptime plan

## Decision

`comptime` is deterministic compile-time evaluation of ordinary nupp code. It
produces data values that the compiler quotes as ordinary source literals. It
does not expose the CST or AST, paste source text, generate declarations, or
inline runtime code.

The type system remains independent:

- Generic functions and nominal types use normal type parameters and are
  checked parametrically.
- `const` means that a local binding cannot be reassigned. A `const` binding
  may additionally carry a compile-time-known value, but immutability alone
  does not make a runtime computation available at compile time.
- `comptime` is explicit at the point where evaluation is required. It is not
  how generics are implemented.

This separation keeps generic APIs understandable without executing user code
and keeps comptime out of module declaration discovery.

## Goals

1. Compute constants using familiar nupp control flow and functions.
2. Expose target-aware `sizeof`, `alignof`, `offsetof`, and read-only type
   reflection.
3. Preserve deterministic builds, the line-count invariant, incremental
   cutoff, and responsive editor tooling.
4. Give comptime code the same type checking and diagnostics as runtime code.
5. Erase every comptime construct from generated Lua except its quoted result.

## Non-goals

The following are deliberately outside this feature:

- AST or CST access
- quoting or splicing source code
- expression macros, templates, and `@inline`
- user-defined derive macros
- declaration or module generation
- compiler lifecycle hooks
- arbitrary `require`, filesystem, environment, clock, random, process, or
  network access
- automatic optimization or specialization of runtime functions

Consequently, comptime will not materialize metamethod declarations produced
by another dialect's macro system. `import-tl` must eject those as explicit
contracts or visible translation residue; see
[metamethods.md](../docs/metamethods.md#deliberate-exclusions).

If a transformation such as `@soa` proves valuable, it should be a separately
specified, compiler-owned language feature. It must not be an escape hatch to
a general macro system.

## Surface syntax

### Expression blocks

`comptime do ... end` is an expression. `comptime` is contextual only when it
is followed by `do`; it remains a valid identifier elsewhere.

```lua
const CACHE_LINE: integer = 64

const vertexStride: integer = comptime do
    const raw = sizeof(Vertex)
    return (raw + CACHE_LINE - 1) // CACHE_LINE * CACHE_LINE
end
```

A block has its own lexical scope. `return` returns from the comptime block,
not from the enclosing runtime function. Every reachable path must return
exactly one value in the first version. Multi-value comptime results are
deferred until normal multi-value semantics are complete.

The result replaces the block:

```lua
const vertexStride: integer = 32
```

### Comptime functions

Reusable helpers arrive after expression blocks. A function annotated with
`@comptime` is typechecked like a normal function, is callable only while
evaluating comptime code, and emits no runtime declaration.

```lua
@comptime local function alignUp(value: integer, alignment: integer): integer
    return (value + alignment - 1) // alignment * alignment
end

const vertexStride = comptime do
    return alignUp(sizeof(Vertex), 16)
end
```

The initial comptime-function implementation keeps them file-private. Exported
comptime functions would require their checked body or an evaluator artifact to
become part of a module interface; that is deferred until a concrete
cross-module use case justifies the extra interface and cache complexity.

Comptime functions may recurse within the evaluation budget. Generic comptime
functions are deferred until generic constraints can state what operations on
a type parameter are valid.

## Compile-time-known values

The checker tracks an optional compile-time value alongside a binding's normal
type. This is a small, explicit knownness lattice, not a second type system:

```text
unknown at compile time
known quotable value
known comptime-only handle (for example TypeInfo)
```

The following can be compile-time-known:

- literals
- table constructors whose keys and values are all known
- pure operators over known operands
- `const` bindings initialized from known expressions
- results of comptime intrinsics and comptime functions

A `const` initialized from a runtime operation remains runtime-only:

```lua
const argument = arg[1]

const bad = comptime do
    return argument -- NUPP2401: runtime value is unavailable at comptime
end
```

Mutable locals declared inside a comptime block are allowed; their storage
exists only in the evaluator. A comptime block may capture only known values
and resolved type handles. It may not read or mutate runtime locals, upvalues,
module state, or globals.

## Quotable results

The first version can quote:

- `nil`
- booleans
- finite Lua numbers
- strings
- acyclic tables with boolean, finite-number, or string keys; quotable values;
  and no metatable

Functions, threads, userdata, arbitrary cdata, type handles, cyclic tables,
and tables with metatables are rejected. Sized integer cdata and other values
that need new literal rules can be added deliberately later.

The serializer is canonical:

- strings use escaped single-line literals;
- array entries precede keyed entries;
- keyed entries use a stable ordering by key kind and value;
- negative zero is emitted as `-0.0`;
- NaN and infinities are rejected initially;
- table identity and aliasing are not preserved.

Quoting a table creates a normal fresh runtime table when the generated module
loads. It does not embed a mutable compiler-owned object.

The checker infers the quoted literal's type using the ordinary expression
checker and validates it against the surrounding expected type. Comptime does
not bypass assignment, return, or field checks.

## Reflection and layout intrinsics

The first public intrinsics are:

```lua
sizeof(T): integer
alignof(T): integer
offsetof(T, fieldName): integer
reflect(T): TypeInfo
```

Their type arguments are parsed and resolved as type positions, so aliases,
qualified project types, and instantiated nominal types work without a
corresponding runtime value. `fieldName` must be a compile-time-known string.

`sizeof`, `alignof`, and `offsetof` accept only types with a defined runtime
layout for the selected target. They use compiler-owned layout information,
not ambient host `ffi.sizeof`. A request for an erased or target-unsupported
type is a checked error.

`reflect(T)` returns an immutable public descriptor rather than the mutable
tables used internally by `compiler.types`. The initial descriptor includes:

```lua
{
    kind = "struct",
    name = "Vertex",
    qualifiedName = "geometry.Vertex",
    fields = {
        {name = "x", type = <TypeInfo>, offset = 0},
        {name = "y", type = <TypeInfo>, offset = 4},
    },
    size = 8,
    alignment = 4,
}
```

Field order is declaration order. Recursive types are represented by stable
read-only handles, not recursively copied tables. A `TypeInfo` handle can be
inspected and compared during comptime evaluation but cannot be returned as a
quoted runtime value.

Reflection is read-only data processing. It cannot add fields, methods, types,
or declarations. Reflection of an unresolved generic type variable is rejected
initially; reflection operates on concrete resolved types.

Every reflection schema change increments a comptime API version that
participates in cache keys.

## Evaluation environment

Comptime execution receives a fresh capability-limited environment containing:

- `assert`, `error`, `ipairs`, deterministic `pairs`, `select`,
  `tonumber`, `tostring`, and `type`
- frozen or per-evaluation copies of the pure portions of `math`, `string`,
  `table`, and `bit`
- the compiler-provided reflection and layout intrinsics
- captured known constants serialized into the request

It does not receive `io`, `os`, `package`, `require`, `ffi`, `debug`, `jit`,
`coroutine`, `load`, `loadstring`, `dofile`, `getfenv`, `setfenv`, clocks,
randomness, environment variables, or ambient `_G`.

Iteration through the provided `pairs` is deterministic. Library tables cannot
be mutated across evaluations. Errors and assertion failures become compiler
diagnostics at the comptime call site with a comptime call stack.

Evaluation has instruction, recursion, result-size, and memory limits. The
limits are documented toolchain constants in the initial version rather than
source-level knobs. A limit failure is deterministic and reports which budget
was exhausted.

The evaluator should ultimately run in a worker process invoked through a
private toolchain mode. The worker accepts a serialized request and returns a
serialized value or diagnostic. This prevents an infinite loop, evaluator
crash, or excessive allocation from taking down the LSP. A limited Lua global
environment by itself is not treated as a security boundary for hostile code.

## Compiler pipeline

The feature fits after parsing and during checking; it does not add a
declaration-expansion phase:

```text
fileText(path)
    -> parse(path)
    -> checkModule(path)
         -> resolve and typecheck comptime block
         -> build canonical evaluation request
         -> evalComptime(request fingerprint)
         -> quote result as a synthetic expression
         -> typecheck quoted expression normally
    -> moduleInterface(name)
    -> generate checked CST
```

### Parser and CST

The parser adds a `comptimeExpr` node holding the contextual `comptime` token,
`do`, a normal block, and `end`. Its array children retain every source token.
The formatter and `cst.textOf` therefore continue to reproduce the user's
source exactly.

The evaluated result is attached through named, non-owning metadata such as
`node.comptimeExpansion`; it is not inserted into the CST's lossless array
children. Syntax tools continue to see the original block, while semantic
tools can inspect the expansion.

### Checker

The checker enters a comptime phase and a fresh lexical scope for the block. It
uses the normal expression, statement, flow, call, and return checking paths,
with additional phase checks for unavailable values and functions.

Type and module resolution performed while building reflection descriptors
uses the existing environment hooks. Those lookups record normal query
dependencies on project interfaces.

After evaluation, the checker constructs or parses a canonical synthetic
literal expression, attributes it to the `comptime` token, and checks that
expression in the surrounding runtime context. The synthetic node carries an
origin link for diagnostics and LSP hover.

### Generator and line numbers

The generator emits only the canonical quoted expression at the source line of
the `comptime` token. It emits none of the block body. Its existing forward-only
line synchronization inserts blank lines until the next source token, so the
generated file preserves the line-count invariant.

Canonical strings never contain raw newlines, and table literals are emitted
on one logical line. A large result may produce a long generated line; result
size limits prevent it from becoming unbounded.

Comptime function declarations erase to whitespace/newlines just like typed
declarations.

## Incremental query design

`evalComptime` is a derived query. Its semantic request fingerprint contains:

- the lowered and typechecked block or comptime function body;
- canonical captured values;
- semantic fingerprints of every reflected type;
- the target triple and ABI/layout version;
- syntax and runtime target settings that affect lowering;
- the compiler comptime API version.

Nominal fingerprints use declaration identity plus a semantic field/layout
fingerprint. They never use the process-local nominal counter by itself.

Resolving a type from another module records a dependency on that module's
exported type interface before evaluation. A body-only edit in that module does
not rerun the block. A reflected field or layout change does.

The query compares canonical quoted results for early cutoff. If a dependency
changes and reevaluation produces the same literal, downstream module
interfaces and generated artifacts retain their previous changed revision.

The first implementation caches results in the live query graph. Persistent
cache serialization belongs to the manifest-driven build cache and is not a
prerequisite for language semantics.

## Diagnostics

Reserve the NUPP24xx range for comptime:

- `NUPP2401`: runtime value is unavailable at comptime
- `NUPP2402`: operation or API is unavailable at comptime
- `NUPP2403`: comptime evaluation failed
- `NUPP2404`: comptime evaluation budget exceeded
- `NUPP2405`: result is not quotable
- `NUPP2406`: type has no layout for the selected target
- `NUPP2407`: comptime function used as a runtime value
- `NUPP2408`: comptime dependency cycle

Diagnostics point first to the source expression that requested evaluation.
Failures inside a helper include a bounded compile-time call stack with
definition locations. Errors in a quoted result point to the comptime block and
identify the result path, such as `result.fields[3]`, when useful.

## Generic-system interaction

Comptime does not replace, instantiate, or implicitly specialize normal
generics. A generic declaration is checked with symbolic type variables before
ordinary calls use it.

In the initial implementation, a comptime request must be closed after normal
name and type resolution. It cannot depend on an unresolved type parameter or
on a runtime generic argument. This keeps module interfaces independent of the
set of call-site instantiations.

Compile-time value parameters such as fixed array lengths may be designed
later as an explicit extension to the generic system, for example
`Matrix<T, const N: integer>`. They are not implicit comptime parameters and do
not change the meaning of existing `<T>` generics.

## Tooling behavior

- Formatting preserves the original comptime block.
- Hover shows the block's result type and a shortened canonical value when it
  is cheap to display.
- Go-to-definition and references inside a block use normal checker metadata.
- Semantic tokens classify `comptime` and comptime-only intrinsics/functions.
- Diagnostics are published through the existing incremental LSP path.
- Completion inside a block contains only bindings and APIs available in the
  comptime environment.
- Rename operates on source declarations and references, never on synthetic
  expansion tokens.

The LSP never evaluates a block on the UI/protocol loop. Evaluation goes
through the same budgeted query and worker path as batch checking.

## Implementation milestones

### C1: expression evaluation

- Add contextual grammar, CST nodes, recovery, formatting, and highlighting.
- Add checker phase tracking and compile-time-known literal/`const` values.
- Extract a block emitter from the existing generator.
- Implement the capability-limited evaluator and canonical scalar/table
  serializer.
- Attach and typecheck synthetic literal expansions.
- Preserve line count and source diagnostics.
- Add an in-memory `evalComptime` query and compute counters.

Exit test: scalar and table blocks execute, forbidden APIs fail, unchanged
results cut off invalidation, generated code runs on plain LuaJIT, and the
self-hosting fixpoint remains byte-identical.

### C2: layout and reflection

- Add target-aware `sizeof`, `alignof`, and `offsetof`.
- Define the versioned immutable `TypeInfo` schema.
- Add semantic type fingerprints and cross-module interface dependencies.
- Add reflection hover and completion.
- Test recursive types, declaration order, target keys, and body/interface
  invalidation separately.

Exit test: changing a reflected exported field reruns only dependent blocks;
changing an unrelated function body does not.

### C3: reusable comptime functions

- Give `@comptime` a checked function-declaration meaning.
- Erase comptime functions from runtime output.
- Add comptime call stacks, recursion limits, and direct-call checking.
- Keep functions file-private; evaluate whether cross-module helpers have a
  demonstrated need before designing their interface representation.

Exit test: helpers compose and recurse within budget, cannot escape as runtime
values, and failures retain definition and call-site locations.

### C4: isolation and build integration

- Move evaluation behind the worker protocol used by both CLI and LSP.
- Enforce memory, instruction, recursion, and result-size limits.
- Add worker crash/timeout recovery and cancellation.
- Integrate persistent results with the manifest build cache when that cache
  lands.
- Run adversarial evaluator and recorded LSP-session tests.

Exit test: a looping, memory-hungry, crashing, or cancelled block cannot hang
or terminate the compiler or language server.

## Test matrix

Every milestone extends these invariants:

- lexer/parser byte round-trip and error recovery
- formatter idempotency and token-fingerprint safety
- type checking of block locals, returns, calls, narrowing, and expected result
  types
- quote round-trips for strings, tables, key ordering, and boundary numbers
- rejection of cycles, metatables, unsupported values, and forbidden APIs
- deterministic iteration and repeated-build byte identity
- line-count-preserving generation and runtime traceback locations
- query compute counters for cache hits, dependency changes, and equal-result
  cutoff
- target-dependent layout cache separation
- LSP cancellation, overlays, diagnostics, hover, completion, and worker
  failure recovery
- self-hosted stage-one/stage-two fixpoint

## Open questions intentionally deferred

- Cross-module comptime functions
- Generic comptime functions and reflection over constrained type variables
- Compile-time value parameters in generic declarations
- Persistent cache format and eviction
- Quotable sized-integer cdata and identity-preserving immutable aggregates
- Whether trusted build configuration needs an explicit file-input capability

None of these questions requires an AST macro system or declaration splicing.
