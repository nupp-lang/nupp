local parser = require("nupp.parser")
local check = require("nupp.check")
local gen = require("nupp.gen")
local fmt = require("nupp.fmt")
local envMod = require("nupp.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function checked(source)
   local result = parser.parse(source, "with-test")
   assertEq(#result.errors, 0,
      result.errors[1] and result.errors[1].msg or "syntax")
   local diags = check.check(result, "with-test", env)
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
   local code, genDiags = gen.generate(result, "with-test")
   assertEq(#genDiags, 0, genDiags[1] and genDiags[1].msg or "generate")
   local chunk, err = loadstring(code, "@with-test")
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
   "@owned(close_resource)",
   "local function open_resource(name: string): Resource",
   "   return new Resource {name = name}",
   "end",
}, "\n")

local M = {}

-- A body that resolves nothing from an enclosing scope is lowered to a region
-- with no upvalues, built once and reused. These cover both that the sharing
-- happens and that it is chosen only when it is safe: sharing a region that
-- did capture would pin every later execution to the first call's cells.

local function usesSharedRegion(code)
   return code:find("%[1%]=") ~= nil
end

function M.aNonCapturingBodyIsLoweredToASharedRegion()
   local _, code = compile(PRELUDE .. table.concat({
      "",
      "local function run()",
      "   with r = open_resource('a') do",
      "      r.name = r.name",
      "   end",
      "end",
      "run() run()",
      "return calls",
   }, "\n"))
   assert(usesSharedRegion(code), "expected a shared region:\n" .. code)
   assert(code:find("const __nuppT", 1, true), code)
   assert(code:find("const function __nuppT", 1, true), code)
   assert(code:find("do const%s+__nuppT"), code)
end

function M.aSharedRegionIsCorrectAcrossManyCalls()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function run(n: string): string",
      "   with r = open_resource(n) do",
      "      return r.name",
      "   end",
      "end",
      "local out = run('a') .. run('b') .. run('c')",
      "return out, calls",
   }, "\n"))
   local out, calls = chunk()
   assertEq(out, "abc")
   assertEq(calls, "abc")
end

function M.aSharedRegionIsReentrantUnderRecursion()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function down(n: number): number",
      "   with r = open_resource(tostring(n)) do",
      "      if n == 0 then return 0 end",
      "      return n + down(n - 1)",
      "   end",
      "end",
      "local total = down(3)",
      "return total, calls",
   }, "\n"))
   local total, calls = chunk()
   assertEq(total, 6)
   assertEq(calls, "0123")
end

function M.aSharedRegionCannotSuspendAResourceScope()
   assertEq(codes(PRELUDE .. table.concat({
      "",
      "local function task(n: string)",
      "   with r = open_resource(n) do",
      "      coroutine.yield(r.name)",
      "   end",
      "end",
      "local a = coroutine.create(task)",
      "local b = coroutine.create(task)",
      "local _, first = coroutine.resume(a, 'a')",
      "local _, second = coroutine.resume(b, 'b')",
      "local mid = calls",
      "coroutine.resume(a)",
      "coroutine.resume(b)",
      "return first, second, mid, calls",
   }, "\n")), "NUPP2603")
end

function M.aBodyReadingEnclosingStateFallsBack()
   local _, code = compile(PRELUDE .. table.concat({
      "",
      "local prefix = 'p'",
      "local function run(): string",
      "   with r = open_resource('a') do",
      "      return prefix .. r.name",
      "   end",
      "end",
      "return run()",
   }, "\n"))
   assert(not usesSharedRegion(code), "reading enclosing state must not share")
end

-- The dangerous case. If the analysis wrongly reported "no capture" here, the
-- region would be built once holding the first call's `seen`, and the second
-- call's write would land on a dead cell.
function M.aBodyWritingEnclosingStateFallsBackAndStaysCorrect()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function run(n: string): string",
      "   local seen = ''",
      "   with r = open_resource(n) do",
      "      seen = seen .. r.name",
      "   end",
      "   return seen",
      "end",
      "return run('a') .. run('b'), calls",
   }, "\n"))
   local out, calls = chunk()
   assertEq(out, "ab")
   assertEq(calls, "ab")
end

function M.aBodyClosingOverEnclosingStateFallsBack()
   local _, code = compile(PRELUDE .. table.concat({
      "",
      -- the only enclosing reference is inside the nested closure
      "local outer = 'x'",
      "local function run(): string",
      "   with r = open_resource('a') do",
      "      local f = function(): string return outer end",
      "      return f()",
      "   end",
      "end",
      "return run()",
   }, "\n"))
   assert(not usesSharedRegion(code),
      "closing over enclosing state must not share")
end

function M.multipleBindingsUseTheGeneralLowering()
   local _, code = compile(PRELUDE .. table.concat({
      "",
      "with a = open_resource('a'), b = open_resource('b') do",
      "   local x = a.name",
      "end",
      "return calls",
   }, "\n"))
   assert(not usesSharedRegion(code), "multiple bindings use the general form")
end

function M.distinctSitesDoNotShareACacheSlot()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function first(): string",
      "   with r = open_resource('a') do return r.name .. '1' end",
      "end",
      "local function second(): string",
      "   with r = open_resource('b') do return r.name .. '2' end",
      "end",
      "return first() .. second() .. first(), calls",
   }, "\n"))
   local out, calls = chunk()
   assertEq(out, "a1b2a1")
   assertEq(calls, "aba")
end

function M.aSharedRegionPreservesEveryExit()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "local function run(): integer, integer",
      "   with r = open_resource('r') do",
      "      return 1, 2",
      "   end",
      "end",
      "local a, b = run()",
      "for i = 1, 3 do",
      "   with v = open_resource(tostring(i)) do",
      "      if i == 1 then continue end",
      "      break",
      "   end",
      "end",
      "with g = open_resource('g') do goto done end",
      "::done::",
      "return a, b, calls",
   }, "\n"))
   local a, b, calls = chunk()
   assertEq(a, 1); assertEq(b, 2)
   assertEq(calls, "r12g")
end

function M.aSharedRegionStillAggregatesCleanupFailures()
   local chunk = compile(table.concat({
      "local calls = ''",
      "local function bad(value: table) calls = calls .. 'c'; error('close') end",
      "@owned(bad)",
      "local function open(): table return {} end",
      "local function run()",
      "   with value = open() do error('body') end",
      "end",
      "local ok, reason = pcall(run)",
      "return ok, reason, calls",
   }, "\n"))
   local ok, reason, calls = chunk()
   assertEq(ok, false)
   assert(tostring(reason):find("body", 1, true), tostring(reason))
   assertEq(calls, "c")
end

function M.withIsContextualAndLossless()
   local source = table.concat({
      "local with = function(value) return value end",
      "local value = with(1)",
      "with item: Resource = open_resource('x') do",
      "   print(item.name)",
      "end",
   }, "\n")
   local result = parser.parse(source, "with-test")
   assertEq(#result.errors, 0)
   assertEq(result.root.blocks[1].stats[2].kind, "localStmt")
   local scope = result.root.blocks[1].stats[3]
   assertEq(scope.kind, "withStmt")
   assertEq(scope.bindings[1].name.text, "item")
   assert(scope.bindings[1].type, "typed binding retained")
end

function M.arbitraryOwnersCleanInReverseOrder()
   local chunk = compile(PRELUDE .. table.concat({
      "",
      "with first = open_resource('a'), second = open_resource('b') do",
      "   calls = calls .. 'x'",
      "end",
      "return calls",
   }, "\n"))
   assertEq(chunk(), "xba")
end

function M.partialAcquisitionAndCleanupFailureAttemptEverything()
   local source = PRELUDE .. table.concat({
      "",
      "local function fail(): Resource error('acquire') end",
      "@owned(close_resource)",
      "local function failed_open(): Resource return fail() end",
      "local ok, reason = pcall(function()",
      "   with first = open_resource('a'), second = failed_open() do end",
      "end)",
      "return ok, tostring(reason), calls",
   }, "\n")
   local ok, reason, calls = compile(source)()
   assertEq(ok, false)
   assert(reason:find("acquire", 1, true), reason)
   assertEq(calls, "a")

   local cleanupSource = table.concat({
      "local calls = ''",
      "local function first(value: table) calls = calls .. '1'; error('bad') end",
      "local function second(value: table) calls = calls .. '2' end",
      "@owned(first, second)",
      "local function open(): table return {} end",
      "local ok, reason = pcall(function() with value = open() do end end)",
      "return ok, tostring(reason), calls",
   }, "\n")
   local cok, creason, cleanupCalls = compile(cleanupSource)()
   assertEq(cok, false)
   assert(creason:find("bad", 1, true), creason)
   assertEq(cleanupCalls, "12")
end

function M.bodyFailureStaysPrimaryAndCleanupFailuresAreSuppressed()
   local source = table.concat({
      "local calls = ''",
      "local function bad_close(value: table) calls = calls .. 'c'; error('close') end",
      "local function final_close(value: table) calls = calls .. 'f'; error('final') end",
      "@owned(bad_close, final_close)",
      "local function open(): table return {} end",
      "local ok, reason = pcall(function()",
      "   with value = open() do error('body') end",
      "end)",
      "return ok, reason, calls",
   }, "\n")
   local ok, reason, calls = compile(source)()
   assertEq(ok, false)
   assertEq(type(reason), "table")
   assert(tostring(reason.primary):find("body", 1, true), tostring(reason.primary))
   assertEq(#reason.suppressed, 2)
   assertEq(calls, "cf")
end

function M.returnBreakContinueAndGotoRunCleanup()
   local returning = PRELUDE .. table.concat({
      "",
      "local function run()",
      "   with value = open_resource('r') do",
      "      return 1, nil, 3",
      "   end",
      "end",
      "local a, b, c = run()",
      "return a, b, c, calls",
   }, "\n")
   local a, b, c, returnCalls = compile(returning)()
   assertEq(a, 1); assertEq(b, nil); assertEq(c, 3); assertEq(returnCalls, "r")

   local looping = PRELUDE .. table.concat({
      "",
      "for i = 1, 3 do",
      "   with value = open_resource(tostring(i)) do",
      "      if i == 1 then continue end",
      "      break",
      "   end",
      "end",
      "with value = open_resource('g') do goto done end",
      "::done::",
      "return calls",
   }, "\n")
   assertEq(compile(looping)(), "12g")
end

function M.nestedScopesPropagateReturnAfterInnerCleanup()
   local source = PRELUDE .. table.concat({
      "",
      "local function run()",
      "   with outer = open_resource('o') do",
      "      with inner = open_resource('i') do",
      "         return 'done'",
      "      end",
      "   end",
      "end",
      "return run(), calls",
   }, "\n")
   local result, calls = compile(source)()
   assertEq(result, "done")
   assertEq(calls, "io")
end

-- The container-as-owner pattern documented in ownership.md: `takes` moves
-- an element in, an `@owned` method moves one back out, and the container's
-- own cleanup closes whatever is left.
function M.owningContainersTransferElementsAcrossTheirBoundary()
   local source = PRELUDE .. table.concat({
      "",
      "local record Pool",
      "   items: {Resource}",
      "end",
      "function Pool:add(takes r: Resource)",
      "   unsafe do",
      "      self.items[#self.items + 1] = intoRaw(r)",
      "   end",
      "end",
      "@owned(close_resource)",
      "function Pool:take(): Resource",
      "   local last = #self.items",
      "   local item = self.items[last]",
      "   self.items[last] = nil",
      "   return item",
      "end",
      "local function close_pool(p: Pool)",
      "   for i = #p.items, 1, -1 do close_resource(p.items[i]) end",
      "end",
      "@owned(close_pool)",
      "local function open_pool(): Pool",
      "   return new Pool {items = {}}",
      "end",
      "local function run()",
      "   with pool = open_pool() do",
      "      pool:add(open_resource('a'))",
      "      pool:add(open_resource('b'))",
      "      local taken = pool:take()",
      "      dispose(taken)",
      "   end",
      "end",
      "run()",
      "return calls",
   }, "\n")
   assertEq(compile(source)(), "ba")
end

function M.storingAnOwnerInATableIsStillRejected()
   assertEq(codes(PRELUDE .. table.concat({
      "",
      "local kept: {Resource} = {}",
      "local function stash(takes r: Resource)",
      "   kept[#kept + 1] = r",
      "end",
   }, "\n")), "NUPP2603 NUPP2603")
end

-- The lowering calls library functions by name, so a user local of the same
-- name must not capture the call.
function M.shadowedLibraryNamesDoNotBreakAScope()
   local source = PRELUDE .. table.concat({
      "",
      "local function run()",
      "   local unpack, pcall, error = 'x', 'x', 'x'",
      "   local xpcall, select, setmetatable = 'x', 'x', 'x'",
      "   local tostring, ipairs = 'x', 'x'",
      "   with r = open_resource('s') do",
      "      return r.name, unpack",
      "   end",
      "end",
      "return run()",
   }, "\n")
   local name, shadowed = compile(source)()
   assertEq(name, "s")
   assertEq(shadowed, "x")
end

function M.bodyCanReadVarargsThroughTheProtectedRegion()
   local source = PRELUDE .. table.concat({
      "",
      "local function run(...)",
      "   with r = open_resource('v') do",
      "      return select('#', ...), r.name",
      "   end",
      "end",
      "return run('a', 'b', 'c')",
   }, "\n")
   local count, name = compile(source)()
   assertEq(count, 3)
   assertEq(name, "v")
end

function M.nestedScopesForwardVarargsToTheInnerRegion()
   local source = PRELUDE .. table.concat({
      "",
      "local function run(...)",
      "   with outer = open_resource('o') do",
      "      with inner = open_resource('i') do",
      "         return select('#', ...)",
      "      end",
      "   end",
      "end",
      "return run('a', 'b'), calls",
   }, "\n")
   local count, calls = compile(source)()
   assertEq(count, 2)
   assertEq(calls, "io")
end

function M.varargsAreOnlyForwardedWhenTheBodyReadsThem()
   local source = PRELUDE .. table.concat({
      "",
      "local function run(...)",
      "   with r = open_resource('n') do",
      "      return r.name",
      "   end",
      "end",
      "return run('a')",
   }, "\n")
   local _, code = compile(source)
   assert(not code:find("xpcall%(function%(%.%.%.%)"),
      "region should not be variadic when the body never reads `...`")
end

function M.ownershipDiagnosticsAreSpecific()
   assertEq(codes(PRELUDE .. "\nwith value = {} do end"), "NUPP2610")
   assertEq(codes(PRELUDE .. table.concat({
      "", "local value = open_resource('x')", "with active = value do end",
      "print(value)",
   }, "\n")), "NUPP2601")
   assertEq(codes(PRELUDE .. table.concat({
      "", "with value = open_resource('x') do", "   value = {}", "end",
   }, "\n")), "NUPP2613")
   assertEq(codes(PRELUDE .. table.concat({
      "", "with value = open_resource('x') do", "   return value", "end",
   }, "\n")), "NUPP2612")
   assertEq(codes(PRELUDE .. table.concat({
      "", "with value = open_resource('x') do", "   dispose(value)", "end",
   }, "\n")), "NUPP2614")
   assertEq(codes(PRELUDE .. table.concat({
      "", "with value = open_resource('x') do", "   local box = {value}", "end",
   }, "\n")), "NUPP2612")
   assertEq(codes(PRELUDE .. table.concat({
      "", "with value = open_resource('x') do",
      "   local function capture() return value.name end", "end",
   }, "\n")), "NUPP2612")
end


function M.nonFinalConsumingCleanupIsRejected()
   local source = table.concat({
      "local function release(takes value: table) end",
      "local function close(value: table) end",
      "@owned(release, close)",
      "local function open(): table return {} end",
      "with value = open() do end",
   }, "\n")
   -- The cleanup itself also fails its independent `takes` obligation;
   -- NUPP2615 is the contract error this case is exercising.
   assertEq(codes(source), "NUPP2603 NUPP2615")
end

function M.gotoCannotEnterAResourceScope()
   local source = PRELUDE .. table.concat({
      "",
      "goto inside",
      "with value = open_resource('x') do",
      "   ::inside::",
      "   print(value.name)",
      "end",
   }, "\n")
   assertEq(codes(source), "NUPP2617")
end

function M.withPreservesLineCountAndFormatsIdempotently()
   local source = PRELUDE .. table.concat({
      "", "with value = open_resource('x') do", "   print(value.name)", "end",
   }, "\n")
   local _, code = compile(source)
   local _, sourceLines = source:gsub("\n", "")
   local _, codeLines = code:gsub("\n", "")
   assertEq(codeLines, sourceLines + 1)
   local once, errors = fmt.format(source, "with-test")
   assertEq(#errors, 0)
   local twice = fmt.format(once, "with-test")
   assertEq(twice, once)

   local long = "with first_resource = open_resource('a very long resource "
      .. "name that forces wrapping'), second_resource = open_resource('another "
      .. "very long resource name that forces wrapping') do\n"
      .. "use(first_resource, second_resource)\nend"
   local wrapped, wrapErrors = fmt.format(long, "with-test")
   assertEq(#wrapErrors, 0)
   assert(wrapped:find("with\n    first_resource", 1, true), wrapped)
   assert(wrapped:find("\n    second_resource", 1, true), wrapped)
   assert(wrapped:find("\ndo\n", 1, true), wrapped)
   local wrappedAgain = fmt.format(wrapped, "with-test")
   assertEq(wrappedAgain, wrapped)
end

function M.yieldCannotSuspendWithCleanupPending()
   local source = PRELUDE .. table.concat({
      "",
      "local co = coroutine.create(function()",
      "   with value = open_resource('y') do",
      "      coroutine.yield(calls)",
      "   end",
      "   return calls",
      "end)",
      "local ok1, during = coroutine.resume(co)",
      "local ok2, after = coroutine.resume(co)",
      "return ok1, during, ok2, after",
   }, "\n")
   assertEq(codes(source), "NUPP2603")
end

return M
