local importc = require("nupp.importc")
local parser = require("nupp.parser")
local check = require("nupp.check")
local envMod = require("nupp.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local function assertContains(text, needle, label)
   if not text:find(needle, 1, true) then
      error(("%s: %q not found in:\n%s"):format(label or "missing",
         needle, text), 2)
   end
end

local M = {}

local generated -- shared across cases (import once)

local function imported()
   if not generated then
      local text, warnings = importc.import(HERE .. "/fixtures/mini.h")
      assert(text, "import failed: " .. table.concat(warnings or {}, "; "))
      generated = text
   end
   return generated
end

function M.importEmitsTypedDeclarations()
   local text = imported()
   assertContains(text, "cdef struct miniPoint")
   assertContains(text, "x: number")
   assertContains(text, "min: miniPoint", "nested struct by value")
   assertContains(text, "flags: uint32")
   assertContains(text, "cdef function mini_add(a: int32, b: int32): int32")
   assertContains(text, "mini_name(): cstring")
   assertContains(text, "mini_fill(p: miniPoint*, n: uint32)")
   assertContains(text, "mini_len(s: cstring): uint64")
   assertContains(text, "mini_printf(fmt: cstring, ...): int32", "C varargs")
   assertContains(text,
      "mini_translate(p: miniPoint, dx: number, dy: number): miniPoint",
      "structs pass and return by value")
end

function M.functionPointerParamsComeFromLuaJITsModel()
   assertContains(imported(),
      "mini_each(fn: function(int32), n: int32)",
      "callbacks use the same parsed declaration model as cheader")
end

function M.macroConstants()
   local text = imported()
   assertContains(text, "local MINI_MAX: number = 64")
   assertContains(text, "local MINI_FLAG: number = (1 << 3)",
      "shift expression stays valid nupp")
   assertContains(text, 'local MINI_NAME: string = "mini"')
   assert(not text:find("MINI_SKIP", 1, true),
      "unevaluable macro must not be emitted")
end

function M.typedefsResolveThroughTheTranslationUnit()
   -- mini.h has no typedefs of its own; this exercises the resolver on a
   -- header whose vocabulary comes from elsewhere (size_t via stddef.h)
   assertContains(imported(), "mini_len(s: cstring): uint64",
      "size_t resolved to a base type")
end

function M.constBytePointersBecomeCstring()
   -- const char*/unsigned char* take a Lua string directly in LuaJIT
   assertContains(imported(), "mini_len(s: cstring)")
   assertContains(imported(), "mini_name(): cstring")
end

function M.libraryClauseIsEmitted()
   local text = importc.import(HERE .. "/fixtures/mini.h", {lib = "mini"})
   assert(text:find('from "mini"', 1, true),
      "every function carries the library clause:\n" .. text:sub(1, 400))
   local parser = require("nupp.parser")
   local result = parser.parse(text, "mini.d.nupp")
   assert(#result.errors == 0, "output with library clauses parses")
end

function M.outputParsesAndChecksCleanly()
   local text = imported()
   local result = parser.parse(text, "mini.d.nupp")
   assert(#result.errors == 0, "generated file must parse: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local diags = check.check(result, "mini.d.nupp")
   assert(#diags == 0, "generated file must check: "
      .. (diags[1] and diags[1].msg or ""))
end

function M.consumerTypechecksAgainstImport()
   -- write the generated file where the module resolver will find it
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local f = assert(io.open(dir .. "/mini.d.nupp", "wb"))
   f:write(imported())
   f:close()
   local env = envMod.new(dir)

   local function diagsOf(src)
      env.loaded = {}
      local result = parser.parse(src, "consumer")
      assert(#result.errors == 0, "consumer must parse")
      local diags = check.check(result, "consumer", env)
      local out = {}
      for j, d in ipairs(diags) do out[j] = d.code .. ":" .. d.line end
      return table.concat(out, " "), diags
   end

   local clean, cleanDiags = diagsOf(table.concat({
      "local mini = require('mini')",
      "local n: number = mini.mini_add(1, 2)",
      "local cap: number = mini.MINI_MAX",
   }, "\n"))
   assert(clean == "", "consumer should check cleanly: "
      .. (cleanDiags[1] and cleanDiags[1].msg or ""))

   local bad = diagsOf(table.concat({
      "local mini = require('mini')",
      "mini.mini_add('x', 2)",
   }, "\n"))
   assert(bad == "NUPP2006:2", "argument mismatch caught: " .. bad)

   local typo = diagsOf(table.concat({
      "local mini = require('mini')",
      "mini.mini_addd(1, 2)",
   }, "\n"))
   assert(typo == "NUPP2004:2", "typo caught: " .. typo)

   os.execute("rm -rf '" .. dir .. "'")
end

return M
