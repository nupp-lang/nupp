local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function codes(source)
   env.loaded = {}
   local parsed = parser.parse(source, "test.g.nupp")
   assertEq(#parsed.errors, 0, "syntax: "
      .. (parsed.errors[1] and parsed.errors[1].msg or ""))
   local out = {}
   for j, diagnostic in ipairs(check.check(parsed, "test.g.nupp", env)) do
      out[j] = diagnostic.code
   end
   return table.concat(out, " ")
end

local function clean(source)
   assertEq(codes(source), "", "expected clean check for:\n" .. source)
end

local M = {}

function M.genericPacksPreserveHeterogeneousValues()
   clean(table.concat({
      "local function forward<A...>(...: A...): A...",
      "   return ...",
      "end",
      "local count, name, active = forward(3, 'nupp', true)",
      "local n: number = count",
      "local s: string = name",
      "local b: boolean = active",
   }, "\n"))
end

function M.callbackAdaptersInferArgumentAndResultPacks()
   clean(table.concat({
      "local function apply<A..., R...>(",
      "   f: function(A...): R..., ...: A...",
      "): R...",
      "   return f(...)",
      "end",
      "local function pair(n: number, s: string): (boolean, string)",
      "   return n > 0, s",
      "end",
      "local ok, text = apply(pair, 1, 'ready')",
      "local b: boolean = ok",
      "local s: string = text",
   }, "\n"))
end

function M.genericAliasesAcceptDelimitedPackArguments()
   clean(table.concat({
      "local type Adapter<A..., R...> = function(A...): R...",
      "local function forward<A...>(...: A...): A... return ... end",
      "local adapter: Adapter<(number, string), (number, string)> = forward",
   }, "\n"))
end

function M.nominalsAcceptAndForwardResultPacks()
   clean(table.concat({
      "local interface Source<R...>",
      "   read: function(self): R...",
      "end",
      "local record Values<R...> is Source<R...>",
      "   read: function(self): R...",
      "end",
      "local function read<R...>(source: Source<R...>): R...",
      "   return source:read()",
      "end",
      "local values: Values<(number, string)> = nil as any",
      "local count, name = read(values)",
      "local n: number = count",
      "local s: string = name",
   }, "\n"))
end

function M.nominalPackArgumentsParticipateInCompatibility()
   assertEq(codes(table.concat({
      "local interface Source<R...>",
      "   read: function(self): R...",
      "end",
      "local numbers: Source<(number, string)> = nil as any",
      "local strings: Source<(string, number)> = numbers",
   }, "\n")), "NUPP2001")
end

function M.nominalsAcceptOpenPackArguments()
   clean(table.concat({
      "local interface Source<R...>",
      "   read: function(self): R...",
      "end",
      "local source: Source<...any> = nil as any",
      "local first, second = source:read()",
      "local anything: any = first",
      "local more: any = second",
   }, "\n"))
end

function M.nominalPackPatternsInferTheCompletePack()
   clean(table.concat({
      "local interface Source<R...>",
      "   read: function(self): R...",
      "end",
      "local type Reader<T> = match T",
      "   when Source<infer R...> then function(): R...",
      "   else never end",
      "local reader: Reader<Source<(string, integer)>> =",
      "   function(): (string, integer) return 'one', 1 end",
   }, "\n"))
end

function M.packBinderPlacementAndPackPositionsAreChecked()
   assertEq(codes("local function bad<A..., T>(x: T) end"), "NUPP2121")
   assertEq(codes("local value: (number, string)"), "NUPP2121")
end

function M.luaOnlyExpandsTheFinalUnparenthesizedExpression()
   clean(table.concat({
      "local function pair(): (number, string)",
      "   return 1, 'one'",
      "end",
      "local function consume(n: number, s: string) end",
      "consume(pair())",
      "local first: number = (pair())",
      "local a, b, c = pair(), true",
      "local n: number = a",
      "local flag: boolean = b",
      "local missing: nil = c",
   }, "\n"))
end

-- An expanding expression is read for every value it produces, and the reader
-- takes them off the node. A call whose own path published no pack used to leave
-- the reader with whichever call ran last, which is one of its own arguments: the
-- inner callee's results became the outer call's.
function M.anInnerCallDoesNotSupplyTheEnclosingCallsResults()
   clean(table.concat({
      "local function want(message: string) end",
      "local function maybe(value: any): string?",
      "   return value and 'owned' or nil",
      "end",
      "local function main(value: any, name: string)",
      "   want(('%s %q'):format(maybe(value), name))",
      "   want(('%s %q'):format(name, maybe(value)))",
      "   local formatted = ('%s'):format(maybe(value))",
      "   want(formatted)",
      "end",
      "return main",
   }, "\n"))
end

-- A literal is one value of its base type, so it carries the same members. Without
-- that, `('%s'):format(x)` found no method and answered `any`, which is what let the
-- leaked pack through in the first place.
function M.aStringLiteralReachesTheStringLibrary()
   assertEq(codes(table.concat({
      "local function want(n: number) end",
      "want(('%s'):format(1))",
      "return want",
   }, "\n")), "NUPP2006")
   clean(table.concat({
      "local repeated: string = ('ab'):rep(2)",
      "local width: number = #('ab'):upper()",
      "return repeated, width",
   }, "\n"))
end

function M.expandedSurplusArgumentsKeepTheArityDiagnostic()
   assertEq(codes(table.concat({
      "local function pair(): (number, string)",
      "   return 1, 'one'",
      "end",
      "local function one(n: number) end",
      "one(pair())",
   }, "\n")), "NUPP2007")
end

function M.protectedCallsKeepCorrelatedResultArms()
   clean(table.concat({
      "local function pair(n: number): (number, string)",
      "   return n, tostring(n)",
      "end",
      "local ok, value, text = xpcall(pair,",
      "   function(_): boolean return false end, 1)",
      "if ok == true then",
      "   local n: number = value",
      "   local s: string = text",
      "else",
      "   local failure: boolean = value",
      "   local absent: nil = text",
      "end",
   }, "\n"))
end

-- A pack union survives a `function` declaration, not just the function-type
-- annotation the prelude declares pcall with. The two spell one signature, and a
-- declaration used to rebuild its result pack from the flat head a union leaves
-- empty, which replaced the union with a pack of no results: the body could return
-- nothing, and every caller read the results as any.
function M.declaredPackUnionsKeepCorrelatedResultArms()
   clean(table.concat({
      "local function run(): ((true, number, string) | (false, any))",
      "   return true, 1, 'one'",
      "end",
      "local ok, value, text = run()",
      "if ok == true then",
      "   local n: number = value",
      "   local s: string = text",
      "end",
   }, "\n"))
end

function M.declaredPackUnionsCheckTheBodyAgainstEveryArm()
   assertEq(codes(table.concat({
      "local function run(): ((true, number, string) | (false, any))",
      "   return true, 'wrong', 'one'",
      "end",
      "return run",
   }, "\n")), "NUPP2010")
end

-- Asserted as a rejection, not a clean check: while the union was being dropped the
-- results came back gradual, so every annotation fit and a `clean` here passed for
-- the wrong reason.
function M.genericWrappersPreserveTheirCallbacksResultArms()
   local wrapper = {
      "local function protect<R...>(callback: function(): R...):",
      "   ((true, R...) | (false, any))",
      "   return pcall(callback)",
      "end",
      "local function pair(): (number, string) return 1, 'one' end",
      "local ok, value, text = protect(pair)",
      "if ok == true then",
   }
   local function inArm(...)
      local lines = {}
      for j, line in ipairs(wrapper) do lines[j] = line end
      for _, line in ipairs({...}) do lines[#lines + 1] = line end
      lines[#lines + 1] = "end"
      return table.concat(lines, "\n")
   end
   clean(inArm("   local n: number = value", "   local s: string = text"))
   assertEq(codes(inArm("   local s: string = value")), "NUPP2001")
end

function M.selectTransformsPacksWithoutAny()
   clean(table.concat({
      "local text, flag = select(2, 1, 'two', true)",
      "local s: string = text",
      "local b: boolean = flag",
      "local last: boolean = select(-1, 1, 'two', true)",
      "local count: integer = select('#', 1, 'two', true)",
   }, "\n"))
   assertEq(codes("local value = select(0, 1, 2)"), "NUPP2010")
end

function M.unpackPreservesTupleAndArrayElementTypes()
   clean(table.concat({
      "local function takeTuple(tuple: {number, string, boolean})",
      "   local n, s = unpack(tuple, 1, 2)",
      "   local exactNumber: number = n",
      "   local exactString: string = s",
      "end",
      "local list: {string} = {'a', 'b'}",
      "local a, b = unpack(list)",
      "local first: string = a",
      "local second: string = b",
   }, "\n"))
end

function M.coroutineProtocolsTypeYieldResumeAndReturnValues()
   clean(table.concat({
      "local function worker(start: number): string",
      "   yields (number, string) resumes (boolean)",
      "   local again: boolean = coroutine.yield(start, 'paused')",
      "   return tostring(again)",
      "end",
      "local co: thread<(number), (boolean), (number, string), (string)> =",
      "   coroutine.create(worker)",
      "local ok, value, label = coroutine.resume(co, 1)",
      "if ok then",
      "   local result: number | string = value",
      "   local detail: string? = label",
      "end",
   }, "\n"))
end

function M.coroutineStartAndResumePacksFollowTheLocalHandlePhase()
   local declaration = table.concat({
      "local function worker(start: number): string",
      "   yields (number) resumes (boolean)",
      "   local again: boolean = coroutine.yield(start)",
      "   return tostring(again)",
      "end",
   }, "\n")
   assertEq(codes(declaration .. "\n" .. table.concat({
      "local co = coroutine.create(worker)",
      "coroutine.resume(co, true)",
   }, "\n")), "NUPP2010")
   clean(declaration .. "\n" .. table.concat({
      "local co = coroutine.create(worker)",
      "local firstOk, firstValue = coroutine.resume(co, 1)",
      "local nextOk, nextValue = coroutine.resume(co, true)",
   }, "\n"))
   assertEq(codes(declaration .. "\n" .. table.concat({
      "local co = coroutine.create(worker)",
      "coroutine.resume(co, 1)",
      "coroutine.resume(co, 2)",
   }, "\n")), "NUPP2010")
end

function M.coroutineWrapCarriesTheSameStatefulProtocol()
   local declaration = table.concat({
      "local function worker(start: number): string",
      "   yields (number) resumes (boolean)",
      "   local again: boolean = coroutine.yield(start)",
      "   return tostring(again)",
      "end",
   }, "\n")
   clean(declaration .. "\n" .. table.concat({
      "local wrapped = coroutine.wrap(worker)",
      "local yielded: number | string = wrapped(1)",
      "local returned: number | string = wrapped(true)",
   }, "\n"))
   assertEq(codes(declaration .. "\n" .. table.concat({
      "local wrapped = coroutine.wrap(worker)",
      "wrapped(true)",
   }, "\n")), "NUPP2006")
end

function M.coroutineStatusNarrowsADeadHandle()
   assertEq(codes(table.concat({
      "local function worker(start: number): string",
      "   yields (number) resumes (boolean)",
      "   local again: boolean = coroutine.yield(start)",
      "   return tostring(again)",
      "end",
      "local co = coroutine.create(worker)",
      "coroutine.resume(co, 1)",
      "local state = coroutine.status(co)",
      "if state == 'dead' then",
      "   coroutine.resume(co, true)",
      "end",
   }, "\n")), "NUPP2010")
end

function M.affinePackResultsCannotBeSilentlyDiscarded()
   local declaration = table.concat({
      "@owned(cleanup = release)",
      "cdef function acquire(): voidptr",
      "cdef function release(takes value: voidptr)",
      "local function make(): (number, owned<voidptr>)",
      "   return 1, acquire()",
      "end",
   }, "\n")
   assertEq(codes(declaration .. "\nlocal first = make()"), "NUPP2605")
   assertEq(codes(declaration .. "\nmake()"), "NUPP2605")
end

function M.protectedCallOwnersAutoDestroyOnlyInTheSuccessArm()
   local declaration = table.concat({
      "@owned(cleanup = release)",
      "cdef function acquire(): voidptr",
      "cdef function release(takes value: voidptr)",
   }, "\n")
   clean(declaration .. "\n" .. table.concat({
      "local ok, resource = pcall(acquire)",
      "if ok then",
      "   drop(resource)",
      "end",
   }, "\n"))
   assertEq(codes(declaration .. "\n" .. table.concat({
      "local ok, resource = pcall(acquire)",
      "if ok then",
      "   print(resource)",
      "end",
   }, "\n")), "")
end

function M.genericPackForwardingKeepsBorrowProvenance()
   local declaration = table.concat({
      "local struct resource",
      "   value: int32",
      "end",
      "@owned(cleanup = resource_free)",
      "cdef function resource_new(): resource*",
      "cdef function resource_free(takes value: resource*)",
      "local function borrow(borrows value: resource*):",
      "   borrowed<resource*> borrows value",
      "   return value",
      "end",
      "local function forward<A...>(...: A...): A...",
      "   return ...",
      "end",
   }, "\n")
   assertEq(codes(declaration .. "\n" .. table.concat({
      "local owner = resource_new()",
      "local view = forward(borrow(owner))",
      "resource_free(owner)",
      "print(view.value)",
   }, "\n")), "NUPP2602")
   clean(declaration .. "\n" .. table.concat({
      "local owner = resource_new()",
      "do",
      "   local view = forward(borrow(owner))",
      "   print(view.value)",
      "end",
      "resource_free(owner)",
   }, "\n"))
end

function M.potentiallyAffineGenericPacksMustTransferExactlyOnce()
   assertEq(codes(table.concat({
      "local function drop<A...>(...: A...) end",
      "return drop",
   }, "\n")), "NUPP2605")
   assertEq(codes(table.concat({
      "local function duplicate<A...>(sink: function(A...), ...: A...)",
      "   sink(...)",
      "   sink(...)",
      "end",
      "return duplicate",
   }, "\n")), "NUPP2605")
end

return M
