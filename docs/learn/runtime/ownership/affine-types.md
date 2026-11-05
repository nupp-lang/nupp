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

```nupp:fragment
local type AlsoHeld = affine(LockToken, unlock) -- the same type as HeldLock
```

## Cleanup and transfer-only forms

The two forms are calls to the same generator:

```nupp
local type Owner<T, const cleanup: function> = affine(T, cleanup)
local type MustForward<T> = affine(T)
```

`affine(T, cleanup)` carries one obligation to invoke exactly `cleanup`, whose
type must be `function(takes T): nil`; it may suspend. `affine(T)` carries an
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

A record constructor may make the affine view its default result:

```nupp:fragment
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
    local file = File(nativeOpen("notes.txt"))
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

## Moving a field out of a record that closes itself

A record with its own cleanup, such as one that is `own.Closeable`, runs that
cleanup on whatever it still holds when it is dropped. Moving an affine field
out of it therefore works the way Rust's `Option::take` does. An optional field
is taken: the generated code writes nil where the field was, so the record's
`close` finds nothing to close twice, and the checker treats the field as moved
until it is assigned again.

```nupp:fragment
local record Child is own.Closeable
    stdin: Writer?

    function close(takes self): nil
        if self.stdin ~= nil then
            self.stdin:close()
        end
    end
end

do
    local child = Child(stdin = openWriter())
    if child.stdin ~= nil then
        child.stdin:close() -- takes the writer; child.stdin is now nil
    end
    child.stdin = nil -- refilled, so the child may be used whole again
end -- Child.close runs once and sees no writer
```

A field that cannot hold nil cannot leave such a record, because nothing could
be written in its place: the move is `NUPP2602`, and the fix is to declare the
field optional. A record without a cleanup of its own is closed field by field,
and a field moved out of it is simply skipped when the rest are closed.

## Comptime type generators

A user-defined comptime type function can call the programmable counterpart of
the direct form:

```nupp:fragment
@comptime
local function MakeOwner(
    T: type,
    const cleanup: function
): type
    return types.affine(T, cleanup)
end

local type HeldAgain = MakeOwner(LockToken, unlock)
```

`types.affine` builds the same types `affine(...)` does, including the
transfer-only `types.affine(T)`. Its cleanup argument must come from a
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
lets one generic API serve affine and ordinary types without overloads.

The relation reaches inside a type the result wraps, so a constructor that
stores its argument preserves the capability into the unique `T` component of
the result. See [generic
preservation](borrowing.md#generic-preservation) for the complete set of shapes
it follows and the ambiguity it refuses.
