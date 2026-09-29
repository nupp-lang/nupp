---
order: 637
---

# GPU compute

`@aot(target = "gpu")` turns one verified Nupp function into a typed kernel
specification. Native targets emit SPIR-V for the Rust WGPU provider, while
browser targets emit WGSL from the same checked operation sequence.

```nupp
local span = require("nupp.mem.span")

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

Its guards may only relate span lengths. The generated binding checks every
such relation when the resident buffers are bound. A dispatch has no wrapper
for a relation involving its scalar uniforms, and a GPU entry always covers a
whole span, so a fact of any other shape is refused rather than silently
dropped on the way to the device. The same kernel targeting the CPU may state
it.

## Resident buffers

A native `aot = "require"` target replaces the declaration with a kernel
specification. The application allocates buffers, compiles the specification,
binds buffers in parameter order, and dispatches scalar uniforms separately:

```nupp
local gpu = require("nupp.gpu")
local kernels = require("kernels")
local array = nupp.mem.array

local source = array.scalar(array.float, 1024)
local result = array.scalar(array.float, 1024)

with context = gpu.open() do
    with input = context:buffer(array.float, 1024), output = context:buffer(array.float, 1024) do
        with kernel = kernels.scale:compile(context) do
            with binding = kernel:bind(output, input) do
                context:upload(input, source:read())
                binding:dispatch(2.0)
            end
        end
        context:enqueueDownload(output)
        context:synchronize()
        context:readDownloaded(output, result:write())
    end
end
```

Uploads, dispatches, and downloads enqueue work. `synchronize()` is the explicit
CPU boundary, so a chain of kernels can keep intermediate buffers resident.
The context, its buffers, compiled kernels and bindings are all closeable, and
each child borrows what it was made from: a binding its kernel, a kernel and a
buffer the context. The checker therefore refuses a close while something still
borrows the closed value, and any use after a close. `with` gives each one exact
extent; `nupp.drop(buffer)` releases a buffer early. Closing a root buffer
releases its allocation, and closing a view ends only the view. No close
suspends. `gpu.open()` raises when no device can be opened, so a program with
another way to run asks `gpu.available()` first.

## Map kernels

A map kernel assigns one complete-span iteration to one GPU invocation. Every
span indexed by the loop position must match the primary output length, unless
a separately bounded `uint32` cursor proves access to another span.

A dispatch may cover any `uint32` element count. A device runs at most 65535
workgroups along one dimension, 16,776,960 elements at the default 256 lanes,
so a longer dispatch is folded into rows of workgroups and the generated shader
recovers each invocation's position from its row. Both providers fold the same
way, and a dispatch is refused only past 65535 rows, which no `uint32` count
reaches at more than one lane per workgroup.

The declaration may take multiple read and write spans plus at most 128 bytes
of fixed-width scalar uniforms. Host transfers stay explicit, and generated
bindings preserve the declared element types and parameter order.

Inside a map, numeric loops such as `for round = 1, 64 do` support an implicit
step of one. Bounds must be `int32` values or exact signed 32-bit literals.
They are evaluated once, left to right, before the loop; assignments in the
body do not change the bound or the loop's internal counter. Empty ranges,
`break`, `continue`, and a last iteration at `2147483647` preserve ordinary
numeric-loop behavior in both SPIR-V and WGSL. Explicit steps, fractional or
`uint32` bounds, and nested span-length bounds are refused at their source
position.

## Structured workgroups

`gpu.workgroups(groups, size, controller)` describes a fixed-size workgroup.
The controller allocates bounded scratch and divides execution into immediate
`phases:run` callbacks:

```nupp
local gpu = require("nupp.gpu")
local span = require("nupp.mem.span")

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
        phases:reduceSum(shared)
        phases:run(function(localIndex: uint32)
            if localIndex == nupp.math.u32.wrap(0) and groupIndex < #output then
                output[groupIndex + 1] = shared[0]
            end
        end)
    end)
end
```

Generated workgroups admit at most 256 lanes and 16 KiB of scratch. Scratch
writes are structurally disjoint. `reduceSum` and `inclusiveScan` expand
to fixed trees whose stage order is the same in the CPU definition and the GPU
artifact; unordered and atomic reductions are not part of this contract.

## Tensor layouts and fixed-width storage

`Context:tensor(element, shape)` allocates dense row-major storage.
The `nupp.gpu.layout` module (imported as `layout`) builds one with
`layout.new(shape, strides, offset?)` and provides `layout.subview`,
`layout.transpose`, `layout.broadcast`, and `layout.asStrided` to transform
checked layout values without allocating. A layout answers `dimensions()`,
`strides()`, `offset()`, `extent()`, `isDense()` and `isInjective()` as
methods, the way a buffer does.

`buffer:view(layout)` applies a layout while preserving the buffer element type, and
`buffer:isDense()` and `buffer:isInjective()` answer for the buffer or view.

Host transfers and dispatch-indexed spans require dense layouts. Cursor-indexed
kernels may consume other input layouts by passing dimensions and strides as
scalar uniforms. Writable views also require disjoint coordinates and a
complete span extent, so broadcast and overlapping writes are refused. One
allocation cannot be bound for both reading and writing in a dispatch, even
through disjoint views: devices track usage per allocation, not per range.

The fixed-width math modules make binary16 and bfloat16 conversion explicit.
GPU kernels need 32-bit storage: a span or struct field of `int8`, `uint8`,
`int16` or `uint16` is refused where the kernel is written, because WGPU's
SPIR-V front end, which every native backend goes through, refuses 8-bit
storage buffers and cannot validate 16-bit ones. Keep a binary16 or bfloat16
value in the low half of a `uint32` element and convert it with
`fromF16Bits`/`fromBF16Bits`, accumulating in explicit binary32. A host-side
buffer may still hold narrow elements: the device moves whole 32-bit words, so
a narrow buffer whose bytes end partway through one is padded to it, and an
upload, download or binding may end partway through a word only where it ends
the buffer.

## Browser GPU kernels

A browser target combines `host = "browser"` and `aot = "require-wasm"`. GPU kernels use `nupp.mem.span.Span` and
`nupp.mem.span.WriteSpan`; the Worker transfers bounded copies between guest
storage and WebGPU buffers:

```nupp
local span = require("nupp.mem.span")
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

WebGPU reports a rejected call later rather than at the call, so the page checks
every GPU operation before answering it. A validation or out-of-memory error
fails the operation that caused it, and an error nothing was waiting for fails
the next one. A dispatch too long for one dimension of workgroups is folded
into rows as it is natively; one past the device's per-dimension limit in rows
as well is refused before it is submitted, with the same message the native
provider gives.

See [wasm.md](wasm.md#browser-package) for the application package and Worker
host around this kernel.

## Inspection and limits

`nupp aot --emit spirv FILE` writes the native WGPU module. On macOS WGPU
translates that module for Metal internally; Nupp does not ship a second Metal
artifact or a shader translator. `nupp aot --emit wgsl FILE` prints the browser
WebGPU artifact when the kernel belongs to the portable profile. The AOT report
records the GPU family and the compiler's verified resource facts. Its `gpu`
object names the shader digest, authored source position, entrypoint and
workgroup width. `nupp build --remarks-out` also records `GPU-DISPATCH` at the
authored declaration, including that same digest.

For native operation costs, use `nupp run --gpu-costs costs.jsonl PROGRAM`.
It composes with `--profile` so host samples and device events can be inspected
together. `nupp bench --gpu-costs DIRECTORY` allocates a separate JSONL file for
every case, fork and comparison candidate; the benchmark JSON names each file.
The [profiling guide](../profiling.md#native-gpu-costs) explains the events
and device timestamp availability. Cost recording adds overhead, so collect
an instrumented account separately from uninstrumented CPU/GPU comparisons.

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
