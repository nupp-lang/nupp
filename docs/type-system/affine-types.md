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
interface special case.

## Next

- [Ownership](../ownership.md) covers moves, borrows, lexical destruction,
  aggregates, pinning, and unsafe representation boundaries.
- [Comptime types](type-level-computation.md) covers user-defined type functions
  and the `nupp.types` construction API.
- [Generics](generics.md) covers type and const-function parameters.
