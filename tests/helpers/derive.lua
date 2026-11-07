local testAssert = require("assert")
-- Compiler-owned declaration derives: semantic members, factory projection, and
-- closed runtime recipes independently of serialization bindings.
local parser = require("nupp.compiler.syntax.parser")
local gen = require("nupp.compiler.lua.gen")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local derive = require("nupp.compiler.check.derive")
local recipeCodec = require("nupp.compiler.comptime.materialize.codec")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local function compileAt(source, filename, opts)
    filename = filename or "derive_test.nupp"
    local parsed = parser.parse(source, filename)
    testAssert.eq(#parsed.errors, 0, "syntax errors")
    local diagnostics = check.check(parsed, filename, env, opts)
    local code, generated = gen.generate(parsed, "derive_test")
    for _, diagnostic in ipairs(generated) do
        diagnostics[#diagnostics + 1] = diagnostic
    end

    return code, diagnostics, parsed
end

local function compile(source)
    return compileAt(source, "derive_test.nupp")
end

local function firstDeclaration(parsed)
    for _, stat in ipairs(parsed.root.blocks[1].stats) do
        while stat and stat.kind == "pragmaStmt" do
            stat = stat.stat
        end
        if stat and stat.kind == "recordDecl" then
            return stat
        end
    end
    error("fixture has no declaration")
end

local function errorsOf(source)
    local _, diagnostics = compile(source)
    local out = {}
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
            out[#out + 1] = diagnostic.code
        end
    end

    return out, diagnostics
end

local function run(source)
    local code, diagnostics = compile(source)
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
            error(("unexpected %s: %s\n---\n%s"):format(diagnostic.code, diagnostic.msg, code), 2)
        end
    end
    local chunk, why = loadstring(code, "@derive_test")
    assert(chunk, why and (why .. "\n---\n" .. code))
    local _, sourceLines = source:gsub("\n", "\n")
    local _, outputLines = code:gsub("\n", "\n")
    testAssert.eq(outputLines, sourceLines, "derive lowering changed the source/output line count")

    return chunk(), code
end

return {
    testAssert = testAssert,
    parser = parser,
    gen = gen,
    check = check,
    envMod = envMod,
    derive = derive,
    recipeCodec = recipeCodec,
    HERE = HERE,
    env = env,
    compileAt = compileAt,
    compile = compile,
    firstDeclaration = firstDeclaration,
    errorsOf = errorsOf,
    run = run,
}
