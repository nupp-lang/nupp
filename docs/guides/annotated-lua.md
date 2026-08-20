# Annotated Lua

Nupp always reads recognized LuaCATS, EmmyLua, and typed LuaDoc comments in a
`.lua` module. No manifest key enables it and no setting disables it. The Lua
source remains the runtime source; imported aliases, interfaces, parameters,
results, local types, varargs, and overloads exist only while checking.

Each example below pairs annotated Lua with a normalized `.g.nupp` spelling of
the facts Nupp derives from it. The Nupp view is not generated runtime code. It
omits the now-redundant comments and arranges declarations for readability; the
`migrate` command preserves the comments when it writes the real file.

## Aliases, classes, and functions

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

A class comment becomes an interface; Nupp does not invent a constructor or
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

An `@type` attached to a later assignment is also an assertion at that
assignment boundary. Negative casts and casts of expressions rather than local
names cannot be represented and recover with `NUPP1008`.

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
signature. Overloads describe additional callable contracts; they do not
select a body or add a runtime dispatcher.

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
and `@treturn` carry types.

The importer accepts the common type intersection of the three dialects
without configuration: primitives, named and literal types, unions, optionals,
arrays, maps, shapes, tuples, functions, varargs, classes, aliases, fields,
parameter and result tags, and callable overloads.

## Recovery

An annotation is never allowed to make the Lua file unreadable. A malformed or
unsupported type becomes `any` at the narrowest affected position and reports
a `NUPP1008` warning. A malformed overload is omitted. Other annotations in the
same block still apply.

Foreign generic declarations currently recover their generic positions to
`any` because Lua annotation dialects do not state Nupp's ownership mode or
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

The `migrate` command dispatches by file extension:

```bash
nupp migrate --check --json src/users.lua
nupp migrate src/users.lua
```

For annotated `.lua`, the destination is the same module at `.g.nupp`.
`--check` returns the destination, complete text, edits, and warnings without
writing. The writing form refuses an existing destination, writes the
destination atomically, parses and checks it, then removes the source only
after that check succeeds. `--dialect` accepts `auto`, `luacats`, `emmy`, or
`luadoc` as an ambiguity hint for migration; it does not control ordinary
annotation ingestion.

The Visual Studio Code action **Migrate annotated Lua to Nupp** sends the
current unsaved text to the same planner. Nupp does not register its full
language service for Lua, so LuaLS can continue to own completion, formatting,
and semantic highlighting. VS Code asks for confirmation before applying the
create-and-remove workspace edit.

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
syntax-compatible annotated file is also passed through the checker. An
importer or checker crash, or a dropped annotation, fails the task.
