#!/usr/bin/env bash
set -euo pipefail
helper=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
temporary=$(mktemp -d "${TMPDIR:-/tmp}/nupp-advance-stage0-test.XXXXXXXX")
trap 'rm -rf "$temporary"' EXIT
export ADVANCE_FIXTURE="$temporary/server"
mkdir -p "$temporary/project/scripts" "$temporary/project/bin" "$temporary/mocks" "$ADVANCE_FIXTURE/assets"
export PATH="$temporary/mocks:$PATH"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
cd "$temporary/project"
git init -q
git config user.name Test; git config user.email test@example.invalid
git init -q --bare "$temporary/origin.git"
git remote add origin "$temporary/origin.git"
printf 'build/\n' > .gitignore
cat > bin/nupp <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$ADVANCE_FIXTURE/compiler.log"
if test "${2:-}" = --emit-stage0; then printf 'verified new native image\n' > "$3"
elif test "${ADVANCE_FAIL_FIXPOINT:-0}" = 1; then exit 9
else test -n "${NUPP_BOOTSTRAP_SEED_MANIFEST:-}"; fi
EOF
cat > scripts/toolchain <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
test "$1" = stage0-seed
test -s "$NUPP_BOOTSTRAP_SEED_MANIFEST"
printf '%s\n' "$ADVANCE_FIXTURE/published-seed"
EOF
chmod +x bin/nupp scripts/toolchain
printf 'old pinned image\n' > "$ADVANCE_FIXTURE/old.image"
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
old_sha=$(sha "$ADVANCE_FIXTURE/old.image")
jq -n '{format:"nupp-bootstrap-seed-1",hosts:{}}' > scripts/bootstrap-seeds.json
hosts=(aarch64-apple-darwin x86_64-pc-windows-gnu x86_64-unknown-linux-gnu)
for host in "${hosts[@]}"; do
    printf 'pinned runtime for %s\n' "$host" > "$ADVANCE_FIXTURE/$host-runtime"
    runtime_sha=$(sha "$ADVANCE_FIXTURE/$host-runtime")
    jq --arg host "$host" --arg runtime "$runtime_sha" --arg image "$old_sha" \
        '.hosts[$host]={url:("https://github.com/test/nupp/releases/download/v0.0.15-native-api-seed.5/"+$host+".tar.gz"),sha256:$image,runtimeSha256:$runtime,imageSha256:$image}' \
        scripts/bootstrap-seeds.json > scripts/pins.tmp
    mv scripts/pins.tmp scripts/bootstrap-seeds.json
done
git add .; git commit -qm 'Create native fixture'
export ADVANCE_REVISION=$(git rev-parse HEAD)
export ADVANCE_TAG=v0.0.15-native-test.1
cat > "$temporary/mocks/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$ADVANCE_FIXTURE/gh.log"
case "$1 $2" in
    'repo view') printf 'test/nupp\n' ;;
    'api repos/test/nupp/commits/'*) printf '%s\n' "$ADVANCE_REVISION" ;;
    'api repos/test/nupp/git/ref/tags/'*) jq -n --arg sha "${ADVANCE_TAG_REVISION:-$ADVANCE_REVISION}" '{object:{type:"commit",sha:$sha}}' ;;
    'api repos/test/nupp/releases/tags/'*)
        if test -e "$ADVANCE_FIXTURE/release.json"; then cat "$ADVANCE_FIXTURE/release.json"
        else printf 'HTTP 404: release not found\n' >&2; exit 1; fi ;;
    'api repos/test/nupp/actions/runs/42')
        jq -n --arg sha "$ADVANCE_REVISION" --arg tag "$ADVANCE_TAG" \
            '{event:"workflow_dispatch",head_sha:$sha,head_branch:$tag,path:".github/workflows/refresh-native-bootstrap-seed.yml",status:"completed",conclusion:"success"}' ;;
    'release create')
        tag=$3; shift 3; asset=$1
        cp "$asset" "$ADVANCE_FIXTURE/assets/$(basename "$asset")"
        jq -n --arg tag "$tag" --arg asset "$(basename "$asset")" \
            '{id:12,tag_name:$tag,prerelease:true,draft:false,assets:[{id:11,name:$asset}]}' > "$ADVANCE_FIXTURE/release.json" ;;
    'release download')
        shift 3; name= dir=
        while test "$#" -gt 0; do
            case "$1" in --repo) shift 2 ;; --pattern) name=$2; shift 2 ;; --dir) dir=$2; shift 2 ;; *) exit 91 ;; esac
        done
        cp "$ADVANCE_FIXTURE/assets/$name" "$dir/$name" ;;
    'run watch') : ;;
    'run download')
        shift 3; dir=
        while test "$#" -gt 0; do
            case "$1" in --repo|--pattern) shift 2 ;; --dir) dir=$2; shift 2 ;; *) exit 92 ;; esac
        done
        cp -R "$ADVANCE_FIXTURE/workflow/." "$dir/" ;;
    *) printf 'Unexpected gh command: %s\n' "$*" >&2; exit 93 ;;
esac
EOF
chmod +x "$temporary/mocks/gh"
"$helper" native-test --version 0.0.15 --prepare-only > "$temporary/prepare.log"
out="$PWD/build/stage0/$ADVANCE_TAG"
receipt="$out/receipt.json"
test -s "$receipt"
test "$(git rev-parse HEAD)" = "$ADVANCE_REVISION"
if grep -q 'release create|workflow run' "$ADVANCE_FIXTURE/gh.log"; then exit 94; fi
"$helper" --resume "$receipt" --publish-only > "$temporary/publish.log"
grep -q -- '--prerelease --latest=false' "$ADVANCE_FIXTURE/gh.log"
grep -q -- "--target $ADVANCE_REVISION" "$ADVANCE_FIXTURE/gh.log"
if grep -q 'workflow run' "$ADVANCE_FIXTURE/gh.log"; then exit 95; fi
if ADVANCE_TAG_REVISION=0000000000000000000000000000000000000000 "$helper" --resume "$receipt" --publish-only > "$temporary/bad-tag.log" 2>&1; then exit 96; fi
printf 'PASS preparation, immutable publication flags, owner dispatch stop, tag target refusal\n'
image_sha=$(jq -r .imageSha256 "$receipt")
compressed_sha=$(jq -r .compressedImageSha256 "$receipt")
asset=$(basename "$(jq -r .compressed "$receipt")")
for host in "${hosts[@]}"; do
    package="$temporary/package-$host"
    mkdir -p "$package/notices"
    cp "$ADVANCE_FIXTURE/$host-runtime" "$package/runtime"
    chmod +x "$package/runtime"
    cp "$(jq -r .image "$receipt")" "$package/compiler.image"
    for name in NOTICE.md notices/LuaJIT-COPYRIGHT.txt notices/Rust-dependencies.html notices/libffi-LICENSE.txt notices/lunajson-LICENSE.txt; do printf 'test notice\n' > "$package/$name"; done
    files='{}'
    for name in runtime compiler.image NOTICE.md notices/LuaJIT-COPYRIGHT.txt notices/Rust-dependencies.html notices/libffi-LICENSE.txt notices/lunajson-LICENSE.txt; do
        files=$(jq --arg name "$name" --arg sha "$(sha "$package/$name")" '.[$name]=$sha' <<< "$files")
    done
    runtime_sha=$(sha "$package/runtime")
    jq -n --arg host "$host" --arg revision "$ADVANCE_REVISION" --arg runtime "$runtime_sha" --arg image "$image_sha" --argjson files "$files" \
        '{format:"nupp-bootstrap-seed-1",host:$host,sourceRevision:$revision,execution:"new-images-with-aot-disabled",runtimeSha256:$runtime,imageSha256:$image,files:$files}' > "$package/manifest.json"
    archive="nupp-seed-$host-$ADVANCE_REVISION.tar.gz"
    COPYFILE_DISABLE=1 tar -czf "$ADVANCE_FIXTURE/assets/$archive" -C "$package" NOTICE.md compiler.image manifest.json notices/LuaJIT-COPYRIGHT.txt notices/Rust-dependencies.html notices/libffi-LICENSE.txt notices/lunajson-LICENSE.txt runtime
    proof="$ADVANCE_FIXTURE/workflow/native-bootstrap-refresh-$host-$ADVANCE_REVISION"
    mkdir -p "$proof"
    jq -n --arg host "$host" --arg revision "$ADVANCE_REVISION" --arg tag "$ADVANCE_TAG" --arg image "$image_sha" \
        --arg compressed "$compressed_sha" --arg asset "$asset" --arg runtime "$runtime_sha" --arg sha "$(sha "$ADVANCE_FIXTURE/assets/$archive")" \
        --arg url "https://github.com/test/nupp/releases/download/$ADVANCE_TAG/$archive" --slurpfile pins "$out/pins-before.json" \
        '{host:$host,sourceRevision:$revision,workflowRevision:$revision,releaseId:12,tag:$tag,imageSha256:$image,compressedImageSha256:$compressed,imageAsset:$asset,runtimeSha256:$runtime,sha256:$sha,url:$url,previousPin:$pins[0].hosts[$host]}' > "$proof/receipt.json"
done
first="$ADVANCE_FIXTURE/workflow/native-bootstrap-refresh-${hosts[0]}-$ADVANCE_REVISION/receipt.json"
cp "$first" "$temporary/good-proof.json"
jq '.runtimeSha256="ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' "$first" > "$first.tmp"; mv "$first.tmp" "$first"
if "$helper" --resume "$receipt" --run 42 > "$temporary/bad-runtime.log" 2>&1; then exit 97; fi
grep -q 'invalid .* workflow receipt' "$temporary/bad-runtime.log"
cmp scripts/bootstrap-seeds.json "$out/pins-before.json"
cp "$temporary/good-proof.json" "$first"
if ADVANCE_FAIL_FIXPOINT=1 "$helper" --resume "$receipt" --run 42 > "$temporary/failed-fixpoint.log" 2>&1; then exit 98; fi
grep -q 'published-pair fixpoint failed' "$temporary/failed-fixpoint.log"
cmp scripts/bootstrap-seeds.json "$out/pins-before.json"
archive="$out/archives/nupp-seed-${hosts[0]}-$ADVANCE_REVISION.tar.gz"
cp "$archive" "$temporary/good-archive.tar.gz"
printf 'corrupt' >> "$archive"
if "$helper" --resume "$receipt" --run 42 > "$temporary/bad-archive.log" 2>&1; then exit 100; fi
grep -q 'archive digest mismatch' "$temporary/bad-archive.log"
cmp scripts/bootstrap-seeds.json "$out/pins-before.json"
cp "$temporary/good-archive.tar.gz" "$archive"
"$helper" --resume "$receipt" --run 42 > "$temporary/finish.log" 2>&1 || { cat "$temporary/finish.log"; exit 99; }
test "$(git log -1 --format=%s)" = "Move the stage-zero pin to $ADVANCE_TAG"
test "$(git diff --name-only HEAD^ HEAD)" = scripts/bootstrap-seeds.json
test -z "$(git status --porcelain)"
jq -e --arg image "$image_sha" '[.hosts[].imageSha256] | all(. == $image)' scripts/bootstrap-seeds.json >/dev/null
jq -e '.publishedPairFixpoint == true' "$out/pin-commit.json" >/dev/null
printf 'PASS runtime preservation, failed-fixpoint pin preservation, all-host archive verification, pin-only commit\n'
