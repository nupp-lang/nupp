---
title: Fetch the stage-zero compiler from a published release
status: Implemented
created: 2026-09-05
---

## Summary

Stop committing the generated stage-zero compiler bundle to the repository.
Publish it as an asset of every tagged release, pin the release and the
bundle's SHA-256 in the tree beside the other provisioned sources, and have the
toolchain fetch and cache it the first time a checkout needs it. The compiler
sources are then written in the language of the pinned release rather than the
language of the current commit, which is the rule every fetched-bootstrap
compiler lives under and the one this proposal decides to accept.

How a checkout builds today, and how the fixpoint is verified, belong to the
[build documentation](../learn/projects/build.md).

## Goals

- A fresh checkout builds with nothing installed beyond what the toolchain
  script already provisions.
- The stage-zero bytes are authenticated by a digest committed in the tree, so
  moving them out of git does not weaken what a checkout trusts.
- One cached copy serves every worktree and every compiler pair on a machine,
  and an offline builder can supply it by hand the way it supplies every other
  pinned archive.
- The repository stops growing by the size of a compiler bundle each time the
  language changes.
- The self-hosting claim stays mechanically checkable.

## Non-goals

- Rewriting history to recover the space the committed bundles already occupy.
- Bootstrapping from anything other than a Nupp compiler: no hand-written
  interpreter, no C translation, no second implementation.
- Changing what a release is or how one is cut.
- Letting compiler sources use a language feature before a stage zero that
  understands it has been published.

## Motivation

The compiler is written in Nupp, so compiling it needs a Nupp compiler, and a
checkout has to get its first one from somewhere. The tree answers that today
with a generated bundle committed under `bootstrap/`: the whole compiler
lowered to one Lua file, with the standard-library declarations embedded, and a
fixpoint command that refuses to let it drift from what the current sources
produce.

That design has one property that is hard to give up and two costs that have
grown with the project. The property is that compiler sources may use a
language feature in the same commit that adds it: the commit refreshes the
bundle, and the refreshed bundle is what the next checkout starts from. The
first cost is size. The bundle is about twelve megabytes, it has been refreshed
in roughly a quarter of all commits, and each refresh is a new blob in the pack,
so the history of one generated file is most of what a clone downloads. The
second cost is that the fixpoint's staleness check makes every language change
a two-step commit in practice, and a forgotten refresh is the most common way
for a fresh checkout to fail to build.

The obvious answers do not work. Shrinking the bundle by compressing it or
splitting it does not change its rate of change, which is what the history
pays for. Committing only occasionally leaves stretches of history no checkout
can build. Git LFS moves the blobs but keeps every other property, and adds a
dependency on a service to a clone that needs none today.

The answer other self-hosted compilers settled on is to start from a previous
release. Rust downloads the beta named in its `stage0` file and holds the
compiler to what that beta can build. Go requires an installed previous
release. Kotlin, Scala, Swift, GHC and Nim all build against a published
earlier version of themselves. Zig and OCaml are the exceptions that commit a
stage-zero artifact, and both pay for it with a refresh step of the kind Nupp
has now. The fetched design is the common one because it turns the bootstrap
into an ordinary pinned dependency, and this tree already knows how to
provision those.

## Overview and specification

### The pin

The stage-zero compiler is one more record in the pinned-sources file the
toolchain reads, naming the release it comes from, the digest of the exact
bytes, and where to look first:

```sh
STAGE0_TAG=v0.0.2
STAGE0_SHA256=…
STAGE0_URL='https://github.com/…/releases/download/${STAGE0_TAG}/nupp-stage0-${STAGE0_TAG}.lua.gz'
```

The digest is what authenticates the bundle; the URL is advisory, and a mirror
or a directory of already-downloaded archives may stand in for it exactly as
they do for LuaJIT and LPeg. The pin is the only thing about the bootstrap that
lives in the tree.

### The asset

Every tagged release publishes the bundle the self-hosting target produces,
gzipped, as `nupp-stage0-<tag>.lua.gz`. It is the same artifact the tree
commits today: platform independent, needing only a LuaJIT at or above the
floor the pins already state, with the standard-library declarations embedded.
Release assets are immutable, which is what lets a digest committed once stay
valid.

Because the bundle is produced by the fixpoint-verified compiler of the tagged
commit, and the fixpoint is deterministic, the digest in the pin is
reproducible from the tag alone: anyone can rebuild the asset from source and
compare.

### Fetching and caching

The toolchain script gains a `stage0` component that fetches the asset,
verifies it against the pinned digest, decompresses it, and answers with the
path it was installed under. It lives in the machine-wide toolchain cache,
keyed by the digest rather than by the compiler-pair key, since the bundle does
not depend on which C compiler the machine has. Every worktree of a checkout
therefore shares one copy, and the worktree helper has nothing new to seed.

The existing offline controls apply unchanged: the offline variable refuses the
network and reports what file to supply, and the source-directory variable is
where to supply it.

### The launcher

The launcher asks the toolchain for the stage zero only on the path where it
has no built compiler to run and no built compiler that can rebuild the tree.
An ordinary command in a built tree never reaches that path and never pays a
network round trip or a digest check. `help` keeps working in a tree that has
never fetched anything, as it must today.

### The fixpoint

The fixpoint stops comparing anything against a tracked file, because the
pinned release is meant to differ from the current compiler. The claim becomes
the three-stage one: stage zero builds stage one, stage one builds stage two,
stage two builds stage three, and stages two and three must be byte identical.
The staleness check and the flag that refreshed the tracked bundle are
withdrawn with the file they served.

### The language rule

Everything stage zero compiles, which is the whole self-hosting target and so
the compiler, the standard library, and the runtime beneath it, must be
accepted by the pinned release. A language feature therefore reaches the
compiler's own sources in three steps: it lands, a release that carries it is
tagged and its stage-zero asset published, and the pin is bumped to that
release. Only after the bump may the compiler use it.

The bump is the new refresh step, and it is a one-line change reviewed like
any other pin. Nothing prevents tagging a release for no reason other than to
move the pin, and the release workflow is already cheap enough for that.

### Migration

1. Teach the release workflow to publish the stage-zero asset, and tag a
   release from a tree that still carries the committed bundle, so the first
   published stage zero is produced by the verified path.
2. Add the pin and the toolchain component, point the launcher at them, and
   reduce the fixpoint to the three-stage claim.
3. Delete `bootstrap/` in that same commit, with the tests, documentation, and
   CI steps that name it.

## Risks and assumptions

- **The compiler waits a release for its own features.** This is the bet. The
  bundle has been refreshed nine times in the two days since the first tag,
  and each of those would have been a wait or a release. The assumption is that
  most language work does not need to be used by the compiler immediately, and
  that the ones that do are worth a tag. If that proves wrong, the remedy is to
  publish the asset from every green trunk commit and pin a commit rather than
  a tag, which keeps this design and shortens the wait to one CI run.
- **The first build needs the network.** A fresh clone on a machine that has
  never built Nupp now reaches out once for the bundle, where it reached out
  for LuaJIT already. The offline path covers the case where that is not
  allowed.
- **A release could be cut whose compiler cannot build the next tree.** The
  pin can only move forward to a release that builds the current sources, and
  the CI job that builds the tree from the fetched stage zero is what proves
  each candidate. A bad release is skipped, not repaired.
- **Trusting trust.** The chain now starts from a downloaded binary rather
  than a committed one, but the committed one was itself generated, so nothing
  about what a reader can audit changes. The digest reproduces from the tag,
  which is more than the tracked file offered.
- **Release assets must stay immutable.** The digest depends on it. The
  workflow refuses to replace assets today, and this proposal makes that rule
  load-bearing.

## Alternatives considered

**Keep committing the bundle.** Keeps same-commit use of new features, and
keeps paying for it in clone size and in a refresh step that is forgotten
often enough to have a test for it. It is what Zig and OCaml do, and both
have the same refresh discipline this tree has been carrying.

**Commit the bundle less often.** Leaves stretches of history that no checkout
can build, and the fixpoint no longer has a single answer for what the tracked
file should be.

**Git LFS.** Moves the blobs off the clone but keeps every refresh, the
staleness check, and the two-step commit, while adding a service dependency to
the one thing in the tree that needed none.

**Publish from every trunk commit and pin a commit.** The same design with a
shorter wait: the trunk matrix uploads the bundle for each green commit and the
pin names a commit hash and digest. It was set aside for the first version
because a tag is a decision and a trunk commit is not, and because it makes
the pinned bootstrap depend on a rolling release that has to be pruned. It
remains the fallback if the release cadence turns out to be the wrong unit.

**A minimal seed compiler in another language.** A hand-maintained C or Lua
interpreter for a subset of Nupp, of the kind Nim's `csources` provides, would
bootstrap with no download at all. It is a second implementation to keep in
step with the first, and the language has not stopped moving.
