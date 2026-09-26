-- Compile one Nupp `@aot` source file into the spike's private artifacts: the
-- verified IR, the LLVM IR and its object, the binding, and, when LIBRARY is
-- given, the shared library the binding loads.

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local root = here .. "../.."
local compiler = dofile(here .. "kernel_compiler.lua")
local parser = require("nupp.compiler.syntax.parser")
local check = require("nupp.compiler.check")
local env = require("nupp.compiler.project.env")
local input = assert(arg[1], "usage: generate.lua INPUT.nupp OUTPUT_DIR [LIBRARY]")
local output = assert(arg[2], "usage: generate.lua INPUT.nupp OUTPUT_DIR [LIBRARY]")
local library = arg[3]

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
if #parsed.errors > 0 then
    for _, problem in ipairs(parsed.errors) do
        io.stderr:write(
            (
                "%s:%d:%d: %s\n"
            ):format(input, problem.line or 1, problem.col or 1, problem.message or problem.msg or "syntax error")
        )
    end
    os.exit(1)
end

local checkedDiagnostics = check.check(parsed, input, env.new(root))
if #checkedDiagnostics > 0 then
    for _, problem in ipairs(checkedDiagnostics) do
        local start = problem.range and problem.range.start or {}
        io.stderr:write(
            (
                "%s:%d:%d: %s: %s\n"
            ):format(
                problem.file or input,
                start.line or 1,
                start.column or 1,
                problem.code or "error",
                problem.message or "checking failed"
            )
        )
    end
    os.exit(1)
end

-- Lower the same tree the checker annotated.
local artifacts, diagnostics = compiler.compile(source, input, parsed)
if not artifacts then
    for _, problem in ipairs(diagnostics) do
        io.stderr:write(compiler.renderDiagnostic(problem), "\n")
    end
    os.exit(1)
end

write(output .. "/kernel.ir", artifacts.irText)
write(output .. "/checked.nupp", artifacts.binding)

-- LLVM in process, with the logical symbols the binding names.
local aotllvm = require("nupp.tools.build.aotllvm")
local selected = artifacts.selected
local ir, why = aotllvm.emit(artifacts.programs, selected.tier, selected.triple, true)
assert(ir, why)
write(output .. "/kernel.ll", ir)
local object = output .. "/kernel.o"
local compileErr = aotllvm.compileMany({
    {ir = output .. "/kernel.ll", triple = selected.triple, tier = selected.tier, object = object},
})
assert(compileErr == nil, compileErr)
if library then
    local linkErr = aotllvm.link(selected.triple, {object}, library)
    assert(linkErr == nil, linkErr)
end
