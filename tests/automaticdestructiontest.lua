local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local fmt = require("nupp.compiler.fmt")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local checkedRun = 0
local function checked(source)
   checkedRun = checkedRun + 1
   env.loaded = {}
   local filename = ("automatic-destruction-test-%d.g.nupp"):format(checkedRun)
   local result = parser.parse(source, filename)
   assertEq(#result.errors, 0,
      result.errors[1] and result.errors[1].msg or "syntax")
   local diags = check.check(result, filename, env)
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
   "local function close_resource(takes value: Resource): nil",
   "   calls = calls .. value.name",
   "end",
   "local function open_resource(name: string): affine(Resource, close_resource)",
   "   return new Resource(name = name)",
   "end",
}, "\n")

local M = {}

function M.withIsContextualAndScopesAnAffineOwner()
   local ordinary = parser.parse(
      "local with = function(value) return value end\nreturn with(1)",
      "automatic-destruction-test.g.nupp")
   assertEq(#ordinary.errors, 0)

   local chunk = compile(PRELUDE .. table.concat({
      "",
      "with value = open_resource('w') do",
      "   value.name = value.name",
      "end",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "w")
end

function M.aProvenNonRaisingWithUsesDirectCleanup()
   local chunk, code = compile(PRELUDE .. table.concat({
      "",
      "with value = open_resource('f') do",
      "   value.name = value.name",
      "end",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "f")
   assert(not code:find("xpcall", 1, true),
      "a proven non-raising with should call its terminal directly:\n" .. code)
end

function M.aWithThatMayRaiseKeepsProtectedCleanup()
   local chunk, code = compile(PRELUDE .. table.concat({
      "",
      "local function run()",
      "   with value = open_resource('p') do",
      "      error(value.name)",
      "   end",
      "end",
      "local ok = pcall(run)",
      "return ok, calls",
   }, "\n"))
   local ok, calls = chunk()
   assertEq(ok, false)
   assertEq(calls, "p")
   assert(code:find("xpcall", 1, true),
      "a possibly raising with must retain body protection:\n" .. code)
end

function M.aWithWhoseTerminalMayRaiseKeepsProtectedCleanup()
   local source = table.concat({
      "local record Resource",
      "   name: string",
      "end",
      "local function fail_close(takes value: Resource): nil",
      "   error(value.name)",
      "end",
      "local function open_resource(name: string): affine(Resource, fail_close)",
      "   return new Resource(name = name)",
      "end",
      "local function run()",
      "   with value = open_resource('c') do",
      "      value.name = value.name",
      "   end",
      "end",
      "return pcall(run)",
   }, "\n")
   local chunk, code = compile(source)
   assertEq(chunk(), false)
   assert(code:find("xpcall", 1, true),
      "a possibly raising terminal must retain protected cleanup:\n" .. code)
end

function M.withAcquiresLeftToRightAndDropsInReverse()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "with first = open_resource('a'), second = open_resource('b') do",
      "   calls = calls .. 'x'",
      "end",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "xba")
end

function M.withDropsOnRaisedAndReturnedExits()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function returning(): string",
      "   with value = open_resource('r') do return value.name end",
      "end",
      "local function raising()",
      "   with value = open_resource('e') do error('body') end",
      "end",
      "local result = returning()",
      "local ok = pcall(raising)",
      "return result, ok, calls",
   }, "\n"))
   local result, ok, calls = chunk()
   assertEq(result, "r")
   assertEq(ok, false)
   assertEq(calls, "re")
end

function M.withBindingCannotEscapeOrBeDroppedEarly()
   assertEq(codes(PRELUDE .. table.concat({
      "",
      "local function escape(): Resource",
      "   with value = open_resource('x') do return value end",
      "end",
   }, "\n")), "NUPP2608")

   assertEq(codes(PRELUDE .. table.concat({
      "",
      "with value = open_resource('x') do drop value end",
   }, "\n")), "NUPP2602")
end

function M.gotoCannotEnterAWithScope()
   assertEq(codes(PRELUDE .. table.concat({
      "",
      "goto inside",
      "with value = open_resource('x') do",
      "   ::inside::",
      "   print(value.name)",
      "end",
   }, "\n")), "NUPP2602")
end

function M.withFormatsWrappedBindingsIdempotently()
   local source = "with first_resource = open_resource('a very long resource "
      .. "name that forces wrapping'), second_resource = open_resource('another "
      .. "very long resource name that forces wrapping') do\n"
      .. "use(first_resource, second_resource)\nend"
   local formatted, errors = fmt.format(source, "with-test.g.nupp")
   assertEq(#errors, 0)
   assert(formatted:find("with\n    first_resource", 1, true), formatted)
   assert(formatted:find("\n    second_resource", 1, true), formatted)
   assert(formatted:find("\ndo\n", 1, true), formatted)
   local again = fmt.format(formatted, "with-test.g.nupp")
   assertEq(again, formatted)
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
      "      local raw = unsafe release value",
      "      calls = calls .. raw.name",
      "   end",
      "end",
      "local value = open_resource('t')",
      "consume(value)",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "t")
end

function M.aTakesBoundaryMayItselfBeTheTerminal()
   assertEq(codes(PRELUDE .. table.concat({
      "",
      "local function incomplete(takes value: Resource)",
      "   print(value.name)",
      "end",
   }, "\n")), "")
end

function M.anOwningReturnTransfersResponsibility()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function make(): affine(Resource, close_resource)",
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
      "local function forward<T>(takes value: T): T preserves value",
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
      "local function begin(): affine(table) return {} end",
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
      "local function maybe_open(present: boolean): affine(Resource?, close_resource)",
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
      "local function failed_open(): affine(Resource, close_resource) return fail() end",
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
      "local function failed_open(): affine(Resource, close_resource) return fail() end",
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
      "   first: affine(Resource, close_resource)",
      "   second: affine(Resource, close_resource)",
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

function M.managedGroupAdoptionTransfersAutomaticResponsibility()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local managed = require('nupp.managed')",
      "do",
      "   local group = managed.group()",
      "   local value = open_resource('q')",
      "   local handle = group:adopt(nupp.manage(value))",
      "   local name = handle:with(function(borrows item) return item.name end)",
      "   print(name)",
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

function M.aChunkLevelLoopVariableTravelsThroughARegionFrame()
   local chunk, code = compile(PRELUDE .. table.concat({
      "",
      "for i = 1, 3 do",
      "   local value = open_resource('x')",
      "   calls = calls .. tostring(i)",
      "end",
      "return calls",
   }, "\n"))
   assert(code:match(CACHED_REGION),
      "a body reading a chunk-level loop variable shares its framed region function")
   assertEq(chunk(), "1x2x3x")
end

function M.aFunctionLocalWriteUsesOneRegionPerInvocation()
   local chunk, code = compile(PRELUDE .. table.concat({
      "",
      "local function count(limit: integer): integer",
      "   local total: integer = 0",
      "   for i = 1, limit do",
      "      local value = open_resource('x')",
      "      total = total + #value.name",
      "   end",
      "   return total",
      "end",
      "local first = count(3)",
      "local second = count(2)",
      "return first, second, calls",
   }, "\n"))
   local first, second, calls = chunk()
   assertEq(first, 3)
   assertEq(second, 2)
   assertEq(calls, "xxxxx")
   assert(code:match("local __nuppT%d+;"),
      "a capturing region reserves one cache for the function invocation")
end

function M.recursiveInvocationsDoNotShareRegionUpvalues()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function descend(depth: integer): number",
      "   local total: number = depth",
      "   for once = 1, 1 do",
      "      local value = open_resource('x')",
      "      if depth > 0 then total = total + descend(depth - 1) end",
      "   end",
      "   return total",
      "end",
      "return descend(3), calls",
   }, "\n"))
   local total, calls = chunk()
   assertEq(total, 6)
   assertEq(calls, "xxxx")
end

function M.aLoopLocalWriteTravelsThroughARegionFrame()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local totals = ''",
      "for outer = 1, 3 do",
      "   local total: integer = 0",
      "   for inner = 1, outer do",
      "      local value = open_resource('x')",
      "      total = total + inner",
      "   end",
      "   totals = totals .. tostring(total)",
      "end",
      "return totals, calls",
   }, "\n"))
   local totals, calls = chunk()
   assertEq(totals, "136")
   assertEq(calls, "xxxxxx")
end

function M.frameWritebackPrecedesStructuredExitDispatch()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local totals = ''",
      "for outer = 1, 3 do",
      "   local total: integer = 0",
      "   for inner = 1, 3 do",
      "      local value = open_resource('x')",
      "      total = total + inner",
      "      if inner == 2 then break end",
      "   end",
      "   totals = totals .. tostring(total)",
      "end",
      "return totals, calls",
   }, "\n"))
   local totals, calls = chunk()
   assertEq(totals, "333")
   assertEq(calls, "xxxxxx")
end

function M.automaticLoweringEmitsLoadableCleanupRegions()
   local source = PRELUDE .. table.concat({
      "",
      "local function run()",
      "   local value = open_resource('l')",
      "   print(value.name)",
      "end",
   }, "\n")
   local _, code = compile(source)
   assert(loadstring(code, "@automatic-cleanup-lowering"), code)
end

function M.aNestedFunctionReturnsValuesThroughItsOwnRegion()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local outer = open_resource('o')",
      "local function inner(): (string, integer)",
      "   local value = open_resource('i')",
      "   return value.name, 2",
      "end",
      "local name, count = inner()",
      "return name, count, calls",
   }, "\n"))
   local name, count, calls = chunk()
   assertEq(name, "i")
   assertEq(count, 2)
   assertEq(calls, "i")
end

function M.closeableFieldsCloseInReverseOrder()
   local chunk = compile(table.concat({
      "local calls = ''",
      "local record Resource is nupp.Closeable",
      "   name: string",
      "   function flush(exclusive self): nil end",
      "   function close(takes self): nil calls = calls .. self.name end",
      "end",
      "local record Bundle",
      "   first: Resource",
      "   second: Resource",
      "end",
      "do",
      "   local bundle = new Bundle(",
      "      first = new Resource(name = 'a'),",
      "      second = new Resource(name = 'b')",
      "   )",
      "end",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "ba")
end

function M.manualCloseDischargesAnInherentObligationOnce()
   local chunk = compile(table.concat({
      "local calls = 0",
      "local record Resource is nupp.Closeable",
      "   function flush(exclusive self): nil end",
      "   function close(takes self): nil calls = calls + 1 end",
      "end",
      "do",
      "   local value = new Resource()",
      "   value:close()",
      "end",
      "return calls",
   }, "\n"))
   assertEq(chunk(), 1)
end

return M
