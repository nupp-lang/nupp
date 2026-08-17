# Exact affine scopes

Ordinary affine locals are destroyed automatically at their lexical boundary,
but they may also be moved, returned, or dropped early. `with` gives an affine
value a stricter contract: one exact extent whose visible name is a borrow.

```nupp:playground
local soa = require("nupp.soa")
local ffi = require("ffi")

local struct Position
    x: float
    velocity: float
end

local positions = soa.allocate(ffi.typeof<Position>(), 128)
with rows = positions:write() do
    for index = 1, rows.count do
        rows[index].x += rows[index].velocity
    end
end
```

The hidden owner is dropped when the body falls through, returns, raises, or
leaves through loop control or an outward `goto`. For writable SoA and span
views, dropping only ends the exclusive borrow: stores already changed the
original columns, so the scope performs no flush or copy.

## Syntax

One acquisition is the common form:

```nupp
with file = openFile(path) do
    print(file:read("*a"))
end
```

Several resources may share an extent. Acquisitions run left to right and
terminals run in reverse order:

```nupp
with
    input = openFile(source, "rb"),
    output = openFile(target, "wb")
do
    output:write(input:read("*a"))
end
```

A binding may have an underlying representation type annotation:

```nupp
with file: FileHandle = openFile(path) do
    use(file)
end
```

`with` is contextual. It introduces a scope only at statement position when a
name and `=` or `:` follow it, so `local with = function(...) ... end` remains
ordinary Lua-compatible code.

## The visible name is a borrow

The acquisition must produce a non-optional `affine(T, terminal)` value. The
compiler moves that owner into an inaccessible slot and binds the authored name
as a scoped borrow of `T`. Code in the body can read and mutate through that
borrow, but cannot:

- move it into a `takes` parameter;
- return it or store it in a longer-lived value;
- capture it in an escaping closure;
- assign a replacement to it; or
- invoke `drop` on it directly.

Those rules make cleanup unconditional without an "already closed" flag. If a
value needs to move or end early, use an ordinary affine local and `drop`:

```nupp
local rows = positions:write()
update(rows)
drop rows
```

## Failure and control flow

Each successful acquisition is registered before the next begins. If a later
acquisition fails, earlier owners still drop. Every terminal is attempted even
if another terminal raises.

When both the body and cleanup fail, the body error stays primary and cleanup
errors are attached as suppressed failures. When only cleanup fails, its first
failure is primary. A single failure is rethrown unchanged.

`return`, `break`, `continue`, and an outward `goto` cross the cleanup region
and resume only after its terminals run. A `goto` cannot enter a `with` body and
bypass acquisition.

## Runtime cost

Affine wrappers and `with` bindings are erased; the acquired value itself is
not copied or boxed. The generated code uses the same cleanup-region machinery
as automatic lexical destruction. When the body has ordinary fallthrough,
every reachable operation is proven non-raising, and every terminal has a
`noRaise` guarantee, the compiler emits an ordinary block followed by direct
terminal calls. No `pcall`, `xpcall`, or closure is present in that form.

Uncertain or raising extents use a protected call, and a non-capturing body is
shared rather than rebuilt on each execution. Outward `return`, loop control,
`goto`, multiple acquisition, and nested cleanup currently keep this general
lowering. This is a control-flow cost, not a storage-layout or copy-back cost.

For data-oriented code, put `with` around the hot loop rather than inside it:
the loop continues to access SoA columns directly and can be checked with
`nupp bc --check` for LuaJIT trace blockers.

See [Ownership](ownership.md) for affine terminals, moves, borrows, aggregates,
and unsafe representation boundaries.
