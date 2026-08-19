---
title: Worker threads
status: Implemented
created: 2026-08-19
---

## Summary

A worker is a fresh LuaJIT state on its own operating-system thread, connected
to its spawner by two bounded byte queues. Lua values never cross directly: the
sender validates and serializes, the receiver decodes a separate copy. The model
is closer to Web Workers than to shared-memory threads. The only provider is the
compiler-owned binary host, and other configurations are refused at build time
rather than degraded.

[Workers](../concepts/workers.md) documents the surface.

## Goals

- Give Nupp real parallelism without introducing shared mutable state to a
  language whose ownership model assumes single-threaded access.
- Keep worker code ordinary checked Nupp — a named module already in the
  payload.
- Fail loudly where the guarantees cannot be delivered.

## Non-goals

- A shared Lua heap, shared globals, registry, loaded modules, closures,
  userdata, or cdata pointers.
- Killing a worker at an arbitrary instruction.
- A concurrency capability in the ownership model. See
  [NEP 17](0017-ownership-capabilities.md).

## Motivation

### Shared memory would invalidate the ownership model

Every proof in [NEP 17](0017-ownership-capabilities.md) — one cleanup, no view
outliving its root, exclusive regions — assumes one thread of access. Sharing a
heap between threads means either extending the whole capability model with
isolation and synchronization, or having proofs that are silently false under
concurrency.

Isolated states with copied messages keep every existing proof true without
extending anything, which is why this is the shape rather than a compromise.

### The narrow provider is a refusal, not a limitation

The original proposal had two providers, including a sidecar loaded into an
arbitrary host interpreter. That was cut: a sidecar cannot reliably reserve
address space before the surrounding process maps its libraries, and embedding a
second LuaJIT raises symbol interposition and native-module identity questions.

The alternative to refusing it is shipping a worker that quietly runs
interpreted, or that initializes a different runtime than the one the program
was checked against. A build-time refusal is the better failure.

## Overview and specification

### Isolation is total, and communication is bytes

Nothing is shared. Messages and request/reply calls are the only path, and a
value crossing is validated, serialized, and decoded into a separate copy.

### The transferable vocabulary is deliberately small

Booleans, numbers, strings, and tables whose scalar keys and values recursively
use the same vocabulary. Functions, threads, userdata, cdata, metatables,
resources, non-scalar keys, deep nesting, cycles, and repeated table aliases are
rejected before encoding, and the diagnostic names the path to the first
rejected value.

**Repeated aliases are rejected along with cycles**, because the compatibility
contract does not promise graph identity. A later encoder may widen that only
with conformance tests across every supported runtime build. Accepting aliases
now would silently commit to preserving sharing, which is the kind of promise
that is discovered rather than decided.

Top-level absence is rejected because it is the closure sentinel.

### Stopping closes and joins

A worker is stopped by closing its inbox and joining, not by killing a thread at
an arbitrary instruction — which would abandon obligations mid-discharge and
leave native state in an unknown condition.

The cost is stated rather than hidden: an uncooperative worker can keep a join
or an automatic cleanup waiting forever.

## Risks and assumptions

- **An uncooperative worker hangs its parent, by design.** There is no timeout
  and no forced termination. That is the correct trade against killing a thread
  mid-discharge, and it means a buggy worker is a hang rather than a crash.
- **Copying is the cost model.** Large messages are large copies. Nothing in the
  design offers a way out, and a workload that needs shared buffers has no
  answer here.
- **One provider means one deployment shape.** Anything that is not the
  compiler-owned binary host cannot use workers at all.
- **The vocabulary will be asked to grow.** Each addition is a permanent
  compatibility commitment across every supported runtime build, and alias
  preservation in particular cannot be added quietly.

## Alternatives considered

**Shared-memory threads.** Rejected: every ownership proof assumes
single-threaded access, so sharing a heap means extending the capability model
with isolation and synchronization, or shipping proofs that are false under
concurrency.

**A sidecar provider** loaded into an arbitrary host interpreter. Designed, then
cut: address-space reservation is unreliable once the surrounding process has
mapped its libraries, and a second embedded runtime raises symbol interposition
and native-module identity questions. Refusing the configuration at build time
beats shipping a worker that quietly runs interpreted.

**Killing a worker on stop.** Rejected: it abandons obligations mid-discharge
and leaves native state unknown. Waiting forever on an uncooperative worker is
the lesser failure because it is visible.

**Transferring values by reference, or preserving aliasing.** Rejected: it
promises graph identity across an encoder boundary, which cannot be widened back
once anything depends on it.

**Adding an isolated-transfer capability to the ownership model** so values
could move between workers. Deliberately not done: it should arrive from a
demonstrated worker API rather than be designed pre-emptively into the base
model.

## FAQ

**Can a worker share a table with its spawner?** No. It receives a separate
copy.

**Can worker code be anything?** It is a named, checked module already present
in the target payload.

**What happens if a message contains something untransferable?** It is rejected
before encoding, with the path to the first offending value.

**Why can't I use workers outside the compiler-owned host?** Because the
guarantees cannot be delivered there, and the build says so rather than
degrading silently.
