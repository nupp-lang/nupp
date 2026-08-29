-- Compile the benchmark's annotated Nupp body to one native C translation unit.
local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local root = here .. "../.."
package.path = root .. "/build/?.lua;" .. package.path

local aot = require("nupp.compiler.aot.compile")
local target = require("nupp.compiler.aot.target")
local parser = require("nupp.compiler.parser")
local check = require("nupp.compiler.check")
local env = require("nupp.compiler.env")

local input = assert(arg[1], "usage: compile.lua INPUT.nupp OUTPUT_DIR")
local output = assert(arg[2], "usage: compile.lua INPUT.nupp OUTPUT_DIR")

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
      io.stderr:write(("%s:%d:%d: %s\n"):format(
         input, problem.line or 1, problem.col or 1,
         problem.message or problem.msg or "syntax error"
      ))
   end
   os.exit(1)
end

local checkedDiagnostics = check.check(parsed, input, env.new(root))
if #checkedDiagnostics > 0 then
   for _, problem in ipairs(checkedDiagnostics) do
      local start = problem.range and problem.range.start or {}
      io.stderr:write(("%s:%d:%d: %s: %s\n"):format(
         problem.file or input, start.line or 1, start.column or 1,
         problem.code or "error", problem.message or "checking failed"
      ))
   end
   os.exit(1)
end

local host = assert(require("nupp.compiler.targetlayout").hostKey())
local architecture = target.architecture(host)
local selected = assert(target.select(nil, target.tiers(architecture)[1]))
local gangBytes = os.getenv("NUPP_AOT_BENCH_GANG_BYTES")
if gangBytes ~= nil and gangBytes ~= "16" then
   error("NUPP_AOT_BENCH_GANG_BYTES accepts only 16")
end
if gangBytes == "16" then
   selected = {triple = host, architecture = architecture, tier = "baseline"}
end

local library = "bench/simd-mandelbrot/build/libmandelbrot"
local artifacts, diagnostics = aot.artifacts(source, input, parsed, library, selected)
if not artifacts then
   for _, problem in ipairs(diagnostics) do
      io.stderr:write(aot.renderDiagnostic(problem), "\n")
   end
   os.exit(1)
end

write(output .. "/kernel.ir", artifacts.irText)
write(output .. "/kernel.c", artifacts.c)
write(output .. "/checked.nupp", artifacts.binding)
