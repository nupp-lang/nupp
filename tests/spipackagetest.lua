local testAssert = require("nupp.test")
local project = require("nupp.tools.build.project")
local process = require("nupp.compiler.process")
local fs = require("nupp.compiler.fs")
local M = {}

local function write(path, text)
    assert(fs.writeFile(path, text))
end

local function read(path)
    return assert(fs.readFile(path))
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
    assert(require("nupp.io.files").remove(dir, true))
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
    testAssert.equal(entry.entry, "provider.codegen", "the selected entry is returned")

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
local time = require("nupp.time")
local representation = require("nupp.mem.representation")
return {newBuffer = text.newBuffer, now = time.now, storage = representation.storage}
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
        local diagnostics = require("fragment").check(parsed, path, environment)
        for _, diagnostic in ipairs(diagnostics) do
            assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
        end
        testAssert.equal(parsed.host, "browser", "the editor honors the named default target")
        testAssert.equal(project.check(dir), 0, "the default browser target checks")
    end)
    remove(dir)
    assert(ok, why)
end

function M.advertisedImplementationsAndTheirImportsReceiveTheAotPolicy()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {
            kind = "modules", outDir = "out", entries = {"main"},
            sources = {"src/main.nupp"}, aot = "require"
        }}]],
        ["nupp/spi.json"] = [[{"api.Kernel":["implementation"]}]],
        ["src/api.nupp"] = [[module api
export interface Kernel
    @readonly apply: function(number): number
end
]],
        [
            "src/main.nupp"
        ] = [[local {type Kernel} = require("api")
local impl = assert(nupp.spi.load(Kernel)())
return impl.apply
]],
        ["src/implementation.nupp"] = [[local kernel = require("kernel")
return {apply = kernel.apply}
]],
        [
            "src/kernel.nupp"
        ] = [[module kernel
@aot
local function apply(value: number): number
    return value * 2 + 1
end
export = {apply = apply}
]],
    })
    -- Only GPU kernels compile ahead of time, so the policy reaching the
    -- implementation's import shows as the CPU kernel's refusal.
    local here = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
    local status, output = process.capture({fs.absolute(here .. "/../bin/nupp"), "build"}, {cwd = dir})
    testAssert.equal(status, 1, "the implementation's CPU @aot import is refused: " .. tostring(output))
    testAssert.assert(
        tostring(output):find("apply is a CPU @aot function", 1, true),
        "the refusal names the imported kernel: " .. tostring(output)
    )
    remove(dir)
end

local function checkDocumentedSpi(page)
    local files = {
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {
            kind = "binary", stub = "nupp", outDir = "out", entries = {"main"}
        }}]],
        [
            "src/main.nupp"
        ] = [[local codec = require("example.codec")
assert(codec.encode("hello") == "hello")
io.write(codec.encode == require("example.fastcodec").encode and "provider" or "fallback")
]],
    }
    local moduleCount = 0
    -- A fence carries the file it is, as `json [nupp/spi.json]`, so the page can
    -- show other JSON without it becoming the descriptor this project builds.
    for language, caption, source in page:gmatch("```([%w]+)([^\r\n]*)\r?\n(.-)\r?\n```") do
        if language == "nupp" then
            local name = assert(source:match("^module ([%w.]+)"), "the guide example needs a module name")
            local suffix = name == "example.codec" and "/init.nupp" or ".nupp"
            files["src/" .. name:gsub("%.", "/") .. suffix] = source .. "\n"
            moduleCount = moduleCount + 1
        elseif language == "json" and caption:find("nupp/spi.json", 1, true) then
            files["nupp/spi.json"] = source .. "\n"
        end
    end
    testAssert.equal(moduleCount, 4, "the guide's interface, implementations, and consumer")
    assert(files["nupp/spi.json"], "the guide includes a discovery descriptor")
    local dir = tempProject(files)
    local executable = dir .. "/out/binary" .. (package.config:sub(1, 1) == "\\" and ".exe" or "")
    for _, expected in ipairs({"provider", "fallback"}) do
        testAssert.equal(project.build(dir), 0, "the documented SPI example builds")
        local status, output = process.capture({executable}, {cwd = dir})
        testAssert.equal(status, 0, output)
        testAssert.equal(output, expected, "the documented consumer chooses its implementation")
        write(dir .. "/nupp/spi.json", "{}\n")
    end
    remove(dir)
end

function M.documentedSpiModulesSelectAnImplementationAndFallBack()
    checkDocumentedSpi(read("docs/learn/projects/spi.md"))
end

function M.documentedSpiModulesAcceptWindowsLineEndings()
    local page = read("docs/learn/projects/spi.md"):gsub("\r\n", "\n"):gsub("\n", "\r\n")
    checkDocumentedSpi(page)
end

return M
