---
order: 480
---

# Integrations

Nupp is designed to join an existing Lua program a file, module, or package at
a time. These guides cover the surrounding runtime or ecosystem: what stays
ordinary Lua, what Nupp checks, and which declarations are available without
changing the host's execution model.

| Integration | Status | What it covers |
| --- | --- | --- |
| [LuaRocks](luarocks.md) | Available | Typed libraries, dependencies, packing, and publication. |
| [LuaCATS](luacats.md) | Available | Project annotations and pinned, checker-only API definitions. |
| [LÖVE](love.md) | Available | A LuaJIT-compatible game project with the full LÖVE API surface. |
| Neovim | Planned | A tested host guide and template are not available yet. |
| OpenResty | Planned | A tested host guide and template are not available yet. |

The planned entries are deliberately not setup guides. A host belongs here once
its integration has a reproducible example or template, rather than when it is
only expected to work.

::: seealso
- [Gradual typing](../../concepts/strictness.md) for moving a Lua file into Nupp
  without changing how other modules load it
- [LuaCATS](luacats.md) for the comments Nupp reads in ordinary `.lua` files
- [Embedding Nupp](../embedding.md) when a C application owns the
  process and event loop
:::
