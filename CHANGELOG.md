# Changelog

## Unreleased

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

- Say what every JSON codec in the compiler does with an empty table and with a
  NaN, instead of taking whichever cjson the interpreter loaded at its word.
  cjson's defaults belong to the build rather than to the library, so a codec
  that left the question open answered one way under a stamped host binary and
  another under a distribution build, and the same command could read its own
  cache file two ways. The default that actually bites is decoding: `NaN` and
  `Infinity` are accepted on the way in where they are refused on the way out,
  so a document could be read and then fail to be written back. Eight codecs
  were inheriting it -- the build state file, the task list, cargo's artifact
  messages, the comptime worker's request side, `bc`, `run --aborts-out`, `aot`,
  and the coverage shard reader -- and now state their own policy. A test walks
  the sources and fails naming any codec that leaves a setting to the default.
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
