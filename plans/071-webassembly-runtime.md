# WebAssembly application runtime

Status: proposed. Written 2026-08-19. Follows the AOT contract in plan 038,
the embedding boundary in plan 054, VM-aware AOT construction in plan 064, and
cross-target production in plan 043.

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

The dialect is not only syntax. Lua 5.4's integer subtype changes answers rather
than spellings, and the standard library the payload links is itself written
against LuaJIT's `ffi`, `bit`, `table.new` and `string.buffer`. The number model
is ported in the emitter and the library in the runtime. Neither moves on its
own because the source that names it compiles.

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
- generated Lua computes and prints the same numbers under the linked Lua 5.4
  runtime as under LuaJIT;
- every standard-library module either runs on the web runtime or reports at
  check time that the target has no provider for it;
- `aot = "off"` runs the same source body and changes performance and artifacts,
  not answers;
- the JavaScript host catches every Lua failure at a protected boundary and
  returns structured failure information without a long jump crossing
  JavaScript;
- the default runner cannot freeze the document's main thread when an
  application loops indefinitely;
- a target that names an unavailable browser facility fails during checking or
  packaging, rather than lazily reaching a missing global;
- rebuilding from identical inputs reproduces every byte outside the one named
  toolchain metadata section; and
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

Plan 043 remains authoritative for cross-target production. Its model is that
the payload is platform-neutral Lua stamped into a pinned prebuilt stub, so one
machine builds for every platform without holding that platform's toolchain. The
web target keeps that model wherever it still applies. `aot = "off"` and
`emit-c` builds stamp their payload into a prebuilt web stub -- stock Lua, the
runtime and the loader, compiled once by release CI -- and need no local
Emscripten at all. Only `aot = "require"` compiles generated C, and only that
policy requires the toolchain. The stub is a cataloged `platforms` entry named
by its triple, which extends the existing distribution path rather than adding a
second one beside it.

Plan 063 assumed a tracing JIT and this target has none. Root-view scalar
replacement removes view allocation on the native target because LuaJIT sinks
what the pass leaves behind; here the same removal has to be complete in the
compiler. Plan 058's advisor rests on the same assumption from the other side:
an unannotated hot body runs the interpreter rather than a trace, so a candidate
it would decline natively may be the one that decides a web build.

Plan 053 remains authoritative for user C interop. Arbitrary desktop shared
libraries do not become available in a browser merely because generated AOT C
does. A dependency must have an explicit wasm32 build and browser-safe host
contract or the web target rejects it.

The browser playground remains a separate product surface. Its Fengari state is
a private compiler state with shims sufficient for checking and generation. It
does not share application values with a produced web artifact and is not the
runtime against which struct or AOT behavior is validated. It does share the
portable emitter, which is a compiler-side dependency rather than a shared
runtime.

## Artifact and build target

Add an explicit `web` build kind rather than pretending the output is an
existing single-file binary or a Lua bundle:

```lua
build = {
    targets = {
        web = {
            kind = "web",
            layoutTarget = "wasm32-unknown-emscripten",
            entries = {"src/main.nupp"},
            output = "dist/app",
            aot = "require",
        },
    },
}
```

The triple is spelled in the existing `layoutTarget`, which already names the
target of compile-time C layout intrinsics, and a stub-stamped build names it in
`platforms` the way plan 043 does. The web kind adds no third spelling for the
same fact, and it does not overload the target name with the platform.

`aot = "require"` is this target's ordinary policy rather than an aggressive
one. Every other target treats AOT as opt-in polish over a JIT-ed baseline; here
an unannotated body runs an interpreter with nothing behind it, so the projects
that reach for the web target are the ones that should be requiring compilation
rather than permitting it.

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
- long-jump mode and any WebAssembly feature it requires;
- scalar or SIMD feature tier;
- generated C, compile and link flags; and
- every input digest already carried by modules, dependencies and resources.

Production support pins the toolchain by version and digest, just as the native
stub pins LuaJIT. An initial development implementation may discover an `emcc`
installation explicitly selected by the project, but its complete identity and
flags remain in the artifact key, and a discovered toolchain identifies the
machine that found it: those artifacts are machine-local, never published and
never entered into a shared cache. Only a pinned toolchain produces an artifact
another machine may reuse.

Rebuilds are byte-identical apart from the WebAssembly `producers` section,
which records the toolchain that wrote the module and is stripped before any
comparison. Nothing else is exempt. The build passes the flags that make Clang,
Emscripten and `wasm-ld` reproducible, and a difference anywhere else is a
defect rather than expected toolchain noise.

`aot = "emit-c"` writes deterministic C and registration metadata for a vendor
web build without invoking Emscripten. `aot = "require"` invokes the selected
toolchain and fails if the compiler, sysroot, source subset, runtime ABI or link
step is unavailable. `aot = "off"` includes no generated AOT C and emits every
annotated body as portable Lua.

There is no dynamic AOT loading mode. Browsers do not search for shared
libraries, and one link is what lets generated code, struct storage and the Lua
state share a memory and ABI.

### Error and suspension build mode

Two Emscripten choices decide the shape of the whole artifact, so the target
names both rather than accepting a default.

Lua's error handling compiles to `setjmp` and `longjmp`. The scalar baseline
selects emulated long jumps, which keeps WebAssembly exception handling out of
the required feature set at a size and speed cost that is measured rather than
assumed. An exception-handling build is a later tier with its own artifact
identity and its own feature check, not a silent upgrade under the same name.

The runtime does not use Asyncify or JSPI. A host operation suspends only where
Lua itself yields, and no provider suspends inside a C frame. That is a
constraint on provider design rather than an implementation detail: a provider
that cannot express its wait as a yield at the Nupp suspension boundary is not
admitted, because admitting one buys a whole-program transform that inflates
every function in the module to pay for the few that suspend.

## Portable generated Lua

Add a target dialect to the generator rather than rewriting emitted text after
generation. The portable emitter preserves the existing line-count invariant:
all target lowering for a source line stays on that line, so chunk names and
tracebacks continue to identify authored positions without source maps.

### Number model

Lua 5.4's integer subtype is the largest difference between the runtimes and the
one that is not a syntax question. LuaJIT gives every Nupp `number` one
representation. Lua 5.4 carries an integer through most arithmetic on integer
operands, and that result prints differently, divides differently, wraps where a
double would lose precision, and is accepted or refused where a float is not:
`tostring(1.0)` is `1.0` rather than `1`, `string.format` with `%d` raises on a
non-integral float, `//` and `%` differ on mixed operands, `math.type` starts
answering, and a numeric `for` variable changes subtype with its bounds.

The target keeps Nupp's number. Generated arithmetic produces Lua floats, and an
operation whose Lua 5.4 result is an integer is forced back before anything can
observe it. Printed representations, table-key identity, comparison and division
therefore read what they read today. A Lua 5.4 integer is an implementation
detail of the runtime, never a value a Nupp program can see.

The fixed-width refinements are the same question one level up. `int32`,
`uint32` and the other established widths are refinements over that number,
`nupp.math.i32` and `nupp.math.u32` are implemented against LuaJIT's `bit`
library, and the float helpers beside them round by punning bits through it.
They are reimplemented for the target rather than assumed to carry across, and
their answers are compared against the native ones at the boundaries the
refinements exist to police.

### Syntax lowering

For the Lua 5.4 runtime, generation must at least:

- translate customary logical operators to `not`, `and`, `or` and `~=`;
- lower conditional, nil-coalescing and safe-navigation expressions while
  evaluating receivers, keys and arguments exactly once;
- lower every compound assignment with the same single-evaluation rule;
- lower short functions and named varargs;
- lower `continue` to a generated `goto`, wrapping the remainder of the loop
  body in a block wherever a local declared after the jump would otherwise place
  the label inside that local's scope, which Lua 5.4 rejects;
- translate Nupp `const` bindings to Lua `local name <const>` where the binding
  shape permits it and to checked ordinary locals where it does not;
- use Lua 5.4 floor division directly;
- preserve Nupp's signed 32-bit bit-operation semantics through compiler-owned
  helpers, under the number model above, instead of assuming Lua's native
  integer width agrees;
- reject LuaJIT cdata literal suffixes outside reified/AOT lowering rather than
  silently changing values; and
- bind target runtime helpers by resolved compiler identity, not mutable globals.

Lua 5.4 `<close>` may implement a simple lexical cleanup only when the compiler
proves its behavior is identical to Nupp's cleanup graph. It is not a wholesale
replacement for affine lowering. Moves, conditional activation, field cleanup,
multiple cleanup identities, suspension rules and primary/suppressed error
composition remain compiler-owned. The ordinary protected-region lowering is
the initial correctness path; `<close>` is a later verified optimization.

### Dialect versions

The dialect is parameterized by the Lua version it targets, with one axis rather
than one dialect per consumer. Lua 5.3 and Lua 5.4 accept the same generated
text apart from the 5.4 attribute lowerings -- `local name <const>`, and
`<close>` once it is proved -- which the 5.3 form omits. That axis is what lets
the playground consume the same emitter instead of rewriting its output.

The generated dialect is tested under the exact Lua VM linked into the web
runtime. Success under the compiler's LuaJIT state or the playground's Fengari
state is not target validation.

## Standard library on the web target

Porting the emitter ports the code the compiler writes, not the code it links.
The shipped library reaches for LuaJIT directly, and none of those reaches
survives a stock PUC runtime:

- `nupp.data.valuebuilder` builds values through `ffi` and presizes with
  `table.new`, and it is plan 064's own support code, so it sits on the critical
  path rather than beside it;
- `nupp.data.bitset`, `nupp.mem.span`, `nupp.mem.heap` and `nupp.mem.soa` hold
  their storage as `ffi` allocations;
- `nupp.math.i32` and `nupp.math.u32` are written against the `bit` library,
  down to punning floats through their bits;
- `nupp.io`'s buffers, views, readers and writers hold their bytes as `ffi`
  allocations, and `nupp.json` falls back to `package.loadlib` of a native
  library when its host does not already provide one -- which this target's
  first required outcome forbids outright;
- `nupp.workers` frames its messages with `string.buffer` across OS threads; and
- `nupp.profile` and its trace and zone modules read `jit.profile`, `jit.util`
  and `jit.vmdef`, which describe a compiler this target does not contain.

Every standard-library module therefore carries an explicit web disposition, and
that profile is compiler data rather than something a program discovers when a
`require` fails. A module either:

- runs unchanged on the portable dialect;
- has a target implementation, in the runtime's C or in portable Lua, whose
  observable behavior is the same; or
- has no web provider, and says so at check time naming the source call.

The storage-holding modules take C implementations rather than portable Lua
ones. The artifact is statically linked and already registers generated C
against the application state, so a bitset word array or a span allocation costs
one more translation unit and keeps the representation it has today. Rewriting
them over Lua tables would commit inside the library exactly the substitution
this plan refuses in the language. `nupp.profile` reports no web provider, and
`nupp.workers` reports the same until independent worker states exist.

## Struct representation

Each reified struct type has a compiler descriptor containing its nominal
identity, size, alignment, ordered fields, field kinds, offsets, widths, nested
descriptors and method table. The generated C translation unit declares the
corresponding C type and exports layout reporters derived with `sizeof`,
`_Alignof` and `offsetof`.

An owning struct value is a Lua full userdata holding the exact struct bytes,
with the descriptor and metatable reached through a user value. Lua guarantees
the payload only its own maximum alignment, which is below the sixteen bytes the
SIMD tier wants, so the allocation carries the slack the descriptor requires and
the bytes begin at the first correctly aligned offset inside it rather than at
the payload's first byte. Construction zeroes those bytes before applying
positional or named initializers. Primitive reads and writes use generated or
descriptor-driven C accessors so conversion follows the field's C type:

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

Materialize a view only where one escapes. `owner.inner.field` names an offset
the compiler already holds in the descriptor, so the chain lowers to a single
accessor on the owning userdata at a folded offset and allocates nothing; a view
userdata is built when a nested value is bound, passed or returned. Without that
lowering every nested field read allocates, under a collector with no tracing
JIT behind it -- which is the allocation plan 063 removes on the native target
by relying on a pass this runtime does not have.

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
the public Lua 5.4 C API plus a header of macros wherever plan 064's
Lua 5.1-oriented subset differs. Macros rather than wrapper functions: the calls
plan 064 generates are a small fixed set, the mapping is mechanical, and a
header leaves link-time optimization nothing to see through.
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

Providers are designed for the worker first, because that is the default host. A
worker has no DOM: canvas integration there means `OffscreenCanvas` and a DOM
message means a port rather than a node. A provider that can exist only on the
main thread declares that, rather than discovering it when the default host
loads it.

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

The playground is also the portable emitter's first consumer, and adopting it
deletes machinery rather than adding it. Today the playground reaches Lua 5.3 by
rewriting generated text. Its `tools/patch-bootstrap-for-browser.lua` edits
`const`, `ULL` literals and expression syntax out of the compiler at build time,
and its host runtime applies the same rewrites again at load time to any chunk
the VM refused. That is the post-generation rewriting this plan replaces.
When the dialect lands, the playground selects its 5.3 form and both rewriting
layers go. One dialect is tested, and the playground runs the tested one.

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
  module and payload transfer size and AOT entries;
- a struct-layout inspection prints modeled and compiled wasm32 measurements;
- `nupp bc` reports that this target records no traces, rather than reading
  LuaJIT bytecode; `--check`, whose whole subject is trace abort and
  blacklisting, has nothing to answer here and says so; and
- the AOT advisor scores web candidates against an interpreted baseline, so it
  recommends bodies it would leave alone natively.

That last pair is the target's answer to "why is this build slow". Every other
target answers it with trace behavior, and this one has none, so the advisor and
the artifact's own size and entry report carry the question instead.

## Verification

Verification is differential and layered.

### Portable Lua

- Parse every generated module with the exact linked Lua version.
- Compare portable and LuaJIT output for expression evaluation order, false
  versus nil coalescing, multiple returns, varargs and error positions.
- Exercise `continue`, `break`, `goto`, return and errors across nested affine
  cleanup regions, including loop bodies that declare a local after a
  `continue`.
- Assert generated line counts and traceback source lines remain unchanged.
- Compare every arithmetic operator, `//`, `%`, comparison, `tostring`,
  `string.format` and table-key identity against the LuaJIT baseline over
  integer boundaries, non-integral values, negative zero, infinities and NaN.
- Assert no generated expression makes a Lua 5.4 integer observable, and hold
  the fixed-width refinements and `nupp.math.i32`/`u32` to their native answers
  at every boundary they establish.

### Standard library

- Load every module the target admits under the linked runtime and run that
  module's own suite against it.
- Compare each target implementation with its native counterpart rather than
  with its own specification: bitsets, spans, heap allocations and the value
  builder answer identically or the disposition is wrong.
- Prove a module with no web provider reports at check time, names the source
  call, and never reaches a failing `require`.

### Layout and structs

- Generate one fixture for every primitive width and alignment.
- Cover tail padding, nested structs, fixed arrays, pointer fields, zero-sized
  logical counts and the largest supported alignment.
- Compare compiler layout models with C reporters in scalar and optimized builds.
- Verify binary32 truncation, signed wrapping, unsigned wrapping, zero
  initialization, field views and parent rooting.
- Keep a nested view alive through collection and prove its owner remains rooted;
  release every owner and prove no allocation remains registered.
- Prove a nested field read through its owner allocates nothing, and that
  binding, passing or returning a nested value does materialize a view.

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
- Rebuild from identical inputs and compare every byte outside the `producers`
  section, which is stripped before comparison. A difference elsewhere is a
  defect, not accepted toolchain noise.
- Record compressed transfer size for the loader, the module and the payload on
  every build, and treat an unexplained move the way a timing regression is
  treated. The size decides whether the target is usable, so it is measured from
  the first artifact rather than at the end.
- Build with no local Emscripten installed and prove `aot = "off"` still
  produces a working artifact from the prebuilt stub.

### Performance

Measure startup download size, compilation time, state initialization, first
entry and steady-state calls separately. Compare:

- portable Lua under the Wasm VM;
- scalar AOT;
- `wasm-simd128` AOT where admitted;
- emulated long jumps against a WebAssembly exception-handling build, in module
  size and in call cost, before either is promoted; and
- the existing native LuaJIT/AOT result as a reference, not an equality target.

The first performance gate is architectural: one transition per AOT call, no
span copy, no per-element JavaScript bridge and no Lua-value materialization in
JavaScript. Absolute browser throughput is recorded only after those conditions
hold.

## Implementation sequence

1. Add the portable generator dialect, including the number model, and run
   generated modules under a native PUC Lua 5.4 test interpreter before
   WebAssembly is involved.
2. Give every standard-library module a web disposition and implement the ones
   that need it: the fixed-width helpers, bitsets, spans, heap and the value
   builder stop reaching for `ffi`, `bit`, `table.new` and `string.buffer`, and
   the modules with no provider start saying so at check time.
3. Add the wasm32 layout model, target vocabulary and scalar AOT selection;
   compare every modeled layout with Clang's emitted reporters.
4. Build the minimal PUC Lua runtime with Emscripten, fixing the long-jump mode,
   and load an embedded generated module through a protected JavaScript entry.
5. Add the `web` target, deterministic `.js`/`.wasm` outputs, artifact metadata,
   recorded transfer size and a worker-based console runner. Publish the
   prebuilt web stub so an `aot = "off"` build needs no local toolchain.
6. Implement owning primitive structs, generated descriptors, field access,
   construction and layout intrinsics.
7. Add nested struct and fixed-array views with parent rooting and the
   escape-only materialization lowering, then pointer fields under the existing
   unsafe rules.
8. Add GC-owned contiguous allocations and the web span provider.
9. Register pure scalar AOT kernels as Lua C closures and pass struct spans
   through one checked call.
10. Port plan 064's VM-aware registrar to the wasm runtime ABI and run its
    forced collection fixtures.
11. Add suspension-backed browser scheduling and the first explicit asynchronous
    provider.
12. Add `wasm-simd128`, feature selection and differential lane tests.
13. Pin the production toolchain, complete browser automation, document the web
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
- Do not use Asyncify or JSPI to let a host operation suspend inside a C frame.
- Do not reach the target runtime by rewriting generated text after generation.
- Do not add `wasm32-wasi` or a standalone non-browser host under this target.
  The application boundary here is the browser and its event loop; a server-side
  WebAssembly host is a separate target with its own providers, and nothing in
  this plan is written to prevent one later.
- Do not call the worker boundary a security sandbox for hostile native code.

## Open questions to settle by spikes

The following choices need measured prototypes, but none changes the one-VM
decision:

1. Whether the payload and resources belong in Wasm data segments or a separate
   content-addressed data file for browser caching.
2. Whether generic descriptor-driven struct access is fast enough outside AOT
   or generated per-field C closures are warranted, once the escape-only
   lowering has removed the allocation from the same measurement.
3. Whether contiguous allocations should use Lua userdata storage, the runtime
   allocator, or separate arenas while preserving deterministic ownership.
4. Whether the initial loader uses Emscripten's generated module shell or a
   smaller compiler-owned instantiation layer after link.
5. Which provider and component calls may safely run on the main thread and
   which require the default worker host.
6. What scalar-to-SIMD artifact selection strategy gives reliable browser
   caching without duplicating the whole payload.
7. What emulated long jumps cost against WebAssembly exception handling, and
   whether the second tier earns a separate artifact identity.

Answer these with executable fixtures and record the selected results in the
implementation status or a narrower follow-up plan. Do not postpone the target
behind questions whose conservative scalar, copied-host-boundary answer is
already correct.
