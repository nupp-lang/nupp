-- unused-binding: a `local` this file introduces that nothing reads. The
-- interesting half is what it declines to say -- a parameter, a loop variable,
-- an `_`, an owned value with a rule of its own -- since a lint that reported
-- those would be one a project learned to turn off.

local parser = require("compiler.parser")
local check = require("compiler.check")
local envMod = require("compiler.env")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- Every diagnostic the source produces, with the lint left at its default. This
-- file asks for the real checker rather than the tests' fragment wrapper, which
-- turns this lint off for everything that is not about it.
local function diagnostics(src, config)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   return check.check(result, "test.g.nupp", envMod.new("."), config or {})
end

local function lint(src, config)
   local found = {}
   for _, diag in ipairs(diagnostics(src, config)) do
      if diag.code == "NUPP2507" then found[#found + 1] = diag end
   end
   return found
end

local function assertFlagged(src, label)
   local found = lint(src)
   assertEq(#found, 1, (label or "expected one report") .. "\n" .. src)
   assertEq(found[1].lint, "unused-binding", "lint name")
   return found[1]
end

local function assertQuiet(src, label)
   local found = lint(src)
   if #found ~= 0 then
      error(("%s: reported at line %d -- %s\n%s"):format(
         label or "expected no report", found[1].line, found[1].msg, src), 2)
   end
end

local M = {}

function M.flagsALocalNothingReads()
   local at = assertFlagged([[
local function shout(text: string): string
   local prefix = "> "
   return text .. "!"
end

return shout
]])
   assertEq(at.line, 2, "reported at the binding")
   assertEq(at.col, 10, "and at the name, not the statement")
   assertEq(at.severity, "warning", "suspicious lints warn by default")
   assertEq(at.msg, "nothing uses prefix")
end

-- The other half of missing-require: that lint says a module name is used
-- without being required, this one says a require binds a name nothing wants.
function M.aRequireNothingUsesNamesItsModule()
   local at = assertFlagged([[
local strutil = require("strutil")

return 1
]])
   assertEq(at.msg,
      'nothing uses strutil, so requiring "strutil" does nothing here')
   assertEq(at.help, "delete the require", "the help says what to delete")
end

function M.flagsALocalFunctionNothingCalls()
   local at = assertFlagged([[
local function helper(): number
   return 1
end

return 2
]])
   assertEq(at.msg, "nothing uses helper")
   assertEq(at.help, "delete it, or return it from the module")
end

-- A use written below the declaration is still a use, which is why the
-- judgement waits for the end of the file rather than for the end of the scope
-- the binding is in.
function M.aUseBelowTheDeclarationCounts()
   assertQuiet([[
local prefix = "> "

local function shout(text: string): string
   return prefix .. text
end

return shout
]], "the reader is written later in the file")
end

function M.readingThroughATypeAnnotationIsAUse()
   assertQuiet([[
local T = require("compiler.types")

local function widen(t: T.Type): T.Type
   return t
end

return widen
]], "a require reached only for the types it exports")
end

function M.anUnderscoreSaysTheValueIsNotWanted()
   assertQuiet([[
local _unused = 1
local _ = 2

return 3
]], "a name beginning with _ is deliberate")
end

function M.parametersAndLoopVariablesAreNotJudged()
   assertQuiet([[
local function handle(event: string, ignored: string): string
   for index = 1, 3 do
      print(event)
   end
   for key, value in pairs({}) do
      print(key)
   end
   return event
end

return handle
]], "a signature and an iterator bind these, not their author")
end

-- Writing resolves the name the same way reading does, so it counts. Saying
-- otherwise is a flow-sensitive question this lint does not ask.
function M.aWriteCountsAsARead()
   assertQuiet([[
local count = 1
count = 2

return 3
]], "assigned and never read afterwards")
end

-- An owned value that goes unread already has a rule with something to say
-- about it, and two reports about one binding is one too many.
function M.anOwnedValueKeepsItsOwnDiagnostic()
   local codes = {}
   for _, diag in ipairs(diagnostics([[
local record Handle
   name: string
end

local function close(value: Handle)
   print(value.name)
end

@owned(close)
local function open(name: string): Handle
   return new Handle {name = name}
end

local function work()
   local handle = open("a")
end

return work
]])) do
      codes[#codes + 1] = diag.code
   end
   assertEq(table.concat(codes, " "), "NUPP2603",
      "the ownership rule reports, and this lint stays quiet")
end

function M.aDeclarationFileDeclaresWhatLivesElsewhere()
   local result = parser.parse("local helper: number\n", "test.d.nupp")
   local found = {}
   for _, diag in ipairs(check.check(result, "iface.d.nupp",
      envMod.new("."), {})) do
      if diag.code == "NUPP2507" then found[#found + 1] = diag end
   end
   assertEq(#found, 0, "nothing in a declaration file has a reader here")
end

function M.anAllowSilencesIt()
   assertQuiet([[
@allow("unused-binding")
local prefix = "> "

return 1
]], "the statement disagreed with the judgement")
   assertQuiet([[
@allow("NUPP2507")
local prefix = "> "

return 1
]], "and by code, which means the same lint")
end

function M.aProjectMovesItsLevel()
   assertEq(#lint("local prefix = 1\nreturn 2\n",
      {lints = {["unused-binding"] = "off"}}), 0, "off is not reported")
   local raised = lint("local prefix = 1\nreturn 2\n",
      {lints = {["unused-binding"] = "error"}})
   assertEq(raised[1] and raised[1].severity, "error", "raised by name")
   assertEq(#lint("local prefix = 1\nreturn 2\n",
      {lints = {suspicious = "off"}}), 0, "and by category")
end

function M.anFfiIntrinsicCountsAsUsingTheRequire()
   -- The intrinsic path recognizes `ffi.new` by the name it was written with
   -- rather than by resolving it, which skips the one place a read is recorded.
   -- The binding looked unread, and codegen emits it, so taking the advice left
   -- the program indexing a nil global -- while still checking clean.
   assertQuiet([[
const ffi = require("ffi")

local M = {}

function M.make(n: integer): cdata
    return ffi.new("double[?]", n)
end

return M
]], "ffi.new is a use of the ffi binding")
end

function M.otherFfiEntryPointsCountToo()
   assertQuiet([[
const ffi = require("ffi")

local M = {}

function M.size(): integer
    return ffi.sizeof("double")
end

return M
]], "ffi.sizeof is a use as well")
end

return M
