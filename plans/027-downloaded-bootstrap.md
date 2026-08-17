# Downloaded bootstrap compiler

Status: proposed. Not implemented. The tracked
`bootstrap/nupp.lua` remains the only cold-start path until Nupp has made and
retained the first release named by this plan, every supported host can use
that release, and the cold-bootstrap CI gate passes without the bundle.

## Decision

Nupp will eventually stop committing a generated compiler. A fresh checkout
will instead carry a small stage-0 manifest which pins one previously released
standalone Nupp executable for every supported host, including its SHA-256
digest. `bin/nupp` will download the selected executable on first use, verify it
before execution, cache it under `build/bootstrap`, and use it only to compile
the current compiler.

The version is never inferred from “latest,” a branch name, or mutable release
metadata. An old checkout must keep selecting the same compiler after new Nupp
versions are released.

The compiler source has an explicit **stage-0 compatibility floor**: everything
needed to compile it — language syntax and semantics, manifest fields,
compile-time facilities, standard-library declarations, and the compiler's
build entry point — must be understood by the version pinned in the stage-0
manifest. A new language feature therefore lands in two steps:

1. Release a compiler which implements the feature without using the feature
   in the compiler's own source.
2. Advance the stage-0 manifest to that release. Only then may compiler source
   use the feature.

This is the same constraint Rust accepts by building its current compiler with
a downloaded beta compiler. It is policy, not something self-hosting can infer
or repair. A compiler which cannot parse current source cannot create the first
new stage.

The normal build remains three logical compilers:

```text
pinned released executable (stage 0)
    -> current compiler built by stage 0 (stage 1)
    -> current compiler built by stage 1 (stage 2)
```

Stage 0 and stage 1 need not emit identical files. Stage 0 may contain an older
generator. The claims are instead that stage 0 can produce a working stage 1,
and that the current compiler reaches the existing byte-identical fixpoint when
it rebuilds itself. The initial cold build and `nupp fixpoint` together prove
those claims.

## Why make the change

`bootstrap/nupp.lua` is currently a 2.5 MB generated file and changes whenever
the compiler bundle changes. It gives every commit a branch-exact, portable,
offline route into the compiler, but it also puts generated churn into reviews
and repository history. A released standalone binary already contains the
compiler and its runtime; once releases are durable, the repository needs only
to identify and authenticate the one used as stage 0.

Deleting the file will not remove its existing objects from full Git history.
This plan stops future churn and reduces the checked-out tree. It does not
rewrite history.

## Goals

1. Build a fresh checkout without a committed generated compiler.
2. Make the bootstrap input exact, reviewable, immutable, and authenticated by
   a digest committed in the same change as a version bump.
3. Preserve the current preference for a successfully built current compiler;
   stage 0 is recovery and cold-start machinery, not the everyday compiler.
4. Detect stage-0 incompatibility before a compiler change merges.
5. Keep interrupted downloads, corrupt cache entries, unsupported hosts, and
   unavailable networks from producing ambiguous compiler failures.
6. Retain an explicit local-executable override for offline builds and release
   recovery.
7. Make advancing the compiler's self-hosting language floor a deliberate
   release operation.

## Non-goals

- Downloading the newest available Nupp automatically.
- Trusting an unverified CI artifact or a release asset which may expire.
- Supporting a host for which Nupp publishes no standalone compiler.
- Removing LuaJIT, Cargo, or the development native provider from every later
  development path. Those are separate launcher and packaging decisions.
- Making old compilers accept arbitrary future syntax.
- Reclaiming generated bootstrap objects already present in Git history.
- Adding transparent network access to commands which already have a usable
  current compiler.
- Establishing artifact signing in the first version. The committed SHA-256
  digest is the required integrity boundary; signing can be layered on later.

## Current baseline

- `bootstrap/nupp.lua` is the complete generated stage-0 compiler and embeds
  the declarations it needs.
- `bin/nupp` prefers `build/nupp/compiler/main.lua`, falls back to the tracked
  bundle when a rebuild fails, and uses the bundle directly in a tree with no
  completed build.
- The compiler target is a module tree. The release target is a self-contained
  executable containing the same compiler entry point.
- Tagged release CI already publishes standalone Linux x86-64, macOS arm64,
  and Windows x86-64 artifacts.
- `nupp fixpoint` asks a current compiler to build itself twice and compares the
  resulting trees byte for byte.
- No release is yet the permanent predecessor on which source builds promise
  to depend. The tracked bundle cannot be removed before one exists.

## Stage-0 manifest

Add `bootstrap/stage0` as a line-oriented, shell-readable manifest. It contains
one immutable release identity and one artifact record per supported host. A
representative shape is:

```text
version=v0.1.0
base_url=https://github.com/nupp-lang/nupp/releases/download/v0.1.0
linux-x86_64=nupp-linux-x86_64 <sha256>
macos-arm64=nupp-macos-arm64 <sha256>
windows-x86_64=nupp-windows-x86_64.exe <sha256>
```

The implemented grammar must be narrower than this illustration permits:

- exactly one `version` and `base_url`;
- no duplicate keys;
- host keys drawn from a fixed mapping in the downloader;
- artifact names containing no slash or shell metacharacters;
- lowercase, 64-character hexadecimal SHA-256 values; and
- unknown fields rejected so a misspelling cannot silently weaken the pin.

The URL may be split into a fixed distribution server plus release and artifact
paths if that makes mirrors easier, but the selected bytes and digest remain
fully pinned. The manifest is data. It is never sourced as shell code.

`bootstrap/README.md` will describe how the file is generated, reviewed, and
advanced. A stage-0 bump is expected to be a small manifest-only change unless
host support changes with it.

## Download and cache behavior

The downloader belongs below `bin/nupp`, either as shell functions in the
launcher or as a small script under `bootstrap/`. It must not require Nupp.

On a cold build it will:

1. Normalize `uname` output to one supported host key.
2. Read exactly that host's artifact name and digest.
3. Choose `build/bootstrap/<version>/<host>/nupp` as the repository-local cache
   path. The digest is recorded beside it or included in a containing path.
4. Reuse a cache hit only after verifying its SHA-256 digest.
5. Download to a uniquely named temporary file in the destination directory.
6. Verify the complete temporary file before making it executable.
7. Rename it atomically into the cache and execute only the final verified
   path.

Use `curl` as the primary transport. If Windows support needs a PowerShell
fallback, it must have identical verification and atomic-install semantics.
Digest calculation may select `sha256sum`, `shasum -a 256`, or an equally
specific platform facility. Missing download or digest tools produce an error
which names the requirement and the local override.

A failed download or digest mismatch removes only its temporary file. It never
replaces a valid cached compiler. No path uses `curl | sh`, and no downloaded
byte executes before verification.

`NUPP_STAGE0` may name an existing standalone executable. This is an explicit
operator override for offline builds, mirrors, release recovery, and CI tests;
it is not populated implicitly from `PATH`. The launcher reports that it is
using the override. The normal manifest digest cannot authenticate arbitrary
override bytes, so CI must not use an unpinned override except when a test is
specifically exercising override behavior.

## Launcher behavior

Preserve the useful parts of the current recovery order:

```text
completed current compiler exists
    -> try it for a required rebuild
       -> success: run the new current compiler
       -> failure: try verified stage 0

no completed current compiler
    -> acquire verified stage 0
       -> build the current compiler
       -> run the current compiler
```

Help which needs no source tree must not trigger a download. A command which
can run on an existing completed compiler must not contact the network merely
because the cache is absent.

When stage 0 builds the current compiler, success still means both the compiler
entry point and its completion stamp exist. The launcher then starts that
compiler rather than continuing to serve the user's command from stage 0. This
keeps diagnostics and behavior tied to the checkout.

If rebuilding with the current compiler and then stage 0 both fail, preserve
the last completed current compiler and report both failures clearly. A failed
attempt must not turn an existing usable compiler into an incomplete build
that wins discovery.

## Compatibility contract

Stage-0 compatibility covers more than parsing:

- syntax used anywhere in the compiler target;
- type-system rules needed to check that source;
- generator behavior sufficient to create a runnable stage 1;
- manifest schema and target kinds used by `nupp.lua`;
- embedded declaration formats and compile-time execution protocols;
- standard-library APIs called while compiling; and
- command-line options used by the launcher and release workflow.

A feature may be implemented, documented, and tested without immediately being
used by compiler source. Once a release containing it is pinned as stage 0, a
separate change may migrate compiler source to it. Reviews which cross the
floor must say so and include the manifest bump.

`RUSTC_BOOTSTRAP`-style feature-gate bypass is not a general solution for Nupp.
It could enable a construct already implemented but gated by policy; it cannot
make an older lexer, parser, checker, build system, or standard library
understand code which did not exist in that release.

## Release policy

Stage-0 artifacts are part of Nupp's source-build trust root and have stronger
retention requirements than ordinary convenience downloads:

- published assets are immutable;
- every supported host has a complete standalone executable;
- asset names are stable and unambiguous;
- the release workflow records SHA-256 values for the manifest bump;
- old assets remain available as long as any maintained source revision names
  them; and
- replacement bytes require a new release identity, never `--clobber` under an
  identity already pinned by source.

The current release workflow uploads with `--clobber`; that is incompatible
with a release asset serving as an immutable bootstrap root. Before the first
pin, change the workflow to refuse replacement of an existing tagged asset, or
publish content-addressed names whose digest cannot be silently reused.

After release N is published and verified on every host, main may advance
`bootstrap/stage0` from N-1 to N. Release N+1 is then built from N. A release
must never pin itself: its source has to be buildable before its artifacts
exist.

## CI gates

Add a cold-bootstrap job on every supported host. It starts without a completed
compiler and forces the downloaded path even while the transition still keeps
`bootstrap/nupp.lua` in the tree. The job must:

1. Acquire the artifact named by `bootstrap/stage0` and verify its digest.
2. Build the current compiler with it.
3. Invoke the resulting current compiler successfully.
4. Run the compiler checks and suite appropriate to that host.
5. Run `nupp fixpoint` with the current compiler.
6. Build and smoke-test the standalone distribution.

This sequence distinguishes the two important failures: “the released compiler
cannot build current source” and “the current compiler cannot reproduce
itself.” It deliberately does not compare stage-0 output byte-for-byte with
stage-1 output.

Downloader tests cover:

- every supported OS and architecture mapping;
- unknown and duplicate manifest keys;
- malformed artifact names and digests;
- cache hit and corrupt-cache replacement;
- digest mismatch without execution;
- interrupted download without a partial cache hit;
- unsupported host diagnostics;
- missing transport and hash tools;
- offline local override; and
- concurrent cold starts resolving to one valid cached executable.

Release CI additionally builds every manifest-supported host artifact, tests
the executable before upload, emits its digest, and refuses mutable replacement
of a published bootstrap asset.

## Rollout

### DB-S0: Establish the release root

1. Publish the first permanent standalone release using the tracked bundle.
2. Remove mutable `--clobber` behavior for bootstrap-eligible release assets.
3. Confirm retention, naming, and download behavior for Linux x86-64, macOS
   arm64, and Windows x86-64.
4. Record and independently verify each artifact digest.

Exit gate: a clean machine on every supported host can download and run the
released compiler, and those exact assets are declared immutable.

### DB-S1: Add the manifest and verified downloader

1. Add `bootstrap/stage0` pinned to the release from DB-S0.
2. Implement strict manifest parsing, host selection, verified atomic download,
   cache reuse, and `NUPP_STAGE0`.
3. Add downloader regression tests without removing `bootstrap/nupp.lua`.

Exit gate: tests prove that only bytes matching the committed host digest can
become the cached executable.

### DB-S2: Run both bootstrap paths

1. Teach `bin/nupp` to prefer the downloaded stage 0 for cold builds and
   recovery while retaining the tracked bundle behind an explicit transition
   fallback.
2. Add cold-bootstrap CI on every supported host.
3. Run the complete compiler build, test, fixpoint, and distribution sequence
   from the released executable.
4. Keep this dual-path period through at least one stage-0 bump so the bump
   procedure itself is exercised.

Exit gate: two successive released versions have bootstrapped their successors
through the manifest path, including one compiler change which affects emitted
code.

### DB-S3: Remove the generated bundle

1. Delete `bootstrap/nupp.lua`.
2. Remove its launcher fallback and update `bootstrap/README.md`, contributor
   instructions, source distributions, and CI comments.
3. Change `nupp fixpoint --update-bootstrap`: it must no longer rewrite a
   generated compiler. Replace it with a separately named stage-0 bump/check
   workflow or retire the option with a direct migration diagnostic.
4. Verify a source archive, shallow clone, and ordinary full checkout all cold
   bootstrap through the same manifest.

Exit gate: no tracked generated compiler remains, no documented command tries
to regenerate one, and a fresh checkout passes every supported-host gate.

### DB-S4: Enforce the compatibility floor

1. Make the cold-bootstrap job required for compiler and manifest changes.
2. Document the two-step rule in `AGENTS.md` and contributor documentation.
3. Add a release checklist item to bump stage 0 only after all release assets
   are permanent and verified.
4. Treat a compiler-source use of an unsupported feature as a build-breaking
   compatibility regression, not as a reason to fetch an unpinned newer build.

Exit gate: the repository can no longer merge compiler source which its pinned
stage 0 cannot turn into a working current compiler.

## Recovery and exceptional changes

If a pinned release is broken but its bytes remain available, bump the manifest
to a later known-good release in a change whose parent still builds with the old
pin. If the asset itself disappears, restore the exact bytes at a new immutable
location with the same verified digest and change only the distribution URL.

If a compiler change genuinely cannot be expressed in the stage-0 language,
make an intermediate release which implements the needed facility without
using it in compiler source. Pin that release, prove the cold bootstrap, and
then land the source migration. Do not solve the problem with a branch artifact
or a floating nightly: that only moves the unrecorded compiler binary outside
the repository.

For disaster recovery, documentation should retain the command for supplying a
locally archived standalone compiler through `NUPP_STAGE0`. The release digest
list remains enough to authenticate such an archive independently of the
download server.

## Completion criteria

The migration is complete when:

- `git ls-files` contains no generated compiler executable or Lua bundle;
- the only bootstrap identity in source is the strict manifest;
- cold builds on every supported host download or reuse exactly the pinned
  artifact and verify it before execution;
- current compiler source remains buildable by that artifact;
- the produced compiler passes the existing byte-identical fixpoint;
- tagged releases are themselves built from the preceding pinned release;
- release assets used for bootstrapping cannot be replaced in place; and
- offline builders have a documented, explicit local stage-0 path.
