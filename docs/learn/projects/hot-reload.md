---
order: 560
---

# Hot reload

`nupp run --watch app.nupp` runs a program on the VM and replaces the bodies of
functions you edit while it keeps running. Every function in the VM is an id, and
a commit replaces the body stored at that id, so closures already made, methods
and direct calls all enter the new body on their next call. Reload is
cooperative, so the program calls `nupp.hotreload.poll()` at a point where
changing future calls is safe:

```nupp:fragment
while running do
    nupp.hotreload.poll()
    update()
end
```

Call `poll` between units of work, when no update or request is partially
applied. Application state, registered callback values and module tables stay in
place; only future calls enter new bodies.

Watch mode refuses an `-O` level other than `-O0`.

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

A generation may change the bodies of existing named local functions, qualified
functions, record and struct methods, and the closures written inside them.
Captured locals keep the same cells, and existing function values compare equal
before and after a commit. Every call that starts after the commit enters the
newest body, recursive calls and calls from other modules alike.

A changed body may create closures the running code never had; they are added
with it. A closure a body no longer creates stays as it was for the values
already made from it.

A syntax or type error rejects the candidate and leaves the last good generation
running. The runtime checks every module's patch against the code it is running
before it replaces any body, so a multi-module change lands whole or not at
all.

Before staging, Nupp rechecks every loaded module through the incremental
semantic dependency graph, so a changed global declaration, imported module
interface, or C declaration is observed even when the source form of a function
signature did not change. Unrelated declarations stop at their dependency
boundary and do not force a restart.

::: deepdive
A function's identity is its lexical parent, its name, and its position among
same-named siblings, so a module lowered again after an edit matches the running
one function for function even when adding a closure renumbers everything after
it. The patch is the module's new image with that match beside it; the runtime
checks the calling convention, captures and record layouts again against the
code it actually loaded before it replaces anything, because a partly-applied
patch is the behavior of no version of the source. The program owns the commit
boundary because there is no generally safe moment to swap an implementation,
and only the program knows which one it is in.

:::

### C declarations

Checked `cdef` declarations are compared by stable aggregate or
library-and-symbol identity rather than as one source-order-sensitive module
string. The comparison covers checked layout, callable ABI, library, and Nupp
ownership contracts, and a generation records the declarations installed by
module initialization alongside those used by each retained function.

Reordering equivalent declarations is therefore not a C change, though moving
one at a module's top level is still a top-level change. Changing a
retained declaration, removing it, or making a replacement body use a
declaration the running module never installed requires restart. A raw or
indirect FFI operation that cannot be assigned a complete identity retains the
conservative module-wide C comparison, which can cause an extra restart but
cannot make an unsafe edit pass.

### Imported headers

Imported headers are part of the running session's dynamic watch set. A direct
[`cheader`](../runtime/c-interop/index.md#type-the-header-in-place) observes the
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

The mapping applies to `cdef ... from "mini"`, and only watch mode consults it:
a watched module loads the exact resolved file, and the session observes that
path, its symlink target, and its bytes. Ordinary builds continue to name the
authored loader and are byte-identical to builds made without this
configuration. A `cheader(..., "mini")` or `ffi.load("mini")` that names the
same loader is observed the same way.

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

```nupp:fragment
@comptime
function M.derive(info: nupp.derive.Info): nupp.derive.Result<M.Contract>
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
[derives.md](../../reference/derives.md) for the provider surface.

## Changes that require restart

Restart after changing any top-level executable statement or initializer,
adding, removing, renaming or moving a named declaration, changing a callable
signature or capture set, or changing a record, struct, native or component
layout. Changes to C declarations, imported header declarations, and configured
native artifacts also require a restart: the old C declarations, loaded
library, and any values created from them already exist in the VM.

A changed derive-provider file also requires restart. Nupp observes and rechecks
it, but does not migrate values or generated declaration state that the old
recipe may already have created.

A restart result identifies the changed semantic dependency, its source path,
and the loaded module that requires it. Structural reasons likewise identify the
callable, capture, or module boundary that made the candidate incompatible.

### Callbacks and running calls

A callback registered with a library is reloaded like any other function,
anonymous or named, because the value the library holds names the function's
id:

```nupp:fragment
server:onMessage(function(message: string): nil
    -- body may be reloaded
end)
```

Code that never reaches `poll` cannot reload. A call already executing finishes
on the body it entered, and that includes a task parked inside a changed
function: it resumes on its old body, while every later call enters the
replacement. The old body stays alive as long as a frame runs it.

A cleanup a scope or an owner registered is a function value too, so an edited
cleanup body runs for cells that are still live. A change to what such a cell
holds is a record or struct layout change, and requires restart.

Watch mode runs the images `nupp run` runs. Nothing is added to a program to
make it reloadable, so a watched program behaves as an ordinary run of the same
source does.

The guarantees on this page are indexed to executable compiler-session, runtime,
and standalone-command cases in `tests/hotreloadguaranteetest.lua`, and the
runtime's half to `native/crates/vm/tests/hot_patch.rs`. The standalone cases
edit a required module inside `nupp run --watch` processes.

## FAQ

### Does watch mode change what an ordinary build produces?

No. A watched program is lowered exactly as an ordinary one is; what watch mode
adds is a compiler session beside it and the runtime's body patch, neither of
which reaches a build.

### Why did an edit to one function body still require a restart?

Nupp rechecks every loaded module before staging, so an edit that also changed
an exported type, a C declaration, or a capture set reaches further than the
body it was written in. The restart result names the semantic dependency that
changed and the module that requires it.

### Can a callback registered with a library be reloaded?

Yes, named or anonymous: see [Callbacks and running calls](#callbacks-and-running-calls).

::: seealso
- [build.md](build.md) for the ordinary build that ships
- [c-interop.md](../runtime/c-interop/index.md) for the C declarations a watch
  session tracks
:::
