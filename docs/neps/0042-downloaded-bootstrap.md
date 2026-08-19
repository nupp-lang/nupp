---
title: Downloaded bootstrap compiler
status: Draft
created: 2026-08-19
---

## Summary

Stop committing a generated compiler. A fresh checkout would carry a small
stage-0 manifest pinning one previously released executable per supported host,
with its digest; the launcher downloads it on first use, verifies it, caches it,
and uses it only to compile the current compiler. The pinned version is never
inferred from "latest" or from mutable release metadata.

Nothing below exists. The tracked bundle is still committed.

## Goals

- Remove a large generated artifact from version control.
- Keep an old checkout building with the same compiler it always used.

## Non-goals

- Resolving the bootstrap version dynamically.

## Motivation

A committed generated compiler is a large binary-shaped file in every diff,
every clone, and every review. It is also refreshed by hand, which means it
tracks the tree only as well as someone remembers.

## Overview and specification

### The version is pinned, never resolved

Never "latest", never a branch name, never mutable release metadata. An old
checkout must keep selecting the same compiler after new versions are released,
or a historical build becomes unreproducible the moment something new ships.

### A stage-0 compatibility floor, and two-step feature landing

Everything needed to compile the compiler — syntax and semantics, manifest
fields, compile-time facilities, standard-library declarations, the build entry
point — must be understood by the pinned version.

So a new language feature lands in two steps: release a compiler implementing
the feature without using it in the compiler's own source, then advance the
stage-0 manifest to that release. Only then may compiler source use it.

This is the real cost of the design, and it is permanent. It is also the same
discipline a committed bundle imposes informally, made explicit.

## Risks and assumptions

- **A fresh build requires the network.** That is a new failure mode for
  environments that currently need none.
- **The two-step rule slows every language feature the compiler wants to use**,
  by one release.
- **Digest verification is the whole trust story.** The manifest pins a digest,
  and everything rests on that being checked before execution.
- **Retention becomes an obligation.** A released executable that stops being
  downloadable makes every checkout pinning it unbuildable.

## Alternatives considered

**Committing the generated compiler.** The status quo, and it works. It costs a
large generated artifact in the tree and a manual refresh step.

**Resolving the bootstrap version dynamically.** Rejected: an old checkout would
start selecting a newer compiler, so a historical build would stop being
reproducible.

**Building the bootstrap from source in the checkout.** Rejected as circular —
that is the problem being solved.

## FAQ

**Would a build need the network every time?** No — the verified executable is
cached after the first use.

**Why can't the compiler use a new language feature immediately?** Because the
pinned stage-0 compiler has to understand everything needed to compile it. That
is a release behind, by construction.
