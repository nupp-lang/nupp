---
order: 510
---

# LuaCATS and annotated Lua

LuaCATS describes an existing Lua API with comments such as `---@class`,
`---@field`, and `---@param`. Nupp always reads recognized LuaCATS, EmmyLua,
and typed LuaDoc comments in an ordinary `.lua` module: no manifest key enables
it and no setting disables it.

::: code-group
```lua [users.lua]
---@alias UserId integer

---@class User
---@field id UserId
---@field name? string

local users = {}

---@param id UserId
---@return User
function users.find(id)
    return { id = id, name = "Ada" }
end

return users
```

```nupp [users.g.nupp (Nupp view)]
local users = {}

local type UserId = integer
type users.UserId = UserId

local interface User
    id: UserId
    name: string?
end
type users.User = User

function users.find(id: UserId): User
    return { id = id, name = "Ada" }
end

return users
```
:::

The Lua source remains the runtime source; the imported aliases, interfaces,
parameters, results, local types, varargs, and overloads exist only while
checking. Each example below pairs annotated Lua with a normalized `.g.nupp`
spelling of the facts Nupp derives from it. The Nupp view is not generated
runtime code: it omits the now-redundant comments and arranges declarations for
readability, where [migrate](#migration) preserves the comments when it writes
the real file.

A class comment becomes an interface, and Nupp does not invent a constructor or
change how its tables are built. `find` has type `function(id: UserId): User`,
and both `UserId` and `User` are published as type-only members of the returned
module.

## Unions, collections, and several results

LuaCATS arrays and generic tables map to Nupp arrays and indexers. Separate
return tags form one result pack.

::: code-group
```lua [describe.lua]
---@param status "queued"|"running"|"done"
---@param tags string[]
---@param counts table<string, integer>
---@return boolean
---@return string?
local function describe(status, tags, counts)
    return counts[status] ~= nil, tags[1]
end

return describe
```

```nupp [describe.g.nupp (Nupp view)]
local function describe(
    status: "queued" | "running" | "done",
    tags: {string},
    counts: {[string]: integer}
): boolean, string?
    return counts[status] ~= nil, tags[1]
end

return describe
```
:::

Literal types, unions, optionals, arrays, maps, shapes, tuples, and function
types use the same checked meanings they have in Nupp syntax after their common
dialect spellings are translated.

## Local types and casts

`@type` applies positionally to names in a local declaration. A positive
`@cast` adds an explicit checker assertion without changing the Lua value.

::: code-group
```lua [payload.lua]
---@type string, integer
local name, count = "Ada", 1

local payload = decode()
---@cast payload table<string, string>
payload.name = name

return payload, count
```

```nupp [payload.g.nupp (Nupp view)]
local name: string, count: integer = "Ada", 1

local payload = decode()
payload = payload as {[string]: string}
payload.name = name

return payload, count
```
:::

A `@type` attached to a later assignment is also an assertion at that assignment
boundary. Negative casts, and casts of expressions rather than local names,
cannot be represented and [recover](#recovery) instead.

## Varargs

::: code-group
```lua [summarize.lua]
---@param prefix string
---@vararg integer
---@return string
---@return integer
local function summarize(prefix, ...)
    return prefix, select("#", ...)
end

return summarize
```

```nupp [summarize.g.nupp (Nupp view)]
local function summarize(prefix: string, ...: integer): string, integer
    return prefix, select("#", ...)
end

return summarize
```
:::

The vararg tag describes every value in `...`; it does not package them into an
array or change Lua's value-adjustment rules.

## Overloads

Every `@overload` signature joins the parameter-and-return signature as an
intersection. Calls are checked against the complete overload set.

::: code-group
```lua [normalize.lua]
local legacy = require("legacy")

---@overload fun(value: string): integer
---@param value integer
---@return string
local function normalize(value)
    return legacy.normalize(value)
end

return normalize
```

```nupp [normalize.g.nupp (Nupp view)]
local legacy = require("legacy")

local type Normalize = function(value: string): integer
    & function(value: integer): string

local normalize: Normalize = function(value)
    return legacy.normalize(value)
end

return normalize
```
:::

The function body is checked against the primary `@param` and `@return`
signature. Overloads describe additional callable contracts; they do not select
a body or add a runtime dispatcher.

## Typed LuaDoc

Typed LuaDoc puts the type before the parameter name. Nupp recognizes that
ordering as well as the LuaCATS and EmmyLua forms above.

::: code-group
```lua [greet.lua]
-- @tparam string name name to greet
-- @treturn string the greeting
local function greet(name)
    return "Hello, " .. name
end

return greet
```

```nupp [greet.g.nupp (Nupp view)]
local function greet(name: string): string
    return "Hello, " .. name
end

return greet
```
:::

Plain LuaDoc `@param` is prose when the LuaDoc dialect is selected; `@tparam`
and `@treturn` carry types. The interoperable subset across the three dialects
needs no configuration: primitives, named and literal types, unions, optionals,
arrays, maps, shapes, tuples, functions, varargs, classes, aliases, fields,
parameter and result tags, and callable overloads.

## Recovery

An annotation is never allowed to make the Lua file unreadable. A malformed or
unsupported type becomes `any` at the narrowest affected position and reports a
`NUPP1008` warning. A malformed overload is omitted. Other annotations in the
same block still apply.

A declaration file is never allowed to make the rest of its tree unreadable
either. A file in a `kind = "types"` dependency that cannot be read, parsed, or
checked is skipped and reported as a `NUPP1009` warning against the file, and
the declarations beside it are imported as usual. A pinned upstream tree is
somebody else's source: one corner of it spelled in a way this importer has yet
to learn costs that corner, not the API.

Foreign generic declarations currently recover their generic positions to `any`,
because Lua annotation dialects do not state Nupp's ownership mode or
result-preservation contract:

::: code-group
```lua [keep.lua]
---@generic T
---@param value T
---@return T
local function keep(value)
    return value
end

return keep
```

```nupp [keep.g.nupp (recovered view)]
local function keep(value: any): any
    return value
end

return keep
```
:::

The generic comment remains in place for a later manual contract. Nupp does not
invent one or weaken public capability checks.

## Migration

The `migrate` command dispatches by file extension, and for annotated `.lua` the
destination is the same module at `.g.nupp`:

```bash
nupp migrate --check --json src/users.lua
nupp migrate src/users.lua
```

`--check` returns the destination, complete text, edits, and warnings without
writing. The writing form refuses an existing destination, writes the
destination atomically, parses and checks it, then removes the source only after
that check succeeds. `--dialect` accepts `auto`, `luacats`, `emmy`, or `luadoc`
as an ambiguity hint for migration; it does not control ordinary annotation
ingestion.

The Visual Studio Code action **Migrate annotated Lua to Nupp** sends the
current unsaved text to the same planner. Nupp does not register its full
language service for Lua, so LuaLS can continue to own Lua completion,
formatting, and semantic highlighting. VS Code asks for confirmation before
applying the create-and-remove workspace edit.

## LuaLS compatibility corpus

The repository carries no vendored upstream corpus and the ordinary suite is
offline. Run the explicit compatibility task when changing the importer:

```bash
nupp task annotated-lua-corpus
```

The task lazily downloads a pinned MIT-licensed LuaLS source archive, verifies
its SHA-256 digest, caches it under `build/corpus`, and feeds every real
annotation comment in every `.lua` file through the importer. Recoverable
warnings and files using Lua syntax outside LuaJIT's grammar are counted. Every
syntax-compatible annotated file is also passed through the checker. An importer
or checker crash, or a dropped annotation, fails the task.

## Shared type definitions

A `kind = "types"` dependency imports a whole LuaCATS definition tree as
ambient checker facts. Use this for APIs supplied by a host or another external
tool, rather than copying an adapter into the project.

```lua [nupp.lua]
return {
   dependencies = {
      host_api = {
         kind = "types",
         format = "luacats",
         source = {
            git = "https://example.com/host-api.git",
            rev = "<full commit id>",
         },
         path = "library",
      },
   },
}
```

`format = "luacats"` reads only `.lua` declaration files beneath `path`. Their
annotations and ambient assignments become globals and types available while
checking the project. The files are never executed, generated into the output,
or added to `package.path`.

## Pin the source

`source.rev` is required and must name a full Git commit ID. On `nupp check` or
`nupp build`, Nupp resolves that revision under `.nupp/deps/host_api`. The
language server resolves the same revision the first time it reads the project,
so an editor types a project the way its build does. A checkout already at the
pinned revision is confirmed locally and nothing is fetched, which is every
open after the first; the one that does fetch says so in the server's log.

To update a definition, choose a new upstream commit and change `source.rev`.
That keeps a project's checked API reproducible and makes the type-surface
change visible in version control.

## Runtime limits

A type dependency does not install a runtime package. If the host provides a
global, the definition merely describes that global. If the program needs an
ordinary Lua module at runtime, obtain it through the host, [LuaRocks](luarocks.md),
or the project's own deployment process.

The provider is intentionally generic: future readers can use the same
`kind = "types"` lifecycle and select their representation through `format`.
Today, `luacats` is the supported format.

::: seealso
- [Build dependencies](../build.md#type-dependencies) for the manifest
  contract shared by every type provider
- [LÖVE](love.md) for a host integration using the pinned LuaCATS definitions
:::
