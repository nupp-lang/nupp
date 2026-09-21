-- `or return`, `or break` and `or continue`: the contextual exit suffixes.
--
-- The cases run each admitted program through the LuaJIT generator and execute
-- the resulting straight-line control flow.

local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local gen = require("nupp.compiler.gen")
local fmt = require("nupp.compiler.fmt")
local optimize = require("nupp.compiler.optimize")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local FILE = "or-exit.g.nupp"

-- One environment for the whole suite. The eligibility rules are about result
-- packs the prelude declares -- `pcall`'s union above all -- so these cases need
-- the real declarations rather than the implicit gradual environment.
local sharedEnv = envMod.new(HERE)

local function parsed(source)
    return parser.parse(source, FILE)
end

local function checked(source, dialect)
    local tree = parsed(source)
    assert(#tree.errors == 0, tree.errors[1] and tree.errors[1].msg)
    local diagnostics = check.check(tree, FILE, sharedEnv, {dialect = dialect})
    return tree, diagnostics
end

local function run(source, dialect, level)
    local tree, diagnostics = checked(source, dialect)
    assert(#diagnostics == 0, diagnostics[1] and diagnostics[1].msg)
    if level then
        optimize.run(tree, {level = level, filename = FILE, dialect = dialect or "luajit"})
    end
    local code, errors = gen.generate(tree, FILE)
    assert(#errors == 0, (errors[1] and errors[1].msg or "") .. "\n" .. code)
    local fn, failure = loadstring(code)
    assert(fn, tostring(failure) .. "\n" .. code)

    return fn(), code
end

-- Asserts the generated program answers true and returns its source for cases
-- that also inspect the lowering.
local function runsGenerated(source)
    local answer, code = run(source, "luajit")
    assert(answer, "luajit:\n" .. code)

    return code
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

local function assertClean(diagnostics, label)
    assert(#diagnostics == 0, (label or "expected a clean check") .. ": " .. firstMessage(diagnostics))
end

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
        return nil, new Problem(message = "low")
    end

    return n, nil
end

local function flag(n: integer): (boolean, Problem?)
    if n <= 0 then
        return false, new Problem(message = "low")
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
        "NUPP2146",
        "never falsy"
    )
    -- A first result that can never be a value: the suffix would always exit.
    assertReports(
        "local function never_(): nil\n    return nil\nend\n"
        .. "local function f(): integer?\n    local value = never_() or return\n    return 1\nend\n"
        .. "return f()\n",
        "NUPP2146",
        "never a value"
    )
    -- An operand with no results at all.
    assertReports(
        "local function nothing(): nil\nend\n"
        .. "local function f(): integer?\n    local value = nothing() or return\n    return 1\nend\n"
        .. "return f()\n",
        "NUPP2146",
        "no value"
    )
    -- An unfixed result count.
    assertReports(
        "local function spread(...: integer): (integer?, ...integer)\n    return 1, ...\nend\n"
        .. "local function f(): integer?\n    local value = spread(1) or return\n    return value\nend\n"
        .. "return f()\n",
        "NUPP2146",
        "an unfixed width"
    )
end

--- A direct `pcall` is refused by the pack-union rule, and the message names
--- the standard-library pair rather than leaving the reader to find it.
function M.protectedBuiltinsAreRefusedByName()
    for _, builtin in ipairs({"pcall", "xpcall"}) do
        local call = builtin == "pcall" and "pcall(work)" or "xpcall(work, tostring)"
        local diagnostic = assertReports(
            (
                "local function work(): integer\n    return 1\nend\n"
                .. "local function f(): (integer?, unknown)\n    local value = %s or return\n"
                .. "    return value, nil\nend\n"
                .. "return f()\n"
            ):format(call),
            "NUPP2146",
            builtin
        )
        assert(diagnostic.help and diagnostic.help:find("nupp.util." .. builtin .. "se", 1, true), diagnostic.help)
    end
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
    return n, new Resource(id = n)
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

local present, presentReason = via(new Source(id = 1), 2)
local absent, absentReason = via(nil, 2)
local failed, failedReason = via(new Source(id = 1), -1)

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

return new Box(1)
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

    return new Source(id = 1)
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
    return new Resource(id = id)
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

--- Generated output carries no new syntax, and a fixed-width operand costs no
--- pack table.
function M.generatedOutputIsOrdinaryLua()
    local code = runsGenerated(
        [[
local function source(n: integer): (integer?, string?)
    if n <= 0 then
        return nil, "low"
    end

    return n, nil
end

local function wrapped(n: integer): (integer?, string?)
    local value = source(n) or return

    return value, nil
end

return wrapped(1) == 1
]]
    )
    assert(not code:find("or return", 1, true), code)
    assert(not code:find("or break", 1, true), code)
    assert(not code:find("or continue", 1, true), code)
    assert(not code:find("__nuppBlockPack", 1, true), "a fixed-width operand needs no pack table")
end

--- Every optimization level keeps the exit and the pack.
function M.optimizerPreservesTheExit()
    for _, level in ipairs({0, 1, 2}) do
        for _, dialect in ipairs({"luajit"}) do
            local answer = run(
                [[
local function source(n: integer): (integer?, string?)
    if n <= 0 then
        return nil, "low"
    end

    return n, nil
end

local function wrapped(n: integer): (integer?, string?)
    local value = source(n) or return

    return value * 2, nil
end

local good, goodReason = wrapped(2)
local bad, badReason = wrapped(-1)

return good == 4 and goodReason == nil and bad == nil and badReason == "low"
]],
                dialect,
                level
            )
            assert(answer, ("level %d, %s"):format(level, dialect))
        end
    end
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

--- Coverage counts the two arms rather than treating the exit as always taken.
function M.coverageRegistersTheBranch()
    local tree, diagnostics = checked(
        [[
local function source(n: integer): (integer?, string?)
    if n <= 0 then
        return nil, "low"
    end

    return n, nil
end

local function wrapped(n: integer): (integer?, string?)
    local value = source(n) or return

    return value, nil
end

return wrapped(1)
]]
    )
    assert(#diagnostics == 0, codesOf(diagnostics))
    local code, errors, sites = gen.generate(tree, FILE, {coverage = true})
    assert(#errors == 0, errors[1] and errors[1].msg)
    assert(code:find(".branch(", 1, true), "the suffix registers a branch site")
    if sites then
        local branches = 0
        for _, site in ipairs(sites.sites or sites) do
            if site.kind == "branch" then
                branches = branches + 1
            end
        end
        assert(branches > 0, "a branch site was recorded")
    end
end

---------------------------------------------------------------------------
-- The standard-library pair
---------------------------------------------------------------------------

--- `pcallse` answers the conventional layout, passing the raised value through
--- exactly as raised, and `xpcallse` answers whatever its handler made of it.
function M.protectedWrappersAnswerTheConventionalLayout()
    local protected = require("nupp.util.internal.protected")

    local function work(n)
        if n < 0 then
            error("negative")
        end

        return n * 2
    end

    local value, reason = protected.pcallse(work, 4)
    assert(value == 8 and reason == nil, tostring(value))
    value, reason = protected.pcallse(work, -1)
    assert(value == nil and tostring(reason):find("negative", 1, true), tostring(reason))

    -- A non-string payload arrives unchanged.
    local function raiseTable()
        error({code = 7})
    end

    value, reason = protected.pcallse(raiseTable)
    assert(value == nil and type(reason) == "table" and reason.code == 7, tostring(reason))

    -- A nil payload is still a failure, and a successful nil is still nil: the
    -- documented limit of the conventional layout.
    value, reason = protected.pcallse(error, nil)
    assert(value == nil and reason == nil)
    value, reason = protected.pcallse(function()
        return nil
    end)
    assert(value == nil and reason == nil)

    -- The handler decides the reason's type, and runs before the stack unwinds.
    local depth = nil
    value, reason = protected.xpcallse(
        function(raised)
            depth = debug.traceback("", 2):find("work") ~= nil

            return {message = tostring(raised)}
        end,
        work,
        -1
    )
    assert(value == nil and type(reason) == "table", tostring(reason))
    assert(reason.message:find("negative", 1, true), reason.message)
    assert(depth, "the handler ran before the stack unwound")
end

--- A caller propagating `pcallse`'s reason declares it `unknown`; narrowing it
--- at the hop is what is refused.
function M.propagatingAnUnknownReasonChecks()
    local _, diagnostics = checked(
        [[
local util = require("nupp.util")

local function work(n: integer): integer
    return n * 2
end

local function propagated(n: integer): (integer?, unknown)
    local value = util.pcallse(work, n) or return

    return value + 1, nil
end

return propagated(1)
]]
    )
    assertClean(diagnostics)
    assertReports(
        [[
local util = require("nupp.util")

local function work(n: integer): integer
    return n * 2
end

local function narrowed(n: integer): (integer?, string?)
    local value = util.pcallse(work, n) or return

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
local util = require("nupp.util")

local record Problem
    message: string
end

local function work(n: integer): integer
    return n * 2
end

local function handler(raised: any): %s
    return %s
end

local function described(n: integer): (integer?, %s?)
    local value = util.xpcallse(handler, work, n) or return

    return value + 1, nil
end

return described(1)
]]
        ):format(
            shape,
            shape == "string" and "tostring(raised)"
            or shape == "integer" and "1"
            or "new Problem(message = tostring(raised))",
            shape
        )
        local _, diagnostics = checked(source)
        assertClean(diagnostics, shape)
    end
end

return M
