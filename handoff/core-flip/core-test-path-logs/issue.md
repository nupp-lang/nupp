`NUPP_RUNTIME=core ./bin/nupp test --lane=shared` on macOS ARM64 now runs every suite to an answer: 2690 tests, 2181 passed, 509 failed. Before the fixes on core-dev up to this issue, 13 of 18 workers died and only 1138 tests reported.

## What still ends a shared worker

- `graphguestbranchtest/scalarVectorSpecializationKeepsSourceTerminalRefusals` replaces `profile.call` on the table `tagged.forVersion(8)` answers. The carried compiler's own call of `profile.call` is bound to the function first stored there, so the core refuses the call with transport status 4 and the process ends. It is the same family as carried compiler code not seeing a test's monkeypatches of `package.loaded` and `os.getenv`.
- A call the core refuses at preparation (a callsite contract or signature mismatch) is reported as "core resource limit" (`guestops.prepareRefused`), indistinguishable from a full frame stack. Such refusals cannot be caught by `pcall`, so each one ends its worker.

## Families of remaining failures (counts are cases)

- 39 processtest: spawning reports "No such file or directory".
- 46 `tagged graph: drop of an owner this function does not hold` (net, compression, hashstream, portableio contracts, automatic destruction).
- 27 serde contract fixtures say they run on the VM.
- 16 `orExitExpr` and 7 `safeCall`/`safeBracket` are not lowered by the function graph; 13 numeric `switch` refusals; 3 `continue` in `repeat`.
- 18 nativetablestest cases fail because `program.run` returns only the first value a fragment returns on the core, not because of table bugs.
- layouttest: `types.layoutof` is not lowered on the core.
- fieldcodecmaterializetest: materialized comptime values (closures and helpers) and `@annotation` declarations are refused.
- gpudevicetest: `nupp.runtime.provider.wgpumemory` needs `nupp.vm.foreign` on the core.
- compression: `writer:close()` before `finish` reports "compression writer was closed without finish".
- coroutine, table and simd suites: "attempt to call a nil value" in tasks and pool helpers, and "SIMD species is not available on the scalar core".
- `local f = tonumber; f()` still answers nil: a call through a local alias of a library function pads its missing arguments with nil.

## Not started in this lane

- Binary targets on the core (`kind = "binary"`, `stub = "nupp"`). The guest program producer (`nupp.core.guestbuild.declareProgram`) only builds entries under the compiler checkout, so a project outside it has no core bundle to stamp.
- A top-level `...` in a `.nupp` program under `nupp run`: a module instance's owner has no vararg pack.
