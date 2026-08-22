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

`src/lovehost.lua` is the small LuaCATS-annotated LÖVE surface this example
uses. It is local and versioned with the game. Nupp does not yet have an
ambient, type-only Git dependency mechanism for loading the full LuaCATS LÖVE
definitions. Replace or expand this adapter as the game uses more of LÖVE's
API.
