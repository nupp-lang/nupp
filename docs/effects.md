# Effect contracts

::: note Most code does not need @effects
The compiler infers effects for visible functions automatically. Add
`@effects` when an API needs a reviewed contract, when a visible implementation
must not silently gain effects, or when bodyless or foreign code needs a trusted
summary. Do not add it mechanically to ordinary helpers or data types.
:::

An effect contract describes what a function may observe or change in addition
to its input and return types. Types answer which values cross a call boundary;
effects answer what else can happen while the call is in progress.

```nupp:playground
@effects(reads = {"value"}, returns = {"1=value"})
local function identity(value: table): table
    return value
end
```

This contract says that `identity` reads `value` and that its first return is
the same table as `value`. It does not write through the table, change its
shape or metatable, let it escape, allocate, yield, raise, or invoke opaque
external behavior.

`@effects` is type-erased. It adds no runtime guard and changes no calling
convention. Its consumers are the checker and optimizations that need to know
whether a call can invalidate a proof.

## Complete upper bounds

An `@effects` contract is a complete upper bound, not a list of interesting
effects and not an instruction to infer the omitted members.

```nupp
@effects()
local function constant(): integer
    return 42
end
```

`@effects()` means no observable effects in the effect model. Every list is
empty and every boolean is false. If the body performs an omitted effect, the
checker reports `NUPP2112`.

```nupp
@effects()
local function mutate(values: {integer})
    values[1] = 2
end
```

The contract above is rejected because the body writes through `values` and,
conservatively, may change its shape. The corresponding complete contract is:

```nupp
@effects(writes = {"values[*]"}, shapes = {"values"})
local function mutate(values: {integer})
    values[1] = 2
end
```

Declaring more than the body currently does is valid. That is what makes a
contract an upper bound: an implementation may become less effectful without
changing its contract. Declaring less is invalid because a caller could then
make an unsound decision from the missing fact.

## Visible and opaque implementations

The meaning of an effect annotation depends on whether its implementation is
visible.

- Nupp function with a body: inferred, propagated, then checked against the
  annotation.
- `cdef function`: trusted declaration; there is no Nupp body to inspect.
- Bodyless function binding in `.d.nupp`: trusted declaration.
- Visible function without `@effects`: inferred summary is available to
  same-file analysis.
- Unknown or unresolved call: worst case (`top`).

A visible body cannot use an annotation to hide what it does. A declaration
without a body necessarily crosses a trust boundary, just as an FFI type
signature does: the compiler records the promise but cannot prove the foreign
implementation honors it.

```nupp
@effects(reads = {"source[*]"}, writes = {"destination[*]"}, external = true)
cdef function copyBytes(destination: voidptr, source: voidptr, count: uint64): int32
```

`external = true` says that the call may interact with state outside the
parameter-rooted paths in the contract. Omit it only when the declaration's
implementation really is contained by the other members.

For a bodyless Nupp declaration, `@effects` can be combined with `const`:

```nupp
-- clock.d.nupp
@effects(external = true)
const monotonicNow: function(): number

return {monotonicNow = monotonicNow}
```

The two promises are independent. `@effects` describes calling the value;
`const` says the binding continues to hold that same value. This trusted use
of `const` belongs on bodyless declaration surfaces such as `.d.nupp` files.
Do not apply it to an ordinary module merely to suggest that the module is
stable: the promise is shallow and says nothing about mutation of its fields.

## Contract members

Every argument is named. The contract is closed: an unknown member, a repeated
member, a list member that is not a literal array of strings, or a boolean
member that is not literally `true` or `false` is `NUPP2112`.

### Path-valued members

Each of these names a set of rooted paths the call may touch:

- `reads`: state the function may observe through a rooted path.
- `writes`: existing state the function may write through a rooted path.
- `shapes`: tables whose key set or dense-array boundary may change.
- `metatables`: values whose metatable or metatable-dependent behavior may
  change.
- `escapes`: arguments that may remain reachable after the call returns.
- `calls`: symbolic callees carried by a declared or propagated summary.
- `returns`: result positions that alias an input path.

### Boolean members

Each of these answers yes or no for the whole call:

- `allocates`: may allocate a table, closure, or other modeled object.
- `yields`: may suspend the current coroutine.
- `raises`: may raise instead of returning normally.
- `external`: may perform opaque behavior outside the modeled paths.

All eleven members are optional. Omission means an empty list or `false`, not
unknown.

## Paths and roots

Paths are symbolic strings. Use these canonical roots:

| Form | Meaning |
| --- | --- |
| `parameter` | The parameter value itself |
| `parameter[*]` | An element or field reached through the parameter |
| `self` | A method receiver |
| $capture | State reached through a captured local |
| $capture[*] | An element or field reached through captured state |
| $global | State reached through a global declaration contract |

Examples:

```nupp
@effects(reads = {"destination", "source", "source[*]"}, writes = {"destination[*]"}, shapes = {"destination"})
local function appendAll(destination: {string}, source: {string})
    for _, value in ipairs(source) do
        destination[#destination + 1] = value
    end
end
```

The current checker treats path entries as opaque strings after validating
that their container is an array and each entry is a string. It does not yet
reject a noncanonical path spelling. Consumers compare paths exactly, so use
the forms documented here: `"value"` and `"value[*]"` are distinct facts, and
one does not imply the other.

That exactness matters for visible bodies. Merely evaluating a parameter is a
root read; a recognized operation such as `rawget(value, key)` may additionally
produce an element read. When `NUPP2112` names a missing path, add the exact
fact only if it is part of the intended public contract.

`self`, `$global`, `calls`, and `metatables` are principally declaration
vocabulary today. Visible-body inference is parameter-centric; where it cannot
map state back to a parameter, it may report `$capture` or widen to unknown
instead of producing one of those more specific paths.

## Return aliases

`returns` uses `N=path`, where `N` is a one-based result position.

```nupp
@effects(reads = {"value"}, returns = {"1=value"})
local function first(value: table): table
    return value
end
```

This does not describe the result's type, which remains the return type
annotation. It says the result and argument may be the same object, which is the
fact alias analysis needs.

Multiple results name their positions independently:

```nupp
@effects(reads = {"left", "right"}, returns = {"1=left", "2=right"})
local function both(left: table, right: table): table, table
    return left, right
end
```

Return aliases propagate through direct visible calls:

```nupp
@effects(reads = {"value"}, returns = {"1=value"})
local function same(value: table): table
    return value
end

@effects(reads = {"value"}, returns = {"1=value"})
local function wrapped(value: table): table
    return same(value)
end
```

The second contract is verified from the first summary. A fresh table returned
from a function is not a return alias; describe the allocation with
`allocates = true`.

## Allocation, raising, and yielding

The non-memory flags describe behavior that cannot be located at one path.

```nupp
@effects(reads = {"value"}, allocates = true)
local function box(value: integer): {integer}
    return {value}
end
```

Table expressions and nested function values are allocations in the current
analysis.

```nupp
@effects(reads = {"message"}, raises = true)
local function fail(message: string): never
    error(message)
end
```

Direct calls to `error` and `assert` set `raises`. A direct
`coroutine.yield` sets `yields`. These facts also propagate from a directly
resolved visible callee.

For the user-facing control-flow model, including `nosuspend`, cancellation,
coroutine inheritance, and concurrent combinators, see
[suspension](start/suspension.md).
[Suspension handlers](start/suspension.md#hosts-supply-scheduling-policy) own
the scheduling policy. This page stays focused on complete `@effects`
contracts.

`raises` is an optimizer effect, not a replacement for API documentation.
Public failure conditions still belong in `@raises` docblocks, and `never`
still describes a function that never returns normally.

## Allocation and raising regions

`noalloc do ... end` requires every reachable modeled operation to avoid
Nupp- or Lua-managed allocation. `noraise do ... end` independently requires
that no modeled path raises a catchable Nupp or Lua error. Both are lexical
static checks and erase to ordinary `do` blocks without guards or protected
calls.

```nupp
local function quiet(value: uint32): uint32
    return nupp.math.u32.add(value, 1)
end

local result: uint32 = 0
noalloc do
    noraise do
        result = quiet(1)
    end
end
```

Visible functions are inferred to a pessimistic fixed point, including their
automatic cleanup. Exact direct exports transport only the positive
`noAllocate` and `noRaise` facts a dependent module observes; complete path,
escape, and return summaries remain file-local. Unknown callbacks, methods,
gradual calls, and uncontracted C functions prove neither fact.

A bodyless or foreign declaration may establish a fact with a trusted
`@effects` contract. That is a promise about the unseen implementation, not a
proof about an operating system, driver, or process-wide allocator. A visible
body is still checked against its contract.

## Writes, shapes, and metatables

`writes` and `shapes` answer different questions:

- `writes = {"values[*]"}` says an entry may receive a different value.
- `shapes = {"values"}` says the set of entries or array boundary may change.

The current inference deliberately classifies an indexed parameter assignment
as both. It does not try to prove that `values[1] = replacement` replaces an
already-present slot rather than inserting or removing one. This conservative
choice may reject an optimization, but it cannot authorize one from a shape
fact that was too narrow.

Writes through a nonlocal table are summarized under `$capture`; writes to a
table local to the function do not become caller-visible path effects unless
that table escapes.

`metatables` is primarily declaration-facing today. It lets a foreign or
bodyless contract say that behavior derived from a metatable can change. A
consumer that depends on ordinary raw table behavior must stop when a relevant
metatable effect is possible.

## Escape facts

An escape says that an argument may remain reachable somewhere the caller does
not control after the call returns. Storing an argument into captured state,
global state, or through another reference is conservatively an escape.

```nupp
local saved: {table} = {}

@effects(reads = {"value"}, writes = {"$capture[*]"}, shapes = {"$capture"}, escapes = {"value"})
local function remember(value: table)
    saved[1] = value
end
```

Returning the argument is represented by `returns`, not `escapes`, because the
alias remains explicit in the call's results.

An escape does not itself say the value is later mutated. It says that a later
proof cannot assume the caller owns the only reference.

## Calls and fixed-point propagation

The checker collects visible functions in the file, identifies direct calls by
definition rather than spelling, and repeatedly joins callee effects into
callers until the summaries stop changing. Recursive and mutually recursive
groups therefore converge to one conservative fixed point.

Parameter-rooted paths are substituted at a call site. If a callee writes
`items[*]` and the caller passes its own parameter `values`, the caller acquires
`writes = {"values[*]"}`. Effects on local scratch values stay local. Effects
that cannot be mapped safely widen toward captured or unknown state.

This propagation is currently file-local. Calls through imported modules,
computed function values, unresolved methods, or other definitions without a
summary are unknown. Effect summaries are not yet serialized into the
cross-module incremental interface.

The `calls` list itself is currently carried by declared summaries and
propagated into callers; inference does not enumerate every directly observed
call into that list. A direct known call contributes its callee's other effects,
while an unknown call widens the whole summary as described below.

## Unknown calls and `top`

Unknown code is pessimistic by default. An unresolved call widens the inferred
summary to `top`, meaning no finite `@effects(...)` contract can verify the
visible body.

```nupp
@effects(external = true)
local function run(callback: function())
    callback()
end
```

The example is rejected: `external = true` is an ordinary declared effect, not
a way to say "accept arbitrary unknown behavior." The checker cannot prove
what `callback` does, so the visible implementation cannot claim a complete
finite contract.

The current analysis recognizes a deliberately small set of builtins rather
than treating every prelude function as unknown:

- `type`, `tonumber`, `select`, and `rawequal`;
- `rawget`, `rawlen`, `ipairs`, `pairs`, and `next`;
- `error` and `assert` as raising;
- `coroutine.yield` as yielding.

Everything else needs a directly resolved visible summary or remains unknown.
A same-file function definition takes precedence over this list. The fallback
recognition is otherwise spelling-based today, so do not rely on an unresolved
value shadowing one of these names when writing a verified contract.

## Contract verification

For each visible function carrying `@effects`, the checker:

1. creates parameter-rooted alias classes for direct local aliases;
2. walks the body conservatively, without entering nested function bodies;
3. propagates summaries from directly resolved callees;
4. repeats propagation to a fixed point across the file;
5. checks that every inferred path, flag, and return alias is present in the
   declared contract.

The comparison is set containment. Order and duplicate path strings have no
semantic effect after normalization, although repeating a named member such as
two separate `reads = ...` arguments is invalid.

The first missing fact is reported as `NUPP2112`, for example:

```text
@effects contract is missing shapes = "values"
```

An unknown call instead reports that the contract calls code with unknown
effects. The annotation points at the function declaration; optimizer remarks,
when applicable, point at the call or mutation that stopped a proof.

## Inference without an annotation

Visible functions do not need `@effects` merely so the compiler can analyze
them. The checker infers a summary whether or not an annotation is present, and
same-file optimizations may use that inferred summary.

Add `@effects` when the contract itself is valuable:

- an API boundary should make side effects reviewable;
- a visible implementation should be prevented from silently growing new
  effects;
- a bodyless or C declaration needs a trusted summary;
- a future implementation must preserve a stable optimization interface.

Do not mechanically annotate every private helper. An inferred private summary
can change with its body; a declared complete contract becomes an obligation
that every later edit must continue to satisfy.

## Optimizer interaction

The numeric `ipairs` pass is the first consumer. It lowers a loop only after a
separate dense-entry and alias proof succeeds. Calls in the containing body are
then checked pessimistically:

- `top` or unresolved calls stop the rewrite;
- `external`, `yields`, or a metatable effect stops it;
- a `shapes` effect mapped to the iterated array stops it;
- captured or unresolved shape effects stop it.

An effect contract cannot force the rewrite. The array must still be a visible
dense literal with a static bound, its binding must not be exposed elsewhere,
and all the pass's other proof obligations must hold. Use `-O1 --remarks` or
`-O2 --remarks` to see `OPT-2` explain why it rewrote or declined a loop.

See [Performance](tooling/performance.md) for levels, remarks, pass controls,
and the benchmark behind that restriction.

## Effects, stability, relaxation, and ownership

These mechanisms answer different questions:

- `@effects`: what may happen while this value is called?.
- `const`: will this bodyless binding keep the same value?.
- `@relax` / `--relax`: which observable guarantee may an optimization change?.
- affine and borrowed types: who must release a resource, and what it may
  outlive.

An effect summary does not imply stability, purity does not imply ownership,
and ownership does not imply a call cannot raise or yield. State each boundary
with the mechanism that actually describes it.

## Current conservative limits

The effect system is intentionally useful before it is a full program IR. Its
current limits are part of the contract with users:

- propagation follows direct, definition-resolved calls in one file;
- alias classes are flow-insensitive and cover direct local assignments and
  declared return aliases, not arbitrary heap paths;
- there is no CFG/SSA-sensitive effect query yet;
- path strings use canonical conventions but are not yet grammar-validated;
- builtin fallback recognition is spelling-based after same-file resolution;
- full imported effect summaries are not yet part of incremental interface
  hashes; the checked suspension guarantee is, including nominal methods;
- unknown calls widen to `top` rather than accepting an optimistic annotation;
- trusted C and `.d.nupp` declarations are only as correct as their author.

These choices lose optimization opportunities. They are safe defaults: when
the compiler cannot establish a fact, it declines the transformation instead
of manufacturing a proof.

## Complete member example

This declaration demonstrates the whole surface. Real contracts should include
only the effects the implementation may actually perform.

```nupp
@effects(
    reads = {"source", "source[*]", "$global"},
    writes = {"destination[*]", "$capture[*]"},
    shapes = {"destination", "$capture"},
    metatables = {"destination"},
    escapes = {"destination"},
    calls = {"$global.callback"},
    returns = {"1=destination"},
    allocates = true,
    yields = true,
    raises = true,
    external = true
)
cdef function process(destination: voidptr, source: voidptr): voidptr
```

Because this is a `cdef function`, the compiler trusts the declaration. The
same annotation on a visible Nupp function would be checked as an upper bound
on its inferred body effects.

## FAQ

### Does every function need `@effects`?

The checker infers effects for visible functions whether or not they carry
`@effects`. Add a contract only when its complete upper bound belongs to the
API or must remain stable across implementation changes. [Inference without an
annotation](#inference-without-an-annotation) explains the boundary, and
[trusted declarations](#visible-and-opaque-implementations) cover code
whose body is unavailable.

### Do effect contracts add runtime work?

`@effects` is erased after checking. It adds no guard, wrapper, allocation, or
calling-convention change. The compiler uses the summary to reject an invalid
contract and to decide whether an [optimization
proof](#optimizer-interaction) remains valid around a call.

### Do effects replace ownership contracts?

Effects describe what may happen during a call; ownership describes which
value carries a cleanup, access, or lifetime obligation. A function may be
effect-free while forwarding an affine value, or effectful while accepting
only GC-managed values. See [ownership and affine
types](ownership.md#public-capability-contracts) for the separate public
capability contract.

## Diagnostic checklist

When an effect contract reports `NUPP2112`:

1. Read the missing member or unknown-call explanation literally.
2. Decide whether the implementation should perform that effect.
3. If yes, add the exact path or boolean to the public contract.
4. If no, change the implementation or call a directly summarized helper.
5. Do not use `external = true` to suppress an unknown visible call; it does
   not mean "unchecked."
6. Re-run `nupp check` before looking at optimizer remarks.

For bodyless declarations, review the implementation on the other side of the
boundary: the checker cannot do that verification for you.

## Diagnostics

- **NUPP2710**: a `noalloc` region can reach a modeled allocation.
- **NUPP2711**: a `noraise` region can reach a catchable error path.

- **NUPP2112**: an effect annotation member is not one the contract accepts, or
  a boolean member is not literally `true` or `false`.

## Next

- [ownership.md](ownership.md): the other contract a bodyless declaration
  carries.
- [performance.md](tooling/performance.md): what a summary lets a pass prove.
