local test = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("fragment")
local gen = require("nupp.compiler.lua.gen")
local envMod = require("nupp.compiler.project.env")
local M = {}

local function compile(source, filename, env)
    local parsed = parser.parse(source, filename)
    test.equal(#parsed.errors, 0)
    local errors = {}
    for _, item in ipairs(checker.check(parsed, filename, env)) do
        if item.severity == "error" then
            errors[#errors + 1] = item.code .. ": " .. item.msg
        end
    end
    test.equal(table.concat(errors, "\n"), "")
    local code, diagnostics = gen.generate(parsed, filename)
    test.equal(#diagnostics, 0)

    return code
end

local function withExtension(callback)
    local root = os.tmpname()
    os.remove(root)
    local directory = root .. "/src/nupp/runtime"
    assert(os.execute("mkdir -p '" .. directory .. "'") == 0)
    local path = directory .. "/standardio.nupp"
    local source = [[
@!internal
module nupp.runtime.standardio
export function columns(): integer return 73 end
export const value: table = do
    local original = rawget(_G, "io") as any
    original.columns = columns
    yield original
end
]]
    local file = assert(io.open(path, "wb"));
    file:write(source);
    file:close()
    local env = envMod.new(root, {config = {include = {"src"}}})
    local name = "nupp.runtime.standardio"
    local loaded, preload, columns = package.loaded[name], package.preload[name], rawget(io, "columns")
    local ok, reason = pcall(function()
        local code = compile(source, path, env)
        package.loaded[name] = nil
        package.preload[name] = assert(loadstring(code, "@standardio-fixture"))
        callback(env)
    end)
    package.loaded[name], package.preload[name] = loaded, preload
    rawset(io, "columns", columns)
    os.execute("rm -rf '" .. root .. "'")
    assert(ok, reason)
end

function M.preservesTheHostTableThroughAliasesAndRequire()
    withExtension(function(env)
        local source = [[
local original = io
local imported = require("io")
return original == io, original == imported, imported.columns(), original.stdout == imported.stdout
]]
        local code = compile(source, "extension-consumer.nupp", env)
        local global, imported, columns, stdout = assert(loadstring(code))()
        test.equal(global, true)
        test.equal(imported, true)
        test.equal(columns, 73)
        test.equal(stdout, true)
        test.equal(package.loaded.io, io)
        test.equal(require("nupp.runtime.standardio").value, io)
    end)
end

function M.ordinaryBuiltinMembersDoNotLoadExtensions()
    withExtension(function(env)
        local code = compile("return io.stdout", "ordinary-consumer.nupp", env)
        assert(not code:find('require("nupp.runtime.standardio")', 1, true))
        test.equal(assert(loadstring(code))(), io.stdout)
        test.equal(package.loaded["nupp.runtime.standardio"], nil)
    end)
end

function M.localTablesAndRequireShadowsKeepTheirOwnMeaning()
    withExtension(function(env)
        local code = compile(
            [[
module shadow_consumer
export function run(): (integer, integer)
    local io = {columns = function(): integer return 19 end}
    local require: function(string): integer = function(name: string): integer return #name end
    local length: integer = require("io")
    return io.columns(), length
end
]],
            "shadow-consumer.nupp",
            env
        )
        assert(not code:find('require("nupp.runtime.standardio")', 1, true))
        local columns, length = assert(loadstring(code))().run()
        test.equal(columns, 19)
        test.equal(length, 2)
    end)
end

return M
