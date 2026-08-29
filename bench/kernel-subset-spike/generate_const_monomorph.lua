-- Generate the retained const-specialized C fixture and its stable symbol.
local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local root = here .. "../.."
package.path = root .. "/build/?.lua;" .. package.path

local compile = require("nupp.compiler.aot.compile")
local parser = require("nupp.compiler.parser")
local check = require("nupp.compiler.check")
local env = require("nupp.compiler.env")
local targets = require("nupp.compiler.aot.target")

local input = assert(arg[1], "usage: generate_const_monomorph.lua INPUT OUTPUT_DIR")
local output = assert(arg[2], "usage: generate_const_monomorph.lua INPUT OUTPUT_DIR")

local function read(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    assert(file:close())
    return value
end

local function write(path, value)
    local file = assert(io.open(path, "wb"))
    assert(file:write(value))
    assert(file:close())
end

local source = read(input)
local parsed = parser.parse(source, input)
local diagnostics = check.check(parsed, input, env.new(root))
for _, problem in ipairs(diagnostics) do
    if problem.severity == "error" then
        error(problem.message, 0)
    end
end

local selected = assert(targets.select(nil, targets.tiers(
    targets.architecture(assert(require("nupp.compiler.targetlayout").hostKey())))[1]))
local artifacts, problems = compile.constSpecializations(source, input, parsed, selected)
if artifacts == nil then
    for _, problem in ipairs(problems) do
        io.stderr:write(compile.renderDiagnostic(problem), "\n")
    end
    os.exit(1)
end

assert(#artifacts.programs == 1, "prototype fixture should discover one const tuple")
write(output .. "/kernel.c", artifacts.c)
write(output .. "/kernel.ir", artifacts.irText)
write(output .. "/symbol.txt", artifacts.programs[1].symbol .. "\n")
io.write(artifacts.programs[1].symbol, "\n")
