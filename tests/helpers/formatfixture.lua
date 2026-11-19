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

return {
    testAssert = testAssert,
    fmt = fmt,
    formatter = formatter,
    lexer = lexer,
    HERE = HERE,
    ROOT = ROOT,
    fmt1 = fmt1,
    kinds = kinds,
}
