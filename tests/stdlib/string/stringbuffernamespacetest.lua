local testAssert = require("assert")
-- `string.buffer`, a builtin namespace path backed by the string.buffer module.
--
-- The runtime keeps it in package.loaded and puts nothing on the `string` table.
-- The compiler gives the module its builtin surface without changing that table.
--
-- Everything here runs the compiled code: the point of the namespace is what it
-- lowers to, and a type that checks is not evidence about that.
local parser = require("nupp.compiler.syntax.parser")
local program = require("program")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local function runs(src)
    local result = parser.parse(src, "test.nupp")
    testAssert.eq(#result.errors, 0, "syntax errors in test source")
    local diags = check.check(result, "test.nupp", env)
    for _, diag in ipairs(diags or {}) do
        if diag.severity == "error" then
            error(("%s: %s\n%s"):format(diag.code, diag.msg, src), 2)
        end
    end

    return program.run(result, "string_buffer_namespace_test", "test.nupp")
end

local M = {}

function M.buildsAStringWithNoRequire()
    local value = runs(
        [[
local b: string.buffer.Buffer = string.buffer.new()
b:put("a", "b")
b:put(1, 2)
return b:tostring()
]]
    )
    testAssert.eq(value, "ab12", "the module is reachable through the string namespace")
end

function M.theModuleIsTypedRatherThanAny()
    -- If `string.buffer` were `any` this would check silently. It resolves to the
    -- declaration in decls/stringbuffer.d.nupp, so the arity is held.
    local result = parser.parse("local b = string.buffer.new(1, 2, 3, 4)\nreturn b\n", "test")
    testAssert.eq(#result.errors, 0, "syntax errors")
    local diags = check.check(result, "test.nupp", env)
    local found = false
    for _, diag in ipairs(diags or {}) do
        if diag.severity == "error" then
            found = true
        end
    end
    testAssert.eq(found, true, "too many arguments is an error, so the type is real")
end

function M.aShadowingBindingWins()
    local value = runs(
        [[
local string = {buffer = {new = function(): string return "shadowed" end}}
return string.buffer.new()
]]
    )
    testAssert.eq(value, "shadowed", "a local named string is that local")
end

function M.anExplicitRequireStillWorks()
    local value = runs([[
const buffer = require("string.buffer")
local b = buffer.new()
b:put("x")
return b:tostring()
]])
    testAssert.eq(value, "x", "writing the require explicitly still works")
end

function M.bareBufferIsNotACompilerGlobal()
    local result = parser.parse("local b = buffer.new()\nreturn b\n", "test.nupp")
    testAssert.eq(#result.errors, 0, "syntax errors")
    local diags = check.check(result, "test.nupp", env)
    local found = false
    for _, diag in ipairs(diags or {}) do
        if diag.severity == "error" then
            found = true
        end
    end
    testAssert.eq(found, true, "strict source rejects the removed buffer global")
end

function M.theRetiredTextFacadeIsUnavailable()
    local result = parser.parse("return nupp.text.newbuffer()\n", "test.nupp")
    testAssert.eq(#result.errors, 0, "syntax errors")
    local diags = check.check(result, "test.nupp", env)
    local found = false
    for _, diag in ipairs(diags or {}) do
        found = found or diag.severity == "error"
    end
    testAssert.eq(found, true, "the retired text facade is not a public namespace")
end

function M.decodingRoundTrips()
    -- The module is the whole module, not a hand-picked `new`.
    local value = runs([[
local b = string.buffer.new()
b:encode({1, 2, 3})
local out = b:decode()
return #out
]])
    testAssert.eq(value, 3, "encode and decode are reachable too")
end

function M.compilerFactoryRetainsTheBufferImplementation()
    local buffers = require("string.buffer")
    testAssert.eq(type(buffers.new), "function")
    testAssert.eq(buffers.new, buffers.new)
    local buffer = buffers.new()
    buffer:put("native", " buffer")
    testAssert.eq(buffer:tostring(), "native buffer")
end

return M
