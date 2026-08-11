local importc = require("nupp.compiler.importc")
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

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
   local parser = require("nupp.compiler.parser")
   local result = parser.parse(text, "mini.d.nupp")
   assert(#result.errors == 0, "output with library clauses parses")
end

local enumsText -- shared across cases (import once)

local function enumsImported()
   if not enumsText then
      local text, warnings = importc.import(HERE .. "/fixtures/enums.h")
      assert(text, "import failed: " .. table.concat(warnings or {}, "; "))
      enumsText = text
   end
   return enumsText
end

function M.enumMembersBecomeNamedConstants()
   local text = enumsImported()
   assertContains(text, "local MINI_OK: int32 = 0")
   assertContains(text, "local MINI_BUSY: int32 = 1")
   assertContains(text, "local MINI_GONE: int32 = 7")
   assertContains(text, "MINI_GONE = MINI_GONE", "and are exported")
end

function M.anonymousEnumsCarryTheirMembers()
   local text = enumsImported()
   assertContains(text, "local MINI_READ: int32 = 1")
   assertContains(text, "local MINI_WRITE: int32 = 2")
end

function M.negativeEnumMembersSurvive()
   assertContains(enumsImported(), "local MINI_ERROR: int32 = -1")
end

function M.aConstantKeepsItsFirstMeaning()
   local text = enumsImported()
   local _, count = text:gsub("local MINI_OK[:%s]", "")
   assert(count == 1, "MINI_OK declared " .. count .. " times:\n" .. text)
   assert(not text:find("MINI_OK: number", 1, true),
      "the later macro must not redeclare the enum member:\n" .. text)
end

function M.enumOutputParsesAndChecksCleanly()
   local text = enumsImported()
   local result = parser.parse(text, "enums.d.nupp")
   assert(#result.errors == 0, "generated file must parse: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local diags = check.check(result, "enums.d.nupp")
   assert(#diags == 0, "generated file must check: "
      .. (diags[1] and diags[1].msg or ""))
end

function M.anEnumMemberIsAcceptedWhereItsFunctionWantsIt()
   -- The point of importing the members: a C enum parameter is an integer
   -- everywhere it appears, and the constant fits it without a cast.
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local f = assert(io.open(dir .. "/enums.d.nupp", "wb"))
   f:write(enumsImported())
   f:close()
   local env = envMod.new(dir)

   local result = parser.parse(table.concat({
      "local e = require('enums')",
      "local rc: number = e.mini_status(e.MINI_BUSY)",
   }, "\n"), "consumer")
   assert(#result.errors == 0, "consumer must parse")
   local diags = check.check(result, "consumer.g.nupp", env)
   assert(#diags == 0, "consumer should check cleanly: "
      .. (diags[1] and diags[1].msg or ""))

   os.execute("rm -rf '" .. dir .. "'")
end

function M.aDeclarationTheParserRejectsCostsOnlyItself()
   local text = importc.import(HERE .. "/fixtures/partial.h")
   assert(text, "a rejected declaration must not take the header with it")
   assertContains(text, "cdef function partial_add(a: int32, b: int32): int32")
   assertContains(text, "cdef function partial_scale(v: number): number")
   assertContains(text, "-- import-c: skipped declaration")
   assertContains(text, "partialHolder", "the residue names what was lost")
end

function M.skippedDeclarationsAreCountedOnTheWayOut()
   -- The count is the signal: one of four is a corner in the header, and
   -- four of four is a module not worth having.
   local _, warnings = importc.import(HERE .. "/fixtures/partial.h")
   assert(#warnings == 1, "expected one warning, got " .. #warnings)
   assertContains(warnings[1], "1 of 4 declarations skipped")
end

function M.typedefsAreDeclaredInTheOrderCCanReadThem()
   -- chain_base.h reaches chain_size_t through names that sort before the
   -- ones they are built from, which is how Darwin spells its own.
   local text, warnings = importc.import(HERE .. "/fixtures/chain.h")
   assert(text, "chain import failed: "
      .. table.concat(warnings or {}, "; "))
   assertContains(text, "chain_len(s: cstring): uint64",
      "the chain resolved to its base type")
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
      local result = parser.parse(src, "consumer.g.nupp")
      assert(#result.errors == 0, "consumer must parse")
      local diags = check.check(result, "consumer.g.nupp", env)
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
