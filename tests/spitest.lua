local fs = require("nupp.compiler.fs")
local project = require("nupp.compiler.build.project")
local process = require("nupp.compiler.build.process")
local discovery = require("nupp.compiler.build.spi")
local M = {}

local function fixture(files, body)
    local dir = os.tmpname()
    os.remove(dir)
    assert(fs.mkdir(dir))
    for name, source in pairs(files) do
        assert(fs.writeFile(fs.join(dir, name), source))
    end
    local ok, why = pcall(body, dir)
    assert(require("nupp.io.files").remove(dir, true))
    assert(ok, why)
end

local function files(main, descriptor)
    return {
        [
            "nupp.lua"
        ] = [[return {include = {"src"}, build = {
            kind = "bundle", dialect = "lua51", outDir = "out",
            output = "out/app.lua", entries = {"main"}
        }}]],
        ["nupp/spi.json"] = descriptor or [[{"example.api.Codec":["example.first","example.second"]}]],
        [
            "src/example/api.nupp"
        ] = [[module example.api
export interface Codec
    readonly encode: function(value: string): string
end]],
        [
            "src/example/first.nupp"
        ] = [[module example.first
export function encode(value: string): string return "first:" .. value end]],
        [
            "src/example/second.nupp"
        ] = [[module example.second
export function encode(value: string): string return "second:" .. value end]],
        ["src/main.nupp"] = main,
    }
end

local function run(dir)
    local produced = {}
    assert(project.build(dir, {produced = produced}) == 0, "SPI fixture did not build")
    local status, output = process.capture({"luajit", dir .. "/out/app.lua"})
    assert(status == 0, output)

    -- Printed lines use CRLF on Windows; the provider results are the same.

    return produced, (output:gsub("\r\n", "\n"))
end

function M.typedLazyIterationRetainsModuleIdentityAndBindsDirectFunctions()
    local sources = files(
        [[module main
local spi = require("nupp.spi")
local {type Codec} = require("example.api")
local next = spi.load(Codec)
local first = assert(next())
local second = assert(next())
assert(next() == nil and next() == nil)
assert(first.encode("x") == "first:x")
assert(second.encode("x") == "second:x")
assert(spi.load(Codec)() == first)
local api = require("example.api")
assert(spi.load(api.Codec)() == first)
local encode = first.encode
for i = 1, 10 do assert(encode("x") == "first:x") end
print("ok")]]
    )
    fixture(sources, function(dir)
        local produced, output = run(dir)
        assert(output == "ok\n", output)
        assert(#produced.spi == 2)
        assert(produced.spi[1].interface == "example.api.Codec")
        local code = assert(fs.readFile(dir .. "/out/main.lua"))
        assert(code:find('"example.api.Codec"', 1, true), code)
    end)
end

function M.earlyTerminationDoesNotLoadLaterProviders()
    local sources = files(
        [[module main
local {load as providers} = require("nupp.spi")
local {type Codec as Interface} = require("example.api")
for candidate in providers(Interface) do
    assert(candidate.encode("x") == "first:x")
    break
end
print("ok")]]
    )
    sources["src/example/second.nupp"] = sources["src/example/second.nupp"] .. '\nerror("must stay unloaded")'
    fixture(sources, function(dir)
        local _, output = run(dir)
        assert(output == "ok\n", output)
    end)
end

function M.emptyDiscoveryUsesOrdinaryFallback()
    fixture(
        files(
            [[module main
local spi = require("nupp.spi")
local {type Codec} = require("example.api")
local provider: Codec = spi.load(Codec)() ?? require("example.first")
assert(provider.encode("x") == "first:x")
print("ok")]],
            "{}"
        ),
        function(dir)
            local _, output = run(dir)
            assert(output == "ok\n", output)
        end
    )
end

function M.discoveryUsesDeclaredDependencyOrderAndDeduplicates()
    fixture(
        {
            ["nupp/spi.json"] = [[{"example.api.Codec":["app.codec","app.codec"]}]],
            ["z/spi.json"] = [[{"example.api.Codec":["z.codec"]}]],
            ["a/spi.json"] = [[{"example.api.Codec":["a.codec"]}]],
            ["child/spi.json"] = [[{"example.api.Codec":["child.codec","app.codec"]}]],
            ["tool/spi.json"] = [[{"example.api.Codec":["tool.codec"]}]],
        },
        function(dir)
            local entries = assert(
                discovery.read(
                    dir,
                    {dependencies = {z = {dependencies = {"child"}}, a = {}, child = {}, tool = {},}},
                    {dependencies = {"z", "a", "child"}},
                    {
                        z = {typeRoot = dir .. "/z"},
                        a = {typeRoot = dir .. "/a"},
                        child = {typeRoot = dir .. "/child"},
                        tool = {typeRoot = dir .. "/tool"},
                    }
                )
            )
            local names = {}
            for _, entry in ipairs(entries) do
                names[#names + 1] = entry.implementation
            end
            assert(table.concat(names, ",") == "app.codec,z.codec,child.codec,a.codec")
        end
    )
end

function M.providerErrorsAreNotTreatedAsAbsence()
    local sources = files(
        [[module main
local spi = require("nupp.spi")
local {type Codec} = require("example.api")
for candidate in spi.load(Codec) do print(candidate.encode("x")) end]]
    )
    sources["src/example/second.nupp"] = sources["src/example/second.nupp"] .. '\nerror("broken provider")'
    fixture(sources, function(dir)
        assert(project.build(dir) == 0)
        local status, output = process.capture({"luajit", dir .. "/out/app.lua"})
        assert(status ~= 0 and output:find("broken provider", 1, true), output)
        assert(output:find("example.api.Codec", 1, true), output)
    end)
end

function M.typeReexportsResolveToTheDefiningInterface()
    local sources = files(
        [[module main
local spi = require("nupp.spi")
local load = spi.load
local {type PublicCodec} = require("example.alias")
assert(assert(load(PublicCodec)()).encode("x") == "first:x")
print("ok")]],
        [[{"example.alias.PublicCodec":["example.first"]}]]
    )
    sources[
        "src/example/alias.nupp"
    ] = [[module example.alias
local {type Codec} = require("example.api")
export type PublicCodec = Codec]]
    fixture(sources, function(dir)
        local produced, output = run(dir)
        assert(output == "ok\n", output)
        assert(produced.spi[1].interface == "example.api.Codec")
    end)
end

function M.returnedModuleTablesExportTheirInterfaces()
    local sources = files(
        [[module main
local spi = require("nupp.spi")
local api = require("example.api")
assert(assert(spi.load(api.Codec)()).encode("x") == "first:x")
print("ok")]]
    )
    sources[
        "src/example/api.nupp"
    ] = [[module example.api
local api = {}
interface api.Codec
    readonly encode: function(value: string): string
end
export = api]]
    fixture(sources, function(dir)
        local _, output = run(dir)
        assert(output == "ok\n", output)
    end)
end

function M.invalidProvidersFailBuildWithoutExecutingThem()
    local sources = files(
        [[module main
local spi = require("nupp.spi")
local {type Codec} = require("example.api")
for candidate in spi.load(Codec) do print(candidate.encode("x")) end]]
    )
    sources[
        "src/example/second.nupp"
    ] = [[module example.second
export const encode = 42
error("provider bodies must not run during discovery")]]
    fixture(sources, function(dir)
        assert(project.build(dir) ~= 0, "a number cannot implement an encode function")
    end)
end

function M.descriptorChangesUpdateTheWarmBuild()
    fixture(
        files(
            [[module main
local spi = require("nupp.spi")
local {type Codec} = require("example.api")
for candidate in spi.load(Codec) do print(candidate.encode("x")) end]]
        ),
        function(dir)
            local _, first = run(dir)
            assert(first == "first:x\nsecond:x\n", first)
            assert(fs.writeFile(dir .. "/nupp/spi.json", [[{"example.api.Codec":["example.second"]}]]))
            local produced, second = run(dir)
            assert(second == "second:x\n", second)
            assert(#produced.spi == 1)
        end
    )
end

function M.selectionUsesOrdinaryModuleInitialization()
    local sources = files(
        [[module main
local spi = require("nupp.spi")
local {type Codec} = require("example.api")
local selected: Codec = do
    local chosen: Codec?
    local tied = false
    for candidate in spi.load(Codec) do
        if chosen == nil or (candidate.priority ?? 0) > (chosen.priority ?? 0) then
            chosen = candidate
            tied = false
        elseif (candidate.priority ?? 0) == (chosen.priority ?? 0) then
            tied = true
        end
    end
    assert(not tied, "highest priority is tied")
    yield chosen ?? require("example.first")
end
export const encode = selected.encode
assert(encode("x") == "second:x")
print("ok")]]
    )
    sources[
        "src/example/api.nupp"
    ] = [[module example.api
export interface Codec
    readonly priority: integer?
    readonly encode: function(value: string): string
end]]
    sources["src/example/second.nupp"] = sources["src/example/second.nupp"] .. "\nexport const priority: integer = 5"
    fixture(sources, function(dir)
        local _, output = run(dir)
        assert(output == "ok\n", output)
    end)
end

function M.onlyExportedConcreteInterfacesCanBeLoaded()
    for _, declaration in ipairs({
        "local interface Codec readonly encode: function(string): string end",
        "export record Codec readonly encode: function(string): string end",
        "export interface Codec<T> readonly encode: function(T): T end",
    }) do
        fixture(
            files(
                "module main\nlocal spi = require('nupp.spi')\n" .. declaration .. "\nlocal iterator = spi.load(Codec)",
                "{}"
            ),
            function(dir)
                assert(project.build(dir) ~= 0, declaration)
            end
        )
    end
end

return M
