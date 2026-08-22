---
order: 510
---

# LuaCATS definitions

LuaCATS describes an existing Lua API with comments such as `---@class`,
`---@field`, and `---@param`. Nupp understands those comments in ordinary Lua
modules, and a `kind = "types"` dependency imports a whole LuaCATS definition
tree as ambient checker facts.

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
- [Annotated Lua](../guides/annotated-lua.md) for importing annotations from a
  project-owned `.lua` module
- [Build dependencies](../guides/build.md#type-dependencies) for the manifest
  contract shared by every type provider
:::
