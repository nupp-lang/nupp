# Embedding Nupp

`libnupp` embeds checked Nupp components in applications that would otherwise
embed LuaJIT directly. An owned runtime creates Nupp's pinned LuaJIT state; an
attached runtime installs Nupp into a compatible state supplied by the host.
Both forms use one application heap and collector.

The stable boundary is C. Build it with:

```sh
cargo build --release --manifest-path host/Cargo.toml --lib
```

This produces static and dynamic `libnupp` libraries. The public declarations
are in `host/include/nupp.h`, and `host/examples/embed.c` is a complete host.

## Build a component

A component installs modules without running their top levels. Its entry runs
only when the host calls `nupp_component_start`; an exported module is loaded
when that export is first called.

```lua
return {
   include = {"src"},
   build = {
      kind = "component",
      entries = {"game.main"},
      exports = {
         "game.update",
         "game.shutdown",
      },
   },
}
```

`nupp build` writes `build/component.nuppc` by default. The artifact records its
component format, compiler host ABI, entry, exports, layout target and required
host features. Installation checks every module and export name before changing
the runtime; a collision or unavailable feature rejects the whole component.

## Runtime lifecycle

Initialize `nupp_config` with `nupp_config_init`, then use
`nupp_runtime_new`. An application which already owns a compatible state may
instead use `nupp_runtime_attach`; attached shutdown removes Nupp's roots but
does not call `lua_close`.

Before loading the first component, a host may:

- register a `lua_CFunction` with `nupp_runtime_preload`;
- declare a capability with `nupp_runtime_add_feature`;
- copy bytes into the host resource record with `nupp_runtime_add_resource`.

These registrations freeze at the first successful component load. Runtime
operations are thread-affine: call them on the OS thread which created or
attached the runtime.

Every operation which can fail returns a `nupp_status`. Its optional
`nupp_error` owns the message until `nupp_error_free`; component evaluation,
entry calls and export calls are protected and return Lua failures through that
error value.

Shutdown explicitly with `nupp_runtime_shutdown`, then release the opaque
runtime with `nupp_runtime_free`. Releasing a component handle does not unload
its modules. Component unload is deliberately unsupported because tables,
closures, cdata and native state may already have escaped.

## Calling exports and garbage collection

`nupp_export_find` returns a runtime-scoped rooted handle. `nupp_call` copies
nil, booleans, binary64 numbers and strings/bytes. Other Lua values cross as
opaque handles. A returned string or byte sequence is owned by its
`nupp_value`; release it with `nupp_value_release`. Release a standalone handle
with `nupp_handle_release`.

Handles are registry roots rather than object addresses. They remain valid
across full Lua collections, reject use with another runtime and become invalid
as soon as they are released. No public API exposes a pointer into a
collector-managed record, table, closure or string.

For direct Lua integration, `nupp_runtime_lua_state` returns the application
state. The host may then use the ordinary Lua C API and is responsible for its
own stack discipline.

## Authority and safety

Embedding Nupp is not a hostile-code sandbox. Full Lua libraries, FFI, native
modules and host callbacks can grant process authority. Select features before
load and treat component bytes with the same trust as other application code.

Nupp's ownership checker still governs retained native pointers and affine
cleanup. It complements the collector; it does not replace it with a second GC.
The application Lua and Nupp modules share the same state, roots and collection
cycles.
