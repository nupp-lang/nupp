# Plans

These are dated design records, not documentation. A plan says what was
believed and why at the time it was written. It is not revised when the code
moves past it.

`docs/` is the authority on how Nupp behaves today. When a plan and a doc
disagree, the doc is right.

## Read the status line first

Every plan carries a `Status:` line immediately under its title, and that line
is the only part maintained after the plan is written. It says how much of the
plan is real, and names what diverged. The body below it may describe syntax
that was never built, or that was built differently.

Common states, none of them a fixed vocabulary:

- `implemented` — it landed. Qualifications after the word are the divergences
  that matter.
- `proposed` / `planned` — nothing below it exists yet. Do not write code
  against it and do not describe it to a user as a feature.
- `superseded by <plan>` — read the named plan instead.
- `historical` — kept for the reasoning, not the design.
- `evidence record` — measurements accurate on the date given, not after.

## Updating one

Change the status line in the same commit that changes the code, while you
still know what happened. Do not rewrite the body to match — the record of what
you originally intended is the reason the file is worth keeping, and a plan
edited into agreement with the code is just a worse copy of `docs/`.

Delete a plan whose design was rejected outright, or mark it `historical` with
the reason. A wrong plan kept without explanation is the one case that misleads
every reader.

## They are cited from source

Diagnostics carry `docs = "plans/…"` anchors that `nupp explain` prints, and
compiler and benchmark comments cite plans for their rationale. Renaming or
removing a file breaks those references, so check `grep -rn 'plans/' src bench
tests docs` before moving one.
