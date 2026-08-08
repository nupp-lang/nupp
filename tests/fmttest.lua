local fmt = require("nupp.fmt")
local lexer = require("nupp.lexer")

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
      "local f = function() return nil end\n")
   assertEq(fmt1("local f: function (number): string"),
      "local f: function(number): string\n")
   assertEq(fmt1("t . a [ 1 ] : m ( )"), "t.a[1]:m()\n")
   assertEq(fmt1('f"lit"'), 'f"lit"\n')
   assertEq(fmt1("f{1,2}"), "f{1, 2}\n")
end

function M.propertyCapabilities()
   assertEq(fmt1("local x:{read value:string,write value:string|integer}"),
      "local x: {read value: string, write value: string | integer}\n")
   assertEq(fmt1("local x:{read [string]:string,write [string]:integer}"),
      "local x: {read [string]: string, write [string]: integer}\n")
   assertEq(fmt1("local interface Cell\nread value:string\nwrite value:integer\nend"),
      "local interface Cell\n    read value: string\n    write value: integer\nend\n")
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
      "local function f(...args: number) return args.n end\n")
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
   assertEq(fmt1(input), "local t = {\n    1,\n    a = 2,\n}\n")
end

-- `as` and `is` are contextual operators lexed as names, and what follows them
-- is a type. The call sugar that hugs `f{...}` and `f"lit"` to their callee
-- must not take them for one.
function M.contextualOperatorsAreNotCallees()
   assertEq(fmt1("local a = t as {number}"), "local a = t as {number}\n")
   assertEq(fmt1("local a = t as {p: number}"), "local a = t as {p: number}\n")
   assertEq(fmt1('local b = v is "red"'), 'local b = v is "red"\n')
   assertEq(fmt1("local c = v is {string}"), "local c = v is {string}\n")
   -- and the sugar still hugs a real callee
   assertEq(fmt1("f{1}"), "f{1}\n")
   assertEq(fmt1('f"lit"'), 'f"lit"\n')
end

function M.continuationLines()
   local input = 'local s = a ..\n"tail"'
   assertEq(fmt1(input), 'local s = a ..\n    "tail"\n')
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

function M.selfFormatStable()
   for _, rel in ipairs({
      "src/nupp/lexer.nupp", "src/nupp/cst.nupp", "src/nupp/parser.nupp",
      "src/nupp/fmt/displaywidth.nupp", "src/nupp/fmt/init.nupp",
      "src/nupp/main.nupp",
   }) do
      local f = assert(io.open(ROOT .. "/" .. rel))
      local src = f:read("*a")
      f:close()
      local once = fmt.format(src, rel)
      assertEq(fmt.format(once, rel), once, "not idempotent: " .. rel)
      assertEq(kinds(once), kinds(src), "parse changed: " .. rel)
   end
end

return M
