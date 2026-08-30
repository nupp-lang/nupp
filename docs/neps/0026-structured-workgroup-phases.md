---
title: Structured GPU workgroup phases
status: Draft
created: 2026-08-30
---

## Summary

GPU cooperation is expressed as a statically sized workgroup containing an
ordered sequence of phases. Every local invocation completes one phase before
any invocation begins the next. The boundary is a workgroup barrier on GPU and
a complete local-index loop on CPU.

Workgroup scratch is statically sized and fixed-width. A phase may write a
scratch array only at its own `localIndex`, which makes the writes structurally
disjoint. A later phase may read any in-bounds scratch element. Values that
cross a phase boundary live in scratch rather than in per-invocation locals.

This proposal does not admit a raw barrier intrinsic. Barriers are properties
of the phase tree, so the compiler can prove that every invocation reaches them
in the same order.

## Goals

- Express cooperative loads, fixed trees, and tiled kernels in ordinary Nupp.
- Give every GPU phase program one deterministic CPU meaning.
- Make barrier convergence structural rather than dataflow analysis.
- Prove scratch capacity, initialization, and write disjointness before IR.
- Keep the workgroup size and scratch footprint visible in the artifact.
- Preserve the bit-identical scalar operation sequence inside each lane.

## Non-goals

- Arbitrary barriers inside branches, loops, or helper calls.
- Atomics, unordered reductions, subgroup operations, or warp-size assumptions.
- Dynamically sized shared memory or backend-selected workgroup sizes.
- Values that remain private to one invocation across phase boundaries.
- Cooperative matrices or tolerance-based arithmetic.
- Inferring a workgroup transformation from an ordinary map kernel.

## Motivation

### A barrier intrinsic is not locally checkable

An ordinary `barrier()` call is correct only when every live invocation reaches
the same dynamic call. A branch on `localIndex`, an early return, or a loop with
lane-dependent trip count can deadlock a workgroup even though the call itself
looks harmless. Reconstructing convergence after general control-flow lowering
would make GPU admission a second control-flow verifier.

A phase boundary already says the stronger fact: all local indices execute the
preceding body, and only then may any execute the following body. The backend
does not have to infer where barriers are legal because the source never names
one.

### Shared writes need a cheap disjointness proof

Two invocations writing an arbitrary scratch index race. Requiring the left hand
side to be exactly `shared[localIndex]` gives every invocation one distinct
slot. Loads after the next phase boundary may index the initialized array using
ordinary proved fixed-width arithmetic, which is the useful asymmetric rule
for tiled loads and reduction trees.

### CPU order must be part of the operation

Running each GPU invocation to completion on CPU gives the wrong answer as soon
as one invocation consumes another invocation's scratch write. The CPU meaning
therefore follows the phase tree: execute phase one for local indices zero
through `size - 1`, then phase two for the same indices, and so on. This is a
specified schedule, not a simulator accident.

## Overview and specification

### Proposed source form

The exact names remain draft. The structural shape is the decision under
evaluation:

```nupp
local gpu = require("nupp.gpu")
local f32 = nupp.math.f32

@aot(target = "gpu")
local function tiled(
    exclusive c: span.WriteSpan<float>,
    borrows a: span.Span<float>,
    borrows b: span.Span<float>,
    columns: uint32,
    inner: uint32
): nil
    local groups = nupp.math.u32.div(nupp.math.u32.wrap(#c), 256)
    gpu.workgroups(groups, 256, function(groupIndex, phases)
        local aTile = phases:scratch(f32.narrow(0.0), 256)
        local bTile = phases:scratch(f32.narrow(0.0), 256)
        local accumulators = phases:scratch(f32.narrow(0.0), 256)

        for tile = 0, inner - 1 do
            phases:run(function(localIndex)
                aTile[localIndex] = loadA(groupIndex, localIndex, tile)
                bTile[localIndex] = loadB(groupIndex, localIndex, tile)
            end)
            phases:run(function(localIndex)
                accumulators[localIndex] = accumulate(
                    accumulators[localIndex], aTile, bTile, localIndex)
            end)
        end
        phases:run(function(localIndex)
            storeC(c, accumulators[localIndex], groupIndex, localIndex)
        end)
    end)
end
```

`workgroups`, `scratch`, and `run` are compiler-recognized forms with ordinary
library implementations. Their callbacks are immediate structural bodies, not
heap closures: they cannot escape, be stored, be selected dynamically, or be
called from another function.

The group count and workgroup size are `uint32`; the size is a compile-time
integer from 1 through the backend limit. A kernel has one size. Scratch length
is a positive compile-time integer, and its element is one admitted physical
scalar or struct layout. The total statically computed scratch footprint must
fit the portable limit chosen before this proposal can become Accepted.

### Uniform phase tree

The callback enclosing `phases:run` is the group controller. Its sequence of
phase calls may be repeated or selected only by control flow independent of
`localIndex`, scratch values, or lane-private loads. Group index and authored
uniforms are uniform and may control it. A return, break, or error cannot cross
a phase body.

Every `run` callback receives the zero-based `localIndex`. A scratch write is
admitted only when its target index is syntactically that value with no offset,
cast, alias, or equivalent arithmetic spelling. This intentionally chooses a
small proof over an optimizer trying to establish injectivity.

A scratch read must be in bounds and dominated by an earlier phase that writes
every slot. Conditional initialization is expressed by selecting the stored
value, not by conditionally skipping the store. A phase may read a scratch
array it also writes only at `localIndex`; cross-lane reads require a preceding
phase boundary.

### CPU meaning

For each `groupIndex` in increasing order, the ordinary implementation creates
fresh scratch storage and evaluates the group controller. Each `run(callback)`
invokes `callback(0)` through `callback(size - 1)` in increasing order before it
returns. Scratch persists until the controller returns and is then discarded.

This schedule defines results, including the order of any future fixed-tree
reduction. Implementations may execute groups in parallel only when the
existing span ownership and region proofs make their effects disjoint.

### Fixed-tree reductions

A reduction declares a power-of-two workgroup size and an identity value. Its
first phase writes one input or the identity to each scratch slot. Subsequent
phases use strides `size / 2`, `size / 4`, through `1`; local index `i` below
the stride writes exactly `combine(shared[i], shared[i + stride])` back to
`shared[i]`. The final value is slot zero after the last phase.

The combine operation is one admitted scalar operation with its authored
operand order. A larger reduction applies the same tree recursively to the
ordered group results. The CPU meaning runs those same stage loops in that
same order. There is deliberately no unordered, atomic, fast, or
backend-selected reduction family: each of those would lack one ordinary CPU
answer.

### GPU lowering

One source group becomes one GPU workgroup, and one callback evaluation becomes
one local invocation. Scratch arrays lower to Workgroup storage. Adjacent phase
bodies are separated by a workgroup execution-and-memory barrier; no barrier is
needed after the final phase.

The verified IR records the workgroup size, scratch declarations, and a nested
phase tree rather than raw branch instructions around barrier opcodes. SPIR-V
emits `OpControlBarrier` with Workgroup execution and memory scope and
AcquireRelease semantics for Workgroup memory. SPIRV-Cross derives the matching
Metal `threadgroup_barrier` call.

The dispatch count remains a host-validated compiler fact. For a tiled map it
is the complete output length and must equal `groupCount * workgroupSize`; later
operations may add a separate proved group-count rule rather than weakening
that equality silently.

### Tiled GEMM evidence

The isolated benchmark in `bench/sdl-gpu-spike/run-tiled-gemm.sh` implements the
phase tree directly in MSL while the source form is still undecided. A 16 by 16
workgroup cooperatively loads two 256-element tiles, crosses a barrier, performs
the same ordered `f32.fma` accumulation as the generated naive kernel, and
crosses another barrier before overwriting the tiles.

On the Apple M5 Pro, every element agreed exactly with the CPU AOT body and the
generated naive GPU kernel. A 512-cubed run measured 0.780 ms for the tiled
kernel versus 0.819 ms naive; a 1024-cubed run measured 4.581 ms tiled versus
4.416 ms naive. The mixed result is useful: the structure is expressible and
exact, but tiling is not itself a portable performance promise.

`bench/sdl-gpu-spike/run-fixed-tree-reduction.sh` validates the reduction
schedule independently. It applies the compiler-owned binary32 exponential to
65,536 values, reduces them through two 256-lane trees, and compares the Metal
result with a CPU stage interpreter after every operation has the same
binary32 meaning. The final bits agreed on the Apple M5 Pro; the two GPU levels
measured 178.375 microseconds, or 367.41 million input values per second.

## Risks and assumptions

- Immediate callbacks are a new recognized higher-order shape in AOT lowering.
  Diagnostics must point at the authored escape or nonuniform control, not at a
  verifier traceback.
- Requiring every cross-phase value in scratch increases shared-memory use. It
  buys a simple CPU meaning and prevents an implementation from depending on
  unspecified private-register lifetime across barriers.
- One-slot writes rule out cooperative vector stores and transposed conflict
  avoidance. Those need a separately proved injective indexing family.
- Workgroup memory limits differ by device. Acceptance needs a conservative
  portable floor or a checked device requirement in the generated spec.
- The Metal measurements do not predict Vulkan or other hardware. They validate
  exactness and feasibility, not a universal speedup.

## Alternatives considered

**A raw `barrier()` intrinsic.** Smaller surface and a global convergence proof
problem. It also has no natural ordinary CPU meaning when placed in a map body.

**Infer phases from adjacent loops.** Makes a seemingly local loop refactor
change synchronization and forces the compiler to distinguish an intentional
phase from ordinary sequential work. The phase call should be explicit.

**Allow arbitrary injective scratch indices.** Useful patterns exist, but proving
injectivity across wrapping integer arithmetic is substantially larger than the
feature. Exact `shared[localIndex]` writes establish the first sound subset.

**Expose only a tiled GEMM intrinsic.** Avoids the phase design and cannot serve
fixed trees, scans, stencil halos, or other cooperative kernels.

**Give CPU execution one invocation at a time.** Fast to implement and wrong:
the first invocation reads scratch before later invocations have produced it.
Stage-complete order is the semantics cooperation requires.
