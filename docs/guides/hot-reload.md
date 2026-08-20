# Hot reload

`nupp run --watch app.nupp` builds a development-only version of a program in
which named functions and methods keep their public identity while their bodies
change. Reload is cooperative, so the host calls `nupp.hotreload.poll()` at a
point where changing future dispatch is safe:

```nupp
while running do
    nupp.hotreload.poll()
    update()
end
```

Call `poll` between units of work, when no update or request is partially
applied. Application state, registered callback values and module tables stay in
place; only future calls through named function slots enter new bodies.

Watch mode is always an `-O0` build. Run the ordinary optimized build before
release: optimizer passes can change control flow, allocation and JIT behavior
that watch mode does not exercise.

## Start, edit, reload

Save this as `app.nupp`. It prints once, waits for Enter, then polls and prints
again:

```nupp
local function message(): string
    return "version one"
end

while true do
    nupp.hotreload.poll()
    print(message())
    io.read("*l")
end
```

Start it in one terminal:

```console
$ ./bin/nupp run --watch app.nupp
version one
```

While it is still running, change only the function body:

```diff
 local function message(): string
-    return "version one"
+    return "version two"
 end
```

Press Enter in the running terminal. The next poll commits the edit, and the
same process calls the new body:

```console
nupp: committed hot generation 2
version two
```

The first poll also acknowledges a long-running entry module as initialized.
Lazily required modules join the running generation only after their top level
returns successfully. Editing an unloaded module emits no patch; its current
source is compiled when it is first required.

## Accepted edits

A generation may change bodies of existing named local functions, qualified
functions, and record or struct methods. Mutable captured locals retain the same
lexical cells, and existing function values compare equal before and after a
commit. Direct self-recursion stays inside the implementation generation that
the call entered; mutual and cross-module calls go through the newest committed
slot.

A syntax or type error rejects the candidate and leaves the last good generation
running. A compatible multi-function patch is staged completely before any slot
changes, and commit flushes LuaJIT traces.

Before staging, Nupp rechecks every loaded module through the incremental
semantic dependency graph, so a changed global declaration, imported module
interface, or C declaration is observed even when the source form of a function
signature did not change. Unrelated declarations stop at their dependency
boundary and do not force a restart.

::: deepdive
Staging proves a whole patch compatible before commit touches any slot, because
a partly-applied patch is what makes reload untrustworthy: the reported behavior
is then the behavior of no version of the source. The host owns the commit
boundary because there is no generally safe moment to swap an implementation,
and only the program knows which one it is in.

See [NEP 6](../neps/0006-hot-reload.md) for more information.
:::

### C declarations

Checked `cdef` declarations are compared by stable aggregate or
library-and-symbol identity rather than as one source-order-sensitive module
string. The comparison covers checked layout, callable ABI, library, and Nupp
ownership contracts, and a generation records the declarations installed by
module initialization alongside those used by each retained function.

Reordering equivalent declarations therefore produces `no-change`. Changing a
retained declaration, removing it, or making a replacement body use a
declaration the running module never installed requires restart. A raw or
indirect FFI operation that cannot be assigned a complete identity retains the
conservative module-wide C comparison, which can cause an extra restart but
cannot make an unsafe edit pass.

### Imported headers

Imported headers are part of the running session's dynamic watch set. A direct
[`cheader`](../concepts/c-interop.md#type-the-header-in-place) observes the
resolved header itself. A `cheader` using `"preprocess"` also asks the
configured C compiler for its complete include closure and observes every
contributing header. Header paths are canonicalized, so two forms of the same
path are polled once while each importing site retains its own diagnostic
identity.

A header-only edit therefore wakes `run --watch` without touching a `.nupp`
file. Comments and layout-neutral whitespace are rechecked but produce
`no-change` when the declarations have the same meaning. A changed aggregate
layout, callable ABI, symbol or toolchain identity requires restart before a
patch can stage. A missing retained header rejects the candidate and remains in
the watch set.

### Native libraries

C declarations describe a contract; they do not identify the binary that
implements it. Watch mode can pin authored loader names to exact artifacts in
`nupp.lua`:

```lua
return {
  hotreload = {
    libraries = {
      mini = "build/lib/libmini.dylib",
    },
  },
}
```

The mapping applies to `cdef ... from "mini"`, `cheader(..., "mini")`, and a
statically known `ffi.load("mini")`. Only watch generation consults it. The
generated watch chunk loads the exact resolved file, and the session observes
that path, its symlink target, and its bytes. Ordinary builds continue to emit
the authored loader name and are byte-identical to builds made without this
configuration.

A bare loader name remains legal, but watch mode reports once that its binary
identity is unverified. A dynamically computed `ffi.load` argument is likewise
reported as untracked rather than silently receiving a stronger guarantee.

::: deepdive
Replacing, removing, or retargeting a configured artifact requires a process
restart, and Nupp deliberately does not unload or replace a library in the live
VM. Old cdata, callbacks, function pointers, and native state can still belong
to the loaded image, and nothing available at the swap point can prove that
every one of them is gone.
:::

### Provider inputs

An exported derive provider may read an immutable project file with a literal
path:

```nupp
comptime function M.derive(info: nupp.derive.Info): nupp.derive.Result<M.Contract>
    local schema = nupp.derive.file("schemas/widget.txt")
    -- Build a closed recipe from schema.
end
```

The compiler resolves the path from the consumer project root before isolated
provider evaluation. Its bytes participate in the provider memo key and the
incremental query graph, and a loaded consumer adds the canonical path to the
dynamic watch set. Changing or removing the file rechecks that consumer and
requires restart before its already-generated members can diverge from live
state.

A dynamic path or one outside the project root is rejected. Providers remain
isolated and cannot use arbitrary filesystem, network, environment, clock, or
process-global state as an undeclared semantic dependency. See
[derives.md](../reference/derives.md) for the provider surface.

## Changes that require restart

Restart after changing any top-level executable statement or initializer,
adding, removing, renaming or moving a named declaration, changing a callable
signature or capture set, or changing a record, struct, native or component
layout. Changes to C declarations, imported header declarations, and configured
native artifacts also require a restart: the old FFI declarations, loaded
library, and any values created from them already exist in the VM. A function
that takes [ownership](../concepts/ownership.md) of a cleanup-bearing capture is
also not patchable, and the diagnostic names the capture that selected the
affine lowering.

A changed derive-provider file also requires restart. Nupp observes and rechecks
it, but does not migrate values or generated declaration state that the old
recipe may already have created.

A restart result identifies the changed semantic dependency, its source path,
and the loaded module that requires it. Structural reasons likewise identify the
callable, capture, or module boundary that made the candidate incompatible.

### Named callbacks

Anonymous escaping closures are not yet patch identities. Give a long-lived
callback a name:

```nupp
local function receive(message: string): nil
    -- body may be reloaded
end

server:onMessage(receive)
```

Code that never reaches `poll` cannot reload. A call already executing finishes
on its old closure, and a later call enters the replacement. These
development-mode stack and dispatch semantics add no branch, registry, watcher,
runtime dependency or generated byte to an ordinary non-watch artifact.

### Persistent capability stores

A `nupp.owners.store` store that survives a patch belongs to the watch host, not
to a reloadable module capture. Generated watch modules include their stable
dynamic type-policy keys in staging.

A cleanup-body edit under the same cleanup declaration keeps the key, and old
entries call the patched function slot. A representation or cleanup-policy
change is rejected while a matching entry is live; removing or taking those
entries permits the next stage. Rejection leaves the store, handle generations,
and published hot generation unchanged.

The guarantees on this page are indexed to executable compiler-session, runtime,
and standalone-command cases in `tests/hotreloadguaranteetest.lua`. The
standalone cases edit a required module, a header, and a temporary native
library inside `nupp run --watch` processes.

## FAQ

### Does watch mode change what an ordinary build produces?

No. The reload machinery exists only in the watch generation, so an ordinary
build is byte-identical to one made without it. Watch mode is also always `-O0`,
so measure and ship the optimized build instead. See
[performance.md](performance.md) for what the optimization levels change.

### Why did an edit to one function body still require a restart?

Nupp rechecks every loaded module before staging, so an edit that also changed
an exported type, a C declaration, or a capture set reaches further than the
body it was written in. The restart result names the semantic dependency that
changed and the module that requires it.

### Can a callback registered with a library be reloaded?

Only when it was registered by name. An anonymous closure has no patch identity,
so declare the function and pass the name, as
[Named callbacks](#named-callbacks) shows.

::: seealso
- [profiling.md](profiling.md) for finding where a running program spends time
- [build.md](build.md) for the ordinary optimized build that ships
- [c-interop.md](../concepts/c-interop.md) for the C declarations a watch
  session tracks
- [NEP 6](../neps/0006-hot-reload.md) for the design record
:::
