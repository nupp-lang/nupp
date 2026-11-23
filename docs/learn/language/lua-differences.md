---
order: 200
title: Differences from Lua
---

# Differences from Lua

Nupp runs Lua 5.5 source, and its native runtime keeps Lua's behavior
wherever it can. This page lists the places where a program can still tell
the difference, each with an example and the reason it stays.

## Error handling

### A cleanup's failure under a body failure that is no string

When a function that owns affine values fails, its owners are destroyed on
the way out. If a destructor raises too, the native runtime keeps the body's
failure. A string failure carries the cleanup's after it, on a line of its
own; a failure of any other kind keeps its identity, and the cleanup's
failure is dropped:

```nupp:fragment
local ok, problem = pcall(function(): nil
    local log = Log()          -- Log.destroy raises "flush failed"
    error({code = 7})
end)
-- problem is the {code = 7} table itself
```

Lua 5.5 does the opposite: an error raised by a `__close` method replaces the
error that was unwinding. The Rust VM wraps both in a table,
`{primary = ..., suppressed = {...}}`, that prints as the string form does.
The native runtime cannot make the function that table would print through
when it lands the error, so it keeps the failure the program raised, which
is the one it is most likely to test for.

## The debug library

The native runtime provides `debug.getinfo` and `debug.traceback`. The rest of
Lua's `debug` library (`debug.debug`, `gethook`, `sethook`, `getlocal`,
`setlocal`, `getupvalue`, `setupvalue`, `upvalueid`, `upvaluejoin`,
`getmetatable`, `setmetatable`, `getregistry`, `getuservalue` and
`setuservalue`) is not there: those fields are nil.

`debug.traceback` lists levels as Lua's does, with two differences:

- A library function the runtime runs itself, such as `error`, has no level
  of its own, so a traceback taken in a message handler starts at the
  function that called it, where Lua's starts with `[C]: in function 'error'`.
- Under `nupp run`, the levels below the program's main chunk are the
  command's own, which follow `[C]: in ?` where Lua's listing ends.
- Another thread's levels are not available. A traceback of a coroutine
  other than the running one has a header and no lines:

```lua
local co = coroutine.create(function() coroutine.yield() end)
coroutine.resume(co)
print(debug.traceback(co, "where"))   -- "where\nstack traceback:"
```

`debug.getinfo` refuses a thread argument for the same reason.

## Structs

A struct is a value in C layout: an instance is its bytes, which is what a C
function or the GPU is given. Beside the bytes the native runtime keeps a
type id that names the struct's declaration, so a struct that reaches `any`,
`unknown` or plain Lua still answers `is`, and Lua can call the struct to
build one and read its fields by name:

```nupp:fragment
local struct Vec
    x: float64
    y: float64
end
local value: any = Vec(1, 2)
assert(value is Vec)          -- the type id names Vec's declaration
local class: any = Vec
local made = class(3, 4)      -- built from Lua, by position
assert(made.x == 3)           -- read by name, through the declaration
```

Two structs with the same layout in two modules are two types, because the
id names the declaration, not the layout. Code that knows a struct's static
type reads its fields at their offsets and never looks at the id. Where the
Rust VM's structs (LuaJIT FFI cdata) behave differently:

- Lua reads and writes a scalar field by name: a number, an integer or a
  boolean. A nested struct, a fixed array, a vector, a pointer or a bitfield
  field raises when Lua names it; typed code reaches each at its offset.
- Calling a struct from Lua (`Vec(3, 4)`) fills its fields by position, or
  runs the constructor whose arity admits the arguments. Two constructors of
  the same arity are not told apart by their parameter types: the first
  declared runs.
- `getmetatable` of a struct answers the table its declaration gives its
  instances, where LuaJIT answers `"ffi"`.
- Bytes that reach a program without a struct's type, such as storage cast
  from a raw pointer, carry no type id: `is` answers false for them, and Lua
  cannot name their fields.
- The id is the process's own: a declaration gets the next one the first time
  the process names it, by the key the checker gives the declaration (its
  module and its place there), which is what stays the same from one build to
  the next. A module run twice in one process with a changed struct layout
  keeps one id for both, so `is` answers true for values of either, and Lua
  reads them through the later layout. The Rust VM refuses the second
  declaration as a conflicting native struct declaration.
