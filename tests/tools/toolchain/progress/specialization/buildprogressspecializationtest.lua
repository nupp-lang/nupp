local fixture = require("helpers.buildprogressfixture")
local testAssert = fixture.testAssert
local tempDir = fixture.tempDir
local constProject = fixture.constProject
local run = fixture.run
local readAll = fixture.readAll

local M = {}

function M.crossModuleConstBodiesBelongToTheDeclarationAndTrackIncomingKeys()
    local dir = constProject()
    local _, firstErr = run(dir, "build")
    testAssert.eq(firstErr, "", "the first optimized build succeeds")
    local declaration = readAll(dir .. "/out/lib.lua")
    local caller = readAll(dir .. "/out/main.lua")
    assert(
        declaration:find("local function __nuppConst_accumulate_", 1, true),
        "the private body is emitted with its declaration"
    )
    assert(
        declaration:find("__nuppConstSpecializations", 1, true),
        "the declaration publishes private linkage by public function identity"
    )
    assert(
        caller:find("_G.__nuppConstSpecializations[", 1, true),
        "the checked direct call names the body without a tuple branch"
    )
    assert(not caller:find("local function __nuppConst_accumulate_", 1, true), "the caller does not duplicate the body")

    local pipe = assert(
        io.popen(
            (
                "cd %q && luajit -e %q"
            ):format(dir, 'package.path="out/?.lua;"..package.path; assert(require("main")==20)')
        )
    )
    pipe:read("*a")
    assert(pipe:close(), "the cross-module private call answers")

    local source = assert(io.open(dir .. "/main.nupp", "wb"))
    source:write("local lib = require('lib')\nconst run = lib.accumulate\nreturn run(10.0, 5)\n")
    source:close()
    local _, secondErr = run(dir, "build")
    testAssert.eq(secondErr, "", "changing only the incoming tuple rebuilds cleanly")
    local changed = readAll(dir .. "/out/lib.lua")
    assert(changed ~= declaration, "the declaring artifact changes when its incoming specialization manifest changes")
    assert(changed:find("local function __nuppConst_accumulate_", 1, true), "and still owns the replacement body")
end

function M.aFileBuildCountsTheBodiesItEmitted()
    -- `nupp build FILE` does not use the project module graph, so it reports its
    -- own count. It read zero however many bodies OPT-8 emitted, which made the
    -- number say a build specialized nothing whenever it specialized anything.
    local dir = tempDir()
    local file = assert(io.open(dir .. "/only.nupp", "wb"))
    file:write(
        table.concat(
            {
                "local function accumulate<const N: integer>(value: number, count: N): number",
                "    local total = value",
                "    for offset = 1, count as integer do total = total + offset end",
                "    return total",
                "end",
                "return accumulate(10.0, 4) + accumulate(10.0, 7)",
            },
            "\n"
        ) .. "\n"
    )
    file:close()
    local out, err = run(dir, "build -O1 --json only.nupp")
    testAssert.eq(err, "", "the file build succeeds quietly")
    local decoded = require("testjson").decode(out)
    testAssert.eq(decoded.ok, true, "the file build worked: " .. out)
    local emitted = 0
    for _ in readAll(dir .. "/build/only.lua"):gmatch("local function __nuppConst_accumulate_") do
        emitted = emitted + 1
    end
    testAssert.eq(emitted, 2, "two closed tuples emit two private bodies")
    testAssert.eq(decoded.timing.specializedBodies, emitted, "and the reported count is the number of bodies emitted")
end

function M.aFileBuildAtLevelZeroCountsNothing()
    local dir = tempDir()
    local file = assert(io.open(dir .. "/only.nupp", "wb"))
    file:write(
        table.concat(
            {
                "local function accumulate<const N: integer>(value: number, count: N): number",
                "    local total = value",
                "    for offset = 1, count as integer do total = total + offset end",
                "    return total",
                "end",
                "return accumulate(10.0, 4)",
            },
            "\n"
        ) .. "\n"
    )
    file:close()
    local out, err = run(dir, "build -O0 --json only.nupp")
    testAssert.eq(err, "", "the unoptimized file build succeeds quietly")
    local decoded = require("testjson").decode(out)
    testAssert.eq(decoded.timing.specializedBodies, 0, "-O0 emits and counts nothing")
    assert(
        not readAll(dir .. "/build/only.lua"):find("__nuppConst_accumulate_", 1, true),
        "-O0 leaves the generic declaration and call"
    )
end

function M.levelZeroDoesNotPlanOrCountProjectConstBodies()
    local dir = constProject()
    local out, err = run(dir, "build -O0 --json")
    testAssert.eq(err, "", "the unoptimized build succeeds quietly")
    local decoded = require("testjson").decode(out)
    testAssert.eq(decoded.ok, true, "the unoptimized build worked: " .. out)
    testAssert.eq(decoded.timing.specializedBodies, 0, "timing counts emitted bodies rather than eligible source calls")
    local declaration = readAll(dir .. "/out/lib.lua")
    assert(not declaration:find("__nuppConst_accumulate_", 1, true), "-O0 never emits the optional private body")
end

return M
