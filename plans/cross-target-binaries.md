# Cross-target binary builds

> **Status: proposed. Not implemented.** `stub = "nupp"` still builds a host
> for the machine running the compiler. The release workflow builds three
> standalone compiler binaries on native runners, but those binaries are not a
> stub catalog the Nupp CLI can select.

## Decision

One computer running Nupp will be able to produce binaries for every supported
platform by compiling a target-specific payload and stamping it into a pinned,
prebuilt stub for that platform. Nupp will not claim that one local Rust
toolchain can compile every native host from source.

The first supported platform set is the set release CI already exercises:

- `x86_64-unknown-linux-gnu`;
- `aarch64-apple-darwin`; and
- `x86_64-pc-windows-msvc`.

Adding a platform means publishing and retaining its stub, teaching the
compiler its filename and executable suffix, modeling its compile-time C
layout, and running the same stamping and execution conformance tests. A layout
model by itself does not make a platform supported.

A binary target names platforms with a camelCase `platforms` field. The CLI
selects one with `--platform`, or all configured platforms with `--platform
all`. `--target` keeps naming the build target; platform and build-target
identity must not be overloaded.

The source-built current-platform path remains available. A target with no
`platforms` keeps today's behavior: `stub = "nupp"` compiles a feature-matched
host locally. Cross-target selection always uses a verified prebuilt stub.

## Why the bootstrap is not circular

The stub is only the Rust/LuaJIT host. The compiler and program payloads are
platform-neutral Lua, so stamping an already-built Linux, macOS or Windows stub
does not invoke that platform's linker or SDK. The compiler host's platform and
the payload target's platform are independent once the native stub exists.

Catalog publication does introduce a release-order constraint. A released
compiler may refer only to immutable stub assets which already exist, so release
N publishes the stubs and catalog release N+1 consumes. An unchanged `hostAbi`
may retain an older stub; a changed `hostAbi` needs native-runner stubs before a
compiler release can consume it. Source checkouts can always build their current
platform host while that next catalog is being prepared.

Every catalog-referenced stub must remain downloadable for as long as a released
compiler names it. Retention is therefore part of correctness, not release
housekeeping: deleting an old asset breaks a pinned released CLI.

## Why prebuilt stubs are the boundary

Stamping is platform-neutral. It copies an existing executable, appends one Lua
payload, and writes the fixed trailer. It does not parse ELF, Mach-O or PE and
does not need the target SDK.

Compiling the executable is not platform-neutral:

- the current Windows path invokes `msvcbuild.bat` and MSVC;
- linking Mach-O requires Apple's non-redistributable SDK;
- LuaJIT's Make build is not driven by Cargo's target selection; and
- native sidecars have their own target toolchains and system dependencies.

Prebuilding stubs on native CI keeps those constraints where they can be
satisfied. Once the resulting artifacts and digests exist, Linux, macOS or
Windows can stamp every target.

## Goals

1. Produce all configured supported-platform binaries from one `nupp build`
   invocation on any supported compiler host.
2. Authenticate every prebuilt stub before reading or executing it.
3. Compile target-sensitive payloads under the selected platform's layout,
   never under the compiler host by accident.
4. Preserve the current single-platform manifest and output behavior.
5. Work from a local artifact directory with network access disabled.
6. Make release artifacts, notices, checksums and platform support one
   versioned unit.
7. Refuse native dependencies for which no target artifact exists rather than
   emitting a binary that fails on another machine.
8. Keep the payload and trailer format independent of artifact acquisition.

## Non-goals

- Cross-linking Linux, macOS and Windows hosts from one Rust installation.
- Treating every target in `targetLayout.keys()` as a supported distribution
  platform.
- Downloading a mutable `latest` artifact or accepting an unverified CI
  artifact.
- Shelling out to `curl`, PowerShell or another optional system downloader from
  the released compiler.
- Absorbing arbitrary project C, Rust or LuaRock native libraries into the
  compiler-owned stub.
- Solving Apple notarization by weakening signature checks or asking users to
  disable Gatekeeper.
- Changing path-valued third-party stubs. They remain explicit local artifacts
  unless their owner supplies a separate catalog.

## Current baseline

- `build.targets.<name>.stub` is one string. `"nupp"` means compile the
  compiler-owned host; any other value is a project-relative path.
- `stage.hostStub` invokes Cargo without `--target`, reads
  `targetDir/release/nupp-host` or `.exe` according to `jit.os`, and therefore
  always returns a current-platform executable.
- `layoutTarget` already makes compile-time C layout independent of the
  compiler host, but it is not connected to binary platform selection.
- The release workflow builds Linux x86-64 and macOS arm64 binaries on their
  native runners. It extracts the Linux payload and stamps that payload into a
  Windows x86-64 host on a Windows runner.
- The trailer and payload are platform-neutral and the binary packaging
  fixpoint passes on the current platform.
- `project.build` calls `native.build` for every target kind. It therefore
  compiles and stages current-machine sidecars even when the eventual binary is
  meant for another platform.
- Features such as files and process have both a native sidecar and a compiler
  host feature. Path, URI, UUID, HTTP and SHA-256 are sidecar-only today.
- `stampFile` unconditionally invokes `chmod +x`, which cannot run on a Windows
  compiler host and applies the compiler host's mode operation rather than the
  output platform's rule.
- The released compiler host has files and process but no HTTP/TLS provider, so
  it cannot implement an in-process catalog download yet.
- `hostAbi` does not exist yet. The only current container identity is
  `PAYLOAD_VERSION = 1`; target-layout ABI is a separate concern.
- Release artifacts currently contain only executables. They do not carry the
  required notice tree, and the appended macOS binary is not notarizable under
  the current signing method.

## Manifest and CLI surface

A multi-platform target is an ordinary binary target with `platforms`:

```lua
return {
   build = {
      default = "app",
      targets = {
         app = {
            kind = "binary",
            entries = { "app.main" },
            stub = "nupp",
            platforms = {
               "x86_64-unknown-linux-gnu",
               "aarch64-apple-darwin",
               "x86_64-pc-windows-msvc",
            },
         },
      },
   },
}
```

The supported commands are:

```text
nupp build --target app --platform x86_64-pc-windows-msvc
nupp build --target app --platform all
nupp check --target app --platform aarch64-apple-darwin
nupp clean --target app --platform x86_64-unknown-linux-gnu
```

Rules:

- `platforms` is a non-empty, gap-free array of unique supported triples.
- `--platform NAME` must name a configured platform.
- `--platform all` is valid only for a target with `platforms`.
- With one configured platform and no option, that platform is selected.
- With several configured platforms and no option, `build` asks for an
  explicit platform rather than silently building one; release automation uses
  `--platform all`.
- `check` performs the target-sensitive check but writes no payload or stub.
- `clean --target NAME --platform NAME` removes only that platform's owned
  outputs. `clean --target NAME --platform all` removes every configured
  platform output. For compatibility, omitting `--platform` from `clean` removes
  all outputs owned by the named target; `--platform` without `--target` is an
  error.
- `layoutTarget`, when present on a cross-target binary, must equal the selected
  platform. Normally it is omitted and inferred from that platform.
- A binary platform must have a layout model. A layout model need not have a
  binary platform.
- Manifest and JSON field names remain camelCase. CLI flags retain the existing
  hyphenated command-line convention.

`nupp tasks --json` reports `platforms`, and the text form lists them beneath
the binary target. Build JSON adds `platform` to a single-platform result. An
`all` result has a `platforms` array whose entries each contain `platform`,
`status`, `outputs` and, on failure, `error`.

`--platform all` attempts every configured platform in manifest order. A
failure does not prevent independent later platforms from being checked or
stamped. Successful outputs and their state remain valid, every platform gets a
result entry, and the command exits non-zero when any entry failed. A rerun may
reuse the successful entries.

## Output layout

Today's literal `output` remains valid for a build which selects exactly one
platform. A multi-platform build rejects one literal `output`, because three
executables cannot truthfully occupy it.

The default multi-platform layout is:

```text
<outDir>/<targetName>/<platform>/<targetName><executableSuffix>
```

For example:

```text
build/app/x86_64-unknown-linux-gnu/app
build/app/aarch64-apple-darwin/app
build/app/x86_64-pc-windows-msvc/app.exe
```

If real projects require custom names, add a camelCase `platformOutputs` map
from configured platform to path. Do not put replacement tokens into `output`:
an unchecked string template makes collisions and escaping part of the build
contract.

Build cache keys, completion stamps, `produced.outputs`, cleanup ownership and
fixpoint paths all include the platform. A stamped-output key additionally
includes `catalogRelease` and the selected stub's SHA-256. Replacing an override
stub or advancing a catalog therefore forces a restamp even when the platform
and payload are unchanged. Building or cleaning one platform must not remove
another platform's files.

Stamping and applying a file mode are separate operations. `stampFile` writes
the same bytes on every compiler host and never unconditionally runs `chmod`.
A target finalizer applies these rules:

- PE output needs no executable-mode operation.
- A POSIX compiler host sets ELF and Mach-O raw outputs to mode `0755`.
- A Windows compiler host cannot represent a Unix executable bit on its
  filesystem. Its raw output is byte-complete, and the transferable Unix
  artifact is a deterministic tar archive whose executable entry records mode
  `0755`.

Unix release artifacts use tar, not zip, so extraction preserves that mode.
Windows release artifacts may use zip. Native CI extracts the archive, checks
the mode where applicable, and executes the result.

Every cross-target POSIX result owns both the raw stamped file and a
deterministic `<output>.tar` containing that file at mode `0755`. Emitting both
on every compiler host keeps `produced.outputs` and cache behavior independent
of the compiler host; the tar file is the canonical transferable artifact when
the raw file lives on Windows. `platformOutputs` customizes the raw path and the
tar path is derived from it. Phase 4 may compress that tar deterministically for
release without changing the mode contract.

## Stub catalog

The compiler carries a versioned catalog for the release whose host ABI it
understands. Each record contains:

```text
catalogRelease
platform
hostAbi
artifact
sha256
size
executableSuffix
hostFeatures
noticeArtifact
```

The catalog is immutable data generated by release automation and reviewed in
source. It never resolves `latest`, a branch or mutable release metadata. A
catalog bump names a new release identity and new digests.

Source revisions between releases may have a host ABI newer than the embedded
catalog. Such a checkout can still build the current-platform host from source,
but cross-target builds require an explicit local catalog or stub directory
until a matching release exists. They must not silently use an older host.

The catalog format is distinct from the payload trailer. Artifact acquisition
can change without revising the executable container, and a third-party stub
does not become a Nupp release artifact merely because it implements that
container.

### Host ABI

Phase 2 introduces one integer `hostAbiVersion` beside `PAYLOAD_VERSION` in
the packager and host. `docs/distribution.md` specifies it immediately after the
trailer contract before any catalog is published. `hostAbi` is the catalog's
camelCase spelling of that exact integer; target-layout ABI remains unrelated.

The host ABI describes the contract between a compiler-generated payload and a
compiler-owned host. It bumps when an older host cannot correctly run a new
payload, including incompatible changes to:

- the compiler-owned preload set or preload registration rules;
- the private host capability record or bootstrap handshake;
- the worker-state startup and payload protocol; or
- the minimum LuaJIT/runtime behavior generated payloads require.

A trailer-layout change bumps `PAYLOAD_VERSION`. It bumps `hostAbiVersion` as
well only when that change also makes the payload/host runtime contract
incompatible. Adding a compatible optional host capability does not itself bump
the ABI; the catalog's `hostFeatures` records it.

The compiler compares the catalog record's `hostAbi` with its own constant
before reading or stamping the stub. The payload preamble repeats the check at
startup as defense against an artifact mislabeled outside the catalog. A
mismatch never falls back to a different catalog or current-platform host.

## Stub features

Publishing every combination of cjson, LPeg, luautf8, workers, native files and
native process features would create a growing artifact matrix. The official
cross-target stub is therefore one **universal compiler-owned host** per
platform, built with every compiler-owned host feature.

That must not make unselected modules observable. A universal host publishes
its compiled capability set through a private bootstrap record. The exposure
mask is a pure function of the target's selected feature set, never of the stub
or its capability record. The generated payload begins by:

1. checking that every required host feature is present;
2. removing unselected C module openers from `package.preload`; and
3. installing only the compiler-generated runtime modules selected by the
   payload.

No user code runs before this mask. Removing a preload which an exact-feature
host never registered is a documented no-op, so an exact host and a universal
host receive byte-identical payloads for the same target. A computed
`require("lpeg")` therefore continues to fail when the checked program did not
select LPeg, even though the universal stub contains LPeg machine code. Worker
states run the same payload preamble and see the same mask.

The source-built current-platform host may continue compiling the exact feature
set for size. Both paths must pass the same visible-capability tests.

Cross-target native staging classifies every resolved feature before calling
`native.build`:

- a feature with a `host` Cargo feature is satisfied by the compiler-owned
  catalog stub and is not sidecar-built or copied into `outDir/lib`;
- a sidecar-only feature with `cargo` but no `host` is refused until the catalog
  provides a matching target-native provider artifact; and
- pure runtime modules are still bundled when implied by a host-backed feature.

This means files and process are satisfied by the universal stub even though
they also have sidecar implementations. Path, URI, UUID, HTTP and SHA-256 are
sidecar-only today and are refused. No Linux `.so` may be staged beside a
Windows `.exe` merely because Linux ran the compiler.

Workers require a compiler-owned host, source-built or selected from the
catalog; they no longer key on the literal `target.stub == "nupp"` path. Later
support publishes a target-native provider pack with its own digest and feature
manifest, or deliberately links selected providers into the universal host.
The HTTP/TLS size and export surface must be measured before choosing between
those approaches.

## Acquisition and offline behavior

Phase 3 acquisition is deliberately local because the released compiler has no
HTTP/TLS provider. It follows this trust shape:

1. Reuse a digest-verified project cache entry.
2. Search `NUPP_STUB_DIR` for the catalog artifact.
3. On a miss, name the exact artifact and directory required. Phase 3 never
   contacts the network and never shells out to an optional downloader.

Every local artifact is checked for size and SHA-256 before it enters the
project cache. A bad override never replaces a valid cached stub.

The default cache is project-local under
`.nupp/stubs/<catalogRelease>/<hostAbi>/<platform>/<sha256>/` so cleaning
generated output does not force another acquisition and distinct immutable
stubs cannot alias. A future shared cache may be selected by another environment
variable, but no implementation may infer and write into a user home directory
without documenting ownership and cleanup.

Phase 5 may add the catalog URL and `NUPP_STUB_BASE_URL` fallback only after the
standalone compiler distribution carries an in-process HTTP/TLS provider.
Downloads then go to a unique temporary sibling, are checked before atomic
rename, and obey `NUPP_STUB_OFFLINE`. Help, checks which need no stub, local
hits, and current-platform source builds never contact the network. Offline
mode continues to work without loading the HTTP provider.

## Target-specific payloads

Do not assume that one payload is portable merely because the compiler's
current release payload happens to be. For each selected platform the build:

1. sets the effective `layoutTarget` to that platform;
2. includes the platform in persistent comptime and generated-module cache
   keys;
3. checks and generates the module graph under that target;
4. resolves native effects;
5. writes a deterministic payload; and
6. stamps that payload into the selected stub.

Payload bytes may be reused across platforms only after their complete target
fingerprints agree. This is an optimization, not the semantic model. The
release workflow's current Linux-to-Windows payload reuse must either prove
that equality through the build result or build the payload separately.

Rock dependencies containing platform-native modules require a target artifact
the same way compiler-native sidecars do. Pure Lua rocks remain payload input
and need no special handling.

## macOS signing and Windows signing

Appending to today's ad-hoc-signed Mach-O produces a binary which runs locally
but fails strict code-signature validation and notarization. Cross-target
stamping may land before distributable macOS signing, but the CLI and release
workflow must not describe that artifact as Gatekeeper-ready.

Closing cross-platform **distribution** requires a signer which covers the
payload after stamping, deterministic signing behavior for the packaging
fixpoint, and notarization in release CI. The signer operates on an already
linked Mach-O and therefore does not move Apple SDK linking onto a non-Apple
host. Credentials remain a release concern; ordinary local builds are not
silently signed with a developer identity.

Windows developer artifacts need no Authenticode signature to run. Tagged
release policy decides whether public Windows artifacts are signed, records the
signature outside the payload determinism claim, and verifies it after upload.

## Notices and release packaging

A release artifact is an archive, not a bare executable. It contains:

- the platform stub or stamped compiler;
- `NOTICE.md` and the applicable files under `notices/`;
- the stub catalog record and SHA-256 checksum; and
- platform-specific installation or signing notes.

The current workflow's bare executable uploads do not meet this contract. CI
unpacks every archive, verifies its checksum and notices, executes it on the
native platform, and then uploads the exact archive it tested. Release assets
are immutable; replacement bytes require a new release identity rather than
`--clobber` under a pinned identity.

Unix archives are tar files whose executable entry records mode `0755`; zip is
not used for ELF or Mach-O because its executable-mode handling is not portable.
Windows archives may be zip files.

Raw stubs used by the compiler may be separate release assets from end-user
standalone Nupp archives, but both derive from the same native build and catalog
record.

## Diagnostics

Every refusal names the build target, selected platform and remedy. Refusals
include:

- platform not configured on the target;
- configured platform not supported by the compiler;
- no layout model for the platform;
- catalog host ABI differs from the compiler;
- local, cached or downloaded stub has the wrong digest or size;
- phase 3 cannot find the required artifact in the cache or `NUPP_STUB_DIR`;
- after network acquisition exists, offline mode is missing an artifact;
- selected payload needs a host feature absent from the stub;
- selected payload needs a native sidecar with no target artifact; and
- one literal `output` was used for a multi-platform build.

Errors do not fall back to the current-platform stub, another platform, a
smaller feature set or an unverified path.

Successful output may also carry notices. An unsigned cross-stamped macOS
binary is produced in phase 3 with a structured `distributionReady = false`
notice explaining that it is runnable for development but has not passed strict
signature validation or notarization. It is not a refusal; phase 4 signing
turns that status true for a release artifact.

## Implementation phases

### Phase 1: platform identity

- Add and validate `platforms` on binary targets.
- Add `--platform` and `--platform all` to check, build and clean.
- Connect selected platform to effective `layoutTarget`, cache keys, task
  descriptions and JSON schemas.
- Define output paths and cleanup ownership without acquiring stubs yet.
- Define per-platform result entries and continue-after-failure behavior for
  `--platform all`.
- Prove two platform checks in one process do not share target-sensitive
  comptime results.

### Phase 2: universal stubs and catalog

- Define `hostAbiVersion`, its bump rules and runtime handshake beside the
  trailer in `docs/distribution.md`.
- Add the private host capability record and payload exposure mask.
- Build one all-host-features stub per initial platform on native CI.
- Generate the immutable catalog and checksums.
- Package notices with every stub.
- Test universal and exact-feature hosts for identical visible modules.
- Prove the exposure mask and resulting payload depend only on selected target
  features, not on the chosen stub.

### Phase 3: acquisition and stamping

- Implement cache and `NUPP_STUB_DIR` local lookup with no network fallback.
- Verify size, digest, platform and host ABI before stamping.
- Include `catalogRelease` and stub SHA-256 in stamped-output cache keys.
- Skip sidecar builds for host-backed features and refuse sidecar-only features
  before anything is copied into `outDir/lib`.
- Replace unconditional `chmod` with target-aware mode and archive handling.
- Stamp one or all configured platforms and report every output.
- Use committed synthetic stub bytes and a synthetic catalog for offline
  mechanical acquisition, corruption and cross-stamping tests.
- Gate real Linux-to-Windows and Linux-to-macOS artifacts on release CI.

### Phase 4: release completion

- Replace bare release executables with verified archives carrying notices.
- Implement or integrate post-stamping macOS signing and notarization.
- Decide and implement Windows Authenticode policy.
- Use tar archives with mode `0755` for Unix binaries and verify the extracted
  mode on native runners; do not ship Unix executables in zip files.
- Retain immutable raw stub assets and their catalog for every supported
  compiler release and verify that every catalog URL remains available.
- Exercise one CLI invocation which produces all three outputs, followed by
  native execution jobs for each artifact.

### Phase 5: native provider packs

- Measure universal-host versus sidecar size for path, URI, UUID, SHA-256 and
  HTTP/TLS providers.
- Put an HTTP/TLS provider in the standalone compiler distribution, then add
  catalog URL, `NUPP_STUB_BASE_URL` and `NUPP_STUB_OFFLINE` acquisition without
  shelling out to system downloaders.
- Publish target-native provider packs or extend the universal host deliberately.
- Add native LuaRock artifact metadata if a real project requires it.
- Remove the phase-3 refusal only for providers with complete target tests.

## Verification

Unit and integration coverage must include:

- manifest validation for empty, duplicate, unknown and unsupported platforms;
- CLI selection of one, all, missing and unconfigured platforms;
- target layout and persistent comptime separation;
- deterministic per-platform output paths and cleanup isolation;
- `clean --platform`, target-aware executable mode and Unix archive mode;
- local stub directory, cache hit and local miss in phase 3;
- mirror, verified download and offline miss after phase 5 enables networking;
- corrupt, truncated, wrong-platform and wrong-ABI stubs;
- cache invalidation when `catalogRelease` or the stub digest changes;
- universal-host feature masking for direct and computed `require`;
- byte-identical payloads for universal and exact-feature host selection;
- worker startup under a universal stub;
- payload feature mismatch refusal before user code runs;
- host-backed sidecar suppression and sidecar-only refusal before staging;
- synthetic offline catalog fixtures in the ordinary suite and real catalog
  artifacts only in native release CI;
- the existing twenty damaged-container cases on every native runner;
- recorded LSP session equivalence through every standalone compiler;
- repeated off-platform stamping with the same stub and payload is
  byte-identical;
- the existing self-stamping binary fixpoint runs only on a native runner which
  can execute that platform's result;
- required notices in every unpacked release archive;
- macOS signature and notarization verification; and
- one host producing all configured artifacts before native runners execute
  their own result.

## Completion gate

The TODO item closes only when:

1. the manifest and CLI can select all three initial platforms;
2. one supported host can produce all three binaries without target toolchains;
3. every stub is pinned, verified, cacheable and available through an offline
   local override, with cache identity including its digest and catalog release;
4. target-dependent payloads are compiled under the target rather than the
   compiler host;
5. host-backed features use the stub without building a compiler-host sidecar,
   and unsupported sidecar-only features are refused before staging;
6. release archives carry notices and immutable checksums;
7. Linux and Windows release artifacts run on clean native machines;
8. the macOS release artifact passes strict signature validation and
   notarization; and
9. all native host, container, LSP replay and fixpoint gates pass.
