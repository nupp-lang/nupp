local testAssert = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local program = require("program")
local fmt = require("nupp.tools.fmt")
local cst = require("nupp.compiler.syntax.cst")
local env = require("nupp.compiler.project.env")

local function parsed(source)
    local result = parser.parse(source, "test.nupp")
    testAssert.eq(#result.errors, 0, result.errors[1] and result.errors[1].msg or "unexpected syntax error")
    return result
end

local function diagnostics(source)
    local result = parsed(source)
    local out = {}
    for index, diagnostic in ipairs(check.check(result, "test.nupp", env.new("."))) do
        out[index] = diagnostic.code
    end

    return table.concat(out, " ")
end

local function run(source)
    local result = parsed(source)
    local checked = check.check(result, "test.nupp", env.new("."))
    testAssert.eq(#checked, 0, checked[1] and checked[1].msg or "unexpected check diagnostic")
    return program.run(result, "binding_pattern_test")
end

local pair = table.concat({"local record Pair", "   x: number", "   y: number", "end",}, "\n")

local M = {}

function M.syntaxRoundTripsAndRecordsAliasesAndAnnotations()
    local source = pair .. "\nconst {x: number, y as vertical: number} = point"
    local result = parsed(source)
    testAssert.eq(cst.textOf(result.root), source)
    local declaration = result.root.blocks[1].stats[2]
    testAssert.eq(declaration.kind, "localStmt")
    testAssert.eq(declaration.isConst, true)
    testAssert.eq(#declaration.pattern, 2)
    testAssert.eq(declaration.pattern[1].sourceName.text, "x")
    testAssert.eq(declaration.pattern[2].sourceName.text, "y")
    testAssert.eq(declaration.pattern[2].alias.text, "vertical")
    testAssert.eq(declaration.names[2].text, "vertical")
    assert(declaration.types[1] and declaration.types[2])
end

function M.sourceAndFieldsEvaluateOnceFromLeftToRight()
    local answer = run(
        pair .. "\n" .. table.concat(
            {
                "local calls = 0",
                "local fields = ''",
                "local point = setmetatable({}, {__index = function(_, key)",
                "   fields = fields .. key",
                "   return key == 'x' and 3 or 4",
                "end}) as Pair",
                "local function source(): Pair calls += 1 return point end",
                "local {x, y as vertical} = source()",
                "return tostring(calls) .. fields .. tostring(x) .. tostring(vertical)",
            },
            "\n"
        )
    )
    testAssert.eq(answer, "1xy34")
end

function M.constBindingsStayImmutableAndKeepTheirFieldTypes()
    testAssert.eq(
        diagnostics(
            pair .. "\n" .. table.concat(
                {"local point = Pair(x = 1, y = 2)", "const {x, y as vertical} = point", "x = 3", "vertical = 4",},
                "\n"
            )
        ),
        "NUPP2008 NUPP2008"
    )
end

function M.annotationsCheckTheSelectedField()
    testAssert.eq(
        diagnostics(
            pair .. "\n" .. table.concat({"local point = Pair(x = 1, y = 2)", "const {x: string} = point",}, "\n")
        ),
        "NUPP2001"
    )
end

function M.missingAndRepeatedSelectionsAreDiagnosed()
    testAssert.eq(
        diagnostics(pair .. "\n" .. table.concat({"local point = Pair(x = 1, y = 2)", "local {z} = point",}, "\n")),
        "NUPP2004"
    )
    testAssert.eq(
        diagnostics(
            pair .. "\n" .. table.concat({"local point = Pair(x = 1, y = 2)", "local {x, x as other} = point",}, "\n")
        ),
        "NUPP2006"
    )
    testAssert.eq(
        diagnostics(
            pair .. "\n" .. table.concat(
                {"local point = Pair(x = 1, y = 2)", "local {x as value, y as value} = point",},
                "\n"
            )
        ),
        "NUPP2006"
    )
end

function M.patternsDoNotPartiallyMoveOwnedContainers()
    testAssert.eq(
        diagnostics(
            pair .. "\n" .. table.concat(
                {
                    "local function close(takes value: Pair): nil end",
                    "local function open(): affine(Pair, close)",
                    "   return Pair(x = 1, y = 2)",
                    "end",
                    "const owned = open()",
                    "local {x} = owned",
                    "print(x)",
                    "own.drop(owned)",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.formattingUsesReadableBraces()
    testAssert.eq(fmt.format("const{x,y as vertical}=point"), "const {x, y as vertical} = point\n")
    testAssert.eq(fmt.format("draw({x,y}=point,color='blue')"), "draw({x, y} = point, color = 'blue')\n")
end

function M.oldAndAliasedPlucksCarryWholeFixes()
    local old = parser.parse("draw((x, y) = point)", "test.nupp")
    testAssert.eq(#old.errors, 1)
    testAssert.eq(old.errors[1].code, "NUPP1002")
    testAssert.eq(old.errors[1].fixes[1].title, "use a braced pluck")
    testAssert.eq(old.errors[1].fixes[1].edits[1].newText, "{")
    testAssert.eq(old.errors[1].fixes[1].edits[2].newText, "}")

    local aliased = parser.parse("draw({y as color} = point)", "test.nupp")
    testAssert.eq(#aliased.errors, 1)
    testAssert.eq(aliased.errors[1].code, "NUPP1002")
    testAssert.eq(aliased.errors[1].fixes[1].title, "use a named argument")
    testAssert.eq(aliased.errors[1].fixes[1].edits[1].newText, "color = point.y")
end

return M
