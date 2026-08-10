# Finite type-level computation results

This records the T4 acceptance decision for
[`type-level-computation.md`](type-level-computation.md). Measurements are from
the self-hosted compiler on the implementation worktree on 2026-08-10.

## Accepted workloads

The fixture in `tests/acceptance/typelevel/apis.g.nupp` ports two APIs that
previously require names to be repeated in parallel declarations:

1. `Events<T>` derives `nameChanged`-style callback members and their callback
   value types from the fields of `T`.
2. `RouteParameters<Path>` derives a handler parameter shape from a literal
   route. It is deliberately hand-unrolled to four path segments.

The event adapter removes both duplicated event names and duplicated callback
argument types. The route adapter removes duplicated parameter names between a
route literal and its handler input. Capability filtering/remapping provides a
third finite workload in the focused tests.

## Limits and latency

- One mapped shape or template product produces at most 256 members.
- One finite reduction visits at most 4096 nodes.
- The focused semantic-member suite checks 5 cases in about 4 ms.
- The T0--T3 language suite checks 19 cases in about 85 ms. The semantic-member
  suite checks 5 cases in about 4 ms.
- A self-host rebuild after changing the exported `Type` representation takes
  two compiler passes, about 14 seconds each on this machine. The following
  unchanged build completes in about 0.3 seconds.
- The existing two-module incremental fixture remains unchanged: a warm build
  checks 0 of 2 modules, a function-body edit checks 1 of 2, and an exported
  interface edit checks 2 of 2. Const values and binder-renaming canonicality
  have additional interface-fingerprint tests.
- A fresh CLI LSP inspection of the route handler parameter takes about 0.5
  seconds including process startup and renders the reduced type as
  `{readonly post: string, readonly user: string}`.
- After rebasing onto the landed reflection, associated-type, comptime-worker,
  materialization, and PEG bytecode work, the complete suite passes 1,532
  tests in about 117 seconds. `nupp fixpoint` also passes.

Reflection now serializes ordinary fields and indexers through the same member
view used by access, `keyof`, indexed lookup, and mapped shapes. Its descriptor
also carries const binders, const arguments, and exact C-array count terms.

The route floor accepts four segments. A fifth segment is intentionally outside
this alias and does not silently start recursive reduction; extending that
ceiling means adding another explicit finite layer.

## Recursive gate

Finite unrolling is sufficient for the two accepted APIs at their stated
ceilings. Multi-segment routes are the only demonstrated recursive workload;
the plan requires a second real workload before T5 may begin. Recursive aliases
therefore remain NUPP2115, and no `AliasCall` or recursive reducer budget is
implemented.
