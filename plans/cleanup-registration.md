# Registering a terminal named in a type

> **Status: blocked.** The checker side works. Generated code does not register the
> cleanup, so a discharge fails at run time. This is the one thing the rest of the
> `@owned` retirement waits on.

## What is being built

`Owned<T, cleanup>` names a terminal in the type that carries it:

```nupp
cdef function malloc(size: uint64): voidptr
cdef function free(takes value: voidptr)

function m.take(): Owned<voidptr, free>
    return malloc(64)
end
```

This exists for types that cannot carry a `@drop` of their own. A C pointer has
nowhere to write one, and `voidptr` is shared by everything in a project, so a
terminal attached to that type would be wrong for every other use of it. Naming the
terminal at the producer is what `@owned(cleanup)` does today, and moving it into
the type is what lets `@owned` go.

## Why registration exists at all

A cleanup is not called directly. The prologue emits a lazy resolver per cleanup:

```lua
local __nuppCleanups=_G.__nuppCleanupRegistry;
if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;
local __nuppCleanup1;__nuppCleanup1=function(value)
  local cleanup=__nuppCleanups["oc#free"];
  if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: oc#free") end;
  __nuppCleanup1=cleanup;return cleanup(value) end;
```

The registry is process-wide, so a module can discharge an owner whose terminal was
declared elsewhere. Something has to write `__nuppCleanups["oc#free"]=free`.

Keys are `origin#name`, or `origin#name#N` for a second declaration of one name in a
module, where origin is `result.moduleName or filename`. The key is also part of the
interned identity of every owned type discharged by it, because `types.owned` interns
on the ids of the cleanups it is given.

## The failure

`gen.nupp` writes the registry in exactly one place: the `pragmaStmt` branch, once
for registrations marked `after` and once for the rest. A terminal named in a type
has no annotation statement, so nothing writes it. The module checks clean, builds,
and then:

```
false	Nupp cleanup provider is not loaded: oc#free
```

Reproduce with the module above plus a caller that lets the owner fall out of scope,
then `dofile` the generated Lua.

## What has been tried

**Mark the declaration during checking, emit at that declaration.** `resolveCleanups`
knows the name; set a flag on the definition node and have gen emit the write when it
emits that declaration. The mark never arrives: `entry.definition` for a cdef function
has `kind == "function"`, which is not the `cdefFunc` node gen emits from. The two are
different objects, so the checker cannot hand gen the node it needs this way.

**Emit a module-level block before the module's return.** Correct in principle -- the
call site resolves through the registry on first use and remembers the answer, so the
write only has to land before anything discharges an owner, and a module finishes
loading before its functions run. The hook was wrong: `result.root` is a chunk whose
children are *blocks*, not statements, so a test for `child.kind == "returnStmt"` never
matches and the registrations were appended after `return m`:

```
NUPP3005: generated code does not load: '<eof>' expected near '__nuppCleanups'
```

## Constraints found along the way

**`emit` is at Lua's 60-upvalue ceiling.** Adding three locals for registration state
reported `NUPP3005: this function captures more than 60 names from around it`. Any
design where `emit` consults new state is effectively blocked. This is what rules out
checking a per-node mark during emission, and it is why tracking which keys a pragma
already wrote was dropped -- writing the same key to the same function twice is the
same assignment, so the duplicate is harmless.

**The build blocks its own replacement.** A compiler that generates invalid code
cannot compile the fix; `bin/nupp` falls back to the last one that built, which
silently answers with the previous behaviour. `nupp clean` drops to the tracked
bootstrap instead, which predates the feature and reports a *different* error
(NUPP2603, an owner with no terminal). Read which compiler answered before believing
an error.

## The two candidate designs

**Emit inside the top-level block.** Iterate the last top-level block's statements in
the outer scope, where the emitter and its state are already visible, and write the
registrations immediately before its trailing `returnStmt`. Costs `emit` no upvalues.
The risk is that delegating to `emit(block)` also does block-level work -- a block
with `automaticOwners` carries a cleanup frame -- so bypassing it needs a guard and a
suite run to confirm nothing else depended on it.

**Splice into the assembled source.** After `local code = table.concat(out)`, insert
the registrations before the final top-level `return`. No upvalue cost and no
traversal question, but it is string surgery on generated Lua.

The first is preferred. The second is the fallback if block-level handling turns out
to matter.

## How to know it works

A module that names a terminal in a type must, after `nupp build`, contain a
`__nuppCleanups["<origin>#<name>"]=<name>` write, load under LuaJIT, and discharge the
owner without raising. The case that exercises the guard is a module with both a
top-level owner and a type-named terminal.

## What waits on this

`Owned<T, cleanup>` is also the *selector* for a type with more than one inherited
terminal -- `src/nupp/io/http.nupp` has four `@drop` declarations, and the checker
reports "bare @owned has multiple inherited @drop operations; choose one with
@owned(cleanup)". Without a way to name a terminal in a type, retiring `@owned`
requires instead a rule of one terminal per type, and `http.Body` has to change first.
