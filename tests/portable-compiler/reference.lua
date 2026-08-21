-- Produces the differential oracle through the normal LuaJIT compiler entry.
-- The stock Lua host reads these bytes but never gains filesystem access.

local parser = require("nupp.compiler.parser")
local check = require("nupp.compiler.check")
local envMod = require("nupp.compiler.env")
local optimize = require("nupp.compiler.optimize")
local gen = require("nupp.compiler.gen")
local tree = require("nupp.compiler.lsp.tree")
local T = require("nupp.compiler.types")
local json = require("nupp.runtime.provider.lunajson")

local function diagnosticsOf(diagnostics)
   local out = json.asArray({})
   for index, diagnostic in ipairs(diagnostics) do
      out[index] = {
         code = diagnostic.code,
         msg = diagnostic.msg,
         severity = diagnostic.severity,
         line = diagnostic.line,
         col = diagnostic.col,
         offset = diagnostic.offset,
         length = diagnostic.length,
         help = diagnostic.help,
         notes = diagnostic.notes,
         related = diagnostic.related,
      }
   end
   return out
end

local source = "local answer: integer = 42\nreturn answer"
local filename = "differential.nupp"
local parsed = parser.parse(source, filename)
assert(#parsed.errors == 0)
local diagnostics = check.check(parsed, filename, envMod.new(".", {
   cache = false,
   nativeCompilerServices = false,
   config = {_target = {dialect = "lua51", layoutTarget = "x86_64-unknown-linux-gnu"}},
   typeRoots = {},
}), {
   strict = true,
   dialect = "lua51",
})
assert(#diagnostics == 0)

optimize.run(parsed, {
   level = 1,
   filename = filename,
   disabled = {},
   relaxed = {},
})
parsed.effects = optimize.liveEffects(parsed)
local code, generated = gen.generate(parsed, filename, nil, nil, nil, "luajit")
assert(#generated == 0)

local token = assert(tree.tokenAt(parsed, 7))
local definition = token.definition
local valueType = token.inferredType
if (valueType == nil or valueType == T.any) and definition and definition.type then
   valueType = definition.type
end
assert(valueType)
local name = definition and definition.name or token.text
local prefix = definition and definition.cdef and "cdef " or
   definition and definition.constant and "const " or ""

io.write(json.encode({
   check = {diagnostics = diagnosticsOf(diagnostics)},
   compile = {code = code, diagnostics = diagnosticsOf(diagnostics)},
   hover = {
      found = true,
      name = name,
      signature = prefix .. name .. ": " .. T.tostring(valueType),
      offset = token.offset,
      length = #token.text,
   },
}), "\n")
