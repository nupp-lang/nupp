# Formatter corpus

Golden pairs for `nupp fmt`. `<name>.nupp` is written the way somebody might
write it; `<name>.expected.nupp` is what the formatter is required to make of
it. `tests/fmtcorpustest.lua` runs every pair three ways: exact output,
formatting the golden again unchanged, and the same token sequence in and out.

The corpus sits outside the manifest's include roots, so `nupp fmt` and `nupp
check` never walk it. An input is free to be as badly written as the rule it
exercises needs, and none of these files has to type-check.

## Adding a case

Write the input under the category it belongs to, then record the golden:

```sh
NUPP_FMT_CORPUS_WRITE=1 ./tests/run fmtcorpustest
```

Then read what it recorded. The recording step asserts nothing: a golden nobody
read is a record of a bug as readily as of a rule. Commit both files together.

## Categories

```
 Directory         What it pins
 ────────────────  ─────────────────────────────────────────────────────────
 blank-lines       collapsing, stripping, and what a declaration is set off by
 calls             argument lists: when they spread, and what may hug
 comments          leading, trailing, comment-only, inside arms and tables
 istrings          templates, nesting, escapes, and what is never reflowed
 long-lines        where a line that does not fit is parted, and in what order
 pathological      CRLF, hashbang, unicode width, one-line programs, no break
 regressions       cases the fuzz found, minimized and checked in
 short-functions   `|x| ->`, `-> do`, and chains of them
 statements        guards, loops, goto, semicolons
 tables            nesting, mixed fields, separators, alignment doctrine
 typed             every annotation position, and cdef blocks left alone
```

`tests/fmtfuzztest.lua` covers the same claims on programs nobody wrote down,
and also proves that the lexer and parser reproduce both the input and the
formatted output byte for byte. It compares the parse trees before and after
formatting, too. When it finds a failure it prints the minimized, still-failing
program; that program belongs in `regressions/` as an ordinary case, so the
next run of the corpus proves it stays fixed whether or not the fuzz draws it
again.
