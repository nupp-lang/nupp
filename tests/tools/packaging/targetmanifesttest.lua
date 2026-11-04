local testAssert = require("assert")
local project = require("nupp.tools.build.project")
local fs = require("nupp.compiler.fs")
local M = {}

local function write(path, text)
    assert(fs.writeFile(path, text))
end

local function tempProject(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir))
    for name, text in pairs(files) do
        write(fs.join(dir, name), text)
    end

    return dir
end

local function remove(dir)
    assert(require("io.files").remove(dir, true))
end

function M.capabilityDescriptorsRejectUnknownAndDuplicateEntries()
    local capabilities = require("nupp.tools.build.capabilities")
    local dir = tempProject({
        [
            "capabilities.json"
        ] = [[
{"schema":2,"capabilities":[
 {"kind":"generator","name":"codegen","api":1,"entry":"provider.codegen"}
]}
]],
    })
    local record = {typeRoot = dir}
    local entry = assert(capabilities.find(record, "provider", "generator", "codegen"))
    testAssert.eq(entry.entry, "provider.codegen", "the selected entry is returned")

    write(dir .. "/capabilities.json", '{"schema":2,"capabilities":[],"extra":true}\n')
    local _, unknown = capabilities.find(record, "provider", "generator", "codegen")
    assert(unknown:find("unknown key extra", 1, true), unknown)

    write(
        dir .. "/capabilities.json",
        [[{"schema":2,"capabilities":[
 {"kind":"generator","name":"codegen","api":1,"entry":"provider.first"},
 {"kind":"generator","name":"codegen","api":1,"entry":"provider.second"}
]}
]]
    )
    local _, duplicate = capabilities.find(record, "provider", "generator", "codegen")
    assert(duplicate:find("duplicates capability codegen", 1, true), duplicate)
    remove(dir)
end

function M.namedManifestTargetsCarryTheSelectedHostAndVm()
    local source = [[
local text = require("nupp.text")
local time = require("coroutine")
local array = require("nupp.mem.array")
return {newBuffer = text.newbuffer, now = os.monotonic, bytes = array.bytes}
]]
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {
            kind = "modules", entries = {"main"}, default = "browser",
            targets = {
                browser = {host = "browser", outDir = "out/browser"},
                native = {host = "native", outDir = "out/native"},
            }
        }}]],
        ["src/main.nupp"] = source,
    })
    local ok, why = pcall(function()
        -- An editor opens the manifest directly, without build's private _target.
        local environment = require("nupp.compiler.project.env").new(dir, {cache = false})
        local path = dir .. "/src/main.nupp"
        local parsed = require("nupp.compiler.syntax.parser").parse(source, path)
        assert(#parsed.errors == 0)
        local diagnostics = require("helpers.fragment").check(parsed, path, environment)
        for _, diagnostic in ipairs(diagnostics) do
            assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
        end
        testAssert.eq(parsed.host, "browser", "the editor honors the named default target")
        testAssert.eq(project.check(dir), 0, "the default browser target checks")
    end)
    remove(dir)
    assert(ok, why)
end

return M
