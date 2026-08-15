# Changelog

## Unreleased

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
