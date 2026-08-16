# Affine types

An affine type is a compile-time-generated view of an existing representation.
It adds a move or cleanup obligation to the checker without adding a runtime
wrapper:

```nupp
local record LockToken
    mutex: Mutex
end

local function unlock(takes held: LockToken): nil
    held.mutex.locked = false
end

local type HeldLock = affine(LockToken, unlock)
```

`affine(LockToken, unlock)` looks like a function call because it is a built-in
compile-time type-generator call. It is never a runtime call:

- `LockToken` is a compile-time type value.
- `unlock` contributes its const function declaration identity, not a callback
  stored in each value.
- the result has the same runtime representation as `LockToken`.

The cleanup identity is part of the generated type. Two functions with the same
signature still create different affine types. Aliasing a generated type does
not create a new nominal identity:

```nupp
local type AlsoHeld = affine(LockToken, unlock) -- The same type as HeldLock.
```

## Cleanup and transfer-only forms

The two forms are calls to the same generator:

```nupp
local type Owner<T, const cleanup: function> = affine(T, cleanup)
local type MustForward<T> = affine(T)
```

`affine(T, cleanup)` carries one obligation to invoke exactly `cleanup`. The
function must be a `nosuspend function(takes T): nil`. `affine(T)` carries an
obligation that may be moved, returned, released through an unsafe boundary, or
placed into another affine value, but it has no local cleanup and therefore
cannot be dropped.

Both forms erase to `T`; neither evaluates `T` or calls `cleanup` when the type
is constructed. Cleanup runs only when a runtime value of the generated type is
explicitly dropped or reaches automatic lexical destruction.

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
    print(file:read(128)) -- The affine value uses File directly.
end -- Calls File.destroy exactly once.
```

The result annotation does not replace `File` with a wrapper. It says that this
constructor introduces one `File.destroy` obligation on the `File` it already
builds. Consequently `file:read(...)` needs no common interface, forwarding
object, or conversion. `File.destroy` is a normal method declaration whose
function identity is used by the type and whose function value is registered
for lexical destruction.

The annotation must contain exactly one result and erase to the record being
constructed. Omitting it preserves ordinary GC-managed construction. Constructor
overloads may state different policies; argument overload selection happens
first, and the selected entry supplies its result policy.

## Why parentheses instead of angle brackets

Angle brackets apply a declared generic type such as `Box<T>`. Parentheses call
a compile-time type generator. Keeping those operations visibly distinct means
the same syntax works for built-in generators and user-defined comptime type
functions:

```nupp
local comptime function MakeOwner(
    T: type,
    const cleanup: function
): type
    return nupp.types.affine(T, cleanup)
end

local type HeldAgain = MakeOwner(LockToken, unlock)
```

`nupp.types.affine` is the programmable comptime builder corresponding to the
direct `affine(...)` type form. Its cleanup argument must come from a const
function parameter so declaration identity remains static and unforgeable.

## Generic capability preservation

A generic need not know whether a value is affine. `takes` permits the checker
to move a capability when one is present, and `preserves` relates that capability
to the result:

```nupp
local function forward<T>(takes value: T): T preserves value
    return value
end
```

For an ordinary value this is an ordinary pass-through. For an affine value its
single obligation moves to the result; it is not copied. This lets generic APIs
work with both affine and ordinary types without overloads or an `Affine`
interface special case. The same relation is compositional:

```nupp
local record Box<T>
    value: T
end

local function box<T>(takes value: T): Box<T> preserves value
    return new Box(value = value)
end
```

The checker substitutes the complete capability into the unique `T` component of
`Box<T>`. It recursively handles records, tuples, optionals, unions, intersections,
identity-mapped and projected types, callable records, closures, and result packs.
Cleanup obligations, pins, and retentions move once; root and region provenance
remains available to derived views. Callable assignment preserves this relation
exactly. A result with two possible `T` components is ambiguous and reports
`NUPP2606` instead of guessing.

This does not require higher-kinded generics. `Box<T>` is an ordinary first-order
application, while `preserves` supplies the separate conservation proof. HKT would
only be relevant to an API abstracting over `Box` itself as a constructor and would
not replace that proof.

## GC finalizers remain a safety net

A GC finalizer can eventually release an unreachable resource, but it cannot
guarantee when that happens. It also cannot prevent use after close, prove that
exactly one unlock or ownership transfer occurs, or keep a
[borrowed pointer](../ownership.md#borrowing-and-pinning) attached to its
backing storage. These guarantees matter at a
[C and FFI boundary](../c-interop.md#describe-lifetime-behavior), where the
garbage collector does not know a native library's ownership, pinning, or
cleanup contract.
[Lexical destruction](../ownership.md#consumption-and-lexical-destruction)
provides the deterministic contract; a finalizer can remain a last-resort
safety net.

## Manual cleanup does not prove every path

Calling `close`, `unlock`, or `free` directly works only when every return,
raised error, and transfer follows the protocol. An
[affine terminal](../ownership.md#terminal-contract) makes that protocol part of
the type. The checker then rejects a forgotten obligation, a second consumption,
or a use after the value moved, while
[automatic lexical
destruction](../ownership.md#consumption-and-lexical-destruction) handles each
scope exit.

## Ordinary values remain GC-managed

Ownership is opt-in. Strings, numbers, tables, and records without a
nontrivial capability retain ordinary Lua behavior and need no ownership
annotation. Explicit
[public capability contracts](../ownership.md#public-capability-contracts)
apply only when an API carries an obligation, root, exclusive access, pin, or
retention. A record constructor likewise remains ordinary unless its [result
introduces a
policy](../type-system/records.md#constructors-and-result-policies).

## Native values keep their ABI representation

An affine type adds no runtime wrapper, cleanup field, tag, or vtable. It
erases to its representation, so a C pointer remains a C pointer and a struct
keeps the [layout declared at the boundary](../c-interop.md#type-mapping).
Imported functions can state their [lifetime
behavior](../c-interop.md#describe-lifetime-behavior) directly, and the checker
enforces the contract around the same LuaJIT FFI call.

## Next

- [Ownership](../ownership.md) covers moves, borrows, lexical destruction,
  aggregates, pinning, and unsafe representation boundaries.
- [Comptime types](type-level-computation.md) covers user-defined type functions
  and the `nupp.types` construction API.
- [Generics](generics.md) covers type and const-function parameters.
