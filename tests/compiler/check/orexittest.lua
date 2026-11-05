-- `or return`, `or break` and `or continue`: the contextual exit suffixes.
--
-- The cases lower each admitted program to a VM image and execute the resulting
-- straight-line control flow.

local parser = require("nupp.compiler.syntax.parser")
local assertions = require("helpers.assertions")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local program = require("program")
local fmt = require("nupp.tools.fmt")

local HERE = require("helpers.paths").tests
local FILE = "or-exit.nupp"

-- One environment for the whole suite. The eligibility rules are about result
-- packs the prelude declares -- `pcall`'s union above all -- so these cases need
-- the real declarations rather than the implicit gradual environment.
local sharedEnv = envMod.new(HERE)

local function parsed(source)
    return parser.parse(source, FILE)
end

local function checked(source)
    local tree = parsed(source)
    assert(#tree.errors == 0, tree.errors[1] and tree.errors[1].msg)
    local diagnostics = check.check(tree, FILE, sharedEnv)
    return tree, diagnostics
end

local function run(source)
    local tree, diagnostics = checked(source)
    assert(#diagnostics == 0, diagnostics[1] and diagnostics[1].msg)

    return program.run(tree, "or_exit", FILE)
end

-- Asserts the program answers true.
local function runsGenerated(source)
    assert(run(source), "the program answered false")

    return true
end

local function codesOf(diagnostics)
    local codes = {}
    for index, diagnostic in ipairs(diagnostics) do
        codes[index] = diagnostic.code
    end

    return table.concat(codes, " ")
end

local function firstMessage(diagnostics)
    return diagnostics[1] and diagnostics[1].msg or "no diagnostic"
end

local assertClean = assertions.clean

local function assertReports(source, code, label)
    local _, diagnostics = checked(source)
    assert(
        diagnostics[1] and diagnostics[1].code == code,
        (label or source) .. ": got " .. codesOf(diagnostics) .. " -- " .. firstMessage(diagnostics)
    )

    return diagnostics[1]
end

local function assertSyntaxError(source, label)
    local tree = parsed(source)
    assert(#tree.errors > 0, (label or source) .. ": expected a syntax error")

    return tree.errors[1]
end

-- A reader-friendly source: the two-result helper most of these cases test with.
local HELPER = [[
local function ok(n: integer): (integer?, string?)
    if n <= 0 then
        return nil, "not positive"
    end

    return n, nil
end
]]

local M = {}

---------------------------------------------------------------------------
-- Syntax
---------------------------------------------------------------------------

--- The suffix reads in every expression position a value does.
function M.everyPositionParses()
    for _, form in ipairs({
        "local value = ok(1) or return",
        "value = ok(1) or return",
        "print(ok(1) or return)",
        "return ok(1) or return",
        "if (ok(1) or return) > 0 then end",
        "local value = (ok(1) or return)",
        "local value = ok(1) || return",
    }) do
        local tree = parsed(HELPER .. "local value = 0\n" .. form .. "\n")
        assert(#tree.errors == 0, form .. ": " .. (tree.errors[1] and tree.errors[1].msg or ""))
    end
end

--- Ordinary disjunction is untouched, and the suffix sits at the `or` tier.
function M.precedenceKeepsTheLooseBinding()
    -- Parsed rather than checked, because the grouping this pins is exactly what
    -- makes the program a type error: `1 + ok(n)` adds to an optional. That is
    -- the reading to have, and the parentheses that fix it are the reader's.
    local tree = parsed(HELPER .. "local sum = 1 + ok(1) or return\n")
    assert(#tree.errors == 0, tree.errors[1] and tree.errors[1].msg)
    local found = nil

    local function walk(node)
        if not node or type(node) ~= "table" then
            return
        end
        if node.kind == "orExitExpr" then
            found = node
            return
        end
        for _, child in ipairs(node) do
            walk(child)
        end
    end

    walk(tree.root)
    assert(found, "the suffix parsed")
    assert(found.operand and found.operand.kind == "binop", "the operand is the whole addition")
    assert(found.exitKind == "return")
    -- `a and f() or return` puts the suffix on the whole conjunction for the same
    -- reason, which is also why its forwarded pack leads with `false`: that is
    -- what `and` can answer.
    local conjunction = parsed(HELPER .. "local flag = true\nlocal value = flag and ok(1) or return\n")
    assert(#conjunction.errors == 0, conjunction.errors[1] and conjunction.errors[1].msg)
    found = nil
    walk(conjunction.root)
    assert(found and found.operand and found.operand.kind == "binop", "the operand is the conjunction")
    assert(found.operand.op and found.operand.op.kind == "and", "and, not or")
    local _, conjunctionDiagnostics = checked(
        HELPER
        .. [[
local function conjunction(flag: boolean, n: integer): (false | integer | nil, string?)
    local value = flag and ok(n) or return

    return value, nil
end

local plain = 1 or 2

return conjunction(true, 1), plain
]]
    )
    assertClean(conjunctionDiagnostics, "a conjunction operand and an ordinary disjunction")
end

--- A ternary's own associativity stays in charge without parentheses.
function M.aTernaryArmTakesTheSuffixWithoutParentheses()
    local tree = parsed(HELPER .. "local flag = true\nlocal value = flag ? 1 : ok(1) or return\n")
    assert(#tree.errors == 0, tree.errors[1] and tree.errors[1].msg)
    local ternary = nil

    local function walk(node)
        if not node or type(node) ~= "table" then
            return
        end
        if node.kind == "ternary" then
            ternary = node
        end
        for _, child in ipairs(node) do
            walk(child)
        end
    end

    walk(tree.root)
    assert(ternary, "the ternary parsed")
    assert(ternary.ifFalse and ternary.ifFalse.kind == "orExitExpr", "the suffix belongs to the false arm")
end

--- What the suffix refuses: a second exit, an operand after the exit word, and
--- an exit word that did not begin on the `or`'s own line.
function M.malformedSuffixesAreRefused()
    assertSyntaxError(HELPER .. "local value = ok(1) or return or return\n", "chained exits")
    assertSyntaxError(HELPER .. "local value = ok(1) or return nil\n", "a value after return")
    assertSyntaxError(HELPER .. "for _ = 1, 2 do local value = ok(1) or break outer end\n", "a label after break")
    -- Not the suffix at all: `or` then wants an expression and the next line
    -- begins with a reserved word.
    assertSyntaxError(HELPER .. "local value = ok(1) or\n    return\n", "the exit word on the next line")
end

--- An `or` may still open a continuation line when its exit word comes with it.
function M.theOrMayOpenAContinuationLine()
    local tree = parsed(HELPER .. "local value = ok(1)\n    or return\n")
    assert(#tree.errors == 0, tree.errors[1] and tree.errors[1].msg)
end

--- The one program whose meaning this feature changes.
---
--- `continue` is an ordinary name everywhere but directly after `or`, so a file
--- holding a variable of that name now reads `a or continue` as the suffix. The
--- overlap is deliberate and is pinned here rather than left as a claim.
function M.aVariableNamedContinueStillReadsAsAName()
    local tree = parsed("local continue = 1\nlocal value = continue + continue\nreturn value\n")
    assert(#tree.errors == 0, tree.errors[1] and tree.errors[1].msg)
    assert(
        run("local continue = 1\nlocal value = continue + continue\nreturn value == 2\n") == true,
        "a name spelled continue keeps its Lua meaning"
    )
    -- Directly after `or`, the same spelling is now the exit word, so this is a
    -- loop exit rather than a disjunction and reports outside a loop.
    local failure = assertSyntaxError("local continue = 1\nlocal value = nil or continue\nreturn value\n")
    assert(failure.msg:find("no loop to continue", 1, true), failure.msg)
end

--- `break` and `continue` do not cross a function boundary or leave a loopless
--- position, and a `repeat` condition is what `continue` jumps to.
function M.loopExitsAreRefusedWhereTheyHaveNoTarget()
    assertSyntaxError(HELPER .. "local value = ok(1) or break\n", "break outside a loop")
    assertSyntaxError(HELPER .. "local value = ok(1) or continue\n", "continue outside a loop")
    assertSyntaxError(
        HELPER .. "for _ = 1, 2 do local f = function(): nil local v = ok(1) or break end end\n",
        "break across a function literal"
    )
    assertSyntaxError(
        HELPER .. "for _ = 1, 2 do repeat until ok(1) or continue end\n",
        "continue in a repeat condition"
    )
    -- `or break` in that same condition is admitted; it targets the loop around
    -- the repeat, the way the generator already treats a lowered condition.
    local tree = parsed(HELPER .. "for _ = 1, 2 do repeat until (ok(1) or break) > 0 end\n")
    assert(#tree.errors == 0, tree.errors[1] and tree.errors[1].msg)
end

--- The suffix is typed syntax, so a plain `.lua` file refuses it.
function M.plainLuaRefusesTheSuffix()
    local tree = parser.parse("local value = f() or return\nreturn value\n", "plain.lua")
    assert(#tree.errors == 0, tree.errors[1] and tree.errors[1].msg)
    local diagnostics = check.check(tree, "plain.lua", nil, {})
    assert(diagnostics[1] and diagnostics[1].code == "NUPP1006", codesOf(diagnostics))
end

--- Formatting is stable and keeps the exit beside its `or`.
function M.formatRoundTrip()
    local source = HELPER
        .. [[

local function wrapped(n: integer): (integer?, string?)
    local value = ok(n) or return

    return value, nil
end

return wrapped(1)
]]
    local formatted = fmt.format(source)
    assert(fmt.format(formatted) == formatted, formatted)
    assert(formatted:find("or return", 1, true), "the exit stays beside its or: " .. formatted)
    -- The customary spelling is left as written, as it is everywhere else.
    local customary = fmt.format(HELPER .. "local value = ok(1) || return\n")
    assert(customary:find("|| return", 1, true), customary)
    assert(fmt.format(customary) == customary, customary)
    -- A suffix whose operand is broken across lines keeps the exit word on the
    -- last one, because the formatter never breaks at the suffix's own `or`.
    local wide = fmt.format(HELPER .. "local total = ok(1) " .. ("+ 100000 "):rep(14) .. "or return\n")
    assert(wide:find("or return", 1, true), wide)
    assert(fmt.format(wide) == wide, wide)
end

---------------------------------------------------------------------------
-- Checking
---------------------------------------------------------------------------

--- The successful value is the first result narrowed by the same truthiness
--- that selected it, at every operand width.
function M.successIsTheNarrowedFirstResult()
    assert(
        runsGenerated(
            [[
local function one(n: integer): integer?
    return n > 0 and n or nil
end

local function flag(n: integer): (boolean, string?)
    return n > 0, n > 0 and nil or "no"
end

local function wide(n: integer): (integer?, string, string?)
    return n > 0 and n or nil, "middle", nil
end

local function useOne(n: integer): integer?
    local value = one(n) or return
    -- Narrowed: no second test is needed to use it as an integer.
    return value + 1
end

local function useFlag(n: integer): (boolean, string?)
    local ready = flag(n) or return
    -- Narrowed to the literal true.
    return ready, nil
end

local function useWide(n: integer): (integer?, string, string?)
    local value = wide(n) or return

    return value + 1, "middle", nil
end

return useOne(1) == 2 and useOne(-1) == nil and useFlag(1) == true and useWide(2) == 3
]]
        )
    )
end

--- `or return` forwards the operand's own pack with the first slot narrowed, so
--- the reason reaches the caller and a boolean discriminator forwards `false`.
function M.failureForwardsTheOperandsPack()
    assert(
        runsGenerated(
            [[
local record Problem
    message: string
end

local function fetch(n: integer): (integer?, Problem?)
    if n <= 0 then
        return nil, Problem(message = "low")
    end

    return n, nil
end

local function flag(n: integer): (boolean, Problem?)
    if n <= 0 then
        return false, Problem(message = "low")
    end

    return true, nil
end

-- The successful types differ from the wrapper's own; only the forwarded pack
-- has to fit.
local function wrapped(n: integer): (string?, Problem?)
    local value = fetch(n) or return

    return tostring(value), nil
end

local function wrappedFlag(n: integer): (boolean, Problem?)
    local ready = flag(n) or return

    return ready, nil
end

local good, goodProblem = wrapped(2)
local bad, badProblem = wrapped(-1)
local ready, readyProblem = wrappedFlag(-1)

return good == "2"
    and goodProblem == nil
    and bad == nil
    and badProblem ~= nil
    and badProblem.message == "low"
    and ready == false
    and readyProblem ~= nil
]]
        )
    )
end

--- The reason's type is never privileged: the policy reads the pack's width and
--- the first slot's truthiness and nothing else.
function M.anyReasonTypeIsAdmitted()
    for _, reason in ipairs({"string?", "integer?", "Problem?", "Problem | Other | nil", "unknown",}) do
        local source = (
            [[
local record Problem
    message: string
end

local record Other
    code: integer
end

local function source(n: integer): (integer?, %s)
    if n <= 0 then
        return nil, nil
    end

    return n, nil
end

local function wrapped(n: integer): (integer?, %s)
    local value = source(n) or return

    return value, nil
end

return wrapped(1)
]]
        ):format(reason, reason)
        local _, diagnostics = checked(source)
        assertClean(diagnostics, reason)
    end
end

--- A forwarded pack the enclosing signature does not accept reports the way a
--- written return does.
function M.aForwardedPackMustFitTheDeclaredResults()
    assertReports(
        [[
local function source(n: integer): (integer?, integer?)
    return n, n
end

local function wrapped(n: integer): (integer?, string?)
    local value = source(n) or return

    return value, nil
end

return wrapped(1)
]],
        "NUPP2002",
        "an incompatible reason slot"
    )
    assertReports(
        [[
local function source(n: integer): (integer?, integer?, integer?)
    return n, n, n
end

local function wrapped(n: integer): (integer?, integer?)
    local value = source(n) or return

    return value, nil
end

return wrapped(1)
]],
        "NUPP2002",
        "a wider pack than the results"
    )
end

--- Layouts the policy cannot read.
function M.unreadableOperandsReport()
    -- A first result that can never be falsy: the suffix would never exit.
    assertReports(
        "local function always(): integer\n    return 1\nend\n"
        .. "local function f(): integer?\n    local value = always() or return\n    return value\nend\n"
        .. "return f()\n",
        "NUPP2149",
        "never falsy"
    )
    -- A first result that can never be a value: the suffix would always exit.
    assertReports(
        "local function never_(): nil\n    return nil\nend\n"
        .. "local function f(): integer?\n    local value = never_() or return\n    return 1\nend\n"
        .. "return f()\n",
        "NUPP2149",
        "never a value"
    )
    -- An operand with no results at all.
    assertReports(
        "local function nothing(): nil\nend\n"
        .. "local function f(): integer?\n    local value = nothing() or return\n    return 1\nend\n"
        .. "return f()\n",
        "NUPP2149",
        "no value"
    )
    -- An unfixed result count.
    assertReports(
        "local function spread(...: integer): (integer?, ...integer)\n    return 1, ...\nend\n"
        .. "local function f(): integer?\n    local value = spread(1) or return\n    return value\nend\n"
        .. "return f()\n",
        "NUPP2149",
        "an unfixed width"
    )
end

--- Status selects the protected-call branch; the expression yields the payload.
function M.protectedCallsUseStatusAndPreserveFalsySuccesses()
    for _, builtin in ipairs({"pcall", "xpcall"}) do
        do
            local source = (
                [=[
local entered = 0
local function work(n: integer): (false | integer | nil, string)
    if n < 0 then
        error("raised", 0)
    elseif n == 0 then
        return nil, "discarded"
    elseif n == 1 then
        return false, "discarded"
    end
    return n, "discarded"
end
local function handler(problem: any): string
    return tostring(problem)
end
local function wrapped(n: integer): (false | integer | nil, unknown)
    local value = %s or return
    entered = entered + 1
    return value, nil
end
local missing, missingReason = wrapped(0)
local falsy, falseReason = wrapped(1)
local value, reason = wrapped(7)
local failed, problem = wrapped(-1)
local continued, broken = 0, 0
for _, n in ipairs({0, 1, -1, 7}) do
    local _value = %s or continue
    continued = continued + 1
end
for _, n in ipairs({0, 1, -1, 7}) do
    local _value = %s or break
    broken = broken + 1
end
return missing == nil and missingReason == nil and falsy == false and falseReason == nil
    and value == 7 and reason == nil and failed == nil and problem == "raised" and entered == 3 and continued == 3 and broken == 2
]=]
            ):format(
                builtin == "pcall" and "pcall(work, n)" or "xpcall(work, handler, n)",
                builtin == "pcall" and "pcall(work, n)" or "xpcall(work, handler, n)",
                builtin == "pcall" and "pcall(work, n)" or "xpcall(work, handler, n)"
            )
            assert(run(source), builtin .. " answered false")
        end
    end
end

function M.protectedFailurePreservesRaisedIdentityAndNil()
    runsGenerated(
        [=[
local raised = {code = 7}
local entered = 0
local function work(n: integer): integer
    if n == 0 then error(nil) end
    error(raised)
end
local function wrapped(n: integer): (integer?, unknown)
    local value = pcall(work, n) or return
    entered = entered + 1
    return value, nil
end
local first, why = wrapped(1)
local second, empty = wrapped(0)
return first == nil and rawequal(why, raised) and second == nil and empty == nil and entered == 0
]=]
    )
end

function M.protectedCallsPreserveExactHandlerErrorTypes()
    for _, shape in ipairs({"string", "integer", "Problem"}) do
        local source = (
            [=[
local record Problem message: string end
local type Reason = %s
local function work(): integer
    error("raised", 0)
end
local handled = 0
local function handler(problem: any): Reason
    handled = handled + 1
    return %s
end
local function wrapped(): (integer?, Reason?)
    local value = xpcall(work, handler) or return
    return value, nil
end
local value, problem = wrapped()
return value == nil and handled == 1 and %s
]=]
        ):format(
            shape,
            shape == "string" and "tostring(problem)"
            or shape == "integer" and "7"
            or "Problem(message = tostring(problem))",
            shape == "string" and 'problem == "raised"'
            or shape == "integer" and "problem == 7"
            or 'problem ~= nil and problem.message == "raised"'
        )
        runsGenerated(source)
    end
    assertReports(
        [=[
local function work(): integer return 1 end
local function wrapped(): (integer?, string?)
    local value = pcall(work) or return
    return value, nil
end
]=],
        "NUPP2002",
        "unknown failure cannot be implicitly narrowed"
    )
    assertReports(
        [=[
local function work(): integer? return nil end
local function wrapped(): (integer?, unknown)
    local value = pcall(work) or return
    local exact: integer = value
    return exact, nil
end
]=],
        "NUPP2001",
        "a successful optional result is still optional"
    )
end

function M.protectedCallsRunOperandAndArgumentsOnce()
    runsGenerated(
        [=[
local chosen, supplied, called = 0, 0, 0
local function work(n: integer): integer
    called = called + 1
    if n == 0 then error("zero", 0) end
    return n
end
local function choose(): function(integer): integer
    chosen = chosen + 1
    return work
end
local function argument(n: integer): integer
    supplied = supplied + 1
    return n
end
local function wrapped(n: integer): (integer?, unknown)
    local value = pcall(choose(), argument(n)) or return
    return value, nil
end
local good = wrapped(4)
local bad = wrapped(0)
return good == 4 and bad == nil and chosen == 2 and supplied == 2 and called == 2
]=]
    )
end

function M.protectedLoopExitsAndCleanupUseStatus()
    for _, builtin in ipairs({"pcall", "xpcall"}) do
        local source = (
            [=[
local closed = 0
local record Resource is own.Closeable
    function close(takes self): nil closed = closed + 1 end
end
local function work(n: integer): integer
    local resource = Resource()
    if n == 0 then error("zero", 0) end
    return n
end
local function handler(problem: any): string return tostring(problem) end
local function wrapped(n: integer): (integer?, unknown)
    local resource = Resource()
    local value = %s or return
    return value, nil
end
local good = wrapped(2)
local bad = wrapped(0)
local continued = 0
for _, n in ipairs({1, 0, 2}) do
    local resource = Resource()
    local value = %s or continue
    continued = continued + value
end
local broken = 0
for _, n in ipairs({1, 0, 2}) do
    local resource = Resource()
    local value = %s or break
    broken = broken + value
end
return good == 2 and bad == nil and continued == 3 and broken == 1 and closed == 14
]=]
        ):format(
            builtin == "pcall" and "pcall(work, n)" or "xpcall(work, handler, n)",
            builtin == "pcall" and "pcall(work, n)" or "xpcall(work, handler, n)",
            builtin == "pcall" and "pcall(work, n)" or "xpcall(work, handler, n)"
        )
        runsGenerated(source)
    end
end

function M.protectedCallsKeepAnOwnedFirstResultAndRejectDiscardedOwners()
    runsGenerated(
        [=[
local closed = 0
local record Resource is own.Closeable
    id: integer
    function close(takes self): nil closed = closed + 1 end
end
local function open(n: integer): Resource
    if n == 0 then error("zero", 0) end
    return Resource(id = n)
end
local function wrapped(n: integer): (integer?, unknown)
    local resource = pcall(open, n) or return
    return resource.id, nil
end
local good = wrapped(4)
local bad = wrapped(0)
return good == 4 and bad == nil and closed == 1
]=]
    )
    assertReports(
        [=[
local record Resource is own.Closeable
    function close(takes self): nil end
end
local function paired(): (integer, Resource) return 1, Resource() end
local function wrapped(): (integer?, unknown)
    local value = pcall(paired) or return
    return value, nil
end
]=],
        "NUPP2605",
        "protected success cannot abandon an extra owner"
    )
end

function M.protectedHandlerOwnersMustBeForwardedOrConsumed()
    local setup = [=[
local closed = 0
local record Problem is own.Closeable
    function close(takes self): nil closed = closed + 1 end
end
local function work(): integer error("raised", 0) end
local function handler(problem: any): Problem return Problem() end
]=]
    runsGenerated(
        setup
        .. [=[
local function wrapped(): (integer?, Problem?)
    local value = xpcall(work, handler) or return
    return value, nil
end
local value, problem = wrapped()
if problem ~= nil then own.drop(problem) end
return value == nil and closed == 1
]=]
    )
    for _, exit in ipairs({"break", "continue"}) do
        assertReports(
            setup .. "for _ = 1, 2 do\nlocal value = xpcall(work, handler) or " .. exit .. "\nprint(value)\nend\n",
            "NUPP2605",
            "a handler's owner cannot be discarded by " .. exit
        )
    end
    for _, destination in ipairs({"any", "unknown"}) do
        assertReports(
            setup
            .. "local function wrapped(): (integer?, "
            .. destination
            .. ")\n"
            .. "local value = xpcall(work, handler) or return\nreturn value, nil\nend\n",
            destination == "any" and "NUPP2611" or "NUPP2603",
            "a handler's owner cannot be erased into " .. destination
        )
    end
end

function M.protectedCallsAdmitNoResultsAndVariadicPlainResults()
    runsGenerated(
        [=[
local visited = 0
local function nothing(): nil end
local function spread(...: integer): (integer, ...integer) return 7, ... end
local function wrapped(): (integer?, unknown)
    local empty = pcall(nothing) or return
    visited = visited + 1
    local first = pcall(spread, 1, 2, 3) or return
    return first, nil
end
return wrapped() == 7 and visited == 1
]=]
    )
end

function M.shadowedProtectedCallsCannotSelectTheBuiltinPolicy()
    assertReports(
        [=[
local function pcall(): ((true, integer) | (false, string)) return true, 7 end
local function wrapped(): (integer?, unknown)
    local value = pcall() or return
    return value, nil
end
]=],
        "NUPP2149",
        "a user function with a correlated pack is not builtin pcall"
    )
end

--- A project's own `pcall` is an ordinary operand: it answers an ordinary pack,
--- so nothing recognizes it as the built-in.
function M.aUserDefinedPcallIsOrdinary()
    local _, diagnostics = checked(
        [[
local function pcall(n: integer): (integer?, string?)
    if n <= 0 then
        return nil, "low"
    end

    return n, nil
end

local function f(n: integer): (integer?, string?)
    local value = pcall(n) or return

    return value, nil
end

return f(1)
]]
    )
    assertClean(diagnostics, "a project's own pcall")
end

--- Every slot after the first is dropped on the successful path, so an owner in
--- one of them is abandoned there.
function M.anOwnerAfterTheFirstSlotIsRefused()
    assertReports(
        [[
local record Resource
    id: integer
end

local function closeResource(takes value: Resource): nil
end

local function paired(n: integer): (integer?, affine(Resource, closeResource))
    return n, Resource(id = n)
end

local function f(n: integer): integer?
    local value = paired(n) or return

    return value
end

return f(1)
]],
        "NUPP2605",
        "an owner in a discarded slot"
    )
end

--- Safe navigation adds one alternative to the operand's pack -- the single nil
--- an absent receiver answers with -- and that arm takes the exit. The suffix
--- cannot tell an absent receiver from a failed read, which is the conflation an
--- explicit `if` over a safe call already has.
function M.aSafeCallIsAnAdmittedOperand()
    assert(
        runsGenerated(
            [[
local record Source
    id: integer

    function read(self, n: integer): (integer?, string?)
        if n <= 0 then
            return nil, "low"
        end

        return n + self.id, nil
    end
end

local function via(source: Source?, n: integer): (integer?, string?)
    local value = source?.:read(n) or return

    return value, nil
end

local present, presentReason = via(Source(id = 1), 2)
local absent, absentReason = via(nil, 2)
local failed, failedReason = via(Source(id = 1), -1)

return present == 3
    and presentReason == nil
    and absent == nil
    and absentReason == nil
    and failed == nil
    and failedReason == "low"
]]
        )
    )
end

--- A binding list taking two names from a suffix always binds nil in the
--- second, which the lint says rather than the checker.
function M.aSecondBoundNameIsLinted()
    local diagnostic = assertReports(
        [[
local function pair(n: integer): (integer?, integer?)
    if n <= 0 then
        return nil, nil
    end

    return n, n + 1
end

local function f(n: integer): (integer?, integer?)
    local left, right = pair(n) or return

    return left, right
end

return f(1)
]],
        "NUPP2517",
        "a second bound name"
    )
    assert(diagnostic.severity == "warning", diagnostic.severity)
end

--- A constructor returns the instance it builds and has no failure pack to
--- forward, and a declared module has no top-level return at all.
function M.constructorsAndDeclaredModulesRefuseTheReturn()
    assertReports(
        [[
local function source(n: integer): (integer?, string?)
    if n <= 0 then
        return nil, "low"
    end

    return n, nil
end

local record Box
    value: integer

    constructor(self, n: integer)
        local found = source(n) or return
        self.value = found
    end
end

return Box(1)
]],
        "NUPP2208",
        "a constructor"
    )
end

--- Loop-exit analysis sees the suffix, so a `while true` a suffix can leave
--- still lets the code after it run.
function M.reachabilityAfterALoopTheSuffixCanLeave()
    local _, diagnostics = checked(
        [[
local function source(n: integer): (integer?, string?)
    if n <= 0 then
        return nil, "low"
    end

    return n, nil
end

local function countdown(): integer
    local total: integer, n: integer = 0, 3
    while true do
        local value = source(n) or break
        total = total + value
        n = n - 1
    end

    return total
end

return countdown()
]]
    )
    assertClean(diagnostics, "code after a while true the suffix can leave")
end

---------------------------------------------------------------------------
-- Runtime and lowering
---------------------------------------------------------------------------

--- The operand and its prefixes run exactly once, and a short-circuited operand
--- does not run at all.
function M.theOperandRunsOnceAndOnlyWhenSelected()
    assert(
        runsGenerated(
            [[
local calls: integer, receivers: integer = 0, 0

local record Source
    id: integer

    function read(self, n: integer): (integer?, string?)
        calls = calls + 1
        if n <= 0 then
            return nil, "low"
        end

        return n, nil
    end
end

local function receiver(): Source
    receivers = receivers + 1

    return Source(id = 1)
end

local function once(n: integer): (integer?, string?)
    local value = receiver():read(n) or return

    return value, nil
end

local answer = once(3)
local shortCircuited = true or (once(5) or false)

return answer == 3 and calls == 1 and receivers == 1 and shortCircuited == true
]]
        )
    )
end

--- Failure forwarding preserves false, embedded nils and the trailing reason,
--- and `nil, nil` still takes the exit because the primary is nil.
function M.failureForwardingPreservesTheWholePack()
    assert(
        runsGenerated(
            [[
local function holes(n: integer): (integer?, string?, string?)
    if n <= 0 then
        return nil, nil, "trailing"
    end

    return n, nil, nil
end

local function wrapped(n: integer): (integer?, string?, string?)
    local value = holes(n) or return

    return value, "middle", nil
end

local function bothNil(n: integer): (integer?, string?)
    return nil, nil
end

local function exits(n: integer): (integer?, string?)
    -- `nil, nil` still takes the exit: the primary decides, not the reason.
    local value = bothNil(n) or return

    return value + 1, "unreachable"
end

local good, goodMiddle, goodTrailing = wrapped(1)
local bad, badMiddle, badTrailing = wrapped(-1)
local exited, exitedReason = exits(1)

return exited == nil
    and exitedReason == nil
    and good == 1
    and goodMiddle == "middle"
    and goodTrailing == nil
    and bad == nil
    and badMiddle == nil
    and badTrailing == "trailing"
]]
        )
    )
end

--- Each loop exit reaches its own target through nesting, and a `repeat`
--- condition keeps the target the generator already gives a lowered condition.
function M.loopExitsReachTheirOwnTarget()
    assert(
        runsGenerated(
            [[
local function source(n: integer): (integer?, string?)
    if n <= 0 then
        return nil, "low"
    end

    return n, nil
end

local inner, outer = 0, 0
for i = 1, 3 do
    outer = outer + 1
    for j = 1, 3 do
        local value = source(3 - j) or break
        inner = inner + value
    end
end

local skipped = 0
for _, n in ipairs({1, 0, 2, 0, 3}) do
    local value = source(n) or continue
    skipped = skipped + value
end

local rounds = 0
for i = 1, 2 do
    repeat
        rounds = rounds + 1
    until (source(i) or break) == i
end

return outer == 3 and inner == 9 and skipped == 6 and rounds == 2
]]
        )
    )
end

--- Cleanup runs exactly once on every exit, the way it does for the statements.
function M.cleanupRunsOnEveryExit()
    assert(
        runsGenerated(
            [[
local closed = 0

local record Resource
    id: integer
end

local function closeResource(takes value: Resource): nil
    closed = closed + 1
end

local function openResource(id: integer): affine(Resource, closeResource)
    return Resource(id = id)
end

local function source(n: integer): (integer?, string?)
    if n <= 0 then
        return nil, "low"
    end

    return n, nil
end

local function leaves(n: integer): (integer?, string?)
    local resource = openResource(n)
    local value = source(n) or return

    return value + resource.id, nil
end

local good = leaves(2)
local bad = leaves(-1)

local looped = 0
for _, n in ipairs({1, 0, 2}) do
    local resource = openResource(n)
    local value = source(n) or continue
    looped = looped + value + resource.id
end

return good == 4 and bad == nil and looped == 6 and closed == 5
]]
        )
    )
end

--- A suffix inside a do expression still leaves the enclosing function, and the
--- loop exits keep their loop targets through one.
function M.aDoExpressionDoesNotCaptureTheExit()
    assert(
        runsGenerated(
            [[
local function source(n: integer): (integer?, string?)
    if n <= 0 then
        return nil, "low"
    end

    return n, nil
end

local function doubled(n: integer): (integer?, string?)
    local value = do
        local inner = source(n) or return
        yield inner * 2
    end

    return value, nil
end

local collected = 0
for _, n in ipairs({1, 0, 2}) do
    local value = do
        local inner = source(n) or continue
        yield inner * 10
    end
    collected = collected + value
end

return doubled(3) == 6 and doubled(-1) == nil and collected == 30
]]
        )
    )
end

--- An operand in a loop condition and in an argument list goes through the
--- generator's block-condition and argument lowering.
function M.conditionsAndArgumentListsLower()
    assert(
        runsGenerated(
            [[
local function source(n: integer): (integer?, string?)
    if n <= 0 then
        return nil, "low"
    end

    return n, nil
end

local function add(a: integer, b: integer): integer
    return a + b
end

local total: integer = 0
for _ = 1, 1 do
    local n: integer = 3
    while (source(n) or break) > 1 do
        total = total + n
        n = n - 1
    end
end

local function inArguments(n: integer): (integer?, string?)
    return add(source(n) or return, 10), nil
end

return total == 5 and inArguments(1) == 11 and inArguments(-1) == nil
]]
        )
    )
end

--- Comptime runs the same branch.
function M.comptimeTakesTheSameBranch()
    assert(
        runsGenerated(
            [[
const chosen = comptime do
    local found: integer? = 3
    local value = found or return

    return value * 2
end

const missing = comptime do
    local absent: integer? = nil
    local value = absent or return

    return value * 2
end

return chosen == 6 and missing == nil
]]
        )
    )
end

---------------------------------------------------------------------------
-- Explicit protected calls
---------------------------------------------------------------------------

function M.protectedBuiltinsPreserveRaisedValuesAndNilResults()
    local function work(n)
        if n < 0 then
            error("negative")
        end

        return n * 2
    end

    local ok, value = pcall(work, 4)
    assert(ok and value == 8, tostring(value))
    ok, value = pcall(work, -1)
    assert(not ok and tostring(value):find("negative", 1, true), tostring(value))

    local raised = {code = 7}
    ok, value = pcall(error, raised, 0)
    assert(not ok and rawequal(value, raised), "a raised object keeps its identity")

    ok, value = pcall(error, nil)
    assert(not ok and value == nil, "raising nil remains a failure")
    ok, value = pcall(function()
        return nil
    end)
    assert(ok and value == nil, "a successful nil remains distinguishable")

    local workIsOnStack = false
    ok, value = xpcall(
        work,
        function(problem)
            local level = 2
            while true do
                local info = debug.getinfo(level, "f")
                if not info then
                    break
                end
                if info.func == work then
                    workIsOnStack = true
                    break
                end
                level = level + 1
            end

            return {message = tostring(problem)}
        end,
        -1
    )
    assert(not ok and type(value) == "table", tostring(value))
    assert(value.message:find("negative", 1, true), value.message)
    assert(workIsOnStack, "the handler ran before the stack unwound")
end

--- A local explicit protected call exposes an `unknown` reason; narrowing it
--- at the hop is what is refused.
function M.propagatingAnUnknownReasonChecks()
    local _, diagnostics = checked(
        [[
local function work(n: integer): integer
    return n * 2
end

local function called(n: integer): (integer?, unknown)
    local ok, value = pcall(work, n)
    if ok then
        return value, nil
    end

    return nil, value
end

local function propagated(n: integer): (integer?, unknown)
    local value = called(n) or return

    return value + 1, nil
end

return propagated(1)
]]
    )
    assertClean(diagnostics)
    assertReports(
        [[
local function work(n: integer): integer
    return n * 2
end

local function called(n: integer): (integer?, unknown)
    local ok, value = pcall(work, n)
    if ok then
        return value, nil
    end

    return nil, value
end

local function narrowed(n: integer): (integer?, string?)
    local value = called(n) or return

    return value + 1, nil
end

return narrowed(1)
]],
        "NUPP2002",
        "narrowing unknown at the hop"
    )
end

--- A handler's own result type reaches the caller, whatever it is.
function M.aHandlerResultTypeReachesTheCaller()
    for _, shape in ipairs({"string", "integer", "Problem"}) do
        local source = (
            [[
local record Problem
    message: string
end
local type Reason = %s

local function work(n: integer): integer
    return n * 2
end

local function handler(raised: any): Reason
    return %s
end

local function called(n: integer): (integer?, Reason?)
    local ok, value = xpcall(work, handler, n)
    if ok then
        return value, nil
    end

    return nil, value
end

local function described(n: integer): (integer?, Reason?)
    local value = called(n) or return

    return value + 1, nil
end

return described(1)
]]
        ):format(
            shape,
            shape == "string" and "tostring(raised)"
            or shape == "integer" and "1"
            or "Problem(message = tostring(raised))"
        )
        local _, diagnostics = checked(source)
        assertClean(diagnostics, shape)
    end
end

return M
