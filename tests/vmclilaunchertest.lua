-- The launcher keeping an installed VM compiler current.
--
-- `bin/nupp` runs the generation `.nupp/vm-cli/current` selects, and rebuilds it
-- first when a compiler source is newer than the stamp the last build left. These
-- cases plant a tree whose generations are shell scripts that say which image
-- they were handed, and whose `scripts/vm-cli` is a stand-in that installs a new
-- one (or fails to) and logs that it was asked. What they test is the launcher's
-- decisions: when to rebuild, that concurrent commands share one rebuild, that a
-- failed one leaves the previous generation running, and what bypasses it all.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local ROOT = HERE .. "/.."

local M = {}

local function capture(command)
    local p = assert(io.popen(command))
    local out = p:read("*a")
    p:close()
    return out
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

-- Installs a generation labelled LABEL: its image is the label and its runtime
-- prints the image it was handed, so the output names the generation that ran.
local GENERATION = [=[
import hashlib, os
def generation(packages, label):
    digest = hashlib.sha256(label.encode()).hexdigest()
    package = os.path.join(packages, digest)
    os.makedirs(package, exist_ok=True)
    with open(os.path.join(package, "format"), "w") as f:
        f.write("nupp-vm-cli-1\n")
    with open(os.path.join(package, "compiler.image"), "w") as f:
        f.write(label + "\n")
    runtime = os.path.join(package, "runtime")
    with open(runtime, "w") as f:
        f.write('#!/bin/sh\nprintf "RAN %s %s\\n" "$(cat "$2")" "$4"\n')
    os.chmod(runtime, 0o755)
    pending = os.path.join(packages, ".current-new")
    with open(pending, "w") as f:
        f.write(digest + "\n")
    os.replace(pending, os.path.join(packages, "current"))
]=]

-- The stand-in for `scripts/vm-cli`: `build` takes its stamp when it starts, as the
-- real one does, waits FAKE_BUILD_SECONDS, fails when `fail-build` exists, and
-- otherwise installs the next generation.
local FAKE_VM_CLI = [=[#!/usr/bin/env python3
import os, sys, tempfile, time
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKAGES = os.path.join(ROOT, ".nupp/vm-cli")
sys.path.insert(0, os.path.join(ROOT, "scripts"))
from generation import generation
command = sys.argv[1]
# This fixture has no source receipt. The real-script control tests content matches.
if command == "current":
    sys.exit(1)
with open(os.path.join(ROOT, "builds.log"), "a") as log:
    log.write(" ".join(sys.argv[1:]) + "\n")
if command == "build":
    handle, stamp = tempfile.mkstemp(prefix=".stamp-", dir=PACKAGES)
    os.close(handle)
    time.sleep(float(os.environ.get("FAKE_BUILD_SECONDS", "0")))
    if os.path.exists(os.path.join(ROOT, "fail-build")):
        os.unlink(stamp)
        print("fake emit failed", file=sys.stderr)
        sys.exit(1)
    with open(os.path.join(ROOT, "builds.log")) as log:
        count = sum(1 for line in log if line.startswith("build"))
    generation(PACKAGES, "gen%d" % count)
    os.replace(stamp, os.path.join(PACKAGES, "stamp"))
]=]

local function plantedTree()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute(("mkdir -p '%s/bin' '%s/src' '%s/templates' '%s/.nupp/vm-cli'"):format(dir, dir, dir, dir)) == 0)
    assert(os.execute(("cp '%s/bin/nupp' '%s/bin/nupp'"):format(ROOT, dir)) == 0)
    assert(os.execute(("cp -R '%s/scripts' '%s/scripts'"):format(ROOT, dir)) == 0)

    local function plant(path, text)
        local file = assert(io.open(dir .. "/" .. path, "wb"))
        file:write(text)
        file:close()
    end

    plant("scripts/generation.py", GENERATION)
    plant("scripts/vm-cli", FAKE_VM_CLI)
    assert(os.execute(("chmod +x '%s/scripts/vm-cli'"):format(dir)) == 0)
    plant("src/compiler.nupp", "-- a compiler source\n")
    -- The generation the tree starts with, built from sources older than its stamp.
    assert(
        os.execute(
            (
                "cd '%s' && python3 -c 'import sys; sys.path.insert(0, \"scripts\"); "
                .. "from generation import generation; generation(\".nupp/vm-cli\", \"gen0\")'"
            ):format(dir)
        ) == 0
    )
    plant(".nupp/vm-cli/stamp", "")
    assert(
        os.execute(
            ("touch -t 202001010000 '%s/src/compiler.nupp' '%s/templates' '%s'/scripts/*"):format(dir, dir, dir)
        ) == 0
    )
    assert(os.execute(("touch -t 202001020000 '%s/.nupp/vm-cli/stamp'"):format(dir)) == 0)

    return dir, plant
end

-- Run without a selected image, as a person at a terminal would, and without the
-- background link, which would outlive the case.
local ENV = "NUPP_VM_CLI_IMAGE= NUPP_VM_BINARY= NUPP_VM_AUTO_LINK= NUPP_VM_AUTO_REBUILD="
    .. " NUPP_VM_AUTO_LINK=0"

local function ran(dir, command, env)
    return capture(("cd '%s' && %s %s ./bin/nupp %s 2>&1"):format(dir, ENV, env or "", command))
end

local function builds(dir)
    local count = 0
    for line in (readFile(dir .. "/builds.log") or ""):gmatch("[^\n]+") do
        if line:match("^build") then
            count = count + 1
        end
    end

    return count
end

local function edit(dir)
    local file = assert(io.open(dir .. "/src/compiler.nupp", "ab"))
    file:write("-- edited\n")
    file:close()
end

local function remove(dir)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aCurrentGenerationRunsWithoutABuild()
    local dir = plantedTree()
    local out = ran(dir, "check")
    assert(out:find("RAN gen0 check", 1, true), out)
    assert(builds(dir) == 0, "nothing changed, and something was built")
    remove(dir)
end

function M.aSourceEditRebuildsBeforeTheCommandRuns()
    local dir = plantedTree()
    edit(dir)
    local out = ran(dir, "check")
    assert(out:find("rebuilding the VM compiler", 1, true), out)
    assert(out:find("RAN gen1 check", 1, true), "the command did not run the rebuilt generation: " .. out)
    assert(builds(dir) == 1, "one edit, one build")
    assert(
        readFile(dir .. "/builds.log"):find("build --seed pinned --no-aot", 1, true),
        "the rebuild lowers with the pinned one"
    )
    out = ran(dir, "check")
    assert(out:find("RAN gen1 check", 1, true) and builds(dir) == 1, "a current generation was rebuilt: " .. out)
    remove(dir)
end

function M.concurrentCommandsShareOneRebuild()
    local dir = plantedTree()
    edit(dir)
    local script = (
        [[
        cd '%s'
        for n in 1 2 3; do
            %s FAKE_BUILD_SECONDS=2 ./bin/nupp check > ran$n.txt 2>&1 &
        done
        wait
    ]]
    ):format(dir, ENV)
    capture(script)
    assert(builds(dir) == 1, "three commands started " .. builds(dir) .. " builds")
    for n = 1, 3 do
        local out = readFile(dir .. "/ran" .. n .. ".txt") or ""
        assert(out:find("RAN gen1 check", 1, true), "command " .. n .. " did not run the shared build: " .. out)
    end
    remove(dir)
end

function M.aFailedRebuildKeepsThePreviousGeneration()
    local dir, plant = plantedTree()
    plant("fail-build", "")
    edit(dir)
    local out = ran(dir, "check")
    assert(out:find("did not build", 1, true), out)
    assert(out:find("fake emit failed", 1, true), "the failure's own words are shown: " .. out)
    assert(out:find("RAN gen0 check", 1, true), "the previous generation did not run: " .. out)

    -- The same sources would fail the same way: say so, and do not build again.
    out = ran(dir, "check")
    assert(builds(dir) == 1, "a failed build was retried without an edit")
    assert(out:find("did not build from these sources", 1, true) and out:find("RAN gen0", 1, true), out)

    -- The next edit is another chance.
    os.remove(dir .. "/fail-build")
    edit(dir)
    out = ran(dir, "check")
    assert(builds(dir) == 2 and out:find("RAN gen2 check", 1, true), out)
    remove(dir)
end

-- An edit made while a build runs is newer than the stamp that build leaves.
function M.anEditDuringARebuildIsBuiltNextTime()
    local dir = plantedTree()
    edit(dir)
    capture(
        (
            [[
        cd '%s'
        %s FAKE_BUILD_SECONDS=2 ./bin/nupp check > first.txt 2>&1 &
        sleep 1
        printf -- '-- during\n' >> src/compiler.nupp
        wait
    ]]
        ):format(dir, ENV)
    )
    assert(builds(dir) == 1, readFile(dir .. "/first.txt"))
    local out = ran(dir, "check")
    assert(builds(dir) == 2, "the edit made during the first build was never built: " .. out)
    assert(out:find("RAN gen2 check", 1, true), out)
    remove(dir)
end

-- A builder that died leaves its lock behind, and the next command takes it.
function M.aDeadBuildersLockIsTaken()
    local dir = plantedTree()
    assert(os.execute(("mkdir -p '%s/.nupp/vm-cli-build.lock'"):format(dir)) == 0)
    local pid = capture("sh -c 'echo $$'"):match("%d+")
    local file = assert(io.open(dir .. "/.nupp/vm-cli-build.lock/pid", "wb"))
    file:write(pid .. "\n")
    file:close()
    edit(dir)
    local out = ran(dir, "check")
    assert(builds(dir) == 1 and out:find("RAN gen1", 1, true), out)
    remove(dir)
end

function M.anExplicitImageBypassesTheRebuild()
    local dir = plantedTree()
    edit(dir)
    local generation = readFile(dir .. "/.nupp/vm-cli/current"):match("%x+")
    local package = dir .. "/.nupp/vm-cli/" .. generation
    local out = capture(
        (
            "cd '%s' && %s NUPP_VM_CLI_IMAGE='%s/compiler.image' NUPP_VM_BINARY='%s/runtime' ./bin/nupp check 2>&1"
        ):format(dir, ENV, package, package)
    )
    assert(out:find("RAN gen0 check", 1, true), out)
    assert(builds(dir) == 0, "an explicitly selected image was rebuilt")
    remove(dir)
end

function M.helpWorkersAndTheSwitchNeverRebuild()
    local dir = plantedTree()
    edit(dir)
    assert(ran(dir, "--help"):find("RAN gen0", 1, true))
    assert(ran(dir, "__comptime-worker"):find("RAN gen0", 1, true))
    assert(ran(dir, "check", "NUPP_VM_AUTO_REBUILD=0"):find("RAN gen0 check", 1, true))
    assert(builds(dir) == 0, "a command that asks for no rebuild built")
    remove(dir)
end

function M.aRunnerResourceEditRebuildsAndRetriesAfterFailure()
    local dir, plant = plantedTree()
    assert(os.execute(("mkdir -p '%s/tests'"):format(dir)) == 0)
    plant("tests/run.lua", "-- carried runner\n")
    assert(os.execute(("touch -t 202001010000 '%s/tests/run.lua'"):format(dir)) == 0)
    assert(ran(dir, "check"):find("RAN gen0 check", 1, true))
    assert(builds(dir) == 0)
    plant("fail-build", "")
    plant("tests/run.lua", "-- edited carried runner\n")
    assert(ran(dir, "check"):find("RAN gen0 check", 1, true))
    assert(builds(dir) == 1)
    assert(ran(dir, "check"):find("did not build from these sources", 1, true))
    assert(builds(dir) == 1)
    os.remove(dir .. "/fail-build")
    plant("tests/run.lua", "-- carried runner changed again\n")
    assert(ran(dir, "check"):find("RAN gen2 check", 1, true))
    assert(builds(dir) == 2, "a runner-only edit unlocked a failed rebuild")
    assert(ran(dir, "check"):find("RAN gen2 check", 1, true))
    assert(builds(dir) == 2, "the unchanged runner reused its generation")
    remove(dir)
end

function M.realSourceFingerprintIncludesRunnerBytesWithoutTimestamps()
    local dir, plant = plantedTree()
    assert(os.execute(("mkdir -p '%s/tests'"):format(dir)) == 0)
    plant("tests/run.lua", "-- original runner\n")
    assert(os.execute(("cp '%s/scripts/vm-cli' '%s/scripts/vm-cli'"):format(ROOT, dir)) == 0)
    assert(os.execute(("cd '%s' && git init -q && git add bin scripts src templates tests"):format(dir)) == 0)
    -- current/status validate only receipt bytes. This fake package never builds
    -- or runs a compiler; sourceNow supplies the actual script's fingerprint.
    plant(
        "receipt.py",
        [[
import hashlib, json
from pathlib import Path
root = Path('.')
package = root / '.nupp/vm-cli' / (root / '.nupp/vm-cli/current').read_text().strip()
digest = lambda name: hashlib.sha256((package / name).read_bytes()).hexdigest()
(package / 'receipt.json').write_text(json.dumps({
    'runtimeSha256': digest('runtime'), 'imageSha256': digest('compiler.image'),
    'sourceAtInstall': {'fingerprint': 'not-recorded'}
}))
]]
    )
    assert(os.execute(("cd '%s' && python3 receipt.py"):format(dir)) == 0)
    local json = require("nupp.codec.json")
    local before = assert(json.decode(capture(("cd '%s' && python3 scripts/vm-cli status"):format(dir))))
    local selected = readFile(dir .. "/.nupp/vm-cli/current"):match("%x+")
    local receipt = json.decode(readFile(dir .. "/.nupp/vm-cli/" .. selected .. "/receipt.json"))
    receipt.sourceAtInstall = before.sourceNow
    plant(".nupp/vm-cli/" .. selected .. "/receipt.json", json.encode(receipt))

    local function current()
        return capture(("cd '%s' && python3 scripts/vm-cli current; printf 'CURRENT:%%d\\n' $?"):format(dir))
    end

    assert(current():find("CURRENT:0", 1, true), "unchanged sources are current")
    plant("tests/run.lua", "-- changed runner bytes\n")
    assert(os.execute(("touch -t 202001010000 '%s/tests/run.lua'"):format(dir)) == 0)
    assert(current():find("CURRENT:1", 1, true), "runner bytes changed without a newer timestamp")
    plant("tests/run.lua", "-- original runner\n")
    assert(current():find("CURRENT:0", 1, true), "restored bytes restore the fingerprint")
    remove(dir)
end

function M.reinstallingIdenticalArtifactsRefreshesOnlyValidatedInstallProvenance()
    local dir, plant = plantedTree()
    assert(os.execute(("mkdir -p '%s/tests'"):format(dir)) == 0)
    plant("tests/run.lua", "-- original installed runner\n")
    assert(os.execute(("cp '%s/scripts/vm-cli' '%s/scripts/vm-cli'"):format(ROOT, dir)) == 0)
    plant(
        "runtime.fake",
        [=[#!/bin/sh
case "$1" in
    verify)
        if [ "${NUPP_INSTALL_FIXTURE_FAIL:-}" = verify ]; then
            echo 'fixture verifier rejected' >&2
            exit 7
        fi
        ;;
    exec)
        if [ "${NUPP_INSTALL_FIXTURE_FAIL:-}" = help ]; then
            echo 'fixture help rejected' >&2
            exit 8
        fi
        printf 'Usage: fixture root CLI\n'
        ;;
    *) exit 9 ;;
esac
]=]
    )
    plant("compiler.image", "module nupp.tools.vm.root 0 root\n")
    assert(os.execute(("chmod +x '%s/runtime.fake'"):format(dir)) == 0)
    assert(os.execute(("cd '%s' && git init -q && git add bin scripts src templates tests"):format(dir)) == 0)
    plant(
        "install-control.py",
        [=[
import hashlib, json, os, subprocess, sys
from pathlib import Path
root = Path.cwd()
packages = root / '.nupp/vm-cli'
def command(*args, expected=0, fail=None):
    env = dict(os.environ)
    env.pop('NUPP_INSTALL_FIXTURE_FAIL', None)
    if fail is not None:
        env['NUPP_INSTALL_FIXTURE_FAIL'] = fail
    result = subprocess.run([sys.executable, 'scripts/vm-cli', *args], env=env, capture_output=True, text=True)
    assert result.returncode == expected, (args, result.returncode, result.stdout, result.stderr)
    return result
install = ('install', '--runtime', 'runtime.fake', '--image', 'compiler.image', '--linked')
def status():
    return json.loads(command('status').stdout)
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
command(*install)
first = status()
command('current')
assert first['sourceChangedSinceInstall'] is False
selected = (packages / 'current').read_bytes()
package = Path(first['package'])
immutable = {name: (package / name).read_bytes() for name in ['runtime', 'compiler.image', 'format']}
original_hashes = {name: digest(package / name) for name in immutable}
receipt = (package / 'receipt.json').read_bytes()
stamp = (packages / 'stamp').read_bytes()
stamp_time = (packages / 'stamp').stat().st_mtime_ns
runner = root / 'tests/run.lua'
original_time = runner.stat()
runner.write_bytes(b'-- changed installed runner with restored timestamp\n')
os.utime(runner, ns=(original_time.st_atime_ns, original_time.st_mtime_ns))
assert runner.stat().st_mtime_ns == original_time.st_mtime_ns
command('current', expected=1)
stale = status()
assert stale['sourceChangedSinceInstall'] is True
assert stale['sourceNow']['fingerprint'] != first['receipt']['sourceAtInstall']['fingerprint']
for fail, message in [('verify', 'fixture verifier rejected'), ('help', 'fixture help rejected')]:
    result = command(*install, expected=1, fail=fail)
    assert message in result.stderr, result.stderr
    assert (packages / 'current').read_bytes() == selected
    assert (package / 'receipt.json').read_bytes() == receipt
    assert (packages / 'stamp').read_bytes() == stamp
    assert (packages / 'stamp').stat().st_mtime_ns == stamp_time
    assert {name: (package / name).read_bytes() for name in immutable} == immutable
    command('current', expected=1)
command(*install)
after = status()
command('current')
assert (packages / 'current').read_bytes() == selected
assert after['package'] == first['package']
assert {name: (package / name).read_bytes() for name in immutable} == immutable
assert {name: digest(package / name) for name in immutable} == original_hashes
assert after['receipt']['runtimeSha256'] == first['receipt']['runtimeSha256']
assert after['receipt']['imageSha256'] == first['receipt']['imageSha256']
assert after['receipt']['sourceAtInstall'] == after['sourceNow']
assert after['receipt']['sourceAtInstall'] != first['receipt']['sourceAtInstall']
assert after['sourceChangedSinceInstall'] is False
assert after['receipt']['sourceProvenance'] == first['receipt']['sourceProvenance']
assert after['receipt']['sourceProvenance'] == 'Source state at installation, not a claim that supplied artifacts were built from it.'
print('INSTALL_REFRESH_OK')
]=]
    )
    local output = capture(("cd '%s' && python3 install-control.py 2>&1"):format(dir))
    assert(output:find("INSTALL_REFRESH_OK", 1, true), output)
    remove(dir)
end

return M
