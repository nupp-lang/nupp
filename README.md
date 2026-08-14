# Nupp

*A typed programming language for LuaJIT.*

Nupp is a gradually typed superset of LuaJIT's Lua dialect, implementing every
[LuaJIT 3.0 syntax extension](https://github.com/LuaJIT/LuaJIT/issues/1475) and
adding to them rather than subtracting
([docs/grammar.abnf](docs/grammar.abnf)). Most of that syntax is written
straight through to the output, because LuaJIT 2.1 backported it; generated
code needs LuaJIT 2.1.1784535649 or newer. Unlike every existing typed Lua, its
types are not always erased: `struct` declarations lower to FFI cdata (fixed
layout, no hash lookups) and C headers import as typed declarations. Owned
resources are affine: an `Owned<T, cleanup>` result records a deterministic
cleanup obligation, `takes` calls move it, borrows cannot escape, and
`pinned<T>` handles keep Lua-managed pointers alive across declared
`retains`/`releases` C calls. Raw-pointer reconstruction is confined to
explicit `unsafe do` blocks. See [docs/ownership.md](docs/ownership.md). A
trace-aware checker (types that know what the JIT will compile) is on the
roadmap ([plans/todo.md](plans/todo.md)).

A file's extension says which floor it is held to, so it is visible where the
file is rather than in a setting that governs everything at once: `.nupp` is
checked strictly, `.g.nupp` is the same typed syntax with the strict floor
down, and a plain `.lua` file is Lua, built and run unchanged, with the typed
layer refused in it. The marker is not part of the module's name, so
`require("models")` finds `models.g.nupp` and a file can change layer without
anything that requires it noticing. `nupp check --strict` holds every file to
the floor whatever it is called. See
[docs/type-system/overview.md](docs/type-system/overview.md).

Compiler and lint output includes stable codes, source spans, related
locations, repair help, and structured fixes; see
[docs/diagnostics.md](docs/diagnostics.md).

<img src="docs/public/images/nupp.png" alt="Nupp" width="460" align="center"/>
