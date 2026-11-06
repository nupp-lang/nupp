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
local ENV = "NUPP_VM_CLI_IMAGE= NUPP_VM_BINARY= NUPP_VM_AUTO_LINK= NUPP_VM_AUTO_REBUILD=" .. " NUPP_VM_AUTO_LINK=0"

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
        readFile(dir .. "/builds.log"):find("build --seed vm --no-aot", 1, true),
        "the rebuild lowers with the installed generation"
    )
    out = ran(dir, "check")
    assert(out:find("RAN gen1 check", 1, true) and builds(dir) == 1, "a current generation was rebuilt: " .. out)
    remove(dir)
end

function M.aDefaultRebuildPublishesTheLinkedReplacement()
    local dir = plantedTree()
    edit(dir)
    local out = ran(dir, "check", "NUPP_VM_AUTO_LINK=1")
    assert(out:find("RAN gen1 check", 1, true), out)
    local commands = assert(readFile(dir .. "/builds.log"))
    assert(commands:find("build --seed vm\n", 1, true), "the replacement was not built with its compiled code")
    assert(not commands:find("--no-aot", 1, true), "an interpreter-only generation was published")
    assert(not commands:find("link\n", 1, true), "linking was deferred until after publication")
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

-- A failed rebuild is remembered from the moment it started, so an edit made
-- while it ran is a reason to try again.
function M.anEditDuringAFailedRebuildIsBuiltNextTime()
    local dir, plant = plantedTree()
    plant("fail-build", "")
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
    assert(builds(dir) == 1 and readFile(dir .. "/first.txt"):find("did not build", 1, true))
    os.remove(dir .. "/fail-build")
    local out = ran(dir, "check")
    assert(builds(dir) == 2, "the edit made during the failed build was never built: " .. out)
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
    local json = require("serde.json")
    local before = assert(json.decodevalue(capture(("cd '%s' && python3 scripts/vm-cli status"):format(dir))))
    local selected = readFile(dir .. "/.nupp/vm-cli/current"):match("%x+")
    local receipt = json.decodevalue(readFile(dir .. "/.nupp/vm-cli/" .. selected .. "/receipt.json"))
    receipt.sourceAtInstall = before.sourceNow
    receipt.sourceRead = "install"
    plant(".nupp/vm-cli/" .. selected .. "/receipt.json", json.encodevalue(receipt))

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
    if package.config:sub(1, 1) == "\\" then
        require("assert").suite.skip("the fixture runtime is a shell script, which Windows cannot execute")
    end
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

function M.macCacheWrapperKeepsStartupPathsShortWithoutChangingBuildTemps()
    if package.config:sub(1, 1) == "\\" then
        require("assert").suite.skip("the cache-wrapper fixture executes POSIX shell scripts")
    end
    local dir, plant = plantedTree()
    assert(os.execute(("cp '%s/rust-toolchain.toml' '%s/rust-toolchain.toml'"):format(ROOT, dir)) == 0)
    assert(os.execute(("cp '%s/scripts/vm-cli' '%s/scripts/vm-cli-real'"):format(ROOT, dir)) == 0)
    plant(
        "cache-control.py",
        [=[
import json, os, runpy, subprocess, sys
from pathlib import Path
from unittest import mock
root = Path.cwd()
fakes = root / 'fakes'
fakes.mkdir()
def script(name, body):
    path = fakes / name
    path.write_text(body)
    path.chmod(0o755)
    return path
script('sccache', '#!/bin/sh\nprintf "%s\\n" "$TMPDIR"\nprintf "%s\\n" "$@"\n')
uname = script('uname', '#!/bin/sh\nif [ "$1" = -s ]; then printf "%s\\n" "$FAKE_SYSTEM"; else /usr/bin/uname "$@"; fi\n')
cargo = script('cargo-probe', '#!/usr/bin/env python3\nimport json, os\nfrom pathlib import Path\nPath(os.environ["WRAPPER_LOG"]).write_text(json.dumps({"wrapper":os.environ.get("RUSTC_WRAPPER"),"tmpdir":os.environ.get("TMPDIR")}))\nraise SystemExit(17)\n')
selected = (root / '.nupp/vm-cli/current').read_text().strip()
runtime = root / '.nupp/vm-cli' / selected / 'runtime'
runtime.write_text('#!/bin/sh\nprintf "%s\\n" "$RUSTC_WRAPPER"\n')
runtime.chmod(0o755)
base = dict(os.environ, PATH=str(fakes) + os.pathsep + os.environ['PATH'],
            TMPDIR=str(root / ('long-task-temp-' * 12)), NUPP_VM_AUTO_REBUILD='0',
            NUPP_VM_AUTO_LINK='0', NUPP_VM_CLI_IMAGE='', NUPP_VM_BINARY='',
            NUPP_CARGO=str(cargo), NUPP_RUSTC=str(cargo),
            NUPP_CACHE_DIR=str(root / 'cache'), WRAPPER_LOG=str(root / 'wrapper.json'))
base.pop('RUSTC_WRAPPER', None)
wrapper = str(root / 'scripts/sccache-wrapper')
def same_wrapper(actual, expected):
    return actual == expected or (os.path.isabs(actual or '') and os.path.isabs(expected) and Path(actual).resolve() == Path(expected).resolve())
for system, expected in [('Darwin', wrapper), ('Linux', 'sccache')]:
    for explicit in [None, '', 'custom-cache']:
        env = dict(base, FAKE_SYSTEM=system)
        if explicit is not None:
            env['RUSTC_WRAPPER'] = explicit
        want = expected if explicit is None else explicit
        result = subprocess.run(['sh', 'bin/nupp', '--help'], env=env, capture_output=True, text=True)
        assert result.returncode == 0 and same_wrapper(result.stdout.strip(), want), (system, result.stdout, result.stderr)
        # Stop at the version probe: test selection without any Rust build.
        result = subprocess.run(['sh', 'scripts/toolchain', 'vm-runtime'], env=env, capture_output=True, text=True)
        assert result.returncode != 0 and (root / 'wrapper.json').exists(), result.stderr
        value = json.loads((root / 'wrapper.json').read_text())
        assert same_wrapper(value['wrapper'], want) and value['tmpdir'] == base['TMPDIR'], value
        (root / 'wrapper.json').unlink()
module = runpy.run_path('scripts/vm-cli-real', run_name='wrapper_test')
call = module['cargo']
seen = []
call.__globals__['run_step'] = lambda command, env, what: seen.append(env)
for platform, expected in [('darwin', wrapper), ('linux', 'sccache'), ('win32', 'sccache')]:
    for explicit in [None, '', 'custom-cache']:
        env = dict(base)
        if explicit is not None:
            env['RUSTC_WRAPPER'] = explicit
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(sys, 'platform', platform), mock.patch.object(module['shutil'], 'which', return_value=str(fakes / 'sccache')):
            call(None, root / 'target')
        assert seen[-1]['RUSTC_WRAPPER'] == (expected if explicit is None else explicit), seen[-1]
        assert seen[-1]['TMPDIR'] == base['TMPDIR']
# Only the sccache process gets short temporary paths, and arguments stay intact.
result = subprocess.run([wrapper, '/compiler with spaces', '--flag'], env=base, capture_output=True, text=True)
assert result.returncode == 0 and result.stdout.splitlines() == ['/private/tmp', '/compiler with spaces', '--flag'], result
assert base['TMPDIR'].startswith(str(root))
print('CACHE_WRAPPER_OK')
]=]
    )
    local output = capture(("cd '%s' && python3 cache-control.py 2>&1"):format(dir))
    assert(output:find("CACHE_WRAPPER_OK", 1, true), output)
    remove(dir)
end

function M.runtimeCacheExcludesOnlyIndependentCoreAndVerifiesEveryArtifact()
    local dir, plant = plantedTree()
    assert(os.execute(("cp '%s/scripts/vm-cli' '%s/scripts/vm-cli'"):format(ROOT, dir)) == 0)
    plant(
        "runtime-cache-control.py",
        [=[
import contextlib, io, json, runpy, subprocess
from pathlib import Path
from types import SimpleNamespace
root = Path.cwd()
fixtures = {
    'src/runtime-input.nupp': 'runtime source',
    'native/crates/vm/src/input.rs': 'Rust glue',
    'native/core/tests/receipt.json': 'independent core receipt',
    'scripts/runtime-input': 'build script',
    'Cargo.toml': 'workspace',
    'Cargo.lock': 'locked dependencies',
    'rust-toolchain.toml': 'pinned toolchain',
    '.cargo/config.toml': 'Rust configuration',
}
for name, contents in fixtures.items():
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents)
subprocess.run(['git', 'init', '-q'], check=True)
subprocess.run(['git', 'add', 'src', 'native', 'scripts', 'bin', 'templates',
                'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml', '.cargo'], check=True)
module = runpy.run_path('scripts/vm-cli', run_name='runtime_cache_test')
runtime = module['runtime']
state = module['source_state']
runtime_state = module['runtime_source_state']
digest = module['digest']
out = root / 'build/native-runtime'
out.mkdir(parents=True)
seed = root / 'seed'
seed.mkdir()
(seed / 'manifest.json').write_text('verified seed fixture')
class CacheMiss(Exception):
    pass
def stop_before_build(*args, **kwargs):
    raise CacheMiss()
runtime.__globals__['execution_seed'] = lambda: seed
runtime.__globals__['cargo'] = stop_before_build
args = SimpleNamespace(reuse=True, link=False, no_cache=False)
artifacts = ('runtime.clif', 'runtime.o', 'runtime.o.rs')
def receipt():
    for name in artifacts:
        (out / name).write_text('artifact fixture: ' + name)
    value = {'inputs': {'source': runtime_state()['fingerprint'],
                        'seed': digest(seed / 'manifest.json')},
             'artifacts': {name: digest(out / name) for name in artifacts}}
    (out / 'source.json').write_text(json.dumps(value))
    return value
def reuse(expected):
    captured = io.StringIO()
    try:
        with contextlib.redirect_stdout(captured):
            runtime(args)
    except CacheMiss:
        assert not expected, 'matching runtime unexpectedly rebuilt'
    else:
        assert expected, 'changed input or invalid output was reused'
        assert captured.getvalue().strip() == str(out / 'runtime.o')
receipt()
reuse(True)
base_cli, base_runtime = state()['fingerprint'], runtime_state()['fingerprint']
core = root / 'native/core/tests/receipt.json'
core.write_text('changed independent receipt')
assert state()['fingerprint'] != base_cli, 'CLI freshness lost native/core'
assert runtime_state()['fingerprint'] == base_runtime
reuse(True)
core.unlink()
assert state()['fingerprint'] != base_cli
assert runtime_state()['fingerprint'] == base_runtime
reuse(True)
core.write_text(fixtures['native/core/tests/receipt.json'])
addition = root / 'native/core/new-input.nupp'
addition.write_text('untracked independent core source')
assert state()['fingerprint'] != base_cli
assert runtime_state()['fingerprint'] == base_runtime
reuse(True)
addition.unlink()
assert state()['fingerprint'] == base_cli
# Every other previously keyed input remains keyed, including seed contents.
for name in fixtures:
    if name.startswith('native/core/'):
        continue
    path = root / name
    original = path.read_bytes()
    path.write_bytes(original + b' changed')
    assert runtime_state()['fingerprint'] != base_runtime, name
    reuse(False)
    path.write_bytes(original)
    reuse(True)
manifest = seed / 'manifest.json'
original = manifest.read_bytes()
manifest.write_bytes(original + b' changed')
reuse(False)
manifest.write_bytes(original)
reuse(True)
for name in artifacts:
    receipt()
    (out / name).write_text('corrupt output')
    reuse(False)
    receipt()
    (out / name).unlink()
    reuse(False)
    value = receipt()
    del value['artifacts'][name]
    (out / 'source.json').write_text(json.dumps(value))
    reuse(False)
value = receipt()
value['artifacts']['unrelated'] = 'not a build artifact'
(out / 'source.json').write_text(json.dumps(value))
reuse(False)
for malformed in ([], {'inputs': receipt()['inputs'], 'artifacts': None}):
    (out / 'source.json').write_text(json.dumps(malformed))
    reuse(False)
value = receipt()
value['inputs']['source'] = None
(out / 'source.json').write_text(json.dumps(value))
runtime.__globals__['runtime_source_state'] = lambda: {'fingerprint': None}
reuse(False)
runtime.__globals__['runtime_source_state'] = runtime_state
receipt()
reuse(True)
print('RUNTIME_CACHE_SCOPE_OK')
]=]
    )
    local output = capture(("cd '%s' && python3 runtime-cache-control.py 2>&1"):format(dir))
    assert(output:find("RUNTIME_CACHE_SCOPE_OK", 1, true), output)
    remove(dir)
end

return M
