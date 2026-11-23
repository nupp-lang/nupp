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
