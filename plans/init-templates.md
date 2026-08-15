# Project templates and `nupp init`

> **Status: implemented, phases 1–4, with phase 5's fixture.** `nupp init`
> ships with the `app` and `lib` built-ins, directory and repository templates,
> and the step restriction; `nupp rock init` delegates to the same scaffolder.
> The fixture test proving a game-shaped manifest needs no new build fields is
> in `tests/templatetest.lua`. The Tecs template itself waits on Tecs moving to
> Nupp and belongs in that repository.
>
> Three things the implementation settled differently from the text below, each
> noted where it applies: built-in templates live in a top-level `templates/`
> rather than under `src`, the payload's `.git` pruning is by directory name
> rather than anything Git-aware, and the sandbox's instruction budget needs the
> JIT turned off for the chunk or it never fires.

## Decision

Nupp will grow one command that turns a template into a working project:

```
nupp init [TEMPLATE] [DIRECTORY]
```

A template is a directory tree with a `template.lua` at its root describing
its variables and nothing else. The same tree is what a built-in template is
authored as, what a local directory template is, and what a remote repository
holds, so there is one format and one code path; where the tree came from is
resolved before scaffolding starts and forgotten afterwards.

Three things follow from that and are the substance of this plan.

A template configures a project, not a file list. Everything a scaffolded
project needs to describe itself — a binary target, a Rust or C dependency, a
non-default host stub, resources, tasks — is already a `nupp.lua` field. The
template mechanism therefore needs no new build features, and a template that
wants a graphics host gets one by writing the manifest that asks for it. This
is the test the design has to pass, because bootstrapping a Tecs game is the
motivating case and Tecs is a Rust host with assets, not a `src/` directory.

Scaffolding is not execution. A template fetched from GitHub is somebody
else's code arriving on the machine, and the command that fetches it must not
be the command that runs it. `template.lua` is loaded as data in a sandbox
with no `io`, `os`, `package`, `require` or `load`; a remote template names
its resolved URL and commit and asks before writing; and no post-init step
that would load the scaffolded `nupp.lua` is honoured for a remote template,
because that file is ordinary unsandboxed Lua and running it is exactly the
thing being deferred. What the scaffolded project does when the user later
runs `nupp build` is the user's deliberate act, and this plan does not pretend
to have removed that — it only declines to perform it on their behalf.

Fetching is `git`, not HTTP. The released compiler has no HTTP/TLS provider —
`plans/cross-target-binaries.md` builds its whole acquisition story around
that — and `nupp.compiler.build.deps` already clones pinned git dependencies.
A template fetch is the same shell-out to the same tool, so `nupp init` adds
no new network surface to the compiler.

## Goals

1. `nupp init` with no arguments produces a project that checks, builds, tests
   and runs, with no further edits.
2. One template format, whether the tree is built in, on disk, or in a
   repository.
3. A built-in template travels inside a stamped single-file binary.
4. A built-in template's scaffolded output is held to the test suite, so a
   template cannot rot into a project that no longer checks.
5. A remote template is identified by resolved URL and commit before anything
   is written, and no code it supplied — in `template.lua` or in the
   `nupp.lua` it scaffolds — runs during `nupp init`.
6. Refuse to write outside the target directory, over an existing project, or
   through a symlink, whatever the template tree contains.
7. One scaffolder: `nupp rock init` becomes the `lib` template rather than a
   second copy of the same idea.
8. A template can express what a Tecs game needs without new manifest fields.

## Non-goals

- A general template language. Substitution is `${name}` over a closed
  variable set, and an undefined name is an error rather than an empty string.
- Running arbitrary commands from a template. There is no `hooks` field and
  there will not be one.
- Template provenance in the scaffolded project. `nupp init` prints the
  resolved source and commit; it writes no lock file, because a provenance
  record is only worth its clutter once `nupp init --update` exists to read
  it, and that command is not proposed here.
- A template registry, index, or short-name namespace beyond the built-ins.
  `owner/repo` is the namespace GitHub already has.
- Caching fetched templates. Scaffolding happens once per project; a cache
  would buy nothing and would raise the shared-directory ownership question
  the stub plan deliberately left closed.
- Updating or re-applying a template to an existing project.

## Current baseline

`nupp rock init <name> [directory]`, in `nupp.compiler.rock`, writes five
files from five Lua long strings, refuses a directory that exists, and stops.
The strings are formatted with `%q`-quoted names, the layout is fixed, and
nothing checks that the result compiles. It is the whole of the current
scaffolding surface and it is worth keeping only as a template.

Around it, the pieces this command needs already exist:

- `nupp.compiler.cli.spec` declares a grammar once and parses and documents
  from it; `nupp.compiler.cli` dispatches by name and answers `--help`,
  `--color` and `--schema` before a command sees anything.
- `nupp.compiler.bundled` shows how the compiler carries files it needs into a
  one-file bundle, as a preloaded module of path to source.
- `nupp.compiler.build.deps` clones a git dependency at an exact `rev` and is
  the precedent for shelling out to `git`.
- `nupp.compiler.build.manifest` validates a whole `nupp.lua` and names the
  path to whatever was wrong, so a template's generated manifest is checked by
  the ordinary build rather than by the scaffolder.
- `tests/clidoctest.lua` requires every command in the grammar to have a
  section in `docs/tooling/cli.md` whose blocks are the bytes the binary
  prints. A command added without documentation fails the suite.

## Command surface

```
nupp init [TEMPLATE] [DIRECTORY]
```

With no `TEMPLATE`, the built-in `app`. With no `DIRECTORY`, a directory named
for the project, which defaults to the basename of the template source and is
overridden by `--name`.

```
  --name NAME        Project name; defaults to the directory basename
  --set KEY=VALUE    Set a template variable; repeatable
  --from PATH        Use a template directory on disk
  --rev REV          Commit, tag or branch for a remote template
  --list             List built-in templates and exit
  --yes              Do not ask before writing a remote template
  --dry-run          Print what would be written and write nothing
  --json             Machine-readable result
  --schema           Print the JSON Schema of --json output
```

### Resolving `TEMPLATE`

The rule is lexical and never consults the filesystem, because a resolution
that changes meaning with what happens to be in the working directory is a
trap:

```
 Spelling                     Resolves to
 ───────────────────────────  ──────────────────────────────────────────
 app                          built-in template of that name
 ./x, ../x, /x, ~/x           directory on disk
 owner/repo                   https://github.com/owner/repo
 owner/repo@v1.2.0            the same, at that revision
 owner/repo/games/topdown     the games/topdown subdirectory of that repo
 https://…, git@…, git+ssh:…  used verbatim
```

`--from PATH` forces a directory and refuses any of the other spellings, for
the case where a local path is genuinely spelled like a GitHub name. A name
with no slash that matches no built-in is refused by name, with the built-in
list as the hint; it is never guessed at as a repository.

`@rev` and `--rev` are the same thing and giving both is refused, the way the
grammar already refuses `--json` alongside `--format`. With neither, the
remote's default branch is used and the commit it resolved to is printed.

### Result

On success `nupp init` prints the created directory, the resolved template
identity, and the first commands worth running. `--json` reports the same:
template source kind, resolved URL and commit where there was one, the
variable values used, and every path written, so a wrapper can tell what
landed without reading the tree.

## The template format

A template tree is ordinary files plus one `template.lua` at its root, which
is not copied:

```lua
return {
   description = "A Nupp application with a binary target",
   variables = {
      name = {
         pattern = "^[a-z0-9][a-z0-9_-]*$",
         invalid = "a project name must use lowercase letters, digits,"
            .. " hyphens, or underscores",
      },
      author = {description = "Author", default = "unknown"},
   },
   raw = {"assets/**"},
   after = {"git"},
}
```

`variables` is the closed set. Every variable is `required` or has a
`default`; a `--set` naming anything else is refused with the accepted names,
and a substitution referring to anything else is a template bug reported as
one.

A variable may also declare `pattern`, matched against the whole value, and
`invalid`, the message shown when it does not match. This is the same pair
`nupp.compiler.cli.spec` already gives an option, for the same reason: the
constraint and the sentence explaining it belong together, and neither is
derivable from the other. It exists because `lib` has to keep the constraint
`nupp.compiler.rock` enforces today — `^[a-z0-9][a-z0-9_-]*$` — and a
template that cannot say so would force that check back into the wrapper and
give up the one-format claim. `choices` is deliberately absent until a
template wants it.

Three names are always defined: `name`, `moduleName` (`name` with hyphens
turned to underscores), and `directory`. A template may declare `name` to
constrain it — that is what the example above does, and it is the only reason
to — but may not give it a `default`, since its value comes from `--name` or
the directory. `moduleName` and `directory` are derived and declaring either
is refused.

`raw` lists globs copied byte for byte, using the glob syntax
`nupp.compiler.build.syntax` already implements for manifests. Everything else
is substituted. `${name}` is replaced in file contents and in path components,
so `src/${moduleName}.nupp` becomes a file named for the project, and `$${` is
a literal `${`.

`after` is a closed set of post-init steps, checked when the template loads
rather than when it runs: `git` initializes a repository, `check` runs `nupp
check`, `build` runs the default target, `test` runs the suite. There is no
spelling for an arbitrary command. A step that fails leaves the project in
place and is reported; scaffolding succeeded and the step did not.

A step spawns the compiler in the scaffolded directory rather than doing the
work in this process, so a `nupp.lua` that calls `os.exit` ends its own run
instead of the command's. The executable is `nupp`, or `$NUPP` where an
installation is not on the path — which is also how the suite points a step at
the compiler it has just built.

**A remote template gets `git` and nothing else.** The other three are not
sandboxed and cannot be made so. `nupp.compiler.build.manifest.load` reads the
generated `nupp.lua` with `loadfile` and `pcall`, which is ordinary
unrestricted Lua with the whole standard library; `check` and `build` reach it,
and `nupp.compiler.build.project.test` additionally executes the `test.argv`
the same file names. So a template that could ask for `check` could execute
arbitrary code at scaffold time by writing it into the manifest it just
scaffolded, and the sandbox around `template.lua` would be theatre — the
attacker would simply put the payload one file over.

The rule is therefore about where the template came from, not what it asked
for:

```
 Source                     Steps honoured
 ─────────────────────────  ────────────────────────────────────────────
 built-in                   git, check, build, test
 --from a local directory   git, check, build, test
 remote (git URL)           git only
```

Built-in templates are this repository's own source, held to the suite. A
local directory is a tree the user already has and could have run anything
out of. A remote tree is neither, and the one step it keeps — `git init` in a
directory that was just created — runs no code the template supplied.

`--yes` does not lift this and there is no flag that does. A user who wants a
freshly fetched project checked can read it and then type `nupp check`, which
is the deliberate act the boundary exists to preserve. A remote template
naming `check`, `build` or `test` is not an error: the steps are dropped, and
the run says which ones and why, because the template author is probably not
an attacker and should learn the rule.

### Loading `template.lua` safely

Loaded with `loadstring` and `setfenv` — the idiom `nupp.compiler.LuaPattern`
already uses, except that its sandbox falls through to `_G` and this one does
not — into a table holding only what a data literal needs, with an
instruction-count hook that aborts a chunk which does not return promptly. No
`io`, `os`, `package`, `require`, `load`, `dofile` or `debug`. A
`template.lua` that reaches for any of them gets a nil index error and the
template is refused, which is the correct outcome: a template that needs to
compute is not a template.

**The budget needs `jit.off(chunk, true)` to work at all.** LuaJIT does not run
debug hooks from compiled code, so `while true do end` becomes a trace that
never checks the count and the command hangs instead of refusing. Turning the
JIT off for the chunk and everything it defines keeps it interpreted, which is
where the hook is honoured. This was found by the test for it hanging the
suite, which is the argument for writing that test.

The result is then validated the way `nupp.compiler.build.manifest` validates
a manifest — every message naming the path to what was wrong — because a
template author is as entitled to a good error as a project author.

### What the payload is

Every regular file at or under the template root, with `template.lua` and any
directory named `.git`, at any depth, pruned. Nothing else is excluded.

The `.git` rule has to be written down because both ways in produce one: a
`git clone` creates a repository store at the root, and `--from` pointed at a
repository checkout exposes the same directory. Copying it would put Git
internals in the scaffolded project and, worse, would make the phase 3
equivalence test compare two trees that differ by an object store.

Pruning is by directory name rather than by asking Git, and this is a
deliberate choice against `git ls-files`. Tracked-file enumeration is only
available for the remote path; a `--from` directory need not be a repository
at all. Defining the payload as a filesystem walk means both paths compute the
same set from the same rule, which is what makes "identical to `--from` on the
same tree" a test that can actually pass. A shallow clone has no untracked or
ignored files for the two definitions to disagree about anyway.

`nupp.compiler.fs.listFiles` takes a `skipDirectory` predicate for exactly
this and is where the pruning goes. It is not sufficient on its own: it
resolves a symbolic link to what it points at rather than reporting it as one,
which is documented behaviour its existing callers were written against and is
the opposite of what a refusal needs. Reading a template therefore uses a walk
that reports `entry.kind == "symlink"` without resolving it. Changing
`listFiles` is not an option — a source tree assembled out of links is
supposed to read as a copied one — so this is a second, stricter walker in
`nupp.compiler.template`, and the reason it exists belongs in a comment on it.

### Refusals during writing

Every one of these is checked against the resolved tree before a byte is
written, so a bad template fails with nothing on disk:

- a path escaping the target directory, by `..` or by being absolute;
- a symlink anywhere in the tree, reported as one by the walker above;
- a path component that is empty, `.`, or `..` after substitution;
- a file whose substituted path collides with another's;
- a target directory refused by the destination policy below.

### Destination policy

Two settings, because the two callers disagree and the disagreement is worth
keeping rather than splitting the scaffolder in half:

```
 Setting           Accepts                              Used by
 ────────────────  ───────────────────────────────────  ──────────
 absent            a path that does not exist           rock init
 emptyOrGitOnly    the above, plus an empty directory   init
                   or one holding only .git
```

`nupp init` takes the second because `mkdir my-game && cd my-game && git init
&& nupp init .` is how people actually start, and refusing it teaches nothing.
`nupp rock init` keeps the first, which is what `nupp.compiler.rock` enforces
today through its `pathExists` check, so its behaviour does not change under
this plan and `tests/rocktest.lua` keeps asserting the same refusal. One
parameter is not a second implementation; silently relaxing a published
command's contract as a side effect of refactoring it is a worse trade than
carrying the parameter.

## Built-in templates

Authored as real directories under a top-level `templates/<name>/`, so the test
suite scaffolds and checks them as ordinary source rather than as strings
nobody compiles. The build stages them as resources under the compiler's own
modules, where `nupp.compiler.bundled` reads them by one relative path whether
it is looking at a directory or at a stamped binary's payload — the mechanism
that already carries the compiler's declarations, which is why built-in
templates cost no new distribution machinery.

**Not under `src`, though that is where they belong by every other measure.**
A template's filenames carry the substitutions that make it a template, and
`src/${moduleName}.nupp` under an include root is a file the compiler tries to
compile and a module name nothing can require. The one place these cannot go
is beside the modules that read them.

That choice has a cost, and it is the reason `nupp.lua` names each template
file rather than globbing them. A string-glob resource derives its output from
the include roots; for a path outside them that means staging beside the build
rather than under the modules, and a resource landing there is dropped from a
bundle as unreachable. So the list is written by hand, and
`tests/templatetest.lua` holds it to the directory — a template file added
without a line in the manifest fails the suite rather than going quietly
missing from every released binary.

Enumerating a carried tree needs a counterpart to `bundled.source`, which
answers only about a path already known. `bundled.list(prefix)` is that: the
embedded table's keys under a prefix when there is one, and the same
leading-slash spellings from a directory walk when there is not.

Two ship in the first release.

`app` is the default: a `nupp.lua` with a `binary` target, a `src/main.nupp`
that prints and returns, a test, a `.gitignore`, and a README saying what to
run. It is the project someone gets for typing `nupp init`, so it has to be
the smallest thing that is genuinely complete.

`lib` is today's `nupp rock init` output — manifest, source, `.d.nupp`
declaration, test, rockspec — moved into a template directory verbatim.
`nupp rock init <name> [directory]` keeps working and becomes a thin call into
the same scaffolder with `lib` and `--name <name>`, so there is one
implementation of writing a project and one thing to keep working.

## Bootstrapping a Tecs project

Tecs is the case this design is meant to survive, so it is worth walking:

```sh
nupp init tecs-engine/tecs/templates/game my-game
```

The template's `nupp.lua` declares a `binary` target whose `stub` is the Tecs
host rather than `nupp`, a `dependencies` entry of `kind = "cargo"`, an
`assets/**` resource list, and a `tasks` entry that runs the game. All four
are existing manifest fields validated by existing code. The template's `raw`
globs keep `assets/**` out of substitution, which is the only reason binary
files need mentioning at all.

The Cargo dependency has to be spelled precisely, and the obvious spelling is
wrong. `DEPENDENCY_KEYS` in `nupp.compiler.build.manifest` closes each kind
against what its own provider reads, and `source` — the key whose `git` and
`rev` fields `nupp.compiler.build.deps.fetchGit` clones from — is a **`c`**
dependency key. `CARGO_KEYS` has no `source` and no `rev`; a Cargo dependency
names a local crate with `manifest` or `path`. So the arrangement is:

```lua
dependencies = {
   host = {
      kind = "cargo",
      manifest = "host/Cargo.toml",
      library = "tecs_host",
   },
},
```

with a small `host/` crate in the template whose own `Cargo.toml` pins the
engine at a revision. Cargo does the fetching and the pinning, through
`Cargo.lock`, which is the tool that should be doing it; Nupp builds the crate
in front of it. This is still no build change, but it is a different shape
from the one-liner it looks like it should be, and a template written the
other way is refused by manifest validation rather than by anything in this
command. Phase 5 tests this exact arrangement, because the claim that a Tecs
project needs no new manifest fields is only worth as much as the manifest
that proves it.

Two limits are real and should be said rather than discovered. A Tecs host
stub is not in Nupp's stub catalog, so a project built from this template
builds its host from source for the current platform; cross-target binaries
for it need a Tecs-published catalog, which is that project's work and not
this one's. And the template lives in the Tecs repository, versioned with the
engine it scaffolds against — which is the whole reason `owner/repo/subdir`
resolution exists, because an engine wants several templates in the repository
that already holds it.

## Implementation phases

### Phase 1: the scaffolder and the built-ins — complete

`nupp.compiler.template` — resolve, load, substitute, refuse, write — and
`nupp/compiler/cli/init_command.nupp` for the grammar, named for the same
collision `completions_command.nupp` already works around, since
`cli/init.nupp` is the dispatcher. Built-in `app` and `lib` under
`src/nupp/templates/`, embedded by the build. `nupp rock init` delegates.
`--list`, `--dry-run`, `--json`, `--schema`. No network, no local directories.

Done when `nupp init` produces a project that checks, builds, tests and runs,
and `nupp rock init` behaves as it does today.

### Phase 2: templates on disk — complete

`--from PATH` and the `./x` spellings, the sandboxed `template.lua` loader,
declared variables, `--set`, and the full refusal list. Built-in templates
gain `template.lua` files of their own and stop being a special case in
everything except where their bytes come from.

Done when a directory copied out of `src/nupp/templates` scaffolds through
`--from` to bytes identical to the built-in.

### Phase 3: remote templates — complete

`owner/repo`, `@rev`, subdirectory paths, and full URLs. `git clone --depth 1`
into a temporary directory, resolve the commit, read the tree, delete the
clone. The confirmation prompt names the URL, the commit, and the file count;
`--yes` skips it, and a non-interactive run without `--yes` is refused rather
than assumed. A refused or failed fetch writes nothing.

Done when a template served from a local `file://` repository scaffolds
identically to the same tree passed to `--from`.

### Phase 4: post-init steps — complete

The closed `after` set, each step reported by name with its status, none of
them able to fail the scaffold that already succeeded, and the source-based
restriction that drops everything but `git` for a remote template.

Done when a local template and a `file://` remote holding identical trees,
both naming `after = {"git", "check"}`, differ in exactly one way: the remote
runs `git` and reports the dropped step, and a `nupp.lua` in the tree that
writes a sentinel file when loaded produces that file for the local template
and never for the remote.

### Phase 5: the Tecs template — fixture landed, template outstanding

The template itself is authored in the Tecs repository once Tecs is on Nupp.
Its value here is as the acceptance case: if it needs a manifest field that
does not exist, that is a build change to argue separately, not a template
feature.

The one thing that landed here is the test for that:
`aGameShapedManifestNeedsNoFieldsTheBuildDoesNotHave` scaffolds a fixture
carrying the `kind = "cargo"` plus local `host/Cargo.toml` arrangement, a
non-default `stub`, an `assets/**` resource list and a run task, then loads
the result through `nupp.compiler.build.manifest`. It also checks that the
`raw` glob carried the binary asset byte for byte rather than substituting it.
So the claim is checked by this repository rather than discovered by that one.

## Diagnostics

Every refusal is a named condition with a hint, in the shape the CLI already
uses for a usage error, and none of them is a Lua error escaping to the top:

- unknown built-in name, listing the built-ins;
- target directory exists and is not empty, naming it;
- `--set` of an undeclared variable, listing the declared ones;
- a required variable with no value, naming it and its description;
- a variable value failing its `pattern`, reported with the template's own
  `invalid` sentence rather than with the pattern;
- `${...}` naming an undeclared variable, with the file and the name;
- `template.lua` missing, unreadable, reaching outside its sandbox, or
  returning the wrong shape, with the path into the returned table;
- a path escaping the target, a symlink, or a collision, naming both paths;
- a post-init step dropped because the template is remote, naming the steps
  and saying that the scaffolded manifest is not loaded for a fetched tree;
- `git` missing, the clone failing, or `--rev` not resolving, naming the URL
  and revision as given;
- a non-interactive remote fetch without `--yes`.

## Verification

- Unit tests for resolution: every spelling in the table above, the refusals,
  and the `--from` and `@rev` interactions.
- Unit tests for substitution: contents, path components, `$$` escaping,
  undeclared names, `raw` globs, and byte-identical copying of a binary file.
- Unit tests for the sandbox: a `template.lua` calling `io.open`, `require`,
  `os.execute` or looping forever is refused, and refused before any write.
- A unit test for declared `pattern` and `invalid`, including that `lib`
  refuses the names `nupp.compiler.rock` refuses today and prints the same
  sentence, and that declaring `moduleName` or a `default` for `name` is
  refused.
- Unit tests for the write refusals, each asserting the target directory is
  untouched afterwards, and for both destination policies: `rock init` refuses
  an existing empty directory and `init` accepts it.
- A unit test that a `.git` directory in a template tree, at the root and
  nested, is pruned from the payload, and that a symlink is reported and
  refused rather than resolved.
- An acceptance test per built-in template that scaffolds into a temporary
  directory and runs `nupp check`, `nupp build`, `nupp test` and `nupp run`
  against the result, asserting the program's expected output rather than only
  its exit status. `run` is in the goal and in the completion gate, so leaving
  it out of the suite would let the one promise a reader tests first be the
  one nothing holds. This is also the test that keeps a template from rotting.
- A remote test using a git repository created in a temporary directory and
  fetched over `file://`, so the suite needs no network.
- The post-init sentinel test from phase 4, which is the executable form of
  the security boundary: a remote template must not be able to cause the
  scaffolded `nupp.lua` to be loaded.
- A `docs/tooling/cli.md` section for `init`, which `tests/clidoctest.lua`
  holds to the bytes the binary prints.
- `tests/rocktest.lua` unchanged, proving `rock init` still behaves as it did
  once it delegates.

## Completion gate

`nupp init` is finished when a new user with a fresh binary and no network can
type `nupp init` and get a project that checks, builds, tests and runs — all
four asserted by the suite, `run` against its expected output; when `nupp init
owner/repo` names its commit, asks before writing, and executes nothing that
repository supplied; when the built-in templates are held to the suite rather
than to review; and when `nupp rock init` is a call into the same scaffolder,
with the same refusals it has today, rather than a second one.
