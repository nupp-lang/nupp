# ${name}

A small LÖVE game written in Nupp.

```sh
nupp check      # type-check the game and its LÖVE API boundary
nupp build      # compile the game into build/
nupp test       # build, then test game logic without LÖVE
nupp task play  # build, then start the game with LÖVE
```

The target uses `luajit-compat`: it lowers Nupp's newer LuaJIT syntax for an
embedded runtime while retaining LuaJIT FFI and native representations.

The full LÖVE API surface comes from the pinned LuaCATS `kind = "types"`
dependency in `nupp.lua`. Nupp fetches it into `.nupp/deps/love` and reads its
annotations only: it is neither executed nor copied into `build/`.
