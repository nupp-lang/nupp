local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local executable = require("nupp.compiler.vm.coregraphexecutable")
local corelibrary = require("nupp.compiler.vm.corelibrary")
local unit = require("nupp.compiler.vm.nativeunit")
local runtime = require("nupp.compiler.runtime")
local ROOT = assert(environment.compilerRoot())
local M = {}
local held

local function read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local function fixture()
    if held then
        return held
    end
    local env = environment.new(ROOT, {config = {include = {"src", "native/core/src"}}})

    local compile = require("nupp.tools.cli.compile")
    local loadImage = assert(rawget(_G, "__nupp_load_image"))

    local function sourceModule(short)
        local path = ROOT .. "/native/core/src/nupp/core/" .. short .. ".nupp"
        local image = assert(compile.image(path, env, "nupp.core." .. short))
        return assert(loadImage(image))()
    end

    local name = "nupp.core.artifactcallfixture"
    local path = "=" .. name .. ".nupp"
    local parsed = parser.parse("module " .. name .. "\nexport = true", path)
    test.eq(#parsed.errors, 0)
    local diagnostics = checker.check(parsed, path, env, {moduleName = name})
    for _, d in ipairs(diagnostics) do
        assert(d.severity ~= "error", d.msg)
    end
    local described = program.describe({{name = name, path = path, parsed = parsed, diagnostics = diagnostics}}, name)
    local code = executable.fromChecked(program.compile(described, tagged.forVersion(8)), 8)
    local requested = {}
    for _, short in ipairs({"guestcatalog", "librarycalls", "storagelibrary", "loadlibrary", "debuglibrary", "corestorage", "coretables"}) do
        requested[
            #requested + 1
        ] = {
            moduleName = "nupp.runtime.core." .. short,
            path = ROOT .. "/native/core/src/nupp/runtime/core/" .. short .. ".nupp"
        }
    end
    requested[
        #requested + 1
    ] = {moduleName = "nupp.runtime.vm.values", path = ROOT .. "/src/nupp/runtime/vm/values.nupp"}
    local session = unit.session(ROOT, requested, "aarch64-apple-darwin", {"src", "native/core/src"}, true)
    local scopes = {}
    for _, request in ipairs(requested) do
        scopes[request.moduleName] = session.module(request.moduleName)
    end
    local subjects = {}
    for _, subject in ipairs(corelibrary.subjects()) do
        subjects[subject.name] = subject
    end
    local removeLoader = runtime.install(
        env,
        function(path, moduleEnv, name, source)
            local image = compile.image(path, moduleEnv, name, nil, source)
            return image, image == nil and "type errors" or nil
        end,
        nil,
        nil,
        function(image)
            return loadImage(image)
        end
    )
    local okay, result = pcall(function()
        return {
            writer = sourceModule("guestartifact"),
            generator = sourceModule("librarycallsgen"),
            code = code,
            scopes = scopes,
            subjects = subjects
        }
    end)
    removeLoader()
    assert(okay, result)
    held = result

    return held
end

local function copy(value)
    local result = {}
    for key, item in pairs(value) do
        result[key] = item
    end

    return result
end

local function changed(f, short)
    local scopes = copy(f.scopes)
    local name = "nupp.runtime.core." .. short
    local owner = copy(scopes[name])
    owner.exportedConstants = copy(owner.exportedConstants)
    scopes[name] = owner

    return scopes, owner.exportedConstants
end

local function encode(f, scopes)
    -- This checks serialization, not machine-code execution. One aligned
    -- dispatch entry fits the selected-code extent supplied to the writer.
    return f.writer.encode(f.code, scopes or f.scopes, {0}, 4)
end

local function refuses(f, scopes, message)
    local ok, problem = pcall(encode, f, scopes)
    test.eq(ok, false)
    assert(tostring(problem):find(message, 1, true), tostring(problem))
end

function M.generatedSubjectFilesMatchTheCanonicalTable()
    local f = fixture()
    test.eq(f.generator.source(), read(ROOT .. "/native/core/src/nupp/runtime/core/librarycalls.nupp"))
    test.eq(f.generator.subject("storage"), read(ROOT .. "/native/core/src/nupp/runtime/core/storagelibrary.nupp"))
end

function M.issuedExecutableEncodesWithTheRealSplitCallScopes()
    local f = fixture()
    test.eq(f.subjects.storage.output, "storagelibrary")
    test.eq(f.subjects.views.output, nil)
    local packed = encode(f)
    assert(type(packed.bytes) == "string" and #packed.bytes > 0)
    assert(packed.layouts.Function.size > 0)
end

function M.missingSplitScopeCannotFallBackToTheDefaultOwner()
    local f = fixture()
    local scopes, constants = changed(f, "librarycalls")
    for name, value in pairs(scopes["nupp.runtime.core.storagelibrary"].exportedConstants) do
        constants[name] = value
    end
    scopes["nupp.runtime.core.storagelibrary"] = nil
    refuses(f, scopes, "guest library calls nupp.runtime.core.storagelibrary")
end

function M.splitCallsKeepTheirMissingAndMismatchRefusals()
    local f = fixture()
    local entry = f.subjects.storage.calls[1]
    local scopes, constants = changed(f, f.subjects.storage.output)
    constants[entry.name] = nil
    refuses(f, scopes, "guest library call " .. entry.name)
    scopes, constants = changed(f, f.subjects.storage.output)
    constants[entry.name] = string.format("%d", entry.id + 1)
    refuses(f, scopes, "guest library call " .. entry.name .. " differs from corelibrary")
end

function M.storageNamedViewCallsStillRequireTheDefaultOwner()
    local f = fixture()
    local entry = f.subjects.views.calls[1]
    assert(entry.name:match("^STORAGE_"))
    local scopes, constants = changed(f, "librarycalls")
    local value = assert(constants[entry.name])
    constants[entry.name] = nil
    local split = copy(scopes["nupp.runtime.core.storagelibrary"])
    split.exportedConstants = copy(split.exportedConstants)
    split.exportedConstants[entry.name] = value
    scopes["nupp.runtime.core.storagelibrary"] = split
    refuses(f, scopes, "guest library call " .. entry.name)
end

function M.defaultCallsAndElementKindsStillRejectChangedConstants()
    local f = fixture()
    local entry = f.subjects.views.calls[1]
    local scopes, constants = changed(f, "librarycalls")
    constants[entry.name] = string.format("%d", entry.id + 1)
    refuses(f, scopes, "guest library call " .. entry.name .. " differs from corelibrary")
    local row = corelibrary.elements()[1]
    scopes, constants = changed(f, row.module)
    constants[row.name] = string.format("%d", row.kind + 1)
    refuses(f, scopes, "guest element kind " .. row.name .. " differs from corelibrary")
end

return M
