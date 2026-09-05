---
order: 637
---

# GPU compute

`@aot(target = "gpu")` turns one verified Nupp function into a typed kernel
specification. Native targets emit SPIR-V for the Rust WGPU provider, while
browser targets emit WGSL from the same checked operation sequence.

```nupp
local span = nupp.mem.span

@aot(target = "gpu")
local function scale(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>,
    factor: float
): nil
    assert(#output == #input, "length mismatch")
    for index = 1, #output do
        output[index] = nupp.math.f32.mul(input[index], factor)
    end
end
```

The ordinary function body remains the CPU definition. The GPU backend accepts
only operations whose storage access, control flow, and arithmetic it can
verify against that definition.

## Resident buffers

A native `aot = "require"` target replaces the declaration with a kernel
specification. The application allocates buffers, compiles the specification,
binds buffers in parameter order, and dispatches scalar uniforms separately:

```nupp
local gpu = nupp.gpu
local kernels = require("kernels")
local span = nupp.mem.span

local context = gpu.open()
local input = context:buffer(ffi.typeof<float>(), 1024)
local output = context:buffer(ffi.typeof<float>(), 1024)
local binding = kernels.scale:compile(context):bind(output, input)
local sourceStorage = carray(float, 1024)
local outputStorage = carray(float, 1024)

context:upload(input, span.fromCarray(sourceStorage, 1024))
binding:dispatch(2.0)
context:enqueueDownload(output)
context:synchronize()
context:readDownloaded(output, span.writeCarray(outputStorage, 1024))
```

Uploads, dispatches, and downloads enqueue work. `synchronize()` is the explicit
CPU boundary, so a chain of kernels can keep intermediate buffers resident.
The context owns its buffers and compiled kernels; their borrows prevent the
context from closing while one remains live.

## Map kernels

A map kernel assigns one complete-span iteration to one GPU invocation. Every
span indexed by the loop position must match the primary output length, unless
a separately bounded `uint32` cursor proves access to another span.

The declaration may take multiple read and write spans plus at most 128 bytes
of fixed-width scalar uniforms. Host transfers stay explicit, and generated
bindings preserve the declared element types and parameter order.

## Structured workgroups

`gpu.workgroups(groups, size, controller)` describes a fixed-size workgroup.
The controller allocates bounded scratch and divides execution into immediate
`phases:run` callbacks:

```nupp
local gpu = nupp.gpu
local span = nupp.mem.span

@aot(target = "gpu")
local function reduce(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    local groups = nupp.math.u32.div(
        nupp.math.u32.wrap(#input),
        nupp.math.u32.wrap(4)
    )
    gpu.workgroups(groups, 4, function(groupIndex: uint32, phases: gpu.Phases)
        local shared = phases:scratch(nupp.math.f32.narrow(0.0), 4)
        phases:run(function(localIndex: uint32)
            local cursor = nupp.math.u32.add(
                nupp.math.u32.mul(groupIndex, nupp.math.u32.wrap(4)),
                localIndex
            )
            if cursor < #input then
                shared[localIndex] = input[cursor + 1]
            end
        end)
        phases:reduceSumF32(shared)
        phases:run(function(localIndex: uint32)
            if localIndex == nupp.math.u32.wrap(0) and groupIndex < #output then
                output[groupIndex + 1] = shared[0]
            end
        end)
    end)
end
```

Generated workgroups admit at most 256 lanes and 16 KiB of scratch. Scratch
writes are structurally disjoint. `reduceSumF32` and `inclusiveScanU32` expand
to fixed trees whose stage order is the same in the CPU definition and the GPU
artifact; unordered and atomic reductions are not part of this contract.

## Tensor layouts and fixed-width storage

`Context:tensor(element, shape)` allocates dense row-major storage.
The `nupp.gpu.layout` module (imported as `layout`) provides
`layout.subview`, `layout.transpose`, `layout.broadcast`, and
`layout.asStrided` to transform checked layout values without allocating.

`gpu.view` applies a layout while preserving the buffer element type.

Host transfers and dispatch-indexed spans require dense layouts. Cursor-indexed
kernels may consume other input layouts by passing dimensions and strides as
scalar uniforms. Writable views also require disjoint coordinates and a
complete span extent, so broadcast and overlapping writes are refused.

The fixed-width math modules make binary16 and bfloat16 conversion explicit.
Narrow integer names remain available as physical span and buffer element types,
so applications can define their storage interpretation while keeping
accumulation explicit binary32.

## Browser GPU kernels

A browser target combines `dialect = "lua51"`, the browser backend, and
`aot = "require-wasm"`. GPU kernels use `nupp.mem.span.Span` and
`nupp.mem.span.WriteSpan` so the Worker can transfer bounded Wasm-memory leases:

```nupp
local span = nupp.mem.span
local array = nupp.mem.array

@aot(target = "gpu")
local function addMask(
    exclusive output: span.WriteSpan<uint32>,
    borrows input: span.Span<uint32>,
    mask: uint32
): nil
    assert(#output == #input, "length mismatch")
    for index = 1, #output do
        output[index] = nupp.math.u32.add(input[index], mask)
    end
end
```

The portable WebGPU profile admits complete-span maps over `int32` and
`uint32` storage with scalar uniforms. It refuses floats, structs,
cursor-indexed storage, and workgroup phases. WebGPU is required; no different
graphics API is substituted when it is unavailable.

See [wasm.md](wasm.md#browser-package) for the application package and Worker
host around this kernel.

## Browser GPU effect

`nupp.experimental.webgpu.xorU32` is a smaller browser-only surface for a program that
needs one checked WebGPU operation without owning a generated kernel binding:

```nupp:playground
local gpu = nupp.experimental.webgpu
local u32 = nupp.math.u32.wrap

local values = {u32(0), u32(0x00ff00ff), u32(0xffffffff)}
local output = gpu.xorU32(values, u32(0xa5a5a5a5))
print(output[1], output[2], output[3])
```

The effect enqueues one invocation per value and returns after the Worker copies
the result back. It accepts at most 262,144 `uint32` values. Generated kernels
are the surface for resident buffers, multiple operations, and source-defined
compute.

## Inspection and limits

`nupp aot --emit spirv FILE` writes the native WGPU module. On macOS WGPU
translates that module for Metal internally; Nupp does not ship a second Metal
artifact or a shader translator. `nupp aot --emit wgsl FILE` prints the browser
WebGPU artifact when the kernel belongs to the portable profile. The AOT report
records the GPU family and the compiler's verified resource facts.

GPU kernels cannot allocate Lua values, suspend, call dynamic functions, or use
unproved storage. Native workgroup and tensor facilities require the native GPU
provider selected by the built target. Browser availability is checked by the
host before dispatch.

::: seealso
- [annotations.md](../../../reference/annotations.md#built-in-annotations)
  for the exact `@aot` arguments
- [build-and-artifacts.md](build-and-artifacts.md) for AOT target policies and
  artifact caching
- [](nupp.gpu) for the generated binding and resident-buffer API
- [](nupp.gpu.layout) for layout functions
:::
