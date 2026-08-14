# Ownership in the type, not above the signature

> **Status: implemented.** A result written `Owned<T>` inherits that type's
> `@drop` wherever a signature is built, `Owned<T, cleanup>` names a terminal,
> and `Owned<T, opaque>` says an owner is deliberately transfer-only. A `cdef`
> return says the same thing the same way, an `out` parameter writes
> `out p: Owned<T, cleanup>*`, and `Success<T, N>` or `Failure<T, N>` on the
> return says which C status means those outputs hold values.
>
> The C spelling differs from the sketch below: the `out` parameter keeps its
> physical pointer-to-pointer type and the wrapper sits on the slot, which leaves
> the ABI, the emitted prototype, and the borrowed-output spelling untouched.
>
> One gap remains. An ordered cleanup list has no spelling, and one terminal
> calling several operations is not equivalent to it, for the reason the rejected
> alternatives give; it waits on `nupp.cleanup.attemptAll`.

## Decision

An owning result is written where the result is, not above the signature.

```nupp
function m.open(path: string): Owned<LuaFile>
```

`@drop` says how a type ends; `Owned<T>` says which values are owners. They are
separate facts and both are needed: `io.stdout`, `io.stderr`, and `io.stdin` are
all `LuaFile`, none may be closed, and a producer of an owned one is what makes
the difference. Attaching cleanup to the type alone would close `stdout`.

`Owned`, `Borrowed`, and `Pinned` are capitalised. They name types, and a
constructor should read as the thing it builds.

## What this settles

**Any result may be owned.** The annotation could only ever mean the first,
because it sat above the signature with nowhere to name a position. The checker
read `j == 1`, and a cdef output had to be addressed by a string naming a
parameter. `(integer, Owned<Session>)` says it directly.

**A terminal is stated once, on the type.** Three producers of one resource
restated the same cleanup at each of them. `@drop` on a member, on a free
function, or on a cdef function registers it once, keyed off the signature's
first `takes` parameter, and every producer then says only that it produces an
owner.

**Only a type that declared a terminal supplies one.** A closure carries its own,
discharged through the capture it took. A C pointer has nowhere to write a
`@drop` and is too coarse to hold one anyway: `free(takes value: voidptr)` would
otherwise become the terminal for every `voidptr` in the project. Both keep the
contract the value arrives with.

## The C contract

A C contract needs three facts: which parameter is an owner, what discharges it,
and when the outputs are valid. Only the third is about the function rather than
the parameter, and it is about the *return value* — so it belongs on the return.

```nupp
cdef function make_pair(
    out first: Owned<nativeBuffer*>,
    seed: int32,
    out second: Owned<nativeBuffer*>
): Success<int32, 7>
```

`Success<T, const N: integer>` states the successful status once, in the one
place that can hold it. `success = always` is a bare `int32`.
`success = nonzero` has no single value and needs `Failure<T, const N>`.

This needs `cdef.nupp` to accept an ownership wrapper around a C type as still a
C type, and a wrapped `out` parameter as its own contract. Both currently report
NUPP2203 and NUPP2602.

## Rejected

**A cdef-only `cOwned`.** It would carry the C facts away from the general type,
but `success` is a relation between the return value and the outputs, so on a
parameter it addresses the contract remotely. Two out-parameters could still
disagree.

**Cleanups as const generic arguments**, `Owned<voidptr*, free>`. Const
parameters are already types, so this needs a singleton type per function
declaration. That is three problems, not one: the identity must be stable across
modules and incremental rechecks because it enters the type key; the const
parameter's domain would mention `T`, which is a dependent domain the
substitution path does not have; and resolving a cleanup name during *type*
resolution inverts a layer, since a type can resolve before the function it
names is declared. A string-named cleanup would stay inside the existing domain
if the C case ever needs one.

**Ordered cleanup lists**, a second terminal in `Owned<T, first, second>` -- the
syntax, not the
semantics. A wrapper that calls both in order is *not* equivalent: it stops where
the first raises, turning one failed cleanup into skipped obligations and leaking
whatever the later steps release. It would also make a composed terminal behave
unlike automatic destruction and unlike a resource set, both of which attempt
everything.

So the list goes and the behaviour stays, under `nupp.cleanup.attemptAll`:
operations run in declaration order, every one is attempted after a failure, the
first failure is the primary and later ones are reported as suppressed, and
`takes` is permitted only on the final operation -- which is today's rule. The
migration writes an ordinary terminal that calls it.

## Open

- Whether a terminal named in a type may be declared below the result that names
  it. A const function argument resolves where the type does, so `Owned<T, f>`
  needs `f` above it, where the retired annotation resolved lazily and did not.
  This is the layer inversion the rejected const-generic alternative describes,
  met from the other side.

- Whether an unresolvable terminal is an error or means opaque. `Owned<voidptr>`
  currently checks clean and behaves transfer-only, where a bare `Owned<T>` reports
  NUPP2602. Making it explicit costs a second constructor and keeps "there is
  deliberately no terminal" distinct from "I forgot one".
- Whether a second `@drop` registration for one type is an error. Registration is
  project-wide because `addDefaultDropOperation` mutates the shared nominal, so
  this is about diagnosing a conflict, not about choosing a scope. Module scoping
  is unsound: an owner's terminal cannot depend on the observer.
- Whether `Owned<T>` inherits a terminal inside any function type, or only in
  declaration results and callable fields. The wider answer resolves terminals
  during type resolution, where a `@drop` may not be registered yet, and makes
  `p: Owned<T>` a second spelling of `takes p: T`.
- `@borrowed(out = p, from = source)`: `borrows (source)` already names a root,
  so the parameter wants `out p: T borrows (source)`. `cdefparam` has no borrows
  suffix today.
