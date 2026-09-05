---
order: 510
---

# Embedding Nupp

`libnupp` lets a C application own the process and event loop while checked
Nupp modules run in an embedded LuaJIT state. The host loads a prebuilt
component, calls named exports, and keeps collector-managed values alive with
opaque handles.

```c [Lifecycle]
nupp_config config;
nupp_runtime *runtime = NULL;
nupp_component *component = NULL;
nupp_error *error = NULL;

nupp_config_init(&config);
nupp_runtime_new(&config, &runtime, &error);
nupp_component_load(runtime, bytes, length, "game.nuppc", &component, &error);
nupp_component_start(runtime, component, 0, NULL, &error);
nupp_component_release(component);
nupp_runtime_shutdown(runtime, &error);
nupp_runtime_free(runtime);
```

This fragment shows the ownership order. A complete host also checks every
returned status and releases its error values; see [Errors](#errors) for that
boundary.

Embedding and [checked C interop](../runtime/c-interop/index.md) point in opposite
directions. Embedding starts with a C application and brings Nupp into it.
Checked C interop starts with Nupp source and gives that source typed access to
a C API. An embedded application can use both boundaries.

::: info
The current SDK is built from a Nupp source checkout. It does not yet ship as
an installed package with CMake or `pkg-config` metadata. The
`host/include/nupp.h` header and the library `scripts/toolchain` builds are
the public embedding surface.
:::

## Complete example

The repository carries a C application example in `host/examples/embed.c` and
its component project in `host/examples/component`. The example calls the
public C ABI implemented by the Rust-owned SDK; it is not the removed legacy C
host implementation. Build the component from its project directory:

```bash
cd host/examples/component
nupp build
```

The project manifest names one application entry and one callable export:

```lua [host/examples/component/nupp.lua]
return {
    include = {"src"},
    build = {
        kind = "component",
        description = "Build the embeddable example component",
        entries = {"app.main"},
        exports = {"game.answer"},
    },
}
```

Each export is a dotted member of a declared module:

```nupp [host/examples/component/src/game.nupp]
module game

export function answer(value: integer): integer
    return value + 1
end
```

`nupp build` writes `build/component.nuppc`. A component records its format,
[compiler host ABI](../../reference/distribution.md#compiler-host-abi), entry
module, public exports, layout target, required host features, modules, and
resources. It is application data, not a shared library and not a stable C ABI
for Nupp records or closures.

The example entry also uses `nupp.log` and `nupp.data.json`. Compiler-provided
modules reached by a component are compiled into the component with their
runtime dependency closure, including providers selected through runtime seams;
the embedding host does not need a Nupp module tree on its Lua search path.

Build the Rust-owned `libnupp` SDK from the repository root:

```bash
SDK=$(./scripts/toolchain host-library \
  lpeg,native-files,native-net,native-process,native-tls,workers)
cc -std=c11 -I"$SDK" host/examples/embed.c \
  -L"$SDK" -lnupp -Wl,-rpath,"$SDK" -o build/embed-nupp
```

The same SDK directory contains `libnupp.dylib` on macOS, `libnupp.so` on
Linux, or `nupp.dll` plus `libnupp.dll.a` on Windows. `link.json` names the
header, static library, dynamic library, exact features, and Windows import
library when present. Put the directory on the platform's dynamic-library
search path, then run the host:

```bash
DYLD_LIBRARY_PATH="$SDK" \
  build/embed-nupp host/examples/component/build/component.nuppc
```

```text
game.answer(41) = 42
```

Use `LD_LIBRARY_PATH` instead of `DYLD_LIBRARY_PATH` on Linux. Static linking
uses `libnupp.a`, which contains the pinned LuaJIT VM, the Rust host, and the
exact-feature Rust native provider. A static application may still need the
ordinary platform libraries named by its C linker; the SDK does not require
separate LuaJIT, LPeg, or provider archives.

## Runtime ownership

A runtime either owns a new state or attaches to one supplied by the host. The
choice fixes who closes the state.

| Form | Creation | Standard libraries | `lua_close` |
| --- | --- | --- | --- |
| Owned | `nupp_runtime_new` | Opened by default | Called by Nupp after shutdown |
| Attached | `nupp_runtime_attach` | Already open, or requested in the config | Never called by Nupp |

Initialize `nupp_config` before changing any field. Its `size` and
`abi_version` let the library reject a caller built for an incompatible
embedding ABI.

```c
nupp_config config;
nupp_config_init(&config);

nupp_runtime *runtime = NULL;
nupp_error *error = NULL;
nupp_status status = nupp_runtime_new(&config, &runtime, &error);
```

`NUPP_CONFIG_OPEN_LIBRARIES` is the only current flag and is enabled by
`nupp_config_init`. Pass a null config to `nupp_runtime_new` for the same
default.

### Attached LuaJIT states

Attachment keeps the host's allocator, heap, globals, module tables, and GC.
It verifies that the state is LuaJIT 2.1.1784535649 or newer before publishing
Nupp's host record.

```c
nupp_config config;
nupp_config_init(&config);
config.flags = 0;

nupp_runtime *runtime = NULL;
nupp_status status = nupp_runtime_attach(existing_state, &config, &runtime, &error);
```

Use `flags = 0` only when the host already opened the libraries the component
needs. Leave `NUPP_CONFIG_OPEN_LIBRARIES` enabled when Nupp must call
`luaL_openlibs` during attachment. The host must keep the state alive until
after `nupp_runtime_free`, and it must not call `lua_close` while Nupp owns
registry roots in the state.

`nupp_runtime_lua_state` returns the application state for a host which also
uses the Lua C API. Calls made directly through that API use the host's stack
discipline and protection rules; the managed Nupp calls described below do not
manage a stack frame the host creates itself.

## Host configuration

Modules, features, and resources are registered before the first successful
component load. The set freezes at that point so generated code cannot observe
providers appearing while it runs.

```c
nupp_runtime_preload(runtime, "engine.clock", luaopen_engine_clock, &error);
nupp_runtime_add_feature(runtime, "engine.clock", &error);
nupp_runtime_add_resource(runtime, "engine/defaults.json", data, length, &error);
```

An AOT archive that contains a Lua builder has one more registration before the
component is loaded. Link the archive into the executable, then pass its
registrar and the key generated in the component binding to the runtime:

```c
extern int ks_register_example(lua_State *state);

nupp_runtime_register_aot_builders(
    runtime, "ks_register_example", ks_register_example, &error
);
```

The registrar runs with the embedded runtime's Lua state and returns the table
of builder functions for that archive. Registration is rejected after the first
component load, just like every other provider registration. Static AOT code
without a Lua builder needs no registration: its generated binding resolves C
symbols from the process image.

`nupp_runtime_preload` accepts an ordinary `lua_CFunction` and places it in
`package.preload`. Requiring `engine.clock` from Lua or Nupp invokes the opener
once through normal Lua module semantics. The opener is compiled against
LuaJIT's C headers and returns values on the Lua stack in the usual way.

A feature is a deployment capability name. Component loading rejects a
component whose compiler-recorded requirements are absent. A resource is
copied during registration, so the caller may release its input buffer after
the call returns. Host resources are for runtime and provider glue; component
resources declared in `nupp.lua` remain available through the ordinary
`nupp.embedded` module.

A registration attempted after component loading returns
`NUPP_STATUS_RUNTIME`. Configure every provider before loading any component,
including a library component whose entry will never start.

### Static AOT components

A component target selects static AOT with `aotLinkage = "static"` and
`aot = "require"`. Its build produces the ordinary component plus an AOT
archive under `outDir/lib`. The archive is input to the embedding application's
link, not a file the component will discover at runtime.

The host contract is four items:

1. Link and retain the archive.
2. Expose its AOT and probe symbols to the VM's default C namespace.
3. Call each builder registrar with the owned `lua_State *`.
4. Call `nupp_runtime_register_aot_builders` before `nupp_component_load` for
   each builder registrar.

The build writes `outDir/aot/link.json` saying what those are for one archive:
its path, the probe symbol and the value it must return, every exported kernel
and registrar symbol, the builder keys the host owes, and the retain and export
flags the target's linker takes. See
[Static AOT components](build.md#static-aot-components) for its shape. The host
also constructs the component with the same target ABI. Numeric and span kernels
then resolve through the process image; substituting `ffi.load` would
reintroduce the dynamic-loader dependency this mode avoids.

Retention is a physical link requirement, not something a generated wrapper can
recover from: an FFI lookup creates no undefined C reference, so a linker
reading the archive normally extracts nothing from it. The archive therefore
exports a probe every rewritten module checks first. An archive that was never
linked, or one stripped by the linker, reports that it is not in the default C
namespace; an archive from a different build of the component reports that
instead. An unregistered builder reports itself the same way. All three are host
deployment errors and all three say so at load.

Use static AOT when the application owns the final link or cannot rely on a
dynamic loader. Use the default shared AOT linkage when components must travel
and update independently of the host. Static archives share one C namespace,
so the compiler qualifies their generated AOT and registrar symbols.

## Component lifecycle

Loading, starting, and releasing are separate operations.

1. `nupp_component_load` validates the format and host ABI, checks required
   features and name collisions, and installs module loaders.
2. `nupp_export_find` may obtain a library export before the application entry
   starts.
3. `nupp_component_start` runs the entry exactly once and installs its `arg`
   table from the supplied arguments.
4. `nupp_component_release` releases the C wrapper, not the modules installed
   in the runtime.

```c
nupp_component_load(runtime, bytes, length, "game.nuppc", &component, &error);
nupp_export_find(runtime, component, "game.answer", &answer, &error);
nupp_component_start(runtime, component, argc, argv, &error);
```

The compiler-owned descriptor runs during loading, but application module top
levels do not. An exported module loads lazily on its first export call. The
entry module loads only when the host starts the component, unless another
module required it first.

Multiple components can share one runtime. A component carries the
compiler-provided runtime modules reached by its generated code, including
standard-library modules. Byte-identical copies are shared by components in the
same runtime; loading refuses a different copy under the same name. Project and
dependency modules still refuse any name already present in `package.loaded` or
`package.preload`, and a public export name claimed by an earlier component is
also refused. These checks run before the new module loaders are installed.

Component unloading is unsupported. Tables, closures, cdata, native state, or
opaque handles may already have escaped, so releasing `nupp_component` cannot
make its Lua modules disappear safely. Closing an owned state reclaims all of
it. An attached state keeps installed module entries after Nupp shuts down; the
host reclaims them when it closes that state.

## Calling an export

`nupp_export_find` roots a named callable in the runtime registry and returns a
`nupp_handle`. The handle remains valid across Lua collections until the host
releases it or shuts down the runtime.

```c
nupp_handle *answer = NULL;
nupp_status status = nupp_export_find(
    runtime, component, "game.answer", &answer, &error
);
```

The managed call boundary has a deliberately small value vocabulary:

| Kind | C fields | Crossing behavior |
| --- | --- | --- |
| `NUPP_VALUE_NIL` | none | Lua `nil` |
| `NUPP_VALUE_BOOLEAN` | `boolean` | Copied |
| `NUPP_VALUE_NUMBER` | `number` | Copied binary64 |
| `NUPP_VALUE_STRING` | `data`, `length` | Copied bytes intended as UTF-8 text |
| `NUPP_VALUE_BYTES` | `data`, `length` | Copied arbitrary bytes |
| `NUPP_VALUE_HANDLE` | `handle` | Existing runtime registry root |

Input string and byte pointers need to remain live only for the duration of
`nupp_call`. A number is binary64; the generic boundary does not preserve an
integer wider than binary64 can represent exactly. Use the Lua C API or an
explicit native interface when an exact wider integer is part of the contract.

```c
nupp_value argument = {0};
nupp_value result = {0};
size_t result_count = 0;

argument.kind = NUPP_VALUE_NUMBER;
argument.number = 41.0;
nupp_status status = nupp_call(
    runtime, answer, &argument, 1, &result, 1, &result_count, &error
);
```

Every non-scalar Lua result, including a table, function, thread, userdata, or
cdata value, returns as `NUPP_VALUE_HANDLE`. Passing that value into a later
call pushes the rooted Lua value. A handle belongs to one runtime; calls reject
a handle from another runtime or one already released.

Returned strings and bytes own their buffers. Release every written result
with `nupp_value_release`; that function also releases a result whose kind is
`NUPP_VALUE_HANDLE`. Release the standalone callable returned by
`nupp_export_find` with `nupp_handle_release`.

```c
nupp_value_release(runtime, &result, &error);
nupp_handle_release(runtime, answer, &error);
```

`nupp_call` writes the number of returned values to `result_count`. If the
callable returns more values than `result_capacity`, the call has already run,
its results are discarded, and the status is
`NUPP_STATUS_BUFFER_TOO_SMALL`. Supply a buffer sized for the export's
contract; do not retry a side-effecting export only to enlarge the buffer.

## Garbage collection

Embedded Nupp does not add another application collector. Ordinary Lua,
generated Nupp modules, and the host's Lua objects occupy the same state and
run under the same LuaJIT GC.

Copied scalars and byte sequences have no GC relationship after a public call
returns. Opaque handles are Lua registry roots, not object addresses, so a full
collection cannot invalidate them. `nupp_handle_release` removes exactly that
root and makes the handle unusable.

Nupp's [ownership contracts](../runtime/ownership/borrowing.md#borrowing-and-pinning)
govern native pointers retained by FFI calls. Pinning a Lua-managed owner and
rooting a value solve different lifetime problems: the pin protects a native
relationship described to the checker, while the registry handle keeps a Lua
value reachable for the calling application.

::: deepdive
Nupp runs in the host's own state, on the host's own heap. A second embedded VM
would mean two collectors, two object models, and a marshaling layer between
code that is the same language. Raw pointers into collector-managed values are
never exposed as a public object ABI, which is the line an embedding API is most
tempted to cross and the one that would constrain the runtime permanently: a
published address is a promise about object layout that every later change to
the runtime has to keep.

See [NEP 8](../../neps/0008-c-interop-and-embedding.md) for more information.
:::

## Errors

Every fallible public function returns `nupp_status` and accepts an optional
`nupp_error **`. On failure, the error owns its message until
`nupp_error_free`. Component evaluation, entry calls, and export calls are
protected and return Lua failures through this boundary.

```c
static int report(nupp_status status, nupp_error *error) {
    if (status == NUPP_STATUS_OK) return 0;
    fprintf(stderr, "nupp: %.*s\n",
        (int)nupp_error_message_length(error),
        nupp_error_message(error));
    nupp_error_free(error);
    return 1;
}
```

The status describes how the operation ended; the category describes the
source of the owned error.

| Status | Meaning |
| --- | --- |
| `NUPP_STATUS_INVALID_ARGUMENT` | A required pointer, UTF-8 name, value kind, or vector shape is invalid |
| `NUPP_STATUS_INCOMPATIBLE` | The public ABI or attached LuaJIT is incompatible |
| `NUPP_STATUS_RUNTIME` | Component or application work failed |
| `NUPP_STATUS_BUFFER_TOO_SMALL` | A completed call returned more values than fit |

The current categories are configuration, compatibility, component, and
runtime. `nupp_error_status` repeats the returned status when an error object
must cross another API boundary. Passing a null `nupp_error **` discards the
owned detail but does not change the returned status.

Initialize or clear the caller's error pointer before reusing it. Each call
sets the output to null before doing work; it does not free an older error the
caller failed to release.

## Threads and polling

Status-returning runtime calls are affine to the OS thread which created or
attached the runtime. A call from another thread returns a runtime error.
`nupp_runtime_lua_state` returns null there because it has no error output.
Cross-thread work uses a queue whose consumer enters Nupp on the runtime
thread, or independent LuaJIT states with no shared handles.

`nupp_runtime_poll` is an explicit host boundary. The current core validates
the runtime lifecycle and thread there; it does not install a scheduler or
resume application coroutines by itself. A host-provided suspension handler
keeps readiness and event-loop policy outside the runtime.

## Shutdown

Release public values before shutting down so their C wrappers and registry
roots can both be retired cleanly:

```c
nupp_value_release(runtime, &result, &error);
nupp_handle_release(runtime, answer, &error);
nupp_component_release(component);
nupp_runtime_shutdown(runtime, &error);
nupp_runtime_free(runtime);
```

Call shutdown on the runtime thread. It releases component and handle roots,
then closes an owned state. Attached shutdown leaves the host's state open.
`nupp_runtime_free` performs best-effort teardown but returns no status, so an
application which needs cleanup failures calls `nupp_runtime_shutdown`
explicitly first.

After shutdown, ordinary runtime operations fail. Calling shutdown again is
allowed and succeeds; double-freeing any C pointer remains invalid C.

## Authority and limits

Embedding is not a hostile-code sandbox. Standard libraries, LuaJIT FFI,
`debug`, native modules, and host callbacks can grant process authority. Treat
component bytes with the same trust as other executable application code.

The current embedding release has these deliberate limits:

- components remain installed until the runtime is destroyed;
- the managed number kind is binary64 rather than an exact integer family;
- `nupp_runtime_poll` does not provide a scheduler;
- the in-process compiler and host-driven hot-reload APIs are not exposed yet.

The current C header remains the authority for the implemented ABI.

::: seealso
- [c-interop.md](../runtime/c-interop/index.md#type-mapping) for how C types cross
  into checked Nupp source
- [build.md](build.md#compiler-native-features) for what a component target
  stages beside the payload
- [distribution.md](../../reference/distribution.md#payload) for the container a
  stamped binary uses instead
:::
