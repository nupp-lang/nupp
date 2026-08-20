---
title: Cross-target binaries
status: Implemented
created: 2026-08-19
---

## Summary

One machine produces binaries for every supported platform by compiling a
target-specific payload and stamping it into a pinned, prebuilt stub for that
platform. Nupp does not claim that one local native toolchain can compile every
host from source. Platform and build-target identity are kept separate.

[Distribution](../reference/distribution.md) documents the surface.

## Goals

- Make cross-platform release builds an ordinary operation on one machine.
- Keep the claim honest about what is being cross-compiled.

## Non-goals

- Cross-compiling the native host from source.

## Motivation

### Why the host is not cross-compiled

The payload is Nupp's own artifact and is target-specific in ways Nupp knows
about. The host is a native program with a native toolchain, sysroots, and
platform SDKs behind it. Claiming to build both from one machine means owning
every one of those, and being wrong about them in ways that appear at run time.

Pinning a prebuilt stub per platform separates the part Nupp can do reliably
from the part it cannot.

## Overview and specification

### Syntax

A binary target names its platforms; the command line selects among them,
separately from naming the build target.

```lua
dist = {
   kind = "binary",
   entries = { "app.main" },
   platforms = { "x86_64-unknown-linux-gnu", "aarch64-apple-darwin" },
   output = "build/dist/app",
}
```

```sh
nupp build --target dist --platform aarch64-apple-darwin
nupp build --target dist --platform all
```

### Usage

One machine produces every configured platform's binary:

```text
build/dist/
├── app-x86_64-unknown-linux-gnu
├── app-aarch64-apple-darwin
└── app-x86_64-pc-windows-msvc.exe
```

### Lowering

Only the payload is produced locally. It is compiled for the target and stamped
into a pinned, prebuilt stub for that platform:

```text
 prebuilt stub (pinned, published)     target payload (compiled here)
 ────────────────────────────────      ──────────────────────────────
 native host executable            +   modules, resources, manifest
                                   ↓
                          one self-contained binary
```

The stub is the native host, with its own toolchain, sysroot, and SDK behind it;
Nupp never compiles it. A platform is supported when four things are true — a
published and retained stub, a known filename and executable suffix, a modelled
compile-time C layout, and passing stamping and execution conformance tests.

A layout model alone does not make a platform supported, which matters because
it is the cheapest of the four and the one that makes a platform look supported
from inside the compiler.

### Obligations for a supported platform

Adding a platform means publishing and retaining its stub, teaching the compiler
its filename and executable suffix, modelling its compile-time C layout, and
running the same stamping and execution conformance tests.

**A layout model by itself does not make a platform supported.** That is the
sentence that keeps the supported set honest: knowing how a target lays out
structs is the easiest of the four, and it is the one that makes a platform look
supported from inside the compiler.

### Platform is not a build target

A binary target names its platforms and the command line selects among them,
separately from naming which build target to build. Overloading one identity for
both would make "build this target for that platform" unexpressible.

## Risks and assumptions

- **Stubs must be published and retained forever.** A checkout that built a
  platform must keep being able to; a lost stub is a platform silently
  unsupported.
- **The supported set grows slowly by construction.** Four obligations per
  platform is deliberate friction, and it means genuine demand can go unmet.
- **Payload-only cross-compilation limits what can differ per platform.**
  Anything requiring a different host, rather than a different payload, is out
  of reach.

## Alternatives considered

**Cross-compiling the host from source** on the build machine. Rejected: it
means owning every target's native toolchain, sysroot, and SDK, and being wrong
about them in ways that surface at run time rather than at build time.

**Treating a platform as a build target.** Rejected: it makes building one
target for several platforms unexpressible.

**Declaring a platform supported once its layout is modelled.** Rejected
explicitly — it is the cheapest of the obligations and the one that creates a
false impression of support.
