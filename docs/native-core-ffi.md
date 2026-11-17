# Standalone core foreign calls

The standalone core's guest C calls use the upstream libffi C API directly:
`ffi_prep_cif`, `ffi_prep_cif_var`, `ffi_call`, `ffi_closure_alloc`,
`ffi_prep_closure_loc` and `ffi_closure_free`. No Rust binding or C semantic
wrapper sits on this path. Existing checked, static kernel calls remain direct
C calls, including the calls that enter libffi itself.

`scripts/native-libraries libffi` provisions libffi 3.8.0 from the source digest
in `scripts/toolchain.pins`, with matching headers and its own upstream notice.
It uses the existing target/compiler/configuration cache and integrity checks.
The matching-header layout/call/closure probe must pass before cache publication.
No Cargo, rustc, rustup or cargo-c is required to build or consume that artifact.
There is no system-library fallback. The artifact-relative import
`@/lib/libnuppffi` is a verified alias for the upstream library. A core bundle
carries those library bytes at `lib/libnuppffi` with the upstream notice.
The guest runner uses the existing checked sidecar copier before starting jobs.
It does not reprovision the other native dependencies.

Nupp still checks foreign declarations, argument counts, ownership modes,
scalar conversions and storage sizes. Its descriptors include the full nested
C struct member types, rather than target ABI classes or byte counts. libffi
computes natural struct layout and argument/result placement. Unions,
bitfields, empty structs and alignment above eight bytes are refused by this
core path. Variadic arguments use C default promotions and a separate CIF.
Arguments, temporary NUL-ended strings, signature storage and the result stay
rooted through the call. No collection, suspension or Nupp exception crosses
the C call. Existing module/symbol resolution and library lifetime policy stay
with the loader.

## Collector callbacks

The currently supported callback is `hostcalls.collector(words)`: a raw C
visitor taking two integer/pointer structs of the stated word count and a
record pointer. The compiler's libclang caller supplies four words; the L3
fixture supplies three. This internal API requires the signature explicitly.
It does not infer a signature from an untyped function address.

Libffi supplies the callable closure and its ABI. Nupp supplies one fixed
libffi handler, immutable signature storage, registration ownership and the
copy contract. Registrations contain no managed pointers. Repeated requests
with the same word count and OS thread reuse a registration. The entry owns
its CIF, type tree, userdata and executable closure until service teardown,
then frees the closure before freeing its storage. The code pointer is invalid
after entry teardown. C must finish its calls before returning and must not
retain it or call it during/after teardown.

The handler checks the creating OS thread before touching caller data. It
checks the record's word count against the immutable signature, copies only
into the record's declared capacity, and cannot allocate, park or unwind.
Refusal returns zero to C and records a fault for the owning Nupp call boundary
to raise after C returns. Calls on the allowed thread have no shared managed
entry state; callers still own synchronization and buffer/allocator validity.
This does not enable arbitrary managed callbacks or retained callback handles;
their existing core refusals remain in place.

## Evidence and remaining boundaries

`sh scripts/test-libffi` checks the pinned header/runtime pair, native storage
layout, a foreign call and a closure's preparation/call/free. Its CI matrix
targets macOS ARM64/x64 and Linux GNU ARM64/x64. These C probes do not establish
Nupp execution on those targets. Windows provisioning is explicitly refused
until it has its own upstream MSVC recipe and evidence.

`tests/core/guests/run.lua guestffi ffiaggregates` exercises the actual core
scalar, string, variadic, nested-struct, aggregate spill/return and callback
paths. Callback cases include both active signatures, repeated registration,
capacity stop, wrong-thread/shape refusal, recovery and entry teardown. Normal,
spill and collection-stress runs are distinct from the upstream C probe.

The frozen VM/compiler bootstrap still consumes the Rust `libffi` and
`libffi-sys` bindings. This change does not extend that VM or claim the default
compiler has become Rust-free. Its final removal belongs to the runtime
switch; the standalone core path and its upstream C artifact are separate.
