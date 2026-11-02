local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("fragment")
local envMod = require("nupp.compiler.project.env")
local generator = require("nupp.compiler.lua.gen")
local compile = require("nupp.compiler.aot.compile")
local text = require("nupp.compiler.aot.text")
local mathRuntime = require("nupp.compiler.runtime.math")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."
local M = {}

local function futureModule(name, path, transform)
    local env = envMod.new(ROOT, {cache = false})
    local file = assert(io.open(ROOT .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    local _, diagnostics = envMod.checkModuleSource(env, ROOT .. "/" .. path, transform(source), {moduleName = name})
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)

    return env
end

local function checked(source, env)
    local parsed = parser.parse(source, "short-names.nupp")
    test.eq(#parsed.errors, 0)
    local diagnostics = checker.check(parsed, "short-names.nupp", env)
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)

    return parsed
end

function M.shortMathNamesKeepTheExistingFunctionsAndContracts()
    local namespace = {}
    mathRuntime.install(namespace)
    test.eq(namespace.vec2.length, nil)
    test.eq(namespace.vec2.distance, nil)
    test.eq(namespace.quat.length, nil)
    test.eq(namespace.quat.multiply, nil)
    test.eq(namespace.vec2.len(3, 4), 5)
    test.eq(namespace.vec2.dist(1, 2, 4, 6), 5)
    test.eq(namespace.quat.len(0, 0, 0, 1), 1)
    local a = {namespace.quat.mul(1, 0, 0, 0, 0, 1, 0, 0)}
    test.deepeq(a, {0, 0, 1, 0})
    checked(
        [[
local length: number = math.vec2.len(3, 4)
local distance: number = math.vec2.dist(1, 2, 4, 6)
local magnitude: number = math.quat.len(0, 0, 0, 1)
local x, y, z, w = math.quat.mul(1, 0, 0, 0, 0, 1, 0, 0)
return length, distance, magnitude, x, y, z, w
]],
        envMod.new(ROOT)
    )
end

function M.soaAllocKeepsTheExistingAllocationOperation()
    local env = futureModule("nupp.mem.soa", "src/nupp/mem/soa.nupp", function(source)
        return (source:gsub("soa%.allocate", "soa.alloc"))
    end)
    local source = [[
local soa = require("nupp.mem.soa")
local ffi = require("ffi")
local struct Row
    x: int32
end
local owner = soa.alloc(ffi.typeof<Row>(), 2)
do local rows = owner:write() ;
    rows[1].x = 17
end
local rows = owner:read()
return rows[1].x
]]
    local parsed = checked(source, env)
    local code, diagnostics = generator.generate(parsed, "short-names.nupp")
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    assert(code:find("._allocate", 1, true), code)
    test.eq(assert(loadstring(code, "@short-names.nupp"))(), 17)
end

local BUILDER = [[
local builder = require("serde.valuebuilder")
@aot
local function decode(source: string, nullValue: any): any
    local count: uint32 = builder.len(source)
    local state = builder.newsized(nullValue, count, count)
    builder.openarray(state, math.u32.wrap(1))
    builder.numberslice(state, source, math.u32.wrap(0), count)
    builder.close(state)
    return builder.finish(state)
end
]]

function M.lowercaseBuilderFunctionsAndLenKeepNativeOperations()
    local before
    for _, future in ipairs({false, true}) do
        local env = future and futureModule("serde.valuebuilder", "src/serde/valuebuilder.nupp", function(source)
            return (source:gsub("export const ([%w_]+)", function(name)
                return "export const " .. (name == "length" and "len" or name:lower())
            end))
        end) or envMod.new(ROOT)
        local source = future and BUILDER:gsub("builder%.([%w_]+)", function(name)
            return "builder." .. (name == "length" and "len" or name:lower())
        end) or BUILDER
        local parsed = checked(source, env)
        local programs, diagnostics = compile.lower(source, "short-names.nupp", parsed)
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].message)
        test.eq(#programs, 1)
        local actual = text.programs(programs)
        assert(actual:find("lua.length(", 1, true), actual)
        if before then
            test.eq(actual, before, "public builder names changed native operations")
        end
        before = actual
    end
end

function M.shortNamesOnOrdinaryLocalTablesRemainOrdinaryCalls()
    local source = [[
local soa = {alloc = function(): number return 2 end}
local builder = {len = function(): number return 3 end}
local math = {quat = {mul = function(): number return 5 end}}
return soa.alloc() + builder.len() + math.quat.mul()
]]
    local parsed = checked(source, envMod.new(ROOT))
    local code, diagnostics = generator.generate(parsed, "short-names.nupp")
    test.eq(#diagnostics, 0)
    test.eq(assert(loadstring(code, "@short-names.nupp"))(), 10)
end

return M
