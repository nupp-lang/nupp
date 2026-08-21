---
order: 0
layout: home
---

<!-- nupp:hero -->

# Nupp

LuaJIT with static guarantees.

Nupp is the "what if we leaned all the way into LuaJIT" language, giving it
types, checked C interop, ownership, scheduler-neutral suspension, workers,
AOT, SIMD, and self-contained builds without losing Lua's charm.

[Get started](getting-started/installation)
[Playground](/playground/)

![A nuppeppo in a moonlit forest](images/nupp.png)

<!-- /nupp:hero -->

---

```playground
```

---

<!-- nupp:features -->

## Strict typing for LuaJIT

Generics, interfaces, unions, intersections, associated types, overloads,
and control-flow narrowing make contracts useful without making Lua feel heavy.

```nupp
local function first<V>(items: {V}): V?
    return items[1]
end

local function label(value: string | number): string
    if value is string then return value:upper() end
    return string.format("%.2f", value)
end
```

## Records and structs

_Records_ stay flexible Lua tables. _Structs_ become compact FFI cdata with a
fixed C layout. Use the representation your data actually needs.

```nupp
local record User
    name: string
    online: boolean
end

local struct Vec2
    x: float
    y: float
end
```

## Bring your old Lua files to Nupp

Nupp can automatically import existing Lua files, and even understands how
to marry documentation comments from LuaCATS, EmmyLua, and typed LuaDoc with
Nupp's type system.

```lua [users.lua]
-- Nupp understands this too!

---@alias UserId integer

---@class User
---@field id UserId
---@field name? string

local users = {}

---@param id UserId
---@return User
function users.find(id)
    return {id = id, name = "Ada"}
end

return users
```

## Gradual typing for existing code

Every valid LuaJIT program is already valid Nupp. Add type syntax under gradual
checks, then rename a file when it is ready for a strict boundary—without
changing how other modules load it.

```nupp
local record Point
    x: number
    y: number
end

-- models.g.nupp: type syntax, gradual checks
local function scale(point, factor)
    return {x = point.x * factor, y = point.y * factor}
end

-- models.nupp: the same code, now a checked boundary
local function scale(point: Point, factor: number): Point
    return new Point(x = point.x * factor, y = point.y * factor)
end
```

## Comptime types

A `comptime` function can inspect and construct types with normal branches,
loops, and recursion. Types generated at compile time participate in inference
and narrowing just like any other type, and the comptime function erases.

```nupp
local comptime function Optional(T: type): type
    return nupp.types.optional(T)
end

local value: Optional(string) = nil
value = "ready"
```

## Borrow checker and ownership

Ownership, borrowing, pinning, and deterministic cleanup make the important
rules at a C boundary explicit—and make leaks and use-after-move errors
reportable.

```nupp
local function send(borrows handle: LuaFile): nil
    print(handle:read("*a"))
end

do
    local report = assert(io.open("report.txt", "r"))
    send(report)
end -- the file is closed on every structured exit
```

## C and FFI in the type system

Import a header or write declarations with the real ABI, then state what each
call borrows, consumes, and returns. Nupp checks the contract while LuaJIT FFI
still makes the call.

```nupp
cdef struct nativeBuffer
    size: uint64
end

cdef function buffer_free(takes buffer: nativeBuffer*)

cdef function buffer_create_c(size: uint64): nativeBuffer*

local function buffer_create(size: uint64): affine(nativeBuffer*, buffer_free)
    return buffer_create_c(size)
end

cdef function buffer_read(
    borrows buffer: nativeBuffer*,
    exclusive output: uint8*,
    size: uint64
): int32
```

## Async that works like blocking code

HTTP requests look like ordinary blocking calls. Without a handler they block;
under a host scheduler, each parks its coroutine. The checker tracks suspension
separately from the return type. [Follow the call from function to
scheduler](concepts/suspension/index.html).

```nupp
const http, uri = nupp.io.http, nupp.io.uri

const client = new http.Client()

local function fetch(url: string): integer
    const request = new http.Request(assert(uri.newURI(url)))
    const response = assert(client:send(request))
    const status = response.status
    response:close()
    return status
end

const statuses = nupp.suspension.all({
    || -> fetch("https://example.com/"),
    || -> fetch("https://example.org/")
})

client:close()
print(statuses[1], statuses[2])
```

## Distribute work across threads using workers

Workers run fresh LuaJIT states on native threads and exchange bounded,
serialized messages. Calls read like functions, failures cross back, and
ownership guarantees every worker is joined.

```nupp
local workers = require("nupp.workers")

do
    local hasher = workers.spawn("workers.hash")
    local answer = hasher:call({
        name = "level1",
        bytes = contents,
    })
end
```

## Named and plucked arguments

Nupp leaves hot loops to LuaJIT's tracer and uses types where the tracer
cannot: plucked arguments share stable table paths and become flat positional
arguments without tables, varargs, or closures.

```nupp
local record Body
    x: number
    y: number
    vx: number
    vy: number
end

local function update(x: number, y: number, vx: number, vy: number): nil
    print(x + vx, y + vy)
end

local body = new Body(x = 0, y = 0, vx = 1, vy = 0)

update({x, y} = body, {vx, vy} = body)
-- body is read once per group; update receives x, y, vx, vy.
```

## Build constants before startup

comptime do ... end runs ordinary Nupp while the file is compiled and writes
the answer into the output as a literal. Deterministic and sandboxed: no clock,
no files, no randomness -- and no macros, because it produces data rather than
code.

```nupp
const CRC32 = comptime do
    const entries = {}
    for byte = 0, 255 do
        local acc = byte
        for _ = 1, 8 do
            acc = acc & 1 ~= 0 and 0xedb88320 ~ (acc >> 1) or acc >> 1
        end
        entries[byte + 1] = acc
    end
    return entries
end

-- The generated Lua holds the table, not the loop that built it.
```

## A standard library for real programs

Make HTTP requests, run child processes, encode JSON, work with hashes and
identifiers, and compile typed PEG parsers without assembling a third-party
stack.

```text
nupp.io.http      HTTP client, TLS, streaming bodies
nupp.io.process   processes, pipes, timeouts
nupp.data.json    JSON encoding and decoding
nupp.data         hashes, checksums, UUIDs, UTF-8
nupp.peg          typed parsing-expression grammars
```

## Nupp is a single binary and can build single binaries

Check, format, build, test, profile, generate documentation, explain errors,
power an editor, and even build standalone binaries all from the same
language-aware compiler. No glue scripts required.

```text
nupp check                # type-check the project
nupp fmt                  # apply Nupp's fixed style
nupp test                 # build and run the configured suite
nupp build --target dist  # stamp a self-contained binary
nupp run --profile        # write a speedscope-compatible profile
nupp lsp                  # start the language server
```

## Write Nupp libraries that work on LuaJIT and Lua 5.1

Write a library once and [build it for multiple targets]((guides/portable-libraries/index.html)).
The LuaJIT build keeps FFI structs and performance optimizations; the portable
build swaps in plain Lua that runs on any Lua from 5.1 to 5.4.

```lua [nupp.lua]
return {
   include = {"src"},
   build = {
      default = "portable",
      targets = {
         native = {
            entries = {"main"},
            dialect = "luajit",
            outDir = "build/luajit",
         },
         portable = {
            entries = {"main"},
            dialect = "lua51",
            outDir = "build/lua51",
            backends = {"portable.backend"},
         },
      },
   },
}
```

<!-- /nupp:features -->

## Learning Nupp

- [Installation](getting-started/installation.md)
- [Tour of Nupp](getting-started/tour.md)
- [Why use Nupp](getting-started/why.md)
- [Gradual typing](concepts/strictness.md)
- [Nupp syntax](concepts/syntax.md)
- [Tooling](getting-started/tooling.md)

## Language reference

- [Type system](type-system/overview.md)
- [Ownership](concepts/ownership.md)
- [Suspension](concepts/suspension.md)
- [Workers](concepts/workers.md)
- [Effect contracts](concepts/effects.md)
- [Reflection](concepts/reflection.md)
- [Standard library](concepts/standard-library.md)
- [Checked spans](nupp.mem.span)

## Performance and profiling

- [Performance](guides/performance.md)
- [LuaJIT trace checking](guides/jit-trace-checking.md)
- [Profiling](guides/profiling.md)
