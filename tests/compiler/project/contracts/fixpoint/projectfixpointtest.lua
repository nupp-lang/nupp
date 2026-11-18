local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local process = fixture.process
local buildPlatform = fixture.buildPlatform
local write = fixture.write
local read = fixture.read
local tempProject = fixture.tempProject
local remove = fixture.remove

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

function M.binaryFixpointReadsThePlatformNamedHostOutput()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {targets = {dist = {
   kind = "binary", stub = "nupp", output = "out/app", entries = {"main"},
}}}, selfHost = {binary = "dist"}}]],
        ["src/main.nupp"] = "return 1\n",
    })
    local output = dir .. "/out/app.exe"
    local oldBuild, oldRun, oldHostKey = project.build, process.run, buildPlatform.hostKey
    project.build = function(_, opts)
        write(output, "same stamped bytes")
        opts.produced.artifact = output
        return 0
    end
    process.run = function(argv)
        testAssert.eq(argv[1], output .. ".stage1", "fixpoint executes the platform-named stage")
        write(output, "same stamped bytes")
        return 0
    end
    buildPlatform.hostKey = function()
        return "x86_64-pc-windows-msvc"
    end
    local ok, status = pcall(project.binaryFixpoint, dir, {result = {}})
    project.build, process.run, buildPlatform.hostKey = oldBuild, oldRun, oldHostKey
    remove(dir)
    assert(ok, status)
    testAssert.eq(status, 0, "the Windows executable suffix is shared with the build")
end

-- The core fixpoint (`nupp.tools.vm.fixpoint.runCore`) over a stand-in for the
-- core: a runtime that answers as the C bridge does when it is given nothing to
-- run, and otherwise "compiles" by copying the compiler it runs and writing a
-- runtime output beside it. `mode` decides that output: "same" writes the same
-- bytes every stage, "differ" writes the stage's count, and "vm" reaches for
-- the Rust VM the way a compiler starting a worker would.
local corefixpoint = require("nupp.tools.vm.fixpoint")
local BUNDLE = "NUPPCORE" .. string.rep("\0", 64) .. "a compiler"

local function coreFixture(mode)
    local dir = tempProject({})
    local runtime = dir .. "/nupp-core"
    write(
        runtime,
        table.concat(
            {
                "#!/bin/sh",
                'if [ "$#" -lt 3 ]; then',
                "    echo 'nupp-core: usage: nupp-core BUNDLE INPUT OUTPUT [ARGUMENT...]' >&2",
                "    exit 1",
                "fi",
                "out=$4",
                'mkdir -p "$out/runtime"',
                'cp "$1" "$out/compiler.bundle"',
                (
                    "count=$(cat '%s/count' 2>/dev/null || echo 0); count=$((count + 1)); echo $count > '%s/count'"
                ):format(dir, dir),
                ("mode=%s"):format(mode),
                'if [ "$mode" = differ ]; then',
                '    printf "runtime %s\\n" "$count" > "$out/runtime/core.o"',
                'elif [ "$mode" = vm ]; then',
                '    "$NUPP_VM_BINARY" exec "$NUPP_VM_CLI_IMAGE" nupp.tools.vm.root build',
                "else",
                '    printf "runtime\\n" > "$out/runtime/core.o"',
                "fi",
                "",
            },
            "\n"
        )
    )
    assert(os.execute(("chmod 755 '%s'"):format(runtime)))
    local recipe = {
        seedRuntime = "vm",
        compiler = "compiler.bundle",
        runtime = runtime,
        seed = function(directory)
            write(directory .. "/compiler.bundle", BUNDLE)
            return nil
        end,
        command = function(core, compiler, directory)
            return {core, compiler, "/dev/null", "/dev/null", directory}
        end,
    }

    return dir, recipe
end

local function quiet()
end

function M.coreFixpointAgreesOverEveryStageArtifact()
    local dir, recipe = coreFixture("same")
    local found = corefixpoint.runCore(dir, dir .. "/out", quiet, recipe)
    local ok, problem = pcall(function()
        testAssert.eq(found.reason, nil, "stages two and three agree")
        assert(found.ok, "the fixpoint holds")
        testAssert.eq(found.image, dir .. "/out/stage3/compiler.bundle", "stage three's compiler is kept")
        testAssert.eq(#found.stages, 3, "every stage is recorded")
        testAssert.eq(found.stages[1].runtime, "vm", "stage one ran on the pinned seed")
        testAssert.eq(found.stages[2].runtime, "core", "stage two ran on the core")
        testAssert.eq(found.stages[3].runtime, "core", "stage three ran on the core")
        assert(found.stages[3].files["runtime/core.o"], "the runtime output is recorded")
    end)
    remove(dir)
    assert(ok, problem)
end

-- The negative control: the compilers agree byte for byte, and only what the
-- build emitted beside them differs. The fixpoint fails and names it.
function M.fixpointFailsWhenOnlyARuntimeOutputDiffers()
    local dir, recipe = coreFixture("differ")
    local found = corefixpoint.runCore(dir, dir .. "/out", quiet, recipe)
    local same = read(dir .. "/out/stage2/compiler.bundle") == read(dir .. "/out/stage3/compiler.bundle")
    remove(dir)
    assert(same, "the stages' compilers are identical")
    assert(not found.ok, "a differing runtime output fails the fixpoint")
    testAssert.eq(found.reason, "stages two and three differ at runtime/core.o", "the runtime artifact is named")
end

function M.coreFixpointRefusesAStageThatRanOnTheRustVm()
    local dir, recipe = coreFixture("vm")
    local found = corefixpoint.runCore(dir, dir .. "/out", quiet, recipe)
    remove(dir)
    assert(not found.ok, "a stage that reached for the Rust VM fails the fixpoint")
    assert(
        tostring(found.reason):find("^stage 2 ran on the Rust VM: ") ~= nil,
        "the refusal says which stage: " .. tostring(found.reason)
    )
end

function M.coreFixpointRefusesARuntimeThatIsNotTheCore()
    local dir, recipe = coreFixture("same")
    recipe.runtime = "/bin/echo"
    local found = corefixpoint.runCore(dir, dir .. "/out", quiet, recipe)
    remove(dir)
    assert(not found.ok, "a runtime that is not the C bridge is refused")
    assert(tostring(found.reason):find("would not run on the core", 1, true), tostring(found.reason))
end

-- A core seed is held to the core like the stages after it.
function M.coreFixpointRefusesACoreSeedThatRanOnTheRustVm()
    local dir, recipe = coreFixture("same")
    recipe.seedRuntime = "core"
    recipe.seed = function(directory, env)
        os.execute(("'%s' exec image"):format(env.NUPP_VM_BINARY))
        write(directory .. "/compiler.bundle", BUNDLE)
        return nil
    end
    local found = corefixpoint.runCore(dir, dir .. "/out", quiet, recipe)
    remove(dir)
    assert(not found.ok, "a core seed that reached for the Rust VM fails the fixpoint")
    assert(tostring(found.reason):find("^stage 1 ran on the Rust VM: ") ~= nil, tostring(found.reason))
end

-- Until compilerselfbuild produces a core compiler image, the compiler's own
-- recipe stops before building anything and says what is missing.
function M.compilerRecipeWaitsForTheSelfBuildSwitch()
    local root = require("helpers.paths").absoluteTests .. "/.."
    local script = assert(read(root .. "/scripts/core-self-build"))
    if not script:find("\nSELF_BUILD=''\n", 1, true) then
        return
    end
    local dir = tempProject({["manifest.json"] = '{\n  "format": "nupp-core-seed-1",\n}\n'})
    local recipe = corefixpoint.compilerRecipe(root, dir, "/bin/echo")
    local found = corefixpoint.runCore(root, dir .. "/out", quiet, recipe)
    remove(dir)
    testAssert.eq(recipe.seedRuntime, "core", "the seed's runtime is read from its manifest")
    assert(not found.ok, "the core fixpoint does not run without the switch")
    assert(tostring(found.reason):find("SELF_BUILD", 1, true), tostring(found.reason))
end

-- Once a host's pin names a core seed, the VM fixpoint has nothing to start
-- from, and no VM seed is fetched in its place.
function M.vmFixpointRefusesACoreSeed()
    local dir = tempProject({["seed/manifest.json"] = '{\n  "format": "nupp-core-seed-1",\n}\n'})
    local found = corefixpoint.run(dir, dir .. "/out", quiet, "echo " .. dir .. "/seed")
    remove(dir)
    assert(not found.ok, "the VM fixpoint refuses a core seed")
    testAssert.eq(found.reason, "the pinned stage zero is a core seed; run nupp fixpoint --runtime core")
end

return M
