local testAssert = require("assert")
-- Compiler-owned declaration derives: semantic members, factory projection, and
-- closed runtime recipes independently of serialization bindings.
local parser = require("nupp.compiler.syntax.parser")

local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local derive = require("nupp.compiler.check.derive")
local recipeCodec = require("nupp.compiler.comptime.materialize.codec")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local program = require("program")

local function compileAt(source, filename, opts)
    filename = filename or "derive_test.nupp"
    local parsed = parser.parse(source, filename)
    testAssert.eq(#parsed.errors, 0, "syntax errors")
    local checking = {}
    for key, value in pairs(opts or {}) do
        checking[key] = value
    end
    checking.moduleName = checking.moduleName or "derive_test"
    local diagnostics = check.check(parsed, filename, env, checking)

    return parsed, diagnostics, parsed
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

local function run(moduleName, source)
    local parsed, diagnostics = compileAt(source, moduleName .. ".nupp", {moduleName = moduleName})
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
            error(("unexpected %s: %s\n---\n%s"):format(diagnostic.code, diagnostic.msg, source), 2)
        end
    end

    return program.run(parsed, moduleName)
end

return {
    testAssert = testAssert,
    parser = parser,
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
    program = program,
}
