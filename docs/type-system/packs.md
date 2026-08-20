# Type packs

A type pack describes a Lua value sequence. Function parameters and results,
expanded call arguments, assignments, returns, varargs, and coroutine transfers
all use the same representation. A tuple type such as `{number, string}` is
still a table; `(number, string)` is a sequence of two values.

```nupp
local function apply<A..., R...>(callback: function(A...): R..., ...: A...): R...
    return callback(...)
end
```

::: rationale
Correlation is flow state rather than part of a type, because a type carrying it
would leak into every signature mentioning a correlated local and make two
identically typed values non-interchangeable. Keeping it in the flow makes it
precise where it is observable and absent where it is not — which is why storing
a result or returning results separately drops it.
:::

## Syntax

```nupp
()                  -- no values
(number, string)    -- two fixed values
(boolean, R...)     -- a fixed head and generic tail
...number           -- zero or more numbers
A...                -- a heterogeneous generic pack
```

Pack binders follow ordinary type binders and are available on functions,
function types, and aliases:

```nupp:playground
local function apply<A..., R...>(callback: function(A...): R..., ...: A...): R...
    return callback(...)
end

local type Adapter<A..., R...> = function(A...): R...
local type Pair = Adapter<(number, string), (boolean, integer)>
```

A pack is not a value type. Writing one as a field or local annotation is
NUPP2121.

## Lua value-list adjustment

Every non-final expression in a list contributes one value. A final call or
`...` contributes its complete pack. Parentheses force one value. Missing
assignment slots receive `nil`, and surplus slots are truncated. Calls apply
the same rules before generic inference and argument checking, so expanding a
two-result call into a one-parameter function still reports NUPP2007.

```nupp
local function pair(): (number, string)
    return 1, "one"
end

local n, s = pair() -- number, string
local first = (pair()) -- number
local a, b = pair(), true -- number, boolean
```

## Correlated alternatives

A union of parenthesized packs selects a complete sequence, not independent
unions for each column:

```nupp
local protected: function<A..., R...>(callback: function(A...): R..., A...): ((true, R...) | (false, any))
```

Destructuring assigns a shared correlation to the bindings. Testing the first
result for truthiness or literal equality narrows every sibling to the same
arm. Copying the discriminator keeps the correlation; assigning to a correlated
binding invalidates that binding's link.

## Pack compatibility

Fixed heads compare in order. Homogeneous tails check every remaining fixed
slot and compatible tails. Generic unification binds one binder to one complete
actual sequence, including a zero-length sequence. Result packs are covariant;
function parameter packs are checked contravariantly. A complete pack union
fits a target only when every possible source arm fits it.

NUPP2010 reports incompatible heads, tails, alternatives, `select` indices, and
coroutine transfers. NUPP2121 reports misplaced binders and packs used outside
a sequence position.

## Protected calls, selection, and unpacking

`pcall` and `xpcall` preserve a callback's heterogeneous result pack. Their
success and failure sequences remain correlated, so testing `ok` reveals the
success values or error value without widening the entire result to `any`.

`select("#", ...)` returns an integer. A constant positive or negative index
returns the exact suffix; an invalid constant index is NUPP2010. A dynamic
index retains a homogeneous union of possible elements. `unpack` returns exact
slots for a tuple table and a homogeneous tail for an array, with constant
bounds producing an exact slice.

`unpackof` also appends a computed tuple or array in the final position of a
tuple construction:

```nupp
local type Prepend<Value, Values> = {Value, unpackof Values}
```

Algorithms that inspect or transform a complete pack use a `comptime function`
with `typepack` parameters and the `nupp.types` pack API.

## Coroutine protocols

A function can declare what it yields and what a resumed yield receives:

```nupp
local function worker(start: number): string yields(number, string) resumes(boolean)
    local again: boolean = coroutine.yield(start, "paused")
    return tostring(again)
end

local co: thread<(number), (boolean), (number, string), (string)> = coroutine.create(worker)
```

The four thread packs are start arguments, resume arguments, yielded values,
and final returns. A local newly created handle checks its first transfer
against the start pack and later transfers against the resume pack. Successful
resume values are the correlated union of yielded and final packs; failure is
`(false, any)`. Bare `thread` remains protocol-erased.

## Ownership and provenance

Every fixed slot keeps its ownership mode, and a substituted generic pack keeps
the modes of its actual slots. Generic forwarding also carries the source of a
borrowed slot, so forwarding does not let a borrow outlive its owner.

Lua truncation is allowed only for non-affine values. Parenthesizing a
multi-result call, ignoring a call statement, truncating an assignment or
argument list, count-only selection, or slicing a pack is NUPP2605 when any
discarded slot is owned, pinned, or a still-generic potentially affine slot.
A correlated owner returned by `pcall` becomes a live obligation only in its
success arm.
