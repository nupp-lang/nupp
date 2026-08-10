# Documentation style

This is how Nupp's documentation is written: the handwritten pages under
`docs/`, the website content generated from them, the `---` doc comments in
`src/`, and CLI help text. It is prescriptive. When a rule and a habit
disagree, the rule wins and the page gets fixed.

The short version: name the thing, show it working, then layer in the rest.

## Page shape

Every page opens the same way.

1. **An H1 that names the subject.** A noun phrase, sentence case, no
   punctuation: `# Records and structs`, `# Explicit resource scopes`,
   `# Effect contracts`.
2. **One to three sentences of intro.** What it is, and why a reader would
   reach for it. Not history, not motivation, not a promise about later
   sections.
3. **A code example inside the first screen.** Before any subheading. If a
   concept cannot be shown in fifteen lines, show the smallest useful part of
   it and layer the rest.
4. **Everything else**, in layers.

```markdown
# Explicit resource scopes

A file, a socket, a C allocation, or any other value produced by an `@owned`
function carries a cleanup obligation that the checker will not let you drop.
`with` is the construct that discharges it for you:

```nupp
with file = files.open("input.txt") do
    print(file:read("*a"))
end
```
```

A page owns one concept. If it needs two H1-sized ideas, it is two pages with a
link between them.

## Titles

Titles are short, and they are one of two kinds.

**Descriptive** is a noun phrase for the thing the section is about:

```
 Inlining
 Records
 Type mapping
 Suspension regions
 Diagnostics
```

**Declarative or imperative** is a sentence that states the fact the section
proves, when the fact is the point:

```
 Intrinsics live under `nupp`
 A union of literals is an enum
 Shared borrowing allows mutation
 Loops that cannot run
```

Never write a title that describes the writing instead of the subject. These
are banned outright:

```
 Banned                  Write instead
 ──────────────────────  ────────────────────────────────
 What it does            The behavior itself: "Inlining"
 What is X               X
 What X is not           The boundary: "Limits", or fold it into prose
 Why it's this way       The reason: "One layout per struct"
 Overview                Delete it; that is the intro
 Introduction            Delete it; that is the intro
 Usage / How to use      The task: "Writing one"
 Advanced usage          The topic: "Type packs"
 Notes / Miscellaneous   Split it or drop it
```

Sentence case. No trailing colons or question marks. A question as a heading
is a fact you have not committed to yet, so skip FAQ framing. Stop at H3;
reaching H4 usually means the page should split.

## Layering

Do not explain a concept completely and then illustrate it. Alternate.

> minimal example → the rule it demonstrates → one more detail → the example
> that needs it → the edge → the diagnostic that catches getting it wrong

Each example adds exactly one idea to the one before it, and each one is real
code that compiles. Keep the running example's names stable down the page so a
reader tracks the change, not the cast.

Order sections so a reader can stop early and still be correct. The common case
comes first, the escape hatch last. `unsafe do` is at the bottom of the
ownership page for a reason.

## Code examples

- Tag every fence: `nupp`, `lua`, `bash`, `c`, `json`.
- Show generated Lua when the lowering is the point, in a code group:

  ````markdown
  ::: code-group
  ```nupp [Nupp]
  local record Point x: number end
  ```

  ```lua [Generated Lua]
  const Point = {} Point.__index = Point
  ```
  :::
  ````

- Prefer a caption over a sentence introducing the block: ` ```lua [Generated
  Lua] `.
- Examples do not carry commentary in comments. Explain in prose above; use a
  comment only for something the prose cannot point at, like
  `-- file is borrowed<LuaFile> here`.
- Show the error too. A page that teaches a rule shows one program that breaks
  it and the code that reports it.
- Use ` ```playground ` when the reader should edit the example rather than
  read it. One per page at most, near the top.

## Cross-linking

Link generously. A page is a node, not a document.

- Link the first mention of any concept that has a page of its own, then use
  the bare term afterward on that page.
- Deep-link to the heading that answers the question, not the page top:
  `[rock dependencies](build.md#rock-dependencies)`.
- One page owns each concept; the rest link to it and state only what they
  need. `with.md` states what `with` does with a value and links `ownership.md`
  for the model.
- Say what is on the other end, as in `See [ownership.md](ownership.md) for
  the complete contract reference`. Never a bare "see here" or a naked URL.
- Diagnostic codes link to the reference anchor the compiler already emits, so
  a code in prose and a code in terminal output land in the same place.
- Doc comments in `src/` link the same way. A `---` block that names a concept
  links to its page; a module blurb links to the page that introduces the
  module's subject. Generated API pages are part of the site, not a separate
  world.
- End a page with what to read next when there is an obvious next step: a
  short `## Next` list of two or three links, each with a clause saying why.

## Tables

Space-aligned columns in a plain fence, one rule under the header, no outer
borders, no per-row separators, indented one space. Never Markdown pipe tables.

```
 Tag                        Shape
 ─────────────────────────  ──────────────────────────────────
 @param <name> <text>       Named, by parameter
 @return <text>             Listed, one per occurrence, in order
```

Tables are for comparing several things across several axes, or for a closed
enumeration of surface syntax. Two columns of key → value is a list, not a
table. A table with one row is a sentence.

## Diagnostics sections

Any page that introduces rules the checker enforces ends with `## Diagnostics`:
the codes that page's rules produce, bolded, each with one line saying what
makes them fire.

```markdown
## Diagnostics

- **NUPP2201** — a struct field is not reifiable, or a struct nests a
  declaration.
- **NUPP2204** / **NUPP2205** — array-part problems.
```

Do not paste the full text of `nupp explain`. The page says which codes belong
to it; the command says everything else.

## Admonitions

`::: note`, `info`, `tip`, `warning`, `danger`. Use them for exactly two jobs:

- **Scope, at the top of a page**, when a reader is likely to reach for a
  feature they do not need. The `@effects` note on [effects.md](effects.md)
  is the model.
- **A trap**, where the obvious reading is wrong and the consequence is
  silent.

Two per page is a lot. An admonition that restates the prose above it is
deleted, not retitled.

## Voice

Present tense, active, declarative. State what the tool does; the reader infers
the guarantee.

```
 Write                                    Not
 ───────────────────────────────────────  ──────────────────────────────────
 The checker reports NUPP2112.            You may get an error.
 `with` releases the resource on error.   `with` will try to release it.
 A struct lowers to FFI cdata.            Structs are basically C structs.
 This is a compile error.                 Unfortunately this won't work.
```

- **"You" for the reader, never "we".** There is no narrator, and the compiler
  is not a person the reader is in a room with.
- **No hedging** ("generally", "typically", "should usually") unless the
  imprecision is real, in which case name the condition instead.
- **No filler**: "simply", "just", "note that", "it is worth mentioning", "in
  order to", "basically". Cut the sentence or make it a claim.
- **No marketing.** "Powerful", "elegant", "blazing", "seamless" say nothing
  checkable. The comparison that earns its place is a specific one: what Lua
  gives you, what Nupp adds, what it costs.
- **Credit the prior art plainly** when a comparison helps, as in "which is
  the part Python's context managers and Java's try-with-resources do not
  have", and never as a dunk.
- **Own the limits in the same voice as the features.** "The model is
  intentionally smaller than Rust's" is a sentence about design, not an
  apology. Never apologize for the design, and never promise a future version
  will fix it outside a roadmap link.
- No emoji, no exclamation points, no rhetorical questions.

## Words

- American spelling: color, behavior, initialize.
- **The tools have names**: the checker, the compiler, the formatter, the
  language server, the documentation generator, the profiler. Commands are
  written as `nupp check`, in code style, without the leading `./bin/`.
- **The checker _reports_** a diagnostic. It does not throw, complain, warn
  about, or yell. Code _reports_ `NUPP2112`; a program does not "get" it.
- **Typed source _lowers to_** Lua or cdata. It does not compile to, generate,
  or emit anything; lowers to is the one verb, used consistently.
- **Types are _erased_** when they leave no runtime trace. `@effects` is
  type-erased; `struct` is not.
- **A resource is _dropped_, _transferred_, or _borrowed_.** It is not freed,
  released, or cleaned up unless describing C's side of the boundary.
- `.nupp`, `.g.nupp`, `.lua`, and `.d.nupp` are always written with their dot
  and in code style.
- Backtick every identifier, filename, extension, flag, and diagnostic code.
  Do not backtick an ordinary English word that happens to also be a keyword.

## Doc comments

The rules above apply inside `---` blocks, compressed.

```nupp
--- Opens a session against the account service.
---
--- The returned session is an owner: drop it early, transfer it, or bind it
--- for automatic lexical cleanup.
---
--- @param id the stable account identifier
--- @return the open session
--- @raises when the service refuses the connection
@owned(closeSession)
local function openSession(id: uint64): Session
```

- **First line: one sentence, third person, ending in a period.** "Opens a
  session against the account service." Not "Open a session" and not "This
  function opens".
- A blank `---` line, then any detail worth having at the call site. Keep it to
  what a reader needs with the signature in front of them; the concept belongs
  on a page, linked.
- Tag descriptions are lowercase fragments with no period: `@param id the
  stable account identifier`.
- `@raises` says what makes it raise, one line per condition.
- Module blurbs, the `--[[ ]]` block at the top of a file, open with what the
  module is for, in one sentence, and link the page that owns the concept.

## Mechanics

- Hard-wrap prose at 80 columns. Do not reflow a paragraph you did not touch.
- One blank line between blocks, none at the top of a section.
- No em dashes. Restructure the sentence: split it in two, subordinate one
  clause to the other, or reorder it. Do not just swap the dash for a
  semicolon or colon in the same spot, and do not leave a fragment standing
  where the dash was.

  ```
   Not                                       Write
   ────────────────────────────────────────  ─────────────────────────────
   Two annotations. `@drop` marks the        `@drop` marks the operation
   operation that consumes the resource,     that consumes the resource;
   and `@owned` marks the function that      `@owned` marks the function
   produces one.                             that produces one.
  ```
- Ordinary quotes, not curly, everywhere except inside prose already using
  them.
- Lists are parallel: all fragments or all sentences, all starting with the
  same part of speech. A run of semicolon-separated clauses closing with a
  period is fine when the items form one sentence, as in the ownership
  guarantees list.
- Relative links between pages, with the `.md` extension, as
  [with.md](with.md) does.

## Checklist

Before a page lands:

- The H1 names the subject, and no heading below it describes the writing.
- The intro is three sentences or fewer and a code example is visible without
  scrolling.
- Every example compiles, and each adds one idea to the one before it.
- Every concept with a page of its own is linked on first mention, by heading
  where a heading answers it.
- Rules the checker enforces are listed under `## Diagnostics`.
- Tables are space-aligned fences; two-column key → value is a list.
- No "we", no filler, no marketing adjective, no hedge that hides a condition.
- Prose wraps at 80 columns and untouched paragraphs are unreflowed.

## Known deviations

These predate the guide and are the standing fix list. Correct them when the
page is next edited, rather than in one sweep.

- `ownership.md` renders its ownership syntax surface as a Markdown pipe table.
- Spelling is split: 17 `behavior` to 11 `behaviour`, 19 `color` to 3
  `colour`, 11 `initialize` to 1 `initialise`. American spelling wins.
- Banned headings are still live: "What developers gain", "What is public",
  "What this costs", "What is inferred", "What a struct field may hold", and
  "What Nupp is".
- Em dashes are still live throughout the handwritten pages, doc comments, and
  CLI help text; only this guide and `ownership.md`'s "Declaring a resource"
  section have been brought into line with the no-em-dash rule.

## Next

- [docs/tooling/doc.md](tooling/doc.md): the fences, admonitions, code groups,
  and tags this guide assumes.
- [docs/diagnostics.md](diagnostics.md): what a diagnostic carries, and the
  anchors pages link to.
