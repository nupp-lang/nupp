-- Whole-plan acceptance with native compilation absent: one ordinary system-shaped
-- source exercises every independent foundation and keeps the same answer under both
-- LuaJIT execution modes.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local gen = require("nupp.compiler.gen")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."

local function read(path)
   local file = assert(io.open(path, "rb"))
   local text = file:read("*a")
   file:close()
   return text
end

local M = {}

function M.ordinaryTecsShapedSourceAgreesWithTheJitOnAndOff()
   local path = HERE .. "/fixtures/native_foundations.nupp"
   local parsed = parser.parse(read(path), path)
   assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg or "parse")
   local diagnostics = check.check(parsed, path, envMod.new(ROOT, {cache = false}),
      {moduleName = "tests.fixtures.native_foundations"})
   for _, diagnostic in ipairs(diagnostics) do
      assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
   end
   local code, generatedDiagnostics = gen.generate(parsed, path)
   assert(#generatedDiagnostics == 0,
      generatedDiagnostics[1] and generatedDiagnostics[1].msg or "generation")
   local module = assert(loadstring(code, "@native-foundations"))()

   local wasEnabled = jit.status()
   jit.off(module.run, true)
   local interpretedX, interpretedFlags = module.run()
   jit.on(module.run, true)
   jit.flush(module.run, true)
   local compiledX, compiledFlags = module.run()
   if not wasEnabled then jit.off() end

   assert(interpretedX == compiledX, "binary32 result is independent of JIT mode")
   assert(interpretedFlags == compiledFlags, "integer result is independent of JIT mode")
   assert(tonumber(compiledFlags) == 8, "the checked slice updates its last element")
end

function M.representativeLoopsAndThePointerWrapperRemainTraceable()
   local command = "cd '" .. ROOT .. "' && ./bin/nupp bc --check "
   assert(os.execute(command .. "tests/fixtures/native_foundations.nupp >/dev/null 2>&1") == 0,
      "numeric, span, and effect-region loops pass bytecode inspection")
   assert(os.execute(command .. "tests/fixtures/export_c_wrapper.nupp >/dev/null 2>&1") == 0,
      "the typed ordinary-struct pointer wrapper passes bytecode inspection")
end

return M
