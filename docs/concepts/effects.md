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
convention. Its consumers are the checker and the optimizations that need to
know whether a call can invalidate a proof.

## Complete upper bounds

An `@effects` contract is a complete upper bound, not a list of interesting
effects and not an instruction to infer the omitted members.

```nupp
@effects()
local function constant(): integer
    return 42
end
```

`@effects()` means no observable effects in the effect model: every list is
empty and every boolean is false. If the body performs an omitted effect, the
checker reports `NUPP2112`.

```nupp
@effects()
local function mutate(values: {integer})
    values[1] = 2
end
```

That contract is rejected because the body writes through `values` and,
conservatively, may change its shape. The corresponding complete contract is:

```nupp
@effects(writes = {"values[*]"}, shapes = {"values"})
local function mutate(values: {integer})
    values[1] = 2
end
```

Declaring more than the body currently does is valid, which is what makes the
contract an upper bound: an implementation may become less effectful without
changing its contract.

::: deepdive
The asymmetry is deliberate. A caller reasons from what a contract does not
say, so a missing fact is the one error that cannot be made safe by checking
harder afterwards. An over-declared fact costs an optimization and nothing
else, and the author can tighten it whenever the narrower promise is worth
keeping.

What that costs is a contract that a rewrite can turn into a lie. That is why
the annotation is reserved for boundaries worth the maintenance, and why every
other function is inferred instead.
:::

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
implementation honors it. See [c-interop.md](c-interop.md) for the rest of what
a C declaration does and does not carry.

```nupp
@effects(reads = {"source[*]"}, writes = {"destination[*]"}, external = true)
cdef function copyBytes(destination: voidptr, source: voidptr, count: uint64): int32
```

`external = true` says the call may interact with state outside the
parameter-rooted paths in the contract. Omit it only when the declaration's
implementation really is contained by the other members.

For a bodyless Nupp declaration, `@effects` combines with `const`:

```nupp
-- clock.d.nupp
@effects(external = true)
const monotonicNow: function(): number

return {monotonicNow = monotonicNow}
```

The two promises are independent. `@effects` describes calling the value, and
`const` says the binding continues to hold that same value. This trusted use of
`const` belongs on a bodyless declaration surface such as a `.d.nupp` file. Do
not apply it to an ordinary module to suggest the module is stable: the promise
is shallow and says nothing about mutation of the module's fields.

## Contract members

Every argument is named, and the contract is closed. An unknown member, a
repeated member, a list member that is not a literal array of strings, or a
boolean member that is not literally `true` or `false` is `NUPP2112`.

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

Every member is optional, and omission means an empty list or `false`.

## Paths and roots

Paths are symbolic strings. Use these canonical roots:

| Form | Meaning |
| --- | --- |
| `parameter` | The parameter value itself |
| `parameter[*]` | An element or field reached through the parameter |
| `self` | A method receiver |
| `$capture` | State reached through a captured local |
| `$capture[*]` | An element or field reached through captured state |
| `$global` | State reached through a global declaration contract |

```nupp
@effects(reads = {"destination", "source", "source[*]"}, writes = {"destination[*]"}, shapes = {"destination"})
local function appendAll(destination: {string}, source: {string})
    for _, value in ipairs(source) do
        destination[#destination + 1] = value
    end
end
```

### Path exactness

The checker treats a path entry as an opaque string after validating that its
container is an array and each entry is a string. It does not yet reject a
noncanonical path, so use the forms above: consumers compare paths exactly, and
`"value"` and `"value[*]"` are distinct facts that do not imply each other.

That exactness matters for a visible body. Evaluating a parameter is a root
read, while a recognized operation such as `rawget(value, key)` may
additionally produce an element read. When `NUPP2112` names a missing path, add
that exact fact only if it belongs in the intended public contract.

### Declaration-only vocabulary

`self`, `$global`, `calls`, and `metatables` are principally declaration
vocabulary today. Visible-body inference is parameter-centric, so where it
cannot map state back to a parameter it reports `$capture` or widens to unknown
rather than producing one of those more specific paths.

## Return aliases

`returns` uses `N=path`, where `N` is a one-based result position.

```nupp
@effects(reads = {"value"}, returns = {"1=value"})
local function first(value: table): table
    return value
end
```

This does not describe the result's type, which remains the return type
annotation. It says the result and the argument may be the same object, which is
the fact alias analysis needs.

Multiple results name their positions independently:

```nupp
@effects(reads = {"left", "right"}, returns = {"1=left", "2=right"})
local function both(left: table, right: table): table, table
    return left, right
end
```

A return alias propagates through a direct visible call:

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
from a function is not a return alias; describe it with `allocates = true`.

## Allocation, raising, and yielding

The non-memory flags describe behavior that cannot be located at one path. A
table expression and a nested function value are both allocations in the current
analysis.

```nupp
@effects(reads = {"value"}, allocates = true)
local function box(value: integer): {integer}
    return {value}
end
```

A direct call to `error` or `assert` sets `raises`, and a direct
`coroutine.yield` sets `yields`. Both facts also propagate from a directly
resolved visible callee.

```nupp
@effects(reads = {"message"}, raises = true)
local function fail(message: string): never
    error(message)
end
```

`raises` is an optimizer effect, not a replacement for API documentation.
Public failure conditions still belong in `@raises` docblocks, and `never` still
describes a function that never returns normally.

For the user-facing control-flow model, including `nosuspend`, cancellation,
coroutine inheritance, and concurrent combinators, see
[suspension.md](suspension.md). See [Hosts supply scheduling
policy](suspension.md#hosts-supply-scheduling-policy) for who owns the
scheduling decision a `yields` contract permits.

## Allocation and raising regions

`noalloc do ... end` requires every reachable modeled operation to avoid Nupp-
or Lua-managed allocation, and `noraise do ... end` independently requires that
no modeled path raises a catchable Nupp or Lua error. Both are lexical static
checks and erase to ordinary `do` blocks, with no guard and no protected call.

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

A region that can reach a modeled allocation reports `NUPP2710`, and one that
can reach a catchable error path reports `NUPP2711`.

Visible functions are inferred to a pessimistic fixed point, including their
automatic cleanup. An exact direct export transports only the positive
`noAllocate` and `noRaise` facts a dependent module observes, while complete
path, escape, and return summaries stay file-local. An unknown callback, method,
gradual call, or uncontracted C function proves neither fact.

A bodyless or foreign declaration may establish a fact with a trusted `@effects`
contract. That is a promise about the unseen implementation, not a proof about
an operating system, a driver, or a process-wide allocator. A visible body is
still checked against its contract.

## Writes, shapes, and metatables

`writes` and `shapes` answer different questions:

- `writes = {"values[*]"}` says an entry may receive a different value.
- `shapes = {"values"}` says the set of entries or the array boundary may
  change.

Inference deliberately classifies an indexed parameter assignment as both. It
does not try to prove that `values[1] = replacement` replaces an already-present
slot rather than inserting or removing one, because a shape fact that was too
narrow could authorize an optimization, while one that is too wide can only
decline one.

A write through a nonlocal table is summarized under `$capture`. A write to a
table local to the function does not become a caller-visible path effect unless
that table escapes.

`metatables` is primarily declaration-facing today. It lets a foreign or
bodyless contract say that behavior derived from a metatable can change, and a
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

Returning the argument is represented by `returns` instead, because that alias
stays explicit in the call's results. An escape does not itself say the value is
later mutated; it says a later proof cannot assume the caller holds the only
reference. See
[ownership.md](../type-system/ownership.md#public-capability-contracts) for the
separate question of who must release a resource.

## Calls and fixed-point propagation

The checker collects the visible functions in a file, identifies direct calls by
definition rather than by name, and repeatedly joins callee effects into callers
until the summaries stop changing. A recursive or mutually recursive group
therefore converges to one conservative fixed point.

Parameter-rooted paths are substituted at a call site. If a callee writes
`items[*]` and the caller passes its own parameter `values`, the caller acquires
`writes = {"values[*]"}`. Effects on local scratch values stay local, and an
effect that cannot be mapped safely widens toward captured or unknown state.

This propagation is file-local. A call through an imported module, a computed
function value, an unresolved method, or any other definition without a summary
is unknown, because effect summaries are not yet serialized into the
cross-module incremental interface. See [modules.md](modules.md) for what that
interface does carry.

The `calls` list is carried by a declared summary and propagated into callers;
inference does not enumerate every directly observed call into it. A direct
known call contributes its callee's other effects, and an unknown call widens
the whole summary.

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

That example is rejected. `external = true` is an ordinary declared effect
rather than a way to accept arbitrary unknown behavior, so a visible
implementation whose callee cannot be proved still cannot claim a complete
finite contract.

The analysis recognizes a deliberately small set of builtins rather than
treating every prelude function as unknown:

- `type`, `tonumber`, `select`, and `rawequal`;
- `rawget`, `rawlen`, `ipairs`, `pairs`, and `next`;
- `error` and `assert` as raising;
- `coroutine.yield` as yielding.

Everything else needs a directly resolved visible summary or remains unknown. A
same-file function definition takes precedence over this list. The fallback
recognition is otherwise name-based today, so do not rely on an unresolved value
shadowing one of these names when writing a verified contract.

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

The first missing fact is reported as `NUPP2112`:

```text
@effects contract is missing shapes = "values"
```

An unknown call instead reports that the contract calls code with unknown
effects. The annotation points at the function declaration, while an optimizer
remark points at the call or mutation that stopped a proof.

## Inference without an annotation

A visible function does not need `@effects` for the compiler to analyze it. The
checker infers a summary whether or not an annotation is present, and same-file
optimizations use that inferred summary.

```nupp
local function append(values: {integer}, value: integer)
    values[#values + 1] = value
end
```

Add `@effects` when the contract itself is valuable: when an API boundary should
make its side effects reviewable, when a visible implementation should be
prevented from silently growing new effects, when a bodyless or C declaration
needs a trusted summary, or when a future implementation must preserve a stable
optimization interface. An inferred private summary changes with its body, while
a declared complete contract becomes an obligation every later edit must
satisfy.

::: deepdive
A region asks for proof where it matters, at a callback, a C boundary, or a
cleanup, rather than requiring an annotation on every function between there and
the operation. That is why an ordinary signature stays silent about effects.

It is the same reason there is no `async` coloring: one call site works with a
scheduler installed and without one, so a library never splits into two versions
of itself. See [suspension.md](suspension.md) for the guarantee that does travel
in a signature.
:::

## Optimizer interaction

The numeric `ipairs` pass is the first consumer. It lowers a loop only after a
separate dense-entry and alias proof succeeds, and the calls in the containing
body are then checked pessimistically:

- `top` or an unresolved call stops the rewrite;
- `external`, `yields`, or a metatable effect stops it;
- a `shapes` effect mapped to the iterated array stops it;
- a captured or unresolved shape effect stops it.

An effect contract cannot force the rewrite. The array must still be a visible
dense literal with a static bound, its binding must not be exposed elsewhere,
and every other proof obligation of the pass must hold. Use `-O1 --remarks` or
`-O2 --remarks` to see `OPT-2` explain why it rewrote or declined a loop, and
see [performance.md](../guides/performance.md#opt-2-numeric-ipairs) for the
benchmark behind that restriction.

## Effects, stability, relaxation, and ownership

Four mechanisms answer four different questions:

- `@effects`: what may happen while this value is called.
- `const`: whether a bodyless binding keeps the same value.
- `@relax` and `--relax`: which observable guarantee an optimization may change.
- affine and borrowed types: who must release a resource, and what it may
  outlive.

An effect summary does not imply stability, purity does not imply ownership, and
ownership does not imply a call cannot raise or yield. State each boundary with
the mechanism that describes it. See [ownership.md](ownership.md) for the
resource side of that split.

## Limits

The effect system is deliberately useful before it is a full program IR, and its
current limits are part of the contract with users:

- alias classes are flow-insensitive and cover direct local assignments and
  declared return aliases, not arbitrary heap paths;
- there is no CFG or SSA-sensitive effect query yet;
- imported effect summaries are not part of incremental interface hashes,
  although the checked suspension guarantee is, including nominal methods;
- a trusted C or `.d.nupp` declaration is only as correct as its author.

These choices lose optimization opportunities. They are safe defaults: when the
compiler cannot establish a fact, it declines the transformation instead of
manufacturing a proof.

## Complete contract

This declaration uses the whole surface at once. A real contract carries only
the effects its implementation may actually perform.

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

Because this is a `cdef function`, the compiler trusts the declaration. The same
annotation on a visible Nupp function would be checked as an upper bound on its
inferred body effects.

## Answering `NUPP2112`

When an effect contract reports `NUPP2112`:

1. Read the missing member or the unknown-call explanation literally.
2. Decide whether the implementation should perform that effect.
3. If it should, add the exact path or boolean to the public contract.
4. If it should not, change the implementation or call a directly summarized
   helper.
5. Do not reach for `external = true` to suppress an unknown visible call; it
   does not mean unchecked.
6. Re-run `nupp check` before looking at optimizer remarks.

For a bodyless declaration, review the implementation on the other side of the
boundary. The checker cannot do that verification for you.

## FAQ

### Does every function need `@effects`?

The checker infers effects for visible functions whether or not they carry
`@effects`. Add a contract only when its complete upper bound belongs to the API
or must remain stable across implementation changes. See [Inference without an
annotation](#inference-without-an-annotation) for the boundary, and [Visible and
opaque implementations](#visible-and-opaque-implementations) for code whose body
is unavailable.

### Do effect contracts add runtime work?

`@effects` is erased after checking, so it adds no guard, wrapper, allocation,
or calling-convention change. The compiler uses the summary to reject an
invalid contract and to decide whether an [optimization
proof](#optimizer-interaction) survives a call.

### Do effects replace ownership contracts?

Effects describe what may happen during a call; ownership describes which value
carries a cleanup, access, or lifetime obligation. A function may be effect-free
while forwarding an affine value, or effectful while accepting only GC-managed
values. See
[ownership.md](../type-system/ownership.md#public-capability-contracts) for the
separate public capability contract.

::: seealso
- [suspension.md](suspension.md) for the control-flow model behind `yields`
- [ownership.md](../type-system/ownership.md) for cleanup and lifetime
  obligations
- [c-interop.md](c-interop.md) for the trusted declarations a C boundary needs
- [performance.md](../guides/performance.md) for the passes that consume a
  summary
:::
