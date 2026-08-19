---
title: Nupp Enhancement Proposal process
status: Active
created: 2026-08-19
---

## Summary

A Nupp Enhancement Proposal is a numbered document that records a design
decision and the reasoning behind it. Proposals live in `docs/neps/`, are
published with the rest of the site, and are listed automatically. Writing one
is the whole ceremony: there is no review board, no voting, and no template to
request.

## Goals

- Keep the reasoning behind a design where it can be found years later.
- Keep that reasoning out of the user documentation, which answers a different
  question.
- Make a proposal cost as little as writing a file.

## Non-goals

- Tracking implementation progress. A proposal is not a project plan, and its
  status says what was decided rather than how much has been built. The
  changelog and the documentation say what exists.
- Describing current behaviour. Every sentence a proposal spends on what the
  compiler does today is a sentence that will be wrong later and that the
  documentation already owns.
- Governance. There is one author. The process exists so the record survives,
  not so the decision is arbitrated.

## Motivation

Documentation answers *what* and *how*, and it is rewritten whenever those
change. That rewriting destroys *why*. A year later the constraint that forced
an awkward-looking design is gone from the tree, and the obvious-looking
simplification gets attempted a second time, fails for the original reason, and
costs the same week it cost before.

The reasoning also has a property documentation does not: it does not go stale.
"We chose A over B because B could not express a borrowed result" is a true
statement about a decision made on a date, and it stays true even after A is
replaced. That is what makes a proposal worth keeping unmaintained, and it is
why a proposal must not also try to be a description of the code.

## Overview and specification

### File layout

One proposal is one markdown file in `docs/neps/`, named
`NNNN-short-slug.md` with a four-digit zero-padded number. The padding sorts the
directory; readers see the number without it.

Numbers are assigned in the order proposals are written, are never reused, and
are never renumbered — a proposal's number is its name, and things link to it.

A proposal is published by existing. Nothing lists it in a manifest, and
[NEP 0](index.md) is generated from the files themselves.

### Frontmatter

Every proposal opens with a frontmatter block:

```text
---
title: Qualified module namespaces
status: Implemented
created: 2026-08-18
---
```

`title` and `status` are required; `created` is expected. Any other `key: value`
line is allowed and is rendered under the heading beside the rest.

The number, the title, and the status appear in the rendered page and in the
index without being written into the prose, so the body starts at its first
`##`. Do not write an `#` heading, a number, or a status line into the body.

### Statuses

```text
Draft                 Written down, not decided. Nothing has been built.
Accepted              Decided. Building it is expected; it may not exist yet.
Implemented           Decided and built. The documentation describes it.
Withdrawn             Decided against, or abandoned. Kept for the reasoning.
Superseded by NEP N   Replaced. Read N instead.
Active                A process proposal, such as this one, that stays current.
```

`Draft` and `Accepted` describe things that do not exist. Do not write code
against them, and do not describe them to a user as features.

### Required structure

A proposal carries these sections, in this order, as `##` headings. A section
with nothing to say is dropped rather than filled in.

```text
Summary                 What this decides, in a paragraph.
Goals                   What the design has to achieve.
Non-goals               What it deliberately does not attempt.
Motivation              The problem, and why the obvious answers do not work.
Overview and            The design itself, and the rules it introduces.
  specification
Risks and assumptions   What this bets on, and what breaks if the bet is wrong.
Alternatives            The designs that lost, and why each one lost.
  considered
FAQ                     The questions this will be asked, answered once.
```

Alternatives considered is the section that earns the file. A proposal without
it records a conclusion; one with it records a decision.

### Updating a proposal

Change the status line when the decision changes, in the same commit that
changes the code. Leave the body alone. The body is the record of what was
intended, and a body edited into agreement with the code is a worse copy of the
documentation.

Two things justify editing a body: a factual error about the past, and a new
section appended under a dated heading when the decision is revisited without
being replaced.

### Superseding and withdrawing

A design that is replaced gets `Superseded by NEP N`, and N explains what
changed. A design that is dropped gets `Withdrawn` and a sentence saying why —
that sentence is the reason the file stays. A proposal is deleted only when it
records nothing a reader would want, which in practice means it never recorded a
decision at all.

## Risks and assumptions

- **A proposal will be mistaken for documentation.** It is published on the
  documentation site, which invites exactly that. The status line and the
  non-goals above are the defence; a `Draft` proposal describing unbuilt syntax
  is the case that misleads.
- **Bodies will be quietly edited toward the code.** This is the failure that
  turned the previous `plans/` directory into a second, worse copy of `docs/`.
  If a body needs updating to stay true, that is evidence it was describing
  behaviour instead of reasoning, and the fix is to delete the passage rather
  than correct it.
- **This assumes one author.** Review, sponsorship, and objection handling are
  all absent. Adding a second author means revisiting this proposal, not
  ignoring it.

## Alternatives considered

**Keep `plans/` as it was.** Dated design records outside the site, with a
free-form status line. This is what Nupp did, and the failure was not the
format: it was that plans described behaviour, so they were wrong the moment the
code moved, and nobody could tell which parts had gone wrong without checking
every claim. Numbering them by write order also meant the directory had no
reading order at all.

**Record decisions in commit messages.** They are already dated, already
attached to the change, and cannot drift. But a decision is usually made across
many commits, a commit message is not discoverable by someone who does not
already know what to search for, and there is nowhere to put the alternatives
that were never committed.

**Record decisions in the documentation itself, in a "why" aside.** This keeps
one file per topic and is how many projects do it. It fails on the two hardest
cases: a design that was rejected has no documentation page to sit on, and a
design that was replaced loses its reasoning when its page is rewritten.

**Lightweight ADRs, one per decision, no required structure.** Cheaper to write
and they would have been an improvement. The structure is required anyway
because the sections that get skipped when they are optional — non-goals, and
alternatives considered — are the two that carry the reasoning. A proposal
without them is a summary of a conclusion.

## FAQ

**Do I need a proposal to change something?** No. Most changes decide nothing.
Write one when a future reader would otherwise ask "why is it like this?" and
have no way to find out.

**Can a proposal cover several features?** Yes, and it usually should. One
proposal per coherent design beats one per milestone; the milestones are what
the changelog is for.

**What if a proposal turns out to be wrong?** Its status changes and its body
stays. A wrong proposal that says it is withdrawn and why is more useful than no
proposal at all.

**Where does evidence go — benchmarks, measurements, acceptance runs?** Into the
proposal that the evidence supported, summarised, with the date. A measurement
is only ever true of the day it was taken, and a file that holds nothing else
has nothing to say a year later.

**Can I renumber to make the reading order better?** No. Order the reading with
links, not with numbers.
