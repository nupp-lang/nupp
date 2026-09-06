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
-- `@aot`, `vectorize`, relaxation, or fixed-width establishment from source
-- spelling.
local artifacts, diagnostics = compiler.compile(source, input, parsed)
if not artifacts then
   for _, problem in ipairs(diagnostics) do
      io.stderr:write(compiler.renderDiagnostic(problem), "\n")
   end
   os.exit(1)
end

-- Whether a loop vectorized is a performance property: no answer depends on it,
-- so no ordinary check reports it, and an edit can quietly take it away. That is
-- the same category `nupp bc --check` already covers for a loop LuaJIT cannot
-- record, and it gets the same treatment -- a check that names the construct and
-- exits 1, rather than an annotation that turns it into a build error for
-- everyone. `@aot(vectorize = false)` is how a deliberately scalar body says so.
if arg[3] == "--check-lanes" then
   io.write(("%s: %.2f arithmetic operations per byte (%d over %d)\n"):format(
      input, artifacts.ir.intensity, artifacts.ir.operations, artifacts.ir.touchedBytes))
   if artifacts.ir.lanes then
      io.write(("%s: lowered to %d lanes\n"):format(input, artifacts.ir.lanes.lanes))
      os.exit(0)
   end
   if artifacts.ir.thin then
      io.write(("%s: declined, too little arithmetic per byte for lanes to pay\n"):format(input))
      os.exit(0)
   end
   if artifacts.ir.vectorizeDeclined then
      io.write(("%s: lane lowering declined by `@aot(vectorize = false)`\n"):format(input))
      os.exit(0)
   end
   io.stderr:write(("%s: ran one iteration at a time\n"):format(input))
   for _, problem in ipairs(artifacts.ir.laneRefusals or {}) do
      io.stderr:write("  ", compiler.renderDiagnostic(problem), "\n")
   end
   os.exit(1)
end

write(output .. "/kernel.ir", artifacts.irText)
write(output .. "/kernel.c", artifacts.c)
write(output .. "/checked.nupp", artifacts.binding)
