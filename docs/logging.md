# `nupp.log`

Leveled logging whose disabled path is the path it is designed around.

```nupp
nupp.log.error("cannot open %s: %s", path, reason)
nupp.log.warn("retrying in %dms", delay)
nupp.log.info("loaded %d entities", count)
nupp.log.debug("state=%s", state)
```

Each severity accepts a `string.format` directive string and the arguments it
calls for. The directives and their argument types are checked where the call is
written, by the same machinery that checks `string.format`, so a missing
argument or a `%d` handed a string is a compile error rather than a line that
fails at run time.

```
nupp.log.error("id %d")
  error: NUPP2006: omitted argument 2 supplies nil, not number
```

Because `%s` accepts anything, nothing needs `tostring` and a nil argument
prints as `nil` rather than raising.

## Severity calls are intrinsics

A severity call in statement position whose format is a literal is lowered
rather than called:

```nupp
nupp.log.error("id %d", id)
```

```lua
const __nuppModule = _G.nupp.log.forModule("amb");   -- once, in the prologue
if __nuppModule.on[1] then __nuppModule.emit(1,47,string.format("id %d",id)) end
```

Three things follow, and they are the reason this is a compiler intrinsic rather
than a library.

**A filtered call evaluates nothing.** The level test stands at the call site,
so the arguments of a suppressed line are never computed. `nupp.log.debug("%s",
render(state))` does not call `render` when debug is off. No library can decline
to evaluate its own arguments.

**The module name and line are constants.** The compiler is generating the file,
so it writes both in directly: the module once in the prologue, the line at each
site. Nothing is recovered at run time, nothing depends on the `debug` library,
and there is no per-module boilerplate to write or to keep in step with a
rename.

**A filtered call costs an upvalue read, an array index and a branch.** The view
is bound once per module, and `on` is an array indexed by severity, shared with
every other module so a level change is seen everywhere at once.

### When it is not lowered

Every other spelling keeps an ordinary call meaning exactly the same thing, only
slower. The module shows as `?`, and the arguments are evaluated:

| Spelling | Lowered | Why not |
| --- | --- | --- |
| nupp.log.info("id %d", id) | yes |  |
| nupp.log.info(format, id) | no | format is not a literal |
| local f = nupp.log.info | no | a value, not a call |
| x = nupp.log.info("hi") | no | not statement position |
| local nupp = ... | no | nupp is not the ambient one |
| logger:info("id %d", id) | no | a named logger, not the path |

## Levels

```nupp
nupp.log.level("debug") -- set, answers the previous one
nupp.log.level() -- read
nupp.log.level(os.getenv("LOG_LEVEL") or "warn")
```

`"off" | "error" | "warn" | "info" | "debug"`, each admitting itself and
everything above it, so `"warn"` emits warnings and errors. The default is
`"warn"`. A level that is not one of the five is a compile error where it is a
literal and an ordinary raise where it is not.

`nupp.log.enabled(level)` answers whether a level would emit. Use it to guard
preparation spanning more than one call, which no single lowered site can elide:

```nupp
if nupp.log.enabled("debug") then
    local report = summarize(world)
    nupp.log.debug("world: %s", report)
end
```

## Swapping the back end

A host that logs through its own facility installs a sink function and takes
over completely. It receives the parts, not a rendered line, and pays for no
formatting it would discard:

```nupp
nupp.log.sink(function(level: integer, module: string, line: integer, message: string): nil
    sdl.logMessage(CATEGORY, PRIORITY[level], ("%s:%d %s"):format(module, line, message))
end)
```

`level` is `1` error, `2` warn, `3` info, `4` debug; `nupp.log.levelName` turns
one back into its name. `line` is `0` for a line the compiler could not
attribute, which is every line from a named logger.

Passing anything file-like instead keeps the built-in rendering and only moves
where it goes:

```nupp
local file = io.open("game.log", "a")
nupp.log.sink(file)
```

A file-like target renders through the formatter, which is replaceable on its
own:

```nupp
nupp.log.formatter(function(level: integer, module: string, line: integer, message: string, stamp: string): string
    return ("%s[%s] %s"):format(stamp, nupp.log.levelName(level), message)
end)
```

Both setters answer the value they replaced, so a host can restore what it
found.

## Timestamps

`nupp.log.timestamp()` answers the current time formatted, recomputed at most
once per wall-clock second and shared by every logger. It is a pull rather than
something pushed to sinks, so a host that stamps its own lines never pays for
one.

```nupp
nupp.log.timestampFormat("%H:%M:%S ") -- set, answers the previous format
nupp.log.timestampFormat("") -- off
```

The second itself is read through the FFI rather than `os.time`, which is NYI in
LuaJIT and stitches the trace it stands on. `os.time` is still used once at
startup to validate the symbol, because some Windows CRTs inline `time` to
`_time64` or give it a 32-bit `time_t`.

## Named loggers

```nupp
local physics = nupp.log.named("physics")
physics:warn("step %d took %.2fms", step, elapsed)
```

For subsystems that do not correspond to a module, and for call sites the
intrinsic cannot reach. Repeating a name answers the same logger. Their methods
are replaced when the level or target changes, so a filtered call reaches an
empty function rather than a test, but the arguments are still evaluated, which
is the cost of a name chosen at run time.

## Destinations

The installer lands only in modules that reach `nupp.log`, like every other
ambient facility. A module that never logs carries nothing.

## Diagnostics

- **NUPP2006**: a logging call's arguments do not fit the format it names,
  which an omitted argument supplying nil also reports.
