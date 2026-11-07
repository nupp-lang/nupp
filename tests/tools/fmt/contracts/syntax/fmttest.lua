local fixture = require("helpers.formatfixture")
local testAssert = fixture.testAssert
local fmt = fixture.fmt
local formatter = fixture.formatter
local fmt1 = fixture.fmt1
local kinds = fixture.kinds

local M = {}

function M.protocolsAfterResultsRemainRefusedByFormatting()
    local source = "local function worker(): string yields(number) resumes(boolean) return 'done' end"
    local formatted, errors = formatter:format(source, "test.nupp")
    testAssert.eq(formatted, source)
    testAssert.eq(errors[1] and errors[1].code, "NUPP1005")
    testAssert.eq(errors[1] and errors[1].msg, "coroutine protocol clauses must precede the result type")
end

function M.switchExpressionIndentation()
    local source = table.concat(
        {
            "local result=switch shape do",
            "case 1->'one'",
            "case is Circle as circle {radius,name as label}->do",
            "local doubled=radius*2",
            "yield doubled",
            "end",
            "else->0",
            "end",
        },
        "\n"
    )
    local expected = table.concat(
        {
            "local result = switch shape do",
            "    case 1 -> 'one'",
            "    case is Circle as circle {radius, name as label} -> do",
            "        local doubled = radius * 2",
            "        yield doubled",
            "    end",
            "    else -> 0",
            "end",
            "",
        },
        "\n"
    )
    local formatted = fmt1(source)
    testAssert.eq(formatted, expected)
    testAssert.eq(fmt1(formatted), expected, "switch formatting is idempotent")
end

function M.spacingBasics()
    testAssert.eq(fmt1("local x=1+2"), "local x = 1 + 2\n")
    testAssert.eq(fmt1("const x:number=1"), "const x: number = 1\n")
    testAssert.eq(fmt1("f( x , y )"), "f(x, y)\n")
    testAssert.eq(fmt1("local f = function () return nil end"), "local f = function()\n    return nil\nend\n")
    testAssert.eq(fmt1("local f: function (number): string"), "local f: function(number): string\n")
    testAssert.eq(fmt1("t . a [ 1 ] : m ( )"), "t.a[1]:m()\n")
    testAssert.eq(fmt1('f"lit"'), 'f"lit"\n')
    testAssert.eq(fmt1("f{1,2}"), "f{1, 2}\n")
end

function M.declaredModulesAndExports()
    local source = "module sample.api\nexport record Thing\nvalue:integer\nend\n"
        .. "export function make(value:integer):Thing\nreturn Thing(value=value)\nend\n"
        .. "const {type External as LocalExternal,value as result}=require('other')\n"
        .. "export=setmetatable(result,{__call=make})"
    local expected = "module sample.api\n\nexport record Thing\n    value: integer\nend\n"
        .. "export function make(value: integer): Thing\n    return Thing(value = value)\nend\n"
        .. "\nconst {type External as LocalExternal, value as result} = require('other')\n"
        .. "export = setmetatable(result, {__call = make})\n"
    local formatted = fmt1(source)
    testAssert.eq(formatted, expected)
    testAssert.eq(fmt1(formatted), expected, "declared module formatting is idempotent")
end

function M.moduleHeaderSeparation()
    testAssert.eq(fmt1("module sample\nlocal value=1"), "module sample\n\nlocal value = 1\n")
    testAssert.eq(
        fmt1("--[[Module documentation.]]\nmodule sample\nexport const value:integer=1"),
        "--[[Module documentation.]]\nmodule sample\n\nexport const value: integer = 1\n"
    )
    testAssert.eq(
        fmt1('module sample -- header\nconst dependency=require("dependency")'),
        'module sample -- header\n\nconst dependency = require("dependency")\n'
    )
    testAssert.eq(fmt1("module sample; local value=1"), "module sample;\n\nlocal value = 1\n")
end

function M.countedCParameters()
    testAssert.eq(
        fmt1("cdef function visit(borrows values:const int32* countedBy(count),count:uint64)"),
        "cdef function visit(borrows values: const int32* countedBy(count), count: uint64)\n"
    )
end

function M.propertyCapabilities()
    testAssert.eq(
        fmt1("local x:{@readonly value:string,@writeonly value:string|integer}"),
        "local x: {\n    @readonly value: string,\n    @writeonly value: string | integer\n}\n"
    )
    testAssert.eq(
        fmt1("local x:{@readonly [string]:string,@writeonly [string]:integer}"),
        "local x: {\n    @readonly [string]: string,\n    @writeonly [string]: integer\n}\n"
    )
    testAssert.eq(
        fmt1("local interface Cell\n@readonly value:string\n@writeonly value:integer\nend"),
        "local interface Cell\n    @readonly value: string\n    @writeonly value: integer\nend\n"
    )
end

-- An annotation that takes no arguments shares the line of what it modifies when
-- that is a member stating one value or a statement that declares nothing. One with
-- arguments, one on a declaration, and one a comment separates from its target each
-- keep a line of their own.
function M.argumentFreeAnnotationsStayInline()
    local source = table.concat(
        {
            "local m = {}",
            "@derive(nupp.Inspect)",
            "record m.Cell",
            "@readonly",
            "value: string",
            "@json(name = \"x\")",
            "@private",
            "hidden: string",
            "@readonly @private both: integer",
            "@readonly",
            "-- why",
            "other: string",
            "@private",
            "function helper(self): nil end",
            "end",
            "@comptime",
            "local function F(T: type): type return T end",
            "function m.f(owner: any): nil",
            "@unsafe",
            "do print(1) end",
            "@allow(NUPP2001)",
            "@nosuspend",
            "do print(2) end",
            "@unsafe",
            "local x = 1",
            "@unsafe",
            "own.release(owner)",
            "end",
            "return m",
        },
        "\n"
    )
    local expected = table.concat(
        {
            "local m = {}",
            "@derive(nupp.Inspect)",
            "record m.Cell",
            "    @readonly value: string",
            "    @json(name = \"x\")",
            "    @private hidden: string",
            "    @readonly @private both: integer",
            "    @readonly",
            "    -- why",
            "    other: string",
            "    @private",
            "    function helper(self): nil",
            "    end",
            "end",
            "",
            "@comptime",
            "local function F(T: type): type",
            "    return T",
            "end",
            "",
            "function m.f(owner: any): nil",
            "    @unsafe do",
            "        print(1)",
            "    end",
            "    @allow(NUPP2001)",
            "    @nosuspend do",
            "        print(2)",
            "    end",
            "    @unsafe local x = 1",
            "    @unsafe own.release(owner)",
            "end",
            "",
            "return m",
            "",
        },
        "\n"
    )
    testAssert.eq(fmt1(source), expected)
    testAssert.eq(fmt1(expected), expected)
end

function M.rejectedLexicalOwnershipFormsRemainUnchanged()
    for _, source in ipairs({
        "local owner = @unsafe adopt raw as affine(any)",
        "local raw = @unsafe release owner",
        "drop owner",
    }) do
        local formatted, errors = formatter:format(source, "test.nupp")
        testAssert.eq(formatted, source)
        testAssert.eq(errors[1] and errors[1].code, "NUPP1005")
    end
end

function M.removedWithSyntaxIsNotFormattedAsAValidProgram()
    local source = "with owner = acquire() do end"
    local formatted, errors = formatter:format(source, "test.nupp")
    testAssert.eq(formatted, source)
    assert(#errors > 0, "removed syntax must fail normal parsing")
end

function M.stageZeroSourcesUseCanonicalForms()
    local source = "local sealed interface Token\n@readonly value:integer\nend"
    local expected = "local sealed interface Token\n    @readonly value: integer\nend\n"
    testAssert.eq(formatter:format(source, "src/nupp/compiler/example.nupp"), expected)
    testAssert.eq(formatter:format(source, "src/nupp/runtime/example.nupp"), expected)
    testAssert.eq(formatter:format(source, "src/nupp/example.nupp"), expected)
    testAssert.eq(formatter:format(source, "src/example.nupp"), fmt1(source))
end

function M.sealedInterfaceModifier()
    testAssert.eq(
        fmt1("local sealed interface Token\n@readonly value:integer\nend"),
        "local sealed interface Token\n    @readonly value: integer\nend\n"
    )
end

function M.constructionUsesOrdinaryCallFormatting()
    testAssert.eq(fmt1("local a = R(n = 1)"), "local a = R(n = 1)\n")
    testAssert.eq(fmt1("local a = m.Point(x = 1)"), "local a = m.Point(x = 1)\n")
    testAssert.eq(fmt1("local a = V2 (1, 2)"), "local a = V2(1, 2)\n")
    testAssert.eq(fmt1("f{a = 1}"), "f{a = 1}\n")
end

function M.constructorResultPoliciesFormatAsFunctionResults()
    testAssert.eq(
        fmt1(
            table.concat(
                {
                    "local record File",
                    "constructor(self,path:string):affine(File,File.destroy)",
                    "self.path=path",
                    "end",
                    "end",
                },
                "\n"
            )
        ),
        table.concat(
            {
                "local record File",
                "    constructor(self, path: string): affine(File, File.destroy)",
                "        self.path = path",
                "    end",
                "end",
                "",
            },
            "\n"
        )
    )
end

function M.methodCallParensDefaultOn()
    testAssert.eq(fmt1("obj:m{a = 1}"), "obj:m({a = 1})\n")
    testAssert.eq(fmt1('obj:m"lit"'), 'obj:m("lit")\n')
    testAssert.eq(fmt1("obj?.:m{a = 1}"), "obj?.:m({a = 1})\n")
    testAssert.eq(fmt1("obj:m?.{a = 1}"), "obj:m?.({a = 1})\n")
    -- already parenthesized, and a plain (non-method) call: untouched
    testAssert.eq(fmt1("obj:m({a = 1})"), "obj:m({a = 1})\n")
    testAssert.eq(fmt1("f{a = 1}"), "f{a = 1}\n")
    testAssert.eq(fmt1('f"lit"'), 'f"lit"\n')
end

function M.methodCallParensCanBeTurnedOff()
    local off = {methodParens = false}
    testAssert.eq((fmt.format("obj:m{a = 1}", nil, off)), "obj:m{a = 1}\n")
    testAssert.eq((fmt.format('obj:m"lit"', nil, off)), 'obj:m"lit"\n')
end

function M.methodCallParensIdempotent()
    local once = fmt1("obj:m{a = 1}")
    testAssert.eq(fmt1(once), once)
    testAssert.eq(kinds(once), "name : name ( { name = number } ) eof")
end

function M.bareSwitchCaseNamesRoundTrip()
    local source = "local result=switch op do case RETURN->do yield 1 end case CALL,TAIL_CALL->2 else->0 end"
    local expected = table.concat(
        {
            "local result = switch op do",
            "    case RETURN -> do",
            "        yield 1",
            "    end",
            "    case CALL, TAIL_CALL -> 2",
            "    else -> 0",
            "end",
            "",
        },
        "\n"
    )
    local formatted = fmt1(source)
    testAssert.eq(formatted, expected)
    testAssert.eq(fmt1(formatted), expected, "bare named cases are idempotent")
    local parsed = require("nupp.compiler.syntax.parser").parse(formatted, "bare-switch.nupp")
    testAssert.eq(#parsed.errors, 0)
    testAssert.eq(kinds(source), kinds(formatted), "formatting preserves case tokens")
end

function M.protocolClauseOrdersAndTrailingFunctionsAreIdempotent()
    for _, source in ipairs({
        "local type F=function(number)yields(number,string)resumes(boolean):string",
        "local function f(x:number)yields(number)resumes(boolean):string return 'done' end",
        "invoke(name='load',function(value:string):string return value end)",
    }) do
        local formatted = fmt1(source)
        testAssert.eq(fmt1(formatted), formatted, "formatting is idempotent")
        testAssert.eq(kinds(formatted), kinds(source), "formatting preserves syntax")
        local result = require("nupp.compiler.syntax.parser").parse(formatted)
        testAssert.eq(#result.errors, 0, result.errors[1] and result.errors[1].msg)
    end
end

return M
