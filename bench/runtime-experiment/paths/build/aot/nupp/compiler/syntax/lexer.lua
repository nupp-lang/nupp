_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()























local lexer = { }
local triviaarena = require ( "nupp.compiler.syntax.triviaarena" )






const TRIVIA_WHITESPACE = 1
const TRIVIA_COMMENT = 2
const TRIVIA_HASHBANG = 3
const TRIVIA_BOM = 4
const TRIVIA_KIND_NAMES = { "whitespace" , "comment" , "hashbang" , "bom" }


















function lexer . arena ( source ) 
return triviaarena . new ( source )
end





















































































































































































































local KEYWORDS = { }
for word in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while")


: gmatch ( "%S+" ) do
KEYWORDS [ word ] = true
end
lexer . KEYWORDS = KEYWORDS


local OPS4 = { [ "~>>=" ] = true }
local OPS3 = { }
for op in ("~>> ... <<= >>= //= ..= ??=") : gmatch ( "%S+" ) do
OPS3 [ op ] = true
end
local OPS2 = { }
for op in ("<< >> == ~= <= >= ?. :: // .. -> ?? += -= *= /= %= &= |= && || !=") : gmatch ( "%S+" ) do
OPS2 [ op ] = true
end
local OPS1 = { }
for op in ("+ - * / % ^ # & ~ | < > = ( ) { } [ ] ; : , . ? @ !") : gmatch ( "%S+" ) do
OPS1 [ op ] = true
end







local OPS1BYTE = { }
local OPS2BYTE = { }
local OPS3BYTE = { }
local OPS4BYTE = { }
for op in pairs ( OPS1 ) do
OPS1BYTE [ string . byte ( op , 1 ) ] = op
end
for op in pairs ( OPS2 ) do
local a , b = string . byte ( op , 1 , 2 )
OPS2BYTE [ a * 256 + b ] = op
end
for op in pairs ( OPS3 ) do
local a , b , c = string . byte ( op , 1 , 3 )
OPS3BYTE [ ( a * 256 + b ) * 256 + c ] = op
end
for op in pairs ( OPS4 ) do
local a , b , c , d = string . byte ( op , 1 , 4 )
OPS4BYTE [ ( ( a * 256 + b ) * 256 + c ) * 256 + d ] = op
end










local CUSTOMARY = { [ "!" ] = "not" , [ "&&" ] = "and" , [ "||" ] = "or" , [ "!=" ] = "~=" , }




lexer . CUSTOMARY = CUSTOMARY

local byte , sub , find = string . byte , string . sub , string . find





local function isDigit ( c ) 
return c and c >= 48 and c <= 57
end

local function isHex ( c ) 
return c and ( ( c and c >= 48 and c <= 57 ) or ( c >= 97 and c <= 102 ) or ( c >= 65 and c <= 70 ) )
end

local function isNameStart ( c ) 
return c and ( ( c >= 97 and c <= 122 ) or ( c >= 65 and c <= 90 ) or c == 95 )
end

local function isNameChar ( c ) 
return ( c and ( ( c >= 97 and c <= 122 ) or ( c >= 65 and c <= 90 ) or c == 95 ) ) or ( c and c >= 48 and c <= 57 )
end









local function scanLongBracket ( src , pos ) 
if byte ( src , pos ) ~= 91 then
return nil , false
end
local level = 0
local p = pos + 1
while byte ( src , p ) == 61 do
level = level + 1 ;
p = p + 1
end
if byte ( src , p ) ~= 91 then
return nil , false
end
local close = "]" .. ("=") : rep ( level ) .. "]"
local s = find ( src , close , p + 1 , true )
if not s then
return # src + 1 , false
end

return s + # close , true
end





function lexer . lex ( source , filename ) 
local tokens = { }
local errors = { }
local arena = lexer . arena ( source )
local pos = 1
local line = 1
local lineStart = 1
local len = # source



local interp = { }

local function colOf ( offset ) 
return offset - lineStart + 1
end





local nextNewline = find ( source , "\n" , 1 , true ) or ( len + 1 )


local function advanceLines ( endpos ) 
while nextNewline < endpos do
line = line + 1
lineStart = nextNewline + 1
nextNewline = find ( source , "\n" , nextNewline + 1 , true ) or ( len + 1 )
end
end

local function addError ( offset , l , c , msg ) 
errors [
# errors + 1
] = {
code = "NUPP1001" ,
offset = offset ,
length = math . max ( 1 , pos - offset ) ,
line = l ,
col = c ,
msg = msg ,
filename = filename
}
end



local function scanTrivia ( ) 
local first = arena . count + 1
local taken = 0
while pos <= len do
local start = pos
local l , c = line , colOf ( pos )
local ch = byte ( source , pos )
local kind
if pos == 1 and sub ( source , 1 , 3 ) == "﻿" then
kind , pos = 4 , 4
elseif ( pos == 1 or pos == 4 and sub ( source , 1 , 3 ) == "﻿" ) and sub ( source , pos , pos ) == "#" then
kind = 3
local nl = find ( source , "\n" , pos , true )
pos = nl and ( nl + 1 ) or ( len + 1 )
elseif ch == 32 or ch == 9 or ch == 13 or ch == 10 or ch == 11 or ch == 12 then
kind = 1
repeat
pos = pos + 1
ch = byte ( source , pos )
until not ( ch == 32 or ch == 9 or ch == 13 or ch == 10 or ch == 11 or ch == 12 )
elseif ch == 45 and byte ( source , pos + 1 ) == 45 then
kind = 2
local after , terminated = scanLongBracket ( source , pos + 2 )
if after and terminated then
pos = after
elseif after then
pos = len + 1
addError ( start , l , c , "unterminated long comment" )
else
local nl = find ( source , "\n" , pos + 2 , true )
pos = nl or ( len + 1 )
end
else
do break end
end
arena : append ( kind , start , pos - start , l , c )
taken = taken + 1
advanceLines ( pos )
end

return first , taken
end








local function scanEscape ( p , quote ) 
local function upTo ( at ) 
local stop = byte ( source , at )
if stop == nil or stop == quote or stop == 10 or stop == 13 then
return at - 1
end

return at
end

local function hexValue ( digit ) 
if not digit then
return nil
elseif ( digit and digit >= 48 and digit <= 57 ) then
return digit - 48
elseif digit >= 97 and digit <= 102 then
return digit - 87
elseif digit >= 65 and digit <= 70 then
return digit - 55
end

return nil
end

local ch = byte ( source , p + 1 )
if ch == nil then
return p + 1 , true , p
elseif ch == 10 or ch == 13 then
local after = byte ( source , p + 2 )
if after ~= ch and ( after == 10 or after == 13 ) then
return p + 3 , true , p
end
return p + 2 , true , p
elseif ch == 122 then
local at = p + 2
local next = byte ( source , at )
while next == 32 or next == 9 or next == 10 or next == 13 or next == 11 or next == 12 do
at = at + 1
next = byte ( source , at )
end
return at , true , p
elseif ch == 120 then
local at = p + 2
for _ = 1 , 2 do
if not hexValue ( byte ( source , at ) ) then
return at , false , upTo ( at )
end
at = at + 1
end
return at , true , p
elseif ch == 117 then
if byte ( source , p + 2 ) ~= 123 then
return p + 2 , false , upTo ( p + 2 )
end
local at , value , digits = p + 3 , 0 , 0
local amount = hexValue ( byte ( source , at ) )
while amount do
value = value * 16 + amount
digits = digits + 1
at = at + 1
amount = hexValue ( byte ( source , at ) )
end
if byte ( source , at ) ~= 125 then
return at , false , upTo ( at )
end
return at + 1 , digits > 0 and value <= 1114111 , at
elseif ( ch and ch >= 48 and ch <= 57 ) then
local at , value = p + 1 , 0
for _ = 1 , 3 do
local digit = byte ( source , at )
if not ( digit and ( digit and digit >= 48 and digit <= 57 ) ) then
do break end
end
value = value * 10 + digit - 48
at = at + 1
end
return at , value <= 255 , at - 1
elseif ch == 97
or ch == 98
or ch == 102
or ch == 110
or ch == 114
or ch == 116
or ch == 118
or ch == 92
or ch == 34
or ch == 39
then
return p + 2 , true , p
end

return p + 2 , false , p + 1
end




local function scanShortString ( quote ) 
local p = pos + 1
while p <= len do
local ch = byte ( source , p )
if ch == quote then
return p + 1 , true
elseif ch == 92 then
local after , valid , shown = scanEscape ( p , quote )
if not valid then
local lineAt , startAt = line , lineStart
local newline = nextNewline
while newline < p do
lineAt = lineAt + 1
startAt = newline + 1
newline = find ( source , "\n" , newline + 1 , true ) or ( len + 1 )
end
errors [
# errors + 1
] = {
code = "NUPP1001" ,
offset = p ,
length = shown - p + 1 ,
line = lineAt ,
col = p - startAt + 1 ,
msg = ("invalid escape sequence '%s'") : format ( sub ( source , p , shown ) ) ,
filename = filename
}
end
p = math . min ( after , len + 1 )
elseif ch == 10 then
return p , false
else
p = p + 1
end
end

return len + 1 , false
end






local function scanIstring ( opening ) 
local start = pos
local l , c = line , colOf ( pos )
pos = pos + 1
while pos <= len do
local ch = byte ( source , pos )
if ch == 92 then



pos = math . min ( pos + 2 , len + 1 )
elseif ch == 96 then
pos = pos + 1
if opening then
return "string"
end
interp [ # interp ] = nil
return "istringClose"
elseif ch == 36 and byte ( source , pos + 1 ) == 123 then
pos = pos + 2
if opening then
interp [ # interp + 1 ] = 0
else
interp [ # interp ] = 0
end
return opening and "istringOpen" or "istringMid"
else
pos = pos + 1
end
end
if not opening then
interp [ # interp ] = nil
end
addError ( start , l , c , "unterminated interpolated string" )

return "error"
end



local function scanNumber ( ) 
local p = pos
local wellformed = true
local fractional = false



local function skipUnderscores ( at ) 
while byte ( source , at ) == 95 do
at = at + 1
end
return at
end

local function scanDigits ( at , predicate ) 
local digits = 0
while predicate ( byte ( source , at ) ) do
digits = digits + 1
at = skipUnderscores ( at + 1 )
end

return at , digits
end

local marker = byte ( source , p ) == 48 and skipUnderscores ( p + 1 ) or p + 1
if byte ( source , p ) == 48 and ( byte ( source , marker ) == 120 or byte ( source , marker ) == 88 ) then

p = skipUnderscores ( marker + 1 )
local digits , more
p , digits = scanDigits ( p , isHex )
if byte ( source , p ) == 46 and byte ( source , p + 1 ) ~= 46 then
fractional = true
p = skipUnderscores ( p + 1 )
p , more = scanDigits ( p , isHex )
digits = digits + more
end
if digits == 0 then
wellformed = false
end
local e = byte ( source , p )
if e == 112 or e == 80 then
fractional = true
p = skipUnderscores ( p + 1 )
local s = byte ( source , p )
if s == 43 or s == 45 then
p = skipUnderscores ( p + 1 )
end
if not isDigit ( byte ( source , p ) ) then
wellformed = false
end
p = scanDigits ( p , isDigit )
end
else

if byte ( source , p ) == 46 then
fractional = true
p = p + 1
end
p = scanDigits ( p , isDigit )
if byte ( source , p ) == 46 and byte ( source , p + 1 ) ~= 46 then
fractional = true
p = skipUnderscores ( p + 1 )
p = scanDigits ( p , isDigit )
end
local e = byte ( source , p )
if e == 101 or e == 69 then
fractional = true
p = skipUnderscores ( p + 1 )
local s = byte ( source , p )
if s == 43 or s == 45 then
p = skipUnderscores ( p + 1 )
end
if not isDigit ( byte ( source , p ) ) then
wellformed = false
end
p = scanDigits ( p , isDigit )
end
end


local function suffix ( word ) 
local at = p
for j = 1 , # word do
local ch = byte ( source , at )
if ch and ch >= 65 and ch <= 90 then
ch = ch + 32
end
if ch ~= byte ( word , j ) then
return nil
end
at = skipUnderscores ( at + 1 )
end

return at
end



local integerSuffix = suffix ( "ull" ) or suffix ( "ll" )
if integerSuffix and fractional then
wellformed = false
end
p = integerSuffix or suffix ( "i" ) or p

if isNameChar ( byte ( source , p ) ) then
repeat
p = p + 1
until not isNameChar ( byte ( source , p ) )
wellformed = false
end

return p , wellformed
end

while true do
local triviaFirst , triviaCount = scanTrivia ( )
if pos > len then
if # interp > 0 then
addError ( pos , line , colOf ( pos ) , "unterminated interpolated string" )
end
tokens [
# tokens + 1
] = {
kind = "eof" ,
text = "" ,
offset = pos ,
line = line ,
col = colOf ( pos ) ,
trivia = arena ,
triviaFirst = triviaFirst ,
triviaCount = triviaCount
}
do break end
end

local start = pos
local l , c = line , colOf ( pos )
local ch = byte ( source , pos )
local kind



local text = nil

if ( ch and ( ( ch >= 97 and ch <= 122 ) or ( ch >= 65 and ch <= 90 ) or ch == 95 ) ) then
repeat
pos = pos + 1
until not isNameChar ( byte ( source , pos ) )
text = sub ( source , start , pos - 1 )
kind = KEYWORDS [ text ] and text or "name"
elseif ( ch and ch >= 48 and ch <= 57 ) or ( ch == 46 and isDigit ( byte ( source , pos + 1 ) ) ) then
local endpos , ok = scanNumber ( )
pos = endpos
if ok then
kind = "number"
else
kind = "error"
addError ( start , l , c , "malformed number" )
end
elseif ch == 34 or ch == 39 then
local endpos , terminated = scanShortString ( ch )
pos = endpos
if terminated then
kind = "string"
else
kind = "error"
addError ( start , l , c , "unterminated string" )
end
elseif ch == 96 then
kind = scanIstring ( true )
elseif ch == 123 and # interp > 0 then
interp [ # interp ] = interp [ # interp ] + 1
pos = pos + 1
kind = "{"
elseif ch == 125 and # interp > 0 and interp [ # interp ] == 0 then
kind = scanIstring ( false )
elseif ch == 125 and # interp > 0 then
interp [ # interp ] = interp [ # interp ] - 1
pos = pos + 1
kind = "}"
elseif ch == 91 then
local after , terminated = scanLongBracket ( source , pos )
if after and terminated then
pos = after
kind = "string"
elseif after then
pos = len + 1
kind = "error"
addError ( start , l , c , "unterminated long string" )
else
pos = pos + 1
kind = "["
end
else
local remaining = len - pos + 1
local b1 = ch
local packed = b1
local matched = OPS1BYTE [ packed ]
if remaining >= 2 then
packed = packed * 256 + ( byte ( source , pos + 1 ) )
matched = OPS2BYTE [ packed ] or matched
if remaining >= 3 then
packed = packed * 256 + ( byte ( source , pos + 2 ) )
matched = OPS3BYTE [ packed ] or matched
if remaining >= 4 then
packed = packed * 256 + ( byte ( source , pos + 3 ) )
matched = OPS4BYTE [ packed ] or matched
end
end
end
if matched then
pos = pos + # matched
kind = matched
text = matched
else
pos = pos + 1
kind = "error"


local bad = sub ( source , start , start )
local shown = byte ( bad ) >= 128 and ("\"\\x%02X\"") : format ( byte ( bad ) ) or ("%q") : format ( bad )
addError ( start , l , c , "unexpected character " .. shown )
end
end

kind = CUSTOMARY [ kind ] or kind
tokens [
# tokens + 1
] = {
kind = kind ,
text = text or sub ( source , start , pos - 1 ) ,
offset = start ,
line = l ,
col = c ,
trivia = arena ,
triviaFirst = triviaFirst ,
triviaCount = triviaCount
}
advanceLines ( pos )
end

return tokens , errors
end





local function triviaIndex ( tok , index ) 
return tok . triviaFirst + index - 1
end


function lexer . triviaKind ( tok , index ) 
local code = tok . trivia : record ( ( tok . triviaFirst + index - 1 ) )

return TRIVIA_KIND_NAMES [ code ]
end


function lexer . triviaText ( tok , index ) 
local arena = tok . trivia
local _ , offset , length = arena : record ( ( tok . triviaFirst + index - 1 ) )

return sub ( arena . source , offset , offset + length - 1 )
end


function lexer . triviaFields ( tok , index ) 
local arena = tok . trivia
local kind , offset , length , line , col = arena : record ( ( tok . triviaFirst + index - 1 ) )

return TRIVIA_KIND_NAMES [ kind ] , sub ( arena . source , offset , offset + length - 1 ) , offset , line , col
end



function lexer . triviaRecord ( tok , index ) 
local kind , text , offset , line , col = lexer . triviaFields ( tok , index )

return { kind = kind , text = text , offset = offset , line = line , col = col }
end






function lexer . textOf ( tokens ) 
local parts = { }
for _ , tok in ipairs ( tokens ) do
for index = 1 , tok . triviaCount do
parts [ # parts + 1 ] = lexer . triviaText ( tok , index )
end
parts [ # parts + 1 ] = tok . text
end

return table . concat ( parts )
end







function lexer . quoteBacktickBody ( body ) 
local quoted = body : gsub ( "(\\?)(.)" , function ( backslash , char ) 
if backslash ~= "" then
if char == "`" or char == "$" then
return char
end

return backslash .. char
elseif char == "\"" then
return "\\\""
elseif char == "\n" then
return "\\n"
end

return char
end )

return "\"" .. quoted .. "\""
end








function lexer . stringValue ( text ) 
local first = text : sub ( 1 , 1 )
local quoted
if first == "\"" or first == "'" then
quoted = text
elseif first == "`" and # text >= 2 and text : sub ( -1 ) == "`" then
quoted = lexer . quoteBacktickBody ( text : sub ( 2 , -2 ) )
end
if quoted == nil then
return nil
end
local chunk = loadstring ( "return " .. ( quoted ) )
if not chunk then
return nil
end
local ok , value = pcall ( chunk )
if not ok or type ( value ) ~= "string" then
return nil
end

return value
end

local __nuppExportValue= lexer ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.syntax.lexer"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.syntax.lexer"]=__nuppExports;return __nuppExports