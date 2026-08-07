# Ownership surface migration

This release replaces the earlier experimental ownership vocabulary and makes
resource cleanup contracts usable for Lua values as well as C pointers.

## Mechanical renames

| Before | Now | Reason |
| --- | --- | --- |
| `consumes value: T` | `takes value: T` | Reads naturally opposite `borrows`. |
| `into_raw(value)` | `intoRaw(value)` | Matches Nupp intrinsic naming. |
| `from_raw(value, free)` | `fromRaw(value, free)` | Matches Nupp intrinsic naming. |

Update declarations, `.d.nupp` overlays, examples, and generated binding
templates together. The old spellings are no longer part of the grammar or
prelude.

## `@owned` without arguments

Before, bare `@owned` meant an opaque transfer-only result. It now resolves the
result type's unique `@dispose` operation:

```lua
local interface Closeable
   @dispose
   close: function(takes value: self): nil
end

local record File is Closeable end
function File:close() end

@owned
local function openFile(): File return File{} end
```

To preserve the previous transfer-only meaning, make it explicit:

```lua
@owned(opaque = true)
cdef function foreign_token(): voidptr
```

If bare `@owned` reports no default or ambiguous defaults, add one `@dispose`
contract or name the intended cleanup directly as `@owned(closeFile)`.

## Unsafe is permission, not diagnostic suppression

`intoRaw`, `fromRaw`, `borrowFrom`, unmanaged pointer dereference/indexing, and
passing raw pointers through uncontracted C parameters require `unsafe do`.
Ownership checks remain active inside the block:

```lua
unsafe do
   local raw = intoRaw(owner)
   use_foreign(raw)
end
```

Do not use `unsafe` to hide an owner in a table or let a borrow escape; those
remain errors. Wrap dynamic unsafe storage in an owning abstraction with a
checked disposer.

## Parameter annotations can become optional

Non-escaping resource parameters are inferred as borrows in Nupp bodies:

```lua
local function inspect(value: widget*): int32
   return value.value
end
```

Keeping `borrows` is still useful on public APIs and invariants. It pins the
contract so a later store or capture errors inside the function instead of
changing its inferred effect and breaking callers.

Never remove contracts from `cdef` declarations or declaration-only overlays;
they have no body from which to infer an effect.

## Exclusive access

There is no `borrowMut` operation or `inout<T>` type. Replace experimental
exclusive-borrow forms with the parameter effect:

```lua
local function resize(inout buffer: Buffer*) end
```

Use ordinary `borrows` for stable field mutation. `inout` is for calls that
can invalidate existing derived views or otherwise need call-duration
exclusivity.

## C output parameters

Replace hand-written holder allocation wrappers with declaration contracts:

```lua
@owned(out = result, cleanup = free, success = zero)
cdef function allocate(out result: voidptr*, size: uint64): int32

local status, result = allocate(4096)
```

For an output whose lifetime is tied to an input:

```lua
@borrowed(out = view, from = owner, success = zero)
cdef function lookup(
   borrows owner: Store*,
   out view: Item**
): int32
```

The logical `out` parameter disappears from the Lua call but remains in its
original generated C argument position.

## Coroutine migration

Move cleanup outside raw suspension points. Code that yields with a live owner,
borrow, retained pin, or `with` scope is now rejected. Split the work into
acquire/use/dispose phases before yielding, transfer ownership to a component
with an explicit shutdown path, or keep the code dynamic until a structured
task abstraction can prove completion.

## Review checklist

- Every owning C result and output names the correct cleanup.
- Every cleanup/adoption parameter says `takes`.
- Every stored C pointer has matching `retains`/`releases` contracts and a pin.
- Every borrowed result/output names its source.
- Every raw dereference or uncontracted pointer call is in a narrow `unsafe`.
- Every owner is discharged on every path.
- No raw coroutine suspends an affine or borrowed obligation.
