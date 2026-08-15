-- Compile one Nupp `@aot` source file into the spike's private artifacts.

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local root = here .. "../.."
local compiler = dofile(here .. "kernel_compiler.lua")
local parser = require("nupp.compiler.parser")
local check = require("nupp.compiler.check")
local env = require("nupp.compiler.env")
local input = assert(arg[1], "usage: generate.lua INPUT.nupp OUTPUT_DIR")
local output = assert(arg[2], "usage: generate.lua INPUT.nupp OUTPUT_DIR")

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

-- Lower the same tree the checker annotated. The spike does not rediscover
-- `@aot`, `simd`, relaxation, or fixed-width establishment from source spelling.
local artifacts, diagnostics = compiler.compile(source, input, parsed)
if not artifacts then
   for _, problem in ipairs(diagnostics) do
      io.stderr:write(compiler.renderDiagnostic(problem), "\n")
   end
   os.exit(1)
end

write(output .. "/kernel.ir", artifacts.irText)
write(output .. "/kernel.c", artifacts.c)
write(output .. "/checked.nupp", artifacts.binding)
