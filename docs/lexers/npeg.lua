-- Nupp parsing-expression grammar (NPEG) lexer for Scintillua.
--
-- This is the byte-oriented LPeg 1.1 `re` grammar accepted by
-- `nupp.peg.compile`. Keep the lexer deliberately lexical; the compiler remains
-- the authority on whether a definition, rule reference, or capture is valid.

local lexer = lexer
local P, S = lpeg.P, lpeg.S

local lex = lexer.new(...)

local name = (lexer.alpha + P("_")) * (lexer.alnum + P("_"))^0
local quoted = P("'") * (1 - S("'\r\n"))^0 * P("'")
   + P('"') * (1 - S('"\r\n'))^0 * P('"')
local byteClass = P("[") * (1 - S("]\r\n"))^0 * P("]")
local predefined = P("%") * name

lex:add_rule("whitespace", lex:tag(lexer.WHITESPACE, lexer.space^1))
lex:add_rule("comment", lex:tag(lexer.COMMENT, lexer.to_eol("--")))
lex:add_rule("string", lex:tag(lexer.STRING, quoted))
lex:add_rule("class", lex:tag(lexer.CLASS, byteClass + predefined))

-- A name followed by `<-` starts a rule. Rule references remain variables, so
-- their use is visually distinct from a declaration without guessing whether
-- they resolve.
lex:add_rule("rule", lex:tag(lexer.FUNCTION, name * #(lexer.space^0 * P("<-"))))
lex:add_rule("reference", lex:tag(lexer.VARIABLE, P("<") * name * P(">") + name))
lex:add_rule("number", lex:tag(lexer.NUMBER, lexer.digit^1))

-- Longest forms must come first: Scintillua applies one rule at a time.
lex:add_rule("operator", lex:tag(lexer.OPERATOR,
   P("<-") + P("=>") + P("->") + P(">>") + P("~>")
      + P("{|") + P("|}") + P("{:") + P(":}") + P("{~") + P("~}")
      + S("/|{}()[]?*+^&!.-<>:=~")))

lexer.property["scintillua.comment"] = "--"

return lex
