local importc = require("nupp.compiler.cinterop.importc")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")

local function sourceDirectory(source, currentDirectory)
   local directory = assert(source:match("^@(.*)[/\\]")):gsub("\\", "/")
   if not directory:match("^/") and not directory:match("^%a:/") then
      directory = currentDirectory() .. "/" .. directory
   end
   return directory
end

local HERE = sourceDirectory(debug.getinfo(1, "S").source, function()
   local pipe = assert(io.popen("pwd"))
   local directory = assert(pipe:read("*l"))
   pipe:close()
   return directory
end)
local NUPP = HERE .. "/../bin/nupp"

local function assertContains(text, needle, label)
   if not text:find(needle, 1, true) then
      error(("%s: %q not found in:\n%s"):format(label or "missing",
         needle, text), 2)
   end
end

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s: want %s, got %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local M = {}

function M.windowsSourceDirectoryStaysAbsolute()
   local directory = sourceDirectory("@D:\\a\\nupp\\tests\\importctest.lua", function()
      error("an absolute drive path must not ask for the current directory")
   end)
   assertEq(directory, "D:/a/nupp/tests")
end

local function readFile(path)
   local file = assert(io.open(path, "rb"))
   local text = file:read("*a")
   file:close()
   return text
end

local function runCli(dir, arguments)
   local output = os.tmpname()
   local status = os.execute(("cd %q && %q import-c %s > %q 2>&1")
      :format(dir, NUPP, arguments, output))
   local text = readFile(output)
   os.remove(output)
   return text, status == 0
end

local generated -- shared across cases (import once)

local function imported()
   if not generated then
      local text, warnings = importc.import(HERE .. "/fixtures/mini.h", {module = "mini"})
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
   assertContains(text, "cdef union miniValue")
   assertContains(text, "integer_value: int32")
   assertContains(text, "ready: uint32 : 1")
   assertContains(text, "mode: uint32 : 3")
   assertContains(text, "cdef function mini_add(a: int32, b: int32): int32")
   assertContains(text, "mini_name(): cstring?")
   assertContains(text, "mini_fill(p: miniPoint*?, n: uint32)")
   assertContains(text, "mini_len(s: cstring?): uint64")
   assertContains(text, "mini_printf(fmt: cstring?, ...): int32", "C varargs")
   assertContains(text,
      "mini_translate(p: miniPoint, dx: number, dy: number): miniPoint",
      "structs pass and return by value")
end

function M.namedImportEmitsADeclaredModule()
   local text, warnings = importc.import(HERE .. "/fixtures/mini.h", {
      module = "native.mini",
   })
   assert(text, "named import failed: " .. table.concat(warnings or {}, "; "))
   assertContains(text, "module native.mini")
   assertContains(text, "export = { ")
   assert(not text:find("return { ", 1, true), "a declared binding must not return a second module table")
   local result = parser.parse(text, "native/mini.nupp")
   assert(#result.errors == 0, "declared import output must parse")
end

function M.inspectingAHeaderOutsideEveryRootNeedsNoModuleName()
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/project'") == 0)
   local header = assert(io.open(dir .. "/mini-2.h", "wb"))
   header:write(readFile(HERE .. "/fixtures/mini.h"))
   header:close()
   local output, ok = runCli(dir .. "/project", "--inspect --json ../mini-2.h")
   assert(ok, "an inspection derives its module from the header: " .. output)
   assertContains(output, '"ok":true')
   local refused, written = runCli(dir .. "/project", "-o ../mini-2.nupp ../mini-2.h")
   assert(not written, "a written import still needs a module beneath a root")
   assertContains(refused, "beneath the project root")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.functionPointerParamsComeFromLuaJITsModel()
   assertContains(imported(),
      "mini_each(fn: function(int32)?, n: int32)",
      "callbacks use the same parsed declaration model as cheader")
end

function M.completeDirectDeclaratorsArePreserved()
   local text, warnings = importc.import(
      HERE .. "/fixtures/complete_c_interop.h", {module = "completecinterop"})
   assert(text, "complete declarator import failed: "
      .. table.concat(warnings or {}, "; "))
   assertContains(text, "cdef struct nupp_complete_context")
   assertContains(text, "matrix: float[3][2]", "nested fixed arrays")
   assertContains(text, "callback: function(int32)?", "callback field")
   assertContains(text,
      "nupp_complete_get_callback(): function(int32)?",
      "callback result")
   assertContains(text,
      "nupp_complete_set_callbacks(callbacks: function(int32)?*?)",
      "C array parameters adjust to pointers")
   assertContains(text,
      "nupp_complete_get_row(): int32[4]*?",
      "pointer-to-array results retain their bound")

   local result = parser.parse(text, "complete_c_interop.nupp")
   assert(#result.errors == 0, "complete output must parse: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local diags = check.check(result, "complete_c_interop.nupp")
   assert(#diags == 0, "complete output must check: "
      .. (diags[1] and diags[1].msg or ""))
end

function M.staticInlineAndExplicitMacroBridgesCompileAndCall()
   local ffi = require("ffi")
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local library = dir .. (ffi.os == "OSX" and "/libbridge.dylib"
      or "/libbridge.so")
   local text, warnings, details = importc.import(
      HERE .. "/fixtures/bridge.h", {
         module = "bridge",
         lib = library,
         bridge = true,
         macros = {
            NUPP_BRIDGE_CLAMP = {
               parameters = {"int32", "int32", "int32"},
               result = "int32",
            },
            NUPP_BRIDGE_IGNORE = {
               parameters = {"int32"},
            },
         },
      })
   assert(text, "bridge import failed: "
      .. table.concat(warnings or {}, "; "))
   assert(details and details.bridgeSource, "bridge C was not emitted")
   assertEq(details.bridged, 4, "two inlines and two macro bridges")
   assertContains(text, "local nupp_bridge_scale = __nupp_bridge_")
   assertContains(text, "local NUPP_BRIDGE_CLAMP = __nupp_bridge_")
   assertContains(text, "local NUPP_BRIDGE_IGNORE = __nupp_bridge_",
      "void-result macro bridge")
   assertContains(text, "cdef function nupp_bridge_exported(value: int32): int32",
      "an inline body does not consume the declaration after it")

   local source = dir .. "/bridge.c"
   local handle = assert(io.open(source, "wb"))
   handle:write(details.bridgeSource)
   handle:close()
   local command = ffi.os == "OSX"
      and ("cc -dynamiclib -I. -o '%s' '%s'"):format(library, source)
      or ("cc -shared -fPIC -I. -o '%s' '%s'"):format(library, source)
   assert(os.execute(command) == 0, "generated bridge C must compile")

   local symbols = {}
   for _, disposition in ipairs(details.dispositions) do
      if disposition.symbol then symbols[disposition.name] = disposition.symbol end
   end
   ffi.cdef(("int32_t %s(int32_t); int32_t %s(int32_t, int32_t, int32_t);")
      :format(symbols.nupp_bridge_scale, symbols.NUPP_BRIDGE_CLAMP))
   local native = ffi.load(library)
   assertEq(native[symbols.nupp_bridge_scale](7), 21)
   assertEq(native[symbols.NUPP_BRIDGE_CLAMP](20, 2, 9), 9)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.headerOnlyFunctionsHaveAnExplicitSkippedDisposition()
   local text, warnings, details = importc.import(
      HERE .. "/fixtures/bridge.h", {module = "bridge"})
   assert(text, "direct inspection import succeeds")
   assertContains(text, "static inline needs --bridge-out")
   assert(#warnings == 2, "each inline explains the required bridge")
   assertEq(details.skipped, 2)
   local bridgeRequired = 0
   for _, disposition in ipairs(details.dispositions) do
      if disposition.reason == "bridge-required" then
         bridgeRequired = bridgeRequired + 1
      end
   end
   assertEq(bridgeRequired, 2)
end

function M.macroConstants()
   local text = imported()
   assertContains(text, "local MINI_MAX: number = 64")
   assertContains(text, "local MINI_FLAG: number = 8",
      "a shift is evaluated as C evaluates it")
   assertContains(text, 'local MINI_NAME: string = "mini"')
   assert(not text:find("local MINI_SKIP", 1, true),
      "unevaluable macro must not be emitted")
   assertContains(text, "-- import-c: skipped macro MINI_SKIP",
      "and says so where it would have been")
end

local function scratchHeader(name, text)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local handle = assert(io.open(dir .. "/" .. name, "wb"))
   handle:write(text)
   handle:close()
   return dir .. "/" .. name, dir
end

function M.aMacroAfterAnEmptyMacroSurvives()
   -- cc -dM prints an include guard as `#define GUARD_H` and a newline, and
   -- the value of that line ends there.
   local path, dir = scratchHeader("guard.h", table.concat({
      "#ifndef NUPP_GUARD_H",
      "#define NUPP_GUARD_H",
      "#define NUPP_GUARD_VERSION 3",
      "#define NUPP_GUARD_LIMIT 64",
      "#endif",
   }, "\n") .. "\n")
   local text = assert(importc.import(path, {module = "guard"}))
   os.execute("rm -rf '" .. dir .. "'")
   assertContains(text, "local NUPP_GUARD_VERSION: number = 3")
   assertContains(text, "local NUPP_GUARD_LIMIT: number = 64")
   assert(not text:find("NUPP_GUARD_H", 1, true), "an empty macro is not a constant:\n" .. text)
end

function M.macroValuesFollowCSemantics()
   local path, dir = scratchHeader("cvalues.h", table.concat({
      "#define CV_OCTAL 0644",
      "#define CV_HALF (7 / 2)",
      "#define CV_NEG_MOD (-7 % 3)",
      "#define CV_SCALE 1.5f",
      "#define CV_TENTH 0.1f",
      "#define CV_WRAP (0u - 1)",
      "#define CV_MIXED (-1 < 0u)",
      "#define CV_MASK (0xF0 ^ 0x0F)",
      "#define CV_SUM 1 + 2",
      "#define CV_TIMES (CV_SUM * 3)",
      "#define CV_CAST ((uint8_t)300)",
      "#define CV_CHAR 'A'",
      "#define CV_TEXT \"a\\101\" \"b\"",
      "#define CV_HEXLIKE (a + 1)",
      "#define CV_BIG 0xFFFFFFFFFFFFFFFFULL",
      "#define CV_WIDE 0x100000000",
      "#define CV_ZERO_DIV (1 / 0)",
   }, "\n") .. "\n")
   local text = assert(importc.import(path, {module = "cvalues"}))
   os.execute("rm -rf '" .. dir .. "'")
   assertContains(text, "local CV_OCTAL: number = 420")
   assertContains(text, "local CV_HALF: number = 3")
   assertContains(text, "local CV_NEG_MOD: number = -1")
   assertContains(text, "local CV_SCALE: number = 1.5")
   assertContains(text, "local CV_TENTH: number = 0.10000000149011612", "a float constant is a float")
   assertContains(text, "local CV_WRAP: number = 4294967295")
   assertContains(text, "local CV_MIXED: number = 0", "-1 converts to unsigned first")
   assertContains(text, "local CV_MASK: number = 255")
   assertContains(text, "local CV_TIMES: number = 7", "macros substitute as tokens")
   assertContains(text, "local CV_CAST: number = 44")
   assertContains(text, "local CV_CHAR: number = 65")
   assertContains(text, 'local CV_TEXT: string = "aAb"', "C escapes are octal")
   assertContains(text, "local CV_WIDE: number = 4294967296", "a literal wider than 32 bits keeps every bit")
   for _, name in ipairs({"CV_HEXLIKE", "CV_BIG", "CV_ZERO_DIV"}) do
      assert(not text:find("local " .. name, 1, true), name .. " must not be emitted:\n" .. text)
      assertContains(text, "-- import-c: skipped macro " .. name)
   end
   local result = parser.parse(text, "cvalues.nupp")
   assert(#result.errors == 0, "generated constants parse: " .. (result.errors[1] and result.errors[1].msg or ""))
end

function M.theBridgeWrapsOnlyWhatThisPlatformCompiles()
   if os.execute("cc --version >/dev/null 2>&1") ~= 0 then
      return require("assert").skip("cc is unavailable")
   end
   local path, dir = scratchHeader("vec.h", table.concat({
      "#ifndef NUPP_VEC_H",
      "#define NUPP_VEC_H",
      "#include <stdint.h>",
      "typedef int32_t vec2_t;",
      "static inline vec2_t vec2(vec2_t x) { return x * 2; }",
      "#if 0",
      "static inline int32_t vec_disabled(int32_t x) { return x; }",
      "#endif",
      "#ifdef NUPP_VEC_NEVER_DEFINED",
      "static inline int32_t vec_elsewhere(int32_t x) { return x; }",
      "#endif",
      "#endif",
   }, "\n") .. "\n")
   local text, warnings, details = importc.import(path, {module = "vec", bridge = true, bridgeInclude = "vec.h"})
   assert(text, table.concat(warnings or {}, "; "))
   assertEq(details.bridged, 1, "only vec2 is compiled on this platform")
   assert(not details.bridgeSource:find("vec_disabled", 1, true), details.bridgeSource)
   assert(not details.bridgeSource:find("vec_elsewhere", 1, true), details.bridgeSource)
   assertContains(details.bridgeSource, "(vec2_t x) {", "the parameter type keeps its name")
   local source = dir .. "/bridge.c"
   local handle = assert(io.open(source, "wb"))
   handle:write(details.bridgeSource)
   handle:close()
   local compiled = os.execute(("cc -fsyntax-only -I'%s' '%s'"):format(dir, source)) == 0
   os.execute("rm -rf '" .. dir .. "'")
   assert(compiled, "the generated bridge compiles:\n" .. details.bridgeSource)
end

function M.typedefsResolveThroughTheTranslationUnit()
   -- mini.h has no typedefs of its own; this exercises the resolver on a
   -- header whose vocabulary comes from elsewhere (size_t via stddef.h)
   assertContains(imported(), "mini_len(s: cstring?): uint64",
      "size_t resolved to a base type")
end

function M.anIncludedHeaderWithTheSameBasenameStaysOut()
   local text, warnings = importc.import(HERE .. "/fixtures/target.h", {module = "target"})
   assert(text, "same-name import failed: "
      .. table.concat(warnings or {}, "; "))
   assertContains(text, "cdef function requested_target()")
   assert(not text:find("included_same_name", 1, true),
      "an included file with the target's basename leaked into the import:\n"
         .. text)
end

function M.constBytePointersBecomeCstring()
   -- const char*/unsigned char* take a Lua string directly in LuaJIT
   assertContains(imported(), "mini_len(s: cstring?)")
   assertContains(imported(), "mini_name(): cstring?")
end

function M.libraryClauseIsEmitted()
   local text = importc.import(HERE .. "/fixtures/mini.h", {module = "mini", lib = "mini"})
   assert(text:find('from "mini"', 1, true),
      "every function carries the library clause:\n" .. text:sub(1, 400))
   local parser = require("nupp.compiler.syntax.parser")
   local result = parser.parse(text, "mini.nupp")
   assert(#result.errors == 0, "output with library clauses parses")
end

local enumsText -- shared across cases (import once)

local function enumsImported()
   if not enumsText then
      local text, warnings = importc.import(HERE .. "/fixtures/enums.h", {module = "enums"})
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
   local result = parser.parse(text, "enums.nupp")
   assert(#result.errors == 0, "generated file must parse: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local diags = check.check(result, "enums.nupp")
   assert(#diags == 0, "generated file must check: "
      .. (diags[1] and diags[1].msg or ""))
end

function M.anEnumMemberIsAcceptedWhereItsFunctionWantsIt()
   -- The point of importing the members: a C enum parameter is an integer
   -- everywhere it appears, and the constant fits it without a cast.
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local f = assert(io.open(dir .. "/enums.nupp", "wb"))
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
   local text = importc.import(HERE .. "/fixtures/partial.h", {module = "partial"})
   assert(text, "a rejected declaration must not take the header with it")
   assertContains(text, "cdef function partial_add(a: int32, b: int32): int32")
   assertContains(text, "cdef function partial_scale(v: number): number")
   assertContains(text, "-- import-c: skipped declaration")
   assertContains(text, "partialHolder", "the residue names what was lost")
end

function M.skippedDeclarationsAreCountedOnTheWayOut()
   -- The count is the signal: one of four is a corner in the header, and
   -- four of four is a module not worth having.
   local _, warnings = importc.import(HERE .. "/fixtures/partial.h", {module = "partial"})
   assert(#warnings == 1, "expected one warning, got " .. #warnings)
   assertContains(warnings[1], "1 of 4 declarations skipped")
end

function M.bridgeWriteFailureDoesNotRestyleEarlierWarningsAsErrors()
   if package.config:sub(1, 1) == "\\" then
      require("assert").skip("POSIX directory permissions provide this failure seam")
   end
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/locked'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write('return {include = {"."}}\n')
   manifest:close()
   local header = assert(io.open(dir .. "/mixed.h", "wb"))
   header:write(readFile(HERE .. "/fixtures/partial.h"))
   header:write([[
static inline int nupp_inline_identity(int value) { return value; }
]])
   header:close()
   assert(os.execute("chmod 555 '" .. dir .. "/locked'") == 0)

   local output, ok = runCli(dir,
      "-o mixed.nupp --bridge-out locked/bridge.c mixed.h")
   assert(not ok, "an unwritable bridge destination fails the import")
   local warning = "declarations skipped"
   local _, count = output:gsub(warning, "")
   assert(count == 1,
      "the import warning is printed once rather than replayed as an error: " .. output)
   assert(output:find("nupp: warning:", 1, true),
      "the original warning keeps warning severity: " .. output)
   assert(os.execute("chmod 755 '" .. dir .. "/locked'") == 0)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.typedefsAreDeclaredInTheOrderCCanReadThem()
   -- chain_base.h reaches chain_size_t through names that sort before the
   -- ones they are built from, which is how Darwin spells its own.
   local text, warnings = importc.import(HERE .. "/fixtures/chain.h", {module = "chain"})
   assert(text, "chain import failed: "
      .. table.concat(warnings or {}, "; "))
   assertContains(text, "chain_len(s: cstring?): uint64",
      "the chain resolved to its base type")
end

local layoutImport -- shared across cases (import once)

local function layoutImported()
   if not layoutImport then
      local text, warnings, details = importc.import(HERE .. "/fixtures/layout.h", {module = "layout"})
      assert(text, "layout import failed: " .. table.concat(warnings or {}, "; "))
      layoutImport = {text = text, warnings = warnings, details = details}
   end
   return layoutImport
end

function M.aStructTheRenderingCannotLayOutIsRefusedWithItsLine()
   local imported = layoutImported()
   local byName = {}
   for _, disposition in ipairs(imported.details.dispositions) do
      byName[disposition.name] = disposition
   end
   local refused = {
      layout_tagged = {"anonymous-member", 10},
      layout_bits = {"unnamed-member", 20},
      layout_wire = {"layout-mismatch", 29},
      layout_aligned = {"layout-mismatch", 34},
      layout_typedef_aligned = {"layout-mismatch", 41},
      layout_pragma_packed = {"pragma-pack", 47},
      layout_holds_vector = {"unsupported-field-type", 56},
      layout_flags = {"unsupported-field-type", 65},
      layout_vector_first = {"unsupported-c-type", 60},
      layout_complex_make = {"unsupported-c-type", 61},
      layout_complex_real = {"unsupported-c-type", 62},
   }
   for name, want in pairs(refused) do
      local disposition = byName[name]
      assert(disposition, name .. " has no disposition")
      assertEq(disposition.kind, "skipped", name)
      assertEq(disposition.reason, want[1], name .. " reason")
      assertEq(disposition.line, want[2], name .. " line")
      assert(not imported.text:find("cdef struct " .. name .. "\n", 1, true)
         and not imported.text:find("cdef function " .. name .. "(", 1, true),
         name .. " must not be emitted:\n" .. imported.text)
   end
   for _, name in ipairs({"layout_inner", "layout_mixed", "layout_value", "layout_opaque"}) do
      assertEq(byName[name] and byName[name].kind, "type-only", name)
   end
   assertContains(imported.text, "skipped struct layout_tagged at layout.h:10",
      "the comment says where the struct is")
   local warned = table.concat(imported.warnings, "\n")
   assertContains(warned, "layout.h:29: skipped struct layout_wire",
      "a layout refusal is a warning on the way out")
end

function M.anIncompleteStructIsMarkedAsAHandle()
   local text = layoutImported().text
   assertContains(text, "-- import-c: layout_opaque is incomplete in C")
   assertContains(text, "cdef function layout_opaque_new(): layout_opaque*?")
end

-- The structs an import emits, laid out by LuaJIT from the generated module and by
-- the C compiler from the header, must be the same bytes.
function M.importedLayoutsMatchWhatTheCCompilerLaysOut()
   if os.execute("cc --version >/dev/null 2>&1") ~= 0 then
      return require("assert").skip("cc is unavailable")
   end
   local ffi = require("ffi")
   local gen = require("nupp.compiler.lua.gen")
   local specs = {
      {c = "struct layout_inner", name = "layout_inner", fields = {"a", "b"}},
      {c = "layout_mixed", name = "layout_mixed",
         fields = {"flag", "inner", "row", "matrix", "id", "callback", "pair"}},
      {c = "union layout_value", name = "layout_value", fields = {"i", "d", "bytes"}},
   }

   -- The header's own tags are already in this process's registry, so the emitted
   -- declarations are renamed to lay themselves out afresh.
   local blocks, exported, open = {}, {}, nil
   for line in layoutImported().text:gmatch("([^\n]*)\n") do
      if line:match("^cdef %a+ layout_[%w_]+$") then
         open = {line}
      elseif open then
         open[#open + 1] = line
         if line == "end" then
            blocks[#blocks + 1] = (table.concat(open, "\n"):gsub("layout_", "layoutcc_"))
            open = nil
         end
      end
   end
   for _, spec in ipairs(specs) do
      local renamed = spec.name:gsub("layout_", "layoutcc_")
      exported[#exported + 1] = renamed .. " = " .. renamed
   end
   local source = table.concat(blocks, "\n") .. "\nreturn { " .. table.concat(exported, ", ") .. " }\n"
   local result = parser.parse(source, "layoutcc.g.nupp")
   assert(#result.errors == 0, "renamed declarations parse: "
      .. (result.errors[1] and result.errors[1].msg or "") .. "\n" .. source)
   local diags = check.check(result, "layoutcc.g.nupp")
   assert(#diags == 0, "renamed declarations check: " .. (diags[1] and diags[1].msg or ""))
   local code = gen.generate(result, "layoutcc")
   local types = assert(loadstring(code, "@layoutcc"))()

   local lines = {}
   for _, spec in ipairs(specs) do
      local ct = assert(types[(spec.name:gsub("layout_", "layoutcc_"))], spec.name)
      lines[#lines + 1] = ("%s size %d align %d"):format(spec.name, ffi.sizeof(ct), ffi.alignof(ct))
      for _, field in ipairs(spec.fields) do
         lines[#lines + 1] = ("%s.%s %d"):format(spec.name, field, ffi.offsetof(ct, field))
      end
   end
   local mixed = ffi.new(types.layoutcc_mixed)
   mixed.mode = 5
   mixed.level = 17
   local bytes = ffi.cast("uint8_t *", mixed)
   local dump = {}
   for index = 0, ffi.sizeof(mixed) - 1 do
      dump[#dump + 1] = ("%02x"):format(bytes[index])
   end
   lines[#lines + 1] = "bits " .. table.concat(dump)
   local luajit = table.concat(lines, "\n") .. "\n"

   local program = {
      "#include <stddef.h>",
      "#include <stdio.h>",
      "#include <string.h>",
      '#include "layout.h"',
      "int main(void) {",
   }
   for _, spec in ipairs(specs) do
      program[#program + 1] = ('printf("%s size %%d align %%d\\n", (int)sizeof(%s), (int)_Alignof(%s));')
         :format(spec.name, spec.c, spec.c)
      for _, field in ipairs(spec.fields) do
         program[#program + 1] = ('printf("%s.%s %%d\\n", (int)offsetof(%s, %s));')
            :format(spec.name, field, spec.c, field)
      end
   end
   program[#program + 1] = "layout_mixed m; memset(&m, 0, sizeof m); m.mode = 5; m.level = 17;"
   program[#program + 1] = 'printf("bits "); for (size_t i = 0; i < sizeof m; i++) '
      .. 'printf("%02x", ((unsigned char *)&m)[i]); printf("\\n");'
   program[#program + 1] = "return 0; }"

   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local handle = assert(io.open(dir .. "/layout.c", "wb"))
   handle:write(table.concat(program, "\n"), "\n")
   handle:close()
   assert(os.execute(("cc -I'%s/fixtures' -o '%s/layout' '%s/layout.c'"):format(HERE, dir, dir)) == 0,
      "the layout probe compiles")
   local pipe = assert(io.popen("'" .. dir .. "/layout'"))
   local compiled = pipe:read("*a")
   pipe:close()
   os.execute("rm -rf '" .. dir .. "'")
   assertEq(luajit, compiled, "LuaJIT's layout of the imported declarations")
end

function M.outputParsesAndChecksCleanly()
   local text = imported()
   local result = parser.parse(text, "mini.nupp")
   assert(#result.errors == 0, "generated file must parse: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local diags = check.check(result, "mini.nupp")
   assert(#diags == 0, "generated file must check: "
      .. (diags[1] and diags[1].msg or ""))
end

function M.consumerTypechecksAgainstImport()
   -- write the generated file where the module resolver will find it
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local f = assert(io.open(dir .. "/mini.nupp", "wb"))
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
