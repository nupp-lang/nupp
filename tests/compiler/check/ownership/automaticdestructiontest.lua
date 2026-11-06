local testAssert = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local program = require("program")
local fmt = require("nupp.tools.fmt")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local checkedRun = 0

local function checked(source)
    checkedRun = checkedRun + 1
    env.loaded = {}
    local filename = ("automatic-destruction-test-%d.nupp"):format(checkedRun)
    local result = parser.parse(source, filename)
    testAssert.eq(#result.errors, 0, result.errors[1] and result.errors[1].msg or "syntax")
    local diags = check.check(result, filename, env)

    return result, diags
end

local function codes(source)
    local _, diags = checked(source)
    local out = {}
    for _, diag in ipairs(diags) do
        out[#out + 1] = diag.code
    end

    return table.concat(out, " ")
end

local function compile(source)
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, err = program.load(result, "automatic_destruction_test")
    assert(chunk, err)

    return chunk
end

local PRELUDE = table.concat(
    {
        "local calls = ''",
        "local record Resource",
        "   name: string",
        "end",
        "local function close_resource(takes value: Resource): nil",
        "   calls = calls .. value.name",
        "end",
        "local function open_resource(name: string): affine(Resource, close_resource)",
        "   return Resource(name = name)",
        "end",
    },
    "\n"
)

local M = {}

function M.repeatConditionsCanReadBodyOwnersBeforeCleanup()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local count = 0",
                "repeat",
                "   local value = open_resource('r')",
                "   count = count + 1",
                "until value.name == 'r' and count == 1",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "r")
end

function M.anOrdinaryScopeClosesAnAffineOwner()
    local ordinary = parser.parse(
        "local with = function(value) return value end\nreturn with(1)",
        "automatic-destruction-test.nupp"
    )
    testAssert.eq(#ordinary.errors, 0)

    local chunk = compile(
        PRELUDE .. table.concat(
            {"", "do local value = open_resource('w') ;", "   value.name = value.name", "end", "return calls",},
            "\n"
        )
    )
    testAssert.eq(chunk(), "w")
end

function M.aScopeThatMayRaiseKeepsProtectedCleanup()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function run()",
                "   do local value = open_resource('p') ;",
                "      error(value.name)",
                "   end",
                "end",
                "local ok = pcall(run)",
                "return ok, calls",
            },
            "\n"
        )
    )
    local ok, calls = chunk()
    testAssert.eq(ok, false)
    testAssert.eq(calls, "p")
end

function M.aScopeWhoseTerminalMayRaiseKeepsProtectedCleanup()
    local source = table.concat(
        {
            "local record Resource",
            "   name: string",
            "end",
            "local function fail_close(takes value: Resource): nil",
            "   error(value.name)",
            "end",
            "local function open_resource(name: string): affine(Resource, fail_close)",
            "   return Resource(name = name)",
            "end",
            "local function run()",
            "   do local value = open_resource('c') ;",
            "      value.name = value.name",
            "   end",
            "end",
            "return pcall(run)",
        },
        "\n"
    )
    local chunk = compile(source)
    testAssert.eq(chunk(), false)
end

function M.scopeAcquisitionsRunLeftToRightAndDropInReverse()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "do local first = open_resource('a'); local second = open_resource('b') ;",
                "   calls = calls .. 'x'",
                "end",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "xba")
end

function M.scopedOwnersDropOnRaisedAndReturnedExits()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function returning(): string",
                "   do local value = open_resource('r') ; return value.name end",
                "end",
                "local function raising()",
                "   do local value = open_resource('e') ; error('body') end",
                "end",
                "local result = returning()",
                "local ok = pcall(raising)",
                "return result, ok, calls",
            },
            "\n"
        )
    )
    local result, ok, calls = chunk()
    testAssert.eq(result, "r")
    testAssert.eq(ok, false)
    testAssert.eq(calls, "re")
end

function M.scopedOwnersCanBeReborrowedExclusively()
    local chunk = compile(
        PRELUDE
        .. "\n"
        .. [[
local function rename(exclusive value: Resource): nil
    value.name = 'changed'
end
do local value = open_resource('fresh') ;
    rename(value)
end
local owner = open_resource('named')
do local value = owner ;
    rename(value)
end
return calls
]]
    )
    testAssert.eq(chunk(), "changedchanged")
end

function M.scopedReborrowsRejectLiveAliasesAndRecoverAtScopeExit()
    local source = PRELUDE
        .. "\n"
        .. [[
local function rename(exclusive value: Resource): nil value.name = 'changed' end
local function view(borrows value: Resource): Resource borrows(value) return value end
do local value = open_resource('fresh') ;
    do
        local alias = view(value)
        rename(value)
        print(alias.name)
    end
    rename(value)
end
]]
    testAssert.eq(codes(source), "NUPP2607")
    testAssert.eq(codes((source:gsub("        rename%(value%)\n", ""))), "")
end

local SPAN_SOURCE = [[
local array = table.Array
local span = require("binary.span")
@aot
local function fill(exclusive values: span.WriteSpan<float32>): nil
    for i = 1, #values do values[i] = 3.0 end
end
local values = array.scalar(array.float, 4)
]]

function M.scopedWritableSpansKeepTheirSourceLoansUntilExit()
    testAssert.eq(
        codes(
            SPAN_SOURCE
            .. [[
do local writable = values:write() ;
    fill(writable)
end
local owner = values:write()
do local writable = owner ;
    fill(writable)
end
local result = values:read()
print(result[1])
]]
        ),
        ""
    )

    for _, operation in ipairs({"local other = values:write()", "local other = values:read()", "own.drop(values)",}) do
        local actual = codes(SPAN_SOURCE .. "\ndo local writable = values:write() ;\n" .. operation .. "\nend")
        assert(actual:find("NUPP260[27]"), operation .. ": " .. actual)
    end
end

function M.scopedWritableSpansRejectOverlappingAcquisitions()
    local actual = codes(
        SPAN_SOURCE
        .. [[
do local left = values:write(); local right = values:write() ;
    fill(left)
    fill(right)
end
]]
    )
    assert(actual:find("NUPP2607", 1, true), actual)
end

function M.scopedWritableSpansRejectLiveDerivedViews()
    for _, derive in ipairs({"writable:shared()", "writable:slice(1, 2)"}) do
        local source = SPAN_SOURCE
            .. [[
do local writable = values:write() ;
    do
        local child = ]]
            .. derive
            .. [[

        fill(writable)
        print(child[1])
    end
    fill(writable)
end
]]
        testAssert.eq(codes(source), "NUPP2607", derive)
        testAssert.eq(codes((source:gsub("        fill%(writable%)\n", ""))), "", derive)
    end
end

function M.fallthroughDestroysAnOrdinaryOwner()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function run()",
                "   local value = open_resource('a')",
                "   value.name = value.name",
                "end",
                "run()",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "a")
end

function M.anEmptyNonRaisingIntervalUsesDirectCleanup()
    local chunk = compile(
        PRELUDE .. table.concat(
            {"", "local function run()", "   local value = open_resource('z')", "end", "run()", "return calls",},
            "\n"
        )
    )
    testAssert.eq(chunk(), "z")
end

function M.aRaisedBodyStillDestroysTheOwner()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local ok = pcall(function()",
                "   local value = open_resource('e')",
                "   error(value.name)",
                "end)",
                "return ok, calls",
            },
            "\n"
        )
    )
    local ok, calls = chunk()
    testAssert.eq(ok, false)
    testAssert.eq(calls, "e")
end

function M.ownersDestroyInReverseActivationOrder()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function run()",
                "   local first = open_resource('a')",
                "   local second = open_resource('b')",
                "   calls = calls .. first.name .. second.name",
                "end",
                "run()",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "abba")
end

function M.explicitDropSuppressesAutomaticCleanup()
    local chunk = compile(
        PRELUDE .. table.concat({"", "local value = open_resource('d')", "own.drop(value)", "return calls",}, "\n")
    )
    testAssert.eq(chunk(), "d")
end

function M.aMovedBindingCanBeReinitializedForAutomaticCleanup()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function run()",
                "   local value = open_resource('a')",
                "   own.drop(value)",
                "   value = open_resource('b')",
                "end",
                "run()",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "ab")
end

function M.aTakesCallReceivesResponsibilityExactlyOnce()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function consume(takes value: Resource)",
                "   @unsafe do",
                "      local raw = @unsafe own.release(value)",
                "      calls = calls .. raw.name",
                "   end",
                "end",
                "local value = open_resource('t')",
                "consume(value)",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "t")
end

function M.aTakesBoundaryMayItselfBeTheTerminal()
    testAssert.eq(
        codes(
            PRELUDE .. table.concat(
                {"", "local function incomplete(takes value: Resource)", "   print(value.name)", "end",},
                "\n"
            )
        ),
        ""
    )
end

function M.anOwningReturnTransfersResponsibility()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function make(): affine(Resource, close_resource)",
                "   local value = open_resource('r')",
                "   return value",
                "end",
                "local value = make()",
                "own.drop(value)",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "r")
end

function M.capabilityPreservingGenericsTransferAutomaticResponsibility()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function forward<T>(takes value: T): T preserves value",
                "   return value",
                "end",
                "local value = open_resource('f')",
                "local moved = forward(value)",
                "own.drop(moved)",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "f")
end

function M.opaqueOwnersStillNeedAnExplicitTerminal()
    local source = table.concat({"local function begin(): affine(table) return {} end", "local value = begin()",}, "\n")
    testAssert.eq(codes(source), "NUPP2603")
end

function M.rawSuspensionStillCannotStrandAnAutomaticOwner()
    local source = PRELUDE .. table.concat({"", "local value = open_resource('s')", "coroutine.yield()",}, "\n")
    testAssert.eq(codes(source), "NUPP2603")
end

function M.optionalOwnersDestroyOnlyWhenPresent()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function maybe_open(present: boolean): affine(Resource?, close_resource)",
                "   if present then return Resource(name = 'p') end",
                "   return nil",
                "end",
                "local function run(present: boolean)",
                "   local value = maybe_open(present)",
                "   if value then value.name = value.name end",
                "end",
                "run(false)",
                "run(true)",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "p")
end

function M.protectedCallPacksKeepAutomaticOwnershipCorrelated()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function run()",
                "   local ok, value = pcall(open_resource, 'k')",
                "   if ok then print(value.name) end",
                "end",
                "run()",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "k")
end

function M.partialAcquisitionCleansOnlySuccessfulOwners()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function fail(): Resource error('acquire') end",
                "local function failed_open(): affine(Resource, close_resource) return fail() end",
                "local ok = pcall(function()",
                "   local first = open_resource('a')",
                "   local second = failed_open()",
                "   print(first.name, second.name)",
                "end)",
                "return ok, calls",
            },
            "\n"
        )
    )
    local ok, calls = chunk()
    testAssert.eq(ok, false)
    testAssert.eq(calls, "a")
end

function M.oneDeclarationRegistersEachSuccessfulAcquisition()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function fail(): Resource error('acquire') end",
                "local function failed_open(): affine(Resource, close_resource) return fail() end",
                "local ok = pcall(function()",
                "   local first, second = open_resource('m'), failed_open()",
                "   print(first.name, second.name)",
                "end)",
                "return ok, calls",
            },
            "\n"
        )
    )
    local ok, calls = chunk()
    testAssert.eq(ok, false)
    testAssert.eq(calls, "m")
end

function M.partialFieldMovesAndReinitializationKeepExactObligations()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local record Bundle",
                "   first: affine(Resource, close_resource)",
                "   second: affine(Resource, close_resource)",
                "end",
                "local function run()",
                "   local bundle = Bundle(",
                "      first = open_resource('a'),",
                "      second = open_resource('b')",
                "   )",
                "   local first = bundle.first",
                "   own.drop(first)",
                "   bundle.first = open_resource('c')",
                "end",
                "run()",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "abc")
end

function M.structuredExitsRunCleanup()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
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
            },
            "\n"
        )
    )
    local n, calls = chunk()
    testAssert.eq(n, 1)
    testAssert.eq(calls, "r12g")
end

function M.aBodyThatOnlyCallsOutStillSharesOneRegion()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function note(text: string): nil",
                "   calls = calls .. text",
                "end",
                "for _, name in ipairs({'a', 'b', 'c'}) do",
                "   local value = open_resource(name)",
                "   note(value.name)",
                "end",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "aabbcc")
end

function M.aChunkLevelLoopVariableTravelsThroughARegionFrame()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "for i = 1, 3 do",
                "   local value = open_resource('x')",
                "   calls = calls .. tostring(i)",
                "end",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "1x2x3x")
end

function M.aFunctionLocalWriteUsesOneRegionPerInvocation()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
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
            },
            "\n"
        )
    )
    local first, second, calls = chunk()
    testAssert.eq(first, 3)
    testAssert.eq(second, 2)
    testAssert.eq(calls, "xxxxx")
end

function M.recursiveInvocationsDoNotShareRegionUpvalues()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
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
            },
            "\n"
        )
    )
    local total, calls = chunk()
    testAssert.eq(total, 6)
    testAssert.eq(calls, "xxxx")
end

function M.aColonMethodRegionDoesNotCacheItsReceiverModuleWide()
    -- A colon-declared method binds `self` without a source token, so a region
    -- body reading it must reserve a per-invocation cache: parked module-wide,
    -- the cached closure would answer every later call with the first caller's
    -- receiver.
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local record Client",
                "   name: string",
                "end",
                "function Client:label(): string",
                "   return self.name",
                "end",
                "function Client:tell(): string",
                "   local value = open_resource('x')",
                "   return self:label()",
                "end",
                "local first = Client(name = 'first')",
                "local second = Client(name = 'second')",
                "return first:tell(), second:tell(), calls",
            },
            "\n"
        )
    )
    local first, second, calls = chunk()
    testAssert.eq(first, "first")
    testAssert.eq(second, "second", "a later receiver answers through its own self")
    testAssert.eq(calls, "xx")
end

function M.aLoopLocalWriteTravelsThroughARegionFrame()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
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
            },
            "\n"
        )
    )
    local totals, calls = chunk()
    testAssert.eq(totals, "136")
    testAssert.eq(calls, "xxxxxx")
end

function M.frameWritebackPrecedesStructuredExitDispatch()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
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
            },
            "\n"
        )
    )
    local totals, calls = chunk()
    testAssert.eq(totals, "333")
    testAssert.eq(calls, "xxxxxx")
end

function M.automaticLoweringEmitsLoadableCleanupRegions()
    local source = PRELUDE .. table.concat(
        {"", "local function run()", "   local value = open_resource('l')", "   print(value.name)", "end",},
        "\n"
    )
    assert(compile(source))
end

function M.aNestedFunctionReturnsValuesThroughItsOwnRegion()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local outer = open_resource('o')",
                "local function inner(): (string, integer)",
                "   local value = open_resource('i')",
                "   return value.name, 2",
                "end",
                "local name, count = inner()",
                "return name, count, calls",
            },
            "\n"
        )
    )
    local name, count, calls = chunk()
    testAssert.eq(name, "i")
    testAssert.eq(count, 2)
    testAssert.eq(calls, "i")
end

function M.closeableFieldsCloseInReverseOrder()
    local chunk = compile(
        table.concat(
            {
                "local calls = ''",
                "local record Resource is own.Closeable",
                "   name: string",
                "   function flush(exclusive self): nil end",
                "   function close(takes self): nil calls = calls .. self.name end",
                "end",
                "local record Bundle",
                "   first: Resource",
                "   second: Resource",
                "end",
                "do",
                "   local bundle = Bundle(",
                "      first = Resource(name = 'a'),",
                "      second = Resource(name = 'b')",
                "   )",
                "end",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "ba")
end

function M.manualCloseDischargesAnInherentObligationOnce()
    local chunk = compile(
        table.concat(
            {
                "local calls = 0",
                "local record Resource is own.Closeable",
                "   function flush(exclusive self): nil end",
                "   function close(takes self): nil calls = calls + 1 end",
                "end",
                "do",
                "   local value = Resource()",
                "   value:close()",
                "end",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), 1)
end

function M.aTakingMethodCalledWithAStringArgumentReceivesIt()
    -- The receiver's move is cleared inside a wrapper, so the call is respelled
    -- there argument by argument; a call written with a bare string has that
    -- string for its one argument.
    local chunk = compile(
        table.concat(
            {
                "local calls = ''",
                "local record Resource is own.Closeable",
                "   name: string",
                "   function flush(exclusive self): nil end",
                "   function close(takes self): nil calls = calls .. self.name end",
                "   function consume(takes self, label: string): string",
                "      local answer = self.name .. label",
                "      self:close()",
                "      return answer",
                "   end",
                "end",
                "local function use(): string",
                "   local value = Resource(name = 'r')",
                "   return value:consume'x'",
                "end",
                "return use(), calls",
            },
            "\n"
        )
    )
    local answer, closed = chunk()
    testAssert.eq(answer, "rx")
    testAssert.eq(closed, "r")
end

function M.aParenthesisedOwnerMovesIntoItsNewBindingOnce()
    -- The checker records the move on the name inside `(a)`, and the generator
    -- read it off the parentheses, so the source slot stayed active and both
    -- bindings ran the cleanup.
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "do",
                "   local a = open_resource('a')",
                "   local b = (a)",
                "end",
                "do",
                "   local a = open_resource('b')",
                "   local b = (a) as Resource",
                "   local raw = @unsafe own.release(b)",
                "   calls = calls .. raw.name",
                "end",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "ab")
end

function M.aFieldMovedOnOnePathIsStillDroppedWithTheRecordOnTheOther()
    -- `drop` left a moved field out of the record's cleanup for good, so the path
    -- that never moved it leaked it. The field's run-time record now decides.
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local record Bundle",
                "   first: affine(Resource, close_resource)",
                "   second: affine(Resource, close_resource)",
                "end",
                "local function consume(takes value: affine(Resource, close_resource)): nil",
                "   calls = calls .. '<' .. value.name .. '>'",
                "   own.drop(value)",
                "end",
                "local function run(flag: boolean)",
                "   local bundle = Bundle(",
                "      first = open_resource('a'),",
                "      second = open_resource('b')",
                "   )",
                "   if flag then consume(bundle.first) end",
                "   own.drop(bundle)",
                "   calls = calls .. '|'",
                "end",
                "run(true)",
                "run(false)",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "<a>ab|ba|")
end

function M.aForInOwnerIsClosedAtTheEndOfEachIteration()
    -- The iterator hands out an owner per iteration; the loop variable takes a
    -- hidden name and a local of the written name owns the value for the body.
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function iter(state: integer, control: integer): (integer?, affine(Resource, close_resource)?)",
                "   if control >= 2 then return nil, nil end",
                "   return control + 1, open_resource(tostring(control + 1))",
                "end",
                "for i, r in iter, 0, 0 do",
                "   if r then calls = calls .. '<' .. r.name .. '>' end",
                "end",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "<1>1<2>2")
end

function M.anOptionalSlotFilledLaterIsDroppedAtScopeEnd()
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function late(flag: boolean): nil",
                "   local b: affine(Resource, close_resource)? = nil",
                "   if flag then b = open_resource('b') end",
                "   if b ~= nil then calls = calls .. '<' .. b.name .. '>' end",
                "end",
                "late(false)",
                "late(true)",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "<b>b")
end

function M.aSwitchArmHandsItsOwnerToTheBindingOnce()
    -- The binding's switch used to fail to lift, and once lifted the arm that
    -- named an owner left its slot active, so both closed it.
    local chunk = compile(
        PRELUDE .. table.concat(
            {
                "",
                "local function pick(flag: boolean): nil",
                "   local a = open_resource('a')",
                "   local b = switch flag do",
                "      case true -> a",
                "      else -> do yield open_resource('b') end",
                "   end",
                "   calls = calls .. '<' .. b.name .. '>'",
                "end",
                "pick(true)",
                "calls = calls .. '|'",
                "pick(false)",
                "return calls",
            },
            "\n"
        )
    )
    testAssert.eq(chunk(), "<a>a|<b>ba")
end

function M.genericRecordsCanCloseThemselves()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record Box<T> is own.Closeable",
                    "    value: T",
                    "    close: function(takes self: Box<T>): nil",
                    "end",
                    "local record Other is own.Closeable",
                    "    close: function(takes self: Other): nil",
                    "end",
                    "local record Wrong<T> is own.Closeable",
                    "    close: function(takes self: Other): nil",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2615"
    )
end

return M
