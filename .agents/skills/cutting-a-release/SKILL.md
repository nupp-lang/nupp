---
name: cutting-a-release
description: How to cut, publish and recover a Nupp release, and how to move native bootstrap pins in `scripts/bootstrap-seeds.json` afterwards. Use this whenever the work involves tagging, publishing, version numbers, `nupp --version`, the release workflow, a failed or stuck release run, GitHub release assets, `scripts/bootstrap-seeds.json`, or letting the compiler's own sources use a language feature they currently cannot. Reach for it even when the request sounds small, like "tag v0.1.0", "why did the release fail", "bump the bootstrap pin", or "publish a build" -- the ordering constraints here are not guessable and each wrong attempt burns a version number permanently.
---

# Cutting a Nupp release

A release here is not a button. It is a commit that changes one string, and a
tag on that commit. Everything else is CI reacting to the tag.

The reason to read this before tagging: **release assets are immutable and the
publish job refuses to replace an existing release.** A tag whose run fails is
spent. Recovering means deleting the tag, which is only safe while no release
was created, so a careless attempt costs a version number that is then gone from
the history forever.

## What a release is

`src/nupp/tools/version.nupp` holds `version.VERSION`. Between releases it
carries a `-dev` suffix, because a checkout is not the release it came after and
is not yet the one it is heading for. A release is the commit that removes that
suffix.

Release CI runs the *archived binary* and requires `nupp --version` to print
exactly `nupp <tag without the leading v>`. That is what makes the number
trustworthy rather than merely believed: what shipped is what says it shipped.

Nothing else in the tree moves with a release. The stage-zero image is composed
by CI at release time, so a release commit touches one file.

## Cutting one

**1. Check the trunk is green.** `.github/workflows/compiler.yml` is what decides
whether a commit is good. The release workflow is packaging, not validation, and
it does not run the test suite.

**2. Rehearse if the packaging path has moved.** The release workflow accepts
`workflow_dispatch`, which runs every build job without publishing anything:

```bash
gh workflow run release.yml --ref main
```

Worth doing when anything under `.github/`, `scripts/`, `native/` or the host
has changed since the last release. Be aware of what a rehearsal cannot tell
you: the version guard and the publish job are both gated on the ref being a
tag, so a rehearsal passes with a wrong version string.

**3. Make the version commit** on `main`, setting `version.VERSION` to the
release number with no suffix, then push it.

**4. Tag that exact commit and push the tag.**

```bash
git tag v0.1.0 <commit> && git push origin v0.1.0
```

Tag the commit by hash rather than tagging whatever `main` points at. Other
worktrees push to this trunk, so `main` moves; tagging a commit you did not
verify is how a release ships something nobody looked at.

**5. Watch the run.** It takes roughly an hour. The jobs are the browser
runtime, Linux and macOS binaries, Windows, the stage-zero compiler, the stub
catalog, cross-target stamping, its two verifiers, and finally `release`, which is the only job that publishes.

## After it publishes

**Return the version to a dev suffix.** Leaving `main` on the released number
means every checkout claims to be the release, which is exactly what the `-dev`
convention exists to prevent.

**Consider moving the stage-zero pin.** This is a separate decision, described
below.

## Moving the stage-zero pin

A checkout bootstraps from the published runtime and compiler image paired in
`scripts/bootstrap-seeds.json`. Each entry under `hosts` names one archive URL
and its `sha256`, plus `runtimeSha256` and `imageSha256` for its members:

```sh
./scripts/toolchain stage0-seed
./bin/nupp fixpoint
```

Compiler sources, the standard library and `nupp.lua` may use only language
features and manifest keys that the pinned image understands. Keep the pinned
runtime compatible with that image's format and provider symbols.

Publish the accepting compiler image before adopting new features in compiler
sources. Repackage it with each host's existing pinned runtime through
`.github/workflows/refresh-native-bootstrap-seed.yml`, then verify the published
archives and their members. Update every affected host entry's URL and three
digests in `scripts/bootstrap-seeds.json`; retain each `runtimeSha256` when the
runtime is unchanged. Publishing a standalone `.image.gz` does not move this pin.

The `STAGE0_IMAGE_*` entries in `scripts/toolchain.pins` are legacy sentinels;
they do not select the active cold-bootstrap pair. Do not replace the package
manifest with those entries or rebuild a runtime just to change the image.

Run the source-only `./bin/nupp fixpoint` from the actual published pair before
committing the pin. It lowers three compiler stages and compares their outputs.
Use `--emit-stage0` only when producing an image for publication. Running the
source-only acceptance check does not produce or publish a release asset.

## Experimental pre-releases

A branch that needs a pin the trunk does not have yet -- a format change, a
feature its own sources want -- publishes the image as a pre-release, so the
last release from `main` stays the one users and `main` see. Two things keep it
from becoming the latest release:

- **A tag outside `vX.Y.Z`.** The release workflow runs on exactly that pattern
  and publishes as an ordinary release, so a pre-release tag carries a suffix,
  such as `v0.0.15-vm.1`. The compiler matrix and the measurements skip `v*-*`
  tags too, because the branch push already tested the commit.
- **`--prerelease --latest=false`.** The image is composed locally, the way the
  stage-zero job does, from a commit pushed to the branch:

```bash
./bin/nupp fixpoint --emit-stage0 build/stage0/nupp-stage0-v0.0.15-vm.1.image
shasum -a 256 build/stage0/nupp-stage0-v0.0.15-vm.1.image
gzip -9 -n build/stage0/nupp-stage0-v0.0.15-vm.1.image
gh release create v0.0.15-vm.1 build/stage0/nupp-stage0-v0.0.15-vm.1.image.gz \
    --target "$(git rev-parse <commit>)" --prerelease --latest=false \
    --title 'v0.0.15-vm.1 (experimental VM stage zero)' --notes '...'
```

`--target` needs the full hash; `gh release create` makes the tag.

Then move the branch's pin to it as above. Never tag `main` or change
`version.VERSION` for one.

## The guards, so a failure is recognizable

| Failure | Cause |
|---|---|
| `tag vX ships nupp Y; bump nupp.tools.version` | The version commit was missed, or the tag was cut at the wrong commit. |
| `release vX already exists; immutable assets are not replaced` | That tag already published. Use a new number. |
| A build job fails on a `.nupp` file under `scripts/` | Those sit outside the manifest's include roots. `tests/tools/repository/repositoryscriptstest.lua` covers them; run it before tagging. |

macOS signing is optional and degrades rather than failing when the secrets are
absent, so it is not a blocker.

## When a run fails

The tag is spent unless you remove it. Deleting a tag is only safe when the
`release` job did not run, which you can confirm with `gh release view <tag>`
returning "release not found". If a release exists, do not touch it; move to the
next number.

```bash
gh release view v0.1.0            # must say "release not found"
git push --delete origin v0.1.0 && git tag -d v0.1.0
```

Fix the cause on `main` first, then re-tag. Re-running a failed run against the
same tag only works if the cause was transient, since the tag still points at
the unfixed commit.

Tag deletion and force-pushing tags are the operations most likely to be refused
by a permission prompt. When that happens, hand the user the exact command
rather than working around it.
