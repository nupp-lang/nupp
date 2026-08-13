# Hardening hot-reload

Status: R1-R3 implemented; R4-R6 remain. The current
implementation safely patches compatible named function bodies, rechecks loaded
Nupp modules, and conservatively treats changed C declarations as restart-only.
This plan closes the remaining gaps between that implementation and the public
documentation: external header observation, explicit native-library identity,
extensible semantic inputs, precise C dependency comparison, and executable
coverage for every guarantee.

## Outcome

A watch session must make one of four honest decisions for every observed
change:

1. commit a compatible function-body generation atomically;
2. reject a candidate with syntax, type, or generation diagnostics;
3. require a process restart before changed runtime structure or native ABI can
   take effect; or
4. report no semantic change.

It must not miss a file that contributed to a loaded module's checked meaning,
and it must not describe a native binary as validated when Nupp has only
validated its declarations. Detection of a changed native artifact results in
`restart-required`; Nupp will not unload or replace a C library inside the live
VM.

Normal builds remain a separate target. With watch mode absent, generated Lua
must remain byte-identical and must contain no slot dispatch, manifests,
watchers, external-input registry, polling, native hashing, or reload runtime.

## Guarantees and boundary

For a successfully loaded watch generation, Nupp guarantees:

- every loaded Nupp module is revalidated through the incremental semantic
  graph before a patch is staged;
- every filesystem input explicitly observed while checking those modules is
  part of the session's dynamic watch set;
- a retained observed input whose meaning changes either rejects the candidate
  or requires restart before a body patch can commit;
- a configured native artifact is identified by the exact file loaded in watch
  mode, and changing that file requires restart;
- an unconfigured loader name such as `ffi.load("mini")` is reported as an
  unverified binary identity rather than being covered by a stronger claim;
- a rejected or restart-only candidate cannot mutate slots, generation state,
  module tables, FFI declarations, or existing values; and
- ordinary, non-watch generated programs retain their current bytes and runtime
  behavior.

The guarantee does not prove that a C implementation matches a header. A header
describes a contract; only the library author, an explicit ABI-version contract,
or an external ABI inspection tool can establish that the binary honors it.
Likewise, `poll()` remains a cooperative boundary selected by the program. Nupp
can make committing atomic at that boundary, but cannot infer whether the
application has partially applied a logical update.

Only Nupp-visible structure participates. A component, schema, generated
declaration, or native layout is protected when its provider records a semantic
input or exposes it through checked declarations; arbitrary state hidden behind
an untyped Lua or C boundary is outside the guarantee.

## Deliberate non-goals

- `dlclose`, in-process shared-library replacement, or rebinding old cdata,
  callbacks, function pointers, and native state to a new library image.
- Automatic migration of Lua, record, struct, cdata, or external application
  state after a structural change.
- Claiming that a bare soname identifies a stable file across platform loader
  search paths, environment variables, framework lookup, or already-loaded
  images.
- Preempting a running call or choosing a safe application commit boundary.
- Making watch-mode `-O0` bodies representative of optimized release output.
- Reducing conservative restart decisions before dependency completeness is
  proved.

An optional supervisor may later restart the process after a restart result,
but that is process replacement, not hot reload. State restoration would need a
separate application-owned serialization and migration protocol.

## Current gaps

The current implementation has four concrete gaps:

1. `src/nupp/compiler/cli/run.nupp` polls
   `env.listProjectFiles`, which enumerates Nupp project sources but not headers
   read by `cheader`. Editing only a header therefore does not wake the session.
2. `hot_session.g.nupp` fingerprints the C declaration text recovered during a
   Nupp source recheck, but does not identify or observe the shared library that
   implements those declarations.
3. C fingerprinting is module-wide and token-based. It is safe, but an unrelated
   declaration edit in a loaded module may require restart even when no retained
   body or runtime binding depends on it.
4. The documentation describes several safety properties, but there is no
   single matrix connecting each claim to a session test, runtime test, and
   standalone watcher test.

The existing semantic snapshot and conservative C fingerprint remain the
fallback until the replacements below meet their exit gates.

## External-input model

Add one compiler-owned description for a non-module input observed during
checking:

```text
ExternalInput
  identity       stable kind-specific identity
  kind           header | native-artifact | provider-file | generated-input
  display        authored or diagnostic name
  paths          canonical filesystem paths to observe
  fingerprint    canonical semantic or content digest
  consumer       checked module and declaration/site identity
  binary         whether a change can only be applied by process restart
```

Inputs are keyed records, not a single project-wide digest. This lets the
candidate comparison stop at the actual dependency boundary and lets a
diagnostic name the input and consumer that forced a restart.

The incremental checker owns the relationship between a module query and the
inputs it observed. The hot session owns the running snapshot of inputs for
successfully loaded modules. The standalone watcher owns only filesystem
observation; it asks the session for paths rather than rediscovering semantic
dependencies itself.

Conceptually, extend the session surface with:

```nupp
record hotreload.WatchedInput
    path: string
    kind: string
end

record hotreload.Session
    -- Existing source invalidation, generalized to any observed path.
    diskChanged: function(self: hotreload.Session, path: string, changeType: integer)

    -- The union of project sources and external inputs needed by loaded modules.
    watchedInputs: function(self: hotreload.Session): {hotreload.WatchedInput}
end
```

`watchedInputs` is a snapshot and may grow or shrink after a module loads or a
candidate is checked. `run --watch` refreshes it after `loaded`, `prepare`, and
`committed`. A changed external path invalidates the input query and all
consumers, exactly as a changed Nupp source invalidates its file query.

The session compares the candidate input map with the last committed map:

- a missing retained input is a diagnostic or restart, never `no-change`;
- the same identity with a new semantic fingerprint follows the consumer's
  ordinary compatibility rules;
- a new input used only by an unloaded module waits for that module's initial
  load;
- removing a dependency is allowed only when the candidate body no longer uses
  it and no retained runtime binding was created from it; and
- a `binary` input change always returns `restart-required`.

All paths are normalized once against the project root and the consuming source
file. Diagnostics retain the authored spelling as `display`, but equality and
watching use the canonical path. Duplicate paths reached through different
spellings collapse without collapsing their distinct consumer records.

## Header tracking

`cheader.load` must return provenance as well as declarations:

```text
Header
  exports
  cdef
  sourcePath
  dependencies
  semanticFingerprint
```

For a header read without preprocessing, `dependencies` contains the resolved
header itself. Direct mode strips includes, so it must not claim that ignored
headers contributed meaning.

For a `cheader` call whose third argument selects `"preprocess"`, run the
configured compiler's dependency generation beside preprocessing and record
the complete include closure that contributed to the preprocessed text. Use an
argv-based subprocess rather than constructing a shell command from a header
path. Preserve the compiler binary, flags, target ABI, and version in the
semantic fingerprint because any of those can change the parsed declarations
without changing a header byte.

The checked `cheader` call records the resolved source path, include closure,
library name, and canonical declaration fingerprint on its CST/result node.
`semanticSnapshot` incorporates keyed header inputs instead of discovering
header text by walking tokens. A comment-only header edit may wake and recheck
the session, but if the parsed declarations are identical it answers
`no-change`; changed layout, symbol, calling convention, or callable type
requires restart and names the header and consuming module.

Dependency discovery failure is a candidate diagnostic. It must not silently
fall back to watching only the primary file for a preprocessed header, because
that would restore the missed-change hole this milestone exists to close.

## Native artifact identity

Declarations and binaries are separate inputs. Add an optional watch-only
library map in `nupp.lua`:

```lua
return {
  hotReload = {
    libraries = {
      mini = "build/lib/libmini.dylib",
    },
  },
}
```

The key is the authored library name used by `cdef ... from "mini"`,
`cheader(..., "mini")`, or a statically known `ffi.load("mini")`. The value
resolves relative to the project root. In a watch build, generation loads that
exact canonical file for the mapped name, so the artifact Nupp hashes is the
artifact the VM receives. Normal generation continues to emit the authored
loader name and does not consult or embed the watch mapping. A dynamically
computed `ffi.load` argument cannot be mapped or observed and is reported as an
untracked native input in watch mode.

The native input fingerprint contains the canonical path, file bytes, target
platform and architecture. The watcher observes both the configured path and
its resolved target so atomic replacement and symlink retargeting are visible.
Any content change, disappearance, or identity change produces
`restart-required` before a Lua body patch stages. The diagnostic says that the
old library may already own cdata, callbacks, function pointers, and native
state, so the process must restart.

A bare library name with no mapping remains legal. On the first loaded use,
watch mode emits one concise notice that C declarations are checked but the
binary identity is unverified. The public documentation must make the same
distinction. The implementation must not guess a path by searching common
library directories: that can disagree with the platform loader or an image
already present in the process.

As a later opt-in extension, a map entry may name an ABI probe exported by the
library. Run that probe in a helper process, not the watched VM, and compare its
result with an expected binding fingerprint. This can detect a binary/header
contract mismatch, but it does not make in-process replacement safe and does
not replace artifact observation.

## Precise C dependency comparison

Replace the current module-wide token digest only after checked results expose
a complete keyed C ABI map:

```text
CDeclaration
  identity       aggregate tag, typedef, or library-plus-symbol
  semantic       canonical physical ABI and Nupp ownership contract
  origin         cdef site or resolved header
  consumers      top level and stable function identities
```

Canonical semantics include aggregate kind, ordered field names, offsets,
sizes and alignments; function calling convention, parameter and result ABI,
varargs and symbol spelling; library identity; and Nupp-side ownership,
borrowing, retention, cleanup, and nullability contracts. Source formatting,
comments, and declaration order do not belong in the digest unless order
changes meaning.

Generation records which declarations created runtime bindings at initial
module execution and which declarations each patchable implementation uses.
Candidate comparison then follows these rules:

- changing a declaration used by a retained runtime binding or old/new
  implementation requires restart;
- using a declaration that was not installed during the module's initial load
  requires restart rather than emitting a body that expects missing FFI state;
- removing a declaration still used by an old or candidate implementation
  requires restart;
- an unrelated declaration with no runtime binding or function consumer does
  not force restart; and
- any unresolved or unclassified C use falls back to the current module-wide
  restart rule.

The fallback is load-bearing. Precision may remove false restarts, but an
incomplete use graph must never turn a required restart into an accepted patch.

## Provider and generated semantic inputs

Generalize the same mechanism for compiler features that read schemas,
generated declarations, interface descriptions, or other files outside the
Nupp module list. A provider result may return `inputs`, each with a stable
identity, paths, and semantic fingerprint. The incremental query records those
inputs against the consuming declaration, and hot reload treats their changes
like any other semantic dependency.

The first public protocol should support immutable filesystem inputs only. Do
not accept arbitrary callbacks or mutable Lua tables as fingerprints: they are
not replayable, cacheable, or independently observable. Network resources,
environment variables, clocks, and process-global state require explicit
snapshot adapters before they can participate in the guarantee.

If an existing provider cannot enumerate an external input it reads, watch mode
reports that provider as untracked rather than claiming complete observation.
This makes the boundary visible while providers migrate to the protocol.

## Diagnostics and result shape

Keep the existing four result kinds, but give restart and rejection diagnostics
structured reasons suitable for the CLI and an embedding host:

```text
reason.kind
  source-structure
  callable-abi
  capture-set
  semantic-dependency
  header-abi
  native-artifact
  untracked-input
```

Every external-input diagnostic names:

- the input path or loader name;
- the declaration, function, or module that retained it;
- whether Nupp observed source declarations, binary bytes, or both; and
- why retrying the patch cannot update the already-running VM.

An affine restart continues to name the exact capture that selected affine
lowering. A generic "layout changed" message is insufficient when the changed
layout came from a header or provider; report the originating input and the
checked declaration that consumed it.

## Documentation guarantee matrix

Maintain a table in the test suite whose rows correspond to the public
hot-reload claims. Each row names at least one executable test:

| Claim | Required coverage |
| --- | --- |
| Compatible named body edit commits | session plus runtime slot test |
| Syntax/type error preserves old generation | session and CLI watcher test |
| Top-level, signature, capture, or affine change restarts | session tests |
| Loaded transitive Nupp dependency is rechecked | multi-module session test |
| Direct header edit is observed | standalone watcher test |
| Preprocessed included-header edit is observed | dependency-closure test |
| Header ABI change restarts before staging | session plus runtime-state test |
| Comment-only header edit does not restart | semantic fingerprint test |
| Configured native artifact change restarts | watcher test with a temporary library |
| Bare library identity is explicitly unverified | diagnostic test |
| Unrelated tracked declaration does not restart | keyed dependency test |
| Active call/self-recursion semantics stay frozen | runtime generation test |
| No `poll` means no commit | standalone behavior test |
| Non-watch output has zero reload machinery | byte-for-byte generation test |

Where a platform compiler is required, build the smallest temporary shared
library and skip only when that toolchain is genuinely unavailable. Never make
the native test depend on a globally installed project library. Standalone
watcher tests must bound their polls and subprocess lifetime so a failure cannot
hang the suite.

Public documentation is changed only when the corresponding row passes. It
must distinguish:

- Nupp declarations from native binary implementations;
- detected restart-only changes from in-process replacement;
- Nupp-visible layouts from opaque external state;
- compiler atomicity from the program's responsibility to choose `poll`; and
- `-O0` watch behavior from optimized release behavior.

## Implementation milestones

### R0: Freeze claims and test inventory

- Convert every sentence in `docs/tooling/hot-reload.md` that promises safety or
  observation into a row in the guarantee matrix.
- Mark the current implementation status of each row: covered, conservative,
  overstated, or outside the boundary.
- Add structured external-input and restart-reason records without changing the
  patch wire schema or normal generation.
- Preserve the existing module-wide C fingerprint as the fallback.

Exit gate: no public claim lacks a named test or an explicit boundary statement,
and the result schema can explain every hardening restart without parsing text.

### R1: Dynamic external inputs

- Add keyed external inputs to incremental query results and semantic snapshots.
- Add `Session:watchedInputs()` and invalidate external input queries through
  `diskChanged`.
- Replace the standalone watcher's fixed project-source scan with the dynamic
  union returned by the session.
- Refresh the union after lazy module load, candidate preparation, and commit.
- Cover add, edit, delete, dependency removal, duplicate spelling, and unloaded
  module cases.

Exit gate: changing any synthetic external input rechecks exactly its loaded
consumers, while unrelated modules remain cached and unloaded modules create no
slot patch.

### R2: Complete header observation

- Return canonical provenance and semantic fingerprints from `cheader.load`.
- Record a direct header as an external input.
- Record the complete compiler-reported include closure for preprocessed
  headers using an argv-safe subprocess.
- Move `semanticSnapshot` from CST token discovery to keyed header inputs.
- Add direct, nested include, deleted include, comment-only, layout, function ABI,
  and toolchain-fingerprint tests.

Exit gate: editing a retained header or contributing include without touching a
`.nupp` file wakes `run --watch`; semantic ABI changes require restart and
non-semantic edits do not.

### R3: Native artifact tracking

- Validate `hotReload.libraries` configuration and resolve mapped paths.
- Make watch generation load the exact mapped artifact while leaving normal
  generation byte-identical.
- Add binary inputs to loaded manifests and the dynamic watch set.
- Require restart for replacement, disappearance, symlink retargeting, or byte
  changes.
- Emit a once-per-library unverified-identity notice for unmapped loader names.

Exit gate: rebuilding a configured temporary shared library causes a restart
result before any Lua slot changes, while a bare name is never described as
binary-verified.

### R4: Keyed C ABI dependencies

- Export canonical C declaration identities and semantics from checking.
- Record top-level runtime bindings and per-function C uses in generation
  metadata.
- Compare only retained or candidate uses, with the module-wide digest as an
  explicit fallback for unknown uses.
- Test declaration formatting, reorderings, unrelated declarations, new uses,
  removed uses, ownership annotations, layouts, callbacks, and library names.

Exit gate: safe unrelated C edits answer `no-change` without weakening any case
that currently requires restart.

### R5: Provider input protocol

- Add filesystem input descriptors to provider results and incremental cache
  keys.
- Thread provider inputs into loaded semantic snapshots and watched paths.
- Diagnose providers that perform untracked external reads in watch mode where
  the compiler can identify them.
- Add a fixture provider whose schema change invalidates only its consumers.

Exit gate: a generated semantic input receives the same observe, recheck,
reject/restart, and diagnostic behavior as a Nupp declaration dependency.

### R6: Documentation and regression gate

- Update hot-reload documentation to the exact implemented boundary.
- Run the focused hot-reload, header, incremental, generator, and CLI suites.
- Run the full suite with a bounded worker count and run `./bin/nupp fixpoint`.
- Assert representative normal `-O0`, `-O1`, and `-O2` output is byte-identical
  before and after the hardening work.
- Keep the guarantee matrix in CI so a claim cannot outlive its test.

Exit gate: every implemented public claim has passing coverage, every remaining
limit is stated, full verification passes, and a non-watch artifact contains no
hardening metadata or runtime path.

## Recommended order

Implement R0 through R3 first. They close missed-change holes and make the
native boundary honest. R4 is a precision improvement and must follow the safe
conservative behavior. R5 extends the same proof to future semantic providers
without blocking header and native hardening. R6 lands with each milestone's
documentation changes and becomes the final release gate.

Do not combine in-process native replacement with these milestones. The safe
improvement is reliable detection followed by an explicit restart; stateful
native migration is a separate protocol with different invariants.
