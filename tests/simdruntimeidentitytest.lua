local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local generator = require("nupp.compiler.lua.gen")

local M = {}

local SOURCE = [[
local lanes = require(%q)
local first = lanes.construct(9)
local second = lanes.construct(3)
local holder = lanes.holder(first)
return first + second, -first, first:abs(), lanes.sqrt(first), holder.values
]]

local function checkedFixture(module, sealed)
    local parsed = parser.parse(SOURCE:format(module), "simd-runtime-identity.nupp")
    test.eq(#parsed.errors, 0)
    local origin = {name = "Vector"}
    origin[sealed and "sealedModule" or "moduleName"] = module
    local vector = {
        tag = "nominal",
        origin = origin,
        typeArgs = {
            {tag = "float"},
            {
                tag = "nominal",
                origin = {moduleName = module, name = "Fixed"},
                constArgs = {{tag = "constLiteral", domain = "integer", value = 4}},
            },
        },
    }
    local storageVector = {tag = "nominal", origin = {moduleName = module, name = "Vector"}, typeArgs = vector.typeArgs}
    local holder = {tag = "nominal", declKind = "struct", origin = {name = "Holder"}}
    local seen = {}

    local function annotate(node)
        if type(node) ~= "table" or seen[node] then
            return
        end
        seen[node] = true
        for _, child in pairs(node) do
            annotate(child)
        end
        if node.kind == "name" and node.token then
            if node.token.text == "first" or node.token.text == "second" then
                node.inferredType = vector
            elseif node.token.text == "holder" then
                node.inferredType = holder
            end
        elseif node.kind == "binop" or node.kind == "unop" then
            node.simdIntrinsic = true
        elseif node.kind == "call" and node.obj and node.obj.kind == "dotIndex" and node.obj.name.text == "sqrt" then
            node.simdMath = "sqrt"
        elseif node.kind == "dotIndex" and node.name.text == "values" then
            node.inferredType = {tag = "borrowed", inner = {tag = "genericAlias", body = storageVector}}
        end
    end

    annotate(parsed.root)

    return parsed
end

function M.generatedHelpersUseTheConstructorsOwnModuleInstance()
    for _, module in ipairs({"nupp.simd", "simd"}) do
        for _, sealed in ipairs({false, true}) do
            local other = module == "simd" and "nupp.simd" or "simd"
            local marker, calls = {}, 0

            local function construct(value)
                return setmetatable({value = value}, marker)
            end

            local function value(item)
                test.eq(getmetatable(item), marker, "helper used a different module's vector marker")
                return item.value
            end

            local runtime = {
                construct = construct,
                holder = function(item)
                    return {values = item}
                end
            }
            runtime.lane = {
                binary = function(op, element, left, right)
                    calls = calls + 1
                    test.eq(op, "+")
                    test.eq(element, "float")
                    return construct(value(left) + value(right))
                end,
                unary = function(op, element, item)
                    calls = calls + 1
                    test.eq(op, "-")
                    test.eq(element, "float")
                    return construct(-value(item))
                end,
                method = function(name, element, item)
                    calls = calls + 1
                    test.eq(element, "float")
                    test.eq(name == "abs" or name == "sqrt", true)
                    return construct(name == "sqrt" and math.sqrt(value(item)) or math.abs(value(item)))
                end,
                fromstorage = function(element, lanes, item)
                    calls = calls + 1
                    test.eq(element, "float")
                    test.eq(lanes, 4)
                    return construct(value(item))
                end,
            }
            local saved = {}
            for _, name in ipairs({module, other}) do
                saved[name] = {loaded = package.loaded[name], preload = package.preload[name]}
                package.loaded[name] = nil
            end
            package.preload[module] = function()
                return runtime
            end
            package.preload[other] = function()
                error("loaded the other SIMD module: " .. other)
            end
            local ok, problem = pcall(function()
                local code, problems = generator.generate(checkedFixture(module, sealed), "simd-runtime-identity.nupp")
                test.eq(#problems, 0, problems[1] and problems[1].msg)
                local sum, negated, absolute, root, stored = assert(loadstring(code, "@simd-runtime-identity.nupp"))()
                test.eq(value(sum), 12)
                test.eq(value(negated), -9)
                test.eq(value(absolute), 9)
                test.eq(value(root), 3)
                test.eq(value(stored), 9)
                test.eq(calls, 5)
                test.eq(package.loaded[module], runtime)
                test.eq(package.loaded[other], nil)
            end)
            for name, previous in pairs(saved) do
                package.loaded[name], package.preload[name] = previous.loaded, previous.preload
            end
            if not ok then
                error(problem, 0)
            end
        end
    end
end

return M
