_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);











local lexer = require ( "nupp.compiler.lexer" )
local cst = require ( "nupp.compiler.cst" )

local parser = { }


























local add = cst . add



local BINPRI = {
[ "or" ] = { 1 , 1 } ,
[ "??" ] = { 1 , 1 } ,
[ "and" ] = { 2 , 2 } ,
[ "<" ] = { 3 , 3 } ,
[ ">" ] = { 3 , 3 } ,
[ "<=" ] = { 3 , 3 } ,
[ ">=" ] = { 3 , 3 } ,
[ "~=" ] = { 3 , 3 } ,
[ "==" ] = { 3 , 3 } ,
[ "|" ] = { 4 , 4 } ,
[ "~" ] = { 5 , 5 } ,
[ "&" ] = { 6 , 6 } ,
[ "<<" ] = { 7 , 7 } ,
[ ">>" ] = { 7 , 7 } ,
[ "~>>" ] = { 7 , 7 } ,
[ ".." ] = { 9 , 8 } ,
[ "+" ] = { 10 , 10 } ,
[ "-" ] = { 10 , 10 } ,
[ "*" ] = { 11 , 11 } ,
[ "/" ] = { 11 , 11 } ,
[ "//" ] = { 11 , 11 } ,
[ "%" ] = { 11 , 11 } ,
[ "^" ] = { 14 , 13 } ,
}
local UNARY_PRI = 12
local UNOPS = { [ "not" ] = true , [ "#" ] = true , [ "-" ] = true , [ "~" ] = true }

local BLOCK_FOLLOW = { [ "eof" ] = true , [ "end" ] = true , [ "else" ] = true , [ "elseif" ] = true , [ "until" ] = true , }

local EXPR_START = {
[ "number" ] = true ,
[ "string" ] = true ,
[ "nil" ] = true ,
[ "true" ] = true ,
[ "false" ] = true ,
[ "..." ] = true ,
[ "function" ] = true ,
[ "{" ] = true ,
[ "name" ] = true ,
[ "(" ] = true ,
[ "|" ] = true ,
[ "istringOpen" ] = true ,
}









function parser . parse ( source , filename )
local tokens , errors = lexer . lex ( source , filename )
local i = 1



local noMethod = 0



local loopDepth = 0


local function cur ( )
return tokens [ i ]
end





local function atEmptyPipes ( )
local tok = tokens [ i ]
return tok . kind == "or" and tok . text == "||"
end




local function startsShortfn ( at )
local tok = tokens [ at ]

return tok ~= nil and ( tok . kind == "|" or ( tok . kind == "or" and tok . text == "||" ) )
end


local function atExprStart ( )
local kind = tokens [ i ] . kind
return EXPR_START [ kind ] or UNOPS [ kind ] or kind == "error" or atEmptyPipes ( )
end


local function advance ( )
local tok = tokens [ i ]
if tok . kind ~= "eof" then
i = i + 1
end

return tok
end




local function spelling ( tok )
return lexer . CUSTOMARY [ tok . text ] and tok . text or tok . kind
end


local function found ( tok )
if tok . kind == "eof" then
return "end of file"
end
if tok . text == "" then
return tok . kind
end

return ( "%q" ) : format ( tok . text )
end

local function errAt ( tok , msg , code , help )
if msg : find ( "expected" , 1 , true ) and not msg : find ( "found" , 1 , true ) then
msg = msg .. "; found " .. found ( tok )
elseif msg == "unexpected symbol" then
msg = msg .. "; found " .. found ( tok )
end
errors [
# errors + 1
] = {
code = code or "NUPP1005" ,
offset = tok . offset ,
length = # tok . text ,
line = tok . line ,
col = tok . col ,
msg = msg ,
filename = filename ,
help = help
}
end



local function missing ( kind )
local at = cur ( )
return {
kind = kind ,
text = "" ,
missing = true ,
trivia = at . trivia ,
triviaFirst = 1 ,
triviaCount = 0 ,
offset = at . offset ,
line = at . line ,
col = at . col
}
end


local function expect ( kind , what )
if cur ( ) . kind == kind then
return advance ( )
end
errAt ( cur ( ) , ( "'%s' expected%s; found %s" ) : format ( kind , what and ( " " .. what ) or "" , found ( cur ( ) ) ) , "NUPP1002" )

return missing ( kind )
end


local function expectName ( what )
if cur ( ) . kind == "name" then
return advance ( )
end
errAt ( cur ( ) , ( "name expected%s; found %s" ) : format ( what and ( " " .. what ) or "" , found ( cur ( ) ) ) , "NUPP1003" )

return missing ( "name" )
end







local genericCloseHalfAt = nil


local function expectGenericClose ( what )
if genericCloseHalfAt == i then
genericCloseHalfAt = nil
local at = cur ( )

return {
kind = ">" ,
text = "" ,
trivia = at . trivia ,
triviaFirst = 1 ,
triviaCount = 0 ,
offset = at . offset ,
line = at . line ,
col = at . col
}
end
if cur ( ) . kind == ">>" then
local tok = advance ( )
genericCloseHalfAt = i

return tok
end

return expect ( ">" , what )
end





local function resetNoMethod ( fn , ... )
local saved = noMethod
noMethod = 0
local r = fn ( ... )
noMethod = saved

return r
end

local parseExp , parseBlock , parseSuffixedexp , parseTableconstructor , parseFuncbody , parseType , parsePosttype , parseTypePack , parseStatement , parseReturnType , parseIstring , parseCaptureClause


local TYPE_START = {
[ "name" ] = true ,
[ "nil" ] = true ,
[ "{" ] = true ,
[ "function" ] = true ,
[ "(" ] = true ,
[ "string" ] = true ,
[ "true" ] = true ,
[ "false" ] = true ,
}



local FFI_INTRINSIC = {
[ "new" ] = true ,
[ "cast" ] = true ,
[ "istype" ] = true ,
[ "typeof" ] = true ,
[ "sizeof" ] = true ,
[ "alignof" ] = true ,
}





local COMPOUND_ASSIGN = {
[ "+=" ] = "+" ,
[ "-=" ] = "-" ,
[ "*=" ] = "*" ,
[ "/=" ] = "/" ,
[ "//=" ] = "//" ,
[ "%=" ] = "%" ,
[ "&=" ] = "&" ,
[ "|=" ] = "|" ,
[ "<<=" ] = "<<" ,
[ ">>=" ] = ">>" ,
[ "~>>=" ] = "~>>" ,
[ "..=" ] = ".." ,
[ "~=" ] = "~" ,


[ "??=" ] = "??" ,
}





local function compoundOp ( )
local tok = tokens [ i ]
if tok . kind == "~=" and tok . text ~= "~=" then
return nil
end

return COMPOUND_ASSIGN [ tok . kind ]
end


local TYPEDECL_KW = { [ "type" ] = true , [ "record" ] = true , [ "interface" ] = true , [ "struct" ] = true , }

local ALIAS_KW = { [ "type" ] = true }











local function afterDeclName ( at )
if not tokens [ at ] or tokens [ at ] . kind ~= "name" then
return nil
end
local j = at + 1
while tokens [ j ] and tokens [ j ] . kind == "." do
if not tokens [ j + 1 ] or tokens [ j + 1 ] . kind ~= "name" then
return nil
end
j = j + 2
end

return j
end



local function startsTypedecl ( at )
local kw = tokens [ at ]
if kw and kw . kind == "sealed" then
at = at + 1
kw = tokens [ at ]
end
if not kw or kw . kind ~= "name" or not TYPEDECL_KW [ kw . text ] then
return false
end
local name = tokens [ at + 1 ]
if not name or name . kind ~= "name" then
return false
end




if name . line ~= kw . line then
return false
end
local past = afterDeclName ( at + 1 )
if not past then
return false
end
local after = tokens [ past ]
if not after then
return false
end
if ALIAS_KW [ kw . text ] then
return after . kind == "=" or after . kind == "<"
end

return after . kind ~= "=" and after . kind ~= ","
end





local function annotationColon ( n , what )
local colon = add ( n , expect ( ":" , what ) )
colon . typeColon = true
return colon
end





local function parseGenerics ( n )
if cur ( ) . kind ~= "<" then
return nil
end
local g = setmetatable({ kind =  "generics" }, cst.Generics)
add ( g , advance ( ) ) . generic = true
g . names , g . bounds , g . packs , g . consts , g . domains = { } , { } , { } , { } , { }
g . defaults = { }
repeat
local at = # g . names + 1
local isConst = cur ( ) . kind == "name" and cur ( ) . text == "const" and tokens [
i + 1
] and tokens [ i + 1 ] . kind == "name" and tokens [ i + 2 ] and tokens [ i + 2 ] . kind == ":"
if isConst then
add ( g , advance ( ) ) . contextualOp = true
g . names [ at ] = add ( g , advance ( ) )
g . consts [ at ] = true
annotationColon ( g , "after const generic parameter" )




if cur ( ) . kind == "function" then
g . domains [ at ] = add ( g , advance ( ) )
else
g . domains [ at ] = add ( g , expectName ( "as const parameter domain" ) )
end
else
g . names [ at ] = add ( g , expectName ( "in generic parameter list" ) )
end
if not isConst and cur ( ) . kind == "..." then
g . packs [ at ] = true
add ( g , advance ( ) ) . generic = true
end
if not isConst and cur ( ) . kind == "name" and cur ( ) . text == "is" then
add ( g , advance ( ) )
g . bounds [ at ] = add ( g , parseType ( ) )
end



if cur ( ) . kind == "=" then
add ( g , advance ( ) )
g . defaults [ at ] = add ( g , parseType ( ) )
end
if cur ( ) . kind ~= "," then
break
end
add ( g , advance ( ) )
until false
add ( g , expectGenericClose ( "to close generic parameter list" ) ) . generic = true
n . generics = add ( n , g )

return g
end





local function startsType ( tok )
if not tok then
return false
end
local k = tok . kind

return k == "name"
or k == "nil"
or k == "{"
or k == "function"
or k == "("
or k == "string"
or k == "number"
or k == "true"
or k == "false"
or k == "istringOpen"
end


local function parseTypePrimary ( )
local kind = cur ( ) . kind
if kind == "name" and (
cur ( ) . text == "keyof" or cur ( ) . text == "writekeyof"
) and startsType ( tokens [ i + 1 ] ) and tokens [ i + 1 ] . line == cur ( ) . line then
local n = setmetatable({ kind =  "tkeyof" ,  capability =  cur ( ) . text == "keyof" and "read" or "write" }, cst.Tkeyof)
add ( n , advance ( ) ) . contextualOp = true
n . inner = add ( n , parseTypePrimary ( ) )
return n
end
if kind == "name" and cur ( ) . text == "writeof" and startsType (
tokens [ i + 1 ]
) and tokens [ i + 1 ] . line == cur ( ) . line then
local n = setmetatable({ kind =  "twriteof" }, cst.Twriteof)
add ( n , advance ( ) ) . contextualOp = true
n . inner = add ( n , parsePosttype ( ) )
return n
end






if kind == "name" and cur ( ) . text == "nosuspend" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "function" then
local keyword = advance ( )
keyword . contextualOp = true
local inner = parseTypePrimary ( )
if inner . kind == "tfunc" then
inner . noSuspend = true
end


table . insert ( inner , 1 , keyword )
return inner
end
if kind == "name" and cur ( ) . text == "comptime" and tokens [
i + 1
] and ( tokens [ i + 1 ] . kind == "function" or tokens [ i + 1 ] . kind == "name" and tokens [ i + 1 ] . text == "type" ) then
local keyword = advance ( )
keyword . contextualOp = true
local inner = parseTypePrimary ( )
inner . comptimeOnly = true
table . insert ( inner , 1 , keyword )
return inner
end
if kind == "name" and cur ( ) . text == "const" and startsType ( tokens [ i + 1 ] ) then
local n = setmetatable({ kind =  "tconst" }, cst.Tconst)
add ( n , advance ( ) )
n . inner = add ( n , parseTypePrimary ( ) )
return n
end
if kind == "string" or kind == "number" or kind == "true" or kind == "false" then




local n = setmetatable({ kind =  "tliteral" }, cst.Tliteral)
n . token = add ( n , advance ( ) )
return n
end
if kind == "name" or kind == "nil" then
local n = setmetatable({ kind =  "tname" }, cst.Tname)
n . base = add ( n , advance ( ) )
while cur ( ) . kind == "." and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "name" do
add ( n , advance ( ) )
add ( n , expectName ( "after '.' in type name" ) )
end
if cur ( ) . kind == "<" then
add ( n , advance ( ) ) . generic = true
local packArgs = n . base and n . base . text == "thread"
local function argument ( )
local explicitPack = cur ( ) . kind == "..." or cur ( ) . kind == "name" and tokens [
i + 1
] and tokens [ i + 1 ] . kind == "..."
return ( packArgs or explicitPack ) and parseTypePack ( false ) or parseType ( )
end

n . typeArgs = { add ( n , argument ( ) ) }
while cur ( ) . kind == "," do
add ( n , advance ( ) )
n . typeArgs [ # n . typeArgs + 1 ] = add ( n , argument ( ) )
end
add ( n , expectGenericClose ( "to close type arguments" ) ) . generic = true
end
if cur ( ) . kind == "(" then
local call = setmetatable({ kind =  "ttypecall" ,  arguments =  { } }, cst.Ttypecall)
call . callee = add ( call , n )
add ( call , advance ( ) )
if cur ( ) . kind ~= ")" then
call . arguments [ 1 ] = add ( call , parseType ( ) )
while cur ( ) . kind == "," do
add ( call , advance ( ) )
call . arguments [ # call . arguments + 1 ] = add ( call , parseType ( ) )
end
end
add ( call , expect ( ")" , "to close type-function arguments" ) )
return call
end
return n
elseif kind == "(" then
local open = advance ( )
local first = parseType ( )
if cur ( ) . kind == "," then
local pack = setmetatable({ kind =  "tpack" ,  types =  { } }, cst.Tpack)
add ( pack , open )
pack . types [ 1 ] = add ( pack , first )
while cur ( ) . kind == "," do
add ( pack , advance ( ) )
pack . types [ # pack . types + 1 ] = add ( pack , parseType ( ) )
end
add ( pack , expect ( ")" , "to close type pack" ) )
return pack
end
local n = setmetatable({ kind =  "tparen" }, cst.Tparen)
add ( n , open )
n . inner = add ( n , first )
add ( n , expect ( ")" , "to close type" ) )
return n
elseif kind == "{" then
local n
local addOpen = advance ( )
if cur ( ) . kind == "name" and (
cur ( ) . text == "readonly" or cur ( ) . text == "writeonly"
) and tokens [
i + 1
] and tokens [
i + 1
] . kind == "[" and tokens [
i + 2
] and tokens [ i + 2 ] . kind == "name" and tokens [ i + 3 ] and tokens [ i + 3 ] . kind == "in" then
local mapped = setmetatable({ kind =  "tmapped" }, cst.Tmapped)
add ( mapped , addOpen )
mapped . capability = add ( mapped , advance ( ) )
mapped . capability . propertyCapability = mapped . capability . text == "readonly" and "read" or "write"
add ( mapped , advance ( ) )
mapped . binder = add ( mapped , advance ( ) )
add ( mapped , advance ( ) ) . contextualOp = true
mapped . keys = add ( mapped , parseType ( ) )
if cur ( ) . kind == "name" and cur ( ) . text == "as" then
add ( mapped , advance ( ) ) . contextualOp = true
mapped . remap = add ( mapped , parseType ( ) )
end
add ( mapped , expect ( "]" , "to close mapped member" ) )
annotationColon ( mapped , "in mapped member" )
mapped . value = add ( mapped , parseType ( ) )
add ( mapped , expect ( "}" , "to close mapped shape" ) )
return mapped
end
local function shapeMember ( )
local capability = nil
if cur ( ) . kind == "name" and (
cur ( ) . text == "readonly" or cur ( ) . text == "writeonly"
) and tokens [ i + 1 ] and ( tokens [ i + 1 ] . kind == "name" or tokens [ i + 1 ] . kind == "[" ) then
capability = advance ( )
capability . propertyCapability = capability . text == "readonly" and "read" or "write"
end
local member
if cur ( ) . kind == "[" then
member = setmetatable({ kind =  "tmap" ,  capability =  capability }, cst.Tmap)
if capability then
add ( member , capability )
end
add ( member , advance ( ) )
member . key = add ( member , parseType ( ) )
add ( member , expect ( "]" , "to close indexer key type" ) )
annotationColon ( member , "in indexer type" )
member . value = add ( member , parseType ( ) )
else
member = setmetatable({ kind =  "tshapeField" ,  capability =  capability }, cst.TshapeField)
if capability then
add ( member , capability )
end
member . name = add ( member , expectName ( "in shape field" ) )
annotationColon ( member , "in shape field" )
member . type = add ( member , parseType ( ) )
end

return member
end

if cur ( ) . kind == "[" then

local first = shapeMember ( )
if cur ( ) . kind == "," then
n = setmetatable({ kind =  "tshape" ,  fields =  { } }, cst.Tshape)
add ( n , addOpen )
n . fields [ 1 ] = add ( n , first )
while cur ( ) . kind == "," do
add ( n , advance ( ) )
n . fields [ # n . fields + 1 ] = add ( n , shapeMember ( ) )
end
else
n = first
table . insert ( n , 1 , addOpen )
end
elseif cur ( ) . kind == "name" and tokens [
i + 1
] and (
tokens [
i + 1
] . kind == ":" or (
(
cur ( ) . text == "readonly" or cur ( ) . text == "writeonly"
) and ( tokens [ i + 1 ] . kind == "name" or tokens [ i + 1 ] . kind == "[" )
)
) then


n = setmetatable({ kind =  "tshape" }, cst.Tshape)
add ( n , addOpen )
n . fields = { }
repeat
local f = shapeMember ( )
n . fields [ # n . fields + 1 ] = add ( n , f )
if cur ( ) . kind ~= "," then
break
end
add ( n , advance ( ) )
until cur ( ) . kind == "}" or cur ( ) . kind == "eof"
else

local first = parseType ( )
if cur ( ) . kind == "," then
n = setmetatable({ kind =  "ttuple" }, cst.Ttuple)
add ( n , addOpen )
n . types = { add ( n , first ) }
while cur ( ) . kind == "," do
add ( n , advance ( ) )
if cur ( ) . kind == "}" then
break
end
if cur ( ) . kind == "name" and cur ( ) . text == "unpackof" and startsType (
tokens [ i + 1 ]
) and tokens [ i + 1 ] . line == cur ( ) . line then
add ( n , advance ( ) ) . contextualOp = true
n . tail = add ( n , parseType ( ) )
break
end
n . types [ # n . types + 1 ] = add ( n , parseType ( ) )
end
else
n = setmetatable({ kind =  "tarray" }, cst.Tarray)
add ( n , addOpen )
n . element = add ( n , first )
end
end
add ( n , expect ( "}" , "to close table type" ) )
return n
elseif kind == "function" then
local n = setmetatable({ kind =  "tfunc" }, cst.Tfunc)
add ( n , advance ( ) )
parseGenerics ( n )
add ( n , expect ( "(" , "in function type" ) )
n . params = { }
if cur ( ) . kind ~= ")" then
repeat
local p = setmetatable({ kind =  "tfuncParam" }, cst.TfuncParam)
local isFunctionConst = cur ( ) . kind == "name" and cur ( ) . text == "const" and tokens [
i + 1
] and tokens [
i + 1
] . kind == "name" and tokens [
i + 2
] and tokens [ i + 2 ] . kind == ":" and tokens [ i + 3 ] and tokens [ i + 3 ] . kind == "function"
if isFunctionConst then
p . constTok = add ( p , advance ( ) )
p . constTok . contextualOp = true
p . name = add ( p , advance ( ) )
annotationColon ( p , "after const function parameter" )
p . constDomainTok = add ( p , advance ( ) )
n . params [ # n . params + 1 ] = add ( n , p )
if cur ( ) . kind ~= "," then
break
end
add ( n , advance ( ) )
goto continue_type_parameter
end
if cur ( ) . kind == "name" and (
cur ( ) . text == "takes"
or cur ( ) . text == "borrows"
or cur ( ) . text == "scoped"
or cur ( ) . text == "exclusive"
or cur ( ) . text == "retains"
or cur ( ) . text == "releases"
) and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "..." then
p . modeTok = add ( p , advance ( ) )
end
if cur ( ) . kind == "..." then
add ( p , advance ( ) )
p . vararg = true
if cur ( ) . kind == ":" then
annotationColon ( p , "in vararg type" )
if cur ( ) . kind == "name" and (
(
tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "..."
) or ( cur ( ) . text == "unpackof" and startsType ( tokens [ i + 1 ] ) )
) then
p . type = add ( p , parseTypePack ( ) )
p . pack = true
else
p . type = add ( p , parseType ( ) )
end
end
n . params [ # n . params + 1 ] = add ( n , p )
break
elseif cur ( ) . kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "..." then
local pack = setmetatable({ kind =  "tpack" ,  types =  { } }, cst.Tpack)
local tail = setmetatable({ kind =  "tname" }, cst.Tname)
tail . base = add ( tail , advance ( ) )
pack . tail = add ( pack , tail )
pack . tailKind = "generic"
add ( pack , advance ( ) ) . generic = true
p . type , p . pack = add ( p , pack ) , true
n . params [ # n . params + 1 ] = add ( n , p )
break
elseif cur ( ) . kind == "name" and (
cur ( ) . text == "takes"
or cur ( ) . text == "borrows"
or cur ( ) . text == "scoped"
or cur ( ) . text == "exclusive"
or cur ( ) . text == "retains"
or cur ( ) . text == "releases"
) and tokens [
i + 1
] and tokens [ i + 1 ] . kind == "name" and tokens [ i + 2 ] and tokens [ i + 2 ] . kind == ":" then
p . modeTok = add ( p , advance ( ) )
p . name = add ( p , advance ( ) )
annotationColon ( p , "in parameter type" )
p . type = add ( p , parseType ( ) )
elseif cur ( ) . kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == ":" then
p . name = add ( p , advance ( ) )
annotationColon ( p , "in parameter type" )
p . type = add ( p , parseType ( ) )
else
p . type = add ( p , parseType ( ) )
end
n . params [ # n . params + 1 ] = add ( n , p )
if cur ( ) . kind ~= "," then
break
end
add ( n , advance ( ) )
:: continue_type_parameter ::
until false
end
add ( n , expect ( ")" , "to close function type parameters" ) )
if cur ( ) . kind == ":" then
annotationColon ( n , "before return type" )



local returnPack = parseTypePack ( false , true )
n . returnPack = returnPack
if returnPack . kind == "tpack" and not returnPack . tail then
for _ , child in ipairs ( returnPack ) do
add ( n , child )
end
else
add ( n , returnPack )
end
n . rets = returnPack . kind == "tpack" and returnPack . types or { }
local returns = n . rets or { }
local firstResult = returns [ 1 ]
if firstResult and firstResult . kind == "tborrows" then
local borrowed = firstResult
local parameterNames = { self = true }
for _ , parameter in ipairs ( n . params ) do
if parameter . name then
parameterNames [ parameter . name . text ] = true
end
end
local external = false
for _ , source in ipairs ( borrowed . params or { } ) do
external = external or not parameterNames [ source . text ]
end
if external then
n . captureBorrows = borrowed
if borrowed . type then
returns [ 1 ] = borrowed . type
if returnPack . kind == "tpack" then
returnPack . types [ 1 ] = borrowed . type
end
end
end
end
end
if cur ( ) . kind == "name" and cur ( ) . text == "borrows" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "(" then
n . captureBorrows = add ( n , parseCaptureClause ( ) )
end
if cur ( ) . kind == "name" and cur ( ) . text == "yields" then
add ( n , advance ( ) )
n . yieldPack = add ( n , parseTypePack ( false ) )
if not ( cur ( ) . kind == "name" and cur ( ) . text == "resumes" ) then
errAt ( cur ( ) , "'resumes' must follow a coroutine yield pack" )
else
add ( n , advance ( ) )
n . resumePack = add ( n , parseTypePack ( false ) )
end
end
return n
elseif kind == "istringOpen" then
return parseIstring ( )
end
errAt ( cur ( ) , "type expected" )
local n = setmetatable({ kind =  "errorType" }, cst.ErrorType)
add ( n , missing ( "type" ) )

return n
end




parsePosttype = function ( )
local t = parseTypePrimary ( )
while true do
local k = cur ( ) . kind
if k == "?" or k == "*" then
local n
if k == "?" then
n = setmetatable({ kind =  "topt" }, cst.Topt)
else
n = setmetatable({ kind =  "tptr" }, cst.Tptr)
end
n . inner = add ( n , t )
add ( n , advance ( ) ) . typePostfix = true
t = n
elseif k == "[" then


local n = setmetatable({ kind =  "tcarray" }, cst.Tcarray)
n . element = add ( n , t )
add ( n , advance ( ) ) . typePostfix = true
if cur ( ) . kind == "?" then
add ( n , advance ( ) ) . typePostfix = true
else
n . count = add ( n , parseExp ( ) )
end
add ( n , expect ( "]" , "to close a C array type" ) ) . typePostfix = true
t = n
elseif k == "." and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "[" then
local n = setmetatable({ kind =  "tmember" }, cst.Tmember)
n . object = add ( n , t )
add ( n , advance ( ) ) . typePostfix = true
add ( n , advance ( ) ) . typePostfix = true
n . key = add ( n , parseType ( ) )
add ( n , expect ( "]" , "to close an indexed member type" ) ) . typePostfix = true
t = n
else
return t
end
end
end


local function parseIntersection ( stopAtFunctionMember )
local t = parsePosttype ( )
local function nextIsFunctionMember ( )
return tokens [
i + 1
] and (
tokens [
i + 1
] . kind == "function" or tokens [
i + 1
] . kind == "name" and tokens [
i + 1
] . text == "comptime" and tokens [ i + 2 ] and tokens [ i + 2 ] . kind == "function"
) or false
end

if cur ( ) . kind ~= "&" or stopAtFunctionMember and nextIsFunctionMember ( ) then
return t
end
local n = setmetatable({ kind =  "tintersection" }, cst.Tintersection)
n . types = { add ( n , t ) }
while cur ( ) . kind == "&" and not ( stopAtFunctionMember and nextIsFunctionMember ( ) ) do
add ( n , advance ( ) )
n . types [ # n . types + 1 ] = add ( n , parsePosttype ( ) )
end

return n
end





parseType = function ( noUnion , stopAtFunctionMember )
local t = parseIntersection ( stopAtFunctionMember )
if noUnion or cur ( ) . kind ~= "|" then
return t
end
local n = setmetatable({ kind =  "tunion" }, cst.Tunion)
n . types = { add ( n , t ) }
while cur ( ) . kind == "|" do
add ( n , advance ( ) )
n . types [ # n . types + 1 ] = add ( n , parseIntersection ( stopAtFunctionMember ) )
end

return n
end


parseTypePack = function ( allowBareList , stopAtFunctionMember )
if cur ( ) . kind == "name" and cur ( ) . text == "unpackof" and startsType (
tokens [ i + 1 ]
) and tokens [ i + 1 ] . line == cur ( ) . line then
local n = setmetatable({ kind =  "tpack" ,  types =  { } ,  tailKind =  "computed" }, cst.Tpack)
add ( n , advance ( ) ) . contextualOp = true
n . tail = add ( n , parseType ( nil , stopAtFunctionMember ) )
return n
end
if cur ( ) . kind == "..." then
local n = setmetatable({ kind =  "tpack" ,  types =  { } ,  tailKind =  "homogeneous" }, cst.Tpack)
local dots = add ( n , advance ( ) )
dots . generic , dots . homogeneousPack = true , true
n . tail = add ( n , parseType ( nil , stopAtFunctionMember ) )
return n
end
if cur ( ) . kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "..." then
local n = setmetatable({ kind =  "tpack" ,  types =  { } ,  tailKind =  "generic" }, cst.Tpack)
local tail = setmetatable({ kind =  "tname" }, cst.Tname)
tail . base = add ( tail , advance ( ) )
n . tail = add ( n , tail )
add ( n , advance ( ) ) . generic = true
return n
end
if cur ( ) . kind ~= "(" then
local n = setmetatable({ kind =  "tpack" ,  types =  { } }, cst.Tpack)
n . types [ 1 ] = add ( n , parseReturnType ( stopAtFunctionMember ) )
while allowBareList and cur ( ) . kind == "," and tokens [ i + 1 ] and TYPE_START [ tokens [ i + 1 ] . kind ] do
add ( n , advance ( ) ) . typeSeparator = true
n . types [ # n . types + 1 ] = add ( n , parseReturnType ( stopAtFunctionMember ) )
end
return n
end
local n = setmetatable({ kind =  "tpack" ,  types =  { } }, cst.Tpack)





local function packPunct ( tok )
tok . typeBracket = true

return tok
end

packPunct ( add ( n , advance ( ) ) )
if cur ( ) . kind == ")" then
packPunct ( add ( n , advance ( ) ) ) ;
return n
end
if cur ( ) . kind == "(" then
local first = add ( n , parseTypePack ( false ) )
if cur ( ) . kind == "|" then
local union = setmetatable({ kind =  "tpackUnion" ,  packs =  { first } }, cst.TpackUnion)
for _ , child in ipairs ( n ) do
add ( union , child )
end
while cur ( ) . kind == "|" do
packPunct ( add ( union , advance ( ) ) )
union . packs [ # union . packs + 1 ] = add ( union , parseTypePack ( false ) )
end
packPunct ( add ( union , expect ( ")" , "to close pack union" ) ) )
return union
end
n . types [ 1 ] = first
else
while true do
if cur ( ) . kind == "..." then
local dots = add ( n , advance ( ) )
dots . generic , dots . homogeneousPack = true , true
n . tailKind = "homogeneous"
n . tail = add ( n , parseType ( nil , stopAtFunctionMember ) )
break
end
if cur ( ) . kind == "name" and cur ( ) . text == "unpackof" and startsType (
tokens [ i + 1 ]
) and tokens [ i + 1 ] . line == cur ( ) . line then
add ( n , advance ( ) ) . contextualOp = true
n . tailKind = "computed"
n . tail = add ( n , parseType ( nil , stopAtFunctionMember ) )
break
end
local item = add ( n , parseReturnType ( stopAtFunctionMember ) )
if cur ( ) . kind == "..." then
if item . kind ~= "tname" then
errAt ( cur ( ) , "only a generic pack name may precede '...'" )
end
add ( n , advance ( ) ) . generic = true
n . tail , n . tailKind = item , "generic"
break
end
n . types [ # n . types + 1 ] = item
if cur ( ) . kind ~= "," then
break
end
packPunct ( add ( n , advance ( ) ) )
end
end
packPunct ( add ( n , expect ( ")" , "to close type pack" ) ) )

return n
end


local function parseExplist ( n )
local exprs = { }
exprs [ 1 ] = add ( n , parseExp ( ) )
while cur ( ) . kind == "," do
add ( n , advance ( ) )
exprs [ # exprs + 1 ] = add ( n , parseExp ( ) )
end

return exprs
end




local function pluckGroupAhead ( )
local j = i + 1
if not tokens [ j ] or tokens [ j ] . kind ~= "name" then
return false
end
j = j + 1
while tokens [ j ] and tokens [ j ] . kind == "," do
if not tokens [ j + 1 ] or tokens [ j + 1 ] . kind ~= "name" then
return false
end
j = j + 2
end

return tokens [ j ] ~= nil and tokens [ j ] . kind == ")" and tokens [ j + 1 ] ~= nil and tokens [ j + 1 ] . kind == "="
end


local function parseCallargs ( typeFirst )
local kind = cur ( ) . kind
if kind == "(" then
local n = setmetatable({ kind =  "args" }, cst.Args)
add ( n , advance ( ) )
n . exprs = { }
if cur ( ) . kind ~= ")" then
repeat
local argument
if typeFirst and # n . exprs == 0 then
argument = parseType ( )
n . typeArg = argument
elseif cur ( ) . kind == "(" and pluckGroupAhead ( ) then
local pluck = setmetatable({ kind =  "pluckArg" ,  names =  { } }, cst.PluckArg)
add ( pluck , advance ( ) )
pluck . names [ 1 ] = add ( pluck , advance ( ) )
while cur ( ) . kind == "," do
add ( pluck , advance ( ) )
pluck . names [ # pluck . names + 1 ] = add ( pluck , advance ( ) )
end
add ( pluck , expect ( ")" , "to close a plucked parameter group" ) )
add ( pluck , advance ( ) )



pluck . value = add ( pluck , resetNoMethod ( parseExp ) )
argument = pluck
elseif cur ( ) . kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "=" then
local named = setmetatable({ kind =  "namedArg" }, cst.NamedArg)
named . name = add ( named , advance ( ) )
add ( named , advance ( ) )
named . value = add ( named , resetNoMethod ( parseExp ) )
argument = named
else
argument = resetNoMethod ( parseExp )
end
n . exprs [ # n . exprs + 1 ] = add ( n , argument )
if cur ( ) . kind ~= "," then
break
end
add ( n , advance ( ) )
until false
end
add ( n , expect ( ")" , "to close arguments" ) )
return n
elseif kind == "{" then
local n = setmetatable({ kind =  "args" }, cst.Args)
n . table = add ( n , resetNoMethod ( parseTableconstructor ) )
return n
elseif kind == "string" then
local n = setmetatable({ kind =  "args" }, cst.Args)
n . str = add ( n , advance ( ) )
return n
end

return nil
end





local function parseMethodCall ( obj , safeObj )
local n = setmetatable({ kind =  "methodCall" }, cst.MethodCall)
n . obj = add ( n , obj )
if safeObj then
n . safeObj = add ( n , safeObj )
end
add ( n , advance ( ) )
n . name = add ( n , expectName ( "for method call" ) )
if cur ( ) . kind == "?." then
n . safeMethod = add ( n , advance ( ) )
end
local args = parseCallargs ( )
if args then
n . args = add ( n , args )
else
errAt ( cur ( ) , "function arguments expected" )
add ( n , missing ( "args" ) )
end

return n
end


local function parsePrimaryexp ( )
local kind = cur ( ) . kind
if kind == "name" then
local n = setmetatable({ kind =  "name" }, cst.NameExpr)
n . token = add ( n , advance ( ) )
return n
elseif kind == "(" then
local n = setmetatable({ kind =  "paren" }, cst.Paren)
add ( n , advance ( ) )
n . expr = add ( n , resetNoMethod ( parseExp ) )
add ( n , expect ( ")" , "to close parenthesized expression" ) )
return n
elseif kind == "error" then
local n = setmetatable({ kind =  "errorExpr" }, cst.ErrorExpr)
add ( n , advance ( ) )
return n
end
errAt ( cur ( ) , ( "expression expected; found %s" ) : format ( found ( cur ( ) ) ) , "NUPP1004" )
local n = setmetatable({ kind =  "errorExpr" }, cst.ErrorExpr)
add ( n , missing ( "expr" ) )

return n
end


parseSuffixedexp = function ( )
local e = parsePrimaryexp ( )
while true do
local kind = cur ( ) . kind
if kind == "." then
local n = setmetatable({ kind =  "dotIndex" }, cst.DotIndex)
n . obj = add ( n , e )
add ( n , advance ( ) )
n . name = add ( n , expectName ( "after '.'" ) )
e = n



local member = n . name
local base = n . obj
local baseTok = base and base . kind == "name" and base . token
if cur ( ) . kind == "<" and member and baseTok and FFI_INTRINSIC [
member . text
] and baseTok . text == "ffi" then
add ( n , advance ( ) ) . generic = true
n . ffiTypeArg = add ( n , parseType ( ) )
add ( n , expectGenericClose ( "to close a type argument" ) ) . generic = true
end
elseif kind == "[" then
local n = setmetatable({ kind =  "bracketIndex" }, cst.BracketIndex)
n . obj = add ( n , e )
add ( n , advance ( ) )
n . expr = add ( n , resetNoMethod ( parseExp ) )
add ( n , expect ( "]" , "to close index" ) )
e = n
elseif kind == ":" then
if noMethod > 0 then

return e
end
e = parseMethodCall ( e , nil )
elseif kind == "?." then
local qtok = advance ( )
local nk = cur ( ) . kind
if nk == ":" then


if noMethod > 0 then

errAt (
qtok ,
"a safe method call cannot appear in the " .. "second arm of a ternary; parenthesize it"
)
end
e = parseMethodCall ( e , qtok )
elseif nk == "name" then
local n = setmetatable({ kind =  "safeIndex" }, cst.SafeIndex)
n . obj = add ( n , e )
add ( n , qtok )
n . name = add ( n , advance ( ) )
e = n
elseif nk == "[" then
local n = setmetatable({ kind =  "safeBracket" }, cst.SafeBracket)
n . obj = add ( n , e )
add ( n , qtok )
add ( n , advance ( ) )
n . expr = add ( n , resetNoMethod ( parseExp ) )
add ( n , expect ( "]" , "to close index" ) )
e = n
else
local args = parseCallargs ( )
if args then
local n = setmetatable({ kind =  "safeCall" }, cst.SafeCall)
n . obj = add ( n , e )
add ( n , qtok )
n . args = add ( n , args )
e = n
else
errAt ( cur ( ) , "name, index, or arguments expected after '?.'" )
local n = setmetatable({ kind =  "errorExpr" }, cst.ErrorExpr)
n . obj = add ( n , e )
add ( n , qtok )
e = n
end
end
else
local comptimeIntrinsic = cst . comptimeTypeIntrinsicSpelling ( e )
local args = parseCallargs ( comptimeIntrinsic ~= nil )
if args then
local n = setmetatable({ kind =  "call" }, cst.Call)
n . obj = add ( n , e )
n . args = add ( n , args )
e = n
else
return e
end
end
end
end


parseTableconstructor = function ( )
local n = setmetatable({ kind =  "tableExpr" }, cst.TableExpr)
add ( n , expect ( "{" ) )
n . fields = { }
while cur ( ) . kind ~= "}" and cur ( ) . kind ~= "eof" do
local f
if cur ( ) . kind == "[" then
f = setmetatable({ kind =  "fieldBracket" }, cst.FieldBracket)
add ( f , advance ( ) )
f . key = add ( f , resetNoMethod ( parseExp ) )
add ( f , expect ( "]" , "to close field key" ) )
add ( f , expect ( "=" , "in table field" ) )
f . value = add ( f , resetNoMethod ( parseExp ) )
elseif cur ( ) . kind == "name" and cur ( ) . text == "const" and tokens [
i + 1
] and tokens [ i + 1 ] . kind == "name" and tokens [ i + 2 ] and tokens [ i + 2 ] . kind == "=" then
f = setmetatable({ kind =  "fieldNamed" }, cst.FieldNamed)
f . isConst = true
add ( f , advance ( ) )
f . name = add ( f , advance ( ) )
add ( f , advance ( ) )
f . value = add ( f , resetNoMethod ( parseExp ) )
elseif cur ( ) . kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "=" then
f = setmetatable({ kind =  "fieldNamed" }, cst.FieldNamed)
f . name = add ( f , advance ( ) )
add ( f , advance ( ) )
f . value = add ( f , resetNoMethod ( parseExp ) )
elseif atExprStart ( ) then
f = setmetatable({ kind =  "fieldItem" }, cst.FieldItem)
f . value = add ( f , resetNoMethod ( parseExp ) )
else
errAt ( cur ( ) , "unexpected symbol in table constructor" )
f = setmetatable({ kind =  "errorExpr" }, cst.ErrorExpr)
add ( f , advance ( ) )
end
n . fields [ # n . fields + 1 ] = add ( n , f )
if cur ( ) . kind == "," or cur ( ) . kind == ";" then
add ( n , advance ( ) )
elseif cur ( ) . kind ~= "}" then
break
end
end
add ( n , expect ( "}" , "to close table constructor" ) )

return n
end






local function parseShortfn ( )
local n = setmetatable({ kind =  "shortfn" }, cst.Shortfn)
n . params = { }
if atEmptyPipes ( ) then



add ( n , advance ( ) )
elseif cur ( ) . kind == "|" then
local open = add ( n , advance ( ) )
open . _shortfnOpen = true
if cur ( ) . kind ~= "|" then
repeat
local p = setmetatable({ kind =  "param" }, cst.Param)
if cur ( ) . kind == "..." then
local dots = add ( p , advance ( ) )
if cur ( ) . kind == "name" and cur ( ) . offset == dots . offset + # dots . text then
local nameTok = advance ( )
p . name = add ( p , nameTok )
p . namedVararg = true
nameTok . namedVararg = true
n . varargParam = p
end
if not p . namedVararg then
errAt ( dots , "named vararg expected in short function" )
end
else
p . name = add ( p , expectName ( "in short function parameters" ) )
end
if cur ( ) . kind == ":" then
annotationColon ( p , "in parameter annotation" )
p . type = add ( p , parseType ( true ) )
end
n . params [ # n . params + 1 ] = add ( n , p )
if p . namedVararg and cur ( ) . kind == "," then
errAt ( cur ( ) , "named vararg must be the last parameter" )
end
if cur ( ) . kind ~= "," then
break
end
add ( n , advance ( ) )
until false
end
local close = add ( n , expect ( "|" , "to close short function parameters" ) )
close . _shortfnClose = true
else
local p = setmetatable({ kind =  "param" }, cst.Param)
p . name = add ( p , expectName ( "in short function" ) )
n . params [ 1 ] = add ( n , p )
end
add ( n , expect ( "->" , "in short function" ) )
if cur ( ) . kind == "do" then
add ( n , advance ( ) )
local savedLoopDepth = loopDepth
loopDepth = 0
n . body = add ( n , parseBlock ( ) )
loopDepth = savedLoopDepth
add ( n , expect ( "end" , "to close short function" ) )
else
n . expr = add ( n , parseExp ( ) )
end

return n
end




parseIstring = function ( )
local n = setmetatable({ kind =  "istring" }, cst.Istring)
add ( n , advance ( ) )
n . parts = { }
while true do
n . parts [ # n . parts + 1 ] = add ( n , resetNoMethod ( parseExp ) )
local k = cur ( ) . kind
if k == "istringMid" then
add ( n , advance ( ) )
elseif k == "istringClose" then
add ( n , advance ( ) )
return n
else
errAt ( cur ( ) , "'}' expected to close interpolation" )
add ( n , missing ( "istringClose" ) )
return n
end
end
end







local function atNewexp ( )
local tok = cur ( )
if tok . kind ~= "name" or tok . text ~= "new" then
return false
end
local after = tokens [ i + 1 ]

return after ~= nil and after . kind == "name" and after . line == tok . line
end







local function atComptimeexp ( )
local tok = cur ( )
if tok . kind ~= "name" or tok . text ~= "comptime" then
return false
end
local after = tokens [ i + 1 ]

return after ~= nil and after . kind == "do" and after . line == tok . line
end








local function parseNewexp ( )
local n = setmetatable({ kind =  "newExpr" }, cst.NewExpr)
local kw = advance ( )
add ( n , kw )
local call = parseSuffixedexp ( )
n . call = add ( n , call )
if call . kind == "call" or call . kind == "safeCall" then




local calleeEnd = cst . lastToken ( call . obj )
if calleeEnd then
calleeEnd . constructTarget = true
end
end
if call . kind ~= "call" and call . kind ~= "safeCall" then
errAt (
kw ,
"'new' needs a construction; write new T(...)" ,
"NUPP1004" ,
"add the constructor arguments, or `()` when there are none"
)
end

return n
end


local function parseSimpleexp ( )
local kind = cur ( ) . kind
if kind == "name" and cur ( ) . text == "unsafe" and tokens [
i + 1
] and tokens [ i + 1 ] . kind == "name" and ( tokens [ i + 1 ] . text == "adopt" or tokens [ i + 1 ] . text == "release" ) then
local operation = tokens [ i + 1 ] . text
local n = setmetatable({ kind =  "unsafeOwnershipExpr" ,  operation =  operation }, cst.UnsafeOwnershipExpr)
add ( n , advance ( ) ) . contextualOp = true
add ( n , advance ( ) ) . contextualOp = true
if operation == "release" then
n . expr = add ( n , parseExp ( ) )
else



local assertion = add ( n , parseExp ( ) )
if assertion . kind == "castExpr" then
n . expr , n . type = assertion . expr , assertion . type
else
errAt (
cst . lastToken ( assertion ) or cur ( ) ,
"'unsafe adopt' needs an affine target; write unsafe adopt value as Owner" ,
"NUPP1002"
)
n . expr = assertion
end
end
return n
elseif kind == "name" and cur ( ) . text == "dedent" and tokens [
i + 1
] and tokens [ i + 1 ] . kind == "string" and tokens [ i + 1 ] . text : sub ( 1 , 1 ) == "[" then
local n = setmetatable({ kind =  "dedentString" }, cst.DedentString)
n . keyword = add ( n , advance ( ) )
n . token = add ( n , advance ( ) )
return n
elseif kind == "number" or kind == "string" then
local n
if kind == "number" then
n = setmetatable({ kind =  "number" }, cst.NumberLit)
else
n = setmetatable({ kind =  "string" }, cst.StringLit)
end
n . token = add ( n , advance ( ) )
return n
elseif kind == "|" or atEmptyPipes ( ) or ( kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "->" ) then
return parseShortfn ( )
elseif kind == "istringOpen" then
return parseIstring ( )
elseif kind == "nil" or kind == "true" or kind == "false" or kind == "..." then
local n
if kind == "..." then
n = setmetatable({ kind =  "vararg" }, cst.Vararg)
elseif kind == "nil" then
n = setmetatable({ kind =  "nilExpr" }, cst.NilExpr)
elseif kind == "true" then
n = setmetatable({ kind =  "trueExpr" }, cst.TrueExpr)
else
n = setmetatable({ kind =  "falseExpr" }, cst.FalseExpr)
end
n . token = add ( n , advance ( ) )
return n
elseif kind == "function" then
local n = setmetatable({ kind =  "funcExpr" }, cst.FuncExpr)
add ( n , advance ( ) )
n . body = add ( n , parseFuncbody ( ) )
return n
elseif kind == "{" then
return parseTableconstructor ( )
elseif atNewexp ( ) then
return parseNewexp ( )
elseif atComptimeexp ( ) then
local n = setmetatable({ kind =  "comptimeExpr" }, cst.ComptimeExpr)
add ( n , advance ( ) ) . contextualOp = true
add ( n , advance ( ) )
n . body = add ( n , parseBlock ( ) )
add ( n , expect ( "end" , "to close 'comptime do'" ) )
return n
else
return parseSuffixedexp ( )
end
end






local function contextualOp ( prevLine )
local tok = cur ( )
if tok . kind == "name" and tok . line == prevLine and ( tok . text == "as" or tok . text == "is" ) then
return tok . text
end

return nil
end


local function parseBinexp ( limit )
local left
if UNOPS [ cur ( ) . kind ] then
local n = setmetatable({ kind =  "unop" }, cst.Unop)
n . op = add ( n , advance ( ) )
n . operand = add ( n , parseBinexp ( UNARY_PRI ) )
left = n
else
left = parseSimpleexp ( )
end
while true do
local prevLine = tokens [ i - 1 ] and tokens [ i - 1 ] . line or cur ( ) . line
local ctx = contextualOp ( prevLine )
if ctx == "as" and 11 > limit then
local n = setmetatable({ kind =  "castExpr" }, cst.CastExpr)
n . expr = add ( n , left )
add ( n , advance ( ) ) . contextualOp = true
n . type = add ( n , parseType ( ) )
left = n
elseif ctx == "is" and 3 > limit then
local n = setmetatable({ kind =  "isExpr" }, cst.IsExpr)
n . expr = add ( n , left )
add ( n , advance ( ) ) . contextualOp = true
n . type = add ( n , parseType ( ) )
left = n
else
local pri = BINPRI [ cur ( ) . kind ]
if not ( pri and pri [ 1 ] > limit ) then
break
end
local n = setmetatable({ kind =  "binop" }, cst.Binop)
n . lhs = add ( n , left )
n . op = add ( n , advance ( ) )
n . rhs = add ( n , parseBinexp ( pri [ 2 ] ) )
left = n
end
end

return left
end


parseExp = function ( )
local e = parseBinexp ( 0 )
if cur ( ) . kind == "?" then
local n = setmetatable({ kind =  "ternary" }, cst.Ternary)
n . cond = add ( n , e )
add ( n , advance ( ) )
noMethod = noMethod + 1
n . ifTrue = add ( n , parseExp ( ) )
noMethod = noMethod - 1
add ( n , expect ( ":" , "in ternary expression" ) )
n . ifFalse = add ( n , parseExp ( ) )
return n
end

return e
end

parseCaptureClause = function ( )
local n = setmetatable({ kind =  "captureClause" ,  names =  { } }, cst.CaptureClause)
n . mode = add ( n , advance ( ) )
n . mode . contextualOp = true
add ( n , expect ( "(" , "to open closure captures" ) )
if cur ( ) . kind ~= ")" then
repeat
n . names [ # n . names + 1 ] = add ( n , expectName ( "as closure capture" ) )
if cur ( ) . kind ~= "," then
break
end
add ( n , advance ( ) )
until false
end
add ( n , expect ( ")" , "to close closure captures" ) )

return n
end


parseFuncbody = function ( )
local n = setmetatable({ kind =  "funcbody" }, cst.Funcbody)
parseGenerics ( n )
add ( n , expect ( "(" , "to begin parameter list" ) )
n . params = { }
if cur ( ) . kind ~= ")" then
repeat
local p = setmetatable({ kind =  "param" }, cst.Param)
local isFunctionConst = cur ( ) . kind == "name" and cur ( ) . text == "const" and tokens [
i + 1
] and tokens [
i + 1
] . kind == "name" and tokens [
i + 2
] and tokens [ i + 2 ] . kind == ":" and tokens [ i + 3 ] and tokens [ i + 3 ] . kind == "function"
if isFunctionConst then
p . constTok = add ( p , advance ( ) )
p . constTok . contextualOp = true
p . name = add ( p , advance ( ) )
annotationColon ( p , "after const function parameter" )
p . constDomainTok = add ( p , advance ( ) )
n . params [ # n . params + 1 ] = add ( n , p )
if cur ( ) . kind ~= "," then
break
end
add ( n , advance ( ) )
goto continue_parameter
end
if cur ( ) . kind == "name" and (
cur ( ) . text == "takes"
or cur ( ) . text == "borrows"
or cur ( ) . text == "scoped"
or cur ( ) . text == "exclusive"
or cur ( ) . text == "retains"
or cur ( ) . text == "releases"
) and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "..." then
p . modeTok = add ( p , advance ( ) )
end
if cur ( ) . kind == "..." then
local dots = add ( p , advance ( ) )
p . vararg = true
if cur ( ) . kind == "name" and cur ( ) . offset == dots . offset + # dots . text then
local nameTok = advance ( )
p . name = add ( p , nameTok )
p . namedVararg = true
nameTok . namedVararg = true
n . varargParam = p
end
if cur ( ) . kind == ":" then
annotationColon ( p , "in vararg annotation" )
if cur ( ) . kind == "name" and (
(
tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "..."
) or ( cur ( ) . text == "unpackof" and startsType ( tokens [ i + 1 ] ) )
) then
p . type = add ( p , parseTypePack ( ) )
else
p . type = add ( p , parseType ( ) )
end
end
n . params [ # n . params + 1 ] = add ( n , p )
if cur ( ) . kind == "," then
errAt ( cur ( ) , "'...' must be the last parameter" )
end
break
end
if cur ( ) . kind == "name" and (
cur ( ) . text == "takes"
or cur ( ) . text == "borrows"
or cur ( ) . text == "scoped"
or cur ( ) . text == "exclusive"
or cur ( ) . text == "retains"
or cur ( ) . text == "releases"
) and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "name" then
p . modeTok = add ( p , advance ( ) )
end
p . name = add ( p , expectName ( "as parameter" ) )
if cur ( ) . kind == ":" then
annotationColon ( p , "in parameter annotation" )
p . type = add ( p , parseType ( ) )
end
n . params [ # n . params + 1 ] = add ( n , p )
if cur ( ) . kind ~= "," then
break
end
add ( n , advance ( ) )
:: continue_parameter ::
until false
end
add ( n , expect ( ")" , "to close parameter list" ) )
if cur ( ) . kind == ":" then

annotationColon ( n , "before return types" )
local returnPack = parseTypePack ( true )
n . returnPack = returnPack
if returnPack . kind == "tpack" and not returnPack . tail then
for _ , child in ipairs ( returnPack ) do
add ( n , child )
end
else
add ( n , returnPack )
end
n . rets = returnPack . kind == "tpack" and returnPack . types or { }
local returns = n . rets or { }
local firstResult = returns [ 1 ]
if firstResult and firstResult . kind == "tborrows" then
local borrowed = firstResult
local parameterNames = { self = true }
for _ , parameter in ipairs ( n . params ) do
if parameter . name then
parameterNames [ parameter . name . text ] = true
end
end
local external = false
for _ , source in ipairs ( borrowed . params or { } ) do
external = external or not parameterNames [ source . text ]
end
if external then
n . captureBorrowsCandidate = borrowed
end
end
end
while cur ( ) . kind == "name" and (
cur ( ) . text == "takes" or cur ( ) . text == "borrows"
) and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "(" do
local clause = parseCaptureClause ( )
if clause . mode and clause . mode . text == "takes" then
if n . captureTakes then
errAt ( clause . mode , "a closure has only one takes clause" )
else
n . captureTakes = add ( n , clause )
end
elseif n . captureBorrows then
errAt ( clause . mode or cur ( ) , "a closure has only one borrows clause" )
else
n . captureBorrows = add ( n , clause )
end
end
if cur ( ) . kind == "name" and cur ( ) . text == "yields" then
add ( n , advance ( ) )
n . yieldPack = add ( n , parseTypePack ( true ) )
if not ( cur ( ) . kind == "name" and cur ( ) . text == "resumes" ) then
errAt ( cur ( ) , "'resumes' must follow a coroutine yield pack" )
else
add ( n , advance ( ) )
n . resumePack = add ( n , parseTypePack ( true ) )
end
end
local savedLoopDepth = loopDepth
loopDepth = 0
n . body = add ( n , parseBlock ( ) )
loopDepth = savedLoopDepth
add ( n , expect ( "end" , "to close function" ) )

return n
end



local parseTypedecl




local function parseBorrowRelation ( result )









if cur ( ) . kind == "name" and cur ( ) . text == "borrows" and tokens [
i + 1
] and ( tokens [ i + 1 ] . kind == "name" or tokens [ i + 1 ] . kind == "(" ) then
local n = setmetatable({ kind =  "tborrows" }, cst.Tborrows)
n . type = add ( n , result )
add ( n , advance ( ) )
n . params = { }
add ( n , expect ( "(" , "to open borrow sources" ) )
repeat
local param = add ( n , expectName ( "as borrow source" ) )
n . params [ # n . params + 1 ] = param
if cur ( ) . kind ~= "," then
break
end
add ( n , advance ( ) )
until false
add ( n , expect ( ")" , "to close borrow sources" ) )
n . param = n . params [ 1 ]
return n
end

return result
end




parseReturnType = function ( stopAtFunctionMember )
local after = tokens [ i + 1 ]
if cur ( ) . kind == "name" and after and after . kind == "name" and after . text == "is" then
local n = setmetatable({ kind =  "tpredicate" }, cst.Tpredicate)
n . param = add ( n , advance ( ) )
add ( n , advance ( ) )
n . type = add ( n , parseType ( nil , stopAtFunctionMember ) )
return n
end
local result = parseType ( nil , stopAtFunctionMember )

if cur ( ) . kind == "name" and cur ( ) . text == "preserves" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "name" then
local n = setmetatable({ kind =  "tpreserves" }, cst.Tpreserves)
n . type = add ( n , result )
add ( n , advance ( ) )
n . param = add ( n , advance ( ) )
return n
end

return parseBorrowRelation ( result )
end






local function parseAnnotationApplication ( n )
add ( n , expect ( "@" ) )
n . name = add ( n , expectName ( "after '@'" ) )
if cur ( ) . kind ~= "(" then
return n
end

n . open = add ( n , advance ( ) )
n . annotationArgs = { }
if cur ( ) . kind ~= ")" then
repeat
local arg = setmetatable({ kind =  "annotationArg" }, cst.AnnotationArg)
if cur ( ) . kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "=" then
arg . name = add ( arg , advance ( ) )
arg . eq = add ( arg , advance ( ) )
end
arg . expr = add ( arg , resetNoMethod ( parseExp ) )
n . annotationArgs [ # n . annotationArgs + 1 ] = add ( n , arg )
if cur ( ) . kind ~= "," then
break
end
add ( n , advance ( ) )
until false
end
n . close = add ( n , expect ( ")" , "to close annotation arguments" ) )

return n
end







local function startsAssociatedType ( at )
local kw = tokens [ at ]
if not kw or kw . kind ~= "name" or kw . text ~= "associated" then
return false
end
local word = tokens [ at + 1 ]
if not word or word . kind ~= "name" or word . text ~= "type" or word . line ~= kw . line then
return false
end
local named = tokens [ at + 2 ]

return named ~= nil and named . kind == "name"
end


local function parseAssociatedType ( )
local n = setmetatable({ kind =  "associatedDecl" }, cst.AssociatedDecl)
n . keyword = advance ( )
add ( n , n . keyword )
n . typeKeyword = advance ( )
add ( n , n . typeKeyword )
n . name = add ( n , expectName ( "after 'associated type'" ) )
if cur ( ) . kind == "name" and cur ( ) . text == "is" then
add ( n , advance ( ) )
n . bound = add ( n , parseType ( ) )
end
if cur ( ) . kind == "=" or cur ( ) . kind == "==" then
n . fixed = cur ( ) . kind == "=="
add ( n , advance ( ) )
n . value = add ( n , parseType ( ) )
end

return n
end

local function parseRecordBody ( n )
n . entries = { }
while cur ( ) . kind ~= "end" and cur ( ) . kind ~= "eof" do
local attached = { }
while cur ( ) . kind == "@" do
local application = parseAnnotationApplication ( setmetatable({ kind =  "annotationApply" }, cst.AnnotationApply) )
attached [ # attached + 1 ] = add ( n , application )
end
local e
if startsAssociatedType ( i ) then
e = parseAssociatedType ( )
elseif startsTypedecl ( i ) then
e = parseTypedecl ( nil , "nested" )
elseif cur ( ) . kind == "function" then
e = setmetatable({ kind =  "inlineMethod" }, cst.InlineMethod)
add ( e , advance ( ) )
e . name = add ( e , expectName ( "after 'function' in declaration" ) )
e . body = add ( e , parseFuncbody ( ) )
elseif cur ( ) . kind == "name" and cur ( ) . text == "constructor" and tokens [
i + 1
] and ( tokens [ i + 1 ] . kind == "(" or startsShortfn ( i + 1 ) ) then


e = setmetatable({ kind =  "constructorDecl" }, cst.ConstructorDecl)
add ( e , advance ( ) )




if startsShortfn ( i ) then
e . body = add ( e , parseShortfn ( ) )
else
e . body = add ( e , parseFuncbody ( ) )
end
elseif cur ( ) . kind == "name" and cur ( ) . text == "satisfies" and tokens [
i + 1
] and tokens [ i + 1 ] . kind ~= ":" then


e = setmetatable({ kind =  "satisfiesDecl" }, cst.SatisfiesDecl)
add ( e , advance ( ) )




if startsShortfn ( i ) then
e . body = add ( e , parseShortfn ( ) )
else
e . body = add ( e , parseFuncbody ( ) )
end
elseif cur ( ) . kind == "name" and cur ( ) . text == "metamethod" and tokens [
i + 1
] and tokens [ i + 1 ] . kind == "name" then
e = setmetatable({ kind =  "metamethodDecl" }, cst.MetamethodDecl)
add ( e , advance ( ) )
e . name = add ( e , expectName ( "after 'metamethod'" ) )
annotationColon ( e , "in metamethod declaration" )
e . type = add ( e , parseType ( ) )
elseif cur ( ) . kind == "{" then


e = setmetatable({ kind =  "arrayPart" }, cst.ArrayPart)
e . type = add ( e , parseType ( ) )
elseif cur ( ) . kind == "[" or (
cur ( ) . kind == "name" and (
cur ( ) . text == "readonly" or cur ( ) . text == "writeonly"
) and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "["
) then
e = setmetatable({ kind =  "indexerDecl" }, cst.IndexerDecl)
if cur ( ) . kind == "name" then
e . capability = add ( e , advance ( ) )
e . capability . propertyCapability = e . capability . text == "readonly" and "read" or "write"
end
add ( e , expect ( "[" , "to open indexer key type" ) )
e . key = add ( e , parseType ( ) )
add ( e , expect ( "]" , "to close indexer key type" ) )
annotationColon ( e , "in indexer declaration" )
e . value = add ( e , parseType ( ) )
elseif cur ( ) . kind == "name" then
e = setmetatable({ kind =  "fieldDecl" }, cst.FieldDecl)
if cur ( ) . text == "private" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "name" then
e . privacy = add ( e , advance ( ) )
end
if (
cur ( ) . text == "readonly" or cur ( ) . text == "writeonly"
) and tokens [
i + 1
] and tokens [ i + 1 ] . kind == "name" and tokens [ i + 2 ] and tokens [ i + 2 ] . kind == ":" then
e . capability = add ( e , advance ( ) )
e . capability . propertyCapability = e . capability . text == "readonly" and "read" or "write"
end
e . name = add ( e , advance ( ) )
if cur ( ) . kind == "," then


errAt (
cur ( ) ,
"each field needs its own explicit type " .. "annotation (grouped fields are not supported)"
)
end
annotationColon ( e , "in field declaration" )
e . type = add ( e , parseReturnType ( ) )
if cur ( ) . kind == ":" then
add ( e , advance ( ) )
e . bitWidth = add ( e , expect ( "number" , "as C bitfield width" ) )
end
if cur ( ) . kind == "=" then
add ( e , advance ( ) )
e . defaultValue = add ( e , parseExp ( ) )
end
else
errAt ( cur ( ) , "field or nested declaration expected" )
e = setmetatable({ kind =  "errorStmt" }, cst.ErrorStmt)
add ( e , advance ( ) )
end
e . annotations = attached
n . entries [ # n . entries + 1 ] = add ( n , e )
end
add ( n , expect ( "end" , "to close declaration" ) )
end





local function parseDeclName ( n , what )
n . name = add ( n , expectName ( what ) )
while cur ( ) . kind == "." do
add ( n , advance ( ) )
n . qualifiers = n . qualifiers or { }
n . qualifiers [ # n . qualifiers + 1 ] = n . name
n . name = add ( n , expectName ( "after '.' in declaration name" ) )
end
end


parseTypedecl = function ( modifierTok , visibility )
local sealedTok = nil
if cur ( ) . kind == "sealed" then
sealedTok = advance ( )
end
local kw = advance ( )
local which = kw . text
if sealedTok and which ~= "interface" then
errAt ( sealedTok , "'sealed' may modify only an interface" , "NUPP1002" )
end



local function introduce ( n )
n . visibility = visibility
n . keyword = kw
n . modifier = modifierTok
if modifierTok then
add ( n , modifierTok )
end
if sealedTok then
add ( n , sealedTok )
end
add ( n , kw )

return n
end

if which == "type" then
local n = introduce ( setmetatable({ kind =  "typeAlias" }, cst.TypeAlias) )
parseDeclName ( n , "after '" .. which .. "'" )
parseGenerics ( n )
add ( n , expect ( "=" , "in " .. which .. " declaration" ) )
n . value = add ( n , parseType ( ) )
return n
else
local n = introduce ( setmetatable({ kind =  "recordDecl" }, cst.RecordDecl) )
n . declKind = which
n . sealedTok = sealedTok
parseDeclName ( n , "after '" .. which .. "'" )
parseGenerics ( n )
n . supertypes = { }
if cur ( ) . kind == "name" and cur ( ) . text == "is" then
add ( n , advance ( ) )
repeat
n . supertypes [ # n . supertypes + 1 ] = add ( n , parseType ( ) )
if cur ( ) . kind ~= "," then
break
end
add ( n , advance ( ) )
until false
end
if cur ( ) . kind == "name" and cur ( ) . text == "where" then
local where = setmetatable({ kind =  "whereClause" }, cst.WhereClause)
add ( where , advance ( ) )
where . expr = add ( where , parseExp ( ) )
n . whereClause = add ( n , where )
end
parseRecordBody ( n )
return n
end
end







local function parseCdef ( )
local cdefTok = advance ( )
if cur ( ) . kind == "function" then
local n = setmetatable({ kind =  "cdefFunc" }, cst.CdefFunc)
add ( n , cdefTok )
add ( n , advance ( ) )
n . name = add ( n , expectName ( "after 'cdef function'" ) )
add ( n , expect ( "(" , "in cdef function" ) )
n . params = { }
if cur ( ) . kind ~= ")" then
repeat
local p = setmetatable({ kind =  "param" }, cst.Param)
if cur ( ) . kind == "..." then
add ( p , advance ( ) )
n . varargs = true
n . params [ # n . params + 1 ] = add ( n , p )
break
end
if cur ( ) . kind == "name" and (
cur ( ) . text == "takes"
or cur ( ) . text == "borrows"
or cur ( ) . text == "scoped"
or cur ( ) . text == "exclusive"
or cur ( ) . text == "retains"
or cur ( ) . text == "releases"
or cur ( ) . text == "out"
) and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "name" then
p . modeTok = add ( p , advance ( ) )
end
p . name = add ( p , expectName ( "as cdef parameter" ) )
annotationColon ( p , "in cdef parameter" )



p . type = add ( p , parseBorrowRelation ( parseType ( ) ) )
if cur ( ) . kind == "name" and cur ( ) . text == "countedBy" then
p . countedByTok = add ( p , advance ( ) )
p . countedByTok . contextualOp = true
add ( p , expect ( "(" , "after 'countedBy'" ) )
p . countedBy = add ( p , expectName ( "as the countedBy parameter" ) )
add ( p , expect ( ")" , "to close countedBy" ) )
end
n . params [ # n . params + 1 ] = add ( n , p )
if cur ( ) . kind ~= "," then
break
end
add ( n , advance ( ) )
until false
end
add ( n , expect ( ")" , "to close cdef parameters" ) )
if cur ( ) . kind == ":" then
annotationColon ( n , "before cdef return type" )
n . ret = add ( n , parseType ( ) )
end

if cur ( ) . kind == "name" and cur ( ) . text == "from" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "string" then
add ( n , advance ( ) )
n . fromLib = add ( n , advance ( ) )
end
return n
end
local n = setmetatable({ kind =  "cdefStruct" }, cst.CdefStruct)
add ( n , cdefTok )
local aggregate = advance ( )
add ( n , aggregate )
n . aggregateKind = aggregate . text
n . name = add ( n , expectName ( "after 'cdef " .. aggregate . text .. "'" ) )
parseRecordBody ( n )

return n
end


parseStatement = function ( )
local kind = cur ( ) . kind

if kind == "name" and cur ( ) . text == "cdef" and tokens [
i + 1
] and (
tokens [
i + 1
] . kind == "function" or (
tokens [
i + 1
] . kind == "name" and (
tokens [ i + 1 ] . text == "struct" or tokens [ i + 1 ] . text == "union"
) and tokens [ i + 2 ] and tokens [ i + 2 ] . kind == "name"
)
) then
return parseCdef ( )
end

if kind == "@" then
local n = setmetatable({ kind =  "pragmaStmt" }, cst.PragmaStmt)
parseAnnotationApplication ( n )
n . stat = add ( n , parseStatement ( ) )
return n
end

if kind == ";" then
local n = setmetatable({ kind =  "emptyStmt" }, cst.EmptyStmt)
add ( n , advance ( ) )
return n

elseif kind == "if" then
local n = setmetatable({ kind =  "ifStmt" }, cst.IfStmt)
n . clauses = { }
local clause = setmetatable({ kind =  "ifClause" }, cst.IfClause)
add ( clause , advance ( ) )
clause . cond = add ( clause , parseExp ( ) )
add ( clause , expect ( "then" , "after condition" ) )
clause . body = add ( clause , parseBlock ( ) )
n . clauses [ 1 ] = add ( n , clause )
while cur ( ) . kind == "elseif" do
clause = setmetatable({ kind =  "elseifClause" }, cst.ElseifClause)
add ( clause , advance ( ) )
clause . cond = add ( clause , parseExp ( ) )
add ( clause , expect ( "then" , "after condition" ) )
clause . body = add ( clause , parseBlock ( ) )
n . clauses [ # n . clauses + 1 ] = add ( n , clause )
end
if cur ( ) . kind == "else" then
clause = setmetatable({ kind =  "elseClause" }, cst.ElseClause)
add ( clause , advance ( ) )
clause . body = add ( clause , parseBlock ( ) )
n . elseClause = add ( n , clause )
end
add ( n , expect ( "end" , "to close 'if'" ) )
return n

elseif kind == "while" then
local n = setmetatable({ kind =  "whileStmt" }, cst.WhileStmt)
add ( n , advance ( ) )
n . cond = add ( n , parseExp ( ) )
add ( n , expect ( "do" , "after condition" ) )
loopDepth = loopDepth + 1
n . body = add ( n , parseBlock ( ) )
loopDepth = loopDepth - 1
add ( n , expect ( "end" , "to close 'while'" ) )
return n

elseif kind == "do" then
local n = setmetatable({ kind =  "doStmt" }, cst.DoStmt)
add ( n , advance ( ) )
n . body = add ( n , parseBlock ( ) )
add ( n , expect ( "end" , "to close 'do'" ) )
return n

elseif kind == "for" then
local fortok = advance ( )
local name1 = expectName ( "after 'for'" )
if cur ( ) . kind == "=" then
local n = setmetatable({ kind =  "fornumStmt" }, cst.FornumStmt)
add ( n , fortok )
n . var = add ( n , name1 )
add ( n , advance ( ) )
n . start = add ( n , parseExp ( ) )
add ( n , expect ( "," , "in numeric for" ) )
n . stop = add ( n , parseExp ( ) )
if cur ( ) . kind == "," then
add ( n , advance ( ) )
n . step = add ( n , parseExp ( ) )
end
add ( n , expect ( "do" , "in numeric for" ) )
loopDepth = loopDepth + 1
n . body = add ( n , parseBlock ( ) )
loopDepth = loopDepth - 1
add ( n , expect ( "end" , "to close 'for'" ) )
return n
else
local n = setmetatable({ kind =  "forinStmt" }, cst.ForinStmt)
add ( n , fortok )
n . names = { add ( n , name1 ) }
while cur ( ) . kind == "," do
add ( n , advance ( ) )
n . names [ # n . names + 1 ] = add ( n , expectName ( "in for name list" ) )
end
add ( n , expect ( "in" , "in generic for" ) )
n . exprs = parseExplist ( n )
add ( n , expect ( "do" , "in generic for" ) )
loopDepth = loopDepth + 1
n . body = add ( n , parseBlock ( ) )
loopDepth = loopDepth - 1
add ( n , expect ( "end" , "to close 'for'" ) )
return n
end

elseif kind == "repeat" then
local n = setmetatable({ kind =  "repeatStmt" }, cst.RepeatStmt)
add ( n , advance ( ) )
loopDepth = loopDepth + 1
n . body = add ( n , parseBlock ( ) )
loopDepth = loopDepth - 1
add ( n , expect ( "until" , "to close 'repeat'" ) )
n . cond = add ( n , parseExp ( ) )
return n

elseif kind == "name" and cur ( ) . text == "handle" and tokens [
i + 1
] and tokens [ i + 1 ] . kind == "name" and tokens [ i + 1 ] . text == "suspension" then



local n = setmetatable({ kind =  "handleStmt" }, cst.HandleStmt)
n . handleTok = add ( n , advance ( ) )
add ( n , advance ( ) ) . contextualOp = true
if cur ( ) . kind == "name" and cur ( ) . text == "with" then
add ( n , advance ( ) ) . contextualOp = true
else
errAt ( cur ( ) , "'with' expected in 'handle suspension'" , "NUPP1002" )
end
n . handler = add ( n , parseExp ( ) )
n . doTok = add ( n , expect ( "do" , "to open 'handle suspension'" ) )
n . body = add ( n , parseBlock ( ) )
n . endTok = add ( n , expect ( "end" , "to close 'handle suspension'" ) )
return n

elseif kind == "name" and cur ( ) . text == "nosuspend" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "do" then
local n = setmetatable({ kind =  "noSuspendStmt" }, cst.NoSuspendStmt)
n . keywordTok = add ( n , advance ( ) )
n . doTok = add ( n , advance ( ) )
n . body = add ( n , parseBlock ( ) )
n . endTok = add ( n , expect ( "end" , "to close 'nosuspend do'" ) )
return n

elseif kind == "name" and (
cur ( ) . text == "noalloc" or cur ( ) . text == "noraise"
) and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "do" then
local written = cur ( ) . text
local n = setmetatable({ kind =
"effectRegionStmt" ,  effect =
written == "noalloc" and "allocates" or "raises" }, cst.EffectRegionStmt)

n . keywordTok = add ( n , advance ( ) )
n . doTok = add ( n , advance ( ) )
n . body = add ( n , parseBlock ( ) )
n . endTok = add ( n , expect ( "end" , "to close '" .. written .. " do'" ) )
return n

elseif kind == "name" and cur ( ) . text == "unsafe" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "do" then
local n = setmetatable({ kind =  "unsafeStmt" }, cst.UnsafeStmt)
n . unsafeTok = add ( n , advance ( ) )
n . doTok = add ( n , advance ( ) )
n . body = add ( n , parseBlock ( ) )
n . endTok = add ( n , expect ( "end" , "to close 'unsafe do'" ) )
return n

elseif startsTypedecl ( i ) then
return parseTypedecl ( nil , "module" )

elseif kind == "name" and cur ( ) . text == "global" and startsTypedecl ( i + 1 ) then
local globalTok = advance ( )
return parseTypedecl ( globalTok , "global" )

elseif kind == "function" or kind == "name" and cur ( ) . text == "comptime" and tokens [
i + 1
] and tokens [ i + 1 ] . kind == "function" then
local n = setmetatable({ kind =  "funcStmt" }, cst.FuncStmt)
if kind == "name" then
n . comptimeTok = add ( n , advance ( ) )
n . comptimeTok . contextualOp = true
end
add ( n , advance ( ) )
local fn = setmetatable({ kind =  "funcname" }, cst.Funcname)
fn . base = add ( fn , expectName ( "after 'function'" ) )
while cur ( ) . kind == "." do
add ( fn , advance ( ) )
add ( fn , expectName ( "after '.'" ) )
end
if cur ( ) . kind == ":" then
add ( fn , advance ( ) )
fn . method = add ( fn , expectName ( "after ':'" ) )
end
n . name = add ( n , fn )
n . body = add ( n , parseFuncbody ( ) )
return n

elseif kind == "name" and cur ( ) . text == "const" and tokens [
i + 1
] and (
tokens [ i + 1 ] . kind == "..." or tokens [ i + 1 ] . kind == "name"
) and (
(
tokens [ i + 1 ] . kind == "name" and tokens [ i + 2 ] and tokens [ i + 2 ] . kind == "."
) or (
tokens [
i + 1
] . kind == "..." and tokens [
i + 2
] and tokens [ i + 2 ] . kind == "name" and tokens [ i + 3 ] and tokens [ i + 3 ] . kind == "."
)
) then
local n = setmetatable({ kind =  "assignStmt" }, cst.AssignStmt)
n . isConst = true
add ( n , advance ( ) )
if cur ( ) . kind == "..." then
n . deepConst = true
add ( n , advance ( ) )
end
n . targets = { add ( n , parseSuffixedexp ( ) ) }
local function plainFieldPath ( target )
if target . kind ~= "dotIndex" then
return false
end
local base = target . obj

return base and ( base . kind == "name" or plainFieldPath ( base ) )
end

if not plainFieldPath ( n . targets [ 1 ] ) then
errAt ( cst . firstToken ( n . targets [ 1 ] ) or cur ( ) , "const field declaration needs a dotted field path" )
end
add ( n , expect ( "=" , "in const field declaration" ) )
n . exprs = parseExplist ( n )
if n . deepConst then
local function markDeep ( value )
if not value or value . kind ~= "tableExpr" then
return
end
for _ , field in ipairs ( value . fields or { } ) do
if field . kind == "fieldNamed" then
field . isConst = true
else
errAt ( cst . firstToken ( field ) or cur ( ) , "const... table requires named fields" )
end
if field . value then
markDeep ( field . value )
end
end
end

for _ , value in ipairs ( n . exprs ) do
markDeep ( value )
end
end
return n

elseif kind == "local" or (
kind == "name" and cur ( ) . text == "const" and tokens [
i + 1
] and ( tokens [ i + 1 ] . kind == "name" or tokens [ i + 1 ] . kind == "function" )
) then



local isConst = kind == "name"
local loctok = advance ( )
if cur ( ) . kind == "function" or cur ( ) . kind == "name" and cur ( ) . text == "comptime" and tokens [
i + 1
] and tokens [ i + 1 ] . kind == "function" then
local n = setmetatable({ kind =  "localFuncStmt" }, cst.LocalFuncStmt)
n . isConst = isConst
add ( n , loctok )
if cur ( ) . kind == "name" then
n . comptimeTok = add ( n , advance ( ) )
n . comptimeTok . contextualOp = true
end
add ( n , advance ( ) )
n . name = add (
n ,
expectName (
isConst and (
n . comptimeTok and "after 'const comptime function'" or "after 'const function'"
) or ( n . comptimeTok and "after 'local comptime function'" or "after 'local function'" )
)
)
n . body = add ( n , parseFuncbody ( ) )
return n
end



if not isConst and startsTypedecl ( i ) then
return parseTypedecl ( loctok , "local" )
end
local n = setmetatable({ kind =  "localStmt" }, cst.LocalStmt)
n . isConst = isConst
add ( n , loctok )
n . names = { }
n . types = { }
local function bind ( )
n . names [ # n . names + 1 ] = add ( n , expectName ( isConst and "after 'const'" or "after 'local'" ) )
if cur ( ) . kind == ":" then
annotationColon ( n , "in variable annotation" )
n . types [ # n . names ] = add ( n , parseType ( ) )
end
end

bind ( )
while cur ( ) . kind == "," do
add ( n , advance ( ) )
bind ( )
end
if cur ( ) . kind == "=" then
add ( n , advance ( ) )
n . exprs = parseExplist ( n )
end
return n

elseif kind == "::" then
local n = setmetatable({ kind =  "labelStmt" }, cst.LabelStmt)
add ( n , advance ( ) )
n . name = add ( n , expectName ( "in label" ) )
add ( n , expect ( "::" , "to close label" ) )
return n

elseif kind == "goto" then
local n = setmetatable({ kind =  "gotoStmt" }, cst.GotoStmt)
add ( n , advance ( ) )
n . name = add ( n , expectName ( "after 'goto'" ) )
return n

elseif kind == "break" then
local n = setmetatable({ kind =  "breakStmt" }, cst.BreakStmt)
add ( n , advance ( ) )
return n

elseif kind == "name" and cur ( ) . text == "continue" and tokens [ i + 1 ] and BLOCK_FOLLOW [ tokens [ i + 1 ] . kind ] then
local n = setmetatable({ kind =  "continueStmt" }, cst.ContinueStmt)
local tok = add ( n , advance ( ) )
if loopDepth == 0 then
errAt ( tok , "no loop to continue" )
end
return n

elseif kind == "return" then
local n = setmetatable({ kind =  "returnStmt" }, cst.ReturnStmt)
add ( n , advance ( ) )
if not BLOCK_FOLLOW [ cur ( ) . kind ] and cur ( ) . kind ~= ";" then
n . exprs = parseExplist ( n )
else
n . exprs = { }
end
if cur ( ) . kind == ";" then
add ( n , advance ( ) )
end
return n
end

if kind == "name" and cur ( ) . text == "drop" then
local n = setmetatable({ kind =  "callStmt" }, cst.CallStmt)
local dropTok = add ( n , advance ( ) )
dropTok . contextualOp = true
local value = add ( n , parseExp ( ) )
local callee = setmetatable({ kind =  "name" ,  token =  dropTok }, cst.NameExpr)
local args = setmetatable({ kind =  "args" ,  exprs =  { value } }, cst.Args)
n . expr = setmetatable({ kind =  "call" ,  obj =  callee ,  args =  args ,  ownershipSyntax =  "drop" }, cst.Call)
return n
end


local e = parseSuffixedexp ( )
if compoundOp ( ) then
local n = setmetatable({ kind =  "compoundAssign" }, cst.CompoundAssign)
n . target = add ( n , e )
n . op = add ( n , advance ( ) )
n . value = add ( n , parseExp ( ) )
local tk = e . kind
if not (
tk == "name"
or tk == "dotIndex"
or tk == "bracketIndex"
or tk == "safeIndex"
or tk == "safeBracket"
or tk == "errorExpr"
) then
errAt ( cur ( ) , "cannot assign to this expression" )
end
return n
end
if cur ( ) . kind == "=" or cur ( ) . kind == "," then
local n = setmetatable({ kind =  "assignStmt" }, cst.AssignStmt)
n . targets = { add ( n , e ) }
while cur ( ) . kind == "," do
add ( n , advance ( ) )
n . targets [ # n . targets + 1 ] = add ( n , parseSuffixedexp ( ) )
end
add ( n , expect ( "=" , "in assignment" ) )
n . exprs = parseExplist ( n )
for _ , target in ipairs ( n . targets ) do
local tk = target . kind
if not (
tk == "name"
or tk == "dotIndex"
or tk == "bracketIndex"
or tk == "safeIndex"
or tk == "safeBracket"
or tk == "errorExpr"
) then
errAt ( cur ( ) , "cannot assign to this expression" )
end
end
return n
end
local ek = e . kind
if ek == "call" or ek == "methodCall" or ek == "safeCall" or ek == "errorExpr" then
local n = setmetatable({ kind =  "callStmt" }, cst.CallStmt)
n . expr = add ( n , e )
return n
end
errAt ( cur ( ) , "syntax error: expression is not a statement" )
local n = setmetatable({ kind =  "errorStmt" }, cst.ErrorStmt)
add ( n , e )

return n
end


parseBlock = function ( )
local n = setmetatable({ kind =  "block" }, cst.Block)
n . stats = { }
local returned = false
while not BLOCK_FOLLOW [ cur ( ) . kind ] do



if returned then
errAt (
cur ( ) ,
"'return' must be the last statement in a block" ,
nil ,
"move the 'return' below the statements that follow " .. "it, or delete them"
)
returned = false
end
local start = i
local s = parseStatement ( )
if s . kind == "returnStmt" then
returned = true
end
n . stats [ # n . stats + 1 ] = add ( n , s )



if i == start then
local e = setmetatable({ kind =  "errorStmt" }, cst.ErrorStmt)
errAt ( cur ( ) , ( "unexpected '%s'" ) : format ( spelling ( cur ( ) ) ) )
add ( e , advance ( ) )
n . stats [ # n . stats + 1 ] = add ( n , e )
end
end

return n
end

local root = setmetatable({ kind =  "chunk" }, cst.Chunk)
root . blocks = { }
while cur ( ) . kind == "@" and tokens [
i + 1
] and tokens [
i + 1
] . kind == "not" and tokens [ i + 1 ] . text == "!" and tokens [ i + 2 ] and tokens [ i + 2 ] . kind == "name" do
local name = tokens [ i + 2 ] . text
if name ~= "nofmt" and name ~= "internal" then
break
end


root . formatDisabled = root . formatDisabled or name == "nofmt"
root . documentationInternal = root . documentationInternal or name == "internal"
tokens [ i ] . startsStat = true
tokens [ i ] . blockDepth = 0
tokens [ i + 1 ] . unaryTok = true
tokens [ i + 1 ] . blockDepth = 0
tokens [ i + 2 ] . blockDepth = 0
advance ( ) ;
advance ( ) ;
advance ( )
end
while true do
root . blocks [ # root . blocks + 1 ] = add ( root , parseBlock ( ) )
if cur ( ) . kind == "eof" then
break
end


local e = setmetatable({ kind =  "errorStmt" }, cst.ErrorStmt)
errAt ( cur ( ) , ( "unexpected '%s' at top level" ) : format ( spelling ( cur ( ) ) ) )
add ( e , advance ( ) )
add ( root , e )
end
root . eof = add ( root , advance ( ) )

return { root = root , tokens = tokens , errors = errors }
end

return parser
