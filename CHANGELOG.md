# Changelog

## Unreleased

- Install the development native library by renaming rather than by writing over
  it. `bin/nupp` copied it into place, which leaves a window in which the file
  is half a shared library -- and the loader does not report that as a bad file:
  on macOS the kernel refuses the image and kills the process, some way from the
  cause. Rebuilding it whenever its sources change made that window reachable in
  ordinary use.

- Reimplement child processes in C. Spawning, the nonblocking pipes to and from
  a child, the readiness wait and the exit accounting move to
  `runtime/native/c/process.c` and the two platform files under it. The POSIX
  half keeps what the Rust one had got right and says so in the same places: the
  `SIGPIPE` block-inspect-write-consume-restore sequence, close-on-exec on both
  ends of every pipe, and stderr joined to stdout as one pipe handed to the
  child twice rather than two streams merged afterwards. The Windows half uses
  uniquely named overlapped pipes, because an anonymous pipe cannot be read
  without blocking and has nothing a readiness wait can wait on. `libc` and
  `windows-sys` leave the dependency list.

- Reimplement URI parsing in C. A URI is held as one normalized serialization
  plus the offsets of its parts, so reading a component slices storage the
  handle already owns; deriving one takes the parts apart, replaces the one that
  changed, writes the result out and parses it again, so one grammar decides
  what is valid. `tests/uritest.lua` records the answers -- every component of
  seventeen URIs, six malformed ones and their reasons, and every derivation,
  concatenation, resolution and rerooting -- against the implementation this
  replaces. The `url` crate leaves the dependency list for everything but the
  HTTP transport, which still parses the handle's own text until it too is
  ported.

- Reimplement paths, SHA-256 and the UUID generators in C. `nupp.io.path` reads
  a path as components rather than by string arithmetic, and answers what it
  answered before down to the spelling: a path rebuilt is normalised, one sliced
  keeps the `.` the caller wrote. The digest is FIPS 180-4 directly and the two
  identifier versions are the same random bytes with different stamps. Five more
  crates -- `camino`, `path-clean`, `pathdiff`, `sha2` and `uuid` -- leave the
  dependency list.

- Rebuild the development native library when its sources change. `bin/nupp`
  built it once and then never again, so an edit to a provider was picked up by
  whoever next deleted the library by hand and every command in between ran
  against the one before it.

- Reimplement the file provider in C. `nupp.io.files` stands on
  `runtime/native/c` rather than on the Rust crate: metadata, listing, globbing,
  the open-file handles and the off-thread transfer lane, with the platform
  halves in `platform_posix.c` and `platform_windows.c` rather than one file
  with the differences threaded through it. The ABI is unchanged, so nothing
  above it moved. This is the first facility ported under
  [NEP 17](docs/neps/0017-c-only-toolchain.md); the rest of the provider and the
  binary host are still Rust.

- Provision LuaJIT, LPeg, luautf8 and simdjson from pinned sources rather than
  expecting them installed. `scripts/toolchain` fetches each by revision,
  refuses any archive whose SHA-256 is not the one written down, builds it with
  `NUPP_CC` and `NUPP_CXX`, and caches the result beside the repository so every
  worktree shares one build. `bin/nupp` uses the interpreter on `PATH` when it
  clears the syntax floor and builds the pinned one when it does not, putting it
  on `PATH` so the comptime workers, the LSP relay and the test runner all reach
  the same one; the JSON runtime links what pkg-config reports and falls back to
  the staged simdjson where it reports nothing. A checkout's requirement is now
  a C and a C++ compiler, plus a Rust toolchain until the native providers and
  the binary host are ported.

- Add schema-driven serde for records, fixed-layout structs, and run-time
  dynamic values. `@derive(nupp.derive.Serde)` produces one format-neutral
  schema and binding; prepared JSON profiles cache encoded keys and raw-byte
  lookup, traverse flat scalar structures in one native call, and reuse
  per-thread encoder and decoder scratch. Dynamic bindings resolve names once
  into checked dense slots, and typed extensions now provide the shared lazy
  cache boundary for reflection descriptors, schemas, and bindings. Prepared
  writes reserve caller-owned buffer storage and avoid allocating and copying a
  complete intermediate Lua string.

- Publish the documentation site by convention rather than by inventory. A page
  entry names a `glob`, and every Markdown file it matches is published at the
  route its path gives, under the title its heading gives; what a path cannot
  say -- where the page sits in the navigation, the name navigation should use
  instead, the routes it used to answer at -- the page says in its own front
  matter. The manifest had listed all 71 pages as a route, a title, and a source
  that were the same fact written three times, which the tree already held and
  which failed silently the first time a page was written and not listed. The
  home page's hero and feature showcase move the same way, from three hundred
  lines of Lua tables holding Markdown into the Markdown page itself, between
  comment markers. `nupp.lua` is a third of its former size.

- Move the standard library's documentation into the modules themselves. Twelve
  pages under `docs/modules/` said what a module is, next to none of the source
  that says what it does, so a change to one had to remember the other. Each is
  now that module's blurb: `nupp.data.json` in `src/nupp/data/json.nupp`,
  `nupp.math` and `nupp.peg` in the prelude declarations that describe them. A
  blurb renders as a module page's own prose, its headings join the page
  outline, and a reference to a module may carry an anchor into it, as
  `[](nupp.mem.span#writable-spans)`.

- Add the explicit `nupp.Closeable` lifecycle, inherent affine construction, and
  `managed(T)` cells with checked copyable `alias(T)` references. Replace the
  compiler-privileged `nupp.owners` Set/Store protocol with ordinary
  `nupp.managed.Group` library code, permanent cell tombstones, and managed
  policy checks during hot reload. HTTP clients now use the same `nupp.Closeable`
  lifecycle.

- Write incremental and derived JSON through one checked, buffer-backed writer.
  `EncodedValue` and the interned `EncodedString` retain bytes encoded or
  verified once, letting `write` and `key` append them without another walk,
  validation, escape pass, or intermediate string. Derived schemas lazily cache
  encoded field names and literals; `encodeAs` and `encodeRecord` remain
  explicit allocating conveniences. The Writer is `nupp.Closeable`, batches commits,
  names container endings explicitly, and pools only native backing state after
  its consuming `close()`.

- Let a loop compile around an owned binding whose protected body reads or
  writes an enclosing local. A capture stable for one function call keeps one
  guarded region closure in that invocation; a local recreated by an enclosing
  loop travels through a frame passed to the module-cached closure, with writes
  copied back before cleanup and structured-exit dispatch. Recursive calls keep
  independent upvalues, and per-iteration resources remain per-iteration.

- Put the design rationale where the question occurs. A `::: rationale` block
  renders collapsed, holds two to four sentences on why the construct on that
  page is shaped the way it is, and links to the proposal holding the full
  record. Fifteen pages had no signal that a design record existed at all. It
  carries the current design only: a rejected alternative, a superseded
  spelling, or a withdrawn attempt has no page to sit on and is rewritten away
  when behaviour changes, which is why proposals are separate files.

- Cut the enhancement proposals to eleven architecture documents. The port
  produced one proposal per decision, which is one per sub-feature: forty-three
  documents, several of them re-documenting the type system, the standard
  library, or the command-line tools that already have pages of their own. A proposal is now a broad
  architectural slice -- ownership, suspension, comptime, modules, C interop,
  ahead-of-time compilation -- and each shows the syntax, a usage example, and
  what the construct lowers to, rather than describing it. More granular ones
  can arrive when contributors write them.

- Publish the design record on the site as Nupp Enhancement Proposals. `plans/`
  held 71 dated files outside the documentation, and their statuses had stopped
  being true: two described `Owned<T, cleanup>` and `@drop` as implemented after
  both were removed, two disagreed with each other about whether a pluck is
  written with parentheses or braces, and one carried two status lines. They are
  now 42 numbered proposals under `docs/neps/`, ordered so each builds on the
  ones before it, and a proposal records why a design was chosen rather than what
  the compiler does -- reasoning about a decision made on a date stays true after
  the code moves, which is the property that made the old files worth keeping and
  the descriptions in them worth deleting. Three that never built anything are
  kept as the alternatives sections of the designs that replaced them, because
  the module design looks arbitrary without the four attempts before it. The
  backlog that was living in there is `TODO.md`, and the four diagnostic anchors
  that pointed into `plans/` now point at proposals, so `nupp explain` renders
  them as links rather than as repository paths.

- Publish a directory of markdown as one documentation section. A page entry in
  the manifest may name a `directory` instead of a `source`, and then stands for
  every document under it plus an index generated at its own route from their
  frontmatter. Listing each document instead fails silently -- the file is
  written, the site shows one fewer than the repository holds, and nothing
  reports a problem.

- Let a reader take the part of the reference they need. `nupp reference` had
  three slices -- `language`, `cli`, `performance` -- and the first is over
  thirteen thousand words, so a question about one construct cost the whole
  chapter. `--section NAME` prints one section, a few hundred words, named by
  its heading or by any `docs` pointer at it, so the anchor every diagnostic
  already carries is a thing that can be followed rather than only cited.
  `--for CODE` goes the other way and prints whichever sections explain a
  diagnostic, which is what a reader holding one actually has. Bare `nupp
  reference` now lists every section, because the alternative to naming the
  slices is guessing at them: agents in the evaluation harness ran `nupp
  reference types`, `nupp reference syntax` and `nupp reference
  docs/modules.md`, all of which failed, and then loaded the whole chapter
  instead. `types` and `modules` are real names now.

- Say whether `nupp check --json` actually checked anything. An empty
  `diagnostics` meant two different things -- a project with nothing wrong,
  and a run that never reached a file because it could not use the manifest --
  and nothing in the payload told them apart, so a reader consuming the JSON
  and not the exit status read a configuration failure as a clean bill of
  health. `ok` is now beside `diagnostics`, false in both failing cases, which
  is what `nupp build --json` has always reported for the same reason. Found by
  the agent evaluation harness, whose first task workspace was misconfigured
  in exactly that way and reported clean.

- Give `nupp explain` a worked example for every diagnostic code the compiler
  can actually emit that one is reachable for. 60 of the 149 codes used to
  fall back to their family's generic paragraph -- summary, rule and all --
  which reads as an answer without being one; `NUPP2105`, an unknown-variable
  typo, was one of them. Each new entry's `wrong` example is compiled for
  real and asserted to report the code it is filed under, the same as every
  existing entry; two lint codes and two codegen codes are demonstrated too,
  by triggering the underlying checker/generator gap rather than inventing a
  program that only looks like it should. A handful of codes -- a reserved
  annotation nothing currently reserves, a formatter safety net with no known
  input that trips it, hot reload's own restart notice, and two whole-project
  name collisions no single file can exhibit -- keep the family's rule text
  under their own summary but carry no example, since a wrong example that
  cannot be verified is worse than the fallback it would replace.

- Report `nupp check --json`'s cache accounting the same way `nupp build
  --json` already does. AGENTS.md has long said a slow check is worth reading
  rather than waiting out, but nothing in `check`'s own output said what a
  given run actually redid -- the accounting was already computed for every
  check, `nupp build --json`'s `timing` object having published it for a
  build all along, and `check` silently discarded it before it reached
  `--json`. `compiledModules = 0` is now the answer to trust that a slow
  check redid nothing; `slowest` ranks modules by wall-clock time spent
  either way, since confirming a cache entry is still valid costs time too,
  just less of it.

- Remind the next worktree about the last one. `scripts/worktree` now lists
  any other registered worktree whose branch already merged into `HEAD`,
  right after creating the one just asked for. AGENTS.md has always asked
  that a finished worktree be removed, but nothing noticed when it was not;
  two accumulated silently in this checkout before this was written. The
  check is best effort and never fails the worktree it is only polishing.

- Hold hot reload to the strict floor. `src/nupp/hotreload.g.nupp` and
  `src/nupp/compiler/hot_session.g.nupp` were the only two files under `src` that
  opted out of it, which put the machinery deciding whether an edit may reach a
  running program outside the checking every other part of the compiler gets.
  Both are `.nupp` now. `nupp.HotReload.poll` answers `nupp.HotReloadPoll`
  instead of `any`, and its docblock says which of the four `kind` values carries
  which fields, so a host branches on a documented answer. The compiler side
  gains the `Prepared | Rejected | Restart | Unchanged` result it was specified
  to have, plus the `Session`, `InitialBuild` and watched-input types. The slot
  vectors, the loaded patch chunk and the module manifests stay `any`, which is
  what they are: generated code writes them, generated code reads them, and their
  shape is not this module's to claim.

- Replace lua-cjson with Nupp's simdjson-backed JSON runtime. The public
  `nupp.data.json` surface now has eager `decode`, On-Demand `pull`, strict
  `encode`/`serialize`, and an incremental writer. Null is dropped by default
  or preserved with a caller-provided value; `NULL`, `EMPTY_ARRAY`, and
  `EMPTY_OBJECT` cover the values plain Lua cannot distinguish, while
  `asArray` and `asObject` make container intent explicit. The compiler,
  sidecar builds, and self-contained host all use the same codec and policy.
- Check every entry of a table constructor, not only the ones before its first
  computed key. A `[k] = v` entry settles what the constructor's type is -- a
  generic table -- and the checker answered with that type as soon as it saw
  one, which left every entry past it unvisited. So a mistake in one went
  unreported, and a `new R(field = value)` standing after one reached the
  generator with nothing resolved: a construction lowers from the fields the
  checker bound rather than from the arguments as written, so it was written
  out as the call it was spelled as, and `{["a"] = new R(f = 1), ["b"] = new
  R(f = 2)}` failed to compile with NUPP3005. Positional construction past a
  computed key had the quieter version of the same fault -- it generated Lua
  that parsed and called the record's own table at run time.
- Create a project from a template with `nupp init`. A template is a directory
  tree with one `template.lua` at its root, and the same format serves a
  built-in, a directory named with `--from`, and a repository spelled
  `owner/repo`, optionally with a path within it and `@rev`. `${name}` is
  replaced in file contents and in path components, so `src/${moduleName}.nupp`
  becomes a file named for the project. The built-in `app` and `lib` travel
  inside the compiler, so `nupp init` answers with no network and no checkout,
  and `nupp rock init` now scaffolds `lib` rather than carrying its own copy of
  the same five files.
- Run nothing a fetched template supplied. `template.lua` is read in a sandbox
  with no `io`, `os`, `require` or `load` in it, and a repository template's
  post-init steps are reduced to `git init`, because `check`, `build` and
  `test` all load the scaffolded `nupp.lua` and a manifest is ordinary
  unrestricted Lua. A repository template also names the commit it resolved to
  and is confirmed before anything is written; a run with nothing at the
  terminal to answer is refused rather than assumed.
- Let a loop compile around an owned binding whose body calls something. The
  cached region function is written where it stands and only its instance is
  kept for the module, so a name the chunk's outermost block declares -- which
  is every module-level function -- can be captured and reused. Only a name
  belonging to an enclosing function, block, or loop, including a chunk-level
  loop variable, still costs the region a function per entry.
- Spread an argument list one argument per line whenever it stops fitting on
  one, whether by width, by a comment inside it, or by an argument whose own
  body is a block. A call's trailing function or table still hugs the line that
  opens the call while what precedes its body fits there, and a table
  constructor spreads on the same terms.
- Keep a shape type of one field on the line that names it, so
  `headers: {string: string}?` stays as written and breaks only on width. A
  shape of several fields is still a list of them, one per line however short.
- Keep the space in `borrows (p)` and a closure's `takes (a, b)`, leave a bare
  `;` on the line of the statement it terminates, indent a comment that is the
  whole of an `if` arm inside that arm, and stop a docblock's trailing
  annotation from taking the blank line owed to the declaration below it.
- Say when a closure that reads its iteration costs a loop its trace. The new
  `jit-loop-closure` lint (`NUPP2515`) is off until a project asks for it,
  since the code it reports is correct and has no mechanical fix, but a
  function annotated `@jit` promised that it compiles and reports the same
  hazard as `NUPP2707` whatever level the lint is at.
- Read each workspace folder under its own `nupp.lua`, so a file is checked the
  same way whichever window opened it. Every folder gets its own incremental
  graph, built when something first asks that folder a question and reading the
  editor's open buffers along with the rest; `$/nupp/inspect` and
  `workspace/symbol` say which folder answered.
- Stop language-server work when the request it belongs to is cancelled, at
  every module and file header on the way to the answer, and answer
  `ContentModified` rather than sending positions the client has already typed
  past. Published diagnostics name the document version they were found in.
- Say what a build is doing while it runs, and where its wall-clock time went
  and which modules cost the most when it ends. Reported to a terminal only;
  `--progress`, `-q` and `NUPP_PROGRESS` say otherwise, and `build --json`
  carries the same numbers in a `timing` object.
- Type `ffi.C` from a C function this process had already declared, which an
  ordering accident between the compiler's own code and the file it is
  checking could previously empty.
- Add deterministic target-aware C header export and typed ordinary-struct
  pointer interoperation through `nupp export-c`.
- Add explicit allocation-free `nupp.math.i32`, `u32`, and IEEE-754 binary32
  scalar operations.
- Add affine writable span slices, allocation-free checked common ranges, and
  ownership-qualified typed variadic parameters.
- Add `noalloc do` and `noraise do` regions with observed cross-module
  guarantees and cleanup-aware effect inference.
- Increase the single isolated comptime-worker deadline to 10 seconds so
  bounded evaluation includes compiler startup under parallel build load.
