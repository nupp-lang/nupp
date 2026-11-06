-- The real `scripts/vm-cli build`, and what the generation it installs vouches for.
--
-- `tests/vmclilaunchertest.lua` holds the launcher's decisions against a
-- stand-in `scripts/vm-cli`. These cases run the real one in a planted tree
-- whose tools are shell scripts: a runtime that "emits" an image naming the
-- bytes of the one compiler source it read and logs who asked, a `cargo` that
-- copies that runtime, and a stage zero that is that runtime too. What they
-- hold is the bookkeeping: a generation is current only for the sources its
-- build read, each rebuild is lowered by the newest generation and is told the
-- interpreter it runs on, and a link keeps what the build vouched for.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local ROOT = HERE .. "/.."

local M = {}

-- A runtime: `run ... emit` reads `src/compiler.nupp`, then edits it when
-- `edit-during-emit` asks, then writes an image naming what it read; `exec`
-- names the image it was handed. Every emit is logged with what it was told.
local RUNTIME = [=[#!/bin/sh
command=$1
shift
output=
previous=
for argument in "$@"; do
    [ "$previous" = --output ] && output=$argument
    previous=$argument
done
case "$command" in
    verify) ;;
    exec)
        image=$1
        shift 2
        case " $* " in *" --help "*) echo "Usage: fixture root CLI"; exit 0 ;; esac
        printf 'RAN %s %s\n' "$(head -n 1 "$image")" "$*"
        ;;
    run)
        if [ "$2" = nupp.tools.vm.project ]; then
            printf 'emit by=%s id=%s cache=%s\n' "$1" "${NUPP_VM_RUNTIME_ID:-}" "${NUPP_VM_EMIT_CACHE:-}" >> emits.log
            read=$(cksum < src/compiler.nupp | cut -d ' ' -f 1)
            if [ -f edit-during-emit ]; then
                rm -f edit-during-emit
                printf -- '-- edited after the build read it\n' >> src/compiler.nupp
            fi
            printf 'image %s\nnupp.tools.vm.root\n' "$read" > "$output"
        else
            echo clif > "$output"
        fi
        ;;
    native)
        case "$1" in
            layouts) echo '{}' > "$2" ;;
            object) echo object > "$3" ;;
        esac
        ;;
    aot) echo object > "$2" ;;
    *) exit 9 ;;
esac
]=]

-- `cargo build`: the runtime above, marked with the features it was asked for,
-- so a linked runtime is other bytes than the interpreter it replaces.
local CARGO = [=[#!/bin/sh
out="$CARGO_TARGET_DIR/release/nupp-vm"
mkdir -p "$CARGO_TARGET_DIR/release"
cp "$FIXTURE_RUNTIME" "$out.new"
printf '# cargo %s\n' "$*" >> "$out.new"
chmod +x "$out.new"
mv "$out.new" "$out"
]=]

local TOOLCHAIN = [=[#!/bin/sh
[ "$1" = stage0-seed ] && echo "$PWD/seed"
]=]

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function readFile(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local text = file:read("*a")
    file:close()

    return text
end

-- What the tree's commands run with: its tools first, and no background link.
local function environment(dir)
    return ("PATH=%s/fakebin:\"$PATH\" FIXTURE_RUNTIME=%s/runtime.fixture NUPP_VM_CLI_IMAGE= NUPP_VM_BINARY= "
        .. "NUPP_VM_RUNTIME_ID= NUPP_VM_AUTO_REBUILD= NUPP_VM_AUTO_LINK=0 RUSTC_WRAPPER="):format(
        quote(dir),
        quote(dir)
    )
end

-- Runs `command` in the tree: its exit status and everything it printed.
local function run(dir, command)
    local pipe = assert(
        io.popen(("cd %s && %s %s 2>&1; echo __exit__:$?"):format(quote(dir), environment(dir), command))
    )
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__exit__:(%d+)%s*$"))

    return status, (output:gsub("__exit__:%d+%s*$", ""))
end

local function emits(dir)
    local lines = {}
    for line in (readFile(dir .. "/emits.log") or ""):gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end

    return lines
end

local function selected(dir)
    return assert(readFile(dir .. "/.nupp/vm-cli/current")):match("%x+")
end

local function receipt(dir)
    local json = require("serde.json")
    return json.decodevalue(assert(readFile(dir .. "/.nupp/vm-cli/" .. selected(dir) .. "/receipt.json")))
end

local function edit(dir)
    local file = assert(io.open(dir .. "/src/compiler.nupp", "ab"))
    file:write("-- edited\n")
    file:close()
end

-- A tree with one generation installed from its sources as they are.
local function plantedTree()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute(("mkdir -p %s"):format(quote(dir))) == 0)
    -- As `scripts/vm-cli` names it: with every link resolved.
    local resolved = assert(io.popen(("cd %s && pwd -P"):format(quote(dir))))
    dir = assert(resolved:read("*l"))
    resolved:close()
    local function plant(path, text, executable)
        assert(os.execute(("mkdir -p %s"):format(quote((dir .. "/" .. path):match("^(.*)/[^/]+$")))) == 0)
        local file = assert(io.open(dir .. "/" .. path, "wb"))
        file:write(text)
        file:close()
        if executable then
            assert(os.execute(("chmod +x %s"):format(quote(dir .. "/" .. path))) == 0)
        end
    end

    assert(os.execute(("mkdir -p %s/bin %s/templates"):format(quote(dir), quote(dir))) == 0)
    assert(os.execute(("cp %s/bin/nupp %s/bin/nupp"):format(quote(ROOT), quote(dir))) == 0)
    assert(os.execute(("cp -R %s/scripts %s/scripts"):format(quote(ROOT), quote(dir))) == 0)
    plant("src/compiler.nupp", "-- a compiler source\n")
    plant("src/nupp/tools/vm/project.nupp", 'project.ROOT_EXTRAS = {"fixture.extra"}\n\n')
    plant("runtime.fixture", RUNTIME, true)
    plant("fakebin/cargo", CARGO, true)
    plant("scripts/toolchain", TOOLCHAIN, true)
    -- The seed's verifier, run as a Python script: an empty one accepts.
    plant("scripts/bootstrap-seed", "")
    plant("seed/runtime", RUNTIME, true)
    plant("seed/compiler.image", "image seed\nnupp.tools.vm.root\n")
    plant("seed/manifest.json", "{}\n")
    plant("start.image", "image start\nnupp.tools.vm.root\n")
    assert(os.execute(("cd %s && git init -q"):format(quote(dir))) == 0)
    local status, out = run(dir, "python3 scripts/vm-cli install --runtime runtime.fixture --image start.image")
    assert(status == 0, out)

    return dir
end

local function remove(dir)
    os.execute(("rm -rf %s"):format(quote(dir)))
end

-- The sources a build fingerprints are the ones before it read any. An edit
-- made after the read is in neither the image nor what the receipt vouches
-- for, so the generation is not current, and the next command rebuilds.
function M.anEditAfterTheBuildReadItIsBuiltNextTime()
    local dir = plantedTree()
    edit(dir)
    assert(io.open(dir .. "/edit-during-emit", "wb")):close()
    local status, out = run(dir, "python3 scripts/vm-cli build --seed vm --no-aot")
    assert(status == 0, out)
    assert(out:find("sources changed while this build read them", 1, true), out)
    assert(receipt(dir).sourceRead == "build-start", "the receipt does not say how its sources were read")
    status, out = run(dir, "python3 scripts/vm-cli current")
    assert(status == 1, "a generation that never read the last edit is current: " .. out)

    status, out = run(dir, "./bin/nupp check")
    assert(#emits(dir) == 2, "the edit made after the build read it was never built: " .. out)
    local image = readFile(dir .. "/.nupp/vm-cli/" .. selected(dir) .. "/compiler.image")
    assert(out:find("RAN " .. image:match("^[^\n]+") .. " check", 1, true), out)
    status, out = run(dir, "python3 scripts/vm-cli current")
    assert(status == 0, "the rebuilt generation read these sources: " .. out)
    remove(dir)
end

-- Unchanged sources are a hit however their times say otherwise: a touched
-- source is checked by content, and the generation is still current.
function M.unchangedSourcesNeedNoBuild()
    local dir = plantedTree()
    local _, out = run(dir, "./bin/nupp check")
    assert(out:find("RAN image start check", 1, true) and #emits(dir) == 0, out)
    assert(os.execute(("sleep 1 && touch %s"):format(quote(dir .. "/src/compiler.nupp"))) == 0)
    _, out = run(dir, "./bin/nupp check")
    assert(out:find("RAN image start check", 1, true), out)
    assert(#emits(dir) == 0, "a touched, unchanged source rebuilt the compiler: " .. out)
    remove(dir)
end

-- Every rebuild is lowered by the newest generation, the one the last rebuild
-- installed, told the interpreter its runtime computes with, into the one emit
-- cache that keys by both. Nothing is pinned, and the trees an older vm-cli
-- kept per image go.
function M.theNewestGenerationLowersEveryRebuild()
    local dir = plantedTree()
    local legacy = dir .. "/build/vm-cli/emit-cache/compilers/old"
    assert(os.execute(("mkdir -p %s"):format(quote(legacy))) == 0)
    assert(io.open(dir .. "/.nupp/vm-cli/emitter", "wb")):close()
    local generations = {selected(dir)}
    for _ = 1, 2 do
        edit(dir)
        local _, out = run(dir, "./bin/nupp check")
        assert(out:find("rebuilt the VM compiler", 1, true), out)
        generations[#generations + 1] = selected(dir)
    end
    local lines = emits(dir)
    assert(#lines == 2, table.concat(lines, "\n"))
    for index, line in ipairs(lines) do
        local package = dir .. "/.nupp/vm-cli/" .. generations[index]
        local by, id, cache = line:match("^emit by=(%S+) id=(%S*) cache=(%S*)$")
        assert(by == package .. "/compiler.image", "emit " .. index .. " was not lowered by the newest: " .. line)
        local named = assert(readFile(package .. "/runtime-identity"), "no runtime identity"):match("%x+")
        assert(id == named, "emit " .. index .. " was told another interpreter: " .. line)
        assert(cache == dir .. "/build/vm-cli/emit-cache", "emit " .. index .. " cache: " .. line)
    end
    assert(readFile(dir .. "/.nupp/vm-cli/emitter") == nil, "a pin was left behind")
    assert(io.open(legacy) == nil, "the per-image cache trees were kept")
    remove(dir)
end

-- A link replaces the runtime and keeps what the build vouched for: the sources
-- it read, not the ones there when the link finishes, and the interpreter the
-- generation's emits are keyed by.
function M.aLinkKeepsWhatTheBuildVouchedFor()
    local dir = plantedTree()
    edit(dir)
    assert(io.open(dir .. "/edit-during-emit", "wb")):close()
    local status, out = run(dir, "python3 scripts/vm-cli build --seed vm --no-aot")
    assert(status == 0, out)
    local built = receipt(dir)
    status, out = run(dir, "python3 scripts/vm-cli link")
    assert(status == 0, out)
    local linked = receipt(dir)
    assert(linked.linked == true and linked.runtimeSha256 ~= built.runtimeSha256, "nothing was linked")
    assert(linked.runtimeIdentity == built.runtimeIdentity, "the link changed the interpreter it names")
    assert(linked.sourceAtInstall.fingerprint == built.sourceAtInstall.fingerprint, "the link vouched anew")
    status, out = run(dir, "python3 scripts/vm-cli current")
    assert(status == 1, "linking made a generation current for an edit it never read: " .. out)
    remove(dir)
end

return M
