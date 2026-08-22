---
order: 510
redirects: guides/annotated-lua
---

# LuaCATS and annotated Lua

LuaCATS describes an existing Lua API with comments such as `---@class`,
`---@field`, and `---@param`. Nupp always reads recognized LuaCATS, EmmyLua,
and typed LuaDoc comments in an ordinary `.lua` module. The source remains the
runtime source; the imported facts exist only while checking.

## Project-owned Lua

No manifest setting enables annotation ingestion. Nupp reads aliases, classes,
fields, function parameters and returns, local types, varargs, casts, and
overloads from a project-owned Lua module:

```lua [users.lua]
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

The checker sees `UserId`, `User`, and
`function(id: UserId): User`; Nupp does not invent a constructor or change how
the tables are built. LuaCATS arrays and `table<K, V>` become Nupp arrays and
indexers, and several `@return` tags form one result pack.

`@type` applies positionally to a local declaration. A positive `@cast` creates
a checker assertion at the named local or assignment without changing the Lua
value. `@overload` signatures form an intersection with the ordinary parameter
and result signature. Typed LuaDoc's `@tparam` and `@treturn` forms work too.

Malformed or unsupported annotations recover to `any` at the narrowest affected
position and report a `NUPP1008` warning; an annotation never makes valid Lua
unreadable. Foreign generic positions also recover to `any`, because those
dialects do not state Nupp's ownership and result-preservation contracts.

`nupp migrate src/users.lua` writes the same module as `.g.nupp`, preserving
the annotations while adding the equivalent typed syntax. Its `--dialect`
option accepts `auto`, `luacats`, `emmy`, or `luadoc` to resolve migration
ambiguity; ordinary annotation ingestion needs no dialect setting.

## Supported annotation forms

The interoperable subset includes primitives, named and literal types, unions,
optionals, arrays, maps, shapes, tuples, functions, varargs, classes, aliases,
fields, parameters, results, and callable overloads. A vararg tag describes
each value in `...`; it does not turn the values into an array or change Lua's
value-adjustment rules. Function bodies are checked against their primary
`@param` and `@return` signature, while overloads describe additional call
contracts and do not add a runtime dispatcher.

The Visual Studio Code action **Migrate annotated Lua to Nupp** uses the same
planner on unsaved text. It creates the `.g.nupp` file only after parsing and
checking it, then removes the Lua source. Nupp does not register a complete
language service for Lua, so LuaLS can continue to own Lua completion,
formatting, and highlighting.

The ordinary test suite is offline. When changing annotation support, run
`nupp task annotated-lua-corpus` to fetch the pinned LuaLS compatibility corpus
and exercise its real comments. The task verifies the archive digest, caches it
under `build/corpus`, and fails if the importer or checker crashes or drops an
annotation in a syntax-compatible file.

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
language server uses an existing checkout when present and does not fetch just
because an editor opened the project.

To update a definition, choose a new upstream commit and change `source.rev`.
That keeps a project's checked API reproducible and makes the type-surface
change visible in version control.

## What this is not

A type dependency does not install a runtime package. If the host provides a
global, the definition merely describes that global. If the program needs an
ordinary Lua module at runtime, obtain it through the host, [LuaRocks](luarocks.md),
or the project's own deployment process.

The provider is intentionally generic: future readers can use the same
`kind = "types"` lifecycle and select their representation through `format`.
Today, `luacats` is the supported format.

::: seealso
- [Build dependencies](../guides/build.md#type-dependencies) for the manifest
  contract shared by every type provider
- [LÖVE](love.md) for a host integration using the pinned LuaCATS definitions
:::
