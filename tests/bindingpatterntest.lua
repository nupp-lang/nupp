local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local gen = require("nupp.compiler.lua.gen")
local fmt = require("nupp.tools.fmt")
local cst = require("nupp.compiler.syntax.cst")
local env = require("nupp.compiler.project.env")

local function parsed(source)
    local result = parser.parse(source, "test.g.nupp")
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "unexpected syntax error")
    return result
end

local function diagnostics(source)
    local result = parsed(source)
    local out = {}
    for index, diagnostic in ipairs(check.check(result, "test.g.nupp", env.new("."))) do
        out[index] = diagnostic.code
    end

    return table.concat(out, " ")
end

local function run(source)
    local result = parsed(source)
    local checked = check.check(result, "test.g.nupp", env.new("."))
    testAssert.equal(#checked, 0, checked[1] and checked[1].msg or "unexpected check diagnostic")
    local code, problems = gen.generate(result, "test.g.nupp")
    testAssert.equal(#problems, 0, problems[1] and problems[1].msg or "unexpected generation diagnostic")
    local chunk, problem = loadstring(code, "@binding_pattern_test")
    assert(chunk, tostring(problem) .. "\n" .. code)

    return chunk(), code
end

local pair = table.concat({"local record Pair", "   x: number", "   y: number", "end",}, "\n")

local M = {}

function M.syntaxRoundTripsAndRecordsAliasesAndAnnotations()
    local source = pair .. "\nconst {x: number, y as vertical: number} = point"
    local result = parsed(source)
    testAssert.equal(cst.textOf(result.root), source)
    local declaration = result.root.blocks[1].stats[2]
    testAssert.equal(declaration.kind, "localStmt")
    testAssert.equal(declaration.isConst, true)
    testAssert.equal(#declaration.pattern, 2)
    testAssert.equal(declaration.pattern[1].sourceName.text, "x")
    testAssert.equal(declaration.pattern[2].sourceName.text, "y")
    testAssert.equal(declaration.pattern[2].alias.text, "vertical")
    testAssert.equal(declaration.names[2].text, "vertical")
    assert(declaration.types[1] and declaration.types[2])
end

function M.sourceAndFieldsEvaluateOnceFromLeftToRight()
    local answer, code = run(
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
    testAssert.equal(answer, "1xy34")
    testAssert.equal(select(2, code:gsub("= source %( %)", "")), 1, code)
    assert(code:match("local%s+x%s*,%s*vertical%s*=%s*__nuppT%d+%.x%s*,%s*__nuppT%d+%.y"), code)
end

function M.constBindingsStayImmutableAndKeepTheirFieldTypes()
    testAssert.equal(
        diagnostics(
            pair .. "\n" .. table.concat(
                {"local point = new Pair(x = 1, y = 2)", "const {x, y as vertical} = point", "x = 3", "vertical = 4",},
                "\n"
            )
        ),
        "NUPP2008 NUPP2008"
    )
end

function M.annotationsCheckTheSelectedField()
    testAssert.equal(
        diagnostics(
            pair .. "\n" .. table.concat({"local point = new Pair(x = 1, y = 2)", "const {x: string} = point",}, "\n")
        ),
        "NUPP2001"
    )
end

function M.missingAndRepeatedSelectionsAreDiagnosed()
    testAssert.equal(
        diagnostics(pair .. "\n" .. table.concat({"local point = new Pair(x = 1, y = 2)", "local {z} = point",}, "\n")),
        "NUPP2004"
    )
    testAssert.equal(
        diagnostics(
            pair .. "\n" .. table.concat(
                {"local point = new Pair(x = 1, y = 2)", "local {x, x as other} = point",},
                "\n"
            )
        ),
        "NUPP2006"
    )
    testAssert.equal(
        diagnostics(
            pair .. "\n" .. table.concat(
                {"local point = new Pair(x = 1, y = 2)", "local {x as value, y as value} = point",},
                "\n"
            )
        ),
        "NUPP2006"
    )
end

function M.patternsDoNotPartiallyMoveOwnedContainers()
    testAssert.equal(
        diagnostics(
            pair .. "\n" .. table.concat(
                {
                    "local function close(takes value: Pair): nil end",
                    "local function open(): affine(Pair, close)",
                    "   return new Pair(x = 1, y = 2)",
                    "end",
                    "const owned = open()",
                    "local {x} = owned",
                    "print(x)",
                    "nupp.drop(owned)",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.formattingUsesReadableBraces()
    testAssert.equal(fmt.format("const{x,y as vertical}=point"), "const {x, y as vertical} = point\n")
    testAssert.equal(fmt.format("draw({x,y}=point,color='blue')"), "draw({x, y} = point, color = 'blue')\n")
end

function M.oldAndAliasedPlucksCarryWholeFixes()
    local old = parser.parse("draw((x, y) = point)", "test.g.nupp")
    testAssert.equal(#old.errors, 1)
    testAssert.equal(old.errors[1].code, "NUPP1002")
    testAssert.equal(old.errors[1].fixes[1].title, "use a braced pluck")
    testAssert.equal(old.errors[1].fixes[1].edits[1].newText, "{")
    testAssert.equal(old.errors[1].fixes[1].edits[2].newText, "}")

    local aliased = parser.parse("draw({y as color} = point)", "test.g.nupp")
    testAssert.equal(#aliased.errors, 1)
    testAssert.equal(aliased.errors[1].code, "NUPP1002")
    testAssert.equal(aliased.errors[1].fixes[1].title, "use a named argument")
    testAssert.equal(aliased.errors[1].fixes[1].edits[1].newText, "color = point.y")
end

return M
