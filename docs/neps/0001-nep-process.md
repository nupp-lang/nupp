---
title: Nupp Enhancement Proposal process
status: Active
created: 2026-08-19
---

## Summary

A Nupp Enhancement Proposal records one design decision: what was chosen, what
it looks like in source, what it lowers to, and why. Proposals are markdown
files in `docs/neps/`, published with the rest of the site and listed
automatically. Writing the file is the whole process.

## Goals

- Keep the reasoning behind a design findable after the code has moved on.
- Show the syntax and the lowering, so a reader can see what was decided.
- Cost about as much as writing one file.

## Non-goals

- Tracking implementation progress. The changelog and the documentation say what
  exists.
- Replacing user documentation. A proposal is not where someone learns to use a
  feature.

## Motivation

Documentation is rewritten whenever behaviour changes, and the reasoning goes
with it. Later, the constraint that forced an awkward-looking design is no longer
visible in the tree, and the obvious-looking simplification gets attempted a
second time.

Reasoning ages better than description. "A was chosen over B because B could not
express a borrowed result" stays true after A is replaced, which is what makes a
proposal worth keeping without maintaining it.

## Overview and specification

### File layout

One proposal is one file in `docs/neps/`, named `NNNN-short-slug.md` with a
four-digit number. Numbers are assigned in writing order, never reused, and
never renumbered. A proposal is published by existing; [NEP 0](index.md) is
generated from the files themselves and is where they link to each other.

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
its first `##`. Do not write an `#` heading, a number, or a status line into it.

### Statuses

```text
Draft                 Written down, not decided. Nothing has been built.
Accepted              Decided. Building it is expected; it may not exist yet.
Implemented           Decided and built.
Withdrawn             Decided against, or abandoned.
Superseded by NEP N   Replaced. Read N instead.
Active                A process proposal, such as this one.
```

`Draft` and `Accepted` describe things that do not exist yet.

### Sections

In this order, as `##` headings. A section with nothing to say is dropped, and
`FAQ` is optional.

```text
Summary                 What this decides, in a paragraph.
Goals                   What the design has to achieve.
Non-goals               What it deliberately does not attempt.
Motivation              The problem, and why the obvious answers do not work.
Overview and            The design: its syntax, its usage, its lowering, and
  specification         the rules it introduces.
Risks and assumptions   What this bets on, and what breaks if the bet is wrong.
Alternatives            The designs that lost, and why each one lost.
  considered
FAQ                     Optional. Only questions the rest of the proposal does
                        not already answer.
```

### Syntax, usage, and lowering

`Overview and specification` shows the feature rather than only describing it:

- **Syntax** — the construct as it is written, in a fenced `nupp` block.
- **Usage** — a short example of it being used.
- **Lowering** — the generated Lua, or the physical representation, wherever
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

A replaced design gets `Superseded by NEP N`, and N says what changed. A dropped
one gets `Withdrawn` and a sentence saying why. Delete a proposal only when it
records no decision at all.

## Risks and assumptions

- **A proposal can be mistaken for documentation.** It sits on the documentation
  site, and a `Draft` describing unbuilt syntax is the case that misleads. The
  status is the defence.
- **Bodies drift toward the code.** A body that needs updating to stay true was
  probably describing behaviour rather than reasoning.
- **This assumes one author.** Review, sponsorship, and objection handling are
  absent. A second author means revisiting this document.

## Alternatives considered

**Dated design records outside the site**, with a free-form status line. This is
what Nupp had. Those files described behaviour as well as reasoning, so they
went wrong when the code moved and nobody could tell which parts had.

**Commit messages.** Dated, attached to the change, and unable to drift — but a
decision usually spans many commits, and there is nowhere to put the
alternatives that were never committed.

**A "why" aside in the documentation.** Keeps one file per topic, and has
nowhere to put a rejected design, or the reasoning behind a replaced one whose
page has been rewritten.
