---
order: 250
redirects: reference/ownership
---

# Ownership and borrowing

Ownership tracks which value carries a cleanup obligation and where that
obligation is discharged. An affine value may be consumed exactly once, moved
into another affine location, or destroyed by the terminal function carried in
its type.

```nupp:playground
local record Mutex
    locked: boolean
end

-- Only `lock` creates this token; its terminal is the matching unlock.
local record LockToken
    mutex: Mutex
end

local function unlock(takes held: LockToken): nil
    held.mutex.locked = false
end

local type HeldLock = affine(LockToken, unlock)

local function lock(borrows mutex: Mutex): HeldLock borrows (mutex)
    assert(not mutex.locked)
    mutex.locked = true
    return new LockToken(mutex = mutex)
end

local function update(mutex: Mutex, write: boolean): nil
    local held = lock(mutex) -- `mutex` cannot move while `held` is live
    if not write then
        return -- lexical destruction calls `unlock(held)` on this path too
    end

    print("update while the lock is held")
end -- falling through also calls `unlock(held)`

local mutex = new Mutex(locked = false)
update(mutex, false)
assert(not mutex.locked)
```

Affinity is a public language facility. General cleanup policy remains ordinary
Nupp source. The core additionally defines the explicit `nupp.Closeable` lifecycle
and managed cells for dynamic aliases. See
[ownership.md](../concepts/ownership.md) for the annotations a caller writes.

## Declaring affine types

`affine(...)` is a built-in compile-time type-generator call. It takes one
representation and an optional cleanup, then produces a type:

```nupp
local type Owner<T, const cleanup: function> = affine(T, cleanup)
local type MustForward<T> = affine(T)
```

It introduces no table, wrapper, tag, vtable, or runtime cleanup slot. Two
applications with the same canonical representation and cleanup declaration are
the same type; equal function signatures are not enough, because different
cleanup declarations remain different identities. An application without a
cleanup is deliberately transfer-only, while an invalid cleanup name or
signature is an error. See [affine-types.md](affine-types.md) for the generator
in full, including its comptime counterpart.

## Named resource policies

Packages normally hide a representation and publish the policy they mean:

```nupp
local record SocketHandle
    descriptor: integer
end

local function closeSocket(takes socket: SocketHandle): nil
    close(socket.descriptor)
end

global type Socket = affine(SocketHandle, closeSocket)
```

There is no structural `Drop` inference. A foreign pointer or type with several
valid cleanup policies names one explicitly:

```nupp
cdef function malloc(size: uint64): voidptr
cdef function free(takes value: voidptr)

local function allocate(): affine(voidptr, free)
    return malloc(128)
end
```

`affine(voidptr)` says there is deliberately no local terminal.

## `nupp.Closeable` nominal lifecycle

An affine interface declares that conforming nominal types carry an inherent
terminal:

```nupp
affine interface nupp.Closeable
    terminal close: nosuspend function(takes self: nupp.Closeable): nil
end
```

A record must explicitly state `is nupp.Closeable`; matching method names do not
infer conformance. Construction then introduces `affine(T, T.close)` behavior,
and a bare owned `T` annotation carries it. Borrow-qualified parameter and
result positions refer to the representation instead of minting an owner.
Calling `close()` consumes the obligation. Resource-specific interfaces may
add non-consuming operations such as `flush()`.

An affine interface must declare one terminal. Its terminal consumes `self`,
returns `nil`, is non-suspending, and may raise. Interface composition rejects
competing terminal names. A record containing `nupp.Closeable` fields inherits their
aggregate obligations and destroys live fields in reverse declaration order.

## Terminal contract

A closed terminal has the exact shape:

```nupp
nosuspend function(takes Representation): nil
```

The terminal may raise. Automatic destruction keeps the first failure primary,
attempts the independent remaining cleanups, and attaches later failures as
suppressed errors. It may not suspend, because lexical destruction also runs at
non-yieldable boundaries.

Generic terminals use ordinary inference and bounds. A terminal is a const
function identity, not a runtime callback value or a string, which is what makes
`drop` a statically selected call. `nupp.attemptAll(value, operations...)` is
the ordinary way to author a single terminal that performs several independent
operations; the affine type still records only that one terminal identity.

## Introducing an owner

Runtime representation equality does not imply an implicit conversion from `T`
to an affine type over `T`, because that would let aliases mint duplicate
cleanup obligations. Ownership is introduced by a fresh annotated function
result, a record constructor result, a declared C output, a transfer, or audited
adoption:

```nupp
local record File
    descriptor: integer

    constructor(self, descriptor: integer): affine(File, File.destroy)
        self.descriptor = descriptor
    end

    function destroy(takes self): nil
        nativeClose(self.descriptor)
    end
end

local file = new File(nativeOpen("notes.txt"))
```

The constructor still builds and returns `File`; its result annotation adds the
obligation at that fresh introduction point. Methods on `File` remain available
directly, because the affine type has the same representation. See [unsafe
representation boundaries](#unsafe-representation-boundaries) for audited
adoption, which is reserved for a boundary no typed producer can describe.

## Consumption and lexical destruction

`drop owner` and `drop(owner)` consume an affine value and invoke its statically
selected terminal. Passing to `takes`, returning through a matching affine
result, or moving into another affine location transfers the obligation instead:

```nupp
local function peek(path: string): string
    local file = new File(nativeOpen(path))
    local head = file:read(16)
    drop file
    return head
end
```

Dropping a terminal-less affine value is reported, since there is nothing to
call.

Live terminal-bearing owners are destroyed at every lexical exit: fallthrough,
return, loop exit, outward `goto`, and errors. Bindings are acquired left to
right and destroyed right to left, and a successful move deactivates the source
exactly once:

```nupp
local function copy(from: string, to: string): nil
    local source = new File(nativeOpen(from))
    local sink = new File(nativeOpen(to))
    sink:write(source:read(4096))
end -- destroys `sink`, then `source`
```

An obligation still live on a path that leaves without discharging it is
reported.

### Exact extents with `with`

`with` gives an owner a stricter extent than its enclosing block. The
acquisition moves into a hidden slot, the visible binding is a scoped borrow,
and the same lexical cleanup machinery drops the hidden owner on every exit from
the body:

```nupp
with file = new File(nativeOpen("notes.txt")) do
    print(file:read(16))
end -- the hidden owner is destroyed here, not at the end of the function
```

See [exact-affine-scopes.md](../concepts/exact-affine-scopes.md) for what the
scoped binding may not do.

## Affine aggregates and closures

An affine value may be stored inside another value, and the container inherits
the obligation.

### Affine aggregates

A record containing affine fields is an affine aggregate:

```nupp
local record Session
    inbound: File
    outbound: File
end
```

Its synthesized cleanup plan consumes live fields in reverse declaration order
and attempts later fields after a failure. Field moves are path-sensitive, so a
field is tracked apart from the record holding it. A structural
`drop(takes self)` method may replace the synthesized behavior, but it must
discharge every affine field on every path.

### Single-shot closures

A closure with `takes (capture)` is an affine, single-shot callable:

```nupp
local file = new File(nativeOpen("notes.txt"))
local finish = function(): nil takes (file)
    print(file:read(16))
    drop file
end

finish() -- moves `file` into the invocation frame
```

Calling it moves captures into its invocation frame; dropping it destroys
captures without running the body. Borrowed captures use `borrows (source)` and
remain tied to their roots, and a `scoped` callback parameter proves that
borrowed captures do not escape the call.

## Borrowing and pinning

Two facilities give access without transferring an obligation, and they are
independent of each other.

### Borrowing

`borrows` grants call-scoped access without consuming the owner, and `exclusive`
adds sole-access proof for operations that may invalidate derived views:

```nupp
local function checksum(borrows file: File): integer
    return hash(file:read(4096))
end

local file = new File(nativeOpen("notes.txt"))
print(checksum(file)) -- `file` is still live and still owed a close
drop file
```

`T borrows (source)` records provenance on results and declared fields, and it
is the only way a rooted value leaves the scope that made it. Without it the
escape is reported:

```nupp
local function leak(borrows value: table): table
    return borrow(value) -- NUPP2608: a rooted value escapes its lifetime
end

local function view(borrows value: table): table borrows (value)
    return borrow(value)
end
```

### Pinning

`pinned(T)` pairs a pointer with a strong Lua anchor, so C may retain the
pointer under declared `retains` and `releases` contracts:

```nupp
unsafe do
    local callback = function()
    end
    local pointer = ffi.cast<voidptr>(callback)
    local handle = nupp.pin(pointer, callback)
end
```

`pinned(T)` is a built-in compile-time type-generator call, and
`nupp.pin(pointer, root)` is the runtime operation that proves and installs the
anchor. Raw pointer indexing and provenance reconstruction remain unsafe unless
a checked span supplies bounds and a root.

::: deepdive
Pinning is separate from affinity because the two answer different questions. An
affine obligation says who calls cleanup and when; a pin says the Lua garbage
collector may not collect the storage a C pointer names while C still holds
it. Folding them together would mean every pinned pointer also acquired a
terminal, which is wrong for the common case of a callback that C releases on
its own schedule, and it would leave a pointer into a collected buffer as the
first thing a program discovers with a segfault. See [NEP
4](../neps/0004-ownership.md) for more information.
:::

## Public capability contracts

Exported functions need explicit modes only for parameters that may carry a
nontrivial capability. Ordinary strings, numbers, and GC-managed records stay
unannotated, but an unconstrained public generic parameter states `takes`,
`borrows`, `exclusive`, or `scoped`, because callers may instantiate it with a
capability:

```nupp
local m = {}

function m.forward<T>(value: T): T -- NUPP2610: the contract is implicit
    return value
end

function m.send<T>(takes value: T): T preserves value
    return value
end

return m
```

A public forwarder also writes `preserves source`. Visible-body inference
remains a private implementation convenience rather than part of an implicit API
contract.

## Generic preservation

`preserves source` transports a source's complete capability through a result:

```nupp
local function forward<T>(takes value: T): T preserves value
    return value
end

local record Box<T>
    value: T
end

local function box<T>(takes value: T): Box<T> preserves value
    return new Box(value = value)
end
```

Movable cleanup obligations, transfer-only obligations, pins, and foreign
retentions move exactly once. Borrow roots and region provenance are reproduced
on the result instead, because several shared views may name the same root.

An unconstrained `T` may carry a movable capability, so a preserving public
function writes `takes`, and `borrows` there is reported. Copyable values
still pass through the same function without becoming affine. Preservation
follows one unambiguous path through records, tuples, optionals, unions,
intersections, identity-mapped and projected types, callable records, closures,
and result packs, and callable assignment keeps the exact result-to-parameter
relation rather than erasing or inventing one. Where the source type appears in
two result components, the checker reports it rather than guessing which
component owns the obligation.

## Regions and loop-carried capabilities

A loan names a place, and the checker decides overlap from the place path rather
than from the name a method happens to have.

### Loan places

Loans use a general place path: stable fields, tuple slots, dereferences,
constant or unknown indexes, checked intervals, and audited partitions. Sibling
fields, tuple slots, different constant indexes, and non-overlapping exact
intervals are disjoint. A parent overlaps every descendant, and unknown indexes,
bounds, and pointer arithmetic widen conservatively:

```nupp
local function pair(exclusive a: table, exclusive b: table): nil
end

local value = {}
pair(value, value) -- NUPP2607: two exclusive loans of the same place
pair({}, {}) -- fine: disjoint places
```

After validating runtime bounds, audited unsafe library code can attach an exact
interval to a child view:

```nupp
unsafe do
    local left = nupp.region(storage, leftView, 1, 8)
    local right = nupp.region(storage, rightView, 9, 16)
    writeBoth(left, right)
end
```

`nupp.region(parent, child, first, last)` erases to `child`. It grants no bounds
check of its own and therefore requires `unsafe do`, and dynamic bounds produce
an unknown overlapping interval. `nupp.mem.span` splitting uses the same algebra
rather than receiving ownership privilege from method names.

### Loop-carried capabilities

A loop back edge must re-enter its header with the same obligation, roots,
access, pin, retention, and live-region shape. Iteration-local borrows end
before the edge, and consuming an outer owner on a repeating path is
reported:

```nupp
local function run(again: boolean): nil
    local value = new File(nativeOpen("notes.txt"))
    while again do
        drop(value) -- NUPP2609: the second iteration has nothing to drop
    end
end
```

Carrying a newly exclusive child into the next iteration reports the same code.

Consuming and refilling one binding inside the same iteration is the legal
shape of that loop. The back edge then re-enters the header with a live owner
of the same obligation, and its fresh capability identity is tolerated exactly
when no borrow or region loan is live on either side of the edge, because no
loan can dangle across an edge that carries none:

```nupp
local frame = heap.allocate(ffi.typeof<uint8>(), size)
with scope = workers.scope() do
    for generation = 1, 60 do
        frame = scope:spawn(frame, generation, jobs.fill):await()
    end
end
drop frame
```

A borrow taken before the loop and held across it keeps the identity
comparison, and with it the report.

## Ownership in switch patterns

`case is T as whole` and direct field destructuring introduce const views of the
selector. Matching does not move the selector or duplicate an ownership
obligation, and the views last for the selected arm:

```nupp
local size = switch handle do
    case is File as file -> file:read(16)
    case is Buffer {length} -> length
    else -> 0
end
```

A block arm may `return` an owner under the ordinary return contract, or `yield`
a value to the switch merge. When a yield leaves a `with` region, its automatic
cleanup completes before evaluation resumes after the switch, as it does for
other control flow.

Pattern aliases are therefore convenient for reading nominal data, but they do
not create an independent affine owner. Use the explicit move or borrow
operations when an arm must transfer capability. See
[switch-expressions.md](../concepts/switch-expressions.md) for the binding forms
themselves.

## C interop

Affine wrappers erase at the ABI, so a C return can state `affine(T, cleanup)`
directly and an output slot can state `out value: affine(T, cleanup)*`:

```nupp
cdef function free(takes value: voidptr)
cdef function strdup(text: cstring): affine(voidptr, free)
```

The checker allocates physical output holders, returns logical affine values,
and preserves C parameter order.

`out view: T* borrows (source)` describes a borrowed output rooted in a shared
input, and several sources may be named in the parenthesized list. `Success<T,
N>` and `Failure<T, N>` describe when conditional outputs are initialized. These
status and borrow contracts are independent of the affine facility. See
[c-interop.md](../concepts/c-interop.md#describe-lifetime-behavior) for the
import side of the same contracts.

## Dynamic boundaries and managed cells

A nontrivial capability cannot disappear into `any` or an untyped call. Prefer
a typed wrapper or static borrow. When references must escape, `nupp.manage`
moves one self-contained exact obligation into an independently owned cell:

```nupp
local owner = nupp.manage(new Client())
local client = owner:alias()

local answer, problem = client:with(function(borrows value)
    return value:request()
end)
```

`managed(T)` is affine and closes its payload lexically. `alias(T)` is copyable,
does not extend custody, and points permanently at the same cell. The runtime
states are live, shared-borrowed, exclusive-borrowed, closing, closed, and
taken. State changes before cleanup or transfer, active borrows are released
even when callbacks raise, and close or take clears the payload and cleanup.

`with` provides a shared callback borrow, `withExclusive` provides an exclusive
one, `take` restores the original affine payload, and `close` exercises close
authority without making the alias an owner. `nupp.recoverAlias(anyValue)`
checks the unforgeable brand and yields `alias(unknown)`; `downcast<T>` then
checks its erased representation and exact cleanup policy. Failures return
`AliasError`, preserving success/error correlation.

Transfer-only owners, external loans, pins, and unmatched foreign retentions
cannot be managed because a cell could not discharge them independently.
`nupp.ManagedGroup` supplies runtime-sized heterogeneous cleanup by storing
aliases and closing them in reverse adoption order; `nupp.managedGroup()` creates
one. It contains one audited
release where static custody becomes the group's runtime invariant; the
compiler has no special case for the group.

### Managed cells across a reload

Generated modules publish stable cleanup-policy keys to the hot-reload
transaction. Removing or incompatibly changing a policy with live managed cells
rejects the patch. Close or take those cells first. Aliases remain tombstones
after terminal state and never select a replacement resource. See
[hot-reload.md](../guides/hot-reload.md) for the reload transaction.

## Unsafe representation boundaries

Audited adoption is reserved for boundaries where no typed producer can state
the policy:

```nupp
unsafe do
    local owner = unsafe adopt raw as affine(voidptr, free)
end
```

The reverse operation is also explicit:

```nupp
unsafe do
    local raw = unsafe release owner
end
```

`unsafe` grants only the representation assertion. The resulting affine value
still participates in normal move, borrow, and lexical-destruction checks, and
`unsafe release` consumes an obligation without running its terminal, which
makes the caller responsible for the resource from that line on.

## FAQ

### How does this compare to Rust's borrow checker?

The model is intentionally smaller. Relationships name ordinary values, so there
are no named lifetimes, no lifetime parameters, and no read-only shared
references, and everything not carrying a capability stays freely aliased and
garbage collected. See [NEP 4](../neps/0004-ownership.md) for what that
deliberately gives up.

### Can an owner be held across a suspension?

Yes. Affine fields have path-sensitive state, so a field is tracked apart from
the record holding it and a suspension cannot strand an obligation. A terminal
itself may not suspend, since lexical destruction also runs at non-yieldable
boundaries. See [suspension.md](../concepts/suspension.md) for those boundaries.

### Does an owner have to name its cleanup at every call site?

No. The terminal is part of the type, so `drop` selects it statically and
lexical destruction calls it without being written. What a call site does state
is the mode a parameter uses, and only when the parameter may carry a
capability.

::: seealso
- [ownership.md](../concepts/ownership.md) for the annotations a caller writes
- [affine-types.md](affine-types.md) for constructing the types this page moves
  around
- [exact-affine-scopes.md](../concepts/exact-affine-scopes.md) for `with` and
  its exact extent
- [c-interop.md](../concepts/c-interop.md#describe-lifetime-behavior) for the
  native side of a lifetime contract
- [NEP 4](../neps/0004-ownership.md) for the record of why the model is shaped
  this way
:::
