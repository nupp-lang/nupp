---
order: 0
layout: home
---

<!-- nupp:hero -->

# Nupp

LuaJIT with static guarantees.

Nupp is the "lean all the way into LuaJIT" language, giving it types, checked C interop,
ownership, scheduler-neutral suspension, workers, AOT, SIMD, GPU compute, and
self-contained builds without losing Lua's charm.

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

## Actionable errors

Every diagnostic has a stable code, a span, the related locations that explain
it, and help saying what to do. Most also carry a machine-applicable fix, so an
editor or `nupp check --json` can apply the whole repair rather than describe
it. [`nupp explain`](reference/diagnostics/index.html) prints the rule behind a
code, a program that reports it, and the same program corrected.

```text
codec.nupp:15:11: error: NUPP2601: owner "handle" was moved and cannot be used
 15 |     print(handle.rate)
    |           ^~~~~~
codec.nupp:14:19: note: owner was moved here
 14 |     codec_destroy(handle)
    |                   ^~~~~~
help: use the owner before this transfer, or borrow it instead of moving it
```

## Async that works like blocking code

HTTP requests look like ordinary blocking calls. Without a handler they block;
under a host scheduler, each parks its coroutine. The checker tracks suspension
separately from the return type. [Follow the call from function to
scheduler](concepts/suspension/index.html).

```nupp
local http = require("nupp.io.http")
local suspension = require("nupp.suspension")
local uri = require("nupp.io.uri")

const client = new http.Client()

local function fetch(url: string): integer
    const request = new http.Request(assert(uri.newURI(url)))
    const response = assert(client:send(request))
    const status = response.status
    response:close()
    return status
end

const statuses = suspension.all({
    || -> fetch("https://example.com/"),
    || -> fetch("https://example.org/")
})

client:close()
print(statuses[1], statuses[2])
```

## Distribute work across threads using workers

Worker tasks run ordinary exported functions on persistent, isolated LuaJIT
states behind one shared, bounded scheduler. Arguments and results are copied,
failures cross back, and a structured scope waits for every child.

```nupp
const data = require("nupp.data")
const workers = require("nupp.workers")

const left = "left chunk"
const right = "right chunk"

with scope = workers.scope() do
    const first = scope:spawn(left, data.fnv1a64)
    const second = scope:spawn(right, data.fnv1a64)
    print(first:await(), second:await())
end
```

## Types and constants computed at compile time

A `comptime` function inspects and constructs types with normal branches, loops,
and recursion, and the types it returns participate in inference and narrowing
like any other. A `comptime do` block runs ordinary Nupp while the file compiles
and writes the answer into the output as a literal.

Both are deterministic and sandboxed: no clock, no files, no randomness—and no
macros, because what they produce is data rather than code.

```nupp
local comptime function Optional(T: type): type
    return nupp.types.optional(T)
end

local value: Optional(string) = nil
value = "ready"

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

## Compile hot loops ahead of time

`@aot` compiles a function once, ahead of time, with an optimizing compiler
behind it—no trace to record and no abort to fall out of. Its numeric meaning is
pinned to what was written rather than to whatever target compiled it, and a
body shaped like one map loop over spans may be lowered lane-parallel.

The compiler decides whether vectorizing pays and how wide the lanes are, then
reports both answers per kernel. [Read the worked
example](guides/ahead-of-time/index.html).

```nupp
local span = require("nupp.mem.span")

@aot
local function normalize(
    exclusive out: span.WriteSpan<float>,
    borrows samples: span.Span<float>,
    scale: float
): nil
    for index = 1, #out do
        local sample = samples[index] * scale
        out[index] = sample < 0.0 and -sample or sample
    end
end

return normalize
```

## Optimize the JIT at compile time

A tracing JIT compiles what it can record and gives up quietly on what it
cannot, so a hot loop that aborts a trace runs interpreted however hot it gets.
`nupp check` reports the shapes that cause it—a variadic FFI call, a registered
callback, a function built inside a loop—and `nupp bc --check` reads the
generated bytecode and exits non-zero for work the recorder will not take. It
times nothing, so it needs no quiet machine and answers the same every run.
`nupp run --jit-aborts` reports what a real run declined. [Read about trace
checking](guides/jit-trace-checking/index.html).

```text
render.nupp:4:5: warning: NUPP2514 jit-boundary: a variadic FFI call cannot safely execute on a compiled trace
 4 |     printf("%d", value)
   |     ^~~~~~
note: trace classification: risk (jit/ffi-vararg-policy)
help: move the call behind an explicit jit.off boundary when it is not hot
```

## C, Rust, and Lua dependencies in one manifest

A C dependency builds from local sources, `pkg-config`, or an exact Git
revision, and its header passes through `import-c` into typed declarations. A
Cargo dependency builds a `cdylib`, runs cbindgen, and maps ownership onto the
result, so a Rust constructor becomes `affine(Codec*, codec_destroy)` and the
checker enforces the boundary. A LuaRocks dependency installs and joins the
search path. [See the build guide](guides/build/index.html).

```lua [nupp.lua]
dependencies = {
   zstd = {
      kind = "c",
      pkgConfig = "libzstd",
      bindings = {header = "zstd.h"}
   },
   codec = {
      kind = "cargo",
      path = "native/codec",
      bindings = {
         cbindgen = true,
         ownership = {
            returns = {codec_create = "codec_destroy"},
            takes = {codec_destroy = {1}}
         }
      }
   },
   lunamark = {kind = "luarocks", version = "0.6.0-1"}
}
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

## Embed Nupp in a C application

A C host keeps the process and the event loop. `libnupp` creates a runtime or
attaches to a LuaJIT state the host already owns, loads a checked component from
memory, and calls its named exports through GC-safe handles. One state, one
heap, no second VM or collector alongside the host's—which is what makes Nupp
usable as a game engine's or an application's scripting layer. [See the
embedding guide](guides/embedding/index.html).

```c
nupp_config config;
nupp_runtime *runtime = NULL;
nupp_component *component = NULL;
nupp_error *error = NULL;

nupp_config_init(&config);
nupp_runtime_new(&config, &runtime, &error);
nupp_component_load(runtime, bytes, length, "game.nuppc", &component, &error);
nupp_component_start(runtime, component, 0, NULL, &error);
nupp_component_release(component);
nupp_runtime_shutdown(runtime, &error);
nupp_runtime_free(runtime);
```

## Hot reload

`nupp run --watch` builds a version of a program in which named functions and
methods keep their public identity while their bodies change. Reload is
cooperative, so the host polls where changing future dispatch is safe.
Application state, registered callbacks, and module tables stay in place; only
future calls enter new bodies.

```nupp
local function render(frame: integer): nil
    print("frame", frame)
end

for frame = 1, 3 do
    nupp.hotreload.poll()
    render(frame)
end
```

## Ship to any Lua runtime

A build's _dialect_ says which Lua it lowers for. Where a construct needs a
runtime facility rather than syntax, that facility is a named _capability_, and
a backend supplies it as a versioned seam carrying the compiler's own
conformance suite for that contract. Selection is checked: a seam with no
implementation is a diagnostic at the construct that needed it, never a silent
substitute that means something else.

So one source tree becomes a LuaJIT build that keeps FFI structs and native
operations, a `lua51` build of plain Lua that any Lua from 5.1 to 5.4 can
`require`, or a [Wasm host](guides/wasm-aot/index.html) running `@aot` kernels
in the same linear memory. [Build for multiple
targets](guides/portable-libraries/index.html).

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

## Nupp is a single binary and can build single binaries

Check, format, build, test, profile, generate documentation, explain errors,
power an editor, and even build standalone binaries all from the same
language-aware compiler. No glue scripts required.

```text
nupp check                # type-check the project
nupp fmt                  # apply Nupp's fixed style
nupp test                 # build and run the bundled parallel test runner
nupp build --target dist  # stamp a self-contained binary
nupp run --profile        # write a speedscope-compatible profile
nupp lsp                  # start the language server
```

<!-- /nupp:features -->

::: columns

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

## Performance

- [Performance](guides/performance.md)
- [Ahead-of-time compilation](guides/ahead-of-time.md)
- [Wasm AOT applications](guides/wasm-aot.md)
- [LuaJIT trace checking](guides/jit-trace-checking.md)
- [Profiling](guides/profiling.md)

## Guides

- [Build and dependencies](guides/build.md)
- [Embedding](guides/embedding.md)
- [Hot reload](guides/hot-reload.md)
- [Portable libraries](guides/portable-libraries.md)
- [Integrations](guides/integrations/index.md)

  - [LuaRocks](guides/integrations/luarocks.md)
  - [LuaCATS definitions](guides/integrations/luacats.md)
  - [LÖVE](guides/integrations/love.md)

:::
