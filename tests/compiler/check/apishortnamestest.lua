local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local program = require("program")
local compile = require("nupp.tools.cli.compile")
local loadImage = assert(rawget(_G, "__nupp_load_image"))
local mathRuntime = require("nupp.compiler.runtime.math")
local HERE = require("helpers.paths").tests
local ROOT = HERE .. "/.."
local M = {}

local function futureModule(name, path, transform)
    local env = envMod.new(ROOT, {cache = false})
    local file = assert(io.open(ROOT .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    local transformed = transform(source)
    local _, diagnostics = envMod.checkModuleSource(env, ROOT .. "/" .. path, transformed, {moduleName = name})
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)

    return env, transformed
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
    local env = envMod.new(ROOT)
    local source = [[
local soa = table.Array
local span = require("bytes.span")
local struct Row
    x: int32
end
local owner = soa.alloc(ffi.typeof<Row>(), 2, "columnar")
do local rows = owner:write() ;
    rows[1].x = 17
end
local rows = owner:read()
return rows[1].x
]]
    local parsed = checked(source, env)
    local image = program.image(parsed, "short-names", "short-names.nupp")
    assert(image:find("_allocate", 1, true), "the VM retains the existing private allocation operation")
    test.eq(program.run(parsed, "short-names", "short-names.nupp"), 17)
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

function M.lowercaseBuilderFunctionsAndLenKeepRuntimeValues()
    local before
    for _, future in ipairs({false, true}) do
        local env, implementation
        if future then
            env, implementation = futureModule("serde.valuebuilder", "src/serde/valuebuilder.nupp", function(source)
                return (source:gsub("export const ([%w_]+)", function(name)
                    return "export const " .. (name == "length" and "len" or name:lower())
                end))
            end)
        else
            env = envMod.new(ROOT)
        end
        local source = future and BUILDER:gsub("builder%.([%w_]+)", function(name)
            return "builder." .. (name == "length" and "len" or name:lower())
        end) or BUILDER
        local parsed = checked(source .. '\nreturn decode("7", {}) as {number}', env)
        local loaded, preload = package.loaded["serde.valuebuilder"], package.preload["serde.valuebuilder"]
        local ok, actual = pcall(function()
            if implementation then
                local image = assert(
                    compile.image(
                        ROOT .. "/src/serde/valuebuilder.nupp",
                        env,
                        "serde.valuebuilder",
                        nil,
                        implementation
                    )
                )
                package.loaded["serde.valuebuilder"] = nil
                package.preload["serde.valuebuilder"] = assert(loadImage(image))
            end

            return program.run(parsed, "short-names", "short-names.nupp")
        end)
        package.loaded["serde.valuebuilder"], package.preload["serde.valuebuilder"] = loaded, preload
        assert(ok, actual)
        test.deepeq(actual, {7})
        if before then
            test.deepeq(actual, before, "public names changed the retained VM implementation's results")
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
    test.eq(program.run(parsed, "short-names", "short-names.nupp"), 10)
end

return M
