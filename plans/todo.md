# Nupp TODO

Grouped by the part of the system a change lands in. Nothing here is
prioritised by tier; the ordering inside a section is roughly the order the
work makes sense in.

## Type system

- [x] **Comptime** ([design](comptime.md)): deterministic value evaluation,
      deliberately not a macro or declaration-generation system. C1–C4 and
      closed materialization's core have landed. Reach for comptime for a program
      that needs a generated table, not for one that wants a constant: those
      keep turning out to have cheaper answers, `OPT-3` having since taken `//`
      and the bit operators.
  - [x] Materialization M0: run the standalone handwritten specialized PEG and
        pure-Lua reference-machine benchmark now. It has no comptime milestone
        prerequisite. Record workloads and numeric margins before measuring;
        delete the specialized-backend milestone if it misses that margin.
  - [x] C2a: immutable `nupp.reflect(T)` descriptors over the checker's full
        structural vocabulary; semantic type fingerprints and module interface
        dependencies. Target-independent and blocked on nothing. Shared with a
        future derive phase, so it is not shaped around comptime's convenience.
        The versioned indexed graph, immutable user-code views, recursive type
        handling, structural vocabulary, semantic fingerprints, checked
        declaration/field annotations, reflection hover/completion, and keyed
        cross-process invalidation have landed.
  - [x] C2b: target-aware `nupp.sizeof`/`nupp.alignof`/`nupp.offsetof`.
        Build targets select an explicit `layoutTarget`; the compiler owns
        versioned LP64, i686 SysV,
        and i686 MSVC C layout profiles for nupp's fixed-width reifiable type
        vocabulary. Type-position intrinsics accept aliases, qualified types,
        pointers, arrays, and generic instantiations, with target keys separated
        in persistent caches. Runtime `layoutof` remains the running FFI's answer.
  - [x] C3: `@comptime` functions with ordinary type checking, erased runtime
        output, bounded recursion, and comptime call stacks. File-private at
        first, but cross-module helpers are an expected extension; helpers
        taking a `TypeInfo` need nothing from the generic system.
  - [x] C4: the evaluator runs behind an isolated worker with step, call,
        wall-clock, result, protocol and best-effort process-memory limits;
        crashes are recovered and canonical materialization products persist in
        manifest build records. The portable process host now services relayed
        protocol input while a worker is in flight, kills cancelled workers, and
        answers cancelled queued requests without dispatching them.
  - [x] **Closed materialization**
        ([design](materialization.md)): an explicitly typed comptime block may
        return a compiler-owned opaque value that a sealed provider serializes
        as one runtime expression. Benchmark PEG before the framework, ship a
        pure-Lua bytecode-VM backend first, and admit specialization only if
        it clears the recorded bar. A type-directed field codec is the second
        provider and the proof that the common layer is not PEG-shaped. No
        user-defined materializers, code AST, source splicing or generated
        declarations.
        Order the work as C4's worker floor, then M1–M3; M4 additionally needs
        C3, then M5 and the M0-approved M6. C2a and M3 unlock the field-codec
        provider M7. C2a does not block PEG.
        M1–M7 and the persistent/observability/resource-limit portions of M8
        have landed. The common layer and both providers are complete. The
        remaining reflection/editor and cancellation work is tracked under
        C2a and C4; the external tecs run is tracked by the acceptance corpus.
- [ ] **Derives** ([design](derives.md)): the compiler-owned `Debug`, `Default`,
      single-field `From`, and `JSON` derives have landed as checked semantic
      additions with closed lowering recipes, never source or CST fragments.
      The remaining work is editor and incremental hardening, acceptance, and
      deciding whether a restricted user-defined provider is justified.
      The remaining work must preserve line-count-invariant output,
      module-interface fingerprints and generated-member tooling. Associated
      types are not a prerequisite;
      user-defined providers are evaluated only after the four built-ins prove
      the constrained result model.
  - [x] D0: reserve derive/helper annotation names through the existing
        registry, stage declaration checking, freeze the landed semantic
        descriptor, hydrate typed built-in schemas from hidden prelude
        declarations, and add the canonical plan query and observation provider.
  - [x] D1: generated member merge/lowering, declaration-table static-member
        projection with generic inference, and `Debug`.
  - [x] D2: typed field defaults and `Default`.
  - [x] D3: single-field `From`, structural factory shape and `nupp.into`.
  - [x] D4: extend `FieldCodec.KeyedCodec<T>` with typed decode, materialize a
        direct string-buffer emitter from the shared blueprint, keep a private
        cjson instance for raw decode, enforce safe integer fidelity, add
        `JSONEncodable` conformance, and generate JSON forwarders.
  - [ ] D5: finish incremental precision, generated-member editor integration,
        cancellation/recovery, remaining output/local/upvalue limits, external
        acceptance workloads, and fixpoint closure. Reference/skill output,
        plan and field limits, deterministic fingerprints, and idempotence
        coverage have landed.
  - [ ] D6: decide a restricted user-defined semantic provider API from an
        external proving case; do not expose token or AST macros.
- [x] **Type-level computation**
      ([design](type-level-computation.md)): a checker-native, type-to-type
      reducer for dependent API surfaces. It is separate from comptime: share
      the semantic member vocabulary and fingerprints with C2a, then land
      finite `keyof`/indexed/mapped operators, explicit const generic
      parameters, `match`/`infer`, template literal types, and guarded direct
      recursive aliases. `unpackof` bridges a reduced tuple or array into a
      callable pack and powers the prelude's literal-aware `string.format`.
      Route parsing and nested-container normalization are the recursive
      workloads; deterministic budgets, cancellation polling, cycle detection,
      and expansion traces bound the in-process reducer.
- [ ] **Suspension follow-ups** ([design](suspension.md)): checked, handled
      waiting has landed. One call site parks under a scheduler and blocks
      without one, so a library that waits works inside a game frame and inside
      a CLI without knowing which it is in. The open work is effect-interface
      precision for nominal methods and permitting structured exits from a
      handled region without weakening cleanup.
  - [x] S0: the effect, transported. `noYield` is a positive guarantee on
        `types.Func`, in the interning key and in `typeFingerprint`, so both
        identity mechanisms see it. Boundary finalization qualifies each
        exported callable from its own definition after `analysis.run`, which
        is what separates two same-signature exports that interning had
        collapsed. `T.withYields` clones rather than respelling `T.func`.
        Function expressions are now summarized, without which a callable
        inside an exported table had no answer.

        A second pass closed three transport holes. Re-exporting an alias
        preserves an imported guarantee rather than erasing it, absent local
        provenance meaning nothing was learned and not that a fact was
        refuted. Every function-type reconstruction carries the qualifier --
        substitution, instantiation, receiver adjustment, and the shape
        comparison that drops a receiver. And every returned module surface is
        finalized, not only one assembled field by field, so a module that
        returns a function or a table literal is qualified too. A declared
        `yields = false` also outranks an inferred `external`, which is the
        one thing a contract exists to say.

        Left open: nominal methods are outside the qualified boundary and stay
        may-yield, since a nominal's identity survives rechecks and
        `typeFingerprint` does not expand its members, so a guarantee there
        could not be invalidated. `aNominalMethodIsNotQualified` pins that on
        the method's own type and is what should fail first when the
        effect-interface digest moves the boundary.
  - [x] S1: `nosuspend` regions and `@effects(yields = false)`, with NUPP2701
        carrying the call chain. It has no run-time component and turns one of
        tecs's run-time errors into a checked one.
  - [x] S2: the `suspend` operation, the `Suspension` handler interface
        with typed one-shot subscriptions and readiness contexts,
        coroutine-local handler inheritance, `handle ... with ... do`, and the
        built-in blocking fast path. tecs must retain its ready-path and frame
        performance.

        The runtime has landed (`src/nupp/suspension.nupp`): `suspend`, the
        handler interface with `canPark` and `shutdown`, per-coroutine
        installation as an affine `Installed` owner discharged lexically,
        identity-keyed readiness sources with release handles, and the built-in
        blocking handler. 202ns and 416 bytes against tecs's 349 and 568
        (`bench/suspension-baseline.lua`).

        The two implementation items landed, cleanly separated:
        (a) landed. `handle suspension with h do ... end` elaborates to
        installing an `Installed` owner, running the body protected, and
        discharging on every exit, with the body marked a checked
        handled-suspension region (`c.handledDepth`) for S4 to rest on.
        Contextual in both words. Line count preserved.

        One limitation, refused rather than mis-compiled: the body lowers to a
        protected closure, so `return` or an unbound `break` leaving the region
        is NUPP2706. Removing that means reusing what cleanup regions already do for
        the same problem instead of the simpler lowering here.
        (b) landed, and smaller than budgeted. `suspension.create` inherits the
        handler in force where the coroutine was made; there is no `resume` or
        `wrap` wrapper because none is needed. Inheriting at *creation* removes
        the per-resume save/switch/restore this milestone budgeted for
        entirely: a resumption is `coroutine.resume`, unwrapped, costing what
        it always did. Creation costs about 19ns and no allocation
        (`coroutine-resume` against `nupp-create` in the harness).

        It is also the better reading: what answers is the handler in force
        where the work was started, which a reader can point at, rather than
        one belonging to whoever happened to resume it.
  - [x] S3: the C-call boundary — implicit `nosuspend` at known non-yieldable
        FFI and standard-library callback invocations, with safe metamethod and
        generic-loop suspension left alone and a named run-time failure for
        what static analysis cannot reach.

        Landed. `table.sort`'s comparator and `string.gsub`'s function
        replacement are implicit regions, recognized by definition identity so
        a local named `table` is left alone, and a suspending call inside one
        is NUPP2702 naming which call reaches it. Metamethods and generic loops
        are *not* regions by category, since an ordinary metamethod may yield
        on this baseline. What static analysis cannot reach fails at run time
        with the operation and the boundary named rather than LuaJIT's message.

        The prelude's base functions are now `nosuspend function` too. Two of
        them -- `tostring` through `__tostring`, `pairs` through `__pairs` --
        are a stated trust rather than a proof, in the same category as a
        metamethod contract: without it a comparator cannot call `tostring`,
        which is most comparators, and the compiler's own `build/cache.nupp`
        was the first thing the check refused.
  - [x] S4: permit handled suspension while a resource obligation is live,
        keeping NUPP2603 for raw coroutine yields. A handler owns every accepted
        park and its shutdown cancels and unwinds all parks before succeeding.

        Done. A handled suspension may cross a live obligation,
        deliberately rather than by omission, and the diagnostic points at
        `handle suspension` as the way to do it responsibly. A raw yield
        through the global is NUPP2603.

        A raw yield is refused through the global, through `local co =
        coroutine`, through chains of those, and through `local coroutine =
        coroutine` -- while a local bound to somebody else's table is left
        alone. Provenance decides it, on the scope entry rather than on the
        definition, because a definition is shared by every mention of a name
        and a flow fact about one binding does not belong on it. The
        self-rebinding case reads the initializer's own token, which still
        points at what it read rather than at the binding being made.

        An earlier attempt shipped a false positive and was reverted -- except
        the producer was not, which is what made the behaviour unexplainable
        for two rounds. Reverting half a change is worse than reverting none.

        Cancellation unwinds rather than merely unsubscribing: abandoning a
        park wakes the parked continuation with a cancellation, so the stack
        resumes and every lexical owner between there and the park runs its cleanup.
        A ticket is only taken off when its `suspend` returns, so a scheduler
        that answers a wake by enqueueing cannot let release report a closed
        scope while a coroutine is still suspended inside it -- release drives
        shutdown and the pumps, then refuses, naming the operations. Every
        cleanup step is attempted and the first failure reported. Parks are
        held per installation; a released installation is stepped over, so a
        coroutine that starts after its extent ended does not add parks nobody
        will abandon; every failed park path unsubscribes; and a subscription
        that raises after registering a pump releases it.

        Cancellation is itself protected: a `cancel` that raises no longer
        skips marking and waking the park, which used to leave the coroutine
        suspended forever -- the outcome the path exists to prevent. A release
        that cannot drain keeps its tickets and stays retryable rather than
        dropping continuations nobody then owns, and reports the first failure
        rather than hiding it behind the unfinished-park report.

  - [x] S5: `nupp.io.Process`. The platform-neutral state machine, public
        module, contextual waits, `communicate`, `nupp.Reader`/`nupp.Writer`
        streams and `Exit:succeeded` are integrated. The Unix provider is
        tested against real children on macOS and Linux; the Linux masking path
        has run, including preservation of an already-pending `SIGPIPE`.

        The Windows provider uses opaque stream handles, bounded pipe workers
        and waitable events rather than exporting descriptors. Its library and
        tests cross-check for `x86_64-pc-windows-gnu`, and the native-process
        workflow executes them on a Windows runner.

        tecs installs the suspension handler per task and pumps readiness from
        its scheduler. Thirty-two public Process tests pass with only the
        import changed, including application shutdown with a live child. The
        one excluded assertion reaches tecs's old private
        `runtime.registered("processes")` source; preserving it would test the
        implementation being replaced rather than Process compatibility.
- [ ] **Files adoption** ([design](files.md)): `nupp.io.files`, its native
      provider, bounded request lane, suspension integration, and compiler
      adoption have landed. The remaining project is tecs adoption: delete
      `io/files`, `internal/fileasync`, `platform/storagebackend` and its
      atomic-write worker in favor of the shared facility.
  - [x] F0: the immediate tier — metadata, listing, directories, links,
        renames and temporaries over `std::fs`.

        Done. One `nuppFilesInfo` with a follow flag answers `info`, `exists`,
        `isFile`, `isDirectory` and `isSymlink`, so five queries cost one
        export; a listing carries each child's kind from the directory entry
        rather than a second call per name; and a temporary is created rather
        than proposed, so no second caller can take the name in between.
        `tests/filestest.lua` builds the provider with Cargo and drives it
        against a real filesystem.

        `userFolder` reads the `XDG_*` variables and the platform's
        conventional names instead of taking the `directories` crate, which
        settles that open question against a dependency.

        Two deliberate departures. A path goes in and a string comes out,
        because answering a `Path` would make listing a directory link the
        `path` provider too. And `fs.nupp` did not adopt it: the compiler uses
        no native facility today, and making it the first program that cannot
        build without a Rust artifact is F4's decision to take, not F0's.
  - [x] F1: `File` and `TemporaryPath` as owners over the existing contracts,
        with whole-file read, write, append, atomic write, copy and lines.

        Done. The reader and writer are declared as `nupp.Reader` and
        `nupp.Writer`, which are interfaces, so a parser written against a
        buffer takes a file with no adapter. `readInto` and `writeFrom` reach
        the destination buffer's FFI storage directly, which is what backing
        `Buffer` with an array bought.

        Transfers are synchronous; F2 replaces the mechanism and F3 adds the
        `suspend` without moving the surface. `DirectoryStream` did not land —
        `list` answers a table, and streaming a directory belongs with the
        request lane rather than ahead of it.
  - [x] F2: the bounded submit/poll request lane in Rust, ported from tecs's
        `fileasync.rs` with SDL removed, `writeAtomic` among its request kinds.

        Done. Whole-file read, write, append, atomic write and copy submit to
        a four-worker lane bounded by live transfers, by bytes held between
        them, and by the size of one; past any of the three a submission
        answers a reason rather than queueing. The Lua side still waits to
        completion — F3 is what makes the same call park.

        A read is priced by sizing the file on the submitting thread, because
        a lane that cannot price a transfer cannot bound itself. The budget is
        returned when the caller's handle is destroyed. Tying it to the shared
        state instead -- so a cancelled transfer whose worker was still reading
        had not yet given its bytes back -- shipped and then failed
        intermittently: a worker publishes its result from inside the state
        both sides share, so a caller releasing on sight was still counted
        until the worker got around to letting go.

        `nupp task native-test` runs the provider's own unit tests, which the
        Lua suite cannot reach: the lane's budget, its refusals, and what a
        cancelled transfer refunds are only visible from inside.
  - [x] F3: the readiness source and the `suspend` call sites, with the
        immediate-completion early return the cost model requires.

        Done. A whole-file transfer waits by suspending: it sleeps in an
        ordinary program, parks under an installed handler, and is NUPP2701
        inside a `nosuspend` region -- one call site for all three. The
        immediate operations are declared `nosuspend`, so a region that forbids
        waiting still permits asking what a path is.

        This turned up the S2 packaging gap and fixed it. A target has to carry
        `nupp.suspension`, and nothing shipped it: the module resolved only
        inside this repository, so a library that performed `suspend` could not
        ship at all. `native.files` now declares `requires` on a
        `runtime.suspension` feature, `native.resolve` closes over `requires`,
        and the native stage copies a feature's `runtimeModule` out of the
        compiler's build into the target. `handle suspension` records the same
        effect, so user code is served by the same route.

        The pump is chosen per wait: `nuppFsPoll` under a handler, which must
        not block a frame, and `nuppFsWait` without one, since the built-in
        blocking path drives sources in a loop and would otherwise spin.
  - [x] F4a: compiler adoption. `fs.listFiles` walks `nupp.io.files.list` and
        `fs.mkdir` calls `createDirectory`; the `find`/`dir` shell-out is gone.
        Reading and writing stay on `io.open`, since a build reads thousands of
        small files and a worker handoff would cost more than the read.

        Cargo is now a prerequisite for building Nupp at all: stage 0 reaches
        the provider while listing the sources it is about to compile, so
        `bin/nupp` builds `runtime/native` before it needs it and exports
        `NUPP_NATIVE_LIBRARY`. Help is exempt, because it reads no source file
        and has to work in a tree with only the tracked bootstrap.
        `bootstrap/nupp.lua` was regenerated.

        The fixpoint digest skips `lib/` and `native/`: a shared library records
        the path it was built in and each stage builds into its own target
        directory, so comparing them would test Cargo rather than the compiler.

        Verified from a clean clone with no `build/`. Not verified on Linux or
        Windows: the native-process workflow exercises only the Rust process
        provider, not the compiler bootstrap or files adoption.
  - [ ] F4b: tecs adoption, deferred as its own integration project. `tecs`
        is Teal and `nupp.io.files` is an ambient global rather than a module a
        `.tl` file can require, so it needs the bootstrap chunk in tecs's
        runtime, a `.d.tl` surface, the cdylib, `nupp/suspension.lua` staged for
        a consumer nothing stages it for, and its already-landed suspension
        adapter joined to the files readiness source.
- [ ] **HTTP client** ([design](http.md)): optional `nupp.io.http` over a
      feature-gated Reqwest/Tokio provider. Preserve direct string, byte-view,
      buffer and file paths; make responses progressive `Reader` values; use
      bounded per-transfer queues and deduplicated readiness tokens rather than
      per-chunk events. Benchmark warm small requests and 256 MiB streams as
      landing gates. Tecs keeps its ECS policy and SDL-owned loop, installs its
      existing suspension adapter per task, polls Nupp without sleeping before
      and between scheduler rounds, and deletes its per-client transport pump
      and private upload scheduler after adoption. A close/count-only facade
      registry may remain for Teal lifecycle compatibility.

## FFI and the C boundary

- [ ] **`import-c` stops at the file it was pointed at.** One boundary
      question wearing two faces, and it is a design call rather than a bug.
      Declarations reached only through a private sibling header are invisible:
      macOS puts `strlen` in `_string.h`, so importing `string.h` correctly
      yields nothing (`filterToHeader`, `src/nupp/compiler/importc.nupp:46`). The same
      cut applies to constants, which are read from the target file's own text
      (`headerMacroNames`, `src/nupp/compiler/importc.nupp:272`), so `errno.h` — which
      defines `EPERM` in `sys/errno.h` — imports none at all.

      This was the whole of the August 7 real-header sweep. Everything else that
      used to stop system headers was fixed, and eight common macOS SDK headers
      imported without error, four usefully
      (`math.h` 213 functions, `unistd.h` 153, `fcntl.h` with `open`/`fcntl`,
      `zlib.h` 45), and the four empty ones — `stdio.h`, `stdlib.h`,
      `string.h`, `time.h` — are empty for exactly this reason.
- [ ] **Mark C-derived function types, then land the callback `jit.off`
      lint.** Passing a Lua function where C will call it creates an FFI
      callback, and a variadic FFI call or a callback that runs on a compiled
      trace corrupts or panics — but only past the trace threshold, so it
      survives every test that runs the path fewer than ~56 times. NUPP2502
      exists but fires only syntactically, at an `ffi.cast<ptr>(fn)` inside
      `unsafe` (`src/nupp/compiler/check/ffi.nupp:164`). Function types now have
      a generic `foreign` bit, but the real check still needs C callback
      positions distinguished from ordinary Lua function values throughout
      cdef signatures, `cheader` exports, and C function pointers. Then flag a
      Lua function reaching one without `jit.off`, and the variadic FFI call
      with it. This is the validation target's real production bug class, so it
      is worth the marking pass rather than a heuristic that guesses from
      argument shape.
- [x] **Propagate string-pointer provenance past a bare name.** Pointer casts
      now collect provenance from names, indexed values, concatenations,
      constructed records, aliases, and declared preserved or borrowed call
      results. NUPP2501 is emitted at the cast, so assignment form does not
      create the earlier hole.
- [ ] **Generic bounds-carrying spans and the tecs buffer port.** Rooted
      `ByteSpan` and affine `ByteWriteSpan` have landed with checked indexing
      and slicing, consuming `commit`, and provenance-preserving buffer
      conversions. Fixed C arrays also enforce static or runtime bounds. What
      remains is the generic `span<T>`/`span<const T>` decision and the actual
      tecs `Buffer`, `ByteView`, `WriteRange`, compression, process-I/O,
      mapped-buffer, and pointer-plus-length acceptance port. Conversion to a
      raw pointer or unchecked bulk copy remains an explicit `unsafe` boundary.
- [ ] **`@jit` trace checker.** NYI analysis behind the pragma, which is
      likewise reserved and erroring today (`src/nupp/compiler/annotations.nupp:201`).
      Depends on nothing above except the marking pass it shares with the
      callback lint.
- [ ] Struct unions and bitfields (tagged C union lowering); malloc-backed big
      arrays. Fixed arrays `T[N]` landed.
- [ ] **A generalized `Serializable`, because reifying currently makes
      serializing worse.** Superseded in part by layout.md, which takes the
      reflection half; what stays open here is whether anything above it is
      wanted at all. A `struct` instance is cdata, and cdata is where the
      table-shaped world stops: `string.buffer.encode` raises `cannot serialize
      'cdata'` and offers no hook to install, `pairs` needs a `__pairs` on the
      metatype, and `type` answers `"cdata"`. So the largest speedup the
      language has is also the change that breaks the snapshot path, and
      `reifiable-record` (NUPP2509) has to warn about it rather than recommend
      it freely.

      The inversion available: nupp knows the field set and the C layout, so a
      reified value can serialize by copying its bytes rather than by walking
      its keys. Done properly, reifying makes serialization *faster* than the
      table it replaced, and the cost story turns into a reason.

      What has to be decided, roughly in order: whether the contract is an
      interface a declaration opts into or something every reifiable
      declaration gets; whether the wire form is layout-compatible bytes
      (fast, and hostage to field order, padding and endianness) or a described
      encoding that survives a layout change; how a graph with cycles and
      sharing is handled, since `string.buffer.encode` refuses both; and what
      a version skew between writer and reader is supposed to do.

      Do not design this from the declaration inward. tecs is the workload —
      "everything can serialize", world-wide snapshots, and fast — so
      `FFIStorage.tl` and `FFIEvents.tl` in the acceptance port
      (tests/acceptance/tecs) are what say which of the above actually matter.
      Two options short of it stay open meanwhile: a generated `__pairs` from
      the declared field set, which is cheap and restores iteration, and a
      generated conversion for crossing a boundary that only speaks tables.

## Ownership and resource scopes

- [x] **Cleanup functions are resolved references, not spellings.** Cleanup
      metadata is structured and carries a deterministic module-and-definition
      key. The producer registers its private function object; a consumer
      resolves it lazily on first discharge and then calls the cached upvalue.
      Lazy resolution preserves load order when a consumer module exists before
      the producer runs. This removes NUPP2620 and lets `nupp.resources` owners,
      C pointers, and other foreign values cross modules without publishing
      their cleanup functions.
- [x] **`@drop` registration is idempotent across module rechecks.** Every
      inline, declared, external, or inherited default drop operation now reaches one
      deduplicating operation. A cross-module regression runs `check`, `build`,
      and the program, proving that revisiting the exported nominal does not
      turn its one drop operation into an ambiguous pair.
- [x] **Cleanup context is explicit owner state.** Ownership annotations erase,
      so a raw pointer has nowhere to retain a dynamic allocator, arena, or
      parent handle. Model `{context, value}` as a nominal record or struct and
      give it an `@drop` method that calls `ctx_free(self.context,
      self.value)`. This uses the existing affine nominal path, preserves raw
      pointer identity, and introduces neither a hidden side table nor a closure
      per owner. The ownership reference documents the FFI pattern.

## Editor and docs tooling

- [ ] **Completion is receiver-correct but scope-blind.** After a `.` or `:`
      the answer is already what that receiver holds and nothing else. What is
      left: lexical-scope filtering of the ambient list —
      `src/nupp/compiler/lsp/complete.nupp:470`
      filters by source offset alone, so every file symbol is offered
      regardless of enclosing block; the synthesized `ffi.C` namespace, which
      `resolveReceiver` cannot reach even though cdef structs already carry
      `byname`; callable snippets, which need `insertTextFormat` and are absent
      entirely; and module-path completion inside a `require` string. Required
      project modules themselves are now included in the ambient list.
- [ ] **Cancellation, stale results and multi-root.** `$/cancelRequest` is
      registered as a no-op (`src/nupp/compiler/lsp/init.nupp:916`), so it is understood
      only in the sense of not erroring; cancelling work in flight needs input
      readable without blocking, which this loop does not have. Graceful
      stale-request results need request-id tracking, which nothing does.
      Workspace folders are read and re-root correctly but collapse into one
      session, so real multi-root remains — see
      [plan.md](plan.md#lsp-follow-up).
- [ ] **Doc comments as checked grammar.** `@param` parses
      (`src/nupp/compiler/docblock.nupp:23`) and renders, but nothing verifies the names
      against the real parameter list — `@raises` is the only tag any checker
      reads. Symbol cross-references have landed using Markdown's
      `[](symbol)` form rather than the proposed `[[Type]]` spelling.
- [ ] **Docgen JSON output mode.** Static HTML landed (`nupp doc site`,
      `src/nupp/compiler/doc/html.nupp`). What external site generators need is a
      doc-model JSON emitter; `--format json` today is only the CLI's own
      report shape, which `src/nupp/compiler/cli/doc.nupp:40` says outright.
- [ ] **`nupp doc` never removes what it stopped writing.** A module build
      records its outputs and deletes the ones a later build did not produce
      (`src/nupp/compiler/build/project.nupp:188`); the docs target returns at line 161,
      before any of that runs. So a page keeps its rendered HTML after its
      route changes or its source is deleted. Restructuring this site left a
      whole `build/docs/guide/` tree behind, still serving pages whose links
      pointed at files that had moved — a link checker run over the output
      found them and they looked real, which is worse than a 404. The list is
      already in hand: `doc.files.collect` (`src/nupp/compiler/doc/files.nupp:25`)
      records every written path for `--json`. The docs path needs to store it
      and remove the difference.

## Build, codegen and distribution

- [ ] **`--gen-target` guardrails for struct modules** (plan §4: no silent
      erasure). No such flag exists yet; the only target flag is the manifest's
      `--target`.
- [ ] **`nupp doc` picks between two docs targets by hash order.** With no
      top-level `docs` table, `manifestSettings` returns the first
      `kind = "docs"` target `pairs()` reaches
      (`src/nupp/compiler/doc/init.nupp:804`), and `pairs()` does not promise an order.
      Two targets named `alpha` and `zulu` sent five consecutive runs to
      `out-zulu`, `out-alpha`, `out-zulu`, `out-alpha`, `out-alpha`. The
      command has no `--target`, so there is no way to say which was meant
      either. Either sort and take the first, prefer `build.default` when it
      names a docs target, or refuse and ask — but not this.
- [ ] **An unknown key in most of the manifest is still ignored.** Closed key
      sets cover the docs target, its pages, hero actions, features, and
      `config.fmt` (`src/nupp/compiler/build/manifest.nupp:193,420`). Everywhere else
      — top level, module targets, dependencies — a typo is silently accepted.
      The docs target got the closed set because the generator reads keys the
      build's validation knows nothing about; the argument is weaker elsewhere,
      but "this configures nothing" is worth saying wherever it is true.
- [ ] **`nupp.lua`'s `syntax` and `runtimeTarget` configure nothing.** Neither
      key appears anywhere in `src/`, and neither is validated, so a manifest
      setting them is a silent no-op. Manifest-level `strict`, by contrast, is
      explicitly rejected because file extensions and `--strict` own that
      policy.
- [ ] **Single-binary host.** LuaJIT, lua-cjson and luautf8 are pinned by
      revision and SHA-256 and built from source by `host/build.rs`, not
      committed. LPeg is no longer a host C dependency; the compatible runtime
      is generated Lua. `cjson`/`cjson.safe` are registered in
      `package.preload`; the binary container, trailer, stamping, pinned
      revision metadata, and a compiler-built current-platform `stub = "nupp"`
      are implemented. What remains:
  - [ ] decide whether pinned-and-fetched is enough or the sources should be
        vendored in-tree (plan.md §Distribution said vendored)
  - [ ] strict JSON numbers and explicit empty array/object semantics are set
        per call site on the Nupp side, not in the host
  - [ ] malformed-input fuzzing and replay through a stamped host binary;
        framed stdio and recorded-session LSP replay already have coverage
  - [ ] dependency MIT license notices in `host/`
  - [ ] cross-target stub selection and shipped per-platform stubs; a binary
        target still has no target list or cross-build selection
- [ ] Hot-reload typing; the `nupp-cargo` Rust helper.

## Dialect interop (`import-tl`)

Design in plan.md §Dialect interop. Nothing is implemented: no `.tl` handling
in module resolution, no translator subcommand, no `.tl` build input mode.

- [ ] declaration reader (.d.tl subset → interned types, wired into module
      resolution)
- [ ] source translator CLI (eject model, visible residue comments, `any`
      fallbacks), translating metamethod declarations, `record X is Y`,
      bounded generics, nested type namespaces, and `self` directly into their
      landed nupp forms
- [ ] build-system `.tl` input mode for mixed trees
- [ ] expose macroexp-produced protocol declarations explicitly during
      translation; tecs's generated `DoubleArray.__len` must become a visible
      contract rather than being attributed to comptime
- [ ] runtime-equivalence verification against the tecs subsystem corpus

## Diagnostics

- [ ] **`@deprecated` API metadata.** Allow functions, methods, fields, types,
      and module members to name an optional reason and replacement. Report a
      suppressible use-site lint; carry the metadata through module interfaces;
      expose the LSP `deprecated` tag/modifier in completion, hover, and
      semantic tokens; and render it in generated documentation. The annotation
      affects tooling only and emits no runtime behavior. Nothing exists today.
- [ ] **The `pedantic` category has no members**, so setting it in `nupp.lua`
      moves nothing. (`style` has one now, `customary-operator`.)
- [ ] **Report an `@allow` that silenced nothing**, so stale suppressions get
      removed rather than accumulating. Nothing tracks whether a suppression
      fired (`src/nupp/compiler/check/pragma.nupp:394`).
- [ ] **Grow the worked examples in `explain.nupp`.** Forty codes now have
      dedicated entries and thirty-two have a `wrong`/`right` pair; every other
      code answers through its family, which states the rule but cannot show
      the mistake. Two things lean on that table: `nupp explain` is the
      retrieval path a reader reaches from a diagnostic's `docs` anchor, and
      `nupp reference` lists the codes an example can say more about. Both get
      better per entry added, and `tests/explaintest.lua` compiles each pair, so
      an entry cannot be added wrongly. The eleven the reference cites and
      cannot yet expand are
      NUPP2002, NUPP2101, NUPP2108, NUPP2118, NUPP2120, NUPP2203, NUPP2504,
      NUPP2506, NUPP2603, NUPP2610 and NUPP2615: a reader is pointed at those
      having just met the construct, so they are worth the most per entry.

## Formatting

- [ ] **The tree is not `fmt`-clean, and it is not obvious which side is
      wrong.** An August 10 direct formatter scan found 62 of 154 project
      sources non-clean. Only seven of those contained a same-line
      `then ... return ... end`, so the old claim that guard clauses accounted
      for almost all drift was wrong. Either the house style or formatter rules
      have to give, and that is a taste decision rather than a defect. Recount
      with the ordinary command once its bootstrap and generated compiler agree
      again rather than treating these figures as a permanent baseline.

      Reformatting is not a free mechanical pass, which is the part worth
      knowing before starting: generated Lua preserves the source line count,
      so moving a statement to a new line changes every artifact the compiler
      emits, which changes the compiler's own build, which means
      `fixpoint --update-bootstrap` and a new tracked `bootstrap/nupp.lua` in
      the same commit. Until it is settled, `nupp fmt` cannot gate this
      repository.
- [ ] **There is no formatter corpus directory.** `tests/fmtcorpus/` does not
      exist; coverage is inline assertions in `tests/fmttest.lua` and
      `tests/fmtwidthtest.lua`, `tests/typedtest.lua`, and several syntax-specific
      suites, plus a fixed 14-entry idempotency list. Collect golden input +
      expected files under the PLAN doctrine (120/88/4, one-arg-per-line), run
      through idempotency and parse-stability in addition to exact match.
      Existing inline coverage per category is noted where it exists:
  - [ ] Comment placement: have leading/trailing and comment-only files plus
        doc-comment blocks before declarations; need `if`/`elseif` arms and
        comments inside table constructors.
  - [ ] Blank-line policy: have the 3+ collapse and coverage around functions;
        need between record fields and at the top of a file.
  - [ ] Long lines: have call arguments, params, binary-op chains, ternaries;
        need chained method calls (`report:put(...):putf(...)`), long union
        annotations, long generic parameter lists.
  - [ ] Tables: have break-when-long and indentation; need the inline-vs-
        multiline threshold pinned, nested tables, mixed array/named fields,
        trailing separators, and a chosen alignment doctrine.
  - [ ] Typed layer: locals, maps, generics, return packs, optional tightness,
        record bounds and `is`/`where`, metamethods, and inline methods have
        inline coverage. Consolidate every annotation position into the corpus
        and add cdef blocks, where C-name fields with underscores stay untouched.
  - [ ] Short functions: have pipe spacing, single-param, no-param, vararg, as
        call argument; need `-> do` blocks and nested/curried chains.
  - [ ] Interpolated strings: one `${1 + 2}` assert. Need multiline templates
        (never reflowed), nested templates, escapes.
  - [ ] Statements: have guard-clause expansion, numeric-for, goto; need
        semicolon statements.
  - [ ] Pathological: have unbreakable long lines, hashbang, unicode. Need
        CRLF input (nothing in the formatter or its tests mentions `\r\n` at
        all), deeply nested expressions at the wrap boundary, one-line whole
        programs.
  - [ ] Idempotency fuzz: the current pass is a deterministic fixed list, not
        fuzz. Random input, minimized failures checked in as regression
        fixtures.

## Performance and incrementality

Landed: cache keys are digested with XXH64 rather than a pure-Lua SHA-256, the
prelude no longer builds the project index on the way to every command, project
headers are stored between commands (`nupp.compiler.build.store`, plain data via
`string.buffer`, in the gitignored build directory), `nupp check` reuses
unchanged modules and replays their diagnostics, bundled module declarations are
checked when something asks for one, `nupp fmt` stores each file's formatting
verdict, the editor session writes what it worked out on shutdown, and the
project scan prunes dot-directories instead of walking the whole checkout and
discarding it.

Historical August 7 measurements, before native file adoption and the later
type-system work: whole-project check 0.15 s against 1.26 s cold; `fmt --check`
0.15 s; no-op build 0.18 s; `lsp inspect` 0.13 s. The measured startup floor was
23 ms, against 2 ms for a bare `luajit -e ""`. Remeasure before using these as
current priorities.

What is left, in the order the numbers justify:

- [ ] **Remeasure and remove the remaining warm-command subprocesses.** Native
      file adoption removed `nupp.compiler.fs` listing and `mkdir` shell-outs,
      so the old count of seven subprocesses and six `find` calls is obsolete.
      Project discovery still shells out in `env.nupp`, its source and project
      views can still list separately, `bin/nupp` still uses `find | head` while
      locating inputs, and `process.capture` still creates and removes an
      `os.tmpname` file per call. Measure the new floor before deciding whether
      caching or a native discovery path is worth its invalidation cost.
- [ ] **`nupp check FILE` has no per-module reuse at all.**
      `src/nupp/compiler/cli/check.nupp:50` re-parses and re-checks the named file
      unconditionally; only the header index is cached. On August 7 the 0.14 s
      figure was the startup-plus-index floor measured on a small file, while
      `src/nupp/compiler/env.nupp` cost 0.82–0.93 s on every warm run. Remeasure
      the cost, but the missing reuse mechanism remains.
- [ ] **Cross-process cutoff is at the module, not the interface.** A body edit
      stops at an unchanged interface, because the interface digest is recorded
      and compared. But any edit to an exported *type declaration* changes
      `projectIndexHash`, which disables reuse for the whole project: the digest
      covers each declaration's `cst.textOf` (`src/nupp/compiler/env.nupp:569`), which
      emits leading trivia, so reformatting a docblock above a record rechecks
      everything. The other half of the same mechanism is `typeFingerprint`,
      which describes a nominal by its declaration kind and name and
      deliberately does not expand members (`src/nupp/compiler/build/modules.nupp:151`) —
      correct in itself, but it means the interface digest leans entirely on
      `projectIndexHash` to notice a changed record. Narrow the digest to what
      a dependent can actually observe and make the two one mechanism rather
      than two that happen to cover each other.
- [ ] **The prelude image, if its cost becomes worth it.** `env.new` measured
      11.7 ms on August 7, all of it parsing and checking `prelude.d.nupp` on
      every command. Storing the result means storing a cyclic type graph, which
      `string.buffer.encode` cannot do — it rejects cycles and does not
      preserve sharing — so it needs a codec that assigns object ids and
      rebuilds by reference. The delicate part is not the codec but
      `types.nupp`'s arena: every structural type is interned under its
      canonical `id`, and a restored graph has to be rewritten to whatever the
      arena already holds before anything compares two types by identity. Get
      that wrong and the interface cutoff either stops cutting off or starts
      cutting off things that differ. Eleven milliseconds against the most
      identity-sensitive machinery in the compiler is a bad trade today; it
      becomes a good one if the floor drops further or the graph grows.
- [ ] **The store never shrinks below what a run touched.** `KEEP_COLD = 2048`
      (`src/nupp/compiler/build/store.nupp:36`) bounds the cold entries, which is fine
      for a project this size and unmeasured for a large one.

## Testing and CI

- [ ] **Complete the operator-contract matrix.** Only `__add` has a direct
      contract test (`tests/checktest.lua:319`); no test anywhere mentions
      `__unm`, `__sub`, `__mul`, `__div`, `__mod`, `__pow`, `__lt`, `__le`,
      `__concat` or `__eq` dispatch. The table under test is
      `operators.metamethod`/`contractMetamethod`
      (`src/nupp/compiler/check/operators.nupp:45`). Needed: unary minus, subtraction,
      multiplication, division, modulo, power, right-hand fallback, and
      comparison reversal/`__lt` fallback for `<=`.
- [ ] **CI matrix** (GitHub Actions). The process-only Windows job is the first
      executable slice; the project-wide matrix remains. Add macOS + Linux,
      LuaJIT 2.1 rolling (2.1.1784535649 is the floor) + (when released) 3.0;
      run `./tests/run`, the tl.lua oracle, and import-c fixture tests; track
      `bench/reification.lua` and `bench/aos.nupp` numbers as an artifact per
      commit (regression fence around the reification speedup).
- [ ] **Fuzzing.** No corpus exists — `tests/corpustest.lua` is an oracle over
      two hardcoded external paths, skipped when absent. Grow a random-input
      corpus for lexer/parser round-trip and fmt idempotency (`fmt∘fmt = fmt`,
      `parse∘fmt = parse`); minimize and check in failures as regression
      fixtures.
- [ ] **Every lint has to be exercised, by construction.** All twelve have a
      test today, but nothing enforces it: the next one can land untested and
      the suite stays green. `tests/allowtest.lua:everyLintIsWellFormed`
      already iterates `check.lints` to check each entry's shape, so the missing
      half is a fixture table keyed by code — one source that must report it,
      one neighbouring source that must not — driven off the same registry, so
      a lint with no fixture fails the run rather than being noticed later.

      Both halves matter. `reifiable-record` was written whitelist-first and
      the silent cases are most of its value; a lint with only a positive test
      passes while firing on everything.
- [x] **Attribute the intermittent `luajit tests/run.lua` libunwind
      segfault.** It is not a Nupp runner defect. Retired macOS reports carry
      the same signature across unrelated projects and Codex sessions from
      August 4 onward, before this Process work and outside this repository.

      ```
      EXC_BAD_ACCESS  KERN_INVALID_ADDRESS at 0x8
        libunwind.dylib   unw_set_reg
        luajit            ?
        libunwind.dylib   _Unwind_RaiseException
        luajit            lua_pcall
        luajit            lua_cpcall
      ```

      So: an error being raised through LuaJIT's external unwinder, which then
      dereferences near-null in the system library. LuaJIT's own `lj_err.c`
      states the constraint: external unwinding requires correct unwind tables
      for every transitive C frame between the catch and throw. Nupp cannot
      enforce that property on every native library loaded into the host.

      Upstream supplies the escape hatch rather than requiring a runner
      change: build LuaJIT with
      `TARGET_XCFLAGS=-DLUAJIT_UNWIND_INTERNAL`. An upstream checkout built that
      way completed the whole Nupp suite on this machine; it needs its matching
      `src/jit` Lua modules on `LUA_PATH`, not Homebrew's modules from a
      different VM build. Keep external unwinding only where C++ exception
      interoperability is required and the whole native stack is known to
      carry conforming tables.

      What it is not: a wrong answer. The suite passes on the runs that
      complete, and `fixpoint` has never been affected. What it costs is a CI
      job failing at random, which is why it is worth a note rather than a
      shrug.

      Leads, in the order worth trying: reproduce under a LuaJIT built with
      assertions, or with `MallocStackLogging=1` for a real backtrace; check
      whether it correlates with the tests that deliberately raise; and see
      whether a LuaJIT newer than 2.1.1785577137 has touched arm64 unwinding.
      Re-running the suite has stopped being informative — it reproduces about
      as often as a coin lands heads three times, which is enough to be sure it
      is real and not enough to bisect by hand.
- [ ] **`tests/profiletest.lua traceRecordsWhereTheCompilerGaveUp` is
      flaky.** Recorded failing once in six runs with "unrecordable bytecode
      must be reported"; it depends on the JIT attempting and aborting a trace
      within 3000 iterations after `jit.flush()`. Sixteen consecutive runs pass
      today, so the rate is lower than recorded or machine-dependent — but a
      test whose result depends on trace timing will keep costing somebody a
      bisect.

## Acceptance: the tecs subsystem port

Translating and running `internal/ffi/FFIStorage` and its components is the
v0.1 gate, and it is the acceptance corpus several items above name: bounded
generic metatable receivers, bounds-carrying spans, the callback `jit.off`
lint, and dialect-interop runtime equivalence.

The port has started: `tests/acceptance/tecs` holds it, with `PORT.md` logging
what fought back. It is a running port, not a reading exercise — `run.nupp`
exercises the translated modules, and two compiler bugs were found by running
what checked clean.

```
 file                     lines  state
 ───────────────────────  ─────  ────────────────
 schema.tl                   49  ported, runs
 StableChunkedArray.tl       94  ported, runs
 init.tl                    111  not started
 EpochArena.tl              116  not started
 FFIEvents.tl               200  not started
 FFIStorage.tl              706  not started
```

- [ ] **Translate the four remaining files.** 143 of 1276 lines are done, and
      they are the two with the least FFI in them, so nothing about reification
      or a struct not being a table has come up yet. `FFIStorage.tl` is the
      schema-to-cdata layer and the file the gate actually names; `FFIEvents.tl`
      is the event storage the metatable and prototype work was aimed at; and
      `EpochArena.tl` is the owned growable buffer the bounds-carrying spans
      item above wants.
- [ ] **Two frictions the port logged and nobody has fixed.** No table literal
      infers into a tuple type in any position, including a directly annotated
      binding, so every Teal-idiomatic `{string, string}` needs a cast at each
      site. And integer arithmetic widens, so a `%` result cannot key a
      `{[integer]: _}` without `as integer`. Both are in `PORT.md` with repros.
- [ ] Focused fixtures cover tecs-style nested event records, bounded
      registration, late `__call` installation, generic `__index`/`__newindex`,
      and arithmetic contracts (`tests/gentest.lua:152`,
      `tests/checktest.lua:276`).
