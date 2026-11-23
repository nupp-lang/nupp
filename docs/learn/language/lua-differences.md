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

### Messages that do not name the variable

Lua adds the variable a failed operation read to its message, such as
`attempt to call a nil value (method 'missing')` or `attempt to index a nil
value (global 'config')`. The native runtime's message stops before the
parenthesis:

```lua
local ok, problem = pcall(function()
    local box = {}
    return box:missing()
end)
-- problem ends "attempt to call a nil value"
```

Lua finds that name by reading the bytecode around the failed instruction.
The native runtime keeps no such description of its instructions, so a
message names only the kind of value. Match a message by its prefix rather
than by the whole text.

## Control flow

### goto

The native runtime admits a `goto` only to a label that ends the body of a
loop enclosing it: the `continue` that Lua programs write as
`goto continue`. The loop may be an outer one, so a `goto` can leave an inner
loop for the next iteration of the loop around it:

```lua
for _, row in ipairs({{1, 2}, {3, 4}}) do
    for _, cell in ipairs(row) do
        if cell == 2 then
            goto nextrow
        end
    end
    ::nextrow::
end
```

A `goto` to any other label, backward or forward within a block, fails to
compile. The compiler builds each loop with one entry and fixed exits, and
a `goto` to the end of a loop body is one of those exits. A jump to any
other place in a function is not.

## Modules

### require's searchers

`require` on the native runtime looks where Lua's searchers look, in the same
order: `package.loaded`, `package.preload`, the modules the program was built
with, then a Lua file `package.path` names. Only a program that carries Lua's
loaders, one that calls `load`, `loadfile` or `dofile`, looks on
`package.path`; any other finds only the modules it was built with. None looks
on `package.cpath`, and `package.searchers`, `package.searchpath` and
`package.loadlib` are nil, so a program cannot add a searcher of its own:

```lua:fragment
package.path = "plugins/?.lua;" .. package.path
local plugin = require(name)          -- found as Lua finds it, with the loaders
print(package.searchers)              -- nil
```

The runtime has no C module loader to search `package.cpath` with: native
code reaches a program through `cdef` and a project's C dependencies instead.
The loaders bring the runtime's file and process layers with them, which a
program that never loads a chunk does not otherwise carry.

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
