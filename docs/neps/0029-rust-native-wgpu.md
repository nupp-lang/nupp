---
title: Rust-native WGPU provider
status: Implemented
created: 2026-08-31
---

## Summary

Native GPU compute uses the versioned Rust-native provider and WGPU. The
compiler emits one canonical SPIR-V module for native execution; WGPU owns its
translation to Metal, Vulkan, Direct3D 12, or GLES. Browser GPU execution keeps
its separate WGSL and WebGPU provider.

## Goals

- Put native GPU resource ownership and validation behind Rust APIs.
- Use one maintained native GPU abstraction on every supported platform.
- Keep AOT lowering, shader semantics, and generated bindings in Nupp.
- Ship one native shader artifact rather than a platform-specific derivative.
- Make adapter absence a hard failure in GPU conformance environments.
- Remove SDL and SPIRV-Cross from Nupp's build and runtime dependency graph.

## Non-goals

- Moving the Nupp compiler or AOT implementation into Rust.
- Sharing the native Rust provider with browser applications.
- Exposing WGPU handles, command encoders, or binding layouts to Nupp source.
- Preserving the SDL provider ABI or the `nupp aot --emit msl` inspection mode.
- Guaranteeing that every host or sandbox grants access to a physical GPU.

## Motivation

The SDL provider made Nupp own two shader artifacts, a C resource graph, a
separate shader translator, and SDL-specific provisioning solely to reach
compute devices. The compiler and generated binding already had a
backend-neutral boundary, while WGPU provided the missing safe resource model
and native backend selection.

Rust does not make GPU APIs infallible, but it lets the provider represent
contexts, buffers, kernels, bindings, pending downloads, and device loss without
exporting provider-owned pointers. The versioned C ABI carries opaque
generational handles instead. LuaJIT therefore sees a narrow status-and-copy
surface rather than SDL objects or WGPU lifetimes.

## Overview and specification

`@aot(target = "gpu")` continues to lower through Nupp's verified scalar IR.
For a native target the compiler emits SPIR-V and a generated typed binding.
The binding passes the bytes, entrypoint, buffer counts, uniform size, and
workgroup shape to `nupp_native_v2`. The Rust provider validates those values,
creates WGPU resources, and owns command submission and readback.

The host-visible adapter description comes from WGPU, so a macOS context may
report `metal: Apple M5 Pro` while Linux conformance reports its pinned Vulkan
adapter. Adapter enumeration is an operating-system capability; a sandbox that
denies Metal devices is adapterless even when the machine has a GPU.

Browser builds emit WGSL instead. Their generated artifact contains WGSL and an
entrypoint only, and execution remains in the browser WebGPU host rather than
loading the native Rust library.

The SDL implementation, feature flag, linker configuration, source pin, and
benchmark launch requirements are removed. SPIRV-Cross and the derived MSL
artifact are also removed. On Metal hosts WGPU performs the required translation
internally from the canonical SPIR-V.

## Risks and assumptions

- WGPU and its platform backends add Rust build time and binary size.
- GPU access can be denied by containers or application sandboxes. Ordinary
  unit tests may skip there, but conformance sets a strict requirement.
- Backend validation may reject SPIR-V accepted by the previous implementation;
  that is treated as a compiler/provider defect rather than a fallback to SDL.
- The versioned native ABI is intentionally allowed to break while this
  architecture is established.

## Alternatives considered

**Keep SDL as a fallback.** Rejected because it preserves two ownership models,
two build graphs, and two conformance targets precisely where the migration is
meant to establish one strategy.

**Emit Metal source directly.** Rejected because it makes Metal a second native
artifact and restores the platform fork that WGPU already owns.

**Move GPU AOT into Rust.** Rejected because the verified IR, ordinary CPU
meaning, and generated typed surface are language semantics and belong in Nupp.
