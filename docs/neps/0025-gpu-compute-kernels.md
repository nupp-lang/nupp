---
title: GPU compute kernels
status: Superseded by NEP 29
created: 2026-08-29
---

## Summary

An `@aot(target = "gpu")` function is one ordinary Nupp function whose verified
scalar IR may also become a compute shader. Calls cross a typed resident-buffer
boundary: storage is allocated and transferred explicitly, generated kernel
objects preserve the function's span and scalar types, and any number of
dispatches may reuse the same buffers before a download.

SPIR-V is the canonical shader artifact. A pinned SPIRV-Cross translates that
artifact to Metal Shading Language during the build; Metal compiles the
translated source when the compute pipeline is created. A pinned SwiftShader
Vulkan device is the headless conformance device, so shader execution is tested
in CI even when the runner has no physical GPU.

GPU execution preserves the ordinary CPU meaning of the same source. Operations
whose result cannot be made bit-identical are absent rather than silently
relaxed, and the verified IR remains the authority for buffer access, resource
layout, control flow, and arithmetic.

## Goals

- Give checked Nupp a compute target without a second shader language in source.
- Make CPU and GPU execution two consumers of one verified operation sequence.
- Keep buffers resident across dispatches and make transfers explicit.
- Prove every storage access before shader emission.
- Make shader layout and generated host bindings two views of one compiler fact.
- Carry one canonical portable artifact into both Vulkan and Metal builds.
- Exercise real dispatch and readback on a deterministic headless CI device.
- Refuse operations whose ordering or rounding has no ordinary CPU definition.

## Non-goals

- Inferring GPU placement, transfers, fusion, or lifetime from ordinary spans.
- Accepting arbitrary Nupp, Lua allocation, tables, closures, suspension, or
  host calls inside a kernel.
- Transparent unified memory or implicit residency.
- Backend-selected fast math, unordered reductions, or tolerance-based answers.
- Shipping Apple `metallib` files or requiring Apple's toolchain to build Nupp.
- Making cooperative matrices bit-identical to a scalar CPU definition.
- Replacing SDL GPU or exposing its raw binding conventions to source.

## Motivation

### A second source language would split the semantics

Writing a kernel again in MSL, GLSL, or HLSL makes the validation body and the
accelerated body independent programs. Matching signatures do not prove they
index the same elements, take the same branches, or round in the same order.
The existing AOT scalar IR already records those decisions and has a verifier,
so a GPU backend should consume that fact rather than parse a parallel program.

### Host spans are the wrong call boundary

Passing host spans directly to every kernel call makes each call imply uploads
and downloads. That prevents a chain of kernels from keeping intermediates on
the device and makes transfer cost inseparable from dispatch cost. Explicitly
typed resident buffers make the expensive boundary visible and let one uploaded
value feed any number of generated bindings.

### One native shader format is not portable

SDL's Vulkan backend consumes SPIR-V while its Metal backend consumes MSL or a
`metallib`. Treating handwritten MSL as canonical would make Vulkan a separate
backend design. Treating a `metallib` as the portable artifact would require an
Apple-only build exception and still provide nothing to Vulkan. SPIR-V has the
structured control-flow and resource model the verified IR needs, and a pinned
translator makes MSL a deterministic derivative rather than another source of
truth.

### A compile-only suite is not conformance

Shader validation and source inspection catch malformed artifacts but not
resource binding, uniform layout, dispatch bounds, driver acceptance, or
readback. Physical hosted runners are variable and often absent. A pinned
software Vulkan implementation gives the suite one named execution device whose
version changes only through review.

## Overview and specification

### Source contract

The target is selected on an ordinary local function:

```nupp
local span = require("nupp.mem.span")

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

The annotation chooses an execution target; it does not introduce a new
function kind or change the body's ordinary meaning. The admitted entry is a
complete one-based map over its primary writable span. The loop index is a
value in the body and lowers from the zero-based dispatch position by adding
one.

Every span addressed by that index is either the loop bound or is proved equal
to it by the entry guard. A span of another length may be reached only through a
`uint32` cursor used as `span[cursor + 1]` under a dominating
`cursor < #span` branch. Lowering rejects a missing proof at the authored source
position; verifier failures are compiler bugs, not diagnostics.

### Resident calls

The declaration is replaced by a typed kernel specification. A caller opens a
context, allocates typed buffers, uploads complete spans, compiles the generated
specification, binds every buffer slot, and dispatches scalar uniforms. Commands
remain asynchronous until synchronization or a download boundary.

```nupp
local context = gpu.open()
local input = context:buffer(ffi.typeof("float"), count)
local output = context:buffer(ffi.typeof("float"), count)
context:upload(input, source)

local kernel = scale:compile(context)
local invocation = kernel:bind(output, input)
invocation:dispatch(factor)
context:download(output, destination)
```

The context owns kernels, bindings, resident storage, and transfer buffers.
Buffers cannot cross contexts, a binding must fill every generated slot, and a
slot proved equal to the dispatch count is checked when bound. Downloads and
uploads cover complete buffers; subviews are a later decision.

### Verified shader subset

The shader consumes the same verified scalar program as native AOT. Its closed
operation set includes structured branches and loops, fixed-width scalar
arithmetic, explicit binary32 operations, proved storage loads and stores, and
scalar uniforms. Binary32 contraction is disabled unless the source writes
`f32.fma`; NaNs and narrow-storage conversions use compiler-defined canonical
forms.

The subset grows by adding an operation to the IR, verifier, CPU meaning, and
every shader consumer together. There is no backend-only intrinsic whose answer
cannot be produced by the ordinary body.

### Canonical and derived artifacts

The compiler emits a SPIR-V compute module directly from verified IR. Resource
bindings follow SDL's compute convention:

- descriptor set 0 holds readonly storage buffers in source slot order;
- descriptor set 1 holds read-write storage buffers in source slot order;
- descriptor set 2, binding 0 holds the uniform block;
- the dispatch position is the `GlobalInvocationId.x` builtin;
- the declared workgroup size is fixed in the module's execution mode.

SPIR-V is emitted as little-endian words and validated in tests before it is
handed to a driver or translator. A pinned SPIRV-Cross executable derives MSL
from those exact bytes during artifact construction. The generated binding
embeds both the canonical SPIR-V and its derived MSL.

The runtime advertises SPIR-V and MSL when creating the SDL device. A Vulkan
device receives the SPIR-V bytes. A Metal device receives the derived MSL text,
which SDL compiles when creating the compute pipeline. This is called
build-time translation and pipeline-time compilation, not a precompiled Metal
shader. No `metallib` is produced or shipped.

The translator revision and archive digest are part of Nupp's pinned toolchain.
Changing either is a reviewed dependency update and invalidates generated
artifacts. The canonical SPIR-V remains independently inspectable, so a
translator change cannot silently redefine the kernel.

### Uniform layout

The uniform block is one three-way ABI shared by SPIR-V, derived MSL, and the
generated host FFI struct. Word zero is the dispatch element count. One word per
span follows in binding order, readonly spans first and writable spans second.
Authored scalar uniforms follow. The runtime patches the count words from the
buffers actually bound before each dispatch.

Every field is four-byte aligned and the complete block is capped at 128 bytes.
The shader compares the dispatch position against word zero before touching
storage, so over-dispatching a final workgroup is inert.

### Headless conformance device

Linux CI provisions one pinned SwiftShader revision and archive digest, builds
its Vulkan ICD, and points the Vulkan loader at that generated ICD manifest.
The conformance job builds SDL with Vulkan support and runs GPU suites against
that device. A driver mismatch, missing device, skipped dispatch, or failed
readback fails the job; it is not converted to a skip.

The conformance suite covers exact-match vectors, non-multiple workgroup tails,
all binding classes, independent span counts, repeated dispatch over resident
intermediates, and generated kernels used by retained benchmarks. Hardware runs
remain useful performance evidence but are not the semantic gate.

## Risks and assumptions

- SwiftShader may differ from physical drivers. It is the deterministic floor,
  not evidence that every vendor compiler accepts every artifact; retained
  hardware runs cover that separate risk.
- SPIRV-Cross may change generated MSL without changing SPIR-V. Pinning and
  exact generated-source tests make such a change visible, but an update still
  needs a Metal execution run.
- Pipeline-time MSL compilation adds startup cost. Kernel objects are reusable,
  and avoiding an Apple-only build toolchain is worth that one-time cost.
- Bit identity limits the operation set and may cost performance. A future
  tolerance family requires its own proposal and cannot weaken this one.
- SDL's binding ABI is external. Tests assert the descriptor and Metal buffer
  positions so an upstream convention change fails loudly.

## Alternatives considered

**Handwritten or directly emitted MSL as the canonical artifact.** This built
the first spike quickly but left Vulkan needing a second control-flow and
resource emitter. Two native sources would let the backends diverge before a
driver saw them.

**Apple `metallib` artifacts.** They move compilation out of pipeline creation
but require Apple's toolchain and platform-specific outputs. That exception was
rejected; translated MSL source remains portable build data.

**Runtime SPIRV-Cross.** It avoids embedding MSL but adds a large C++ translator
to every application and turns pipeline creation into toolchain work. Translation
belongs in the build, where its output can be cached and inspected.

**A named GPU exclusion in CI.** Compile-only coverage is cheaper but leaves the
resource ABI and execution semantics untested. A pinned software Vulkan device
was chosen instead.

**Implicit host-span calls.** Convenient for one isolated kernel and unable to
represent a useful chain without transfers between every stage. Explicit
resident buffers keep that cost and lifetime visible.

**Backend-selected fast math and reductions.** They can be faster, but neither
has one ordinary CPU answer. Operations without a fixed sequence stay outside
this semantics rather than making `target = "gpu"` a numerical relaxation.
