local terminal = require("io.cli")

local testAssert = require("assert")
-- What a build says about itself while it runs and when it finishes.
--
-- Two halves, tested the two ways they are reachable: the reporter directly,
-- which is where the timeline arithmetic and the wording live, and `nupp build`
-- through the real binary, which is where the decision to say anything at all
-- is made. The second half matters most: a build has been quiet on success for
-- as long as there have been scripts reading its output, and the only reason
-- that is still true is that nothing is written unless somebody is watching.
local progress = require("nupp.tools.build.progress")

local HERE = require("helpers.paths").absoluteTests
local NUPP = HERE .. "/../bin/nupp"

local function tempDir()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    return dir
end

local function tempProject()
    local dir = tempDir()
    local files = {
        [
            "nupp.lua"
        ] = 'return {include = {"."}, build = {targets = {app = {'
        .. 'entries = {"main"}, outDir = "out"}}, default = "app"}}\n',
        ["lib.nupp"] = "local m = {}\nfunction m.double(n: number): number\n" .. "    return n * 2\nend\nreturn m\n",
        ["main.nupp"] = "local lib = require('lib')\nprint(lib.double(21))\n",
    }
    for name, text in pairs(files) do
        local file = assert(io.open(dir .. "/" .. name, "wb"))
        file:write(text)
        file:close()
    end

    return dir
end

local function constProject()
    local dir = tempDir()
    local files = {
        [
            "nupp.lua"
        ] = 'return {include = {"."}, build = {targets = {app = {'
        .. 'entries = {"main"}, outDir = "out", optimize = 1}}, default = "app"}}\n',
        [
            "lib.nupp"
        ] = table.concat(
            {
                "local function accumulate<const N: integer>(value: number, count: N): number",
                "    local total = value",
                "    for offset = 1, count as integer do total = total + offset end",
                "    return total",
                "end",
                "return {accumulate = accumulate}",
            },
            "\n"
        ),
        ["main.nupp"] = "local lib = require('lib')\nreturn lib.accumulate(10.0, 4)\n",
    }
    for name, text in pairs(files) do
        local file = assert(io.open(dir .. "/" .. name, "wb"))
        file:write(text)
        file:close()
    end

    return dir
end

-- Standard output and standard error kept apart, because which one a thing is
-- written to is the whole question here: a build's report goes to stderr so that
-- `--json` on stdout stays a document a program can read.
local function run(dir, arguments, env)
    local errPath = os.tmpname()
    local command = ("cd '%s' && %s'%s' %s 2>'%s'"):format(dir, env or "", NUPP, arguments, errPath)
    local pipe = assert(io.popen(command))
    local out = pipe:read("*a")
    pipe:close()
    local errFile = assert(io.open(errPath, "rb"))
    local err = errFile:read("*a")
    errFile:close()
    os.remove(errPath)

    return out, err
end

-- A reporter writing somewhere the test can read. A file is not a terminal, so
-- it never rewrites a line in place, which is what makes the output comparable.
local function reporterTo(path, mode)
    local stream = assert(io.open(path, "wb"))
    return progress.new(mode, stream), stream
end

local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

return {
    terminal = terminal,
    testAssert = testAssert,
    progress = progress,
    HERE = HERE,
    NUPP = NUPP,
    tempDir = tempDir,
    tempProject = tempProject,
    constProject = constProject,
    run = run,
    reporterTo = reporterTo,
    readAll = readAll,
}
