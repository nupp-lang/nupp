local fmt = require("nupp.compiler.fmt")
local lexer = require("nupp.compiler.lexer")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %q\n  got:  %q"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function fmt1(src)
   return (fmt.format(src))
end

-- Token-kind fingerprint, ignoring trivia — formatting must never change it.
local function kinds(src)
   local tokens = lexer.lex(src)
   local out = {}
   for _, t in ipairs(tokens) do out[#out + 1] = t.kind end
   return table.concat(out, " ")
end

local M = {}

function M.spacingBasics()
   assertEq(fmt1("local x=1+2"), "local x = 1 + 2\n")
   assertEq(fmt1("const x:number=1"), "const x: number = 1\n")
   assertEq(fmt1("f( x , y )"), "f(x, y)\n")
   assertEq(fmt1("local f = function () return nil end"),
      "local f = function()\n    return nil\nend\n")
   assertEq(fmt1("local f: function (number): string"),
      "local f: function(number): string\n")
   assertEq(fmt1("t . a [ 1 ] : m ( )"), "t.a[1]:m()\n")
   assertEq(fmt1('f"lit"'), 'f"lit"\n')
   assertEq(fmt1("f{1,2}"), "f{1, 2}\n")
end

function M.propertyCapabilities()
   assertEq(fmt1("local x:{readonly value:string,writeonly value:string|integer}"),
      "local x: {\n    readonly value: string,\n    writeonly value: string | integer\n}\n")
   assertEq(fmt1("local x:{readonly [string]:string,writeonly [string]:integer}"),
      "local x: {\n    readonly [string]: string,\n    writeonly [string]: integer\n}\n")
   assertEq(fmt1("local interface Cell\nreadonly value:string\nwriteonly value:integer\nend"),
      "local interface Cell\n    readonly value: string\n    writeonly value: integer\nend\n")
end

-- A construction is spelled as call sugar and is not one: the fields belong to
-- the type rather than being an argument to it, so the brace stands off it while
-- an ordinary `f{...}` keeps hugging its callee.
function M.constructionBracesStandOffTheirType()
   assertEq(fmt1("local a = new R{n = 1}"), "local a = new R {n = 1}\n")
   assertEq(fmt1("local a = new R  {n = 1}"), "local a = new R {n = 1}\n")
   assertEq(fmt1("local a = new m.Point{x = 1}"), "local a = new m.Point {x = 1}\n")
   -- parentheses stay hugged, the way every other call's do
   assertEq(fmt1("local a = new V2 (1, 2)"), "local a = new V2(1, 2)\n")
   -- and the sugar this is spelled like is untouched
   assertEq(fmt1("f{a = 1}"), "f{a = 1}\n")
end

function M.methodCallParensDefaultOn()
   assertEq(fmt1("obj:m{a = 1}"), "obj:m({a = 1})\n")
   assertEq(fmt1('obj:m"lit"'), 'obj:m("lit")\n')
   assertEq(fmt1("obj?.:m{a = 1}"), "obj?.:m({a = 1})\n")
   assertEq(fmt1("obj:m?.{a = 1}"), "obj:m?.({a = 1})\n")
   -- already parenthesized, and a plain (non-method) call: untouched
   assertEq(fmt1("obj:m({a = 1})"), "obj:m({a = 1})\n")
   assertEq(fmt1("f{a = 1}"), "f{a = 1}\n")
   assertEq(fmt1('f"lit"'), 'f"lit"\n')
end

function M.methodCallParensCanBeTurnedOff()
   local off = {methodParens = false}
   assertEq((fmt.format("obj:m{a = 1}", nil, off)), "obj:m{a = 1}\n")
   assertEq((fmt.format('obj:m"lit"', nil, off)), 'obj:m"lit"\n')
end

function M.methodCallParensIdempotent()
   local once = fmt1("obj:m{a = 1}")
   assertEq(fmt1(once), once)
   assertEq(kinds(once), "name : name ( { name = number } ) eof")
end

function M.unaryVsBinary()
   assertEq(fmt1("x = a - -b + #t"), "x = a - -b + #t\n")
   assertEq(fmt1("x = ~a ~ b"), "x = ~a ~ b\n")
end

function M.shortFunctionsAndIstrings()
   assertEq(fmt1("local f = | a , b | -> a + b"), "local f = |a, b| -> a + b\n")
   assertEq(fmt1("local g = x->x*2"), "local g = x -> x * 2\n")
   assertEq(fmt1("local h = ||->true"), "local h = || -> true\n")
   assertEq(fmt1("local n = |...args|->args.n"),
      "local n = |...args| -> args.n\n")
   assertEq(fmt1("local s = `v: ${ 1+2 } done`"), "local s = `v: ${1 + 2} done`\n")
   assertEq(fmt1("table.sort(t, |a,b| -> a.id < b.id)"),
      "table.sort(t, |a, b| -> a.id < b.id)\n")
end

function M.namedVarargSpacing()
   assertEq(fmt1("local function f(...args:number)return args.n end"),
      "local function f(...args: number)\n    return args.n\nend\n")
end

function M.ternaryAndSafeNav()
   assertEq(fmt1("x = a?b:c"), "x = a ? b : c\n")
   assertEq(fmt1("x = t ?. a ?. b"), "x = t?.a?.b\n")
   assertEq(fmt1("x = o:m()"), "x = o:m()\n")
end

function M.indentation()
   local input = table.concat({
      "if x then",
      "f()",
      "  if y then",
      "        g()",
      "end",
      "end",
   }, "\n")
   local want = table.concat({
      "if x then",
      "    f()",
      "    if y then",
      "        g()",
      "    end",
      "end",
      "",
   }, "\n")
   assertEq(fmt1(input), want)
end

-- However short the arms, an `if` is spelled as a block.
function M.inlineIfIsBrokenUp()
   assertEq(fmt1("if not ok then error(why) end"),
      "if not ok then\n    error(why)\nend\n")
   assertEq(fmt1("if a then f() elseif b then g() else h() end"),
      table.concat({
         "if a then",
         "    f()",
         "elseif b then",
         "    g()",
         "else",
         "    h()",
         "end",
         "",
      }, "\n"))
   assertEq(fmt1("if a then end"), "if a then\nend\n")
   -- a trailing comment stays with the line it followed
   assertEq(fmt1("if a then f() end -- why"),
      "if a then\n    f()\nend -- why\n")
   -- and the break is taken inside a nested block too
   assertEq(fmt1("while a do\nif b then c() end\nend"),
      "while a do\n    if b then\n        c()\n    end\nend\n")
end

-- An annotation decorates the statement below it; that statement is still a
-- statement, not a continuation line.
function M.annotatedStatementKeepsItsDepth()
   assertEq(fmt1("@owned(close)\nfunction f(): T\nreturn g()\nend"),
      "@owned(close)\nfunction f(): T\n    return g()\nend\n")
   assertEq(fmt1("@a\n@b\nlocal function f()\nend"),
      "@a\n@b\nlocal function f()\nend\n")
end

function M.tableIndentation()
   local input = "local t = {\n1,\na = 2,\n}"
   assertEq(fmt1(input), "local t = {1, a = 2,}\n")
end

function M.documentedShapeClosesOnItsOwnLine()
   assertEq(fmt1("type Options = {\n--- An option.\nflag: boolean?,}"),
      "type Options = {\n    --- An option.\n    flag: boolean?\n}\n")
end

-- `as` and `is` are contextual operators lexed as names, and what follows them
-- is a type. The call sugar that hugs `f{...}` and `f"lit"` to their callee
-- must not take them for one.
function M.contextualOperatorsAreNotCallees()
   assertEq(fmt1("local a = t as {number}"), "local a = t as {number}\n")
   assertEq(fmt1("local a = t as {p: number}"), "local a = t as {\n    p: number\n}\n")
   assertEq(fmt1('local b = v is "red"'), 'local b = v is "red"\n')
   assertEq(fmt1("local c = v is {string}"), "local c = v is {string}\n")
   -- and the sugar still hugs a real callee
   assertEq(fmt1("f{1}"), "f{1}\n")
   assertEq(fmt1('f"lit"'), 'f"lit"\n')
end

function M.continuationLines()
   local input = 'local s = a ..\n"tail"'
   assertEq(fmt1(input), 'local s = a .. "tail"\n')
end

function M.blankLineCollapse()
   assertEq(fmt1("a()\n\n\n\nb()"), "a()\n\nb()\n")
end

function M.commentsPreserved()
   local input = "local x = 1  -- tail\n-- own line\nlocal y = 2"
   assertEq(fmt1(input), "local x = 1 -- tail\n-- own line\nlocal y = 2\n")
   assertEq(fmt1("-- only a comment"), "-- only a comment\n")
end

local CORPUS = {
   "local x=1+2",
   "return a?b:c",
   "for i=1,10 do t[i]=i*2 end",
   "local t={a=1,[k]='v',f(x)}",
   "function m.s:go(...) return ... end",
   "while not done do step() end",
   "x = 1 | 2 ~ 3 & 4 << 5 ~>> 6",
   "local add = |a: number, b: number| -> a + b",
   "print(`total: ${n} of ${m}`)",
   "goto top ::top:: do break end",
   "if a then f() elseif b then g() else h() end",
   "@pure\nlocal function f() return 1 end",
   "local s = [[long\n  string]] .. 'end'",
   "-- comment file\nreturn nil",
}

function M.idempotentAndParseStable()
   for _, src in ipairs(CORPUS) do
      local once = fmt1(src)
      assertEq(fmt1(once), once, "not idempotent: " .. src)
      assertEq(kinds(once), kinds(src), "parse changed: " .. src)
   end
end

function M.supertypesStayOnTheDeclarationLine()
   -- A record's `is` clause is part of its header, not its first field. The formatter
   -- used to break every one onto its own line, which reads as a field list of one and
   -- is how nearly every record in cst.nupp came to be written that way.
   local src = table.concat({
      "local m = {}",
      "",
      "record m.B is m.A",
      "    x: integer",
      "end",
      "",
      "return m",
   }, "\n") .. "\n"
   local out = fmt.format(src, "supertypes.nupp")
   if out:find("record m.B is m.A", 1, true) == nil then
      error("the supertype stays on the header line, got:\n" .. out, 0)
   end
   assertEq(fmt.format(out, "supertypes.nupp"), out, "and the layout is stable")
end

function M.severalSupertypesStillFitOnOneLine()
   local src = table.concat({
      "local m = {}",
      "",
      "record m.C is m.A, m.B",
      "    x: integer",
      "end",
      "",
      "return m",
   }, "\n") .. "\n"
   local out = fmt.format(src, "supertypes.nupp")
   if out:find("record m.C is m.A, m.B", 1, true) == nil then
      error("a short list of contracts is still a header, got:\n" .. out, 0)
   end
end

-- One case per file rather than one loop over all six.
--
-- Formatting a compiler source twice and reparsing it is seconds of work, and together
-- they were fifty of them: the longest case in the whole suite by three orders of
-- magnitude, and on its own the floor for a parallel run, which can divide suites and
-- cases but never one case. Apart they spread across shards, and a failure names the
-- file in the case rather than only in the message.
local SELF_FORMAT = {
   {"lexer", "src/nupp/compiler/lexer.nupp"},
   {"cst", "src/nupp/compiler/cst.nupp"},
   {"parser", "src/nupp/compiler/parser.nupp"},
   {"displaywidth", "src/nupp/compiler/fmt/displaywidth.nupp"},
   {"formatter", "src/nupp/compiler/fmt/init.nupp"},
   {"main", "src/nupp/compiler/main.nupp"},
}

for _, entry in ipairs(SELF_FORMAT) do
   local label, rel = entry[1], entry[2]
   M["selfFormatStable_" .. label] = function()
      local parser = require("nupp.compiler.parser")
      local f = assert(io.open(ROOT .. "/" .. rel))
      local src = f:read("*a")
      f:close()
      local once = fmt.format(src, rel)
      assertEq(fmt.format(once, rel), once, "not idempotent: " .. rel)
      assertEq(#parser.parse(once, rel).errors, 0, "parse changed: " .. rel)
   end
end

return M
