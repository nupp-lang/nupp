---
title: Annotated Lua interoperation and migration
status: Implemented
created: 2026-08-20
---

## Summary

Nupp always reads established Lua type annotations from every `.lua` source it
checks. Those comments refine the gradual types Nupp already infers, become the
typed surface seen through `require`, and remain ordinary comments at run time.
The reader accepts a common superset of LuaCATS, EmmyLua, and established LuaDoc
forms without requiring a project setting or source pragma. A malformed,
ambiguous, or unsupported type loses only the fact it could not establish,
falls back to `any`, and reports a warning rather than making valid Lua fail to
build.

One `nupp migrate` command turns an annotated `.lua` file into `.g.nupp`. The
input extension chooses the migrator, and an optional dialect flag resolves an
ambiguity rather than enabling annotation support. The language server and the
Visual Studio Code action use the same migration planner as the command.

## Goals

- Make the annotated Lua ecosystem a typed Nupp ecosystem boundary without
  requiring its authors or consumers to rewrite a library first.
- Improve a Lua module's inferred surface with the contracts its author already
  wrote, automatically and in every compiler entry point.
- Accept the common type and declaration vocabulary of LuaCATS, EmmyLua, and
  LuaDoc-style tools without asking a project to identify one dialect.
- Recover locally from annotation mistakes while making every lost fact
  visible as a warning.
- Provide one migration command and one implementation of migration for the
  command line, JSON automation, the language server, and Visual Studio Code.
- Preserve the runtime meaning, module name, comments, and source order of a
  migrated Lua file.

## Non-goals

- Reimplementing LuaLS, its diagnostics, completion ranking, or its whole
  project model.
- Making every annotation dialect agree where their semantics differ.
- Inferring Nupp ownership, borrowing, effects, fixed-width establishment, or
  sealed contracts from comments that do not state those facts.
- Turning a documented Lua class into a Nupp `record` or changing how its
  instances and metatables are built.
- Making a `.lua` file strict. It remains plain Lua with a gradual floor.
- Requiring an annotation marker, manifest key, pragma, plugin, or command
  before annotated Lua becomes typed.

## Motivation

### The ecosystem already wrote the missing facts

Lua libraries commonly carry parameter, return, class, field, alias, overload,
and generic information in comments. Nupp already parses the Lua source,
infers what it can from values and bodies, and publishes the returned value as
the type of `require`. The holes left at that boundary are often exactly the
facts sitting immediately above the declaration.

Ignoring them turns a large typed ecosystem back into `any` at the moment it
crosses into Nupp. Requiring a hand-written `.d.nupp` first preserves types only
after somebody duplicates the upstream API and accepts responsibility for
keeping the copy current. Reading the upstream contract makes ordinary Lua
libraries useful immediately and makes Nupp an integration point for the
existing ecosystem rather than an island beside it.

### Opt-in defeats an ecosystem boundary

A manifest switch makes the consumer discover, choose, and maintain a setting
for information already present in the source. A pragma asks upstream authors
to change a file before Nupp can use the annotations they already wrote. Both
split projects into ones whose comments mean something and ones whose identical
comments do not.

The `.lua` extension already says that the runtime language is Lua and the
checking floor is gradual. Reading a comment as a foreign type contract does
not add Nupp syntax to that file or make the file strict. It improves the facts
available to the same gradual checker, so it is always on.

### There is no single annotation dialect to select

LuaCATS descends from EmmyLua but has diverged from it, and LuaDoc-shaped tools
use some of the same tags for prose. Requiring a dialect setting makes the
common case harder and still fails in a repository containing generated
definitions, old files, and new files from different producers.

Most useful forms are either shared or distinguishable from their syntax. The
reader therefore recognizes one compatibility grammar, using dialect evidence
only where a spelling has more than one meaning. An explicit dialect remains a
migration aid for the genuinely ambiguous residue, not a condition of normal
checking.

### Bad comments must not make valid Lua unusable

An annotation is a claim about an implementation, not part of the Lua parser's
acceptance of that implementation. A typo in a type should not turn a module
that LuaJIT loads into a module Nupp cannot build, and dropping the whole
annotated surface because one return type is malformed throws away more truth
than the typo calls into question.

Recovery is therefore local. The failed type position becomes `any`, the rest
of the declaration and module continue to check, and a warning points at the
comment and says what was lost.

## Overview and specification

### Annotation ingestion is unconditional

Every Nupp operation that parses a `.lua` file also reads type-bearing comment
blocks: direct `check`, dependency checking during `build`, module resolution,
the incremental checker, documentation, and editor overlays. There is no
configuration key or source directive that disables or enables this pass.

The reader recognizes adjacent line-doc annotations and the corresponding
block-comment forms used by the supported families. Ordinary comments and
unknown documentary tags remain comments. A known type-bearing tag is parsed
even when the file contains no dialect marker.

For example, this remains valid Lua:

```lua
local M = {}

---@param path string
---@return string|nil contents
function M.read(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local contents = file:read("*a")
    file:close()
    return contents
end

return M
```

A Nupp consumer sees the declared boundary:

```nupp
const files = require("files")
local contents: string? = files.read("settings.json")
```

The declared parameter and result types seed the existing function checker.
Where a body is visible, its uses and returns are checked against them. The
module's ordinary inferred return shape then carries that signature to every
consumer. A declaration whose implementation cannot be followed remains a
trusted foreign claim, on the same terms as a `.d.nupp` declaration.

### Compatibility grammar

The reader covers the common semantic surface rather than selecting one parser
for a whole file. Its initial vocabulary includes:

- primitive, named, literal, union, optional, array, tuple, map, table-shape,
  function, variadic, and generic types;
- parameter, return, variable, alias, class, field, enum, generic, overload,
  operator, cast, and vararg declarations;
- class inheritance and field visibility where the source states them; and
- deprecation metadata.

Equivalent spellings normalize into one contract representation. For example,
`T[]` and the corresponding generic array form become a Nupp array, `fun` types
become Nupp function types, a nullable union becomes an optional when possible,
and an annotation enum becomes a literal union while its Lua table remains
untouched.

Tags whose foreign meaning has no Nupp contract do not invent one. In
particular, foreign diagnostic suppressions do not suppress Nupp diagnostics,
and `async`, `nodiscard`, version, source, and navigation metadata do not imply
Nupp effects or ownership. They remain available to documentation and editor
presentation where useful.

### Dialect detection and ambiguity

Recognition happens per annotation block, not once per project or file. A
dialect-specific tag or grammar production is evidence for that interpretation;
shared forms need no label. This permits old EmmyLua definitions, current
LuaCATS source, and generated metadata to coexist.

If every applicable interpretation produces the same contract, that contract
wins. If one interpretation parses and the others do not, the parsed one wins.
If two valid interpretations disagree about a type-bearing fact, the affected
fact becomes `any` and one warning lists the interpretations. The compiler does
not guess from installed editor extensions or a machine's LuaLS version.

An annotation block may provide stronger evidence for the blocks associated
with the same declaration, but it does not silently set a file-wide mode. That
keeps one stray legacy block from changing the meaning of everything below it.

### Recovery and warnings

Annotation diagnostics are non-fatal warnings. They are reported at the
smallest comment range that failed and are replayed from the incremental cache
like other diagnostics. Strict checking does not promote them to errors.

Recovery follows these rules:

- An invalid type expression becomes `any` only in that type position.
- An unknown named type becomes `any` at its use; other fields and signatures
  remain typed.
- An invalid member is omitted from its class or shape; valid members remain.
- A malformed overload is omitted; the primary signature and other overloads
  remain.
- Conflicting declarations keep a stable identity but expose `any` where the
  conflict prevents one contract from being chosen.
- An unknown non-type tag is retained as documentation and produces no warning.

Warnings cannot be disabled by selecting no dialect, because no such setting
exists. A warning must say which text was not understood, which fact became
gradual, and which supported spelling would establish it. This makes fallback
observable without turning comments into a second syntax gate for Lua.

### Classes are foreign contracts, not runtime declarations

An annotated class becomes a compiler-owned foreign interface. Its fields,
methods, inheritance, generics, and metamethod contracts participate in Nupp
checking, but the declaration emits no constructor, metatable, tag, or runtime
test. Structural interface semantics are the conservative default for a Lua
value whose construction convention Nupp did not create.

A class or alias used by a module's public annotations becomes a type-only
export of that module. Nupp source reaches it through the required module rather
than through a new ambient namespace:

```lua
---@class Client
---@field request fun(self: Client, path: string): string|nil

---@return Client
local function connect()
    return setmetatable({}, Client)
end

return { connect = connect }
```

```nupp
const http = require("http")
local client: http.Client = http.connect()
```

Unqualified names inside foreign annotations may resolve through the
compatibility index built from annotated Lua definitions in the same dependency
roots. That ambient compatibility namespace is visible only while interpreting
foreign annotations; it does not leak names into Nupp source. Conflicts in that
index recover under the warning rules above.

### Nupp semantics remain authoritative

Imported types enter Nupp's type algebra and obey Nupp's relations. A foreign
overload becomes a callable intersection, so Nupp still requires exactly one
entry to accept a call. A foreign class does not create nominal runtime identity.
A comment cannot establish an ownership transfer or complete effect summary
unless a future shared spelling states those exact semantics.

This can make a contract less expressive than it was in its originating tool,
but never gives the foreign dialect a second set of call, subtyping, ownership,
or narrowing rules inside Nupp.

### Explicit declarations remain authoritative

An adjacent or installed `.d.nupp` remains the authoritative Nupp contract for
the runtime Lua module. Inline annotations are still read so malformed comment
types are reported, but they do not overwrite ownership, effects, private
representation, or other facts in the explicit declaration. A disagreement
between an inline public fact and the declaration is a warning attached to the
inline annotation.

This is not an opt-out. The Lua annotations were consumed and compared; the
more expressive contract won by existing declaration precedence.

### One migration command

Migration has one command:

```text
nupp migrate [--check] [--json] [--dialect auto|luacats|emmy|luadoc] FILE...
```

The extension selects the migrator. A `.lua` input uses the annotated-Lua
migrator and becomes the same module at `.g.nupp`; future source-family
migrators add extensions rather than subcommands. An unsupported extension is
reported instead of being guessed from file contents.

`auto` is the default and uses the same compatibility grammar as ordinary
checking. `--dialect` resolves ambiguous foreign spellings for this migration;
it does not enable annotation ingestion, create a project setting, or affect
later `.lua` checks. `--check` prints diagnostics and the planned rename without
changing files. `--json` returns the same plan, warnings, and edits in structured
form.

Without `--check`, migration writes the complete destination, parses and checks
it as `.g.nupp`, and only then removes the source. It refuses to replace an
existing destination. Annotation recovery still writes the destination with
`any` in the lost positions and retains the original annotation text beside a
warning, so the migration is reviewable and can be tightened later.

The source transformation moves supported function, parameter, result, and
local types into Nupp syntax; emits erased aliases and interfaces for foreign
type declarations; preserves descriptive prose; and leaves runtime statements
in their original order. It does not turn a class into `record`, replace a
returned table with a declared module, or introduce `new`.

The result is `.g.nupp` because translation imports existing facts without
claiming that every exported value and global read is typed. `nupp check
--strict` answers whether the result is ready for the separate `.nupp` rename.

### Visual Studio Code action

The Visual Studio Code extension offers **Migrate annotated Lua to Nupp** on a
`.lua` document. It sends the unsaved text and selected dialect, when one is
chosen, to the language server's migration planner and applies the returned
create, edit, and rename operations as one workspace edit.

The action does not register the complete Nupp language service for every Lua
document. LuaLS may continue to own Lua completion, formatting, and semantic
highlighting. Nupp owns only this action and the warnings produced when the Lua
module participates in a Nupp project. Command-line and editor migration cannot
drift because neither contains a second translator.

### Lowering and caching

Annotation ingestion emits no Lua. A `.lua` file remains the runtime source,
and its comments remain comments. Only the compile-time module surface changes.

The normalized annotation contract contributes to the module interface
fingerprint. Changing prose alone may recheck the file but does not invalidate
consumers; changing a parameter, result, field, alias, or other public fact does.
Cross-file annotation declarations are keyed dependencies, so changing an
ambient foreign type invalidates only the modules whose annotations named it.

Migration lowers through the ordinary `.g.nupp` generator. Because every
inserted construct is erased, the generated Lua preserves the original runtime
program except for ordinary canonical formatting and existing Nupp lowering of
syntax the migrated file already chose to adopt.

## Risks and assumptions

- **A permissive compatibility grammar can accept a typo as another dialect.**
  Per-block evidence and disagreement warnings reduce the risk but cannot make
  overlapping grammars unambiguous.
- **Comments become API.** Changing what looked like documentation can now
  invalidate consumers or reveal an implementation mismatch. That is the point
  of type annotations, but some repositories will discover they were not
  maintaining them as contracts.
- **`any` recovery can hide a large damaged surface behind many successful
  checks.** The mandatory warning is the defense; tooling must not collapse all
  failures into one easy-to-miss summary.
- **The compatibility index broadens project discovery.** Large dependency
  trees may contain many annotated definitions. Header-only scanning,
  persistence, and keyed invalidation have to keep this cheaper than checking
  every Lua body.
- **Foreign class semantics are approximate.** Structural interfaces preserve
  useful fields and calls without inventing runtime identity, but code relying
  on a tool's nominal or exact-class behavior may be accepted differently.
- **Dialect evolution is external.** New upstream syntax must recover with a
  warning until supported; it must never turn into a fatal parser error.
- **Always-on behavior removes an escape hatch.** An annotation a project does
  not want interpreted must be made ordinary prose rather than disabled in
  configuration. This is deliberate so identical source has identical meaning
  in every Nupp project.

## Alternatives considered

**Require `luaAnnotations = "luacats"` in `nupp.lua`.** Rejected: a consumer
should not configure upstream source into having the meaning its author already
wrote, and mixed dependency trees do not have one honest project-wide value.

**Require a file pragma or `@meta` marker.** Rejected: most annotated source
does not carry a Nupp marker, so this turns ecosystem integration into an
upstream migration prerequisite.

**Choose one dialect and reject the rest.** Rejected: LuaCATS, EmmyLua, and
LuaDoc-shaped definitions overlap heavily, real repositories mix generations,
and the common semantic subset is much larger than the conflicting residue.

**Silently ignore malformed and unsupported annotations.** Rejected: once
comments contribute facts, silence makes a typo indistinguishable from a
working contract and lets a module become gradual without saying so.

**Make malformed annotations errors.** Rejected: the file remains valid Lua,
and one damaged comment must not prevent building or running the implementation.

**Generate `.d.nupp` files during every build.** Rejected: generated companions
duplicate a source-owned contract, create files that can go stale or be
committed accidentally, and make editor and build behavior depend on whether a
generation step has run. An explicit emitted declaration may be added as an
output mode later, but normal ingestion is in memory.

**Treat `@class` as `record`.** Rejected: `record` creates Nupp runtime and
metatable semantics that a comment did not establish. An erased foreign
interface takes the useful contract without rewriting the implementation.

**Use LuaLS as a compiler subprocess.** Rejected: it makes type checking depend
on an optional editor tool, its installed version and configuration, and a
second semantic engine whose answers Nupp cannot cache or reproduce itself.

**Attach the full Nupp language server to `.lua`.** Rejected: it competes with
the established Lua service for formatting, completion, diagnostics, and
semantic tokens when only migration and Nupp-boundary diagnostics are needed.

**Separate commands such as `migrate-lua`, `convert-emmy`, and
`promote-gradual`.** Rejected: the file extension already identifies the source
family, while dialect is occasionally evidence needed by one migrator rather
than a family of user-facing workflows.
