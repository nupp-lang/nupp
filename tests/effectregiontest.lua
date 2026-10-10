local testAssert = require("nupp.test")
-- Allocation- and raising-free checked regions and their observed module sidecars.
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")
local incremental = require("nupp.compiler.project.incremental")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local function refusals(src)
    local parsed = parser.parse(src, "effect-region.g.nupp")
    testAssert.equal(#parsed.errors, 0, "syntax")
    local diags = check.check(parsed, "effect-region.g.nupp", envMod.new(HERE))
    local found = {}
    for _, diag in ipairs(diags) do
        if diag.code == "NUPP2710" or diag.code == "NUPP2711" then
            found[#found + 1] = diag
        end
    end

    return found, parsed
end

local M = {}

function M.sameFileCallsUseTheExistingSummary()
    local found = refusals(
        table.concat(
            {
                "local function quiet(): nil local n = 1 end",
                "local function allocates(): nil local t = {} end",
                "local function raises(): nil error('bad') end",
                "@noalloc do quiet(); allocates() end",
                "@noraise do quiet(); raises() end",
            },
            "\n"
        )
    )
    testAssert.equal(#found, 2, "one refusal per positive effect")
    testAssert.equal(found[1].code, "NUPP2710", "allocation diagnostic")
    testAssert.equal(found[2].code, "NUPP2711", "raising diagnostic")
end

function M.directOperationsAreCheckedAndRegionsErase()
    local found, parsed = refusals("@noalloc do local t = {} end")
    testAssert.equal(#found, 1, "table construction is an allocation")
    local generated = require("nupp.compiler.lua.gen").generate(parsed, "effect-region.g.nupp")
    assert(generated:find("do", 1, true), "region emits a block")
    assert(not generated:find("noalloc", 1, true), "no runtime guard remains")
end

function M.fixedWidthScalarOperationsSatisfyBothRegions()
    local found = refusals(
        table.concat(
            {
                "@noalloc do local x = nupp.math.u32.mul(0xffffffff, 3) end",
                "@noraise do local y = nupp.math.f32.fma(1.0, 2.0, 3.0) end",
            },
            "\n"
        )
    )
    testAssert.equal(#found, 0, "fixed-width scalar calls have modeled negative effects")
end

function M.boxedSixtyFourBitArithmeticAllocates()
    -- LuaJIT boxes every int64 and uint64 result in a fresh cdata object, so the
    -- arithmetic allocates however scalar its operands are, and a helper doing it
    -- carries that in its summary.
    local found = refusals(
        table.concat(
            {
                "local function sum(a: int64, n: integer): int64",
                "   local v = a",
                "   @noalloc do",
                "      for _ = 1, n do v = v + a end",
                "   end",
                "   return v",
                "end",
                "local function twice(a: uint64): uint64 return a * 2ULL end",
                "@noalloc do local w = twice(1ULL) end",
                "@noalloc do local b = 1LL & 2LL end",
                "@noalloc do local m = -1LL end",
            },
            "\n"
        )
    )
    testAssert.equal(#found, 4, "each boxed result is an allocation: " .. tostring(found[1] and found[1].msg))
    for _, diag in ipairs(found) do
        testAssert.equal(diag.code, "NUPP2710", "allocation diagnostic")
    end
end

function M.aGradualIndexMayRaise()
    -- Nothing says what `any` holds: an `__index` that runs user code, or a value
    -- that cannot be indexed. A gradual call is refused for the same reason.
    local found = refusals(
        table.concat(
            {
                "local function read(g: any): any",
                "   local n: any = 0",
                "   @noraise do n = g.field end",
                "   @noalloc do n = g.field end",
                "   return n",
                "end",
            },
            "\n"
        )
    )
    testAssert.equal(#found, 1, "indexing a gradual value may raise")
    testAssert.equal(found[1].code, "NUPP2711", "raising diagnostic")
end

-- `table` says no more about a metatable than `any` does, and a bracketed key
-- reaches `__index` and `__newindex` the same way a dotted one does.
function M.everyGradualIndexMayRaise()
    for _, access in ipairs({
        "local function f(t: table): any local n: any = nil @noraise do n = t.field end return n end",
        "local function f(t: any, k: string): any local n: any = nil @noraise do n = t[k] end return n end",
        "local function f(t: table, k: string): any local n: any = nil @noraise do n = t[k] end return n end",
        "local function f(t: table): nil @noraise do t.x = 1 end end",
        "local function f(t: table, k: string): nil @noraise do t[k] = 1 end end",
    }) do
        local found = refusals(access)
        testAssert.equal(#found, 1, access)
        testAssert.equal(found[1].code, "NUPP2711", access)
    end
end

function M.aCheckedRangeDischargesMatchingSpanBoundsOnly()
    local found = refusals(
        table.concat(
            {
                "local span = require('nupp.mem.span')",
                "local indexed = require('nupp.mem.indexed')",
                "local struct Value n: integer end",
                "const storage = carray(Value, 4)",
                "const values = span.fromCarray(storage, 4)",
                "const rows = indexed.range(1, 4, values)",
                "for i = rows.first, rows.last do",
                "   @noalloc do local value = values[i] end",
                "   @noraise do local value = values[i] end",
                "end",
                "@noraise do local value = values[1] end",
            },
            "\n"
        )
    )
    testAssert.equal(#found, 1, "only the access outside the dominated loop can raise")
    testAssert.equal(found[1].code, "NUPP2711")
end

function M.rangeProofsRequireStableSpanIdentities()
    local found = refusals(
        table.concat(
            {
                "local span = require('nupp.mem.span')",
                "local indexed = require('nupp.mem.indexed')",
                "local struct Value n: integer end",
                "const storage = carray(Value, 2)",
                "local values = span.fromCarray(storage, 2)",
                "const rows = indexed.range(1, 2, values)",
                "for i = rows.first, rows.last do",
                "   @noraise do local value = values[i] end",
                "end",
            },
            "\n"
        )
    )
    testAssert.equal(#found, 1, "a rebindable span cannot carry a range proof")
end

function M.rangeProofsDoNotEnterNestedFunctions()
    local found = refusals(
        table.concat(
            {
                "local span = require('nupp.mem.span')",
                "local indexed = require('nupp.mem.indexed')",
                "local struct Value n: integer end",
                "const storage = carray(Value, 2)",
                "const values = span.fromCarray(storage, 2)",
                "const rows = indexed.range(1, 2, values)",
                "for i = rows.first, rows.last do",
                "   local callback = function(): nil",
                "      @noraise do local value = values[i] end",
                "   end",
                "end",
            },
            "\n"
        )
    )
    testAssert.equal(#found, 1, "a closure cannot inherit its enclosing loop's proof")
    testAssert.equal(found[1].code, "NUPP2711")
end

function M.unknownCallbacksAndForeignCallsNeedTrustedContracts()
    local found = refusals(
        table.concat(
            {
                "local function invoke(callback: function()): nil",
                "   @noalloc do callback() end",
                "   @noraise do callback() end",
                "end",
                "cdef function opaque(): nil",
                "@noalloc do opaque() end",
                "@noraise do opaque() end",
            },
            "\n"
        )
    )
    testAssert.equal(#found, 4, "unknown callbacks and uncontracted C fail both proofs")
end

function M.shadowingAPureBuiltinDoesNotBorrowItsGuarantees()
    local found = refusals(
        table.concat(
            {
                "local function direct(type: function()): nil",
                "   @noalloc do type() end",
                "end",
                "local function invoke(type: function()): nil type() end",
                "local function wrapper(type: function()): nil invoke(type) end",
                "local function use(type: function()): nil",
                "   @noalloc do wrapper(type) end",
                "   @noraise do wrapper(type) end",
                "end",
                "@noalloc do local kind = type(1) end",
                "@noraise do local kind = type(1) end",
            },
            "\n"
        )
    )
    testAssert.equal(#found, 3, "a callback named like a builtin remains effect-unknown")
end

function M.automaticCleanupParticipatesInTheRaisingSummary()
    -- The contract is what the summary reads for `close`, so it has to admit the
    -- raise: a contract that did not would be reported, and the cleanup would be
    -- believed quiet.
    local found = refusals(
        table.concat(
            {
                "local record Resource end",
                "@effects(suspends = false, raises = true)",
                "local function close(takes value: Resource): nil error('close') end",
                "local function open(): affine(Resource, close) return new Resource() end",
                "local function use(): nil local value = open() end",
                "@noraise do use() end",
            },
            "\n"
        )
    )
    testAssert.equal(#found, 1, "the implicit close keeps use from being noRaise")
    assert(#(found[1].related or {}) > 0, "the diagnostic carries a call chain")
end

local PROVIDER = table.concat(
    {
        "local M = {}",
        "function M.quiet(): nil local n = 1 end",
        "function M.allocates(): nil local t = {} end",
        "function M.raises(): nil error('bad') end",
        "return M",
    },
    "\n"
)

local function withProject(consumer, fn)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    local depPath, mainPath = dir .. "/dep.g.nupp", dir .. "/main.g.nupp"

    local function write(path, text)
        local f = assert(io.open(path, "w"));
        f:write(text);
        f:close()
    end

    write(depPath, PROVIDER)
    write(mainPath, consumer)
    local inc = incremental.new(dir, {cache = false})
    local ok, err = pcall(fn, inc, depPath, mainPath)
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(err, 0)
    end
end

function M.importsObserveOnlyTheExactFactsTheyUse()
    withProject(
        table.concat(
            {
                "local D = require('dep')",
                "@noalloc do D.quiet(); D.allocates() end",
                "@noraise do D.quiet(); D.raises() end",
            },
            "\n"
        ),
        function(inc, _, mainPath)
            local result = inc.checkFile(mainPath)
            local found = {}
            for _, diag in ipairs(result.diags) do
                if diag.code == "NUPP2710" or diag.code == "NUPP2711" then
                    found[#found + 1] = diag
                end
            end
            testAssert.equal(#found, 2, "only unsafe imported calls fail")
        end
    )
end

function M.gainingAGuaranteeInvalidatesARejectedObservation()
    withProject("local D = require('dep')\n@noalloc do D.allocates() end", function(inc, depPath, mainPath)
        local before = inc.checkFile(mainPath)
        testAssert.equal(before.diags[1] and before.diags[1].code, "NUPP2710", "initial refusal")
        local cold = inc.q.stats.checkModule
        inc.changeDocument(depPath, PROVIDER:gsub("local t = {}", "local n = 1"))
        local after = inc.checkFile(mainPath)
        testAssert.equal(
            #after.diags,
            0,
            "the absent observation becomes present: " .. tostring(
                after.diags[1] and after.diags[1].code
            ) .. " " .. tostring(after.diags[1] and after.diags[1].msg)
        )
        testAssert.equal(inc.q.stats.checkModule, cold + 2, "provider and observer recheck")
    end)
end

function M.unobservingDependantsIgnoreBodyOnlyGuaranteeChanges()
    withProject("local D = require('dep')\nlocal f = D.allocates", function(inc, depPath, mainPath)
        inc.checkFile(mainPath)
        local cold = inc.q.stats.checkModule
        inc.changeDocument(depPath, PROVIDER:gsub("local t = {}", "local n = 1"))
        inc.checkFile(mainPath)
        testAssert.equal(inc.q.stats.checkModule, cold + 1, "only provider rechecks")
    end)
end

function M.importedEffectsComposeThroughWrappers()
    withProject(
        "local D = require('dep')\nlocal function wrapper(): nil D.quiet() end\n@noraise do wrapper() end",
        function(inc, _, path)
            local checked = inc.checkFile(path)
            for _, diag in ipairs(checked.diags) do
                assert(diag.code ~= "NUPP2711", diag.msg)
            end
            local observed = false
            for _, dep in ipairs(inc.projectDependencies(path)) do
                if dep.name == "moduleCallableFact" and dep.key == "dep\0quiet\0callableEffects" then
                    observed = true
                end
            end
            assert(observed, "the wrapper observes the exported effects family")
        end
    )
end

function M.effectFactsCutOffUnchangedAndUnrelatedBodies()
    withProject(
        "local D = require('dep')\nlocal function wrapper(): nil D.quiet() end\n@noraise do wrapper() end",
        function(inc, depPath, path)
            inc.checkFile(path)
            local before = inc.q.stats.checkModule
            inc.changeDocument(depPath, PROVIDER:gsub("local n = 1", "local n = 2"))
            inc.checkFile(path)
            testAssert.equal(inc.q.stats.checkModule, before + 1, "same effects do not invalidate their observer")
            before = inc.q.stats.checkModule
            inc.changeDocument(depPath, PROVIDER:gsub("local t = {}", "local n = 2"))
            inc.checkFile(path)
            testAssert.equal(inc.q.stats.checkModule, before + 1, "another export does not invalidate this observer")
            inc.changeDocument(depPath, PROVIDER:gsub("local n = 1", "error('changed')"))
            local changed = inc.checkFile(path)
            local refused = false
            for _, diag in ipairs(changed.diags) do
                refused = refused or diag.code == "NUPP2711"
            end
            assert(refused, "a newly raising dependency invalidates the wrapper")
        end
    )
end

function M.importedRegionAndReturnPathsUseArgumentPositions()
    withProject(
        "local D = require('dep')\nlocal M = {}\nfunction M.forward(target: {n: number}): {n: number} return D.change(target) end\nreturn M",
        function(inc, depPath, path)
            inc.changeDocument(
                depPath,
                "local M = {}\nfunction M.change(value: {n: number}): {n: number} value.n = 1 return value end\nreturn M"
            )
            local checked = inc.checkFile(path)
            local fact = checked.exports.callGuarantees.forward.callableEffects
            assert(fact and fact.summary and not fact.summary.top, "imported effects remain visible")
            assert(fact.summary.writes["target[*]"], "writes substitute the actual parameter")
            assert(fact.summary.returns["1=target"], "return aliases substitute the actual parameter")
        end
    )
end

local RELATIONAL_PROVIDER = [[
local span = require("nupp.mem.span")
local M = {}
function M.get(borrows values: span.Span<uint8>, index: integer): integer
    return values[index]
end
function M.loud(borrows values: span.Span<uint8>, index: integer): integer
    local value = values[index]
    error("still raises")
    return value
end
function M.find(borrows values: span.Span<uint8>, wanted: integer): integer?
    for index = 1, #values do
        if values[index] == wanted then return index end
    end
    return nil
end
return M
]]
local RELATIONAL_CALLER = [[
local span = require("nupp.mem.span")
local D = require("dep")
const values = span.fromString("abc")
]]

local function relationRefusals(body, transform)
    local found = {}
    withProject(RELATIONAL_CALLER .. body, function(inc, depPath, path)
        inc.changeDocument(depPath, transform and transform(RELATIONAL_PROVIDER) or RELATIONAL_PROVIDER)
        local checked = inc.checkFile(path)
        for _, diag in ipairs(checked.diags) do
            if diag.code == "NUPP2711" then
                found[#found + 1] = diag
            end
        end
    end)

    return found
end

function M.importedBoundsDischargeOnlyTheBoundFailure()
    local found = relationRefusals(
        [[
for i = 1, #values do
    @noraise do local value = D.get(values, i) end
    @noraise do local value = D.loud(values, i) end
end
local checked = D.get(values, 99)
@noraise do local unproved = D.get(values, 99) end
]]
    )
    testAssert.equal(#found, 2, "other raises and unproved calls remain checked")
end

function M.returnedBoundsNeedTheNonNilAlternative()
    local found = relationRefusals(
        [[
const index = D.find(values, 98)
if index ~= nil then
    @noraise do local value = values[index] end
end
@noraise do local value = values[index as integer] end
]]
    )
    testAssert.equal(#found, 1, "a return fact holds only on its matching alternative")
end

function M.unknownCallsAndReassignmentDiscardReturnBounds()
    local found = relationRefusals(
        [[
local index = D.find(values, 98)
if index ~= nil then
    index = 100
    @noraise do local value = values[index] end
end
const again = D.find(values, 98)
if again ~= nil then
    unknown()
    @noraise do local value = values[again] end
end
]]
    )
    testAssert.equal(#found, 2, "stale evidence cannot discharge an access")
end

function M.oneUnboundedReturnRemovesTheGuarantee()
    local found = relationRefusals(
        [[
const index = D.find(values, 98)
if index ~= nil then
    @noraise do local value = values[index] end
end
]],
        function(source)
            return source:gsub("return nil", "return 999")
        end
    )
    testAssert.equal(#found, 1, "all normal returns must establish the relationship")
end

function M.replacedImportedCalleesCannotKeepBoundsProofs()
    local found = relationRefusals(
        [[
D.get = function(borrows input: span.Span<uint8>, at: integer): integer
    error("replacement")
    return 0
end
for index = 1, #values do
    @noraise do local value = D.get(values, index) end
end
]]
    )
    testAssert.equal(#found, 1, "a replacement cannot inherit the original helper's proof")
end

function M.providerReplacementDoesNotPublishOneBodyAsTheCallable()
    local found = relationRefusals(
        "for index = 1, #values do @noraise do local value = D.get(values, index) end end",
        function(source)
            source = source:gsub("return values%[index%]", 'error("original") return values[index]', 1)
            return source:gsub(
                "return M",
                [[
function M.replace(): nil
    M.get = function(borrows values: span.Span<uint8>, index: integer): integer
        return values[index]
    end
end
return M]]
            )
        end
    )
    testAssert.equal(#found, 1, "an optional provider mutation does not replace the initial callable's effects")
end

function M.explicitCallerAssertionsEstablishBounds()
    local found = relationRefusals(
        [[
local function work(index: integer): integer
    assert(index >= 1 and index <= #values)
    @noraise do return D.get(values, index) end
end
return work
]]
    )
    testAssert.equal(#found, 0, "the ordinary executable assertion establishes a later fact")
end

function M.conditionalWorkCannotLeakBoundsToItsContinuation()
    local found = relationRefusals(
        [[
local function work(index: integer, enabled: boolean): integer
    while enabled do
        assert(index >= 1 and index <= #values)
        break
    end
    @noraise do return D.get(values, index) end
end
return work
]]
    )
    testAssert.equal(#found, 1, "a zero-iteration loop establishes no fact after itself")
end

function M.aNestedBoundFailureIsNotDischargedByAnUnrelatedAccess()
    local found = relationRefusals(
        [[
for index = 1, #values do
    @noraise do local value = D.combined(values, index, 99) end
end
]],
        function(source)
            return source:gsub(
                "return M",
                [[
function M.combined(borrows values: span.Span<uint8>, index: integer, other: integer): integer
    return values[index] + M.get(values, other)
end
return M]]
            )
        end
    )
    testAssert.equal(#found, 1, "the nested access still needs its own proof")
end

function M.returnFactsInvalidateWhenLostOrGainedAndIgnoreUnrelatedBodies()
    withProject(
        RELATIONAL_CALLER
        .. [[
const index = D.find(values, 98)
if index ~= nil then @noraise do local value = values[index] end end
]],
        function(inc, dep, main)
            local function count()
                local total = 0
                for _, diag in ipairs(inc.checkFile(main).diags) do
                    if diag.code == "NUPP2711" then
                        total = total + 1
                    end
                end

                return total
            end

            inc.changeDocument(dep, RELATIONAL_PROVIDER)
            testAssert.equal(count(), 0)
            require("nupp.compiler.lua.optimize").run(inc.checkFile(main).result, {level = 1})
            local checks = inc.q.stats.checkModule
            inc.changeDocument(dep, RELATIONAL_PROVIDER .. "\n-- unchanged facts\n")
            testAssert.equal(count(), 0)
            testAssert.equal(inc.q.stats.checkModule, checks + 1)
            inc.changeDocument(dep, RELATIONAL_PROVIDER:gsub("return nil", "return 999"))
            testAssert.equal(count(), 1, "a lost result fact invalidates its consumer")
            inc.changeDocument(dep, RELATIONAL_PROVIDER)
            testAssert.equal(count(), 0, "an unknown result becoming known also invalidates")
        end
    )
end

function M.escapedNamespaceAliasesLoseTheirCallableFacts()
    local found = relationRefusals(
        [[
local alias = D
unknown({alias})
for index = 1, #values do
    @noraise do local value = D.get(values, index) end
end
]]
    )
    testAssert.equal(#found, 1, "a namespace inside an escaped container can be mutated")
end

function M.forgedArgumentMappingsDoNotEstablishBounds()
    local source = [[
local span = require("nupp.mem.span")
local D = require("tests.fixtures.crossmodulefacts")
const values = span.fromString("abc")
for index = 1, #values do
    @noraise do local value = D.get(values, 99) end
end
]]
    local env = envMod.new(HERE .. "/..")
    env.resolveCallableFact = function(self, module, member, family)
        if module == "tests.fixtures.crossmodulefacts" and family == "callableRelations" then
            return {version = 1, complete = true, accesses = {{view = 1, index = 999}}}
        end
        return envMod.resolveCallableFact(self, module, member, family)
    end
    local parsed = parser.parse(source, "forged.g.nupp")
    local found = 0
    for _, diag in ipairs(check.check(parsed, "forged.g.nupp", env)) do
        if diag.code == "NUPP2711" then
            found = found + 1
        end
    end
    testAssert.equal(found, 1, "invalid mappings remain conservative")
end

function M.importedSemanticEffectsDoNotHideTraceFindings()
    withProject(
        [[
local D = require("dep")
@jit
local function hot(items: {integer}): nil D.helper(items) end
return hot
]],
        function(inc, dep, main)
            inc.changeDocument(
                dep,
                [[
local M = {}
function M.helper(items: {integer}): nil
    for _, item in ipairs(items) do
        register(function(): integer return item end)
    end
end
return M
]]
            )
            local found = false
            for _, diag in ipairs(inc.checkFile(main).diags) do
                found = found
                or diag.code == "NUPP2707" and diag.msg:find("jit/loop-function-construction", 1, true) ~= nil
            end
            assert(found, "an imported effect summary does not replace its trace summary")
        end
    )
end

return M
