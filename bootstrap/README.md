# Bootstrap compiler

`nupp.lua` is a generated compiler bundle, committed so a fresh checkout can
build itself without an already-installed `nupp`. It is the whole of the stage-0
compiler: one file, needing nothing beside it but LuaJIT — 2.1.1784535649 or
newer. It is generated Nupp, and generated Nupp is written in the syntax
extensions that build backported; whether this particular file happens to
contain any depends on what the compiler sources are written with today, and
is not something to depend on.

That includes the standard-library declarations. A build leaves them on disk in
`decls/` next to the compiled modules; the bundle carries them inside itself, as
a `package.preload["nupp.embedded"]` table of path to source, and `nupp.env`
looks there before it looks on disk.

## Refreshing it

Do not edit the generated file directly. After changing compiler sources, run
`nupp fixpoint --update-bootstrap`; it verifies the two-stage self-hosting
fixpoint and rebuilds the bundle from `build/nupp`, declarations included.
