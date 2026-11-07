local testAssert = require("assert")
local fmt = require("nupp.tools.fmt")
local formatter = fmt.new()
local lexer = require("nupp.compiler.syntax.lexer")

local HERE = require("helpers.paths").tests
local ROOT = HERE .. "/.."

local function fmt1(src)
    return (formatter:format(src))
end

-- Token-kind fingerprint, ignoring trivia — formatting must never change it.
local function kinds(src)
    local tokens = lexer.lex(src)
    local out = {}
    for _, t in ipairs(tokens) do
        out[#out + 1] = t.kind
    end

    return table.concat(out, " ")
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

local function selfFormat(rel)
    local parser = require("nupp.compiler.syntax.parser")
    local f = assert(io.open(ROOT .. "/" .. rel))
    local src = f:read("*a")
    f:close()
    local once = formatter:format(src, rel)
    testAssert.eq(formatter:format(once, rel), once, "not idempotent: " .. rel)
    testAssert.eq(#parser.parse(once, rel).errors, 0, "parse changed: " .. rel)
end

return {
    testAssert = testAssert,
    fmt = fmt,
    formatter = formatter,
    lexer = lexer,
    HERE = HERE,
    ROOT = ROOT,
    fmt1 = fmt1,
    kinds = kinds,
    CORPUS = CORPUS,
    selfFormat = selfFormat,
}
