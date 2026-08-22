---
order: 530
---

# LÖVE

LÖVE runs your game under LuaJIT. Nupp's `luajit-compat` target keeps that
runtime model: it lowers Nupp syntax LuaJIT does not parse while retaining
LuaJIT FFI, native representations, and ordinary Lua modules.

Start with the built-in project:

```bash
nupp init love my-game
cd my-game
nupp task play
```

The template's `nupp.lua` builds the game to `build/` and starts that directory
with LÖVE. `nupp test` remains headless and tests the game logic without
starting the event loop.

## LÖVE's API surface

The template declares the full LÖVE API as a pinned LuaCATS type dependency:

```lua [nupp.lua]
dependencies = {
   love = {
      kind = "types",
      format = "luacats",
      source = {
         git = "https://github.com/LuaCATS/love2d.git",
         rev = "<full commit id>",
      },
      path = "library",
   },
}
```

That makes LÖVE's `love` global available directly to Nupp source:

```nupp
function love.draw()
   love.graphics.setColor(0.35, 0.8, 1)
   love.graphics.rectangle("fill", 32, 220, 48, 48)
end
```

Nupp fetches the pinned definitions when it checks or builds, then reads their
annotations only. LÖVE still supplies the actual global at runtime; no type
file is copied into `build/` and the definition repository is not vendored.

## Existing games

Keep existing files as `.lua` while you migrate. Nupp reads their LuaCATS
comments, and a `.g.nupp` file can adopt typed syntax before it reaches the
strict `.nupp` boundary. The generated game can continue to require ordinary
Lua modules and use LuaJIT's FFI APIs.

::: seealso
- [LuaCATS definitions](luacats.md) for pinning or updating the API source
- [Gradual typing](../concepts/strictness.md) for the file-by-file migration
- [Target dialects](../guides/build.md#dialect-selection) for choosing
  `luajit-compat`
:::
