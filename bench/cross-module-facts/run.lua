-- Run from the repository root with its built compiler on LUA_PATH.
-- Arguments: an existing output directory, then a label such as baseline.
local OUTPUT = assert(arg[1], "pass an existing output directory")
local LABEL = arg[2] or "candidate"
assert(LABEL:match("^[%w_-]+$"), "label must be a simple filename component")

do
    local parser = require("nupp.compiler.syntax.parser")
    local incremental = require("nupp.compiler.project.incremental")
    local optimize = require("nupp.compiler.lua.optimize")
    local gen = require("nupp.compiler.lua.gen")
    local json = require("nupp.codec.json")
    local M = {}

    function M.measureModuleBoundaryVariants()
        local dir = os.tmpname()
        os.remove(dir)
        assert(os.execute("mkdir -p '" .. dir .. "'"))

        local function write(path, data)
            local file = assert(io.open(path, "w"));
            file:write(data);
            file:close()
        end

        local cases = {
            {
                name = "numeric",
                direct = "index * 1.5 + 1",
                params = "value: number",
                args = "index",
                expression = "value * 1.5 + 1"
            },
            {
                name = "hash",
                direct = "(total * 33 + index % 256) % 65536",
                params = "value: number, byte: number",
                args = "total, index % 256",
                expression = "(value * 33 + byte) % 65536"
            },
            {
                name = "serializeByte",
                direct = "index % 256",
                params = "value: number",
                args = "index",
                expression = "value % 256"
            },
            {
                name = "componentStep",
                direct = "total + index * 0.125",
                params = "position: number, velocity: number, dt: number",
                args = "total, index, 0.125",
                expression = "position + velocity * dt"
            },
        }
        local results = {}
        for _, case in ipairs(cases) do
            local helper = "local function step(" .. case.params .. "): number return " .. case.expression .. " end\n"
            local provider = helper .. "return {step = step}\n"
            write(dir .. "/xmdep.nupp", provider)
            for _, variant in ipairs({"direct", "local", "imported"}) do
                local prefix = variant == "local" and helper
                    or variant == "direct" and ""
                    or "local D = require('xmdep')\n"
                local call = variant == "direct" and case.direct
                    or (variant == "local" and "step" or "D.step") .. "(" .. case.args .. ")"
                local source = prefix
                    .. "local function run(count: integer): number local total = 0 for index = 1, count do total = "
                    .. call
                    .. " end return total end\nreturn run"
                write(dir .. "/main.nupp", source)
                local inc = incremental.new(dir, {cache = false})
                local started = os.clock()
                local checked = inc.checkFile(dir .. "/main.nupp")
                for _, diagnostic in ipairs(checked.diags) do
                    assert(diagnostic.severity ~= "error", diagnostic.msg)
                end
                local checkMs = (os.clock() - started) * 1000
                local remarks = optimize.run(checked.result, {level = 1})
                local code = gen.generate(checked.result, "main.nupp")
                local dep = inc.checkFile(dir .. "/xmdep.nupp")
                local depCode = gen.generate(dep.result, "xmdep.nupp")
                local oldLoaded, oldPreload = package.loaded.xmdep, package.preload.xmdep
                package.loaded.xmdep = nil
                package.preload.xmdep = function()
                    return assert(loadstring(depCode))()
                end
                local fn = assert(loadstring(code))()
                local referenceSource = helper
                    .. "local total = 0 for index = 1, 100000 do total = step("
                    .. case.args
                    .. ") end return total"
                referenceSource = referenceSource:gsub(": number", "")
                local expected = assert(loadstring(referenceSource))()
                assert(fn(100000) == expected, "generated kernel differs from its scalar reference")
                local samples = {}
                for i = 1, 7 do
                    local before = os.clock()
                    assert(fn(100000) == expected)
                    samples[i] = (os.clock() - before) * 1000
                end
                package.loaded.xmdep, package.preload.xmdep = oldLoaded, oldPreload
                local count = inc.q.stats.checkModule
                inc.changeDocument(dir .. "/xmdep.nupp", provider:gsub("return", "return", 1) .. "\n")
                inc.checkFile(dir .. "/main.nupp")
                results[
                    #results + 1
                ] = {
                    name = case.name,
                    variant = variant,
                    bytes = #code,
                    checkMs = checkMs,
                    rechecks = inc.q.stats.checkModule - count,
                    runtimeMs = samples,
                    result = expected,
                    remarks = remarks
                }
                write(OUTPUT .. "/" .. LABEL .. "-" .. case.name .. "-" .. variant .. ".lua", code)
            end
        end
        write(OUTPUT .. "/" .. LABEL .. ".json", json.encode(results))
        os.execute("rm -rf '" .. dir .. "'")
    end

    M.measureModuleBoundaryVariants()
end

do
    local incremental = require("nupp.compiler.project.incremental")
    local optimize = require("nupp.compiler.lua.optimize")
    local gen = require("nupp.compiler.lua.gen")
    local json = require("nupp.codec.json")
    local M = {}
    function M.measureViewBoundary()
        local dir = os.tmpname()
        os.remove(dir)
        assert(os.execute("mkdir -p '" .. dir .. "'"))

        local function write(path, text)
            local f = assert(io.open(path, "w"));
            f:write(text);
            f:close()
        end

        local prelude = "local span = require('nupp.mem.span')\n"
        local helper = [[
local function sum(borrows values: span.Span<uint8>): number
    local total = 0
    for index = 1, #values do total = total + values[index] end
    return total
end
]]
        write(dir .. "/xmviews.nupp", prelude .. helper .. "return {sum=sum}\n")
        local result = {}
        for _, variant in ipairs({"direct", "local", "imported"}) do
            local source = prelude .. (
                variant == "local" and helper or "local D = require('xmviews')\n"
            ) .. "local function run(text: string): number const values = span.fromString(text) return " .. (
                variant == "local" and "sum" or "D.sum"
            ) .. "(values) end\nreturn run"
            if variant == "direct" then
                source = prelude
                    .. [[
local function run(text: string): number
    const values = span.fromString(text)
    local total = 0
    for index = 1, #values do total = total + values[index] end
    return total
end
return run]]
            end
            write(dir .. "/main.nupp", source)
            local inc = incremental.new(dir, {cache = false})
            local checked = inc.checkFile(dir .. "/main.nupp")
            for _, diagnostic in ipairs(checked.diags) do
                assert(diagnostic.severity ~= "error", diagnostic.msg)
            end
            local remarks = optimize.run(checked.result, {level = 1})
            local code = gen.generate(checked.result, "main.nupp")
            local dep = inc.checkFile(dir .. "/xmviews.nupp")
            local depCode = gen.generate(dep.result, "xmviews.nupp")
            local oldLoaded, oldPreload = package.loaded.xmviews, package.preload.xmviews
            package.loaded.xmviews = nil
            package.preload.xmviews = function()
                return assert(loadstring(depCode))()
            end
            local fn = assert(loadstring(code))()
            local text = string.rep("abcdefgh", 32)
            assert(fn(text) == 25728)
            for _ = 1, 100 do
                assert(fn(text) == 25728)
            end
            local times = {}
            for r = 1, 7 do
                local before = os.clock()
                local total = 0
                for _ = 1, 10000 do
                    total = total + fn(text)
                end
                assert(total == 257280000)
                times[r] = (os.clock() - before) * 1000
            end
            package.loaded.xmviews, package.preload.xmviews = oldLoaded, oldPreload
            result[#result + 1] = {variant = variant, bytes = #code, runtimeMs = times, remarks = remarks}
            write(OUTPUT .. "/" .. LABEL .. "-view-" .. variant .. ".lua", code)
        end
        write(OUTPUT .. "/" .. LABEL .. "-view.json", json.encode(result))
        os.execute("rm -rf '" .. dir .. "'")
    end

    M.measureViewBoundary()
end
