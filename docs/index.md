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

Generics, interfaces, unions, overloads, and control-flow narrowing make
contracts useful without making Lua feel heavy.

```nupp
local function first<V>(items: {V}): V?
    return items[1]
end

local function label(value: string | number): string
    if value is string then return value:upper() end
    return string.format("%.2f", value)
end
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

A comptime function can inspect and construct types with normal branches,
loops, and recursion. Its result participates in inference and narrowing, then
the whole function erases.

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

## C and FFI in the type systems

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

## Model real data precisely

Records stay flexible Lua tables. Structs become compact FFI cdata with a fixed
C layout. Use the representation your data actually needs.

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

## Derive checked behavior from declarations

Bundled and project-defined comptime providers can add Debug, Default, JSON, or
a project contract. Generated members use normal lookup, inference, interfaces,
and editor navigation.

```nupp
@derive(nupp.derive.Debug, nupp.derive.JSON)
local record User
    id: integer
    name: string
end

local user = new User(id = 42, name = "Ada")
local out = string.buffer.new()
local writer = nupp.data.json.writer(out)
user:writeJSON(writer)
writer:finish()
print(user:debug(), out:tostring())
```

## Async that works like blocking code

HTTP requests look like ordinary blocking calls. Without a handler they block;
under a host scheduler, each parks its coroutine. The checker tracks suspension
separately from the return type. [Follow the call from function to
scheduler](concepts/suspension/index.html).

```nupp
local http = require("nupp.io.http")
local suspension = require("nupp.suspension")
local client = new http.Client()

local function fetch(url: string): integer
    local response = assert(client:send(new http.Request(
        url = assert(nupp.io.uri.newURI(url))
    )))
    local status = response.status
    response:close()
    return status
end

local statuses = suspension.all({function(): integer
    return fetch("https://example.com/")
end, function(): integer
    return fetch("https://example.org/")
end,})

client:close()
print(statuses[1], statuses[2])
```

## Use every core without sharing the heap

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

## Turn raw pointers into checked spans

Counted C pointers become sealed spans that retain their root, check every
index and slice, and keep writable access affine. The adapter verifies equal
lengths before calling C exactly once.

```nupp
cdef function transform(
    borrows output: int32* countedBy(count),
    borrows input: const int32* countedBy(count),
    count: uint64
)

local spans = require("nupp.mem.span")
local input = ffi.new<int32[256]>()
local output = ffi.new<int32[256]>()
local readable = spans.fromCarray(input, 256)
local writable = spans.writeCarray(output, 256)

transform(writable, readable)
drop writable

local result = spans.fromCarray(output, 256)
print(result[1])
```

## Ship only what the program uses

Resolved library uses select exactly the required native providers, then Nupp
stamps them with the program into a self-contained LuaJIT host.
Content-addressed inputs make the result reproducible byte for byte.

```text
nupp build --target dist
nupp fixpoint --binary
```

## Flatten structured calls without allocations

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

## Erase instrumentation from hot paths

Logging filters and profiling zones are compiler intrinsics. A disabled
severity evaluates none of its arguments, while zone push and pop
inline—leaving no Lua call for a hot path to pay for.

```nupp
nupp.log.debug("spawn at %d,%d", x, y) -- unevaluated when filtered

local zone = require("nupp.profile.zone")
zone.push("physics")
stepWorld()
zone.pop() -- inlined against the zone stack, not called
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

## Carry the whole workflow in one toolchain

Check, format, build, test, profile, generate documentation, explain errors,
and power an editor from the same language-aware compiler. No glue scripts
required.

```text
nupp check          # type-check the project
nupp fmt            # apply Nupp's fixed style
nupp test           # build and run the configured suite
nupp run --profile  # write a speedscope-compatible profile
nupp lsp            # start the language server
```

<!-- /nupp:features -->

## Learning Nupp

- [Installation](getting-started/installation.md): requirements, a checkout, and
  a first project.
- [Tour of Nupp](getting-started/tour.md): every construct in one pass, each
  linked to the page that owns it.
- [Why use Nupp](getting-started/why.md): what Lua gives you, what Nupp adds,
  and what each addition costs.
- [Gradual typing](concepts/strictness.md): how an existing `.lua` file becomes
  a checked one, a declaration at a time.
- [Nupp syntax](concepts/syntax.md): the typed layer, and what LuaJIT 2.1
  carries underneath it.
- [Tooling](getting-started/tooling.md): the checker, build system, formatter,
  language server, documentation generator, and profiler.

## Language reference

- [Type system](type-system/overview.md): inference, records, structs,
  interfaces, generics, and narrowing.
- [Ownership](concepts/ownership.md): resources that are hard to leak.
- [Suspension](concepts/suspension.md): scheduler-neutral waiting, checked
  suspension effects, cancellation, and structured concurrency.
- [Workers](concepts/workers.md): CPU work in isolated LuaJIT states, exchanged
  as bounded copied messages.
- [Effect contracts](concepts/effects.md): what a call may observe, change, or
  expose.
- [Reflection](concepts/reflection.md): comptime semantic descriptors, runtime
  type witnesses, lazy descriptors, and JSON's extension-backed codec.
- [Standard library](concepts/standard-library.md): JSON, UTF-8, buffers,
  readers, writers, paths, URIs, identifiers, hashes, checksums, math, and
  vectors.
- [Checked spans](nupp.mem.span): rooted, bounds-checked shared and writable
  views over contiguous C storage.

## Performance and profiling

- [Performance](guides/performance.md): switch dispatch, indexed views, SoA hot
  loops, and where each pass is specified.
- [LuaJIT trace checking](guides/jit-trace-checking.md): deterministic blockers,
  `@jit` contracts, editor inspection, and observed abort reasons.
- [Profiling](guides/profiling.md): sampling, zones, and the places LuaJIT
  declined to compile.
