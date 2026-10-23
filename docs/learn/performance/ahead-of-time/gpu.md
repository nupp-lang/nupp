---
order: 637
---

# GPU compute

`@aot(target = "gpu")` turns one verified Nupp function into a typed kernel
specification.

::: warning
The VM has no GPU provider yet. On it `gpu.available()` answers `false` and
`gpu.open()` raises "GPU compute is not available on the VM runtime yet", so a
kernel checks and binds but no device runs it.
:::

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
        output[index] = input[index] * factor
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

```nupp:fragment
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
CPU boundary, so a chain of kernels can keep intermediate buffers resident. It
parks rather than blocking the thread: while the device works, other tasks run,
and a task deadline or cancellation reaches the wait. With nothing to yield to it
sleeps until the work is done.
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
            local cursor = groupIndex * 4 + localIndex
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

The group count must be written as `u32.div(u32.wrap(#span), size)`, and the
kernel runs exactly that many groups, floor(`#span` / `size`), on the CPU and
on the device alike. When the span is not a whole number of groups, the
elements past the last whole group are not visited; pad the span to a multiple
of the workgroup size to cover them.

Generated workgroups admit at most 256 lanes and 16 KiB of scratch. Scratch
writes are structurally disjoint. `reduceSum` and `inclusiveScan` expand
to fixed trees whose stage order is the same in the CPU definition and the GPU
artifact; unordered and atomic reductions are not part of this contract.

## Tensor layouts and fixed-width storage

`Context:tensor(element, shape)` allocates dense row-major storage. The
`nupp.gpu.layout` module (imported as `layout`) builds one with
`layout.new(shape, strides, offset?)` and provides `layout.subview`,
`layout.transpose`, `layout.broadcast`, and `layout.asStrided` to transform
checked layout values without allocating. A layout provides `dimensions()`,
`strides()`, `offset()`, `extent()`, `isDense()` and `isInjective()` as methods,
the way a buffer does.

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

## Inspection and limits

The build emits the native WGPU module as SPIR-V. On macOS WGPU translates that
module for Metal internally; Nupp does not ship a second Metal artifact or a
shader translator.

For native operation costs, use `nupp run --gpu-costs costs.jsonl PROGRAM`.
`nupp bench --gpu-costs DIRECTORY` allocates a separate JSONL file for
every case, fork and comparison candidate; the benchmark JSON names each file.
[Native GPU costs](#native-gpu-costs) explains the events
and device timestamp availability. Cost recording adds overhead, so collect
an instrumented account separately from uninstrumented CPU/GPU comparisons.

GPU kernels cannot allocate managed values, suspend, call dynamic functions, or use
unproved storage. Native workgroup and tensor facilities require the native GPU
provider selected by the built target.

## Native GPU costs

These records come from the WGPU provider, which the VM does not have yet. Use
a caller-named JSONL file to collect native GPU costs:

```bash
nupp run --gpu-costs frame-costs.jsonl src/main.nupp
nupp bench --gpu-costs build/gpu-costs
```

`run` selects one file. `bench` creates a unique run directory with separate
files for each case, variant, fork, and comparison executable. Native hosts can
set `NUPP_GPU_COSTS` to a unique path before starting the process. The runtime
helper `nupp.runtime.provider.nativegpu.costsOutput(path)` selects an output;
passing `nil` restores the environment default, which is truncated only the
first time the process opens it and appended to when restored. `sequence` runs
on across every output a process writes. A failed write never fails the GPU
work it describes: the next call that can fail cleanly reports it, and
`costsOutput` reports it while still switching to the new output.

Each line is a JSON object with `schemaVersion: 1`, `processId`, `sequence`,
`context`, `target: "gpu"`, and `operation`. Records distinguish adapter/device
setup, pipeline creation, buffer allocation, upload, dispatch, synchronization,
readback, host copies, and cleanup. `hostMs` measures elapsed host API time.
`adapterDevice` splits that setup into `adapterMs` and `deviceMs`; pipeline
records carry `phase: "setup"`, and dispatches distinguish `first-use` from
`steady-state`.

When the adapter supports timestamp queries, `kernelExecution.gpuMs` measures
the compute pass on the device. Join it to `dispatch` by `context` and `dispatch`.
Queries are resolved at synchronization after the measured work completes,
preserving asynchronous dispatch and attributing counters to the current work.
Unsupported adapters report `gpuTiming: "unavailable"` and `gpuMs: null`;
equal or reversed device counters do the same, with `gpuTimingReason` explaining
the invalid interval. Records retain `gpuTicksBegin` and `gpuTicksEnd` as decimal
strings and `gpuTickPeriodNs` without losing integer precision. Host submission
time is never substituted for device time. Timestamp readback
reports its own `instrumentationHostMs`. Collection adds query resources and
JSON output work, so compare variants with the same instrumentation settings.
Host and GPU times can overlap and must not simply be summed.

A dispatch includes authored kernel `metadata` (`sourceFile`, `sourceLine`,
`artifactId`, parameter names), work-item and workgroup dimensions, binding
reuse, and read/write buffer versions. `kernelIdentity` and `bindBuffer` records
also connect kernel storage slots to buffer handles. This join identifies an
upload that occurred before its first binding. Buffer layout metadata retains
format, element width, shape, strides, offset, and count. Typed spans preserve
their bytes without format conversion, recorded explicitly as `conversion`.

Uploads advance a buffer version; each dispatch advances every writable buffer
once. Downloads retain the version captured when their copy was queued, even
if a later upload or dispatch changes the resident buffer before readback.
`downloadQueue` reports byte count and fresh staging allocation;
`downloadMapCopy` reports the staging-to-host copy, and `downloadHostCopy` the
copy into the caller's span. These records expose the existing two-copy path
and synchronization costs before any residency optimization is attempted.

::: seealso
- [annotations.md](../../../reference/annotations.md#built-in-annotations)
  for the exact `@aot` arguments
- [](nupp.gpu) for the generated binding and resident-buffer API
- [](nupp.gpu.layout) for layout functions
:::
