local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local gen = require("nupp.compiler.lua.gen")

local function checked(source)
    local result = parser.parse(source, "switch-test.g.nupp")
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "switch source parses")
    local diagnostics = check.check(result, "switch-test.g.nupp")
    return result, diagnostics
end

local function diagnosticCodes(source)
    local _, diagnostics = checked(source)
    local codes = {}
    for _, diagnostic in ipairs(diagnostics) do
        codes[#codes + 1] = diagnostic.code
    end

    return table.concat(codes, " "), diagnostics
end

local function run(source)
    local result, diagnostics = checked(source)
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].message or "switch source checks")
    local code, lowering = gen.generate(result, "switch-test.g.nupp")
    testAssert.equal(#lowering, 0, lowering[1] and lowering[1].msg or "switch source lowers")
    local chunk, failure = loadstring(code, "@switch_test")
    if not chunk then
        error("generated switch code does not load: " .. tostring(failure) .. "\n---\n" .. code, 2)
    end

    return chunk()
end

local function generate(source, coverage)
    local result, diagnostics = checked(source)
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].message or "switch source checks")
    local code, lowering = gen.generate(result, "switch-test.g.nupp", coverage)
    testAssert.equal(#lowering, 0, lowering[1] and lowering[1].msg or "switch source lowers")

    return code, result
end

local function loweringCodes(source)
    local result, diagnostics = checked(source)
    testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].message or "switch source checks before lowering")
    local _, lowering = gen.generate(result, "switch-test.g.nupp")
    local codes = {}
    for _, diagnostic in ipairs(lowering) do
        codes[#codes + 1] = diagnostic.code
    end

    return table.concat(codes, " ")
end

local M = {}

-- `any` fits every case without any case covering it, so a switch over an `any`
-- selector keeps its `else` and needs one, as the reference says of open types.
function M.aGradualSelectorNeedsItsElse()
    local record = "local record R\n    v: integer\nend\n"
    testAssert.equal(
        run(record .. table.concat({
            "local function f(x: any): integer",
            "    return switch x do",
            "        case is R as r -> r.v",
            "        else -> 0",
            "    end",
            "end",
            "return f(new R(v = 3)) + f(2)",
        }, "\n")),
        3
    )
    testAssert.equal(
        run("local function g(x: any): string\n    return switch x do\n        case 1 -> 'one'\n        else -> 'other'\n    end\nend\nreturn g(1) .. g(2)"),
        "oneother"
    )
    testAssert.equal(
        (diagnosticCodes(record .. "local function f(x: any): integer\n    return switch x do\n        case is R as r -> r.v\n    end\nend\nreturn f")),
        "NUPP2140"
    )
end

function M.staticCasesAreExhaustiveAndRun()
    local first, second, third = run(
        table.concat(
            {
                "local type Status = 200 | 301 | 302",
                "local function label(status: Status): string",
                "   return switch status do",
                "      case 200 -> 'ok'",
                "      case 301, 302 -> 'redirect'",
                "   end",
                "end",
                "return label(200), label(301), label(302)",
            },
            "\n"
        )
    )
    testAssert.equal(first, "ok")
    testAssert.equal(second, "redirect")
    testAssert.equal(third, "redirect")
end

function M.aDiscriminantCaseNarrowsTheValueItBelongsTo()
    -- `case "circle"` on `s.kind` selects the members of `s` whose `kind` admits
    -- it, the way `if s.kind == "circle"` does, through a copy of the field too.
    local SHAPES = table.concat(
        {
            "local record Circle",
            "   kind: 'circle'",
            "   radius: number",
            "end",
            "local record Square",
            "   kind: 'square'",
            "   side: number",
            "end",
            "local type Shape = Circle | Square",
        },
        "\n"
    )
    local direct, copied = run(
        SHAPES .. table.concat(
            {
                "",
                "local function direct(s: Shape): number",
                "   return switch s.kind do",
                "      case 'circle' -> s.radius",
                "      case 'square' -> s.side",
                "   end",
                "end",
                "local function copied(s: Shape): number",
                "   local kind = s.kind",
                "   return switch kind do",
                "      case 'circle' -> s.radius",
                "      case 'square' -> s.side",
                "   end",
                "end",
                "local square = new Square(kind = 'square', side = 4)",
                "return direct(square), copied(square)",
            },
            "\n"
        )
    )
    testAssert.equal(direct, 4)
    testAssert.equal(copied, 4)
    -- A member the case does not select is still out of reach.
    local codes = diagnosticCodes(
        SHAPES .. table.concat(
            {
                "",
                "local function wrong(s: Shape): number",
                "   return switch s.kind do",
                "      case 'circle' -> s.side",
                "      case 'square' -> s.radius",
                "   end",
                "end",
            },
            "\n"
        )
    )
    assert(codes:match("^NUPP2004[ NUPP2004]*$"), "only missing fields: " .. codes)
end

function M.typeBindingsAndDestructuringRun()
    local circle, text = run(
        table.concat(
            {
                "local record Circle",
                "   radius: integer",
                "end",
                "local function measure(value: Circle | string): integer",
                "   return switch value do",
                "      case is Circle as whole {radius} -> radius + whole.radius",
                "      case is string as contents -> #contents",
                "   end",
                "end",
                "return measure(new Circle(radius = 4)), measure('abc')",
            },
            "\n"
        )
    )
    testAssert.equal(circle, 8)
    testAssert.equal(text, 3)
end

function M.blockArmsYieldWithoutChangingReturn()
    local one, other, early = run(
        table.concat(
            {
                "local function describe(value: integer): string",
                "   return switch value do",
                "      case 0 -> do",
                "         return 'early'",
                "      end",
                "      case 1 -> do",
                "         local answer = 'one'",
                "         yield answer",
                "      end",
                "      else -> 'other'",
                "   end",
                "end",
                "return describe(1), describe(2), describe(0)",
            },
            "\n"
        )
    )
    testAssert.equal(one, "one")
    testAssert.equal(other, "other")
    testAssert.equal(early, "early")
end

function M.staticExpressionArmsWorkAtComptime()
    local selected = run(
        table.concat(
            {
                "const selected: string = comptime do",
                "   local code = 302",
                "   return switch code do",
                "      case 200 -> 'ok'",
                "      case 301, 302 -> 'redirect'",
                "      else -> 'other'",
                "   end",
                "end",
                "return selected",
            },
            "\n"
        )
    )
    testAssert.equal(selected, "redirect")
end

function M.liftingPreservesEagerEvaluationOrder()
    local order, value = run(
        table.concat(
            {
                "local events: {string} = {}",
                "local function mark(name: string, value: integer): integer",
                "   events[#events + 1] = name",
                "   return value",
                "end",
                "local function add(a: integer, b: integer, c: integer): integer",
                "   return a + b + c",
                "end",
                "local value = add(mark('left', 1), switch mark('selector', 2) do",
                "   case 2 -> mark('arm', 2)",
                "   else -> 0",
                "end, mark('right', 3))",
                "return table.concat(events, ','), value",
            },
            "\n"
        )
    )
    testAssert.equal(order, "left,selector,arm,right")
    testAssert.equal(value, 6)
end

function M.liftingPreservesAssignmentTargetOrder()
    local order, value = run(
        table.concat(
            {
                "local events: {string} = {}",
                "local row = {value = 0}",
                "local function target(): {value: integer}",
                "   events[#events + 1] = 'target'",
                "   return row",
                "end",
                "local function selector(): integer",
                "   events[#events + 1] = 'selector'",
                "   return 1",
                "end",
                "target().value = switch selector() do",
                "   case 1 -> 9",
                "   else -> 0",
                "end",
                "return table.concat(events, ','), row.value",
            },
            "\n"
        )
    )
    testAssert.equal(order, "target,selector")
    testAssert.equal(value, 9)
end

function M.yieldCompletesCleanupBeforeTheSwitchContinues()
    local value, events = run(
        table.concat(
            {
                "local events = ''",
                "local record Resource",
                "   name: string",
                "end",
                "local function closeResource(takes value: Resource): nil",
                "   events = events .. 'close'",
                "end",
                "local function openResource(): affine(Resource, closeResource)",
                "   return new Resource(name = 'selected')",
                "end",
                "local value = switch 1 do",
                "   case 1 -> do",
                "      with resource = openResource() do",
                "         yield resource.name",
                "      end",
                "   end",
                "end",
                "events = events .. ',after'",
                "return value, events",
            },
            "\n"
        )
    )
    testAssert.equal(value, "selected")
    testAssert.equal(events, "close,after")
end

function M.nestedSwitchesStayAtTheirStatementBoundary()
    local order, value = run(
        table.concat(
            {
                "local events: {string} = {}",
                "local function mark(name: string, value: integer): integer",
                "   events[#events + 1] = name",
                "   return value",
                "end",
                "local value = switch mark('outer', 1) do",
                "   case 1 -> do",
                "      mark('before-inner', 0)",
                "      local inner = switch mark('inner', 2) do",
                "         case 2 -> 8",
                "         else -> 0",
                "      end",
                "      yield inner",
                "   end",
                "   else -> 0",
                "end",
                "return table.concat(events, ','), value",
            },
            "\n"
        )
    )
    testAssert.equal(order, "outer,before-inner,inner")
    testAssert.equal(value, 8)
end

function M.lazyPlacementIsSupported()
    local codes = loweringCodes(
        table.concat(
            {
                "local ready = true",
                "local selector: number = 1",
                "local value = ready and switch selector do",
                "   case 1 -> 1",
                "   else -> 0",
                "end",
            },
            "\n"
        )
    )
    testAssert.equal(codes, "")
end

function M.coverageCountsTestsAndSelectedArmRegions()
    local result, diagnostics = checked(
        table.concat(
            {
                "local selector: number = 1",
                "local value = switch selector do",
                "   case 1 -> 'one'",
                "   case 2 -> 'two'",
                "   else -> 'other'",
                "end",
                "return value",
            },
            "\n"
        )
    )
    testAssert.equal(#diagnostics, 0)
    local _, lowering, coverage = gen.generate(result, "switch-coverage.g.nupp", true)
    testAssert.equal(#lowering, 0)
    local branches, regions = 0, 0
    for _, site in ipairs(coverage.sites) do
        if site.kind == "branch" then
            branches = branches + 1
        end
        if site.kind == "statement" and site.line >= 3 and site.line <= 5 then
            regions = regions + 1
        end
    end
    testAssert.equal(branches, 2)
    testAssert.equal(regions, 3)
end

function M.denseIntegerMapsHandleEveryKindOfMiss()
    local one, four, fraction, negative, far, nan, infinity = run(
        table.concat(
            {
                "local function classify(value: number): string",
                "   return switch value do",
                "      case 1 -> 'one'",
                "      case 2 -> 'two'",
                "      case 3 -> 'three'",
                "      case 4 -> 'four'",
                "      else -> 'miss'",
                "   end",
                "end",
                "return classify(1), classify(4), classify(1.5), classify(-1),",
                "   classify(1000), classify(0 / 0), classify(math.huge)",
            },
            "\n"
        )
    )
    testAssert.equal(one, "one")
    testAssert.equal(four, "four")
    testAssert.equal(fraction, "miss")
    testAssert.equal(negative, "miss")
    testAssert.equal(far, "miss")
    testAssert.equal(nan, "miss")
    testAssert.equal(infinity, "miss")
end

function M.stringAndSparseMapsHandleHitsAndMisses()
    local lines = {"local function word(value: string): string?", "   return switch value do",}
    for index = 1, 8 do
        lines[#lines + 1] = ("      case 'k%d' -> %s"):format(index, index == 3 and "nil" or ("'v%d'"):format(index))
    end
    lines[#lines + 1] = "      else -> 'miss'"
    lines[#lines + 1] = "   end"
    lines[#lines + 1] = "end"
    lines[#lines + 1] = "local function sparse(value: number): integer"
    lines[#lines + 1] = "   return switch value do"
    for index = 1, 16 do
        lines[#lines + 1] = ("      case %d -> %d"):format(index * 100 + 1, index)
    end
    lines[#lines + 1] = "      else -> 0"
    lines[#lines + 1] = "   end"
    lines[#lines + 1] = "end"
    lines[#lines + 1] = "return word('k1'), word('k3'), word('no'), sparse(1601), sparse(2)"
    local first, nilResult, missing, sparseHit, sparseMiss = run(table.concat(lines, "\n"))
    testAssert.equal(first, "v1")
    testAssert.equal(nilResult, nil)
    testAssert.equal(missing, "miss")
    testAssert.equal(sparseHit, 16)
    testAssert.equal(sparseMiss, 0)
end

function M.sentinelAndCoverageAreConditional()
    local source = table.concat(
        {
            "local selector: string = 'k1'",
            "local selected = switch selector do",
            "   case 'k1' -> 'v1'",
            "   case 'k2' -> 'v2'",
            "   case 'k3' -> 'v3'",
            "   case 'k4' -> 'v4'",
            "   case 'k5' -> 'v5'",
            "   case 'k6' -> 'v6'",
            "   case 'k7' -> 'v7'",
            "   case 'k8' -> 'v8'",
            "   else -> 'miss'",
            "end",
            "return selected",
        },
        "\n"
    )
    local code = generate(source)
    assert(code:find("__nuppSwitchMap", 1, true), code)
    testAssert.equal(code:find("__nuppSwitchNil", 1, true), nil, "a map without a nil result needs no sentinel")

    local covered = generate(source, true)
    testAssert.equal(covered:find("__nuppSwitchMap", 1, true), nil, "coverage keeps per-case conditions")
end

function M.recordIdentityGuardUsesTheCheckerProof()
    local safe = table.concat(
        {
            "local record First value: integer end",
            "local record Second value: integer end",
            "local function get(value: First | Second): integer",
            "   return switch value do",
            "      case is First {value} -> value",
            "      case is Second {value} -> value",
            "   end",
            "end",
            "return get(new First(value = 1))",
        },
        "\n"
    )
    local safeCode = generate(safe)
    assert(safeCode:find("=getmetatable(", 1, true), safeCode)
    testAssert.equal(safeCode:find("?.__index", 1, true), nil, "a record-only residue needs no safe guard")

    local open = table.concat(
        {
            "local record Item value: integer end",
            "local function get(value: Item?): integer",
            "   return switch value do",
            "      case is Item {value} -> value",
            "      case nil -> 0",
            "   end",
            "end",
            "return get(nil)",
        },
        "\n"
    )
    local openCode = generate(open)
    assert(openCode:find("?.__index", 1, true), openCode)
end

function M.manyMapsSpillBehindOnePrologueUpvalue()
    local lines = {}
    for functionIndex = 1, 34 do
        lines[
            #lines + 1
        ] = ("local function f%d(value: string): integer%s"):format(functionIndex, functionIndex == 34 and "?" or "")
        lines[#lines + 1] = "   return switch value do"
        for caseIndex = 1, 8 do
            local result = functionIndex == 34 and caseIndex == 3 and "nil" or tostring(functionIndex * 100 + caseIndex)
            lines[#lines + 1] = ("      case 'f%d-k%d' -> %s"):format(functionIndex, caseIndex, result)
        end
        lines[#lines + 1] = "      else -> 0"
        lines[#lines + 1] = "   end"
        lines[#lines + 1] = "end"
    end
    lines[#lines + 1] = "return f1('f1-k1'), f34('f34-k8'), f34('f34-k3')"
    local code = generate(table.concat(lines, "\n"))
    assert(code:find("__nuppSwitchConstants", 1, true), code)
    local chunk = assert(loadstring(code, "@switch_spill"))
    local first, last, nilResult = chunk()
    testAssert.equal(first, 101)
    testAssert.equal(last, 3408)
    testAssert.equal(nilResult, nil)
end

function M.aNestedSwitchMaySupplyAnotherSwitchSelector()
    local first, fourth, missing = run(
        table.concat(
            {
                "local function classify(value: number): string",
                "   return switch (switch value do",
                "      case 1 -> 10",
                "      case 2 -> 11",
                "      case 3 -> 12",
                "      case 4 -> 13",
                "      else -> 0",
                "   end) do",
                "      case 10 -> 'one'",
                "      case 11 -> 'two'",
                "      case 12 -> 'three'",
                "      case 13 -> 'four'",
                "      else -> 'missing'",
                "   end",
                "end",
                "return classify(1), classify(4), classify(99)",
            },
            "\n"
        )
    )
    testAssert.equal(first, "one")
    testAssert.equal(fourth, "four")
    testAssert.equal(missing, "missing")
end

function M.aNestedArmStaysLazyAndPlansIndependently()
    local source = table.concat(
        {
            "local reads = 0",
            "local function read(): string",
            "   reads = reads + 1",
            "   return 'k8'",
            "end",
            "local function choose(outer: number): string",
            "   return switch outer do",
            "      case 1 -> switch read() do",
            "         case 'k1' -> 'v1'",
            "         case 'k2' -> 'v2'",
            "         case 'k3' -> 'v3'",
            "         case 'k4' -> 'v4'",
            "         case 'k5' -> 'v5'",
            "         case 'k6' -> 'v6'",
            "         case 'k7' -> 'v7'",
            "         case 'k8' -> 'v8'",
            "         else -> 'inner-miss'",
            "      end",
            "      case 2 -> 'outer-two'",
            "      else -> 'outer-miss'",
            "   end",
            "end",
            "local first = choose(2)",
            "local before = reads",
            "local second = choose(1)",
            "return first, before, second, reads",
        },
        "\n"
    )
    local code = generate(source)
    assert(code:find("__nuppSwitchMap", 1, true), code)
    local chunk = assert(loadstring(code, "@nested_switch_arm"))
    local first, before, second, after = chunk()
    testAssert.equal(first, "outer-two")
    testAssert.equal(before, 0, "the unselected nested arm does no work")
    testAssert.equal(second, "v8")
    testAssert.equal(after, 1, "the selected nested selector runs once")
end

function M.anOpenUnionKeepsAskingForItsElseArm()
    local source = table.concat(
        {
            "local type Status = 'on' | 'off' | nupp.types.nonExhaustive()",
            "local status: Status = 'on'",
            "local value = switch status do case 'on' -> 1 case 'off' -> 2 end",
        },
        "\n"
    )
    local codes, diagnostics = diagnosticCodes(source)
    testAssert.equal(codes, "NUPP2140", "covering every written member is not exhaustive")
    assert(diagnostics[1].msg:find("open", 1, true), diagnostics[1].msg)

    -- and the `else` that answers it is never the unnecessary one
    local covered = diagnosticCodes(
        table.concat(
            {
                "local type Status = 'on' | 'off' | nupp.types.nonExhaustive()",
                "local status: Status = 'on'",
                "local value = switch status do case 'on' -> 1 case 'off' -> 2 else -> 3 end",
            },
            "\n"
        )
    )
    testAssert.equal(covered, "", "an open union's else arm is not unnecessary")

    -- the same union without the open member still closes
    local closed = diagnosticCodes(
        table.concat(
            {
                "local type Status = 'on' | 'off'",
                "local status: Status = 'on'",
                "local value = switch status do case 'on' -> 1 case 'off' -> 2 end",
            },
            "\n"
        )
    )
    testAssert.equal(closed, "", "a closed union is exhaustive once every member is a case")
end

function M.anOpenUnionDoesNotFitTheMembersItLists()
    local narrowing = diagnosticCodes(
        table.concat(
            {
                "local type Status = 'on' | 'off' | nupp.types.nonExhaustive()",
                "local status: Status = 'on'",
                "local closed: 'on' | 'off' = status",
            },
            "\n"
        )
    )
    testAssert.equal(narrowing, "NUPP2001", "an open union is not the closed union of its members")

    -- a member still assigns into it, so writing one costs nothing at a call site
    local widening = diagnosticCodes(
        table.concat(
            {"local type Status = 'on' | 'off' | nupp.types.nonExhaustive()", "local status: Status = 'on'",},
            "\n"
        )
    )
    testAssert.equal(widening, "", "a member of an open union fits it")

    local arguments = diagnosticCodes("local type Status = 'on' | nupp.types.nonExhaustive(1)")
    testAssert.equal(arguments, "NUPP2421", "the open member takes no arguments")
end

function M.switchDiagnosticsAreSpecific()
    local missing = diagnosticCodes(
        table.concat(
            {
                "local type Status = 'on' | 'off'",
                "local status: Status = 'on'",
                "local value = switch status do case 'on' -> 1 end",
            },
            "\n"
        )
    )
    testAssert.equal(missing, "NUPP2140")

    local duplicate = diagnosticCodes(
        "local selector: number = 1\nlocal value = switch selector do case 1, 1.0 -> 1 else -> 0 end"
    )
    testAssert.equal(duplicate, "NUPP2138")

    local dynamic = diagnosticCodes("local value = switch 2 do case 1 + 1 -> 1 else -> 0 end")
    testAssert.equal(dynamic, "NUPP2137")

    local escaped = diagnosticCodes(
        [[local selector: string = "a"
local value = switch selector do case "\x61", "a" -> 1 else -> 0 end]]
    )
    testAssert.equal(escaped, "NUPP2138")

    local fallthrough = diagnosticCodes(
        table.concat({"local value = switch 1 do", "   else -> do", "      local answer = 1", "   end", "end",}, "\n")
    )
    testAssert.equal(fallthrough, "NUPP2141")

    local never = diagnosticCodes(
        table.concat(
            {
                "local function fail(): string",
                "   return switch 1 do",
                "      case 1 -> do",
                "         error('no value')",
                "      end",
                "   end",
                "end",
            },
            "\n"
        )
    )
    testAssert.equal(never, "")
end

local function leanSwitch(source, expected, inspect)
    do
        local result = parser.parse(source, "lean-switch.g.nupp")
        testAssert.equal(#result.errors, 0, "lean switch parses")
        local diagnostics = check.check(result, "lean-switch.g.nupp")
        testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local code, problems = gen.generate(result, "lean-switch.g.nupp")
        testAssert.equal(#problems, 0, problems[1] and problems[1].msg)
        local chunk, problem = loadstring(code)
        assert(chunk, tostring(problem) .. "\n" .. code)
        testAssert.equal(chunk(), expected)
        if inspect then
            inspect(code)
        end
    end
end

function M.directLocalSwitchUsesItsDestinationAndLocalSelector()
    leanSwitch(
        [[
local function formatStatus(status: number): string return tostring(status) end
local function choose(status: number): string
    local text = switch status do
        case 200 -> formatStatus(status)
        case 301 -> 'redirect'
        else -> 'other'
    end
    return text
end
return choose(200) .. ':' .. choose(301) .. ':' .. choose(500)
]],
        "200:redirect:other",
        function(code)
            assert(not code:find("__nuppT", 1, true), code)
            assert(code:match("local text%s*;"), code)
        end
    )
end

function M.directSwitchKeepsOuterNamesInScope()
    leanSwitch(
        [[
local text = 'outer'
local status: number = 200
local text = switch status do
    case 200 -> text
    else -> 'other'
end
return text
]],
        "outer",
        function(code)
            assert(code:find("__nuppT", 1, true), code)
        end
    )
end

function M.computedSwitchSelectorStillRunsOnce()
    leanSwitch(
        [[
local reads = 0
local source = setmetatable({}, {__index = function(_, _)
    reads = reads + 1
    return 301
end}) as {status: number}
local text = switch source.status do
    case 200 -> 'ok'
    case 301 -> 'redirect'
    else -> 'other'
end
return text .. ':' .. tostring(reads)
]],
        "redirect:1"
    )
end

function M.mapInitializesItsDestinationBeforeItEntersScope()
    leanSwitch(
        [[
local label: number = 10
local label = switch label do
    case 9 -> 'tab'
    case 10 -> 'newline'
    case 11 -> 'vertical tab'
    case 12 -> 'form feed'
    case 13 -> 'return'
    else -> 'other'
end
return label
]],
        "newline",
        function(code)
            assert(not code:find("__nuppT", 1, true), code)
            assert(code:match("local label%s*=%s*__nuppSwitchMap%d+%["), code)
        end
    )
end

function M.directMapPreservesNilFalseAndMissingKeys()
    leanSwitch(
        [[
local function lookup(key: number): string
    local value = switch key do
        case 1 -> nil
        case 2 -> false
        case 3 -> 'three'
        case 4 -> 'four'
        else -> 'other'
    end
    return tostring(value)
end
return lookup(1) .. ':' .. lookup(2) .. ':' .. lookup(3) .. ':' .. lookup(9)
]],
        "nil:false:three:other"
    )
end

function M.earlyDestinationDoesNotShadowAnArmLocalOrClosure()
    leanSwitch(
        [[
local text = 'outer'
local status: number = 200
local text = switch status do
    case 200 -> (function(): string return text end)()
    else -> 'other'
end
return text
]],
        "outer"
    )
end

function M.destinationDoesNotShadowCompilerIntroducedBuiltins()
    leanSwitch(
        [[
local function choose(status: number): string
    local tostring = switch status do
        case 200 -> `status ${status}`
        else -> 'other'
    end
    return tostring
end
return choose(200)
]],
        "status 200"
    )
end

function M.blockArmLocalsKeepTheirOwnScope()
    leanSwitch(
        [[
local function choose(status: number): string
    local text = switch status do
        case 200 -> do
            local text = 'ok'
            yield text
        end
        else -> 'other'
    end
    return text
end
return choose(200)
]],
        "ok"
    )
end

function M.constSwitchResultsKeepASingleInitialization()
    leanSwitch(
        [[
local function choose(status: number): string
    const text = switch status do
        case 200 -> 'ok'
        else -> 'other'
    end
    return text
end
return choose(200)
]],
        "ok",
        function(code)
            assert(code:find("__nuppT", 1, true), code)
        end
    )
end

function M.mappedComputedSelectorStillRunsOnce()
    leanSwitch(
        [[
local calls = 0
local function read(): number calls = calls + 1 return 10 end
local label = switch read() do
    case 9 -> 'tab'
    case 10 -> 'newline'
    case 11 -> 'vertical tab'
    case 12 -> 'form feed'
    case 13 -> 'return'
    else -> 'other'
end
return label .. ':' .. tostring(calls)
]],
        "newline:1"
    )
end

function M.guardedArmRunsOnlyWhenItsPredicateHolds()
    local even, odd, other = run(
        [[
local function classify(n: integer): string
    return switch n do
        case 1, 2, 3 where n % 2 == 0 -> 'small even'
        case 1, 2, 3 -> 'small odd'
        else -> 'big'
    end
end
return classify(2), classify(3), classify(9)
]]
    )
    testAssert.equal(even, "small even")
    testAssert.equal(odd, "small odd")
    testAssert.equal(other, "big")
end

function M.guardedArmProvesNoCoverage()
    -- The only arm naming `true` declines it whenever the guard is false, so the
    -- selector is still open and the switch is not exhaustive.
    testAssert.equal(
        diagnosticCodes(
            [[
local function f(b: boolean): string
    return switch b do
        case true where b -> 'yes'
        case false -> 'no'
    end
end
return f(true)
]]
        ),
        "NUPP2140"
    )
end

function M.guardedArmDoesNotShadowTheArmBelowIt()
    testAssert.equal(
        diagnosticCodes(
            [[
local function f(n: 1 | 2): string
    return switch n do
        case 1 where n > 0 -> 'guarded'
        case 1 -> 'plain'
        case 2 -> 'two'
    end
end
return f(1)
]]
        ),
        ""
    )
end

function M.repeatedValueAfterAnUnguardedArmIsStillADuplicate()
    testAssert.equal(
        diagnosticCodes(
            [[
local function f(n: 1 | 2): string
    return switch n do
        case 1 -> 'plain'
        case 1 where n > 0 -> 'guarded'
        case 2 -> 'two'
    end
end
return f(1)
]]
        ),
        "NUPP2138"
    )
end

function M.aGuardReadsTheArmsOwnBindings()
    local big, small = run(
        [[
local record Box
    n: integer
end
local function g(v: Box | string): string
    return switch v do
        case is Box as box where box.n > 10 -> 'big box'
        case is Box as box -> 'box ' .. tostring(box.n)
        case is string -> v
    end
end
return g(new Box(n = 50)), g(new Box(n = 1))
]]
    )
    testAssert.equal(big, "big box")
    testAssert.equal(small, "box 1")
end

function M.aBareNameGuardIsNotAShortFunction()
    -- `where b -> 'yes'` is a guard and an arm result. Reading it as a short
    -- function taking `b` is the collision that rules out spelling this `and`.
    local yes, no = run(
        [[
local function f(b: boolean): string
    return switch b do
        case true where b -> 'yes'
        else -> 'no'
    end
end
return f(true), f(false)
]]
    )
    testAssert.equal(yes, "yes")
    testAssert.equal(no, "no")
end

function M.aGuardStillAdmitsALambdaInsideBrackets()
    local found, missing = run(
        [[
local function any(xs: {integer}, f: function(integer): boolean): boolean
    for _, x in ipairs(xs) do
        if f(x) then return true end
    end
    return false
end
local function f(xs: {integer}): string
    return switch #xs > 0 do
        case true where any(xs, x -> x > 2) -> 'found'
        else -> 'missing'
    end
end
return f({5}), f({1})
]]
    )
    testAssert.equal(found, "found")
    testAssert.equal(missing, "missing")
end

function M.aGuardedSwitchLowersToBranchesRatherThanAMap()
    local code = generate(
        [[
local function label(n: integer): string
    return switch n do
        case 9 where n > 0 -> 'tab'
        case 10 -> 'newline'
        case 11 -> 'vertical tab'
        case 12 -> 'form feed'
        case 13 -> 'return'
        else -> 'other'
    end
end
return label(10)
]]
    )
    assert(code:find("goto", 1, true), "a guarded switch jumps out of a taken arm:\n" .. code)
end

function M.breakInsideAGuardedArmStillLeavesTheEnclosingLoop()
    -- The guarded lowering jumps to a label rather than wrapping the arms in a
    -- loop, which is what keeps an arm's own `break` bound to the `for` above it.
    local found = run(
        [[
local function firstBig(xs: {integer}): integer
    local found: integer = -1
    for _, x in ipairs(xs) do
        local tag = switch x > 0 do
            case true where x > 10 -> do
                found = x
                break
            end
            else -> 'keep'
        end
        if tag == nil then break end
    end
    return found
end
return firstBig({1, 5, 20, 30})
]]
    )
    testAssert.equal(found, 20)
end

function M.guardedSwitchesNest()
    local both, outer, neither = run(
        [[
local function nested(a: integer, b: integer): string
    return switch a do
        case 1 where a > 0 -> switch b do
            case 2 where b > 1 -> 'one-two'
            else -> 'one-other'
        end
        else -> 'other'
    end
end
return nested(1, 2), nested(1, 9), nested(5, 2)
]]
    )
    testAssert.equal(both, "one-two")
    testAssert.equal(outer, "one-other")
    testAssert.equal(neither, "other")
end

-- A task's status is a closed union, so a switch naming its five states is complete,
-- and one missing a state is caught where it is written.
function M.aTaskStatusSwitchNeedsNoElse()
    local here = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
    local env = require("nupp.compiler.project.env").new(here .. "/..")
    local function diagnosticCodes(source)
        local result = parser.parse(source, "switch-test.g.nupp")
        testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "switch source parses")
        local codes = {}
        for _, diagnostic in ipairs(check.check(result, "switch-test.g.nupp", env)) do
            codes[#codes + 1] = diagnostic.code
        end

        return table.concat(codes, " ")
    end
    local head = {
        "local tasks = require('nupp.tasks')",
        "local function label(task: tasks.Task<function(): integer>): string",
        "    return switch task:status() do",
        "        case 'queued' -> 'waiting'",
        "        case 'running' -> 'busy'",
        "        case 'done' -> 'finished'",
        "        case 'failed' -> 'broken'",
    }
    local complete = table.concat(head, "\n")
        .. "\n        case 'cancelled' -> 'stopped'\n    end\nend\nprint(label)"
    testAssert.equal(diagnosticCodes(complete), "", "the five states cover the status")
    local missing = table.concat(head, "\n") .. "\n    end\nend\nprint(label)"
    testAssert.equal(diagnosticCodes(missing), "NUPP2140", "a missing state is not exhaustive")
    local status = table.concat({
        "local tasks = require('nupp.tasks')",
        "local state: tasks.Status = 'queued'",
        "print(switch state do case 'queued' -> 1 case 'running' -> 2 case 'done' -> 3 "
            .. "case 'failed' -> 4 case 'cancelled' -> 5 end)",
    }, "\n")
    testAssert.equal(diagnosticCodes(status), "", "tasks.Status names the same union")
end

return M
