---
title: Project templates
status: Implemented
created: 2026-08-19
---

## Summary

One command turns a template into a working project. A template is a directory
tree with one file at its root describing its variables and nothing else — the
same format whether it is built in, a local directory, or a remote repository.
Where the tree came from is resolved before scaffolding starts and forgotten
afterwards.

[The CLI reference](../reference/cli.md) documents the surface.

## Goals

- One template format and one code path, regardless of origin.
- Scaffold a project that needs no new build features to describe itself.

## Non-goals

- Template-specific build capabilities.

## Motivation

### A template configures a project, not a file list

Everything a scaffolded project needs to describe itself — a binary target, a
native dependency, a non-default host stub, resources, tasks — is already a
manifest field. So the template mechanism needs no new build features: a
template that wants a graphics host gets one by writing the manifest that asks
for it.

That is the test the design has to pass. If bootstrapping a real application
required a template feature, it would mean the manifest could not express
something a project needs, and the right fix would be in the manifest.

### Three origins, one format

Built-in, local, and remote templates being the same tree means there is nothing
to learn per origin, and a template can move between them without changing.

## Risks and assumptions

- **Remote templates execute someone else's manifest.** Scaffolding produces a
  project whose build configuration came from a fetched tree, and the trust
  model for that is the ordinary one for running fetched code.
- **The no-new-features test holds only while it is applied.** The first
  template requirement answered by a template-specific feature ends the
  property.
- **Variables in one file is a deliberate floor.** Anything more expressive
  becomes a templating language, which is a much larger surface.

## Alternatives considered

**Template-specific build capabilities.** Rejected: a template that needs one is
evidence of a gap in the manifest, and filling it in the template mechanism
hides that.

**Separate formats for built-in and external templates.** Rejected: two code
paths for one concept, and templates that cannot move between origins.

**A general templating language.** Rejected as scope: variables plus a tree
covers scaffolding, and everything beyond it is a program.

## FAQ

**Can a template ask for a graphics host?** Yes, by writing the manifest that
asks for one. No template feature is involved.

**Does a remote template differ from a local one?** Only in where it came from,
which is resolved before scaffolding and not retained.
