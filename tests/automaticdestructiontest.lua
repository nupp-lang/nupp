local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function checked(source)
   local result = parser.parse(source, "automatic-destruction-test.g.nupp")
   assertEq(#result.errors, 0,
      result.errors[1] and result.errors[1].msg or "syntax")
   local diags = check.check(result, "automatic-destruction-test.g.nupp", env)
   return result, diags
end

local function codes(source)
   local _, diags = checked(source)
   local out = {}
   for _, diag in ipairs(diags) do out[#out + 1] = diag.code end
   return table.concat(out, " ")
end

local function compile(source)
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "automatic-destruction-test")
   assertEq(#genDiags, 0, genDiags[1] and genDiags[1].msg or "generate")
   local chunk, err = loadstring(code, "@automatic-destruction-test")
   assert(chunk, tostring(err) .. "\n" .. code)
   return chunk, code
end

local PRELUDE = table.concat({
   "local calls = ''",
   "local record Resource",
   "   name: string",
   "end",
   "local function close_resource(value: Resource)",
   "   calls = calls .. value.name",
   "end",
   "local function open_resource(name: string): Owned<Resource, close_resource>",
   "   return new Resource(name = name)",
   "end",
}, "\n")

local M = {}

function M.withIsOnlyAnOrdinaryIdentifierNow()
   local ordinary = parser.parse(
      "local with = function(value) return value end\nreturn with(1)",
      "automatic-destruction-test.g.nupp")
   assertEq(#ordinary.errors, 0)

   local removed = parser.parse(
      "with value = acquire() do print(value) end",
      "automatic-destruction-test.g.nupp")
   assert(#removed.errors > 0, "the removed resource-scope syntax must not parse")
end

function M.fallthroughDestroysAnOrdinaryOwner()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function run()",
      "   local value = open_resource('a')",
      "   value.name = value.name",
      "end",
      "run()",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "a")
end

function M.anEmptyNonRaisingIntervalUsesDirectCleanup()
   local chunk, code = compile(PRELUDE .. table.concat({
      "",
      "local function run()",
      "   local value = open_resource('z')",
      "end",
      "run()",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "z")
   assert(not code:find("xpcall", 1, true),
      "a proven empty interval should not install raised-exit protection:\n" .. code)
end

function M.aRaisedBodyStillDestroysTheOwner()
   local chunk, code = compile(PRELUDE .. table.concat({
      "",
      "local ok = pcall(function()",
      "   local value = open_resource('e')",
      "   error(value.name)",
      "end)",
      "return ok, calls",
   }, "\n"))
   local ok, calls = chunk()
   assertEq(ok, false)
   assertEq(calls, "e", code)
end

function M.ownersDestroyInReverseActivationOrder()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function run()",
      "   local first = open_resource('a')",
      "   local second = open_resource('b')",
      "   calls = calls .. first.name .. second.name",
      "end",
      "run()",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "abba")
end

function M.explicitDropSuppressesAutomaticCleanup()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local value = open_resource('d')",
      "drop(value)",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "d")
end

function M.aMovedBindingCanBeReinitializedForAutomaticCleanup()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function run()",
      "   local value = open_resource('a')",
      "   drop(value)",
      "   value = open_resource('b')",
      "end",
      "run()",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "ab")
end

function M.aTakesCallReceivesResponsibilityExactlyOnce()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function consume(takes value: Resource)",
      "   unsafe do",
      "      local raw = intoRaw(value)",
      "      calls = calls .. raw.name",
      "   end",
      "end",
      "local value = open_resource('t')",
      "consume(value)",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "t")
end

function M.untouchedTakesParametersRemainExplicitTerminals()
   assertEq(codes(PRELUDE .. table.concat({
      "",
      "local function incomplete(takes value: Resource)",
      "   print(value.name)",
      "end",
   }, "\n")), "NUPP2603")
end

function M.anOwningReturnTransfersResponsibility()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function make(): Owned<Resource, close_resource>",
      "   local value = open_resource('r')",
      "   return value",
      "end",
      "local value = make()",
      "drop(value)",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "r")
end

function M.capabilityPreservingGenericsTransferAutomaticResponsibility()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function forward<T>(value: T): T preserves value",
      "   return value",
      "end",
      "local value = open_resource('f')",
      "local moved = forward(value)",
      "drop(moved)",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "f")
end

function M.opaqueOwnersStillNeedAnExplicitTerminal()
   local source = table.concat({
      "local function begin(): Owned<table, opaque> return {} end",
      "local value = begin()",
   }, "\n")
   assertEq(codes(source), "NUPP2603")
end

function M.rawSuspensionStillCannotStrandAnAutomaticOwner()
   local source = PRELUDE .. table.concat({
      "",
      "local value = open_resource('s')",
      "coroutine.yield()",
   }, "\n")
   assertEq(codes(source), "NUPP2603")
end

function M.optionalOwnersDestroyOnlyWhenPresent()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function maybe_open(present: boolean): Owned<Resource?, close_resource>",
      "   if present then return new Resource(name = 'p') end",
      "   return nil",
      "end",
      "local function run(present: boolean)",
      "   local value = maybe_open(present)",
      "   if value then value.name = value.name end",
      "end",
      "run(false)",
      "run(true)",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "p")
end

function M.protectedCallPacksKeepAutomaticOwnershipCorrelated()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function run()",
      "   local ok, value = pcall(open_resource, 'k')",
      "   if ok then print(value.name) end",
      "end",
      "run()",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "k")
end

function M.partialAcquisitionCleansOnlySuccessfulOwners()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function fail(): Resource error('acquire') end",
      "local function failed_open(): Owned<Resource, close_resource> return fail() end",
      "local ok = pcall(function()",
      "   local first = open_resource('a')",
      "   local second = failed_open()",
      "   print(first.name, second.name)",
      "end)",
      "return ok, calls",
   }, "\n"))
   local ok, calls = chunk()
   assertEq(ok, false)
   assertEq(calls, "a")
end

function M.oneDeclarationRegistersEachSuccessfulAcquisition()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function fail(): Resource error('acquire') end",
      "local function failed_open(): Owned<Resource, close_resource> return fail() end",
      "local ok = pcall(function()",
      "   local first, second = open_resource('m'), failed_open()",
      "   print(first.name, second.name)",
      "end)",
      "return ok, calls",
   }, "\n"))
   local ok, calls = chunk()
   assertEq(ok, false)
   assertEq(calls, "m")
end

function M.partialFieldMovesAndReinitializationKeepExactObligations()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local record Bundle",
      "   first: Owned<Resource>",
      "   second: Owned<Resource>",
      "end",
      "local function run()",
      "   local bundle = new Bundle(",
      "      first = open_resource('a'),",
      "      second = open_resource('b')",
      "   )",
      "   local first = bundle.first",
      "   drop(first)",
      "   bundle.first = open_resource('c')",
      "end",
      "run()",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "abc")
end

function M.resourceSetAdoptionTransfersAutomaticResponsibility()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local resources = require('nupp.resources')",
      "do",
      "   local group = resources.set('automatic')",
      "   local value = open_resource('q')",
      "   local borrowed = group:adopt(value)",
      "   print(borrowed.name)",
      "end",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "q")
end

function M.structuredExitsRunCleanup()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function returning(): integer",
      "   local value = open_resource('r')",
      "   return #value.name",
      "end",
      "local n = returning()",
      "for i = 1, 3 do",
      "   local value = open_resource(tostring(i))",
      "   if i == 1 then continue end",
      "   break",
      "end",
      "do",
      "   local value = open_resource('g')",
      "   goto done",
      "end",
      "::done::",
      "return n, calls",
   }, "\n"))
   local n, calls = chunk()
   assertEq(n, 1)
   assertEq(calls, "r12g")
end
local CACHED_REGION = "if not __nuppT%d+ then __nuppT%d+=function%("

function M.aBodyThatOnlyCallsOutStillSharesOneRegion()
   local chunk, code = compile(PRELUDE .. table.concat({
      "",
      "local function note(text: string): nil",
      "   calls = calls .. text",
      "end",
      "for _, name in ipairs({'a', 'b', 'c'}) do",
      "   local value = open_resource(name)",
      "   note(value.name)",
      "end",
      "return calls",
   }, "\n"))
   assert(code:match(CACHED_REGION),
      "a body naming only module-level locals shares one region function")
   assertEq(chunk(), "aabbcc")
end

function M.aChunkLevelLoopVariableKeepsTheRegionPerEntry()
   local chunk, code = compile(PRELUDE .. table.concat({
      "",
      "for i = 1, 3 do",
      "   local value = open_resource('x')",
      "   calls = calls .. tostring(i)",
      "end",
      "return calls",
   }, "\n"))
   -- Outside every function and still a fresh instance each iteration, so a reused
   -- region function would read the first iteration's `i`.
   assert(not code:match(CACHED_REGION),
      "a body reading a chunk-level loop variable keeps its own region function")
   assertEq(chunk(), "1x2x3x")
end

function M.automaticLoweringPreservesSourceLineCount()
   local source = PRELUDE .. table.concat({
      "",
      "local function run()",
      "   local value = open_resource('l')",
      "   print(value.name)",
      "end",
   }, "\n")
   local _, code = compile(source)
   local _, sourceLines = source:gsub("\n", "")
   local _, codeLines = code:gsub("\n", "")
   assertEq(codeLines, sourceLines + 1,
      "generated output has the source line count plus terminal newline")
end

return M
