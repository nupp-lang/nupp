---
order: 590
---

# Integrations

These guides cover what Nupp reads from outside its own source: what stays
ordinary Lua, what Nupp checks, and which declarations are available without
writing an adapter.

| Integration | What it covers |
| --- | --- |
| [LuaCATS](luacats.md) | Project annotations and pinned, checker-only API definitions. |

::: seealso
- [File types](../../language/file-types.md) for moving a Lua file into Nupp
  without changing how other modules load it
- [LuaCATS](luacats.md) for the comments Nupp reads in ordinary `.lua` files
- [Native modules](../native-modules.md) when a Rust application embeds the VM
:::
