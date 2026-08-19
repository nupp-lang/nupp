---
title: HTTP client
status: Implemented
created: 2026-08-19
---

## Summary

An optional HTTP module implemented by a feature-gated native provider. One
pooled client sends requests, returns as soon as final response headers are
available, and exposes the body as an owned progressive reader. The public call
is synchronous in shape and contextual in execution — the same suspension
contract the filesystem uses.

[The standard library](../concepts/standard-library.md) documents the surface.

## Goals

- Serve small requests and sustained streams as equally primary workloads.
- Own the typed API, resource lifetime, and native boundary while owning none of
  the HTTP semantics.

## Non-goals

- Implementing HTTP. Connection pooling, TLS, redirects, proxies, compression,
  and protocol versions belong to the transport library.
- Owning the host's event loop.

## Motivation

### The transport and the host have different owners

The transport library owns HTTP semantics. Nupp owns the stable typed API,
resource lifetime, bounded native boundary, and the suspension operation. A host
owns how a parked continuation runs again.

That three-way split means an application with its own event loop needs no
HTTP backend of its own, and Nupp needs no knowledge of that loop: transport
threads never enter the VM, the provider never calls the host, and the host
polls readiness sources from its own iteration. The same compiled module works
with no host at all, because the built-in suspension path calls the provider's
sleeping readiness wait instead.

### A generic reader is the right public type and the wrong internal one

The public response is a reader — read, read-into, transfer-to, close are the
operations a consumer needs. It is not sufficient as the only internal upload
path: a generic reader cannot say that its bytes are already contiguous, that it
is a native file, or that its storage may be borrowed for one call's duration.

## Overview and specification

### Performance commitments are part of the design

The provider will not route a string, buffer, or file through the generic reader
fallback; will not allocate a heap event for every body chunk; and will not make
a handled stream wait for one host frame per bounded queue window.

Writing these down as commitments rather than goals is what keeps the streaming
workload from being served by whatever the small-request path happened to need.

## Risks and assumptions

- **A large transport dependency.** Its behaviour on redirects, proxies, and
  protocol negotiation is now Nupp's observable behaviour, and changing it later
  is a compatibility event.
- **The three-way ownership split is only as good as the boundaries.** Transport
  threads must never enter the VM and the provider must never call into the
  host; both are invariants maintained by construction rather than checked.
- **Two internal upload paths.** The public reader plus specialized paths for
  contiguous, native-file, and borrowable storage is more surface than one path,
  and the fast paths are the ones with less coverage.

## Alternatives considered

**Implementing HTTP in Nupp.** Rejected: TLS, connection pooling, and protocol
versions are a large ongoing commitment with a well-served alternative.

**Requiring the host's event loop.** Rejected: it would make the module unusable
in a command-line program and tie it to one host's iteration model.

**Using the generic reader as the only internal upload path.** Rejected: it
cannot express contiguity, native file identity, or borrowable storage, so every
upload pays the generic cost.

**Returning only after the whole body arrives.** Rejected: it makes streaming
impossible and makes latency a function of body size.

## FAQ

**Does this need a scheduler?** No. Without one it blocks in the provider's
readiness wait.

**When does a request return?** As soon as final response headers are available;
the body is a progressive reader.

**Does Nupp call my application's event loop?** No. Your loop polls Nupp's
readiness sources.
