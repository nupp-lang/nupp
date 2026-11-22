-- `nupp build --without NAME` and a target's `without = {...}`.
--
-- Stripping a builtin the program reaches fails the build with NUPP0006 and the
-- chain of requires that reached it, rather than leaving the program to fail at
-- run time far from the decision. A host that cannot provide a builtin fails the
-- same way. These build the closure fixtures over a fixture builtin
-- (`NUPP_BUILTIN_FIXTURE`), since the registry starts empty.
local json = require("testjson")
local closure = require("tools.packaging.builtinclosure")
local explain = require("nupp.tools.explain")

local ROOT = require("helpers.paths").root
local FIXTURES = require("helpers.paths").absoluteTests .. "/tools/packaging/fixtures/builtinclosure"

local M = {}

local ENTRY = {
    modules = {"crcfixture", "crcfixture.*"},
    owned = {},
    libraries = {{name = "nuppcrc", file = "nupp_crc", notices = {"ISA-L-LICENSE.txt", "ISA-L-CRC-LICENSE.txt"}}},
    hosts = {"native"},
}

local function read(path)
    local file = io.open(path, "rb")
    if file == nil then
        return nil
    end
    local text = file:read("*a")
    file:close()

    return text
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function quote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end

local function shell(command)
    local pipe = assert(io.popen(command))
    local text = pipe:read("*a")
    pipe:close()

    return text
end

local function scratch()
    local directory = os.tmpname()
    os.remove(directory)
    shell("mkdir -p " .. quote(directory))

    return directory
end

local function project(name)
    local directory = scratch()
    shell("cp -R " .. quote(FIXTURES .. "/" .. name) .. "/. " .. quote(directory))

    return directory
end

local function fixture()
    local path = scratch() .. "/builtins.json"
    write(path, json.encode({crcfixture = ENTRY}))

    return path
end

local function skipped()
    local why = closure.unavailable()
    if why then
        require("assert").suite.skip(why)
        return true
    end

    return false
end

local function only(report)
    local diagnostics = report.diagnostics or {}
    assert(#diagnostics == 1, "one diagnostic: " .. json.encode(diagnostics))

    return diagnostics[1]
end

function M.anUnknownBuiltinIsRefusedWithTheNearestName()
    if skipped() then
        return
    end
    local directory = project("hello")
    local report, built = closure.build(directory, "--without crcfixtur", fixture())
    assert(not built)
    local diagnostic = only(report)
    assert(diagnostic.code == "NUPP0003", json.encode(diagnostic))
    assert(diagnostic.message:find('unknown builtin "crcfixtur"; did you mean "crcfixture"?', 1, true), diagnostic.message)
    -- A target's list is the manifest's, and is refused as the manifest.
    write(directory .. "/nupp.lua", [[
return {
    include = {"src"},
    build = {kind = "binary", stub = "nupp", entries = {"src/main.nupp"}, without = {"crcfixtur"}},
}
]])
    report, built = closure.build(directory, "", fixture())
    assert(not built)
    diagnostic = only(report)
    assert(diagnostic.code == "NUPP0002", json.encode(diagnostic))
    assert(diagnostic.message:find('without: unknown builtin "crcfixtur"; did you mean "crcfixture"?', 1, true))
    shell("rm -rf " .. quote(directory))
end

-- The refusal of `uses` built without the fixture, as the closure fixtures
-- reach it: main requires app.checksum, which requires crcfixture.
local function assertChain(directory, report, headline)
    local diagnostic = only(report)
    assert(diagnostic.code == "NUPP0006", json.encode(diagnostic))
    assert(diagnostic.docs == "docs/learn/projects/builtins.md#stripping-a-builtin", tostring(diagnostic.docs))
    local message = diagnostic.message
    assert(message:find(headline, 1, true), message)
    assert(message:find('src/main.nupp:1          local checksum = require("app.checksum")', 1, true), message)
    assert(message:find('src/app/checksum.nupp:3  local crcfixture = require("crcfixture")', 1, true), message)
    assert(diagnostic.file:match("src/app/checksum%.nupp$"), diagnostic.file)
    assert(diagnostic.range.start.line == 3, json.encode(diagnostic.range))
    local related = diagnostic.related
    assert(#related == 2, json.encode(related))
    assert(related[1].file:match("src/main%.nupp$") and related[1].range.start.line == 1, json.encode(related[1]))
    assert(related[1].message == "reaches app.checksum", related[1].message)
    assert(related[2].file:match("src/app/checksum%.nupp$") and related[2].range.start.line == 3)
    assert(related[2].message == "reaches crcfixture", related[2].message)
    -- Nothing is written.
    assert(report.artifact == nil and read(directory .. "/build/binary") == nil, "the refused build wrote nothing")
end

function M.aStrippedBuiltinTheProgramReachesFailsWithItsChain()
    if skipped() then
        return
    end
    local directory = project("uses")
    local report, built = closure.build(directory, "--without crcfixture", fixture())
    assert(not built)
    assertChain(directory, report, 'build target "default" is built without crcfixture, but it reaches crcfixture')
    assert(#report.without == 1 and report.without[1] == "crcfixture", json.encode(report.without))
    shell("rm -rf " .. quote(directory))
end

function M.theTargetsWithoutListStripsToo()
    if skipped() then
        return
    end
    local directory = project("uses")
    write(directory .. "/nupp.lua", [[
return {
    include = {"src"},
    build = {
        targets = {
            server = {kind = "binary", stub = "nupp", entries = {"src/main.nupp"}, without = {"crcfixture"}},
        },
    },
}
]])
    local report, built = closure.build(directory, "", fixture())
    assert(not built)
    assertChain(directory, report, 'build target "server" is built without crcfixture, but it reaches crcfixture')
    shell("rm -rf " .. quote(directory))
end

function M.aHostThatCannotProvideItFailsTheSameWay()
    if skipped() then
        return
    end
    local directory = project("uses")
    local report, built = closure.build(directory, "--host browser", fixture())
    assert(not built)
    assertChain(directory, report, 'build target "default" reaches crcfixture, which host browser cannot provide')
    shell("rm -rf " .. quote(directory))
end

function M.stripsAreFoldedIntoTheBuildKey()
    if skipped() then
        return
    end
    -- A builtin the program does not reach strips to nothing, and still
    -- changes the build key: the same project rebuilds its modules.
    local directory = project("hello")
    local plain, built, errors = closure.build(directory, "", fixture())
    assert(built, errors:sub(-2000))
    assert(#plain.without == 0)
    local stripped, strippedBuilt, strippedErrors = closure.build(directory, "--without crcfixture", fixture())
    assert(strippedBuilt, strippedErrors:sub(-2000))
    assert(#stripped.without == 1 and stripped.without[1] == "crcfixture", json.encode(stripped.without))
    assert(stripped.timing.compiledModules > 0, "the strip is in the build key: " .. json.encode(stripped.timing))
    shell("rm -rf " .. quote(directory))
end

function M.explainDescribesTheCode()
    local entry = assert(explain.lookup("NUPP0006"))
    assert(entry.family == false, "NUPP0006 has its own entry")
    assert(entry.rule:find("--without", 1, true) and entry.rule:find("without = {", 1, true), entry.rule)
    local page = assert(read(ROOT .. "/docs/learn/projects/builtins.md"))
    assert(page:find("\n## Stripping a builtin\n", 1, true), "the docs anchor names a section")
end

function M.theRepositoryManifestStripsNothing()
    -- The pinned stage-zero image validates this manifest and does not know the
    -- key until the pin moves past it.
    local text = assert(read(ROOT .. "/nupp.lua"))
    assert(not text:find("%f[%w_]without%s*="), "nupp.lua uses `without`, which the stage-zero pin cannot read")
end

return M
