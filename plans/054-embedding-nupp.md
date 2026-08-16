# Embed Nupp as an application language

Status: in progress

Implemented in the first runtime slice:

- reusable owned and attached runtime core consumed by `nupp-host`;
- static and dynamic `libnupp` artifacts with a versioned C header;
- host feature, module and copied-resource registration before load freeze;
- deterministic `component` targets with separate install and start phases;
- module/export collision and compiler-host compatibility checks;
- named export lookup, copied scalar/string values and GC-rooted handles;
- explicit shutdown, structured errors and wrong-thread/lifecycle checks;
- a compiled C example and embedding guide.

Production AOT artifact loading, the in-process compiler service, host-driven
hot reload and packaged multi-platform SDK discovery remain later phases below.

## Decision

Make Nupp embeddable anywhere a compatible LuaJIT can be embedded. The public
product is a stable C SDK around one application LuaJIT state, Nupp's generated
runtime, compiler-owned native providers, private AOT artifacts and an optional
development compiler. The existing standalone host becomes one consumer of the
same library rather than the only way to run a Nupp payload.

There are two supported runtime ownership forms:

1. a host asks Nupp to create and own the pinned LuaJIT state;
2. a host attaches Nupp to a compatible `lua_State` it already owns.

Both run ordinary Lua and checked Nupp modules in the same state and therefore
on the same LuaJIT heap. Nupp does not put a second application VM, collector or
object model beside the host's Lua integration. A production host loads a
prebuilt component and does not carry the compiler. A development host may
create a compiler service in a separate private state, feed it source through a
virtual filesystem and commit compatible hot-reload generations at boundaries
the host chooses.

The public C API catches every Lua error before returning to the host. Managed
values cross it through the Lua stack, copied scalar values, or explicitly
rooted opaque handles. Raw pointers into collector-managed values do not become
a public object ABI.

This plan does not make Nupp a binary-compatible replacement for every
`libluajit` build. It provides an owned pinned distribution and an explicit
attached-state contract. An attached host must use the LuaJIT syntax, C API and
runtime features the selected Nupp release requires, and must not load a second
conflicting LuaJIT implementation into the process.

## Goal

An application which can host LuaJIT can host Nupp with the rest of the
language and toolchain available by deliberate layers:

- ordinary Lua and generated Nupp modules share `require`, globals and GC;
- checked FFI declarations call host, linked and sidecar native code;
- ownership, pins and affine cleanup govern retained native relationships;
- compiled `@aot` functions load as private implementation artifacts;
- host modules, resources, logging and scheduling enter through callbacks;
- runtime errors and compiler diagnostics leave as structured data;
- an optional compiler checks source without invoking a subprocess;
- an optional hot session prepares changes while the running generation stays
  intact, then commits only when the host declares a safe point.

The first complete demonstration is a small C application which creates a
runtime, registers one native module, loads one component from memory, calls an
export, runs one AOT function, receives one structured failure and shuts down
with every rooted and affine resource released.

## Why embedding is a language boundary

Nupp already has most of the mechanisms an embedded language needs, but they
are reached through separate command-line paths:

- `host/src/lua.rs` creates a state, opens libraries, installs selected native
  modules, publishes `__nuppHost` and executes a protected chunk;
- `host/src/main.rs` finds an appended payload and owns process arguments,
  output and exit status;
- `nupp.compiler.build.package` produces deterministic bundles and enforces the
  compiler host ABI and required feature set inside the payload;
- a compiler-owned stub may be replaced by an engine-owned stub without
  changing the payload format;
- suspension handlers already put scheduling policy in the host rather than in
  the language;
- hot reload already separates a persistent compiler session, inert patch
  staging and a host-selected commit boundary;
- the AOT prototype already separates verified IR, generated C and the checked
  Nupp wrapper which calls it.

What is absent is one reusable lifetime and error boundary. The current host is
a binary, creates its own state, prints a string failure and exits. The current
bundle executes its entry as part of loading. The compiler APIs are internal
Nupp modules whose callers supply filesystem and CLI-derived state. An engine
can reuse the ideas today, but cannot link one supported SDK and rely on a
versioned contract.

Embedding makes those existing boundaries public and tests them independently
of the standalone command. It also lets Nupp serve its strongest application
domain: an engine, editor, server, desktop application or plugin host which
wants Lua's integration model with Nupp's types, ownership, diagnostics and
optional AOT execution.

## Governing invariants

1. **One application state.** Ordinary Lua and Nupp application code run in one
   LuaJIT state and share its collector. A development compiler uses a separate
   private state and shares no Lua object with the application.
2. **The host owns policy.** Nupp owns checking, lowering, component validation
   and language cleanup. The application owns its main loop, scheduler, logging,
   source transport and safe reload boundary.
3. **No Lua jump crosses C.** Every public operation runs beneath a protected
   call and converts failure into a returned status and owned error value.
4. **No unrooted managed escape.** A collector-managed value that outlives one
   call is represented by a runtime-scoped registry handle. Releasing the handle
   removes exactly that root.
5. **No second native ABI for Nupp objects.** Records, tables, closures,
   coroutines and strings do not receive exposed C struct layouts. Reified
   structs and AOT spans use their existing explicit layout and pointer/count
   boundaries.
6. **Runtime calls are thread-affine.** One state is entered from its owning OS
   thread. Parallel application work uses independent states or the existing
   workers facility.
7. **Features freeze before execution.** A host declares and installs its native
   features before the first component runs. A loaded component cannot observe
   a provider set changing underneath it.
8. **Native images stay loaded.** A live runtime never unloads or replaces a
   native or AOT library. Hot reload reports a restart requirement when its
   identity or ABI changes.
9. **Production needs no compiler.** A production component is checked and
   lowered before distribution. Loading it performs compatibility and layout
   validation, not source compilation.
10. **The compiler performs no hidden toolchain work.** An embedded compiler may
    emit verified AOT C or an artifact request. Compiling and linking it goes
    through an explicit host toolchain callback or an offline build.
11. **The C ABI is versioned by shape and behavior.** Public structs begin with
    size and ABI-version fields where extension is needed. Unknown versions and
    unavailable required callbacks are refused rather than guessed.
12. **Embedding is not a sandbox claim.** LuaJIT FFI, `debug`, `os`, native
    providers and host modules can grant process authority. A restricted host
    must select an explicit library and capability profile; checked Nupp alone
    is not an isolation boundary for hostile code.

## Runtime architecture

Refactor the current host into three layers:

```text
host/
|-- nupp-host-core     Rust library owning the LuaJIT/runtime mechanics
|-- libnupp            stable C-facing static or dynamic library
`-- nupp-host          existing executable, reduced to a core client
```

`nupp-host-core` owns:

- creating and closing a pinned LuaJIT state;
- attaching runtime state to a compatible host-owned `lua_State`;
- opening the configured standard-library profile;
- registering built-in and host-provided modules;
- publishing the host ABI and frozen feature set;
- loading, validating, starting and calling components;
- catching Lua errors and creating structured runtime failures;
- rooting and releasing opaque values;
- worker and private AOT artifact registration;
- ordered cancellation, affine cleanup and shutdown.

It does not:

- inspect process arguments;
- find the current executable;
- read an appended trailer;
- write to stdout or stderr;
- choose an exit status;
- poll a project directory;
- invoke a C compiler or linker.

`nupp-host` retains those standalone policies and calls the core. This preserves
the existing one-file binary and makes it the conformance consumer for the same
runtime applications embed.

### Owned and attached states

The owned library carries Nupp's pinned LuaJIT and exposes an opaque runtime.
The attached-state library is built without a second LuaJIT and resolves the C
API through the host's compatible link. Attachment verifies the LuaJIT version
floor and probes the syntax/runtime facilities generated Nupp requires before
installing any module.

An attached runtime never calls `lua_close`. An owned runtime always closes its
state after Nupp shutdown completes. The ownership choice is immutable and is
covered by repeated create/attach/destroy tests.

## Public C surface

The exact names may change before the ABI is frozen. The required shape is:

```c
typedef struct nupp_runtime nupp_runtime;
typedef struct nupp_component nupp_component;
typedef struct nupp_handle nupp_handle;
typedef struct nupp_error nupp_error;

typedef struct {
    uint32_t size;
    uint32_t abi_version;
    void *userdata;
    void (*log)(void *, const struct nupp_log_event *);
    void *(*resolve_native)(void *, const struct nupp_native_request *);
} nupp_config;

nupp_status nupp_runtime_new(
    const nupp_config *config,
    nupp_runtime **out,
    nupp_error **error
);

nupp_status nupp_runtime_attach(
    lua_State *state,
    const nupp_config *config,
    nupp_runtime **out,
    nupp_error **error
);

lua_State *nupp_runtime_lua_state(nupp_runtime *runtime);

nupp_status nupp_component_load(
    nupp_runtime *runtime,
    const void *bytes,
    size_t length,
    nupp_component **out,
    nupp_error **error
);

nupp_status nupp_component_start(
    nupp_component *component,
    int argc,
    const char *const *argv,
    nupp_error **error
);

nupp_status nupp_runtime_poll(
    nupp_runtime *runtime,
    nupp_error **error
);

nupp_status nupp_runtime_shutdown(
    nupp_runtime *runtime,
    nupp_error **error
);

void nupp_component_release(nupp_component *component);
void nupp_runtime_free(nupp_runtime *runtime);
void nupp_error_free(nupp_error *error);
```

Creation, configuration, loading, execution, shutdown and destruction are
separate. `free` is idempotent only where the C type can represent an empty
owner; double-freeing an arbitrary pointer remains invalid C. A failed explicit
shutdown may report cleanup errors, but `free` still performs the remaining
best-effort teardown and never calls application code after the state closes.

### Error values

Every error records:

- a stable machine code;
- a category such as configuration, compatibility, component, runtime, native,
  compiler or host callback;
- an owned message and byte length;
- a Nupp/Lua stack when one exists;
- a primary failure plus cleanup failures without replacing the primary;
- structured compiler diagnostics for compilation operations.

Strings returned in an error remain valid until `nupp_error_free`. The runtime
does not retain a host pointer to temporary error storage. Out-of-memory paths
have a fixed fallback status which requires no secondary allocation.

## Components rather than executing bundles

Add a `component` build target for artifacts intended to be loaded by another
process owner:

```lua
engineScripts = {
   kind = "component",
   entries = {"game.main"},
   exports = {
      "game.update",
      "game.render",
      "game.shutdown",
   },
}
```

A component contains or deterministically names:

- component format version and compiler host ABI;
- its compiled Nupp and Lua modules;
- embedded resources;
- required host features;
- optional application entry;
- exported callable names;
- selected target and layout identity;
- private native and AOT artifact requirements;
- optional source maps and debug metadata.

Loading validates and registers the component but does not execute its entry or
arbitrary module top level. Starting an application component explicitly runs
its entry. A library component may never start; the host calls one of its
exports instead.

The first representation may remain one generated Lua chunk which installs
preloads and returns an immutable component descriptor. The representation is
wrapped in a versioned component container before third-party artifacts are
promised stable. The existing bundle and stamped-binary formats remain
supported: the standalone host adapts their run-immediately behavior to the
new load/start lifecycle without changing existing outputs unnecessarily.

Multiple components may share one runtime. Duplicate module and public export
identities are refused before either component mutates the runtime. Component
unload is not in the first release because module tables, closures, cdata,
handles and native state may have escaped.

## Host modules, resources and features

The host can register facilities before the feature set freezes:

```c
nupp_status nupp_runtime_preload(
    nupp_runtime *runtime,
    const char *module,
    lua_CFunction opener,
    nupp_error **error
);

nupp_status nupp_runtime_add_feature(
    nupp_runtime *runtime,
    const char *feature,
    nupp_error **error
);

nupp_status nupp_runtime_add_resource(
    nupp_runtime *runtime,
    const char *path,
    const void *bytes,
    size_t length,
    nupp_error **error
);
```

The existing compiler host feature names and payload handshake remain the
authority. The library replaces Cargo-feature discovery with a constructed
feature record made from compiled providers and explicit host registrations.
Component loading compares its requirements before user code runs.

Resources are copied or retained under an explicit lifetime contract. A host
callback may provide lazy bytes, but it cannot hand the runtime a temporary
pointer which outlives the callback. Module openers are installed in
`package.preload`, preserving ordinary Lua `require` behavior.

The native resolver receives a structured request including logical library
name, component identity, target and expected artifact digest where one was
recorded. It may return a statically linked namespace or an approved path. A
dynamically computed `ffi.load` remains outside strong artifact identity in the
same way it is in watch mode today.

## Calling Nupp from a host

There are two public call layers.

### Lua C API layer

An engine already integrated with Lua uses `nupp_runtime_lua_state` and the
ordinary Lua C API. Nupp guarantees that installed components, modules and
exports live in that state. The engine remains responsible for Lua stack
discipline, while protected Nupp entry helpers keep language errors from
jumping across the outer application boundary.

### Managed value layer

A host which does not otherwise use Lua receives a deliberately small value
vocabulary:

- nil;
- boolean;
- signed and unsigned fixed-width integers;
- binary64 number;
- copied string or byte sequence;
- opaque rooted handle.

Conceptually:

```c
nupp_status nupp_export_find(
    nupp_component *component,
    const char *name,
    nupp_handle **out,
    nupp_error **error
);

nupp_status nupp_call(
    nupp_runtime *runtime,
    nupp_handle *callable,
    const nupp_value *arguments,
    size_t argument_count,
    nupp_value *results,
    size_t result_capacity,
    size_t *result_count,
    nupp_error **error
);

void nupp_handle_release(
    nupp_runtime *runtime,
    nupp_handle *handle
);
```

Tables, records, functions, threads, userdata and affine values initially cross
as handles. A later typed binding generator may project selected records into a
host language, but the generic runtime API does not recursively marshal an
unbounded or cyclic Lua object graph.

Handles record their owning runtime and registry generation. A handle from
another runtime, a released handle and a handle used after runtime shutdown are
reported in checked debug builds and rejected wherever the runtime can still
inspect them. The API never relies on LuaJIT object addresses remaining stable.

## Garbage collection and native lifetime

Embedding does not introduce a second application collector. Generated Nupp
records, tables, closures and strings remain ordinary objects in the attached
LuaJIT state. Reified structs remain cdata. The existing lexical ownership
rules remain the deterministic path for native resources; GC finalizers remain
a fallback.

The boundary follows four rules:

1. A managed result is copied during the call or rooted before the protected
   call ends.
2. A native pointer into Lua-managed storage cannot be retained without the
   existing `pinned<T>`, `retains` and `releases` contracts.
3. A private AOT function accepts scalars, fixed layouts and caller-owned spans;
   its implementation allocates no Lua object and needs no GC participation.
4. Shutdown first refuses new calls, cancels suspended work, drains language
   cleanup and releases component roots, then closes an owned state.

The SDK documents callback rooting, state ownership, string lifetimes and
shutdown ordering in C terms. Debug tests force collection between every host
operation which claims a value survives.

## AOT inside an embedded runtime

This plan consumes the production work described by
`plans/038-aot-functions.md`; it does not create a second AOT compiler. A
component build lowers required `@aot` bodies, verifies their IR, compiles the
private target C and emits the checked Nupp wrapper. The component records the
artifact identity and loader requirement.

The embedded runtime may obtain an AOT image from:

1. symbols statically linked into the host;
2. a host resolver callback;
3. a digest-identified sidecar path.

The image is private implementation, not the stable SDK ABI. The host calls the
ordinary exported Nupp wrapper; that wrapper performs span length and layout
checks before crossing once into the native function. A required AOT artifact
which is absent, built for the wrong target or reports a mismatched layout
stops component loading. It never silently falls back for that function.

An AOT or native image remains loaded until process termination. Development
replacement reports the same restart requirement hot reload uses for a changed
C library today.

## Optional embedded compiler

Introduce a compiler facade which is independent of command-line parsing,
stdout, process cwd and direct filesystem calls. Implement it first as an
internal checked Nupp module and expose the same operations through the C SDK.

The compiler service owns a private compiler state. The application state never
loads compiler modules and the compiler cannot retain application Lua values.
Inputs and outputs cross as copied bytes and immutable descriptions.

The host supplies a virtual project interface:

- read one source or declared input by canonical logical path;
- enumerate source roots;
- resolve a module name;
- read an imported header and its declared include inputs;
- report changed or removed inputs;
- supply a target and toolchain identity;
- cancel bounded compiler work.

The first facade operations are:

- create a project/session from explicit configuration;
- check one module or the complete source set;
- build an in-memory component;
- return structured diagnostics and fixes;
- return materialization, derive, native-feature and AOT observations;
- update source bytes and incrementally recheck affected modules;
- prepare a hot-reload candidate.

The existing JSON diagnostic schema remains the semantic schema. The C form
owns its strings and ranges rather than asking a host to parse JSON, while a
JSON adapter remains available for language bindings which prefer it.

Compile-time providers keep their existing isolation and declared-input rules.
The VFS does not grant arbitrary host filesystem, network, environment, clock
or process access. Native dependency acquisition, C compilation and linking are
not implicit compiler callbacks; the host opts into a separately described
toolchain operation.

## Host-driven hot reload

Reuse the compiler session and runtime patch protocol from
`plans/036-hot-reload.md`. Remove filesystem polling and terminal reporting
from the reusable surface:

```c
nupp_status nupp_session_change(
    nupp_session *session,
    const char *path,
    const void *bytes,
    size_t length,
    nupp_error **error
);

nupp_status nupp_session_prepare(
    nupp_session *session,
    nupp_update **out,
    nupp_error **error
);

nupp_status nupp_runtime_commit(
    nupp_runtime *runtime,
    nupp_update *update,
    nupp_error **error
);
```

The host decides how source changes arrive and when commit is safe. Preparing a
candidate may happen between frames or requests; commit remains one atomic
application-state operation on the runtime thread. A rejected candidate leaves
the last good generation and all application state intact.

The existing compatibility rules remain: body changes may patch; top-level
effects, signature or capture changes, layouts, installed C declarations and
native image identity may require restart. Commit flushes affected LuaJIT
traces. The standalone `nupp run --watch` implementation becomes the polling
adapter and conformance test for this host-neutral surface.

## Suspension and event loops

Embedding does not install one scheduler. A host exposes or loads a suspension
handler and enters it around application work exactly as described by the
existing language surface. A game ticks readiness once per frame; a server
integrates it with its request loop; a command-line host may block the current
thread.

The SDK provides enough protected-call and wakeup registration machinery for a
host module to implement `park`, `canPark` and `shutdown`. It does not resume a
Lua coroutine from another OS thread. Cross-thread completion queues a wake for
the runtime thread, which performs the resume at `nupp_runtime_poll` or another
explicit host boundary.

Runtime shutdown cancels outstanding waits and invokes handler shutdown before
releasing the state. A cleanup failure is attached to, and does not replace, an
earlier application failure.

## Security profiles

The default owned runtime matches the standalone host's useful language
environment. It is not safe for hostile plugins merely because their source
type-checks.

Add explicit library profiles before claiming restricted embedding:

- `full`: ordinary standalone libraries and selected native providers;
- `hosted`: the host supplies filesystem, process, network and scheduling
  policy;
- a future `restricted` profile only after FFI, dynamic loading, debug access,
  bytecode loading, resource exhaustion and native module authority all have
  enforceable limits.

Component metadata states which capabilities it requires. A restricted host
refuses an unavailable requirement rather than installing a permissive fallback.
This capability record is a deployment contract, not proof that arbitrary Lua
or native code is memory-safe.

## Implementation phases

### E1: reusable host core

- Turn the state and module code in `host/src/lua.rs` into a library-owned
  runtime object.
- Move payload discovery, argv handling, printing and exit status out of it.
- Make the existing host executable call the library.
- Add owned-state and attached-state lifetime tests.
- Preserve the existing host ABI, feature handshake and binary behavior.

Gate: the existing binary tests pass unchanged and a Rust library test loads a
bundle entirely from memory without touching process-global output.

### E2: C runtime ABI

- Build static and dynamic `libnupp` artifacts.
- Add the versioned public header and symbol visibility rules.
- Return owned structured failures from every protected operation.
- Add module, feature, resource and native-resolver registration.
- Add wrong-thread and lifecycle-state checks.
- Write a C conformance host using both owned and attached state forms.

Gate: the C host creates, runs and destroys one runtime repeatedly under
AddressSanitizer and UndefinedBehaviorSanitizer without leaks or a Lua jump
crossing the public call.

### E3: component lifecycle

- Add the manifest target and validation for `kind = "component"`.
- Split installation from entry execution.
- Record entries, exports, target layout and required features.
- Reject module/export collisions before installation.
- Adapt bundle and stamped-binary execution through the same load/start path.

Gate: one process loads two non-conflicting components, starts one application
entry and calls one library export while existing bundle and fixpoint tests
remain byte-identical where their format did not change.

### E4: managed calls and GC handles

- Add scalar/string/bytes values and runtime-scoped opaque handles.
- Root results before protected calls return.
- Specify string ownership and result-buffer behavior.
- Add deterministic handle release and shutdown auditing.
- Exercise a full GC between lookup, call, callback and release operations.

Gate: a non-Lua-aware C host calls a closure retained across collections and no
raw managed pointer enters the public ABI.

### E5: private AOT artifacts

- Complete the production AOT build path.
- Package artifact requirements with components.
- Resolve linked and sidecar images through the embedding runtime.
- Validate target and struct layouts before exports become callable.
- Carry missing/mismatched artifacts as structured component-load errors.

Gate: the C conformance host calls an `@aot` span function through its ordinary
Nupp export, and a corrupted or wrong-target artifact is refused before entry.

### E6: compiler service

- Create the host-neutral compiler facade.
- Bundle it as an optional compiler component in a private compiler state.
- Add the virtual project/input interface and cancellation.
- Return in-memory component bytes and structured diagnostics.
- Keep toolchain invocation outside implicit checking.

Gate: the C host compiles an in-memory `.nupp` source graph, loads the resulting
component into the application state and receives exact byte-based diagnostics
for an invalid edit without invoking `nupp` as a subprocess.

### E7: embedded hot reload

- Expose change, prepare, restart and commit operations.
- Make the standalone watcher an adapter over them.
- Commit only on the application runtime thread.
- Preserve the last good generation after compiler or compatibility failure.
- Report native and layout changes as restart requirements.

Gate: a frame-loop example patches a named function body, rejects a signature
change and continues running the prior generation after the rejection.

### E8: supported SDK distribution

- Publish headers, libraries, notices and compatibility metadata together.
- Add CMake and `pkg-config` discovery.
- Provide C, C++, existing-LuaJIT-state and game-loop examples.
- Build and test the SDK on supported Linux, macOS and Windows targets.
- Document static/dynamic linking, symbols, callbacks, GC and shutdown.

Gate: a clean external example repository builds only against the published SDK
and runs the same component on every supported platform.

## Verification matrix

Every supported release exercises:

- owned state and attached state;
- compatible and incompatible LuaJIT revisions/profiles;
- repeated create, load, start, shutdown and destroy cycles;
- component-format, host-ABI, feature and target-layout mismatch;
- in-memory operation with filesystem access disabled;
- ordinary Lua requiring Nupp and Nupp requiring ordinary Lua;
- a host-provided `lua_CFunction` module;
- statically linked and sidecar native providers;
- one scalar and one lane-lowered AOT function;
- forced collection with every public handle shape live;
- callback rooting and release;
- affine cleanup on success, runtime failure, cancellation and shutdown;
- wrong-runtime, stale-handle and wrong-thread failures;
- host callback failure and panic containment;
- compiler diagnostics, fixes and cancellation;
- accepted body reload and rejected structural/native reload;
- preservation of the last good generation;
- worker creation from an embedded component;
- ASan, UBSan and platform-native leak checking;
- existing payload determinism, binary stamping and self-host fixpoint.

Fuzz the component decoder and every length-bearing public value. A malformed
component, error string, resource name or host callback result must produce a
bounded failure without calling user code or reading past supplied bytes.

## Compatibility and release policy

Keep three versions distinct:

1. component container version: whether bytes can be located and decoded;
2. compiler host ABI: whether the runtime provides what generated code expects;
3. public embedding ABI: whether a compiled host can call this `libnupp`.

Target C layout remains a fourth, target-specific identity rather than being
folded into any of those. A release note says which prior component and public
ABI versions remain accepted. Additive C structure fields use the caller's
`size`; changed ownership or lifecycle behavior requires an ABI version rather
than an undocumented reinterpretation.

The pinned owned runtime, headers and libraries are one release unit. An
attached-state SDK records its exact compatibility floor and probes it at
attachment. The build refuses an accidental process containing two conflicting
LuaJIT copies instead of treating two equal C type spellings as proof of
runtime compatibility.

## Documentation and examples

Add an embedding guide organized around decisions a host must make:

1. owned or attached LuaJIT state;
2. production component or development compiler;
3. full or hosted capability profile;
4. Lua C API calls or managed handles;
5. blocking execution or host suspension handler;
6. restart-only deployment or compatible hot reload;
7. linked or sidecar AOT/native artifacts.

The examples are executable tests:

- `embed-minimal-c`: load bytes and call one scalar export;
- `embed-existing-lua`: add Nupp to a host-owned LuaJIT state;
- `embed-module`: publish an application C module to checked Nupp;
- `embed-game-loop`: suspension polling and safe hot-reload commit;
- `embed-aot`: call a private compiled span function;
- `embed-compiler`: compile source from an in-memory virtual project.

## Non-goals for the first release

- A drop-in binary ABI for arbitrary LuaJIT distributions.
- Loading two LuaJIT implementations into one process.
- Moving one runtime between OS threads while calls or handles are live.
- Concurrent entry into one state.
- Unloading a component or native image from a live state.
- Recursively converting arbitrary Lua object graphs to C values.
- Treating checked source as a hostile-code sandbox.
- Running a platform compiler or dependency downloader during production load.
- Compiling arbitrary Nupp bodies to AOT code; the admitted `@aot` subset stays
  governed by its own plan.
- Migrating live layouts or native state during hot reload.
- Replacing the host's scheduler, renderer, event loop or resource policy.

## Completion criteria

Embedding is released when an external C application can, without a subprocess
or temporary source file:

1. create an owned Nupp runtime or attach to a compatible LuaJIT state;
2. register a host module, feature and resource;
3. load a checked component from memory without executing it;
4. start its optional entry and call a named export;
5. retain and release a managed result across forced collections;
6. invoke a required AOT function and reject a mismatched artifact;
7. drive suspension from its own loop;
8. receive structured runtime and optional compiler diagnostics;
9. optionally prepare and commit a compatible source edit;
10. cancel outstanding work and shut down without leaked handles, skipped
    affine cleanup, an uncaught Lua jump or a second application collector.

At that point `nupp-host` is no longer the embedding implementation. It is the
smallest reference application built on the supported embedding implementation.
