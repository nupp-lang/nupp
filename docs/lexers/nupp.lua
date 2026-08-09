-- Nupp LPeg lexer for Scintillua. It inherits Lua's comments, strings, labels,
-- functions and folding, then replaces the lexical surface Nupp extends.

local lexer = lexer
local P, S = lpeg.P, lpeg.S

local lex = lexer.new(..., {inherit = lexer.load("lua")})

-- Annotations precede names so @owned and the file-level @!internal/@!nofmt
-- forms are one semantic token rather than an operator followed by a variable.
local annotation = lex:tag(lexer.ANNOTATION, P("@") * P("!")^-1 * lexer.word)
local builtinType = lex:tag(lexer.TYPE, lex:word_match(lexer.TYPE))
local keyword = lex:tag(lexer.KEYWORD, lex:word_match(lexer.KEYWORD))
lex:modify_rule("keyword", annotation + builtinType + keyword)

-- Backticks may contain ${...}; Scintillua does not recursively embed a lexer in
-- itself, so the complete interpolated string keeps the string style.
lex:modify_rule("string", lex:get_rule("string") + lex:tag(lexer.STRING, lexer.range("`")))

-- Nupp accepts separators throughout numerals and LuaJIT's ULL/LL and imaginary
-- suffixes. Keep the longest forms together so their suffix is not painted as a name.
local underscore = P("_")
local decDigits = lexer.digit * (lexer.digit + underscore)^0
local hexDigits = lexer.xdigit * (lexer.xdigit + underscore)^0
local exponent = S("eE") * underscore^0 * S("+-")^-1 * underscore^0 * decDigits
local hexExponent = S("pP") * underscore^0 * S("+-")^-1 * underscore^0 * decDigits
local intSuffix = S("uU")^-1 * underscore^0 * S("lL") * underscore^0 * S("lL")
local suffix = (intSuffix + S("iI")) * underscore^0
local decimal = (decDigits * (P(".") * -P(".") * (lexer.digit + underscore)^0)^-1
   + P(".") * decDigits) * exponent^-1
local hexadecimal = P("0") * underscore^0 * S("xX") * underscore^0 * hexDigits
   * (P(".") * -P(".") * (lexer.xdigit + underscore)^0)^-1 * hexExponent^-1
lex:modify_rule("number", lex:tag(lexer.NUMBER, (hexadecimal + decimal) * suffix^-1))

-- Longest first: Scintillua tags one rule match at a time, so compound and safe
-- operators should not be split into visually unrelated pieces.
local operator = P("~>>=") + P("...") + P("<<=") + P(">>=") + P("//=")
   + P("..=") + P("??=") + P("~>>") + P("<<") + P(">>") + P("==")
   + P("~=") + P("<=") + P(">=") + P("!=") + P("&&") + P("||")
   + P("??") + P("?.") + P("::") + P("//") + P("..") + P("->")
   + P("+=") + P("-=") + P("*=") + P("/=") + P("%=") + P("&=")
   + P("|=") + S("+-*/%^#&~|<>=?:@!;,.{}[]()")
lex:modify_rule("operator", lex:tag(lexer.OPERATOR, operator))

lex:set_word_list(lexer.KEYWORD, {
   "and", "as", "break", "borrows", "cdef", "const", "constructor", "continue",
   "do", "else", "elseif", "end", "exclusive", "false", "for", "from", "function",
   "global", "goto", "if", "in", "interface", "is", "local", "matches", "metamethod",
   "new", "nil", "not", "or", "out", "readonly", "record", "releases", "repeat",
   "resumes", "retains", "return", "struct", "takes", "then", "true", "unsafe",
   "until", "where", "while", "with", "writeonly", "yields",
})

lex:set_word_list(lexer.TYPE, {
   "any", "boolean", "borrowed", "cdata", "cstring", "ctype", "float", "int8", "int16",
   "int32", "int64", "integer", "metatable", "never", "number", "owned", "pinned",
   "string", "table", "thread", "uint8", "uint16", "uint32", "uint64", "unknown",
   "userdata", "voidptr",
})

lexer.property["scintillua.comment"] = "--"

return lex
