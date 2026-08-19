---
title: Gradual typing and the strictness floor
status: Implemented
created: 2026-08-19
---

## Summary

Nupp is a superset of LuaJIT's Lua: every valid LuaJIT program is already a
valid Nupp program, and stays one. How strictly a file is checked is decided by
what the file is named — `.lua`, `.g.nupp`, `.d.nupp`, or `.nupp` — rather than
by a project setting, a pragma, or a migration mode. The extension is not part
of the module's name, so tightening a file is a rename and nothing that requires
it changes.

## Goals

- Let an existing LuaJIT codebase adopt Nupp without a conversion step, a
  configuration file, or a flag day.
- Make the strictness of a file visible from the file, to anyone, without
  opening it or consulting anything else.
- Make tightening a file cheap enough that it happens, and reversible enough
  that starting is not a commitment.
- Keep one checker and one code generator. A gradual file and a strict file
  differ in what is *reported*, not in what is *understood* or *emitted*.

## Non-goals

- Soundness. The type system has deliberate holes, and they are written down
  rather than implied.
- A second dialect. There is no "Nupp mode" and "Lua mode" with different
  semantics; there is one language with one floor that some files stand on.
- Inferring strictness from content. A file is not promoted because it happens
  to be fully annotated, and not demoted because it is not.

## Motivation

Two failures make gradual type systems fail to be adopted, and they pull in
opposite directions.

### All-or-nothing switches stall

A project-wide strictness setting has one value. Turning it on means fixing
every file at once, which nobody schedules, so it stays off; and while it is
off, nothing enforces the parts already finished. The work is real but there is
no unit of it small enough to finish, so there is never a good week to start.

### Invisible strictness rots

Strictness declared inside the file — a `--!strict` comment, a pragma, a header
line — is invisible in a directory listing, in a review diff that does not
include the top of the file, and in a code search. It is copied by accident when
a file is duplicated and dropped by accident when a file is rewritten. Six
months later nobody knows which files are actually checked, and finding out
requires reading all of them.

### File names are already the unit

A file is the smallest thing a person edits, reviews, moves, and reasons about,
and its name is the one property every tool already shows. Putting the floor
there makes the unit of migration one file, makes the current state of a project
readable from `ls`, and makes tightening a file an operation version control
already understands.

## Overview and specification

### Four extensions

`.lua` is plain Lua, required and run unchanged, with the typed layer refused in
it. `.g.nupp` is the typed syntax with no floor underneath it. `.d.nupp`
declares an interface something else implements. `.nupp` is the typed syntax
held to the strict floor.

[Gradual typing](../concepts/strictness.md) documents what each one does.

### Strict adds exactly two rules

An unknown variable is an error rather than a global read, and an exported
declaration needs an annotation so nothing untyped crosses a module boundary.

That is the whole of the floor, and keeping it that small is deliberate. A floor
with a dozen rules is one nobody can hold in their head, which makes a rename an
open-ended amount of work and puts the decision back where this design was
trying to move it from. Two rules can be predicted before the rename happens.

### Extensions do not name modules

`models.g.nupp` and `models.nupp` are both the module `models`. `require`
resolves either, the `module` declaration does not change, and no dependent file
is touched when one becomes the other.

This is what makes the rename the migration. If tightening a file changed how it
was required, the cost of tightening would scale with the number of files that
depend on it, which is exactly backwards: the most depended-upon modules are the
ones most worth tightening.

### Refusal in `.lua` is an error, not silence

An annotation written into a `.lua` file reports `NUPP1006` rather than being
ignored. The extension has already settled that the file is Lua, so an
annotation there would govern nothing, and a construct that silently governs
nothing is worse than one that is refused.

### Erasure has two exceptions

Annotations, generics, interfaces, and affine policies erase. A `struct` remains
FFI cdata because its C layout is the feature being asked for, and `cdef`
declarations remain runtime bindings because they load native symbols.

The rule this follows: a construct survives to run time only when its runtime
representation is the reason someone wrote it. Nothing acquires a type registry
or a runtime checker.

### Holes are declared

Arrays are covariant, `as` is unchecked, `table` is gradual in both directions,
and a declared `is` edge is trusted rather than proved. Each buys compatibility
with how Lua is actually written, and each is documented as a hole rather than
described as a guarantee.

## Risks and assumptions

- **This assumes renaming is cheap.** It is cheap because version control tracks
  renames and module identity is unaffected. In a setting where either were
  false — a build system keyed on paths, a package format that publishes file
  names — the migration story would collapse and the floor would have to move
  somewhere else.
- **A project can sit in `.g.nupp` forever.** Nothing forces the second rename.
  `nupp check --strict` holds every file to the floor whatever it is called,
  which is what makes the remaining cost visible before it is paid, but it is a
  report and not a ratchet. If projects turn out to stall here, the answer is a
  manifest-level assertion about which directories must be strict — not moving
  the floor back into the file.
- **Four extensions is a surface to learn.** It is more than one and less than a
  configuration format. The bet is that the meaning of each is guessable and
  that a reader meets at most two of them in an ordinary project.
- **"Types erase" is a useful lie.** It is true of everything except `struct`
  and `cdef`, and those two are exactly where a reader is most likely to assume
  erasure and be wrong about memory. The exceptions are stated everywhere the
  rule is.

## Alternatives considered

**A project-wide strictness setting**, as `tsconfig`'s `strict` does. Rejected
for the reason in the motivation: one value for a whole project makes the unit
of migration the project. It also puts the answer to "is this file checked?" in
a different file, which a reader of the code does not have open.

**A pragma or comment inside the file**, as Luau's `--!strict` does. This gets
the granularity right — one file at a time — and was the closest competitor. It
was rejected because the marker is invisible where files are listed, reviewed,
and searched, and because it can be silently lost or silently copied. The file
name cannot be either.

**A separate strict dialect with its own semantics.** Rejected outright. The
superset property is the reason an existing codebase can start at all, and a
dialect that changes what a program means loses it on the first file.

**Inferring the floor from the file's content** — treat a fully annotated file
as strict automatically. Rejected: it makes the floor a consequence rather than
a decision, so adding one untyped local silently demotes a module, and no diff
shows it happening.

**Accepting annotations in `.lua` files as comments**, the way some tools attach
types to JavaScript. Rejected: it produces two ways to write the same thing with
different reach, and the comment form is the one that silently does nothing when
it is subtly malformed.

**Soundness.** Rejected as a goal, not as an accident. Every hole listed above
buys compatibility with idiomatic Lua, and closing them would produce a checker
that rejects programs that are correct and common. A sound checker for a
language people already have working code in is a checker they do not adopt.

## FAQ

**Why is the floor two rules rather than a level dial?** A dial makes the
question "which level is this file?" and a reader then has to know what each
level contains. Two rules make the question binary and the answer predictable.
More rules can be added as lints, which are independently configurable and do
not change what the floor means.

**Why not make `.nupp` the gradual one and require a marker for strict?** The
common case should be the short name, and the intended end state for a Nupp file
is strict. Making the plain extension the strict one also means a file created
by someone who has not read this document lands in the right place.

**What stops the strict floor from growing?** Nothing mechanical. The commitment
is that new checks arrive as lints unless they are genuinely about whether the
module boundary is typed, which is what the two existing rules are about.

**Does `.d.nupp` need to exist?** It is a declaration file with nothing to
implement, so the strict floor's second rule — exports need annotations — is
vacuous, and the first would reject the names it exists to declare. It is
gradual for that reason rather than as a convenience.
