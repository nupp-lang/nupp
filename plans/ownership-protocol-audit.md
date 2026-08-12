# Ownership protocol audit

Status: complete. This audit tests whether token-shaped protocols require a
general typestate feature after ownership hardening. They do not.

| Protocol shape | Checked representation | Remaining trusted fact |
| --- | --- | --- |
| open / close | `@owned(close)` result | the external producer is fresh and `close` is correct |
| begin / end | dependent owner returned `borrows` its parent | the bodyless begin/end declarations are truthful |
| map / unmap | mapped-range owner borrows the mapped object | the native mapping covers the declared bytes |
| reserve / commit | nominal write-range owner; consuming `commit` transition | commit's native semantics |
| register / unregister | pinned value with paired `retains` / `releases` | C stops retaining on release |
| acquire / submit / cancel | opaque owner consumed by either nominal transition | which terminal transition the application chooses |
| clone / release | explicit `@owned(release)` clone producer | clone really creates an independent reference |
| dynamic retirement | `resources.Set.adopt(value, terminal)` | the supplied terminal consumer is semantically correct |

The state is represented by possession of a nominal affine token. A consuming
transition destroys that token and may return a different nominal token. A
dependent token keeps its parent root live, and an explicit clone creates a new
obligation rather than copying one.

What ownership deliberately does not prove:

- value predicates such as authenticated, committed, or transaction-isolation
  level;
- that one of several legal terminal transitions is the business-correct one;
- protocol liveness or fairness; and
- semantic behavior of native implementations.

Those need ordinary validation or a separate typestate design. Adding them to
the ownership checker would weaken the useful theorem by conflating linear
resource accounting with arbitrary runtime state.
