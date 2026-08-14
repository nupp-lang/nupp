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
- `layoutTarget`, when present on a cross-target binary, must equal the selected
  platform. Normally it is omitted and inferred from that platform.
- A binary platform must have a layout model. A layout model need not have a
  binary platform.
- Manifest and JSON field names remain camelCase. CLI flags retain the existing
  hyphenated command-line convention.

`nupp tasks --json` reports `platforms`, and the text form lists them beneath
the binary target. Build JSON adds `platform` to a single-platform result and a
`platforms` array to an `all` result.

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
fixpoint paths all include the platform. Building or cleaning one platform must
not remove another platform's files.

## Stub catalog

The compiler carries a versioned catalog for the release whose host ABI it
understands. Each record contains:

```text
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

## Stub features

Publishing every combination of cjson, LPeg, luautf8, workers, native files and
native process features would create a growing artifact matrix. The official
cross-target stub is therefore one **universal compiler-owned host** per
platform, built with every compiler-owned host feature.

That must not make unselected modules observable. A universal host publishes
its compiled capability set through a private bootstrap record. The generated
payload begins by:

1. checking that every required host feature is present;
2. removing unselected C module openers from `package.preload`; and
3. installing only the compiler-generated runtime modules selected by the
   payload.

No user code runs before this mask. A computed `require("lpeg")` therefore
continues to fail when the checked program did not select LPeg, even though the
stub contains LPeg machine code. Worker states run the same payload preamble
and see the same mask.

The source-built current-platform host may continue compiling the exact feature
set for size. Both paths must pass the same visible-capability tests.

`path`, `uri`, `uuid`, `http` and `sha256` currently come from native sidecars
rather than host Cargo features. Phase one refuses a cross-target binary which
needs one of those providers. Later support publishes a target-native provider
pack with its own digest and feature manifest, or deliberately links selected
providers into the universal host. The HTTP/TLS size and export surface must be
measured before choosing between those approaches.

## Acquisition and offline behavior

Stub acquisition follows the same trust shape as host source acquisition:

1. Reuse a digest-verified project cache entry.
2. Search `NUPP_STUB_DIR` for the catalog artifact.
3. Otherwise use the catalog URL, replacing its base with
   `NUPP_STUB_BASE_URL` when configured.
4. With `NUPP_STUB_OFFLINE=1`, refuse the network fallback and name the exact
   missing artifact.

Downloads go to a unique temporary sibling, are checked for size and SHA-256,
and are atomically renamed into the cache only after verification. A bad
download never replaces a valid cached stub. A local artifact receives the
same digest check as a download.

The default cache is project-local under `.nupp/stubs/<hostAbi>/<platform>/` so
cleaning generated output does not force another download. A future shared
cache may be selected by another environment variable, but no implementation
may infer and write into a user home directory without documenting ownership
and cleanup.

Help, checking a target without a selected cross platform, and current-platform
source builds do not contact the network merely because the catalog cache is
empty.

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

Raw stubs used by the compiler may be separate release assets from end-user
standalone Nupp archives, but both derive from the same native build and catalog
record.

## Diagnostics

Every refusal names the build target, selected platform and remedy. Required
cases include:

- platform not configured on the target;
- configured platform not supported by the compiler;
- no layout model for the platform;
- catalog host ABI differs from the compiler;
- local, cached or downloaded stub has the wrong digest or size;
- offline mode is missing an artifact;
- selected payload needs a host feature absent from the stub;
- selected payload needs a native sidecar with no target artifact;
- one literal `output` was used for a multi-platform build; and
- macOS output is runnable but not signed for distribution.

Errors do not fall back to the current-platform stub, another platform, a
smaller feature set or an unverified path.

## Implementation phases

### Phase 1: platform identity

- Add and validate `platforms` on binary targets.
- Add `--platform` and `--platform all` to check/build.
- Connect selected platform to effective `layoutTarget`, cache keys, task
  descriptions and JSON schemas.
- Define output paths and cleanup ownership without acquiring stubs yet.
- Prove two platform checks in one process do not share target-sensitive
  comptime results.

### Phase 2: universal stubs and catalog

- Add the private host capability record and payload exposure mask.
- Build one all-host-features stub per initial platform on native CI.
- Generate the immutable catalog and checksums.
- Package notices with every stub.
- Test universal and exact-feature hosts for identical visible modules.

### Phase 3: acquisition and stamping

- Implement cache, `NUPP_STUB_DIR`, mirror and offline lookup.
- Verify size, digest, platform and host ABI before stamping.
- Stamp one or all configured platforms and report every output.
- Refuse unresolved target-native sidecars.
- Run Linux-to-Windows and Linux-to-macOS stamping tests using prebuilt stubs.

### Phase 4: release completion

- Replace bare release executables with verified archives carrying notices.
- Implement or integrate post-stamping macOS signing and notarization.
- Decide and implement Windows Authenticode policy.
- Retain immutable raw stub assets and their catalog for every supported
  compiler release.
- Exercise one CLI invocation which produces all three outputs, followed by
  native execution jobs for each artifact.

### Phase 5: native provider packs

- Measure universal-host versus sidecar size for path, URI, UUID, SHA-256 and
  HTTP/TLS providers.
- Publish target-native provider packs or extend the universal host deliberately.
- Add native LuaRock artifact metadata if a real project requires it.
- Remove the phase-one refusal only for providers with complete target tests.

## Verification

Unit and integration coverage must include:

- manifest validation for empty, duplicate, unknown and unsupported platforms;
- CLI selection of one, all, missing and unconfigured platforms;
- target layout and persistent comptime separation;
- deterministic per-platform output paths and cleanup isolation;
- local stub directory, mirror, cache hit and offline miss;
- corrupt, truncated, wrong-platform and wrong-ABI stubs;
- universal-host feature masking for direct and computed `require`;
- worker startup under a universal stub;
- payload feature mismatch refusal before user code runs;
- target-native sidecar refusal;
- the existing twenty damaged-container cases on every native runner;
- recorded LSP session equivalence through every standalone compiler;
- current-platform and per-platform packaging fixpoints;
- required notices in every unpacked release archive;
- macOS signature and notarization verification; and
- one host producing all configured artifacts before native runners execute
  their own result.

## Completion gate

The TODO item closes only when:

1. the manifest and CLI can select all three initial platforms;
2. one supported host can produce all three binaries without target toolchains;
3. every stub is pinned, verified, cacheable and available through an offline
   local override;
4. target-dependent payloads are compiled under the target rather than the
   compiler host;
5. unsupported native sidecars are refused before stamping;
6. release archives carry notices and immutable checksums;
7. Linux and Windows release artifacts run on clean native machines;
8. the macOS release artifact passes strict signature validation and
   notarization; and
9. all native host, container, LSP replay and fixpoint gates pass.
