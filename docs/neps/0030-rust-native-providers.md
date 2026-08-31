---
title: Rust-native provider strategy
status: Implemented
created: 2026-08-31
---

## Summary

Native operating-system and maintained-protocol integration belongs in
versioned Rust providers. Nupp continues to own language semantics, public
standard-library policy, suspension, ownership, AOT compilation, and portable
providers. LuaJIT remains the native execution runtime and the C ABI remains
the narrow boundary between it and Rust.

This supersedes the C-only toolchain strategy in NEP 17. The WGPU provider in
NEP 29 was the first production provider under this strategy; URI and HTTP are
the first standard-library migrations, and HTTP is the first asynchronous one.

## Goals

- Use Rust ownership and generational handles for native resources.
- Reuse maintained protocol and platform libraries instead of translating them
  into project-owned C state machines.
- Keep native tasks away from Lua threads and report bounded readiness through
  the owning Nupp runtime.
- Select provider crates by the exact native features a program reaches.
- Remove obsolete C sources and source-built dependencies as each complete
  facility migrates.

## Non-goals

- Moving the compiler, checker, generated bindings, or AOT emitters into Rust.
- Exposing Tokio, Reqwest, Rustls, WGPU, futures, or Rust object layouts to Nupp
  programs.
- Preserving provider ABIs or every feature when a smaller coherent contract is
  safer.
- Replacing LuaJIT or requiring application authors to write Rust.
- Keeping two production implementations of one migrated facility.

## Motivation

The C-only provider made Nupp directly own asynchronous resource graphs and the
provisioning of libuv, libcurl, mbedTLS, ada, SDL, and SPIRV-Cross. That reduced
the number of contributor toolchains, but transferred memory-safety,
cross-platform, protocol-update, and dependency-integration work into Nupp.

The compiler already selects native facilities precisely and exposes them
through checked Nupp modules. A versioned ABI can keep that architecture while
letting Rust own unsafe operating-system edges and maintained native libraries.
The relevant unit of migration is a whole resource owner, not a C translation
unit: C and Rust never jointly own one request, socket, file, GPU context, or
Lua state.

## Overview and specification

The Rust workspace separates ABI primitives, shared runtime machinery,
platform facilities, and heavyweight providers. The facade builds as a
`cdylib` or `staticlib` with an explicit feature set. Cargo features mirror the
compiler's native feature closure so an HTTP program does not carry WGPU and a
GPU program does not carry HTTP or TLS.

LuaJIT sees fixed-width values, pointer-and-length borrows valid only for one
call, and opaque `uint64_t` generational handles. Rust validates the handle's
slot, generation, resource kind, owner, and state before using it. Provider
memory never crosses as a Rust object pointer.

Asynchronous providers use one process-wide Tokio executor. Tasks operate only
on Rust-owned state, enqueue bounded readiness, and wake a condition variable;
they never call Lua. The dynamically loaded provider pins its own image before
starting the executor so a Lua state cannot unload code while a task is still
running. Nupp decides when suspended coroutines resume and owns public policy.

URI parsing uses Rust's WHATWG `url` implementation. HTTP uses Reqwest with
Tokio for DNS, connection pooling, HTTP/1.1, HTTP/2, streaming, and
cancellation, and Rustls for HTTPS. Nupp retains request and response owner types,
redirect security policy, limits, and suspension behavior. URL text is copied
at the HTTP boundary rather than sharing ownership of a URI provider object.
Rustls is configured explicitly with `ring`; its bounded cryptographic C and
assembly is the HTTP provider's exception to the Rust-native dependency rule.
Nupp does not substitute a project-owned TLS or cryptographic implementation
merely to remove that reviewed security dependency.

## Risks and assumptions

- Rust crates increase clean build time, artifact size, and dependency count.
- Tokio and protocol crates must be configured with narrow feature sets or
  unrelated native facilities will leak into artifacts.
- Rustls still needs a cryptography provider. `ring` brings carefully bounded
  native and assembly code where no mature pure-Rust provider meets the
  security and portability bar.
- Provider shutdown, cancellation, and unload races require model and stress
  tests; Rust prevents many memory errors but does not prove the state machine.
- Reqwest behavior differs from libcurl around proxies, compression, and
  deadlines. Nupp specifies the accepted contract rather than promising curl
  compatibility.

## Alternatives considered

**Keep the C providers and update their dependencies.** Rejected because it
retains the duplicated ownership and portability work that motivated the
migration.

**Use Mio directly.** Rejected because Nupp would still own task scheduling,
DNS, timers, buffering, and most cancellation transitions, while Reqwest and
Hyper already use Tokio.

**Run Rust futures from Lua.** Rejected because it exposes executor semantics
to the language and risks entering Lua from foreign threads.

**Keep C as a fallback per facility.** Rejected after conformance because it
preserves two resource models and makes every future change satisfy both.
