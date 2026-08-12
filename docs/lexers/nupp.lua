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

-- `comptime` and `nosuspend` change when code runs rather than what it does,
-- so they get a preprocessor-style colour instead of blending into ordinary
-- control keywords.
local compileTimeKeyword = lex:tag(lexer.PREPROCESSOR, lexer.word_match({"comptime", "nosuspend"}))

-- `associated type Name` only means something as a pair, on one line, inside a
-- record or interface body -- `type` alone is never a keyword elsewhere -- so
-- match the two words together rather than adding `type` to the keyword list.
local associatedType = lex:tag(lexer.KEYWORD,
   P("associated") * S(" \t")^1 * P("type") * #(-(lexer.alnum + P("_"))))

lex:modify_rule("keyword", annotation + builtinType + compileTimeKeyword + associatedType + keyword)

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
   "do", "else", "elseif", "end", "exclusive", "false",
   "for", "from", "function", "global", "goto", "handle", "if", "in",
   "interface", "is", "keyof", "local", "matches", "metamethod", "new", "nil",
   "not", "or", "out", "preserves", "readonly", "record", "releases",
   "repeat", "resumes", "retains", "return", "scoped", "struct", "suspension", "takes",
   "then", "true", "unpackof", "unsafe", "until", "where", "while",
   "with", "writekeyof", "writeof", "writeonly", "yields",
})

lex:set_word_list(lexer.TYPE, {
   "any", "boolean", "borrowed", "cdata", "cstring", "ctype", "float", "int8", "int16",
   "int32", "int64", "integer", "metatable", "never", "number", "owned", "pinned",
   "string", "table", "thread", "uint8", "uint16", "uint32", "uint64", "unknown",
   "userdata", "voidptr",
})

lexer.property["scintillua.comment"] = "--"

return lex
