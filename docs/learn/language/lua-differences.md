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
