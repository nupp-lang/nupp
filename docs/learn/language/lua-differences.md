---
order: 200
title: Differences from Lua
---

# Differences from Lua

Nupp runs Lua 5.5 source, and its native runtime keeps Lua's behavior
wherever it can. This page lists the places where a program can still tell
the difference, each with an example and the reason it stays.

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
