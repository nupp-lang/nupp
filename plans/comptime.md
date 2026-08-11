# Nupp comptime plan

## Decision

`comptime` is deterministic compile-time evaluation of ordinary nupp code. It
produces values that the compiler normally quotes as ordinary source literals.
It does not expose the CST or AST, paste source text, or generate declarations.
A compiler-owned opaque result may instead be serialized as a runtime value by
the closed, type-directed [materialization](materialization.md) layer. Comptime
still produces a value and never chooses or observes what source represents it.

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
both, on §Layout intrinsics, and the model they need.

## Goals

1. Compute constants using familiar nupp control flow and functions. This is
   the goal that carries the feature; the others support it.
2. Expose read-only semantic type reflection: what a declaration says, which the
   checker already knows in full and which no layout model is needed to answer.
3. Expose target-aware `sizeof`, `alignof`, and `offsetof`. Separate from goal 2
   and dependent on a layout model nupp does not have — see §Layout intrinsics,
   and the model they need. Reached through this feature rather than part of it.
4. Preserve deterministic builds, the line-count invariant, incremental
   cutoff, and responsive editor tooling.
5. Give comptime code the same type checking and diagnostics as runtime code.
6. Erase every comptime construct from generated Lua except its quoted or
   compiler-materialized result.

## Non-goals

Two lists, because they are two different commitments and an earlier revision
ran them together. Confusing them makes the plan read as though nupp had decided
never to generate code, which is not the decision being taken here.

**Excluded from the language, not merely from this feature.** These stay
excluded whatever else is built, because each of them makes a program's meaning
depend on text a reader cannot see:

- AST or CST access
- quoting or splicing source code
- expression macros, templates, and `@inline`
- compiler lifecycle hooks
- arbitrary `require`, filesystem, environment, clock, random, process, or
  network access

Consequently, comptime will not materialize metamethod declarations produced
by another dialect's macro system. `import-tl` must eject those as explicit
contracts or visible translation residue; see
[metamethods.md](../docs/metamethods.md#deliberate-exclusions).

**Outside comptime, and possibly a separate feature later.** These are not
things the expression evaluator does. Saying so is an architectural boundary,
not a refusal:

- declaration or module generation
- derives
- automatic optimization or specialization of runtime functions

Materialization does not change this list. It emits an expression that
constructs one explicitly typed runtime value; it cannot add a declaration or
module, and it does not implicitly specialize an existing runtime function.
Its provider set is closed and compiler-owned. See
[materialization.md](materialization.md) for the boundary and its PEG and
type-directed-codec proving cases.

Comptime does not generate declarations. Compiler-owned derives, or a future
restricted declaration-generation facility, may be specified independently and
may consume the same semantic reflection model, dependency tracking, cache
fingerprints, and determinism guarantees this plan builds.

### What a derive would be, and why it is not this

The shape worth reserving room for:

```nupp
@derive(Debug, Default, JSON)
local record User
    @json(name = "user_id")
    id: integer
    name: string
end
```

A derive phase would read an already-checked declaration and its annotations,
validate that the fields support what is being asked, and synthesize a narrow
set of methods, interfaces, or constants. It is a different phase from
expression evaluation, reached at a different point, and producing a different
kind of output — which is precisely why it should not be reached by making the
evaluator able to return declarations.

The first ones are compiler-owned: `Debug`, `Default`, single-field `From`, and
`JSON`. If user-defined derives later earn their place, the interface is a
restricted semantic provider that accepts immutable `TypeInfo` and produces
constrained declaration IR — structural generation under a checked contract,
not source text and not an AST. `@soa` belongs in the same category.

The compiler-owned phase and its first `Debug`, `Default`, `From`, and `JSON`
providers are specified in [derives.md](derives.md). What this plan owes that
phase is the semantic reflection model in §Semantic reflection, which is why
that section is written to be consumed by something other than a comptime
block.

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

The initial comptime-function implementation keeps them file-private, because
exporting one means putting its checked body or an evaluator artifact into a
module interface, with the cache complexity that implies.

That is a staging decision and not a design position. A helper nobody else can
call is a helper of limited use, and "reusable computation" is one of the things
this feature is for, so **cross-module comptime functions are an expected
extension** rather than an open question — the first version defers the interface
representation, it does not decide against it. C1 and C3 should avoid choices
that would make exporting one awkward later.

Comptime functions may recurse within the evaluation budget.

Type-driven helpers do not have to wait for generic comptime functions. A helper
can take a `TypeInfo` as an ordinary value:

```lua
@comptime local function schema(info: TypeInfo): Schema
```

which is the reflection-consuming shape most of the interesting cases want, and
needs nothing from the generic system. Generic comptime functions — `@comptime
function f<T>(...)` — remain deferred until generic constraints can state what
operations on a type parameter are valid. Separating the two matters because the
first is reachable in C3 and the second is not.

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

The serializer is canonical, and canonical here has to mean exact rather than
tidy. A quoted value is source that will be parsed back, so any rule that is
merely conventional is a rule the round trip can lose:

- strings use escaped single-line literals;
- an integral number in the exact range emits as an integer, matching what
  `OPT-3` already does;
- a non-integral number emits in a **round-trip** format — the shortest spelling
  that reads back bit-identically, `%.17g` being the safe fallback and LuaJIT's
  default `%.14g` being *not* good enough. A value that cannot round-trip is
  rejected rather than approximated;
- negative zero is emitted as `-0.0`;
- NaN and infinities are rejected initially;
- a table's array part is its entries `1..n` for the largest `n` with no hole;
  every other key, integer keys past the first hole included, is a keyed entry.
  Sparseness therefore has one spelling rather than depending on how the
  evaluator happened to build the table;
- keyed entries use a stable ordering by key kind and value;
- **a table reachable by more than one path is rejected**, with NUPP2405, rather
  than being quoted as two independent tables. The earlier wording — "table
  identity and aliasing are not preserved" — describes silently changing what a
  program means, which is the one thing this plan is otherwise careful never to
  do. Identity-preserving aggregates can be designed later; until then, sharing
  is an error the author can see, not a fact they have to know.

The scalar half of this exists. `OPT-3` already emits a folded value as source
through one small function, with `%q` for strings and `%.0f` for integers, and
its integer range guard is the same exactness question this list is asking. What
is genuinely new is the non-integral formatting and the table serializer. Build
them as one component with comptime as its second caller rather than beside each
other: `analysis.queries` records what the alternative cost when two consumers
grew their own copies of the same reasoning.

Quoting a table creates a normal fresh runtime table when the generated module
loads. It does not embed a mutable compiler-owned object.

### Materializable results

A compiler-owned opaque value has no literal spelling and does not weaken the
rules above. When the `comptime` expression has a directly declared expected
runtime type, that type may select a provider from the compiler's closed
materializer table. The provider finalizes the live opaque value into a
canonical, acyclic blueprint in the evaluator worker and serializes it as one
runtime expression during generation.

The provider defines a partial type-level relation from its closed opaque
result family to accepted explicit runtime types. This is not subtyping or a
general conversion; the checker makes the expression's runtime type exactly
the written expected type only when that relation succeeds. The formal rules
and no-slot/factory distinction are specified in
[materialization.md](materialization.md#the-materialization-relation).

This is not a general escape from quotability. User types cannot register a
provider; a block cannot return source, syntax, declarations or a runtime
binding; and removing the explicit runtime type produces a diagnostic rather
than inferred code generation. The complete phase, cache, provenance and
admission rules are specified in [materialization.md](materialization.md).

A captured constant table is likewise a canonical snapshot of its initializer,
not a reference to runtime table state. `const M.config = {...}` gives the block
the value the initializer described; a later write to a non-const field of that
table is not visible to an evaluation that already happened, and must not be,
since evaluation order against module initialization is not something a program
should be able to observe.

The checker infers the quoted literal's type using the ordinary expression
checker and validates it against the surrounding expected type. Comptime does
not bypass assignment, return, or field checks.

## Reflection and layout intrinsics

The public intrinsics are:

```lua
reflect(T): TypeInfo             -- target-independent
sizeof(T): integer               -- target-specific
alignof(T): integer              -- target-specific
offsetof(T, fieldName): integer  -- target-specific
```

Their type arguments are parsed and resolved as type positions, so aliases,
qualified project types, and instantiated nominal types work without a
corresponding runtime value. `fieldName` must be a compile-time-known string.

The comment column is the important thing on that list, and an earlier revision
of this plan missed it. These are two features that happen to take the same kind
of argument. `reflect` asks what a declaration *says*, which the checker already
knows in full. The other three ask what a value *measures* on some machine,
which nothing in nupp currently knows at compile time. Only the second group is
blocked, and treating them as one milestone blocked the first group on a
prerequisite it does not have.

### Semantic reflection

`reflect(T)` returns an immutable public descriptor rather than the mutable
tables used internally by `nupp.compiler.types`. It is target-independent and needs no
layout model: everything in it is a fact the checker established while checking
the declaration.

```lua
{
    kind = "record",
    name = "User",
    qualifiedName = "accounts.User",
    fields = {
        {name = "id", type = <TypeInfo>, annotations = {...}},
        {name = "name", type = <TypeInfo>, annotations = {...}},
    },
}
```

Schema 2 covers fields and their types, declaration order, checked typed
annotations and their values or referenced-type edges, generic arguments,
unions and intersections, interfaces, shapes and indexers, function signatures
and packs, ownership wrappers, arrays, pointers, C types, and nominal names. It
uses one indexed, acyclic `types` array, so recursive semantic graphs can cross
the worker protocol without leaking checker objects or allocation identities.
Layout facts are not members of this descriptor. Where a target is selected and
the type has a layout, they are available separately, so that a reader can tell
which answers travel with the program and which travel with the machine.

Field order is declaration order. Recursive types are represented by stable
read-only indexed views, not recursively copied tables. A `TypeInfo` handle can
be inspected, deterministically iterated and compared during comptime
evaluation but cannot be returned as a quoted runtime value. Its fingerprint
hashes the canonical semantic graph, not process-local nominal identifiers.

Reflection is read-only data processing. It cannot add fields, methods, types,
or declarations. Reflection of an unresolved generic type variable is rejected
initially; reflection operates on concrete resolved types.

Every reflection schema change increments a comptime API version that
participates in cache keys.

This descriptor is the shared asset of the plan. A future derive phase consumes
exactly this (§What a derive would be), and so would a schema or serialization
helper; designing it as comptime's private convenience would mean designing it
twice.

`reflect` does still need the evaluator, on the other axis: its only use the
scalar intrinsics do not already cover is iterating `fields`, and iteration is
C1. A program reading `reflect(T).size` has written `sizeof(T)` the long way.

### Layout intrinsics, and the model they need

`sizeof`, `alignof`, and `offsetof` accept only types with a defined runtime
layout for the selected target. They use compiler-owned layout information,
not ambient host `ffi.sizeof`. A request for an erased or target-unsupported
type is a checked error.

That is one sentence of specification and the largest single piece of work in
this document. **Nupp has no compile-time layout model.** It has deliberately
declined to build one.

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
they were assumed rather than scheduled.

So these three intrinsics are a separate project that comptime consumes, and are
sequenced as C2b below. The scalar intrinsics also do **not** separate from the
evaluator as a folding extension, which an earlier reading of this plan suggested
they might: they separate from the evaluator and land on the layout model
instead.

## Evaluation environment

Comptime execution receives a fresh capability-limited environment containing:

- `assert`, `error`, `ipairs`, deterministic `pairs`, `select`, `tonumber`,
  and `type`
- an explicit allowlist of deterministic functions from `math`, `string`,
  `table`, and `bit`, as frozen or per-evaluation copies
- the compiler-provided reflection and layout intrinsics
- captured known constants serialized into the request

**An allowlist, named function by function, not "the pure portions of" a
library.** The phrase a previous revision used is a description rather than a
specification, and it decides nothing at the edges — `math.random` is impure,
`os.clock` is obviously out, but `table.sort` with a caller-supplied comparator
is a question, `string.gsub` with a function replacement is another, and
`math.fmod` versus `%` on negative operands is a third. Each of those has a right
answer and the phrase supplies none of them. The list also becomes part of the
comptime API version, so adding to it is a cache-key change and a deliberate act.

`tostring` is deliberately absent from the first list. `tostring(t)` on a table
or function yields `table: 0x...`, which is a process address: it varies between
runs of the same compiler on the same input, so a block using it would break
determinism and repeated-build byte identity. Comptime should provide its own
conversion that answers only for the quotable scalars and raises on anything
else, rather than the ambient one. The same reasoning rejects `#` on a table
whose sparseness is unknown to it, and any other operation whose answer is the
allocator's rather than the program's.

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
private toolchain mode. That wants [suspension.md](suspension.md) and a process
library under it: a worker the language server waits on must not block its
loop, and killing a hung one needs process control `os.execute` cannot give.
The worker accepts a serialized request and returns a serialized value or
diagnostic. This prevents an infinite loop, evaluator crash, or excessive
allocation from taking down the LSP. A limited Lua global environment by
itself is not treated as a security boundary for hostile code.

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
         -> quotable result: attach and typecheck a synthetic literal
         -> opaque result: validate its explicit materialization relation
                           and lower under the active build context
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

After evaluation, an ordinary quotable result follows the existing path: the
checker constructs or parses a canonical synthetic literal expression,
attributes it to the `comptime` token, and checks that expression in the
surrounding runtime context. The synthetic node carries an origin link for
diagnostics and LSP hover.

A compiler-owned opaque result follows the separate
[materialization](materialization.md) path. The checker requires a directly
declared expected runtime type, selects a provider by resolved identity, and
validates the finalized blueprint's result and action-slot relation. It does
not construct a synthetic function or declaration during checking. Check and
build run the same target- and optimization-keyed lowering query; check discards
the output, while build may reuse it. Thus checking cannot accept a blueprint
whose backend or generated expression fails only when build reaches it.

### Generator and line numbers

The generator emits only the canonical quoted expression, or the structured
runtime expression returned by a closed materializer, at the source line of the
`comptime` token. It emits none of the block body. Its existing forward-only
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

The query compares canonical finalized results for early cutoff: the literal
spelling for a quotable value, or the provider-versioned blueprint fingerprint
for an opaque one. If a dependency changes and reevaluation produces the same
result, downstream module interfaces and generated artifacts retain their
previous changed revision.

The first implementation caches results in the live query graph. Persistent
cache serialization belongs to the manifest-driven build cache and is not a
prerequisite for language semantics.

## Diagnostics

Reserve the NUPP24xx range for comptime:

- `NUPP2410`: runtime value is unavailable at comptime
- `NUPP2411`: operation or API is unavailable at comptime
- `NUPP2412`: comptime evaluation failed
- `NUPP2413`: result is not quotable
- `NUPP2414`: type has no layout for the selected target
- `NUPP2415`: comptime function used as a runtime value
- `NUPP2416`: comptime dependency cycle

The range starts at 2410 rather than 2401 because 2401 and 2402 were already
taken, by `carray` and `layoutof` in `check/ffi.nupp`. Reserving "the NUPP24xx
range" was a reservation of codes that were not free, and it took landing C1 to
notice.

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

[Type-level computation](type-level-computation.md) is the separate proposal
for reducing an open type to another type during that resolution. It shares
semantic member facts and fingerprints with reflection, but no evaluator,
worker, environment, recursion budget, or result protocol with comptime.

Compile-time value parameters such as fixed array lengths may be designed
later as an explicit extension to the generic system, for example
`Matrix<T, const N: integer>`. They are not implicit comptime parameters and do
not change the meaning of existing `<T>` generics.

## Tooling behavior

- Formatting preserves the original comptime block.
- Hover shows the block's result type and a shortened canonical value or
  materializer-owned blueprint summary when it is cheap to display.
- Go-to-definition and references inside a block use normal checker metadata.
- Semantic tokens classify `comptime` and comptime-only intrinsics/functions.
- Diagnostics are published through the existing incremental LSP path.
- Completion inside a block contains only bindings and APIs available in the
  comptime environment.
- Rename operates on source declarations and references, never on synthetic
  expansion tokens.

The LSP must never evaluate a block on the UI/protocol loop. C4 moves the
landed direct evaluator behind the same budgeted worker path for editor and
batch checking.

## Implementation milestones

C1, C2a, C3 and C4 are one feature: an evaluator, the reflection it reads, the
helpers that make it reusable, and the isolation that makes it safe in an editor.
C2b is not part of that feature. It is a separate project reached through this
one — see §Layout intrinsics, and the model they need.

### C1: expression evaluation

- Add contextual grammar, CST nodes, recovery, formatting, and highlighting.
- Add checker phase tracking, reading compile-time-known values off what the
  checker records rather than recomputing them.
- Extract a block emitter from the existing generator.
- Implement the capability-limited evaluator against a named allowlist, and the
  canonical serializer, extending `OPT-3`'s scalar quoting rather than starting
  beside it.
- Attach and typecheck synthetic literal expansions.
- Preserve line count and source diagnostics, following the empty-`do` shape
  `OPT-3` already uses for a branch and a loop it discards.
- Add an in-memory `evalComptime` query and compute counters.
- **Minimum worker isolation, if comptime is reachable from the LSP at all**:
  evaluation out of process, an instruction budget, a wall-clock timeout, and
  crash recovery. This did not land with the otherwise complete C1 evaluator
  and is now the first part of C4 rather than an invariant the implementation
  falsely claims today.

Exit test: scalar and table blocks execute, forbidden APIs fail, unchanged
results cut off invalidation, generated code runs on plain LuaJIT, the
self-hosting fixpoint remains byte-identical, and a non-terminating block fails
the one request rather than the server.

### C2a: semantic reflection

Target-independent, and not blocked on anything. Everything here is a fact the
checker established while checking the declaration.

- Define the versioned immutable `TypeInfo` schema over the checker's full
  structural vocabulary: fields and field types, declaration order, annotations,
  generic arguments, unions, interfaces, function signatures, nominal identity.
- Add semantic type fingerprints and cross-module interface dependencies, so a
  reflected change invalidates its dependents and a body-only edit does not.
- Add reflection hover and completion.
- Test recursive types, declaration order, and body/interface invalidation
  separately.

Exit test: changing a reflected exported field reruns only dependent blocks;
changing an unrelated function body does not.

Design it as a shared asset. A derive phase (§What a derive would be) and any
schema or serialization helper consume this same descriptor, so it should not be
shaped around what a comptime block finds convenient.

### C2b: layout intrinsics

Blocked on a compile-time layout model, which nupp has deliberately not built.
The first two items are that project, and nothing after them starts first.

- Define a target layout model: C ABI rules the compiler owns, rather than
  answers asked of whichever FFI is running.
- Define target selection, since a layout is meaningless without knowing whose.
- Then: target-aware `sizeof`, `alignof`, and `offsetof`, and the layout facts
  exposed alongside `TypeInfo` rather than inside it.
- Test target keys and layout cache separation.

Decide before starting whether `layoutof` and `sizeof` should both exist. One
answers at run time from the running platform and one at compile time from a
declared target, and they will disagree whenever a build is cross-compiled —
which is the point of the second, and a bug report waiting to be filed about the
pair. Naming that difference is cheaper than explaining it later.

### C3: reusable comptime functions

- Give `@comptime` a checked function-declaration meaning.
- Erase comptime functions from runtime output.
- Add comptime call stacks, recursion limits, and direct-call checking.
- Support helpers taking a `TypeInfo` parameter, which is the reflection-driven
  shape and needs nothing from the generic system.
- Keep functions file-private for now, while avoiding decisions that would make
  exporting one awkward: cross-module helpers are an expected extension, and
  what is deferred is their interface representation.

Exit test: helpers compose and recurse within budget, cannot escape as runtime
values, and failures retain definition and call-site locations.

### C4: isolation and build integration

The landed C1 evaluator runs directly. C4 first supplies the floor C1 specified
but did not ship — out-of-process evaluation, a timeout and crash recovery —
then hardens and integrates it. Closed materialization does not expose a public
opaque provider before that floor exists.

- Move evaluation behind an isolated worker for CLI and LSP.
- Generalize the worker protocol across CLI and LSP.
- Enforce the remaining limits: memory, recursion, and result size.
- Add cancellation, and recovery from the failure modes the floor does not cover.
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

## Deferred, and the difference between the two kinds

**Expected extensions**, deferred for staging rather than doubt. Design decisions
in C1 and C3 should keep the way clear for them:

- Cross-module comptime functions. What is deferred is the interface
  representation, not whether helpers should be reusable.
- **Compile-time value parameters**, such as `Matrix<T, const N: integer>`. Worth
  naming as the one significant capability ordinary type parameters do not
  replace: nupp's parametric generics already cover what Zig reaches for
  `comptime T: type` to express, so this is the actual gap between the two
  models rather than a rounding error in it. Still an explicit extension to the
  generic system, not an implicit comptime parameter.
- Compiler-owned derives, consuming the same `TypeInfo` — see §What a derive
  would be.

**Open questions**, genuinely undecided:

- Generic comptime functions and reflection over constrained type variables
- Persistent cache format and eviction
- Quotable sized-integer cdata, and identity-preserving immutable aggregates —
  which is the door left open by rejecting shared references rather than
  silently duplicating them
- Whether trusted build configuration needs an explicit file-input capability
- Whether `layoutof` and a compile-time `sizeof` should coexist, and what a
  cross-compiled build promises when they disagree
- Whether user-defined derives ever earn a restricted semantic provider API

None of these questions requires an AST macro system or declaration splicing.
