local fixture = require("helpers.formatfixture")
local testAssert = fixture.testAssert
local fmt = fixture.fmt
local formatter = fixture.formatter
local fmt1 = fixture.fmt1
local kinds = fixture.kinds

local M = {}

function M.supertypesStayOnTheDeclarationLine()
    -- A record's `is` clause is part of its header, not its first field. The formatter
    -- used to break every one onto its own line, which reads as a field list of one and
    -- is how nearly every record in cst.nupp came to be written that way.
    local src = table.concat(
        {"local m = {}", "", "record m.B is m.A", "    x: integer", "end", "", "return m",},
        "\n"
    ) .. "\n"
    local out = formatter:format(src, "supertypes.nupp")
    if out:find("record m.B is m.A", 1, true) == nil then
        error("the supertype stays on the header line, got:\n" .. out, 0)
    end
    testAssert.eq(formatter:format(out, "supertypes.nupp"), out, "and the layout is stable")
end

function M.severalSupertypesStillFitOnOneLine()
    local src = table.concat(
        {"local m = {}", "", "record m.C is m.A, m.B", "    x: integer", "end", "", "return m",},
        "\n"
    ) .. "\n"
    local out = formatter:format(src, "supertypes.nupp")
    if out:find("record m.C is m.A, m.B", 1, true) == nil then
        error("a short list of contracts is still a header, got:\n" .. out, 0)
    end
end

-- An overloaded signature is an intersection of whole function types, so it breaks
-- between the overloads. It used to break inside the first one instead: the depth a
-- break point is judged at counted `<` as a nesting bracket and never took it back at
-- `>`, so everything past a generic parameter list read as nested and the `&` joining
-- the overloads was invisible.
function M.intersectionsBreakBetweenTheirOverloads()
    local src = "local pcall: function<A..., R...>(scoped f: function(A...): R..., A...):"
        .. " ((true, R...) | (false, any)) & function<A..., R...>(takes f: function(A...): R...,"
        .. " A...): ((true, R...) | (false, any))\n"
    local out = formatter:format(src, "overloads.d.nupp")
    local lines = {}
    for line in out:gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    testAssert.eq(#lines, 2, "an overload apiece, got:\n" .. out)
    testAssert.eq(
        lines[1],
        "local pcall: function<A..., R...>(scoped f: function(A...): R..., A...):" .. " ((true, R...) | (false, any))"
    )
    testAssert.eq(
        lines[2],
        "    & function<A..., R...>(takes f: function(A...): R..., A...):" .. " ((true, R...) | (false, any))"
    )
    testAssert.eq(formatter:format(out, "overloads.d.nupp"), out, "and the layout is stable")
end

-- Type parameters are part of a signature's header, the way a record's `is` clause is.
-- A signature too long to fit is nearly always its parameters, so those are what break,
-- and the `>` closing the list stays with the declaration rather than taking a
-- continuation indent of its own.
function M.halfClosedGenericsFormatStably()
    local source = table.concat(
        {
            "local a: Box<Box<integer>>? = nil",
            "local b: Box<Box<integer>> | nil = nil",
            "local c: {Box<Box<integer>>, integer} = x",
            "local d: Box<Box<integer>>[4] = x",
            "",
        },
        "\n"
    )
    testAssert.eq(fmt1(source), source)
    testAssert.eq(kinds(fmt1(source)), kinds(source))
end

-- An @annotationValue on an entry with no name is the checker's to report; the
-- formatter leaves the record alone rather than reaching for a name it lacks.
function M.annotationValueOnANamelessEntryFormats()
    local source = table.concat(
        {
            "@annotation",
            "record Marker",
            "    @annotationvalue [string]: integer",
            "    @annotationvalue {integer}",
            "end",
            "",
        },
        "\n"
    )
    testAssert.eq(fmt1(source), source)
end

function M.typeParametersStayOnTheSignatureLine()
    local src = "local xpcall: function<E, A..., R...>(scoped f: function(A...): R...,"
        .. " scoped handler: function(any): E, A...): ((true, R...) | (false, E))\n"
    local out = formatter:format(src, "header.d.nupp")
    if out:find("local xpcall: function<E, A..., R...>(\n", 1, true) == nil then
        error("the type parameters left the header line, got:\n" .. out, 0)
    end
    testAssert.eq(formatter:format(out, "header.d.nupp"), out, "and the layout is stable")
end

-- A union longer than the width reads as one member per line. It used to be left over
-- the width instead, because a union's `|` was no kind of break point.
function M.longValueChainsKeepEachOperandTogether()
    local compact = fmt.new({width = 64})
    for _, operator in ipairs({"|", "or"}) do
        local operands = {
            "(current == leftBrace)",
            "(current == rightBrace)",
            "(current == leftBracket)",
            "(current == rightBracket)"
        }
        local source = "local structural = " .. table.concat(operands, " " .. operator .. " ")
        local expected = "local structural = " .. operands[1] .. "\n"
        for index = 2, #operands do
            expected = expected .. "    " .. operator .. " " .. operands[index] .. "\n"
        end
        local output = compact:format(source)
        testAssert.eq(output, expected, "break a mask chain between complete comparisons")
        testAssert.eq(compact:format(output), output, "value chain layout is stable")
        testAssert.eq(kinds(output), kinds(source), "operators and parentheses are preserved")
    end
end

function M.longUnionsBreakBetweenTheirMembers()
    local src = "local kind: function(v: any): \"nil\" | \"boolean\" | \"number\" | \"string\""
        .. " | \"table\" | \"function\" | \"thread\" | \"userdata\" | \"cdata\"\n"
    local out = formatter:format(src, "union.d.nupp")
    for line in out:gmatch("(.-)\n") do
        if #line > 120 then
            error("a member per line keeps every one inside the width, got:\n" .. out, 0)
        end
    end
    if out:find("\n    | \"boolean\"\n", 1, true) == nil then
        error("the union did not break between its members, got:\n" .. out, 0)
    end
    testAssert.eq(formatter:format(out, "union.d.nupp"), out, "and the layout is stable")
end

-- An `if NAME = EXPR then` binding is spaced like an assignment and stays one.
function M.ifBindingsAreSpacedLikeAssignments()
    local src = "if   v=f( x )   then\n    print(v)\nelseif w=g()then\n    print(w)\nend\n"
    local once = fmt1(src)
    testAssert.eq(once, "if v = f(x) then\n    print(v)\nelseif w = g() then\n    print(w)\nend\n")
    testAssert.eq(fmt1(once), once, "and the layout is stable")
    testAssert.eq(kinds(once), kinds(src), "parse changed")
end

return M
