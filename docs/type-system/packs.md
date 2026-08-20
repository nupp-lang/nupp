# Type packs

A type pack describes a sequence of Lua values. Function parameters and
results, expanded call arguments, assignments, returns, varargs, and coroutine
transfers all use one representation for it.

```nupp:playground
local function apply<A..., R...>(callback: function(A...): R..., ...: A...): R...
    return callback(...)
end

local function pair(): (number, string)
    return 1, "one"
end

local n, s = apply(pair)
print(n, s)
```

A tuple type such as `{number, string}` is still a table, and something holds
it. `(number, string)` is two values in a row, and nothing does.

## Syntax

A pack is written in the position that accepts a sequence, and it takes one of
these forms:

| Pack | Meaning |
| --- | --- |
| `()` | no values |
| `(number, string)` | two fixed values |
| `(boolean, R...)` | a fixed head and a generic tail |
| `...number` | zero or more numbers |
| `A...` | a heterogeneous generic pack |
| `unpackof T` | the slots of a computed tuple or array |

Pack binders follow ordinary type binders, and they are available on functions,
function types, and aliases:

```nupp
local type Adapter<A..., R...> = function(A...): R...
local type Pair = Adapter<(number, string), (boolean, integer)>
```

A pack is not a value type. Writing one as a field or a local annotation is
reported. See [generics.md](generics.md) for how a binder is bound at a call
site.

## Lua value-list adjustment

Every non-final expression in a list contributes one value. A final call or
`...` contributes its complete pack, and parentheses force it back to one:

```nupp
local n, s = pair() -- number, string
local first = (pair()) -- number
local a, b = pair(), true -- number, boolean
```

Missing assignment slots receive `nil`, and surplus slots are truncated. Calls
apply the same rules before generic inference and argument checking, so
expanding a two-result call into a one-parameter function is still reported:

```nupp
local function one(value: number): nil
end

one(pair()) -- NUPP2007: the second result has nowhere to land
```

## Correlated alternatives

A union of parenthesized packs selects a complete sequence, not an independent
union per column:

```nupp
local protected: function<A..., R...>(
    callback: function(A...): R...,
    A...
): ((true, R...) | (false, any))
```

Destructuring assigns a shared correlation to the bindings. Testing the first
result for truthiness or literal equality narrows every sibling to the same
arm. Copying the discriminator keeps the correlation, and assigning to a
correlated binding invalidates that binding's link. See
[narrowing.md](narrowing.md#narrowing-tests) for the tests that select an arm.

::: deepdive
Correlation is flow state rather than part of a type. A type that carried it
would leak into every signature mentioning a correlated local, and it would
make two identically typed values non-interchangeable, so a function taking
`(boolean, string)` could not be given one produced anywhere else.

Keeping it in the flow makes it precise where it is observable and absent where
it is not, which is why storing the results in a table or returning them
separately drops it. Copying the discriminator into another local keeps it,
because the copy still stands for the same test.
:::

## Pack compatibility

Fixed heads compare in order. Homogeneous tails check every remaining fixed
slot and compatible tails. Generic unification binds one binder to one complete
actual sequence, including a zero-length one:

```nupp
local function run<A...>(callback: function(A...): nil, ...: A...): nil
    return callback(...)
end

run(function(): nil end) -- A... binds to the empty pack
run(function(flag: boolean): nil end, true) -- and to (boolean) here
```

Result packs are covariant and function parameter packs are checked
contravariantly. A complete pack union fits a target only when every arm of it
fits.

Incompatible heads, tails, alternatives, `select` indices, and coroutine
transfers are reported against the pack, and misplaced binders and packs used
outside a sequence position are reported against where they were written.

## Protected calls, selection, and unpacking

The Lua functions that take a value list apart keep the pack rather than
flattening it to `any`.

### Protected calls

`pcall` and `xpcall` preserve a callback's heterogeneous result pack. Their
success and failure sequences stay correlated, so testing `ok` reveals the
success values or the error value:

```nupp
local function parse(text: string): (integer, string)
    return #text, text
end

local ok, count, echoed = pcall(parse, "ready")
if ok then
    print(count + 1) -- count is integer and echoed is string here
end
```

### `select`

`select("#", ...)` returns an integer. A constant positive or negative index
returns the exact suffix, and an invalid constant index is reported. A
dynamic index retains a homogeneous union of the possible elements:

```nupp
local count = select("#", pair()) -- integer
local second: string = select(2, pair()) -- the exact suffix, (string)
```

### `unpack` and `unpackof`

`unpack` returns exact slots for a tuple table and a homogeneous tail for an
array, with constant bounds producing an exact slice. `unpackof` is its type
counterpart: it appends a computed tuple or array in the final position of a
tuple construction:

```nupp
local point: {number, number} = {1, 2}
local x: number, y: number = unpack(point)

local type Prepend<Value, Values> = {Value, unpackof Values}
```

Algorithms that inspect or transform a complete pack use a `comptime function`
with `typepack` parameters and the `nupp.types` pack API. See
[type-level-computation.md](type-level-computation.md#closed-and-generic-calls)
for how such a call closes once inference supplies its arguments.

## Coroutine protocols

A function declares what it yields and what a resumed yield receives:

```nupp
local function worker(start: number): string yields(number, string) resumes(boolean)
    local again: boolean = coroutine.yield(start, "paused")
    return tostring(again)
end
```

The handle carries four packs, in the order start arguments, resume arguments,
yielded values, and final returns:

```nupp
local co: thread<(number), (boolean), (number, string), (string)> =
    coroutine.create(worker)
```

A newly created local handle checks its first transfer against the start pack
and later transfers against the resume pack. Successful resume values are the
correlated union of the yielded and final packs, and failure is `(false, any)`.
Bare `thread` remains protocol-erased. See
[suspension.md](../concepts/suspension.md) for the effect side of the same
boundary.

## Ownership and provenance

Every fixed slot keeps its ownership mode, and a substituted generic pack keeps
the modes of its actual slots. Generic forwarding also carries the source of a
borrowed slot, so forwarding does not let a borrow outlive its owner.

Lua truncation is allowed only for non-affine values. Parenthesizing a
multi-result call, ignoring a call statement, truncating an assignment or
argument list, count-only selection, or slicing a pack is reported when any
discarded slot is owned, pinned, or a still-generic potentially affine slot:

```nupp
local record Resource
end

local function release(takes value: Resource): nil
end

local function acquire(): affine(Resource, release)
    return new Resource()
end

acquire() -- NUPP2605: the owner has nowhere to land

local value = acquire()
release(value) -- the obligation is discharged
```

A correlated owner returned by `pcall` becomes a live obligation only in its
success arm. See [ownership.md](ownership.md) for the model the modes come
from.

## FAQ

### Why is `{number, string}` not the same as `(number, string)`?

`{number, string}` is a tuple table: one value, allocated, indexable, and
storable in a field. `(number, string)` is two values in a row, which is what a
Lua function returns and what a call expands into. Only the tuple can be
annotated on a local, which is what the checker says when a pack is written
there.

### Can a pack be stored in a variable?

No. A pack exists only in a sequence position: parameters, results, a vararg,
an assignment's right side, or a coroutine transfer. Collect the values into a
tuple table with `{...}` when they need to be held, and expand them again with
`unpack`.

### Does `(f())` drop an owner?

It is reported when a discarded slot is owned or pinned. Parentheses
take the first value and truncate the rest, which Lua permits and Nupp allows
only for values carrying no cleanup obligation. See [Ownership and
provenance](#ownership-and-provenance) for the complete list of adjustments
that trigger it.

::: seealso
- [generics.md](generics.md) for how a pack binder is inferred at a call site
- [ownership.md](ownership.md) for the modes a slot carries
- [narrowing.md](narrowing.md#narrowing-tests) for the tests that pick a
  correlated arm
- [type-level-computation.md](type-level-computation.md) for `typepack`
  parameters and the `nupp.types` pack API
:::
