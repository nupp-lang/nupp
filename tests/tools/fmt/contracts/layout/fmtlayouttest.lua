local fixture = require("helpers.formatfixture")
local testAssert = fixture.testAssert
local fmt1 = fixture.fmt1
local kinds = fixture.kinds
local CORPUS = fixture.CORPUS

local M = {}

function M.unaryVsBinary()
    testAssert.eq(fmt1("x = a - -b + #t"), "x = a - -b + #t\n")
    testAssert.eq(fmt1("x = ~a ~ b"), "x = ~a ~ b\n")
end

function M.shortFunctionsAndIstrings()
    testAssert.eq(fmt1("local f = | a , b | -> a + b"), "local f = |a, b| -> a + b\n")
    testAssert.eq(fmt1("local g = x->x*2"), "local g = x -> x * 2\n")
    testAssert.eq(fmt1("local h = ||->true"), "local h = || -> true\n")
    testAssert.eq(fmt1("local n = |...args|->args.n"), "local n = |...args| -> args.n\n")
    testAssert.eq(fmt1("local s = `v: ${ 1+2 } done`"), "local s = `v: ${1 + 2} done`\n")
    testAssert.eq(fmt1("table.sort(t, |a,b| -> a.id < b.id)"), "table.sort(t, |a, b| -> a.id < b.id)\n")
end

function M.namedVarargSpacing()
    testAssert.eq(
        fmt1("local function f(...args:number)return args.n end"),
        "local function f(...args: number)\n    return args.n\nend\n"
    )
end

function M.ternaryAndSafeNav()
    testAssert.eq(fmt1("x = a?b:c"), "x = a ? b : c\n")
    testAssert.eq(fmt1("x = t ?. a ?. b"), "x = t?.a?.b\n")
    testAssert.eq(fmt1("x = o:m()"), "x = o:m()\n")
end

function M.indentation()
    local input = table.concat({"if x then", "f()", "  if y then", "        g()", "end", "end",}, "\n")
    local want = table.concat({"if x then", "    f()", "    if y then", "        g()", "    end", "end", "",}, "\n")
    testAssert.eq(fmt1(input), want)
end

-- However short the arms, an `if` is spelled as a block.
function M.inlineIfIsBrokenUp()
    testAssert.eq(fmt1("if not ok then error(why) end"), "if not ok then\n    error(why)\nend\n")
    testAssert.eq(
        fmt1("if a then f() elseif b then g() else h() end"),
        table.concat({"if a then", "    f()", "elseif b then", "    g()", "else", "    h()", "end", "",}, "\n")
    )
    testAssert.eq(fmt1("if a then end"), "if a then\nend\n")
    -- a trailing comment stays with the line it followed
    testAssert.eq(fmt1("if a then f() end -- why"), "if a then\n    f()\nend -- why\n")
    -- and the break is taken inside a nested block too
    testAssert.eq(fmt1("while a do\nif b then c() end\nend"), "while a do\n    if b then\n        c()\n    end\nend\n")
end

-- An annotation decorates the statement below it; that statement is still a
-- statement, not a continuation line.
function M.annotatedStatementKeepsItsDepth()
    testAssert.eq(
        fmt1("@allow(NUPP2507)\nfunction f(): T\nreturn g()\nend"),
        "@allow(NUPP2507)\nfunction f(): T\n    return g()\nend\n"
    )
    testAssert.eq(fmt1("@a\n@b\nlocal function f()\nend"), "@a\n@b\nlocal function f()\nend\n")
end

function M.tableIndentation()
    local input = "local t = {\n1,\na = 2,\n}"
    testAssert.eq(fmt1(input), "local t = {1, a = 2,}\n")
end

function M.documentedShapeClosesOnItsOwnLine()
    testAssert.eq(
        fmt1("type Options = {\n--- An option.\nflag: boolean?,}"),
        "type Options = {\n    --- An option.\n    flag: boolean?\n}\n"
    )
end

-- `as` and `is` are contextual operators lexed as names, and what follows them
-- is a type. The call sugar that hugs `f{...}` and `f"lit"` to their callee
-- must not take them for one.
function M.contextualOperatorsAreNotCallees()
    testAssert.eq(fmt1("local a = t as {number}"), "local a = t as {number}\n")
    testAssert.eq(fmt1("local a = t as {p: number}"), "local a = t as {p: number}\n")
    testAssert.eq(fmt1("local a = t as {p: number, q: string}"), "local a = t as {\n    p: number,\n    q: string\n}\n")
    testAssert.eq(fmt1('local b = v is "red"'), 'local b = v is "red"\n')
    testAssert.eq(fmt1("local c = v is {string}"), "local c = v is {string}\n")
    -- and the sugar still hugs a real callee
    testAssert.eq(fmt1("f{1}"), "f{1}\n")
    testAssert.eq(fmt1('f"lit"'), 'f"lit"\n')
end

function M.continuationLines()
    local input = 'local s = a ..\n"tail"'
    testAssert.eq(fmt1(input), 'local s = a .. "tail"\n')
end

function M.blankLineCollapse()
    testAssert.eq(fmt1("a()\n\n\n\nb()"), "a()\n\nb()\n")
end

function M.commentsPreserved()
    local input = "local x = 1  -- tail\n-- own line\nlocal y = 2"
    testAssert.eq(fmt1(input), "local x = 1 -- tail\n-- own line\nlocal y = 2\n")
    testAssert.eq(fmt1("-- only a comment"), "-- only a comment\n")
end

function M.idempotentAndParseStable()
    for _, src in ipairs(CORPUS) do
        local once = fmt1(src)
        testAssert.eq(fmt1(once), once, "not idempotent: " .. src)
        testAssert.eq(kinds(once), kinds(src), "parse changed: " .. src)
    end
end

return M
