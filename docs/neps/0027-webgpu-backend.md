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
memory, so a transfer names a region of that memory instead of carrying its
bytes through the effect channel. Device acquisition, submission, and readback
park on the existing browser suspension protocol. Conformance runs one kernel
three ways — the ordinary CPU body, the native artifact on the pinned software
Vulkan device, and the WGSL artifact on a software WebGPU device in the
existing headless browser harness — and requires element-exact agreement.

## Goals

- Run one authored kernel unchanged on a native device and in a browser.
- Keep SPIR-V canonical and add WGSL beside it rather than underneath it.
- Produce the browser shader inside the portable compiler, with no subprocess.
- Carry both device backends on one seam, so generated bindings name neither.
- Move a resident buffer without encoding it.
- Put WebGPU's weaker float guarantees into the admission rules rather than
  into a test's tolerance.
- Test the browser backend on a device whose version changes only by review.

## Non-goals

- A fallback for hosts without WebGPU. WebGL2 has no compute shaders.
- Growing the browser subset past the native one, or feature-gated growth such
  as `shader-f16`, which is a later decision.
- Running a device on the page, sharing one device between worker lanes, or
  presenting to a canvas.
- Cross-origin isolation, `SharedArrayBuffer`, or Wasm threads.
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
and holds that module's heap. A transfer therefore only has to *name* a region
rather than contain it. There is no `SharedArrayBuffer` and no cross-origin
isolation in this host, so that in-Worker heap view is the only zero-copy path
available, and designing transfers around it from the start is what separates a
GPU backend from a demonstration.

### WGSL cannot express the numeric guarantees SPIR-V can

NEP 25's central invariant is that GPU execution preserves the ordinary CPU
meaning exactly, and SPIR-V can ask for it: denormal preservation and
signed-zero/infinity/NaN preservation are execution modes a module declares.
WGSL has no spelling for either. A browser lowers a module through its own
translator to whatever the platform driver does, so subnormal flushing and NaN
payloads are decided below the artifact and vary by device.

Bit identity therefore cannot be assumed for this backend. It has to be a rule
about which operations are admitted, decided before the conformance suite is
written, because a suite that only diffs GPU against CPU would otherwise
discover the gap one browser and one device at a time.

## Overview and specification

### Source is unchanged

The authored kernel is the one NEP 25 admits, with the workgroup phases of
[NEP 26](0026-structured-workgroup-phases.md) where it cooperates. Nothing in
the body, the annotation, or the resident-buffer protocol is browser-specific:

```nupp
@aot(target = "gpu")
local function scale(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>,
    factor: float
): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #output do
        output[i] = nupp.math.f32.mul(nupp.math.f32.narrow(input[i]), factor)
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
kernel with no artifact it accepts raises at compile time, naming the kernel
and the backend.

### WGSL emission

A WGSL emitter sits beside the SPIR-V and Metal emitters and consumes the same
`scalarIR.Program`. Resource layout mirrors NEP 25's, one bind group per
descriptor set: group 0 holds readonly storage buffers in source slot order,
group 1 holds read-write storage buffers in source slot order, group 2 binding
0 holds the uniform block, the dispatch position is
`@builtin(global_invocation_id).x`, and the workgroup size is fixed in
`@workgroup_size`. A phase boundary is `workgroupBarrier()` and workgroup
scratch is `var<workgroup>`, which is the same structural mapping NEP 26 gives
the other backends.

The uniform block keeps its NEP 25 layout exactly: the dispatch count, one
count word per bound span in binding order, one offset word per span, then the
authored scalars, every field four-byte aligned and the whole block capped at
128 bytes.

WGSL's storage address space holds 32-bit scalars only. A kernel whose span
element is a narrower physical type is refused at lowering, naming the element
and the backend. Emitting shift-and-mask packing instead would make the browser
artifact structurally different from the other two consumers of one IR, which
is the divergence the single-IR rule exists to prevent; if narrow storage is
wanted later it belongs in the IR, where every backend gets it at once. Value
conversions that are already synthesized from integer arithmetic, such as the
half and bfloat helpers, are unaffected — their storage is a 32-bit word.

### The uniform block without FFI

The generated replacement writes the block through the seam rather than through
an FFI struct type. At most 128 bytes of `u32` and `f32` makes the writer a
fixed sequence of 32-bit stores into a seam-owned byte region, emitted from the
same layout that produced the shader's declaration, and handed to the native
entry point unchanged on that side. The layout stays one compiler fact with
four consumers — SPIR-V, Metal, WGSL, and the writer — rather than a C
declaration that two of them agree with by inspection.

### Transfers name memory

An upload allocates or reuses a staging region in the host's own memory through
the storage seam, copies the source span into it, and enqueues an effect naming
the buffer handle, the region, and its byte extent. The JavaScript handler
resolves that region to a view of the module's heap and calls `writeBuffer`;
nothing is encoded. A download is the mirror: a copy into a mappable buffer,
a park on the map, and a response naming the region the handler filled, which
`readDownloaded` copies into the destination span. The effect JSON stays small
enough that the existing request and response caps are untouched, and the
number of copies is the one the seam's opaque memory already requires.

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
workgroup scratch — are exactly WebGPU's guaranteed maximum compute
invocations per workgroup and maximum workgroup storage size, so no kernel
generated against the portable floor is refused for its shape. The guaranteed
limit this backend must obey instead is storage buffers per shader stage, which
bounds how many spans one kernel may bind; exceeding it is a lowering refusal
naming the limit rather than a runtime failure. The guaranteed maximum storage
buffer binding size and buffer size bound one resident allocation, and
exceeding either raises at allocation rather than truncating.

### Conformance

The browser application suite gains a GPU case alongside its scalar and SIMD
cases, driven by the existing headless browser harness with a software adapter
selected, so the device is one named implementation rather than whatever the
runner has. Every conformance vector runs three ways — the ordinary CPU body,
the native artifact on the pinned software Vulkan device, and the WGSL artifact
in the browser — and the three must agree element-exactly across exact-match
vectors, non-multiple workgroup tails, every binding class, independent span
counts, and repeated dispatch over resident intermediates.

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

- **WGSL float semantics are decided below the artifact.** The bet is that the
  admitted operation set does not depend on subnormal or NaN behavior. If that
  is wrong, the browser subset narrows further, or the guarantee is restated as
  exact over the normal range. It is not answered with a tolerance.
- **A software WebGPU device is the deterministic floor, not proof.** It says
  nothing about what a vendor's browser and driver pair does, exactly as
  SwiftShader says nothing about a physical Vulkan driver. Hardware runs stay
  useful evidence and are not the gate.
- **Two emitters can drift where a translator could not.** The defense is that
  an IR construct with no WGSL case fails emission rather than emitting
  something, and that conformance compares the two artifacts on every vector.
- **The transfer design assumes effects are serviced in the module's Worker.**
  A host that ever services them off-thread loses the heap view, and transfers
  would need a different design rather than a larger cap.
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

**A WebGL2 compute fallback for hosts without WebGPU.** WebGL2 has no compute
shaders; emulating them through transform feedback would be a third semantics
with no CPU meaning to check it against.
