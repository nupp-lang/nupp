`nupp.log` is leveled logging whose disabled path is the one it is designed
around. A severity call in statement position is lowered rather than called, so
a filtered line evaluates none of its arguments.

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

```text
nupp.log.error("id %d")
  error: NUPP2006: omitted argument 2 supplies nil, not number
```

Because `%s` accepts anything, nothing needs `tostring` and a nil argument
prints as `nil` rather than raising. Lines go to standard error until a host
says otherwise.

`%?` is Nupp's debug directive. It requires `nupp.Debug`, calls the value's
`debug()` method, and formats the returned string as `%s`:

```nupp
nupp.log.debug("state=%?", state)
```

At lowered call sites that method call is inside the level guard, so filtered
logs do not render the value. Named loggers perform the same check in their
already-lazy writer.

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

Three properties follow from that shape, and together they are the reason this
is a compiler intrinsic rather than a library.

### Filtered calls evaluate nothing

The level test stands at the call site, so the arguments of a suppressed line
are never computed. `nupp.log.debug("%s", render(state))` does not call `render`
when debug is off. No library can decline to evaluate its own arguments.

### Module name and line are constants

The compiler is generating the file, so it writes both in directly: the module
once in the prologue, the line at each site. Nothing is recovered at run time,
nothing depends on the `debug` library, and there is no per-module boilerplate
to write or to keep in step with a rename.

### Filtered call cost

A filtered call costs an upvalue read, an array index and a branch. The view is
bound once per module, and `on` is an array indexed by severity, shared with
every other module so a level change is seen everywhere at once.

### Forms that stay calls

Every other form keeps an ordinary call meaning exactly the same thing, only
slower. The module shows as `?`, and the arguments are evaluated:

| Form | Lowered | Reason |
| --- | --- | --- |
| `nupp.log.info("id %d", id)` | yes | |
| `nupp.log.info(format, id)` | no | the format is not a literal |
| `local f = nupp.log.info` | no | a value, not a call |
| `x = nupp.log.info("hi")` | no | not statement position |
| `local nupp = ...` | no | not the compiler-provided `nupp` |
| `logger:info("id %d", id)` | no | a named logger, not the path |

## Levels

`level` reads the threshold, and moves it when given one:

```nupp
nupp.log.level("debug") -- set, answers the previous one
nupp.log.level() -- read
```

The five levels are `"off"`, `"error"`, `"warn"`, `"info"` and `"debug"`, each
admitting itself and everything above it, so `"warn"` emits warnings and errors.
The default is `"warn"`.

The parameter is that literal union, so a string from outside the program has to
be narrowed to one of the five before it can be passed.
`os.getenv("LOG_LEVEL") or "warn"` is `string`, and `string` is not one of them:

```nupp
local wanted = os.getenv("LOG_LEVEL")
if wanted == "debug" or wanted == "info" or wanted == "warn" then
    nupp.log.level(wanted)
end
```

A level that is not one of the five is a compile error where it is a literal and
an ordinary raise where it is not.

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
local file = assert(io.open("game.log", "a"))
nupp.log.sink(file)
```

`io.open` answers `LuaFile?`, and `sink` takes a target rather than a maybe, so
the `assert` is what turns one into the other.

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

::: deepdive Reading the second through the FFI
`os.time` is NYI in LuaJIT and stitches the trace it stands on, so the second is
read through the FFI instead. `os.time` is still called once at startup to
validate the symbol, because some Windows CRTs inline `time` to `_time64` or
give it a 32-bit `time_t`, and a symbol that resolves but is the wrong width
answers nonsense rather than failing to resolve.
:::

## Named loggers

`named` answers a logger carrying a fixed name, with a method per severity:

```nupp
local physics = nupp.log.named("physics")
physics:warn("step %d took %.2fms", step, elapsed)
```

Use one for a subsystem that does not correspond to a module, and for a call
site the intrinsic cannot reach. Repeating a name answers the same logger.
Their methods are replaced when the level or target changes, so a filtered call
reaches an empty function rather than a test, but the arguments are still
evaluated, which is the cost of a name chosen at run time.

## Cost

The installer lands only in modules that reach `nupp.log`, like every other
compiler-provided facility. A module that never logs carries nothing.

::: seealso
- [diagnostics.md](../../reference/diagnostics.md#diagnostic-index) for the
  codes a mistyped format string reports
- [standard-library.md](../../concepts/standard-library.md) for how a facility
  reaches a program without being linked into one that never uses it
:::
