_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);




















local lexer = { }
local ffi = require ( "ffi" )


const TRIVIA_WHITESPACE = 1
const TRIVIA_COMMENT = 2
const TRIVIA_HASHBANG = 3
const TRIVIA_BOM = 4
const TRIVIA_KIND_NAMES = { "whitespace" , "comment" , "hashbang" , "bom" }


const TRIVIA_STRIDE = 5













lexer.TriviaArena = {} lexer.TriviaArena.__index = lexer.TriviaArena











function lexer.TriviaArena:append(kind, offset, length, line, col)
if self . count >= self . capacity then
local grown = self . capacity > 0 ? self . capacity * 2 : 32
local fresh = ffi . new ( "uint32_t[?]" , grown * TRIVIA_STRIDE )
ffi . copy ( fresh , self . words , self . count * TRIVIA_STRIDE * 4 )
self . words = fresh
self . capacity = grown
end

local at = self . count * TRIVIA_STRIDE
do
self . words [ at ] = kind
self . words [ at + 1 ] = offset
self . words [ at + 2 ] = length
self . words [ at + 3 ] = line
self . words [ at + 4 ] = col
end
self . count = self . count + 1

return self . count
end



function lexer . arena ( source )
return setmetatable({ source =
source ,  count =
0 ,  capacity =
0 ,  words =
ffi . new ( "uint32_t[?]" , 0 ) }, lexer.TriviaArena)

end



lexer . EMPTY_TRIVIA = lexer . arena ( "" )








































































































































































































local KEYWORDS = { }
for word in (
"and break do else elseif end false for function goto if in local "
.. "nil not or repeat return sealed then true until while"
) : gmatch ( "%S+" ) do
KEYWORDS [ word ] = true
end
lexer . KEYWORDS = KEYWORDS


local OPS4 = { [ "~>>=" ] = true }
local OPS3 = { }
for op in ( "~>> ... <<= >>= //= ..= ??=" ) : gmatch ( "%S+" ) do
OPS3 [ op ] = true
end
local OPS2 = { }
for op in ( "<< >> == ~= <= >= ?. :: // .. -> ?? += -= *= /= %= &= |= " .. "&& || !=" ) : gmatch ( "%S+" ) do
OPS2 [ op ] = true
end
local OPS1 = { }
for op in ( "+ - * / % ^ # & ~ | < > = ( ) { } [ ] ; : , . ? @ !" ) : gmatch ( "%S+" ) do
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
return c and ( isDigit ( c ) or ( c >= 97 and c <= 102 ) or ( c >= 65 and c <= 70 ) )
end

local function isNameStart ( c )
return c and ( ( c >= 97 and c <= 122 ) or ( c >= 65 and c <= 90 ) or c == 95 )
end

local function isNameChar ( c )
return isNameStart ( c ) or isDigit ( c )
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
local close = "]" .. ( "=" ) : rep ( level ) .. "]"
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
if pos == 1 and sub ( source , 1 , 3 ) == "\239\187\191" then
kind , pos = TRIVIA_BOM , 4
elseif pos == 1 and sub ( source , 1 , 1 ) == "#" then
kind = TRIVIA_HASHBANG
local nl = find ( source , "\n" , pos , true )
pos = nl and ( nl + 1 ) or ( len + 1 )
elseif ch == 32 or ch == 9 or ch == 13 or ch == 10 or ch == 11 or ch == 12 then
kind = TRIVIA_WHITESPACE
repeat
pos = pos + 1
ch = byte ( source , pos )
until not ( ch == 32 or ch == 9 or ch == 13 or ch == 10 or ch == 11 or ch == 12 )
elseif ch == 45 and byte ( source , pos + 1 ) == 45 then
kind = TRIVIA_COMMENT
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
break
end
arena : append ( kind , start , pos - start , l , c )
taken = taken + 1
advanceLines ( pos )
end

return first , taken
end



local function scanShortString ( quote )
local p = pos + 1
while p <= len do
local ch = byte ( source , p )
if ch == quote then
return p + 1 , true
elseif ch == 92 then
p = p + 2
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
pos = pos + 2
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
p = skipUnderscores ( p + 1 )
p , more = scanDigits ( p , isHex )
digits = digits + more
end
if digits == 0 then
wellformed = false
end
local e = byte ( source , p )
if e == 112 or e == 80 then
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
p = p + 1
end
p = scanDigits ( p , isDigit )
if byte ( source , p ) == 46 and byte ( source , p + 1 ) ~= 46 then
p = skipUnderscores ( p + 1 )
p = scanDigits ( p , isDigit )
end
local e = byte ( source , p )
if e == 101 or e == 69 then
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

p = suffix ( "ull" ) or suffix ( "ll" ) or suffix ( "i" ) or p

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
break
end

local start = pos
local l , c = line , colOf ( pos )
local ch = byte ( source , pos )
local kind



local text = nil

if isNameStart ( ch ) then
repeat
pos = pos + 1
until not isNameChar ( byte ( source , pos ) )
text = sub ( source , start , pos - 1 )
kind = KEYWORDS [ text ] and text or "name"
elseif isDigit ( ch ) or ( ch == 46 and isDigit ( byte ( source , pos + 1 ) ) ) then
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
addError ( start , l , c , ( "unexpected character %q" ) : format ( sub ( source , start , start ) ) )
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


local function triviaWordAt ( tok , index )
return ( tok . triviaFirst + index - 2 ) * TRIVIA_STRIDE
end


function lexer . triviaCount ( tok )
return tok . triviaCount
end


function lexer . triviaKind ( tok , index )
local at = triviaWordAt ( tok , index )
local code
do
code = tok . trivia . words [ at ]
end

return TRIVIA_KIND_NAMES [ code ]
end


function lexer . triviaText ( tok , index )
local arena = tok . trivia
local at = triviaWordAt ( tok , index )
local offset
local length
do
offset = arena . words [ at + 1 ]
length = arena . words [ at + 2 ]
end

return sub ( arena . source , offset , offset + length - 1 )
end


function lexer . triviaAt ( tok , index )
local at = triviaWordAt ( tok , index )
do
local words = tok . trivia . words

return words [ at + 1 ] , words [ at + 3 ] , words [ at + 4 ]
end
end



function lexer . triviaRecord ( tok , index )
local offset , line , col = lexer . triviaAt ( tok , index )

return {
kind = lexer . triviaKind ( tok , index ) ,
text = lexer . triviaText ( tok , index ) ,
offset = offset ,
line = line ,
col = col
}
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

return lexer
