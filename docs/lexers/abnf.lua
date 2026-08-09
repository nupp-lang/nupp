-- ABNF (RFC 5234, RFC 7405) LPeg lexer, for the docs site's grammar reference.
-- Scintillua does not ship one; this is the whole reason a project lexers
-- directory exists at all — see nupp.compiler.doc.highlight.

local lexer = lexer
local P, S = lpeg.P, lpeg.S

local lex = lexer.new(...)

-- Whitespace.
lex:add_rule('whitespace', lex:tag(lexer.WHITESPACE, lexer.space^1))

-- Comments run to end of line, `;`.
lex:add_rule('comment', lex:tag(lexer.COMMENT, lexer.to_eol(';')))

-- Quoted terminals, optionally prefixed by RFC 7405's case-sensitivity marker:
-- %s"if" is case-sensitive, %i"if" (the ABNF default) is not.
local case_prefix = P('%s') + P('%i')
local dq_str = lexer.range('"', '"', true)
lex:add_rule('string', lex:tag(lexer.STRING, case_prefix^-1 * dq_str))

-- Numeric terminal values: %x41-5A, %d13.10, %xEF.BB.BF, %b0110 — a base
-- marker followed by digit runs joined by '-' (range) or '.' (concatenation).
local numval = P('%') * S('xdb') * lexer.alnum^1 * (S('-.') * lexer.alnum^1)^0
lex:add_rule('numval', lex:tag(lexer.NUMBER, numval))

-- Bare repetition counts, as in 1*element or 3*5DIGIT.
lex:add_rule('number', lex:tag(lexer.NUMBER, lexer.digit^1))

-- Rule names: a letter, then letters, digits, or hyphens.
lex:add_rule('identifier', lex:tag(lexer.IDENTIFIER, lexer.alpha * (lexer.alnum + P('-'))^0))

-- Definition, alternation, repetition, and grouping.
lex:add_rule('operator', lex:tag(lexer.OPERATOR, S('=/*()[]')))

lexer.property['scintillua.comment'] = ';'

return lex
