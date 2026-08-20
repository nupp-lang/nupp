---
title: Coverage reports
status: Implemented
created: 2026-08-19
---

## Summary

A first-class coverage command runs a project in an instrumented build, merges
the data, and writes a portable static report. It is deliberately separate from
the test command. The report is source-first, presenting Nupp source as the
primary program with generated Lua as a synchronized secondary view.

[Testing](../guides/testing.md) documents the surface.

## Goals

- Report coverage against the source someone wrote, not the code that ran.
- Leave normal compilation byte-identical and effectively as fast.

## Non-goals

- Assuming the configured test command understands Nupp's test runner or
  coverage protocol.
- Replacing the line-attribution invariant with a source map.

## Motivation

### The test command runs an arbitrary program

The test command builds and launches whatever the manifest names. It is not
entitled to assume that program speaks Nupp's coverage protocol, so coverage
cannot be a flag on it without either constraining what a test command may be or
failing confusingly when it is something else.

### Coverage on generated code answers the wrong question

A report over generated Lua shows lowered forms, erased syntax, and constructs
the author never wrote. The question is which of *their* lines ran.

## Overview and specification

### Syntax

A command, not a flag on the test command:

```sh
nupp coverage
nupp coverage --output build/coverage
```

### Usage

```text
 File                     Lines    Functions   Branches
 ───────────────────────  ───────  ──────────  ────────
 src/app/models.nupp      94.2%    100.0%      81.0%
 src/app/parser.nupp      71.8%     85.7%      64.3%
```

The report presents Nupp source as the primary program, with the generated Lua
as a synchronized secondary view.

### Lowering

Instrumentation is a distinct generator mode selected once per module. With
coverage off, generation takes its ordinary path — it does not enumerate
coverage sites, allocate metadata, emit a runtime import, or add a per-node
conditional:

```lua
local function scale(point, factor)
   return {x = point.x * factor, y = point.y * factor}
end
```

With it on, sites are recorded against the module's coverage table:

```lua
local __cov = require("nupp.coverage").module("app.models", 7)

local function scale(point, factor)
   __cov[3] = __cov[3] + 1
   return {x = point.x * factor, y = point.y * factor}
end
```

Line attribution needs no map, because generation already emits code on the
source line it came from and never changes a module's line count. Coverage
metadata supplies what lines cannot — columns, functions, branch arms, lowered
forms, and erased syntax:

```json
{"module": "app.models", "sites": [{"id": 3, "line": 12, "col": 5, "kind": "function"}]}
```

### No source map is needed for lines

Code generation already emits code on the source line it came from and never
changes a module's line count ([NEP 26](0026-compiler-optimizations.md)), so
line attribution is free.

Coverage metadata is still needed for columns, functions, branch arms, lowered
forms, and erased syntax. It supplements the invariant rather than replacing it
— which is worth stating, because a system that carried its own map for
everything would make the invariant look optional.

### Instrumentation is a generator mode

With coverage off, generation takes its ordinary path: it does not enumerate
coverage sites, allocate metadata, emit a runtime import, or add a per-node
conditional.

## Risks and assumptions

- **Two generator modes must stay in step.** Anything added to ordinary
  generation has to be considered for the instrumented one, and a divergence
  shows up as coverage that does not match what ran.
- **The line-attribution invariant is now load-bearing in a second place.**
  Breaking it costs correct stack traces *and* coverage line mapping.
- **A static report is a build artifact with no server.** That makes it portable
  and means large projects produce large files.

## Alternatives considered

**A flag on the test command.** Rejected: that command runs an arbitrary
program, which cannot be assumed to speak the coverage protocol.

**Reporting over generated Lua.** Rejected: it answers which generated lines ran
rather than which authored lines did.

**Carrying a source map** rather than relying on line attribution. Rejected as
redundant for lines, and it would make the invariant appear optional.

**Instrumenting per node in ordinary builds**, gated at run time. Rejected:
ordinary compilation must stay byte-identical and as fast.
