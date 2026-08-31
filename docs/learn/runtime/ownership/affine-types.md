---
order: 240
---

# Affine types

An affine type is a compile-time-generated view of an existing representation.
It adds a move or cleanup obligation to the checker without adding a runtime
wrapper.

```nupp
local record Mutex
    locked: boolean
end

local record LockToken
    mutex: Mutex
end

local function unlock(takes held: LockToken): nil
    held.mutex.locked = false
end

local type HeldLock = affine(LockToken, unlock)
```

## Cleanup identity is part of the type

`affine(LockToken, unlock)` looks like a function call because it is a built-in
compile-time type-generator call. It is never a runtime call:

- `LockToken` is a compile-time type value.
- `unlock` contributes its const function declaration identity, not a callback
  stored in each value.
- the result has the same runtime representation as `LockToken`.

Two functions with the same signature therefore create different affine types,
and aliasing a generated type does not create a new nominal identity:

```nupp
local type AlsoHeld = affine(LockToken, unlock) -- the same type as HeldLock
```

::: deepdive
Angle brackets apply a declared generic type such as `Box<T>`, and parentheses
call a compile-time type generator. Keeping those two operations visibly
distinct is what lets one syntax serve both the built-in generators and
user-defined comptime type functions, so a package that wants its own policy
constructor writes an ordinary `comptime function` rather than asking for a
language keyword. The cost is that `affine(T, cleanup)` reads like a call at a
glance, and the payment for it is that `nupp.types.affine` and every user
generator are written the same way. See
[type-level-computation.md](../../language/types/comptime-types.md) for the rest of the
comptime type surface.
:::

## Cleanup and transfer-only forms

The two forms are calls to the same generator:

```nupp
local type Owner<T, const cleanup: function> = affine(T, cleanup)
local type MustForward<T> = affine(T)
```

`affine(T, cleanup)` carries one obligation to invoke exactly `cleanup`, whose
type must be `nosuspend function(takes T): nil`. `affine(T)` carries an
obligation that may be moved, returned, released through an unsafe boundary, or
placed into another affine value, but it has no local cleanup and therefore
cannot be dropped.

Both forms erase to `T`. Neither evaluates `T` nor calls `cleanup` when the type
is constructed, and cleanup runs only when a runtime value of the generated type
is explicitly dropped or reaches automatic lexical destruction. See
[consumption and lexical
destruction](borrowing.md#consumption-and-lexical-destruction) for when that
happens.

## Constructors can introduce the policy

A record constructor may make the affine view the default result of `new`:

```nupp
local record File
    descriptor: integer

    constructor(self, descriptor: integer): affine(File, File.destroy)
        self.descriptor = descriptor
    end

    function read(self, count: integer): string
        return nativeRead(self.descriptor, count)
    end

    function destroy(takes self): nil
        nativeClose(self.descriptor)
    end
end

do
    local file = new File(nativeOpen("notes.txt"))
    print(file:read(128))
end -- calls File.destroy exactly once
```

The result annotation does not replace `File` with a wrapper. It says that this
constructor introduces one `File.destroy` obligation on the `File` it already
builds, so `file:read(...)` needs no common interface, forwarding object, or
conversion. `File.destroy` is a normal method declaration whose function
identity is used by the type and whose function value is registered for lexical
destruction.

The annotation must contain exactly one result and erase to the record being
constructed. Omitting it preserves ordinary GC-managed construction. Constructor
overloads may state different policies: argument overload selection happens
first, and the selected entry supplies its result policy. See [constructors and
result policies](../../language/types/records-and-structs.md#constructors-and-result-policies) for what else a
constructor result may say.

## Comptime type generators

A user-defined comptime type function can call the programmable counterpart of
the direct form:

```nupp
local comptime function MakeOwner(
    T: type,
    const cleanup: function
): type
    return nupp.types.affine(T, cleanup)
end

local type HeldAgain = MakeOwner(LockToken, unlock)
```

`nupp.types.affine` builds the same types `affine(...)` does, including the
transfer-only `nupp.types.affine(T)`. Its cleanup argument must come from a
const function parameter, so declaration identity stays static and unforgeable.

## Generic capability preservation

A generic need not know whether a value is affine. `takes` permits the checker
to move a capability when one is present, and `preserves` relates that
capability to the result:

```nupp
local function forward<T>(takes value: T): T preserves value
    return value
end
```

For an ordinary value this is an ordinary pass-through. For an affine value its
single obligation moves to the result rather than being copied, which is what
lets one generic API serve affine and ordinary types without overloads or an
`Affine` interface special case.

The relation reaches inside a type the result wraps, so a constructor that
stores its argument preserves the capability into the unique `T` component of
the result. See [generic
preservation](borrowing.md#generic-preservation) for the complete set of shapes
it follows and the ambiguity it refuses.

::: deepdive
Preservation is a separate relation rather than a property of the type, because
it is linear flow information and not a subtyping fact. A generic record is an
ordinary first-order application, and `preserves` supplies the conservation
proof beside it, which is why none of this needs higher-kinded generics. HKT
would only be relevant to an API abstracting over the container itself as a type
constructor, and it would still not supply the proof that the obligation moved
exactly once. See [NEP 4](../../../neps/0004-ownership.md) for more information.
:::

## FAQ

### Why track ownership when LuaJIT already has GC finalizers?

`ffi.gc` attaches runtime finalization to every resource and makes the garbage
collector discover and dispatch its cleanup. `luajit bench/ownership.lua`
compares that path with explicit cleanup around the same `malloc` and `free`; on
LuaJIT 2.1 for arm64, finalization costs roughly an order of magnitude more per
resource. Nupp's affine policy exists only during checking, adds no per-value
wrapper, finalizer registration, or tracing work, and [lexical
destruction](borrowing.md#consumption-and-lexical-destruction) performs like the
equivalent explicit cleanup within measurement noise.

Cleanup timing also controls capacity. The garbage collector sees a small Lua
wrapper, not the file descriptor, socket, lock, or native allocation behind it,
so a program can exhaust its file-descriptor limit before enough wrappers
trigger collection, or keep another task waiting on a lock whose unreachable
guard has not been finalized. An affine terminal runs at the scope boundary; a
finalizer remains useful only as a last-resort safety net.

### Why not call cleanup manually?

Calling `close`, `unlock`, or `free` directly works only when every return,
raised error, and transfer follows the protocol. An [affine
terminal](borrowing.md#terminal-contract) makes that protocol part of the type,
so the checker rejects a forgotten obligation, a second consumption, or a use
after the value moved.

### Does every Nupp value use ownership?

No. Strings, numbers, tables, and records without a nontrivial capability retain
ordinary Lua behavior and need no annotation, and a record constructor stays
ordinary unless its result introduces a policy. See [public capability
contracts](borrowing.md#public-capability-contracts) for the parameters that do
need a mode.

### Does an affine type change the runtime representation?

No. It adds no wrapper, cleanup field, tag, or vtable, and erases to its
representation, so a C pointer remains a C pointer and a struct keeps the
[layout declared at the boundary](../c-interop/index.md#type-mapping).

::: seealso
- [ownership.md](borrowing.md) for moves, borrows, pins, and lexical
  destruction
- [ownership.md](index.md) for the annotations a caller writes
- [c-interop.md](../c-interop/index.md#describe-lifetime-behavior) for
  stating an imported function's lifetime behavior
- [NEP 4](../../../neps/0004-ownership.md) for the record of why the model is shaped
  this way
:::
