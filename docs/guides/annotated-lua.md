# Annotated Lua

Nupp always reads recognized LuaCATS, EmmyLua, and typed LuaDoc comments in a
`.lua` module. No manifest key enables it and no setting disables it. The Lua
source remains the runtime source; imported aliases, interfaces, parameters,
results, local types, varargs, and overloads exist only while checking.

```lua
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

A Nupp module requiring this file sees `find(integer): User`, including the
fields of `User`. Public aliases and classes are also published as type-only
module members. The importer accepts the common type intersection of the three
dialects without configuration: primitives, named and literal types, unions,
optionals, arrays, maps, shapes, tuples, functions, varargs, classes, aliases,
fields, parameter and result tags, and callable overloads.

## Recovery

An annotation is never allowed to make the Lua file unreadable. A malformed or
unsupported type becomes `any` at the narrowest affected position and reports
a `NUPP1008` warning. A malformed overload is omitted. Other annotations in the
same block still apply.

Foreign generic declarations currently recover their generic positions to
`any` with `NUPP1008`. Lua annotation dialects do not state Nupp's ownership
mode or result-preservation contract, and Nupp does not invent one or weaken
the public capability checks. The comment remains in place for a later manual
contract.

## Migration

One command handles source migrations, dispatching by file extension:

```bash
nupp migrate --check --json src/users.lua
nupp migrate src/users.lua
```

`.lua` becomes the same module at `.g.nupp`. `--check` returns the destination,
complete text, edits, and warnings without writing. The writing form refuses an
existing destination, writes the destination atomically, parses and checks it,
then removes the source only after that check succeeds. `--dialect` accepts
`auto`, `luacats`, `emmy`, or `luadoc` as an ambiguity hint for migration; it
does not control ordinary annotation ingestion.

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
