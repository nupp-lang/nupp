-- `nupp fixpoint --runtime core` and its seed package on a small input, end to
-- end on the core, until the compiler can build itself there
-- (scripts/core-self-build names that switch):
--
--   bin/nupp run tests/core/guests/fixpoint.lua
--
-- The compiler is the guest case fixpointcompiler: three modules that lower
-- sources through the compiler's real lexer on the core and emit themselves as
-- the next stage's compiler. The host producer builds its bundle, standing in
-- for the pinned seed's stage one; stages two and three run it on the C bridge
-- built from these sources. Then the stage-three pair is packaged as a seed
-- archive, and a cold bootstrap from that archive alone, all three stages on
-- the core, must reach the same stage three. A stage that reaches for the Rust
-- VM, and a seed archive whose digest is not the one named, are refused.
--
-- Its bundle build is a guest selection, which takes a few minutes and a few
-- gigabytes the first time the runtime's sources change.
local fs = require("nupp.compiler.fs")
local process = require("nupp.compiler.process")
local fixpoint = require("nupp.tools.vm.fixpoint")
local packaging = require("nupp.tools.vm.packaging")

local ROOT = fs.absolute(os.getenv("NUPP_COMPILER_ROOT") or ".")
local OUT = ROOT .. "/build/core-fixpoint-fixture"
local SOURCES = {
    ROOT .. "/tests/core/catalog-fixpoint-compiler.nupp",
    ROOT .. "/tests/core/catalog-fixpoint-lowering.nupp",
    ROOT .. "/tests/core/catalog-fixpoint-emitter.nupp",
}

local failures = 0

local function check(ok, what)
    print((ok and "ok    " or "FAIL  ") .. what)
    if not ok then
        failures = failures + 1
    end
end

local function say(line)
    io.stderr:write("  ", line, "\n")
end

process.run({"rm", "-rf", OUT})
fs.mkdir(OUT)

-- The C bridge, from these sources: what stages two and three run on.
local status, output = process.capture({"sh", ROOT .. "/scripts/core-bridge"}, {
    cwd = ROOT,
    env = {NUPP_CORE_BRIDGE_DIR = OUT .. "/bridge"}
})
assert(status == 0, "the C bridge did not build: " .. output)
local BRIDGE = OUT .. "/bridge/nupp-core"

-- The small compiler's bundle, from the host producer.
status, output = process.capture({ROOT .. "/bin/nupp", "run", "run.lua", "fixpointcompiler"}, {
    cwd = ROOT .. "/tests/core/guests",
    env = {
        NUPP_COMPILER_ROOT = ROOT,
        NUPP_GUEST_EMIT_ONLY = "1",
        NUPP_GUEST_MODES = "normal",
        NUPP_GUEST_SHARDS = "1",
        NUPP_GUEST_QUICK = "1",
    },
})
assert(status == 0, "the host producer did not build the small compiler:\n" .. output:sub(-4000))
local SEED_BUNDLE = assert(fs.readFile(ROOT .. "/build/core-guests/fixpointcompiler-normal.bundle"))

-- How a stage's compiler builds the next: OUTPUT COMPILER SOURCE..., after
-- the bridge's own arguments, with `extra` first.
local function recipe(seedRuntime, seed, extra)
    return {
        seedRuntime = seedRuntime,
        seed = seed,
        compiler = "compiler.bundle",
        runtime = BRIDGE,
        command = function(core, compiler, directory)
            local argv = {core, compiler, "/dev/null", "/dev/null"}
            for _, argument in ipairs(extra or {}) do
                argv[#argv + 1] = argument
            end
            argv[#argv + 1] = directory
            argv[#argv + 1] = compiler
            for _, source in ipairs(SOURCES) do
                argv[#argv + 1] = source
            end

            return argv
        end,
    }
end

local function hostSeed(directory)
    assert(fs.writeFile(directory .. "/compiler.bundle", SEED_BUNDLE))
    return nil
end

local found = fixpoint.runCore(ROOT, OUT .. "/stages", say, recipe("vm", hostSeed))
check(found.ok, "three stages agree: " .. tostring(found.reason or found.digest))
check(
    #found.stages == 3 and found.stages[2].runtime == "core" and found.stages[3].runtime == "core",
    "stages two and three ran on the core"
)
local outputs = 0
for name in pairs(found.ok and found.stages[3].files or {}) do
    if name:match("^runtime/.+%.tokens$") then
        outputs = outputs + 1
    end
end
check(outputs == #SOURCES, "stage three emitted a runtime output for each source")

local refused = fixpoint.runCore(ROOT, OUT .. "/refused", say, recipe("vm", hostSeed, {"--vm"}))
check(
    not refused.ok and tostring(refused.reason):find("^stage 2 ran on the Rust VM: ") ~= nil,
    "a stage that starts the Rust VM is refused: " .. tostring(refused.reason)
)

if found.ok then
    local packaged, problem = packaging.coreSeed(ROOT, BRIDGE, found.image, "fixture", OUT .. "/seed")
    check(packaged ~= nil, "the stage-three pair packages" .. (problem and ": " .. problem or ""))
    if packaged then
        local sum = fs.readFile(packaged.archive .. ".sha256") or ""
        check(sum:match("^(%x+)") == packaged.sha256, "the archive's digest is written beside it")
        local _, listing = process.capture({"tar", "-tzf", packaged.archive})
        check(
            listing == "NOTICE.md\ncompiler.bundle\nmanifest.json\nruntime\n",
            "the archive holds the pair, its manifest and its notice"
        )
        status = process.run(
            {"sh", ROOT .. "/scripts/toolchain", "core-seed-install", packaged.archive, string.rep("0", 64)},
            {cwd = ROOT, env = {NUPP_TOOLCHAIN_DIR = OUT .. "/wrong", NUPP_HOST_OFFLINE = "1"}}
        )
        check(status ~= 0 and not fs.exists(OUT .. "/wrong/core-seed"), "an archive with another digest is refused")
        local cold = fixpoint.coldBootstrap(
            ROOT,
            packaged.archive,
            packaged.sha256,
            OUT .. "/cold",
            say,
            function(pair)
                local fromSeed = recipe("core", nil)
                fromSeed.seed = function(directory, env)
                    local argv = fromSeed.command(pair .. "/runtime", pair .. "/compiler.bundle", directory)
                    if process.run(argv, {cwd = ROOT, env = env}) ~= 0 then
                        return "the core seed did not build stage 1"
                    end

                    return nil
                end

                return fromSeed
            end,
            found.directory
        )
        check(
            cold.ok,
            "a cold bootstrap from the archive reaches the same stage three" .. (
                cold.reason and ": " .. cold.reason or ""
            )
        )
        check(cold.ok and cold.stages[1].runtime == "core", "the cold bootstrap's stage one ran on the core seed")
    end
end

print(("%d failed"):format(failures))
os.exit(failures == 0 and 0 or 1)
