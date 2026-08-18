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

   Sentences, with a subject and a verb. "How a Nupp program becomes one file
   somebody can run." is a description of the page rather than a statement
   about the subject, and it leaves the reader exactly where the title did.
   Write what is true instead: "A distributed program is a stub with a payload
   appended to it."
3. **A code example inside the first screen.** Before any subheading. If a
   concept cannot be shown in fifteen lines, show the smallest useful part of
   it and layer the rest.
4. **Everything else**, in layers.

```markdown
# Owned resources

A file, a socket, a C allocation, or any other value produced by a function
returning `affine(T, cleanup)` carries a cleanup obligation the checker will not let you
drop.
An ordinary local discharges it at its scope boundary:

```nupp
local function slurp(path: string): string
    local file = files.open(path)
    return file:read("*a")
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
 Literal unions are enums
 Shared borrowing allows mutation
 Loops that cannot run
```

Never write a title that describes the writing instead of the subject.

**A title that opens with "What" is the common way to get this wrong**, and it
is banned whatever follows. It names the question the section answers rather
than the thing the section is about, so every one of them reads the same and
none of them says which is which. Name the subject:

| Banned | Write instead |
| --- | --- |
| What it provides | LSP features |
| What it does | Inlining |
| What is public | Public surface |
| What this costs | Cost |
| What narrows | Narrowing tests |
| What a struct field holds | Struct field types |
| What is inferred | Inference |
| What this does not do | Limits |

The same applies to a title naming the document rather than its subject:

| Banned | Write instead |
| --- | --- |
| Why it's this way | The reason: "One layout per struct" |
| `Overview` | Delete it; that is the intro |
| `Introduction` | Delete it; that is the intro |
| Usage / How to use | The task: "Writing a lint" |
| Advanced usage | The topic: "Type packs" |
| Notes / Miscellaneous | Split it or drop it |

A section that genuinely covers a boundary is titled for the boundary, as
"Limits", rather than for the negation, as "What it will not do".

**A title does not append a clause about itself.** "Signing, and what macOS
does about it" names its subject and then explains why the section exists,
which is the intro's job. Name the subject and stop.

| Banned | Write instead |
| --- | --- |
| Signing, and what macOS does about it | Signing for macOS |
| Strict floor, and which files hold it | Strict floor |
| Four declarations, and what each promises | Four declarations |

A title listing several subjects is not this. "Writes, shapes, and metatables"
enumerates what the section covers, and that is what a title is for.

**A title names its object.** "Configuring one" makes a reader scroll up to
find out what "one" was, and an outline of them says nothing at all. Name the
noun, as "Task configuration" or "Configuring a task".

| Banned | Write instead |
| --- | --- |
| Configuring one | Task configuration |
| Answering one | Answering a requirement |
| Choosing between them | Choosing a union kind |
| Annotations travel with it | Annotations travel with the descriptor |

**A title never opens with an article.** "The", "A" and "An" carry nothing and
push the identifying word off the front, which is where a reader scanning an
outline looks. This holds for a declarative title too: state the fact starting
from its subject, which usually means writing the subject plural.

| Banned | Write instead |
| --- | --- |
| The passes | Passes |
| The diagnostic index | Diagnostic index |
| A self-contained binary | Self-contained binary |
| The call is an intrinsic | Severity calls are intrinsics |
| A union of literals is an enum | Literal unions are enums |
| A wait parks one coroutine | Waits park one coroutine |
| The checker tracks it | Suspension propagates through calls |

**A title never ends with "is" or "are".** A trailing copula stops one word
short of the answer, so the title poses the question and withholds the thing it
is about. Name the subject as a noun phrase, or finish the sentence and state
the fact.

| Banned | Write instead |
| --- | --- |
| Asking what a name is | Querying a name |
| Where the strict floor is | Strict floor |
| Where the escape hatches are | Escape hatches |
| How fast an intrinsic call is | Intrinsic call cost |

Sentence case. No trailing colons or question marks outside an FAQ. A page may
end with `## FAQ` when several recurring questions need short answers before
the reader enters the complete reference. Each entry is an H3 containing one
full question and ending in a question mark. Outside that section, a question
as a heading is a fact the page has not committed to yet. Stop at H5; reaching
H6 usually means the page should split.

## Openings

A section opens with a sentence, not with a list. A reader arriving at a
heading needs to know what the list is a list of before the first item means
anything, and one sentence is usually the whole cost.

`## Diagnostics` and `## Next` are the exceptions, because the guide already
fixes their shape: one is the codes a page's rules produce and the other is two
or three links, and neither wants a sentence saying so on every page.

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

An example is the page's evidence, so it is held to the same standard as
the prose around it:

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
  `-- file borrows its source here`.
- Show the error too. A page that teaches a rule shows one program that breaks
  it and the code that reports it.
- A `nupp` fence is highlighted text. Add `:playground` to make one editable and
  checked in the reader's browser, and keep that example a small, self-contained
  program so its diagnostics teach the intended rule.
- One playground per page is the usual number: the example a reader would try
  first, near the top, before the page starts building on itself. A fragment, a
  step in a sequence, the same program shown again, an example inside a code
  group or admonition — none of those earns an editor, and a line-numbered fence
  stays text whatever else it asks for.
- Use ` ```playground ` explicitly for an empty playground that should open on
  the example menu rather than a particular program.

## Cross-linking

Link generously. A page is a node, not a document.

- Link the first mention of any concept that has a page of its own, then use
  the bare term afterward on that page.
- Deep-link to the heading that answers the question, not the page top:
  `[rock dependencies](build.md#rock-dependencies)`.
- One page owns each concept; the rest link to it and state only what they
  need. `start/ownership.md` states the annotations a caller writes and links
  `ownership.md` for the model.
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

Markdown pipe tables. A table drawn with spaces inside a code fence is a
picture of a table: it cannot wrap, it cannot carry a link or a code span, and a
narrow screen scrolls it sideways rather than reflowing it.

```markdown
| Tag                  | Shape                                 |
| -------------------- | ------------------------------------- |
| `@param <name> <text>` | Named, by parameter                 |
| `@return <text>`     | Listed, one per occurrence, in order  |
```

The source columns do not have to line up. What matters is the rendered table,
so let a long cell be long rather than padding every other row to meet it.

Tables are for comparing several things across several axes, or for a closed
enumeration of surface syntax. Two columns of key to value is a list, not a
table. A table with one row is a sentence.

## Diagnostics sections

Any page that introduces rules the checker enforces ends with `## Diagnostics`:
the codes that page's rules produce, bolded, each with one line saying what
makes them fire.

```markdown
## Diagnostics

- **NUPP2201**: a struct field is not reifiable, or a struct nests a
  declaration.
- **NUPP2204** / **NUPP2205**: array-part problems.
```

Do not paste the full text of `nupp explain`. The page says which codes belong
to it; the command says everything else.

A page that does not introduce rules has no such section. `lints.md` and
`diagnostics.md` are about the diagnostic system itself, so a list of the codes
they mention would point at themselves, and a command reference showing
`nupp explain NUPP2119` is quoting a code rather than introducing one.

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

| Write | Not |
| --- | --- |
| The checker reports NUPP2112. | You may get an error. |
| A scope boundary releases it. | It should get released. |
| A struct lowers to FFI cdata. | Structs are basically C structs. |
| This is a compile error. | Unfortunately this won't work. |

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

The vocabulary is fixed so a reader meets one word per idea:

- American spelling: color, behavior, initialize.
- **"Spelling" means how something is written**, as in "the C library's
  spelling" or "`not` is Lua's word spelling of `!`". It is not a word for a
  way of doing something: `external = true` is not "a spelling for accept
  arbitrary behavior", it is a way to say it.
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
local function openSession(id: uint64): affine(Session, closeSession)
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

The rest is formatting, and none of it is negotiable per page:

- Hard-wrap prose at 80 columns. Do not reflow a paragraph you did not touch.
- One blank line between blocks, none at the top of a section.
- No em dashes. Restructure the sentence: split it in two, subordinate one
  clause to the other, or reorder it. Do not just swap the dash for a
  semicolon or colon in the same spot, and do not leave a fragment standing
  where the dash was.

  ```
   Not                                       Write
   ────────────────────────────────────────  ─────────────────────────────
   Two facts. `Drop` supplies cleanup,        `Drop` supplies cleanup;
   and `affine(T, cleanup)` carries the                 `affine(T, cleanup)` carries the
   obligation.                               obligation.
  ```
- Ordinary quotes, not curly, everywhere except inside prose already using
  them.
- Lists are parallel: all fragments or all sentences, all starting with the
  same part of speech. A run of semicolon-separated clauses closing with a
  period is fine when the items form one sentence, as in the ownership
  guarantees list.
- Relative links between pages, with the `.md` extension, as
  [ownership.md](ownership.md) does.

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

- Em dashes are still live in doc comments under `src/` and in CLI help text.
  The handwritten pages under `docs/` no longer carry any.

## Next

- [docs/tooling/doc.md](tooling/doc.md): the fences, admonitions, code groups,
  and tags this guide assumes.
- [docs/diagnostics.md](diagnostics.md): what a diagnostic carries, and the
  anchors pages link to.
