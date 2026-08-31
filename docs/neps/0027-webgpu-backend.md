---
title: WebGPU backend for browser builds
status: Draft
created: 2026-08-30
---

## Summary

One `@aot(target = "gpu")` function runs in a browser by making WGSL a third
consumer of the verified scalar IR and `nupp.gpu` a runtime seam with a device
provider per host. SPIR-V remains the canonical artifact for the native
backend; WGSL is emitted beside it from the same IR rather than translated from
it, because the compiler that has to produce it runs inside a browser and has
no process to spawn.

The WebGPU provider runs in the Worker that already owns the application's Wasm
memory. A new bounded transfer lease lets an effect name a validated heap range
instead of carrying its bytes through JSON; JavaScript resolves the lease to a
current Wasm-memory view before it calls WebGPU. WebGPU still copies the range
into device memory, but the host does not base64-encode, JSON-copy, or
structured-clone it first. Device acquisition, submission, and readback park on
the existing browser suspension protocol.

The first browser profile is deliberately integer-only: `int32` and `uint32`
storage and scalar uniforms. Conformance runs one kernel three ways — the
ordinary CPU body, the native artifact on the pinned software Vulkan device,
and the WGSL artifact on a software WebGPU device in the existing headless
browser harness — and requires element-exact agreement. Floating-point GPU
source remains refused until its cross-backend exactness contract is specified.

## Goals

- Run one authored kernel unchanged on a native device and in a browser.
- Keep SPIR-V canonical and add WGSL beside it rather than underneath it.
- Produce the browser shader inside the portable compiler, with no subprocess.
- Carry both device backends on one seam, so generated bindings name neither.
- Move a resident buffer without JSON, base64, or structured-clone payloads.
- State the browser numeric subset before its conformance tests, rather than
  hiding an incompatible float contract behind a tolerance.
- Test the browser backend on a device whose version changes only by review.

## Non-goals

- A fallback for hosts without WebGPU. WebGL2 has no compute shaders.
- Growing the browser subset past the native one, or feature-gated growth such
  as `shader-f16`, which is a later decision.
- Running a device on the page, sharing one device between worker lanes, or
  presenting to a canvas.
- Cross-origin isolation, `SharedArrayBuffer`, or Wasm threads.
- Browser `f32` kernels until a portable exactness contract admits them.
- A tolerance-based numeric contract for browser results.
- Const-specialized GPU kernels, which remain refused on every backend.

## Motivation

### Translation cannot happen where the artifact is wanted

[NEP 25](0025-gpu-compute-kernels.md) derives Metal from canonical SPIR-V with
a pinned translator during the build. That pattern assumes a build that can run
a subprocess. The reason to want a browser GPU backend at all is to run kernels
on a page that compiles them in the browser, and a Wasm-hosted compiler has no
process to spawn: a derived artifact would be exactly the artifact that cannot
be produced where it is needed.

Nothing available would fit even where a subprocess exists.
[NEP 17](0017-c-only-toolchain.md) removed Rust from the tree, which rules out
naga; the alternative is importing Dawn's translator and its dependencies to
gain one output format. Emitting WGSL from the compiler makes it a peer of
SPIR-V rather than a derivative, and the differential conformance run is what
keeps the peers honest, since there is no translator whose determinism could be
trusted instead.

### A second device backend needs a seam, not a second binding shape

The runtime GPU module is bound to LuaJIT's FFI, and the replacement generated
for a kernel names that module directly and packs its uniform block with an FFI
struct type. The Lua 5.1 Wasm host described in
[NEP 16](0016-portable-compiler-wasm-host.md) has neither. Nupp already has one
answer to "the same contract, two hosts": a seam with a conformance suite and a
provider per host. Making the GPU surface a seam is therefore a prerequisite of
the WebGPU provider rather than a part of it, and the uniform block — the one
piece of the contract that is a byte layout rather than a call — has to move
with it.

### The effect channel is the wrong size for a buffer

Browser effects cross the single yieldable boundary as JSON, with bytes encoded
and a host-side cap per request and per response. A resident buffer is the
payload that framing exists not to carry: a mebi-element `float` buffer is four
mebibytes raw and about five and a half encoded, so the first interesting
upload exceeds the cap, and every smaller one pays an encode, a decode, and two
copies for bytes that never leave the process.

The handler that services an effect runs in the same Worker as the Wasm module
and holds that module's heap. It cannot presently name a Lua allocation: the
Wasm storage provider exposes only opaque userdata to Lua, while the JavaScript
host sees only JSON protocol frames. The backend therefore adds a host-owned,
bounds-checked transfer lease. Its JSON form contains an opaque lease ID and
byte count, never a raw address; the host resolves it to a fresh `HEAPU8` view
at the point of `writeBuffer` or readback. There is no `SharedArrayBuffer` and
no cross-origin isolation in this host. This avoids protocol copies, not the
copy WebGPU makes between Wasm and device memory.

### WGSL needs its own exactness profile

NEP 25's central invariant is that GPU execution preserves the ordinary CPU
meaning exactly, and SPIR-V can ask for it: denormal preservation and
signed-zero/infinity/NaN preservation are execution modes a module declares.
WGSL has no spelling for either. A browser lowers a module through its own
translator to whatever the platform driver does, so subnormal flushing and NaN
payloads are decided below the artifact and vary by device.

Bit identity therefore cannot be assumed for floating point. The initial
browser profile admits only fixed-width integer storage, uniforms, and IR
operations whose wrapped integer meaning is shared by the CPU and WGSL. It
refuses `f32` parameters, storage, and operations at lowering. This is a
portable baseline rather than an assertion that float is unimportant: admitting
float later requires a source-visible finite-range and operation contract that
proves the ordinary CPU meaning is identical, not a tolerance in the test.

## Overview and specification

### Source is unchanged

The authored kernel is the one NEP 25 admits, with the workgroup phases of
[NEP 26](0026-structured-workgroup-phases.md) where it cooperates. Nothing in
the body, the annotation, or the resident-buffer protocol is browser-specific:

```nupp
@aot(target = "gpu")
local function xorMask(
    exclusive output: span.WriteSpan<uint32>,
    borrows input: span.Span<uint32>,
    mask: uint32
): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #output do
        output[i] = nupp.math.u32.xorBits(input[i], mask)
    end
end
```

The choice of device backend is a backend seam selection in the application's
target, beside the storage seams a Wasm application already names:

```nupp
export = Backend.new("app.browser", {
    Structvalue.seam("nupp.runtime.provider.wasmstorage"),
    Wasm.seam("nupp.runtime.provider.wasmstorage"),
    Gpu.seam("nupp.runtime.provider.browserwebgpu"),
})
```

### The GPU seam

`nupp.runtime.seam.gpu` carries the context, buffer, kernel, and binding
contract: opening and dropping a device, allocating and releasing typed
resident storage, compiling one generated kernel from its artifact set, binding
slots, dispatching a packed uniform block, and the upload, enqueue,
synchronize, and read halves of a transfer. Today's implementation becomes the
native provider unchanged in behavior; `nupp.runtime.provider.browserwebgpu` is
the second. The seam's suite is the conformance suite, so a provider that does
not answer the contract fails in isolation rather than inside a kernel.

The checked surface already permits suspension everywhere except `drop`, which
is `nosuspend` and which `device.destroy()` satisfies. No signature has to
change for a provider that parks.

`compileGenerated` takes an artifact set rather than a fixed SPIR-V and Metal
pair, and each provider selects the member it can consume. A provider handed a
kernel with no artifact it accepts raises at the dynamic compile call, naming
the kernel and backend.

### WGSL emission

A WGSL emitter sits beside the SPIR-V and Metal emitters and consumes the same
`scalarIR.Program`. It uses one bind group: storage buffers occupy bindings in
source slot order and the uniform block is the following binding. The dispatch
position is
`@builtin(global_invocation_id).x`, and the workgroup size is fixed in
`@workgroup_size`. A phase boundary is `workgroupBarrier()` and workgroup
scratch is `var<workgroup>`, which is the same structural mapping NEP 26 gives
the other backends.

The uniform block keeps its NEP 25 layout exactly: the dispatch count, one
count word per bound span in binding order, one offset word per span, then the
authored scalars, every field four-byte aligned and the whole block capped at
128 bytes.

The first profile accepts only `int32` and `uint32` storage and scalars. A
kernel using float, a narrow physical element, or a struct is refused at
lowering, naming the element and the `webgpu-int32` profile. Emitting
shift-and-mask packing would make the browser artifact structurally different
from the other two consumers of one IR, which is the divergence the
single-IR rule exists to prevent; if narrow storage is wanted later it belongs
in the IR, where every backend gets it at once.

### The uniform block without FFI

The generated replacement writes the block through the seam rather than through
an FFI struct type. At most 128 bytes of `u32` and `f32` makes the writer a
fixed sequence of 32-bit stores into a seam-owned byte region, emitted from the
same layout that produced the shader's declaration, and handed to the native
entry point unchanged on that side. The layout stays one compiler fact with
four consumers — SPIR-V, Metal, WGSL, and the writer — rather than a C
declaration that two of them agree with by inspection.

### Transfers use bounded Wasm-memory leases

The Wasm application host owns a transfer-lease table. The browser GPU provider
asks it to lease a proved span range; it answers an opaque ID, byte count, and
an expiry tied to the outstanding operation. An upload then enqueues an effect
naming the buffer handle and lease. The JavaScript handler validates the lease,
resolves it to a fresh view of the module's heap, and calls `writeBuffer`.

A download is the mirror: WebGPU copies into a mappable staging buffer, the
handler waits for `mapAsync`, writes the mapped bytes into the leased Wasm
range, and resumes with the lease ID. The provider validates and releases that
lease before it exposes the bytes to the destination span. Cancellation,
device loss, and any validation failure release every outstanding lease. The
effect JSON remains bounded control data; it never contains buffer contents or
a raw heap address.

Buffer handles are opaque on both sides. Lua never receives a device pointer or
a numeric heap address, which is the same rule the Wasm storage seam already
holds.

### Suspension points

`gpu.open()` parks on adapter and device request. `synchronize()` parks on
submitted-work completion. A download parks on the buffer map. Device loss and
validation errors resume the parked caller as an error rather than arriving out
of band, so a lost device fails the call that was waiting on it instead of the
next unrelated dispatch. A host with no WebGPU adapter fails at `gpu.open()`
with a diagnosable error, not at dispatch.

### Limits

The portable floors NEP 25 fixed — 256 workgroup threads and 16 KiB of
workgroup scratch — are WebGPU guarantees, so no kernel generated against the
portable floor is refused for its workgroup shape. Its storage-buffer floor is
eight bindings per compute stage, far below the native runtime's sixteen reads
plus sixteen writes. The `webgpu-int32` profile therefore accepts at most eight
total span parameters. The compiler rejects a larger browser artifact before
it produces WGSL; `gpu.open()` also requires an adapter whose reported limits
meet that profile.

The profile caps one resident allocation at WebGPU's guaranteed storage-buffer
binding size and the application host's Wasm-memory limit, whichever is
smaller. Allocation exceeding either raises rather than truncating. A later,
explicitly named WebGPU profile may request larger adapter limits, but it does
not silently widen a portable artifact.

### Conformance

The browser application suite gains an integer GPU case through the existing
headless browser harness with a software adapter selected, so the device is one
named implementation rather than whatever the runner has. Every conformance
vector runs three ways — the ordinary CPU body, the native artifact on the
pinned software Vulkan device, and the WGSL artifact in the browser — and the
three must agree element-exactly across wrapped arithmetic, non-multiple
workgroup tails, every binding class, independent span counts, and repeated
dispatch over resident intermediates.

A missing adapter fails the job. It is not converted to a skip, for the reason
NEP 25 gives: a GPU suite that can pass by not running is a compile-only suite
with extra steps.

### What stays refused

A GPU kernel is not a Wasm side module. It remains a separate artifact class
carried by the generated binding, so a Wasm application target gains a shader
artifact rather than another compiled unit, and the refusal that rejects
`target = "gpu"` under a Wasm target narrows to the cases this backend does not
admit rather than disappearing.

## Risks and assumptions

- **Float is deferred rather than fuzzed.** The initial integer profile avoids
  WGSL's implementation-defined floating-point edge behavior. A future float
  profile needs an explicit proof obligation for ranges, rounding, NaNs,
  infinities, signed zero, and subnormals before it can add one operation.
- **A software WebGPU device is the deterministic floor, not proof.** It says
  nothing about what a vendor's browser and driver pair does, exactly as
  SwiftShader says nothing about a physical Vulkan driver. Hardware runs stay
  useful evidence and are not the gate.
- **Two emitters can drift where a translator could not.** The defense is that
  an IR construct with no WGSL case fails emission rather than emitting
  something, and that conformance compares the two artifacts on every vector.
- **The transfer lease is a new host ABI.** It is deliberately opaque and
  short-lived, but it touches allocation, cancellation, and the JavaScript
  host. A host that services effects off-thread needs a different transfer
  design rather than a larger JSON cap.
- **WebGPU availability is uneven.** Worker-scope support and adapter behavior
  differ by browser. The backend is opt-in per application, and the failure is
  at device open where it can be reported.
- **The seam refactor touches the working native path.** Most of it is
  mechanical because the checked surface already carries the ownership
  contract; the uniform writer is the part where a mistake is silent, so its
  bytes are asserted against the layout the shaders declare.

## Alternatives considered

**Translating canonical SPIR-V to WGSL with a pinned tool.** This is what NEP
25 does for Metal and would have kept one emitter. It fails twice: no
translator fits a toolchain that removed Rust without importing Dawn, and a
browser-hosted compiler cannot run one at all, so the artifact would be missing
from the only host that needs it.

**A second generated replacement shape for browser targets.** It avoids
touching the native runtime module, and it makes a kernel's host surface two
programs whose uniform layout agrees by inspection. The layout is the part most
likely to break silently, which is the argument for one seam.

**Base64 transfers through the ordinary effect channel.** Nothing new is
required and a few thousand elements would work. The first buffer worth
dispatching over exceeds the request cap, so this is a decision to keep the
feature a demonstration.

**Running the device on the page instead of the application Worker.** The page
owns the canvas and would be the right place if rendering were in scope. Today
it would put every transfer through a structured clone, and the bytes already
live in the Worker's heap.

**A tolerance for browser results.** NEP 25 rejected backend-selected relaxation
for native, and adopting it here would make `target = "gpu"` mean one thing on a
desktop and another in a browser — a difference that would show up as wrong
answers rather than as a refusal.

**Starting with float because the native example scales floats.** WebGPU's
integer operations give the first browser backend an element-exact contract,
while floating-point exceptional values and rounding are not yet a shared
contract. An integer profile is a useful backend; a claimed-exact float profile
without those rules would only look more complete.

**A WebGL2 compute fallback for hosts without WebGPU.** WebGL2 has no compute
shaders; emulating them through transform feedback would be a third semantics
with no CPU meaning to check it against.
