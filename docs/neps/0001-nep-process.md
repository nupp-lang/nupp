---
title: Nupp Enhancement Proposal process
status: Active
created: 2026-08-19
---

## Summary

A Nupp Enhancement Proposal records one design decision: what was chosen, what
it looks like in source, what it lowers to, and why. Proposals are markdown
files in `docs/neps/`, published with the rest of the site and listed
automatically, so writing the file is the whole process.

## Goals

- Keep the reasoning behind a design findable after the code has moved on.
- Show the syntax and the lowering, so a reader can see what was decided.
- Cost about as much as writing one file.

## Non-goals

- Tracking implementation progress; the changelog and the documentation say
  what exists.
- Replacing user documentation. A proposal is not where someone learns to use a
  feature.

## Motivation

Documentation is rewritten whenever behavior changes and the reasoning goes with
it, so the constraint that forced an awkward-looking design stops being visible
and the obvious-looking simplification gets attempted a second time.

Reasoning ages better than description. "A was chosen over B because B could not
express a borrowed result" stays true after A is replaced, which is what makes a
proposal worth keeping without maintaining it.

## Overview and specification

### File layout

One proposal is one file in `docs/neps/`, named `NNNN-short-slug.md` and
numbered consecutively from this one with no gaps. A proposal is published by
existing, and the [index](index.md) is generated from the files themselves.

Removing a proposal closes the gap it would leave: its file is deleted and every
proposal after it is renumbered down. That costs what a number is for, since
earlier citations then point at a different proposal, links to the deleted file
resolve to nothing, and neither failure announces itself, so a removal is a
rewrite of every reference to every later proposal in the same commit.

### Frontmatter

```text
---
title: Qualified module namespaces
status: Implemented
created: 2026-08-18
---
```

`title` and `status` are required, `created` is expected, and any other
`key: value` line is rendered beside them.

The number, title, and status are generated into the page, so the body starts at
its first `##`: do not write an `#` heading, a number, or a status line into it.

### Statuses

- `Draft`: written down but not decided, and nothing has been built.
- `Accepted`: decided, and building it is expected even though it may not exist
  yet.
- `Implemented`: decided and built.
- `Withdrawn`: decided against, or abandoned.
- `Superseded by NEP N`: replaced, and NEP N says what replaced it.
- `Active`: a process proposal, such as this one.

`Draft` and `Accepted` describe things that do not exist yet.

### Sections

In this order, as `##` headings. A section with nothing to say is dropped, and
`FAQ` is optional.

- `Summary`: what this decides, in a paragraph.
- `Goals`: what the design has to achieve.
- `Non-goals`: what it deliberately does not attempt.
- `Motivation`: the problem, and why the obvious answers do not work.
- `Overview and specification`: the design, its syntax, its usage, its
  lowering, and the rules it introduces.
- `Risks and assumptions`: what this bets on, and what breaks if the bet is
  wrong.
- `Alternatives considered`: the designs that lost, and why each one lost.
- `FAQ`: optional, and only for questions the rest of the proposal does not
  already answer.

### Syntax, usage, and lowering

`Overview and specification` shows the feature rather than only describing it:

- **Syntax** is the construct as it is written, in a fenced `nupp` block.
- **Worked example** is a short program using the construct.
- **Lowering** is the generated Lua, or the physical representation, wherever
  lowering is part of what was decided. Where a construct erases entirely, say
  so.

Rules the documentation already owns do not need restating; link to the page
instead.

### Updating

Change the status when the decision changes, in the same commit as the code, and
leave the body alone. Editing a body is for a factual error about the past, or
for a dated section appended when a decision is revisited without being
replaced.

### Superseding and withdrawing

A replaced design gets `Superseded by NEP N`, and N says what changed; a dropped
one gets `Withdrawn` and a sentence saying why. Both keep their file and their
number, because both still record a decision.

Delete a proposal only when nothing is left for it to record, either because it
never held a decision or because the reasoning now lives on a documentation
page. See [File layout](#file-layout) for what deleting one costs.

## Risks and assumptions

- **A proposal can be mistaken for documentation.** A `Draft` describing unbuilt
  syntax, sitting on the documentation site, is the case that misleads, and the
  status is the defense.
- **Bodies drift toward the code.** A body that needs updating to stay true was
  probably describing behavior rather than reasoning.
- **This assumes one author.** Review, sponsorship, and objection handling are
  absent, so a second author means revisiting this document.

## Alternatives considered

**Dated design records outside the site**, with a free-form status line. This is
what Nupp had; those files described behavior as well as reasoning, so they went
wrong when the code moved and nobody could tell which parts had.

**Commit messages.** Dated, attached to the change, and unable to drift, but a
decision usually spans many commits and a commit message has nowhere to put the
alternatives that were never committed.

**A "why" aside in the documentation.** Keeps one file per topic, with nowhere
to put a rejected design or the reasoning behind a replaced one whose page has
been rewritten.
