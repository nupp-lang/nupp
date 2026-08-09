# Nupp comptime plan

## Decision

`comptime` is deterministic compile-time evaluation of ordinary nupp code. It
produces data values that the compiler quotes as ordinary source literals. It
does not expose the CST or AST, paste source text, generate declarations, or
inline runtime code.

The type system remains independent:

- Generic functions and nominal types use normal type parameters and are
  checked parametrically.
- `const` means that a binding or a named field cannot be reassigned, and
  carries a compile-time-known value where its initializer had one. That much
  is built, and is what `OPT-3` propagates through, including across a required
  module's immutable paths; immutability alone still does not make a runtime
  computation available at compile time.
- `comptime` is explicit at the point where evaluation is required. It is not
  how generics are implemented.

This separation keeps generic APIs understandable without executing user code
and keeps comptime out of module declaration discovery.

## Relationship to constant folding

`OPT-3` folds and propagates constants, and has since grown `//`, the bit
operators, and removal of loops that cannot run. It looks like a smaller
comptime and is not one, because the two carry opposite obligations:

```
 OPT-3                              comptime
 ─────────────────────────────────  ────────────────────────────────
 An -O1 rewrite                     A language construct
 Must be invisible                  Must be visible in the result
 Absent at -O0 and under `check`    Present at every level
 May decline silently               Owes a diagnostic when it cannot
```

Anything whose *meaning* depends on the compile-time value — a checked literal
type, a rejected out-of-range constant, a future `const N: integer` array length
— can never be a fold at any strength, because `-O0` must still compile the
program and `check` does not optimize. That is the line, and it does not move.

Two consequences run through the rest of this document.

The first is that folding has taken the cases it can reach, and this plan should
stop describing them as future work. §Compile-time-known values and the scalar
half of §Quotable results are largely built; §Generator and line numbers
describes a risk three landed passes have now retired.

The second cuts the other way. Folding has to prove a fact about the *running
program* — that this `string.format` is the real one, that this table has not
been written to — and often cannot, because the prelude declares those bindings
replaceable. Comptime never asks: nothing it evaluates is the running program,
and §Evaluation environment hands it frozen copies of the pure libraries, so the
function it calls is the real one by construction. That buys back a class of
cases folding provably cannot have, and is a second reason for C1 independent of
the table generation that motivated it. §What folding will not absorb in
[optimizations.md](optimizations.md) lists five such extensions; three of them —
pure library calls, interpolation, and reads of a `const` table — are cases a
block would simply have. The other two are not comptime's to rescue: one is
unreachable in any phase, and the layout intrinsics are blocked identically for
both, on §The layout model is the prerequisite, and it does not exist.

## Goals

1. Compute constants using familiar nupp control flow and functions. This is
   the goal that carries the feature; the others support it.
2. Expose target-aware `sizeof`, `alignof`, `offsetof`, and read-only type
   reflection. Depends on a layout model nupp does not have, and is a separate
   project reached through this one rather than a part of it — see §The layout
   model is the prerequisite, and it does not exist.
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
const CRC32: {integer} = comptime do
    const entries = {}
    for byte = 0, 255 do
        local acc = byte
        for _ = 1, 8 do
            acc = acc & 1 ~= 0 and 0xedb88320 ~ (acc >> 1) or acc >> 1
        end
        entries[byte + 1] = acc
    end
    return entries
end
```

A block has its own lexical scope. `return` returns from the comptime block,
not from the enclosing runtime function. Every reachable path must return
exactly one value in the first version. Multi-value comptime results are
deferred until normal multi-value semantics are complete.

The result replaces the block, as a table literal of 256 entries.

The example is a loop that accumulates on purpose. An earlier revision of this
plan opened with `(raw + CACHE_LINE - 1) // CACHE_LINE * CACHE_LINE`, which
`OPT-3` now folds where its operands are constants, so it no longer argues for
anything. Reaching for the smallest example is the wrong instinct here: the
smallest ones are exactly the ones folding has taken.

### Comptime functions

Reusable helpers arrive after expression blocks. A function annotated with
`@comptime` is typechecked like a normal function, is callable only while
evaluating comptime code, and emits no runtime declaration.

```lua
@comptime local function step(acc: integer): integer
    return acc & 1 ~= 0 and 0xedb88320 ~ (acc >> 1) or acc >> 1
end

const CRC32 = comptime do
    const entries = {}
    for byte = 0, 255 do
        local acc = byte
        for _ = 1, 8 do
            acc = step(acc)
        end
        entries[byte + 1] = acc
    end
    return entries
end
```

A helper is what folding cannot reach even in principle: `OPT-3` may fold a
whitelisted callee whose behaviour the compiler knows, and never a function the
user wrote.

The initial comptime-function implementation keeps them file-private. Exported
comptime functions would require their checked body or an evaluator artifact to
become part of a module interface; that is deferred until a concrete
cross-module use case justifies the extra interface and cache complexity.

Comptime functions may recurse within the evaluation budget. Generic comptime
functions are deferred until generic constraints can state what operations on
a type parameter are valid.

## Compile-time-known values

This section used to design a knownness lattice from scratch. Two now exist, and
the work is to reconcile them rather than to add a third.

The checker's is a type-level fact: a literal type carries `constant`, and
`immutablePath` records that every edge from a const root to an expression is
read-only (`check/expr.nupp`, `check/index.nupp`). The optimizer's is a scope
walk: `OPT-3` maps names and dotted paths to folded values, invalidating a path
when its root is replaced (`optimize.nupp`). The first is available to anything
that checks; the second exists only while a pass runs, and is deliberately
smaller than Lua's constant vocabulary — cdata, floats, and calls are excluded
because their representation, rounding, and errors are not a rewrite's business.

Comptime needs a third thing neither provides: a value that is known *and*
carries a comptime-only handle, such as a `TypeInfo`, which can be inspected
during evaluation but never quoted back. So the lattice is still:

```text
unknown at compile time
known quotable value
known comptime-only handle (for example TypeInfo)
```

but its first two rungs should be read off what the checker already records
rather than recomputed. The following can be compile-time-known:

- literals
- table constructors whose keys and values are all known
- pure operators over known operands
- `const` bindings and named fields initialized from known expressions,
  including through a required module's immutable paths
- results of comptime intrinsics and comptime functions

The exclusions the optimizer makes for its own reasons are not comptime's. A
float is not foldable into source because its rounding is the target's; it is
perfectly knowable inside an evaluator. Where the two disagree, comptime is the
looser of the two, and the narrow one is `OPT-3`.

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

The scalar half of this exists. `OPT-3` already emits a folded value as source
through one small function, with `%q` for strings and `%.0f` for integers, and
its integer range guard is the same exactness question this list is asking. What
is genuinely new is the table serializer and its ordering rules. Build the two as
one component with comptime as its second caller rather than beside each other:
`analysis.queries` records what the alternative cost when two consumers grew
their own copies of the same reasoning.

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

### The layout model is the prerequisite, and it does not exist

That paragraph is one sentence of specification and the largest single piece of
work in this document, so it is worth separating from the milestone that carries
it. **Nupp has no compile-time layout model.** It has deliberately declined to
build one.

`layoutof(T)` already answers what a struct's layout is — fields in declaration
order with offsets, sizes and padding — and answers it **at run time**, through
the FFI, caching per ctype. The checker builds only the field spec, "because
only the checker knows the declared field order and types. Everything numeric is
this platform's and is asked of the FFI at run time" (`check/ffi.nupp`). That is
not an unfinished version of compiler-owned layout. It is the opposite choice,
made because nupp compiles to portable Lua source: a size folded at compile time
is the *build host's* ABI baked into a file that may run somewhere else.

So `sizeof(T)` is not a small intrinsic waiting on the evaluator. Three things
have to exist first:

1. a target layout model — C ABI rules per target, owned by the compiler rather
   than asked of whatever FFI happens to be running;
2. a target selection that says which one a build is for, since the answer is
   meaningless without it;
3. a semantic type fingerprint in the module interface hash, so that changing a
   reflected field in another module invalidates the dependents that folded its
   layout. Without it this is a miscompile, not a stale answer — and
   §Cross-module optimization breaks incremental cutoff in
   [optimizations.md](optimizations.md) says the same thing from the other side.

This plan already assumes all three: §Incremental query design keys evaluation on
"the target triple and ABI/layout version". Naming them here is the correction —
they were assumed rather than scheduled, which made C2 read as though it were
mostly reflection plumbing.

Two consequences. C2 is not the cheap milestone; it is a separate project that
happens to be consumed by comptime, and it should be sequenced as one. And the
scalar intrinsics do **not** separate cleanly from the evaluator as a folding
extension, which an earlier reading of this plan suggested they might: they
separate from the evaluator, and land squarely on the layout model instead.

`reflect(T)` does not separate at all. Its only use that the scalar intrinsics do
not already cover is iterating `fields`, and iteration needs the evaluator. A
program reading `reflect(T).size` has written `sizeof(T)` the long way.

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

The frozen libraries are worth more than the isolation they were written for.
They are also what makes the pure standard library *usable* at compile time at
all. `OPT-3` cannot fold `string.format("%s/%d", name, 3)`, not because the fold
is hard but because `string` is declared `local` with writable fields in
`decls/prelude.d.nupp`, so a program may legally replace `string.format` and the
fold would be asserting what it returns. Inside a block that question does not
arise: the `string` in scope is the frozen copy the evaluator supplied, and the
program's binding is not involved.

That is why the same list disqualifies `tostring` from interpolation folding and
qualifies it here. It is one of two routes to the same class of results — the
other being to declare the pure standard-library surface immutable, which is
§Immutability must be declared in [optimizations.md](optimizations.md) and is a
language policy decision rather than an evaluator one. The two are worth keeping
distinct: the declaration reaches ordinary runtime code and costs a policy, and
comptime reaches only code written inside a block and costs an evaluator.

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

This is the part of the plan that has been de-risked rather than merely
unchanged. Three landed passes replace a construct with something shorter while
holding its lines, and the shape they converged on is available here: `OPT-3`
emits a selected `if` arm, and a loop it proves cannot run, as an empty `do`
block spanning the statement's opening and closing lines. Discarding a block body
and keeping its line span is therefore a solved problem with a worked example in
`gen.nupp`, not a novel one.

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

C1, C3 and C4 are one feature in three deliverable pieces: an evaluator, the
helpers that make it reusable, and the isolation that makes it safe to run in an
editor. C2 is not the fourth piece of that feature. It is a separate project —
see §The layout model is the prerequisite, and it does not exist — and it is
sequenced separately below
rather than presented as the next step after C1.

### C1: expression evaluation

- Add contextual grammar, CST nodes, recovery, formatting, and highlighting.
- Add checker phase tracking, reading compile-time-known values off what the
  checker records rather than recomputing them.
- Extract a block emitter from the existing generator.
- Implement the capability-limited evaluator and canonical scalar/table
  serializer, extending `OPT-3`'s scalar quoting rather than starting beside it.
- Attach and typecheck synthetic literal expansions.
- Preserve line count and source diagnostics, following the empty-`do` shape
  `OPT-3` already uses for a branch and a loop it discards.
- Add an in-memory `evalComptime` query and compute counters.

Exit test: scalar and table blocks execute, forbidden APIs fail, unchanged
results cut off invalidation, generated code runs on plain LuaJIT, and the
self-hosting fixpoint remains byte-identical.

### C2: layout and reflection

Blocked on a compile-time layout model, which nupp has deliberately not built.
The first three items are that project; the rest is the milestone this section
used to describe, and none of it starts until they land.

- Define a target layout model: C ABI rules the compiler owns, rather than
  answers asked of whichever FFI is running.
- Define target selection, since a layout is meaningless without knowing whose.
- Add semantic type fingerprints to the module interface hash, so that changing
  a reflected field in another module invalidates whoever folded its layout.
  This is a correctness prerequisite and not a performance one: there is no
  deoptimization, so a stale layout is a miscompile.
- Then: target-aware `sizeof`, `alignof`, and `offsetof`.
- Then: the versioned immutable `TypeInfo` schema, plus reflection hover and
  completion.
- Test recursive types, declaration order, target keys, and body/interface
  invalidation separately.

Exit test: changing a reflected exported field reruns only dependent blocks;
changing an unrelated function body does not.

Decide before starting whether `layoutof` and `sizeof` should both exist. One
answers at run time from the running platform and one at compile time from a
declared target, and they will disagree whenever a build is cross-compiled —
which is the point of the second, and a bug report waiting to be filed about the
pair. Naming that difference is cheaper than explaining it later.

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

## What starting this should wait for

`plans/optimizations.md` requires a benchmark before a pass is built rather than
after, and the rule has already paid: the FFI group sat in a priority slot,
tagged as a real win, until `bench/ffi-hoisting.lua` measured 1.00x and removed
it. The equivalent discipline here is that comptime should be started against a
program that needs it, not against the expectation that programs will.

What that means concretely, since "demonstrated need" is otherwise a phrase that
approves everything:

- **A workload that builds a table.** Loops and recursion that accumulate are
  the case nothing else can reach, and the case C1 exists for. One real
  program wanting one real generated table is the evidence; the CRC example in
  §Expression blocks is an illustration and not that evidence.
- **Not a workload that wants a constant.** Those keep arriving and keep being
  taken by something cheaper. `//` and the bit operators were comptime-shaped
  until `OPT-3` folded them. `string.format` over constants is comptime-shaped
  and would also be answered by declaring the pure standard library immutable,
  which is one prelude change against an evaluator, a worker and a budget.
- **Not the layout intrinsics.** They are the layout model, which is its own
  project and does not need this one.

Two nearby pieces of work shrink the residue further and should be checked
before the estimate is trusted. [layout.md](layout.md) answers field names,
offsets and sizes at run time, which covers much of what `reflect` was for
without any evaluator; and `import-c` already brings a C header's constants
across, which is one of the usual reasons a systems language grows comptime.

None of this argues the feature away. It argues that the remaining core is
smaller, more specific, and more clearly the thing only comptime can do than the
milestone list suggests — and that the first version should be aimed at exactly
that, rather than at the constants that keep turning out to have cheaper answers.

## Open questions intentionally deferred

- Cross-module comptime functions
- Generic comptime functions and reflection over constrained type variables
- Compile-time value parameters in generic declarations
- Persistent cache format and eviction
- Quotable sized-integer cdata and identity-preserving immutable aggregates
- Whether trusted build configuration needs an explicit file-input capability
- Whether `layoutof` and a compile-time `sizeof` should coexist, and what a
  cross-compiled build promises when they disagree

None of these questions requires an AST macro system or declaration splicing.
