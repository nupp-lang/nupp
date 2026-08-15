# Finite type-level computation results

This records the T4 acceptance decision for
[`type-level-computation.md`](021-type-level-computation.md). Measurements are from
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
- The T0--T5 language suite checks 22 cases in about 120 ms. The semantic-member
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
- With guarded recursion, reflection, associated types, comptime workers,
  materialization, and the then-current PEG bytecode backend enabled, the
  complete suite passed 1,523 tests in about 144 seconds. That backend has since
  been replaced by native LPeg; the entry records the 2026-08-10 acceptance run,
  not the current matcher architecture. `nupp fixpoint` also passed.

Reflection now serializes ordinary fields and indexers through the same member
view used by access, `keyof`, indexed lookup, and mapped shapes. Its descriptor
also carries const binders, const arguments, and exact C-array count terms.

The route alias now accepts as many literal segments as fit the recursive
budgets. It no longer has a written four-segment ceiling.

## Recursive gate result

T5 is admitted. Multi-segment route parsing and recursively nested container
normalization are two useful workloads finite aliases cannot express. The
four-segment route fixture is replaced by a structurally decreasing alias with
no written segment ceiling.

Hoisted aliases now carry stable per-check headers. A direct self-reference
beneath a match result becomes an `AliasCall`; unconditional and mutual
references report NUPP2133. Reduction detects an identical active canonical
application, memoizes completed applications, polls a cancellation control,
and enforces independent depth, step, allocation, result-member, and general
visit budgets. Failures include a bounded instantiated-alias trace.
