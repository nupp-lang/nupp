# WebAssembly application runtime

Status: proposed. Written 2026-08-19. Follows the AOT contract in plan 038,
the embedding boundary in plan 054, and VM-aware AOT construction in plan 064.

## Decision

Make `wasm32-unknown-emscripten` Nupp's browser application target. A web
artifact contains a stock Lua VM, the generated Nupp runtime, reified struct
support, and every required AOT translation unit in one statically linked
WebAssembly module. A small JavaScript loader instantiates it and supplies the
browser facilities selected by the application.

Do not make a JavaScript Lua implementation the production application runtime.
Fengari remains useful for the compiler playground, where checking and portable
Lua generation need no C layout or native code. An application with structs and
AOT needs Lua values, struct bytes, spans, and generated C to share one collector
boundary and one linear memory. Putting application Lua in JavaScript and AOT C
in WebAssembly would create two heaps and turn every struct field, span, rooted
string, and constructed Lua value into a bridge protocol.

Use an unmodified upstream PUC Lua runtime rather than attempting to compile
LuaJIT to WebAssembly. The first runtime is Lua 5.4, compiled by a pinned
Emscripten/Clang toolchain. Generated application Lua uses a compiler-owned
portable dialect that the runtime accepts; it does not contain the LuaJIT syntax
extensions the current emitter passes through.

The web target preserves Nupp's existing meanings:

- a `record` is a Lua table with nominal identity;
- a `struct` is zero-initialized storage with a target C layout, exact field
  widths, inline arrays and nested by-value structs;
- an `@aot` body is either compiled completely under the selected build policy
  or emitted completely as its ordinary Lua fallback;
- spans passed to AOT name contiguous storage for the full proved interval;
- Lua-building AOT code constructs ordinary values owned by the same VM that
  called it; and
- affine cleanup, borrowing, pins, effects, and source-level failure semantics
  do not weaken because the target is a browser.

This is a native Nupp platform whose instruction set and operating environment
are WebAssembly and the Web, not a reduced "browser Nupp" language.

## Required outcome

The first supported web target is complete only when all of these hold:

- `nupp build --target web` deterministically produces a loadable JavaScript
  loader and WebAssembly module from an ordinary Nupp project;
- the module contains one Lua application state, the generated payload, selected
  runtime providers, struct support, and required AOT entries;
- no generated application path requires LuaJIT, FFI, `package.loadlib`, a
  sidecar shared library, or executable-memory mapping;
- a reified struct reports the layout selected for the wasm32 C ABI and the C
  compiler's reporters agree with every size, alignment, field offset and field
  width before application entry runs;
- primitive, nested-struct and fixed-array fields preserve their current
  construction, mutation, aliasing and numeric-conversion behavior;
- a contiguous span of structs crosses one checked Lua-to-C boundary and is
  consumed by an ordinary scalar AOT kernel without copying;
- VM-aware AOT construction allocates and returns ordinary tables and strings in
  the application Lua state through the verified construction IR;
- `aot = "off"` runs the same source body and changes performance and artifacts,
  not answers;
- the JavaScript host catches every Lua failure at a protected boundary and
  returns structured failure information without a long jump crossing
  JavaScript;
- the default runner cannot freeze the document's main thread when an
  application loops indefinitely;
- a target that names an unavailable browser facility fails during checking or
  packaging, rather than lazily reaching a missing global; and
- scalar output is the correctness baseline before WebAssembly SIMD is enabled.

The first release does not require compiling Nupp or C inside the browser. Web
artifacts are cross-compiled by the normal Nupp CLI and then served as static
files. The existing browser compiler may check and emit the ordinary fallback,
but it is not an in-tab native toolchain.

## Why wasm32 is the application boundary

Nupp structs are not typed tables. Today a declaration becomes an FFI ctype and
`ffi.metatype`, so a `float` assignment truncates to binary32, a fixed array sits
inside its owner, a nested struct has a real offset, and a pointer is an address.
Replacing that representation with a table would preserve field names while
discarding the behavior for which the feature exists.

The same boundary appears in AOT. A pure kernel consumes native scalars and
pointers. A VM-aware builder receives `lua_State *`, roots intermediate values
on the VM stack, invokes write barriers through the public API, and returns
ordinary Lua values. With Fengari, the kernel's memory would be WebAssembly
memory while the values a builder must root would be JavaScript objects. A
general bridge would have to duplicate the Lua C API, collector rooting, table
identity, strings, errors and callbacks across runtimes. That is a second VM
implementation, not an AOT backend.

Static linking puts the existing boundaries back where their proofs expect:

```text
JavaScript host
    |
    | protected calls, copied scalars/bytes, opaque handles, wakeups
    v
+------------------------------------------------------------------+
| one WebAssembly module                                           |
|                                                                  |
|  PUC Lua state <-> Nupp runtime <-> struct userdata              |
|       ^                    ^              ^                       |
|       | registered C      | pointers     | shared linear memory  |
|       +----------- generated AOT C ------+                       |
+------------------------------------------------------------------+
```

Only the outer host boundary needs a JavaScript protocol. Inside the module,
the ordinary Lua C API, native pointers and compiler-verified AOT conventions
remain direct calls.

## Relationship to existing plans

Plan 038 remains authoritative for `@aot`, its admitted source model, verified
IR, ordinary fallback, numeric contract and all-or-error build policies. This
plan adds a target backend, a static loading mode, and a wasm32 feature tier. It
does not add another annotation or reinterpret an AOT body.

Plan 064 remains authoritative for VM-aware construction. Its public-API and
rooting rules are preserved. Matching C function names are not treated as proof
of cross-runtime compatibility: wasm artifacts name a new runtime ABI profile,
and the emitter or a compiler-owned compatibility layer maps that profile onto
the selected Lua 5.4 API.

Plan 054 remains authoritative for application-state ownership, protected
errors, rooted handles, feature freeze and host policy. The JavaScript loader is
a WebAssembly implementation of that host boundary. Web callbacks do not expose
raw Lua stack indexes, collector pointers or struct addresses to application
JavaScript.

Plan 053 remains authoritative for user C interop. Arbitrary desktop shared
libraries do not become available in a browser merely because generated AOT C
does. A dependency must have an explicit wasm32 build and browser-safe host
contract or the web target rejects it.

The browser playground remains a separate product surface. Its Fengari state is
a private compiler state with shims sufficient for checking and generation. It
does not share application values with a produced web artifact and is not the
runtime against which struct or AOT behavior is validated.

## Artifact and build target

Add an explicit `web` build kind rather than pretending the output is an
existing single-file binary or a Lua bundle:

```lua
build = {
    targets = {
        web = {
            kind = "web",
            platform = "wasm32-unknown-emscripten",
            entries = {"src/main.nupp"},
            output = "dist/app",
            aot = "require",
        },
    },
}
```

The output stem produces at least:

```text
dist/
  app.js
  app.wasm
```

`app.js` is a small versioned loader, not generated application logic. It
accepts host providers, instantiates `app.wasm`, installs imports, starts the
entry component and converts returned failures to JavaScript values. The Lua
payload, declarations, selected standard-library modules, resources, struct
descriptors and native registration table are deterministic module data. They
may be linked into the Wasm data segments or carried as a separately hashed data
file if measurement shows a material startup or cache benefit; the public
artifact identity covers either representation.

The build records:

- Nupp compiler and runtime ABI versions;
- Lua source and C API profile;
- Emscripten and Clang versions;
- wasm32 layout-model version;
- AOT IR, construction IR and registration ABI versions;
- selected browser feature providers;
- scalar or SIMD feature tier;
- generated C, compile and link flags; and
- every input digest already carried by modules, dependencies and resources.

Production support pins the toolchain by version and digest, just as the native
stub pins LuaJIT. An initial development implementation may discover an `emcc`
installation explicitly selected by the project, but its complete identity and
flags remain in the artifact key.

`aot = "emit-c"` writes deterministic C and registration metadata for a vendor
web build without invoking Emscripten. `aot = "require"` invokes the selected
toolchain and fails if the compiler, sysroot, source subset, runtime ABI or link
step is unavailable. `aot = "off"` includes no generated AOT C and emits every
annotated body as portable Lua.

There is no dynamic AOT loading mode. Browsers do not search for shared
libraries, and one link is what lets generated code, struct storage and the Lua
state share a memory and ABI.

## Portable generated Lua

Add a target dialect to the generator rather than rewriting emitted text after
generation. The portable emitter preserves the existing line-count invariant:
all target lowering for a source line stays on that line, so chunk names and
tracebacks continue to identify authored positions without source maps.

For the Lua 5.4 runtime, generation must at least:

- translate customary logical operators to `not`, `and`, `or` and `~=`;
- lower conditional, nil-coalescing and safe-navigation expressions while
  evaluating receivers, keys and arguments exactly once;
- lower every compound assignment with the same single-evaluation rule;
- lower short functions and named varargs;
- lower `continue` to a generated `goto` whose label cannot be entered across a
  local declaration;
- translate Nupp `const` bindings to Lua `local name <const>` where the binding
  shape permits it and to checked ordinary locals where it does not;
- use Lua 5.4 floor division directly;
- preserve Nupp's signed 32-bit bit-operation semantics through compiler-owned
  helpers instead of assuming Lua's native integer width agrees;
- reject LuaJIT cdata literal suffixes outside reified/AOT lowering rather than
  silently changing values; and
- bind target runtime helpers by resolved compiler identity, not mutable globals.

Lua 5.4 `<close>` may implement a simple lexical cleanup only when the compiler
proves its behavior is identical to Nupp's cleanup graph. It is not a wholesale
replacement for affine lowering. Moves, conditional activation, field cleanup,
multiple cleanup identities, suspension rules and primary/suppressed error
composition remain compiler-owned. The ordinary protected-region lowering is
the initial correctness path; `<close>` is a later verified optimization.

The generated dialect is tested under the exact Lua VM linked into the web
runtime. Success under the compiler's LuaJIT state or the playground's Fengari
state is not target validation.

## Struct representation

Each reified struct type has a compiler descriptor containing its nominal
identity, size, alignment, ordered fields, field kinds, offsets, widths, nested
descriptors and method table. The generated C translation unit declares the
corresponding C type and exports layout reporters derived with `sizeof`,
`_Alignof` and `offsetof`.

An owning struct value is a Lua full userdata whose payload contains the exact
struct bytes and whose uservalue or runtime header retains the descriptor and
metatable. Construction zeroes the payload before applying positional or named
initializers. Primitive reads and writes use generated or descriptor-driven C
accessors so conversion follows the field's C type:

- `float` stores through `float` and therefore truncates to binary32;
- signed and unsigned integer fields use their declared widths;
- `boolean` uses the selected C ABI representation;
- `number` stores a C `double`;
- a nested struct occupies its declared inline bytes; and
- a fixed array occupies `count * element.size` inline bytes.

A nested struct or fixed-array read returns a view userdata, not a copied table.
The view stores an offset and roots its owning userdata, so it cannot outlive or
move independently of the bytes it names. Mutation reaches the parent's bytes.
Views participate in Nupp's existing borrow and exclusivity checks at the source
level; the runtime representation is not treated as permission to manufacture
aliases in unchecked code.

Pointer fields use wasm32 addresses inside the module's linear memory. They do
not become JavaScript numbers or public offsets. Existing unsafe and pinning
rules govern their construction and lifetime. Host JavaScript receives copied
bytes, an approved typed view bounded by an explicit call lifetime, or an opaque
runtime handle; it never receives a persistent raw pointer by default.

Metamethod dispatch preserves existing inline methods and operators. The first
implementation may use a shared C accessor keyed by descriptor and field name.
Hot field-at-a-time loops are not a reason to expose memory unsafely: they are
the workload AOT and span lowering are intended to move across one boundary.
Measurement may later specialize accessors per struct or field without changing
the representation.

`layoutof`, `sizeof`, `alignof` and `offsetof` read compiler descriptors and are
checked against the linked C reporters before application entry. The wasm32
layout model is added to `nupp.compiler.targetlayout`, but a handwritten model
never overrules the compiler that laid out the linked object. A disagreement is
a deterministic build or load failure.

## Contiguous storage and spans

A single struct userdata provides stable storage while rooted. Arrays and spans
need one allocation containing all elements contiguously. The web runtime adds a
GC-owned native allocation object whose bytes live in Wasm memory and whose Lua
owner releases or transfers them through the existing affine policy.

Span values retain the allocation owner, byte offset, element descriptor,
logical count, mutability and borrow state. A checked AOT wrapper projects the
span to pointer and count once. The pointer remains valid because the owner is
rooted for the complete call and the WebAssembly memory allocation is not moved.
JavaScript memory growth may replace a host `TypedArray` view, but it does not
change addresses observed by C inside the module; host adapters reacquire views
after any operation that may grow memory.

The initial allocator may use the runtime C allocator. Its ownership is still
represented in Nupp rather than delegated to finalization: deterministic drop
is the language guarantee, and GC collection is only a backstop for a runtime
being torn down.

String and table storage remain Lua-managed and do not masquerade as spans of C
objects. Existing byte views may borrow string bytes only through the proved
intervals and rooting rules already owned by the span and AOT plans.

## AOT registration and calls

Keep the existing private kernel ABI inside generated C. Pure AOT helpers call
one another directly, and scalar or lane-lowered bodies continue to use native
scalars, pointers and counts. Change only the Lua-facing binding.

Every linked AOT translation unit exports one digest-named registrar. During
runtime initialization, a compiler-generated static registration table invokes
those registrars against the application `lua_State`. Each registrar installs
Lua C closures under compiler identities. The generated Lua wrapper caches the
closure and retains source-level range, relationship, ownership and error
framing.

For a pure kernel, the registered closure:

1. reads and validates scalar arguments;
2. resolves struct or span userdata and roots every owner;
3. projects pointers and counts;
4. invokes the existing private kernel ABI once;
5. converts results to Lua values; and
6. returns or raises through the VM-owned C frame.

For a Lua-building entry, plan 064's verified construction program runs directly
against the same `lua_State`. No JavaScript callback allocates a table or string,
and no Lua object is held solely in an unrooted C pointer.

The generated C targets a versioned `nupp-wasm-lua` API profile. That profile is
implemented either by the selected public Lua 5.4 C API or by thin
compiler-owned adapters where plan 064's Lua 5.1-oriented subset differs.
Generated code does not infer compatibility from a symbol with the same name.
The profile, Lua build and registration ABI are part of every artifact digest.

Failures do not unwind through JavaScript. AOT calls run on VM-owned C frames;
the outer JavaScript entry invokes Lua through a protected runtime operation and
turns the final error object, traceback and source metadata into an owned host
result.

## Scalar and SIMD tiers

The first wasm32 AOT tier is scalar. This establishes numeric equivalence,
layout, registration, failure and memory behavior without making browser SIMD a
prerequisite for correctness.

Add a `wasm-simd128` tier only after scalar differential tests pass. The target
admits 16-byte gangs and emits or maps lane operations to WebAssembly SIMD. It
must not reuse the x86 SSE or ARM NEON target merely because their register width
matches. Instruction selection, shuffle availability, NaN behavior, feature
detection and ABI rules are independently verified.

The loader selects a SIMD artifact or a scalar artifact before the application
state starts. It does not branch per hot call. A project that explicitly
requires lanes fails when the selected browser/runtime cannot instantiate the
SIMD artifact; an ordinary `@aot` body retains its scalar lowering.

Threads, shared WebAssembly memory and atomics are not part of the first target.
They require cross-origin isolation in browsers and change allocator, worker,
suspension and host-lifetime rules. Independent Nupp worker states may be added
later as separate modules and memories before a shared-state design is
considered.

## Browser host boundary

The generated loader exposes a versioned creation operation conceptually like:

```js
const app = await Nupp.instantiate({
  module: wasmUrl,
  console,
  clock,
  schedule,
  fetch,
  storage,
});
await app.start();
```

The exact JavaScript surface follows plan 054's lifecycle rather than exposing
Emscripten implementation details. Providers are declared and frozen before
the first component runs. Missing required providers reject instantiation with
the feature and importing module named.

The initial browser providers are deliberately narrow:

- structured logging and captured standard output;
- monotonic time;
- scheduling a wakeup onto the browser event loop;
- copied resource reads from the artifact; and
- host cancellation and shutdown.

Fetch, persistent storage, canvas/audio integration and DOM messages land as
separate declared modules with explicit effects. They are not ambient globals.
The filesystem, subprocesses, dynamic libraries and native OS workers report
that the web target has no provider. A virtual or persistent browser filesystem
may be added later under a distinct module; it does not imitate POSIX by
accident.

Promise-producing host operations integrate through Nupp's suspension boundary:
Lua yields a runtime-owned continuation, JavaScript settles the operation, and
the scheduler resumes the owning state on its single runtime thread. JavaScript
never resumes an arbitrary coroutine or calls into a busy state reentrantly.

Run untrusted or potentially nonterminating applications in a dedicated Web
Worker by default. Terminating the worker is the hard cancellation boundary.
The main-thread mode is opt-in for hosts that need synchronous DOM integration
and trust the application not to monopolize the event loop. Debug hooks may add
an interpreted instruction budget, but they cannot preempt a long-running AOT
call and are not presented as a complete sandbox.

## Compiler and playground separation

Native `nupp build` owns web artifact production. It checks source, selects the
portable emitter, generates struct and AOT C, invokes Emscripten, links the
runtime, validates the result and writes the loader. Cross-compilation never
executes the target module to discover its ABI or CPU features.

The browser playground continues to run the self-hosted compiler under Fengari.
It may:

- check web-target source against the target capability profile;
- show the generated target Lua while leaving target parsing to the exact linked
  Lua test runtime; and
- load prebuilt Wasm examples produced by the native build.

It may not claim that its FFI stubs validate struct layout or that compiling a C
translation unit happened in-browser. A future hosted build service is an
external product decision, not part of the language target.

## Diagnostics and inspection

Target diagnostics identify the capability and the selected artifact, not a
late missing function:

- a C dependency with no wasm32 build names the dependency and required target;
- a native standard-library effect with no web provider names the source call
  and provider;
- a struct field with no WebAssembly representation uses the existing reifiable
  type diagnostic with the wasm32 layout target attached;
- an AOT body rejected by the wasm backend reports the source construct and
  keeps the ordinary body available only when the whole build selected
  `aot = "off"`;
- a layout disagreement reports the struct, field, modeled value and compiled
  value;
- a missing JavaScript import names the Nupp feature rather than the minified
  Emscripten symbol; and
- an unsupported dynamic-library or process operation reports that the web
  target has no such host facility.

Inspection commands add the selected runtime and artifact information:

- `nupp aot` reports `wasm32`, scalar or `wasm-simd128`, entry mode and runtime
  ABI profile;
- `--emit c` remains deterministic vendor-build input;
- `--emit binding` shows the registered-closure wrapper rather than an FFI
  declaration;
- build JSON lists `.js` and `.wasm` outputs, features, toolchain identity,
  module size and AOT entries; and
- a struct-layout inspection prints modeled and compiled wasm32 measurements.

## Verification

Verification is differential and layered.

### Portable Lua

- Parse every generated module with the exact linked Lua version.
- Compare portable and LuaJIT output for expression evaluation order, false
  versus nil coalescing, multiple returns, varargs and error positions.
- Exercise `continue`, `break`, `goto`, return and errors across nested affine
  cleanup regions.
- Assert generated line counts and traceback source lines remain unchanged.

### Layout and structs

- Generate one fixture for every primitive width and alignment.
- Cover tail padding, nested structs, fixed arrays, pointer fields, zero-sized
  logical counts and the largest supported alignment.
- Compare compiler layout models with C reporters in scalar and optimized builds.
- Verify binary32 truncation, signed wrapping, unsigned wrapping, zero
  initialization, field views and parent rooting.
- Keep a nested view alive through collection and prove its owner remains rooted;
  release every owner and prove no allocation remains registered.

### AOT

- Run every admitted scalar operation against the ordinary Lua body over edge
  values, NaNs, infinities, signed zero and integer boundaries.
- Pass spans of primitive and struct elements without copying and verify writes
  at the first and last legal element.
- Reject mismatched counts and out-of-range intervals before native access.
- Exercise direct AOT helper graphs, multiple results and modeled failures.
- Run plan 064's rooted table/string builders under forced collection at every
  allocating operation.
- Build `aot = "off"`, `emit-c` and `require` from the same source and compare
  ordinary answers.

### Host and artifact

- Instantiate in current Chromium, Firefox and WebKit automation from an HTTP
  origin, never only in Node.
- Start, call, fail, cancel and shut down through the public loader.
- Verify a missing provider, malformed artifact, ABI mismatch and rejected
  Promise all leave no live application handle.
- Terminate an infinite interpreted loop in a worker without freezing the test
  page.
- Move the output directory and serve it from a different path to prove loader
  URLs are relocatable.
- Rebuild from identical inputs and compare all deterministic bytes after
  separating any toolchain metadata that cannot be made reproducible.

### Performance

Measure startup download size, compilation time, state initialization, first
entry and steady-state calls separately. Compare:

- portable Lua under the Wasm VM;
- scalar AOT;
- `wasm-simd128` AOT where admitted; and
- the existing native LuaJIT/AOT result as a reference, not an equality target.

The first performance gate is architectural: one transition per AOT call, no
span copy, no per-element JavaScript bridge and no Lua-value materialization in
JavaScript. Absolute browser throughput is recorded only after those conditions
hold.

## Implementation sequence

1. Add the portable generator dialect and run generated modules under a native
   PUC Lua 5.4 test interpreter before WebAssembly is involved.
2. Add the wasm32 layout model, target vocabulary and scalar AOT selection;
   compare every modeled layout with Clang's emitted reporters.
3. Build the minimal PUC Lua runtime with Emscripten and load an embedded
   generated module through a protected JavaScript entry.
4. Add the `web` target, deterministic `.js`/`.wasm` outputs, artifact metadata
   and a worker-based console runner.
5. Implement owning primitive structs, generated descriptors, field access,
   construction and layout intrinsics.
6. Add nested struct and fixed-array views with parent rooting, then pointer
   fields under the existing unsafe rules.
7. Add GC-owned contiguous allocations and the web span provider.
8. Register pure scalar AOT kernels as Lua C closures and pass struct spans
   through one checked call.
9. Port plan 064's VM-aware registrar to the wasm runtime ABI and run its forced
   collection fixtures.
10. Add suspension-backed browser scheduling and the first explicit asynchronous
    provider.
11. Add `wasm-simd128`, feature selection and differential lane tests.
12. Pin the production toolchain, complete browser automation, document the web
    host API and change this plan's status with the implementation.

Each step leaves the previous one usable. No step silently represents a struct
as a table or marks an uncompiled `@aot` body as compiled.

## Non-goals

- Do not compile LuaJIT, its assembler or its private object model to Wasm.
- Do not implement FFI over JavaScript objects or expose arbitrary JavaScript as
  C symbols.
- Do not turn structs into records on this target.
- Do not run web-target application Lua in Fengari; it is a compiler-playground
  implementation detail, not an alternate application VM.
- Do not dynamically link AOT side modules in the first target.
- Do not make a standalone Lua 5.1, Lua 5.3 or Fengari application target a
  prerequisite for the WebAssembly runtime.
- Do not ship an in-browser C compiler or require source compilation at page
  load.
- Do not emulate a POSIX filesystem, process environment or native dynamic
  loader as an implicit compatibility layer.
- Do not require WebAssembly threads, shared memory, exceptions, garbage
  collection proposals or SIMD for the scalar baseline.
- Do not expose a stable public ABI for generated structs or private AOT
  symbols; the stable surface is the versioned host/runtime API.
- Do not make arbitrary C dependencies browser-compatible without an explicit
  wasm32 build and capability review.
- Do not call the worker boundary a security sandbox for hostile native code.

## Open questions to settle by spikes

The following choices need measured prototypes, but none changes the one-VM
decision:

1. Whether the payload and resources belong in Wasm data segments or a separate
   content-addressed data file for browser caching.
2. Whether generic descriptor-driven struct access is fast enough outside AOT
   or generated per-field C closures are warranted.
3. Whether owning struct bytes should begin directly at the full-userdata
   payload or behind a runtime header with an aligned offset.
4. Whether contiguous allocations should use Lua userdata storage, the runtime
   allocator, or separate arenas while preserving deterministic ownership.
5. Which thin compatibility surface best isolates plan 064's generated Lua C
   API calls from Lua-version changes without obstructing LTO.
6. Whether the initial loader uses Emscripten's generated module shell or a
   smaller compiler-owned instantiation layer after link.
7. Which provider and component calls may safely run on the main thread and
   which require the default worker host.
8. What scalar-to-SIMD artifact selection strategy gives reliable browser
   caching without duplicating the whole payload.

Answer these with executable fixtures and record the selected results in the
implementation status or a narrower follow-up plan. Do not postpone the target
behind questions whose conservative scalar, copied-host-boundary answer is
already correct.
