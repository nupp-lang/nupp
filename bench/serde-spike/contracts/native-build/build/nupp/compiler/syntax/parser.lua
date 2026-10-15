_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()
















local lexer = require ( "nupp.compiler.syntax.lexer" )
local cst = require ( "nupp.compiler.syntax.cst" )

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

local PARAM_MODES = {
[ "takes" ] = true ,
[ "borrows" ] = true ,
[ "scoped" ] = true ,
[ "exclusive" ] = true ,
[ "retains" ] = true ,
[ "releases" ] = true ,
}

local ASSIGN_TARGETS = {
[ "name" ] = true ,
[ "dotIndex" ] = true ,
[ "bracketIndex" ] = true ,
[ "safeIndex" ] = true ,
[ "safeBracket" ] = true ,
[ "errorExpr" ] = true ,
}

local EXPR_START = {
[ "@" ] = true ,
[ "number" ] = true ,
[ "string" ] = true ,
[ "nil" ] = true ,
[ "true" ] = true ,
[ "false" ] = true ,
[ "..." ] = true ,
[ "function" ] = true ,
[ "do" ] = true ,
[ "{" ] = true ,
[ "name" ] = true ,
[ "(" ] = true ,
[ "|" ] = true ,
[ "istringOpen" ] = true ,
}








const MAX_NESTING = 1000


local TOO_DEEP = { }












function parser . parse ( source , filename ) 
local tokens , errors = lexer . lex ( source , filename )
local i = 1
local hasDeclaredModule = false



local noMethod = 0





local noArrow = 0



local loopDepth = 0





local repeatConditionDepth = 0


local valueBlockDepth = 0

local nesting = 0
local tooDeepAt = nil














local genericCloseHalfAt = nil
local genericCloseHalf = nil


local function cur ( ) 
if genericCloseHalfAt == i and genericCloseHalf then
return genericCloseHalf
end

return tokens [ i ]
end





local function atEmptyPipes ( ) 
local tok = cur ( )
return tok . kind == "or" and tok . text == "||"
end




local function startsShortfn ( at ) 
local tok = tokens [ at ]

return tok ~= nil and ( tok . kind == "|" or ( tok . kind == "or" and tok . text == "||" ) )
end


local function atExprStart ( ) 
local kind = cur ( ) . kind
return EXPR_START [ kind ] or UNOPS [ kind ] or kind == "error" or atEmptyPipes ( )
end



local function advance ( ) 
if genericCloseHalfAt == i and genericCloseHalf then
local half = genericCloseHalf
genericCloseHalfAt , genericCloseHalf = nil , nil

return half
end
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




return ( ("%q") : format ( tok . text ) : gsub ( "[€-ÿ]" , function ( b ) 
return ("\\x%02X") : format ( b : byte ( ) )
end ) )
end






local function errAt ( tok , msg , code , help , fixes ) 
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
help = help ,
fixes = fixes ,
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
errAt ( cur ( ) , ("'%s' expected%s; found %s") : format ( kind , what and ( " " .. what ) or "" , found ( cur ( ) ) ) , "NUPP1002" )

return missing ( kind )
end


local function expectName ( what ) 
if cur ( ) . kind == "name" then
return advance ( )
end
errAt ( cur ( ) , ("name expected%s; found %s") : format ( what and ( " " .. what ) or "" , found ( cur ( ) ) ) , "NUPP1003" )

return missing ( "name" )
end





local function expectGenericClose ( what ) 
if cur ( ) . kind == ">>" then
local tok = advance ( )
local at = tokens [ i ]
genericCloseHalf = {
kind = ">" ,
text = "" ,
missing = true ,
trivia = at . trivia ,
triviaFirst = 1 ,
triviaCount = 0 ,
offset = at . offset ,
line = at . line ,
col = at . col
}
genericCloseHalfAt = i

return tok
end

return expect ( ">" , what )
end









local function resetNoMethod ( fn , ... ) 
local saved = noMethod
local savedArrow = noArrow
noMethod = 0
noArrow = 0
local r = fn ( ... )
noMethod = saved
noArrow = savedArrow

return r
end

local parseAnnotationApplication , parseAnnotatedOperand , parseOwnership , parseBinexp
local parseExp , parseBlock , parseSuffixedexp , parseTableconstructor , parseFuncbody , parseType , parsePosttype , parseTypePack , parseStatement , parseReturnType , parseIstring , parseCaptureClause




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


local following = tokens [ at + 1 ]
if kw
and kw . kind == "name"
and kw . text == "sealed"
and following
and following . kind == "name"
and TYPEDECL_KW [ following . text ]
then
at = at + 1
kw = following
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

local function startsExport ( at ) 
local nextToken = tokens [ at + 1 ]
if not nextToken then
return false
end
if nextToken . kind == "function" or startsTypedecl ( at + 1 ) then
return true
end
if nextToken . kind ~= "name" then
return false
end
if nextToken . text == "const" then
local declared = tokens [ at + 2 ]
return declared ~= nil and ( declared . kind == "name" or declared . kind == "function" )
end

return false
end


local function startsWith ( at ) 
local kw , name , after = tokens [ at ] , tokens [ at + 1 ] , tokens [ at + 2 ]
return kw ~= nil
and kw . kind == "name"
and kw . text == "with"
and name ~= nil
and name . kind == "name"
and after ~= nil
and ( after . kind == "=" or after . kind == ":" )
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
local g = _G.setmetatable({ names =
{ } ,  bounds =
{ } ,  packs =
{ } ,  consts =
{ } ,  domains =
{ } ,  defaults =
{ } ,  kind =
"generics" }, cst.Generics)

add ( g , advance ( ) ) . generic = true
repeat
local at = # g . names + 1
local isConst = cur ( ) . kind == "name"
and cur ( ) . text == "const"
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "name"
and tokens [ i + 2 ]
and tokens [ i + 2 ] . kind == ":"
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
do break end
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
or k == "@"
or k == "function"
or k == "("
or k == "string"
or k == "number"
or k == "true"
or k == "false"
or k == "istringOpen"
end



local function borrowsExternalSource ( params , borrowed ) 
local parameterNames = { self = true }
for _ , parameter in ipairs ( params ) do
if parameter . name then
parameterNames [ parameter . name . text ] = true
end
end
local external = false
for _ , source in ipairs ( borrowed . params or { } ) do
external = external or not parameterNames [ source . text ]
end

return external
end





local function attachReturnPack ( n , returnPack ) 
n . returnPack = returnPack
if returnPack . kind == "tpack" and not returnPack . tail then
for _ , child in ipairs ( returnPack ) do
add ( n , child )
end
else
add ( n , returnPack )
end
n . rets = returnPack . kind == "tpack" and returnPack . types or { }
for _ , result in ipairs ( n . rets or { } ) do
if result . kind == "tborrows" then
local borrowed = result
if borrowsExternalSource ( n . params , borrowed ) then
return borrowed
end
end
end

return nil
end




local function parseFunctionBlock ( ) 
local savedLoopDepth , savedValueBlockDepth = loopDepth , valueBlockDepth
local savedRepeatCondition = repeatConditionDepth
loopDepth , valueBlockDepth , repeatConditionDepth = 0 , 0 , 0
local body = parseBlock ( )
loopDepth , valueBlockDepth = savedLoopDepth , savedValueBlockDepth
repeatConditionDepth = savedRepeatCondition

return body
end





local function parseTypeArgument ( packArgs ) 
local explicitPack = cur ( ) . kind == "..."
or cur ( ) . kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "..."

return ( packArgs or explicitPack ) and parseTypePack ( false ) or parseType ( )
end


local function parseTypePrimary ( ) 
local kind = cur ( ) . kind
if kind == "@" then
local attached = { }
while cur ( ) . kind == "@" do
local application = parseAnnotationApplication ( _G.setmetatable({ kind =  "annotationApply" }, cst.AnnotationApply) , true )
application . typeAttachment = true
attached [ # attached + 1 ] = application
end
local inner = parseTypePrimary ( )
inner . typeAnnotations = inner . typeAnnotations or { }
for _ , application in ipairs ( attached ) do
inner . typeAnnotations [ # inner . typeAnnotations + 1 ] = application
end
for at = # attached , 1 , -1 do
table . insert ( inner , 1 , attached [ at ] )
end
return inner
end
if kind == "name"
and ( cur ( ) . text == "keyof" or cur ( ) . text == "writekeyof" )
and startsType ( tokens [ i + 1 ] )
and tokens [ i + 1 ] . line == cur ( ) . line
then
local n = _G.setmetatable({ kind =  "tkeyof" ,  capability =  cur ( ) . text == "keyof" and "read" or "write" }, cst.Tkeyof)
add ( n , advance ( ) ) . contextualOp = true
n . inner = add ( n , parseTypePrimary ( ) )
return n
end
if kind == "name"
and cur ( ) . text == "writeof"
and startsType ( tokens [ i + 1 ] )
and tokens [ i + 1 ] . line == cur ( ) . line
then
local n = _G.setmetatable({ kind =  "twriteof" }, cst.Twriteof)
add ( n , advance ( ) ) . contextualOp = true
n . inner = add ( n , parsePosttype ( ) )
return n
end



if kind == "name" and cur ( ) . text == "const" and startsType ( tokens [ i + 1 ] ) then
local n = _G.setmetatable({ kind =  "tconst" }, cst.Tconst)
add ( n , advance ( ) )
n . inner = add ( n , parseTypePrimary ( ) )
return n
end
if kind == "string" or kind == "number" or kind == "true" or kind == "false" then




local n = _G.setmetatable({ kind =  "tliteral" }, cst.Tliteral)
n . token = add ( n , advance ( ) )
return n
end
if kind == "-" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "number" then



local n = _G.setmetatable({ kind =  "tliteral" }, cst.Tliteral)
n . negated = true
add ( n , advance ( ) )
n . token = add ( n , advance ( ) )
return n
end
if kind == "name" or kind == "nil" then
local n = _G.setmetatable({ kind =  "tname" }, cst.Tname)
n . base = add ( n , advance ( ) )
while cur ( ) . kind == "." and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "name" do
add ( n , advance ( ) )
add ( n , expectName ( "after '.' in type name" ) )
end
if cur ( ) . kind == "<" then
add ( n , advance ( ) ) . generic = true
local packArgs = n . base and n . base . text == "thread"

local function argument ( ) 
return parseTypeArgument ( packArgs )
end

n . typeArgs = { add ( n , argument ( ) ) }
while cur ( ) . kind == "," do
add ( n , advance ( ) )
n . typeArgs [ # n . typeArgs + 1 ] = add ( n , argument ( ) )
end
add ( n , expectGenericClose ( "to close type arguments" ) ) . generic = true
end
if cur ( ) . kind == "(" then
local call = _G.setmetatable({ kind =  "ttypecall" ,  arguments =  { } }, cst.Ttypecall)
call . callee = add ( call , n )
add ( call , advance ( ) )


if cur ( ) . kind ~= ")" then
call . arguments [ 1 ] = add ( call , parseTypeArgument ( ) )
while cur ( ) . kind == "," do
add ( call , advance ( ) )
call . arguments [ # call . arguments + 1 ] = add ( call , parseTypeArgument ( ) )
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
local pack = _G.setmetatable({ kind =  "tpack" ,  types =  { } }, cst.Tpack)
add ( pack , open )
pack . types [ 1 ] = add ( pack , first )
while cur ( ) . kind == "," do
add ( pack , advance ( ) )
pack . types [ # pack . types + 1 ] = add ( pack , parseType ( ) )
end
add ( pack , expect ( ")" , "to close type pack" ) )
return pack
end
local n = _G.setmetatable({ kind =  "tparen" }, cst.Tparen)
add ( n , open )
n . inner = add ( n , first )
add ( n , expect ( ")" , "to close type" ) )
return n
elseif kind == "{" then
local n
local addOpen = advance ( )

local function annotatedShapeMemberKind ( at ) 
local found = false
while tokens [ at ] and tokens [ at ] . kind == "@" do
local name = tokens [ at + 1 ]
if not name or name . kind ~= "name" then
return nil
end
found = true
at = at + 2
if tokens [ at ] and tokens [ at ] . kind == "(" then
local depth = 0
repeat
local token = tokens [ at ]
if not token then
return nil
elseif token . kind == "(" then
depth = depth + 1
elseif token . kind == ")" then
depth = depth - 1
end
at = at + 1
until depth == 0
end
end
local member = tokens [ at ]
if not found or not member then
return nil
end
if member . kind == "[" then
return "indexer"
end

return member . kind == "name" and tokens [ at + 1 ] and tokens [ at + 1 ] . kind == ":" and "field" or nil
end

local function shapeMember ( ) 
local annotations = { }
while cur ( ) . kind == "@" do
local application = parseAnnotationApplication ( _G.setmetatable({ kind =  "annotationApply" }, cst.AnnotationApply) )
application . propertyCapabilityAttachment = true
application . name . propertyCapability = true
annotations [ # annotations + 1 ] = application
end
local member
if cur ( ) . kind == "["
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "name"
and tokens [ i + 2 ]
and tokens [ i + 2 ] . kind == "in"
then
member = _G.setmetatable({ kind =  "tmapped" ,  annotations =  annotations }, cst.Tmapped)
for _ , application in ipairs ( annotations ) do
add ( member , application )
end
add ( member , advance ( ) )
member . binder = add ( member , advance ( ) )
add ( member , advance ( ) ) . contextualOp = true
member . keys = add ( member , parseType ( ) )
if cur ( ) . kind == "name" and cur ( ) . text == "as" then
add ( member , advance ( ) ) . contextualOp = true
member . remap = add ( member , parseType ( ) )
end
add ( member , expect ( "]" , "to close mapped member" ) )
annotationColon ( member , "in mapped member" )
member . value = add ( member , parseType ( ) )
elseif cur ( ) . kind == "[" then
member = _G.setmetatable({ kind =  "tmap" }, cst.Tmap)
member . annotations = annotations
for _ , application in ipairs ( annotations ) do
add ( member , application )
end
add ( member , advance ( ) )
member . key = add ( member , parseType ( ) )
add ( member , expect ( "]" , "to close indexer key type" ) )
annotationColon ( member , "in indexer type" )
member . value = add ( member , parseType ( ) )
else
member = _G.setmetatable({ kind =  "tshapeField" }, cst.TshapeField)
member . annotations = annotations
for _ , application in ipairs ( annotations ) do
add ( member , application )
end
member . name = add ( member , expectName ( "in shape field" ) )
annotationColon ( member , "in shape field" )
member . type = add ( member , parseType ( ) )
end

return member
end

if cur ( ) . kind == "[" or annotatedShapeMemberKind ( i ) == "indexer" then

local first = shapeMember ( )
if first . kind == "tmapped" then
table . insert ( first , 1 , addOpen )
add ( first , expect ( "}" , "to close mapped shape" ) )
return first
end
if cur ( ) . kind == "," then
n = _G.setmetatable({ kind =  "tshape" ,  fields =  { } }, cst.Tshape)
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
elseif cur ( ) . kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == ":"
or annotatedShapeMemberKind ( i ) == "field"
then


n = _G.setmetatable({ fields =  { } ,  kind =  "tshape" }, cst.Tshape)
add ( n , addOpen )
repeat
local f = shapeMember ( )
n . fields [ # n . fields + 1 ] = add ( n , f )
if cur ( ) . kind ~= "," then
do break end
end
add ( n , advance ( ) )
until cur ( ) . kind == "}" or cur ( ) . kind == "eof"
else

local first = parseType ( )
if cur ( ) . kind == "," then
n = _G.setmetatable({ types =  { } ,  kind =  "ttuple" }, cst.Ttuple)
add ( n , addOpen )
n . types [ 1 ] = add ( n , first )
while cur ( ) . kind == "," do
add ( n , advance ( ) )
if cur ( ) . kind == "}" then
do break end
end
if cur ( ) . kind == "name"
and cur ( ) . text == "unpackof"
and startsType ( tokens [ i + 1 ] )
and tokens [ i + 1 ] . line == cur ( ) . line
then
add ( n , advance ( ) ) . contextualOp = true
n . tail = add ( n , parseType ( ) )
do break end
end
n . types [ # n . types + 1 ] = add ( n , parseType ( ) )
end
else
n = _G.setmetatable({ kind =  "tarray" }, cst.Tarray)
add ( n , addOpen )
n . element = add ( n , first )
end
end
add ( n , expect ( "}" , "to close table type" ) )
return n
elseif kind == "function" then
local n = _G.setmetatable({ params =  { } ,  kind =  "tfunc" }, cst.Tfunc)
add ( n , advance ( ) )
parseGenerics ( n )
add ( n , expect ( "(" , "in function type" ) )
if cur ( ) . kind ~= ")" then
repeat
local p = _G.setmetatable({ kind =  "tfuncParam" }, cst.TfuncParam)
local isFunctionConst = cur ( ) . kind == "name"
and cur ( ) . text == "const"
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "name"
and tokens [ i + 2 ]
and tokens [ i + 2 ] . kind == ":"
and tokens [ i + 3 ]
and tokens [ i + 3 ] . kind == "function"
if isFunctionConst then
p . constTok = add ( p , advance ( ) )
p . constTok . contextualOp = true
p . name = add ( p , advance ( ) )
annotationColon ( p , "after const function parameter" )
p . constDomainTok = add ( p , advance ( ) )
n . params [ # n . params + 1 ] = add ( n , p )
else
if cur ( ) . kind == "name"
and PARAM_MODES [ cur ( ) . text ]
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "..."
then
p . modeTok = add ( p , advance ( ) )
end
if cur ( ) . kind == "..." then
add ( p , advance ( ) )
p . vararg = true
if cur ( ) . kind == ":" then
annotationColon ( p , "in vararg type" )
if cur ( ) . kind == "name"
and (
( tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "..." )
or ( cur ( ) . text == "unpackof" and startsType ( tokens [ i + 1 ] ) )
)
then
p . type = add ( p , parseTypePack ( ) )
p . pack = true
else
p . type = add ( p , parseType ( ) )
end
end
n . params [ # n . params + 1 ] = add ( n , p )
do break end
elseif cur ( ) . kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "..." then
local pack = _G.setmetatable({ kind =  "tpack" ,  types =  { } }, cst.Tpack)
local tail = _G.setmetatable({ kind =  "tname" }, cst.Tname)
tail . base = add ( tail , advance ( ) )
pack . tail = add ( pack , tail )
pack . tailKind = "generic"
add ( pack , advance ( ) ) . generic = true
p . type , p . pack = add ( p , pack ) , true
n . params [ # n . params + 1 ] = add ( n , p )
do break end
elseif cur ( ) . kind == "name"
and PARAM_MODES [ cur ( ) . text ]
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "name"
and tokens [ i + 2 ]
and tokens [ i + 2 ] . kind == ":"
then
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
end
if cur ( ) . kind ~= "," then
do break end
end
add ( n , advance ( ) )
until false
end
add ( n , expect ( ")" , "to close function type parameters" ) )
if cur ( ) . kind == ":" then
annotationColon ( n , "before return type" )



local returnPack = parseTypePack ( false , true )
local borrowed = attachReturnPack ( n , returnPack )
if borrowed then
n . captureBorrows = borrowed
if borrowed . type then
( n . rets or { } ) [ 1 ] = borrowed . type
if returnPack . kind == "tpack" then
returnPack . types [ 1 ] = borrowed . type
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
local n = _G.setmetatable({ kind =  "errorType" }, cst.ErrorType)
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
n = _G.setmetatable({ kind =  "topt" }, cst.Topt)
else
n = _G.setmetatable({ kind =  "tptr" }, cst.Tptr)
end
n . inner = add ( n , t )
add ( n , advance ( ) ) . typePostfix = true
t = n
elseif k == "[" and tokens [ i - 1 ] and tokens [ i - 1 ] . line == cur ( ) . line then




local n = _G.setmetatable({ kind =  "tcarray" }, cst.Tcarray)
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
local n = _G.setmetatable({ kind =  "tmember" }, cst.Tmember)
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
local at = i + 1
while tokens [ at ] and tokens [ at ] . kind == "@" do
local qualifier = tokens [ at + 1 ]
if not qualifier
or qualifier . kind ~= "name"
or qualifier . text ~= "comptime" and qualifier . text ~= "nosuspend" and qualifier . text ~= "sendable"
then
do break end
end
at = at + 2
end
local nextToken = tokens [ at ]

return nextToken ~= nil
and (
nextToken . kind == "function"
or nextToken . kind == "name"
and nextToken . text == "comptime"
and tokens [ at + 1 ]
and tokens [ at + 1 ] . kind == "function"
)
or false
end

if cur ( ) . kind ~= "&" or stopAtFunctionMember and nextIsFunctionMember ( ) then
return t
end
local n = _G.setmetatable({ types =  { } ,  kind =  "tintersection" }, cst.Tintersection)
n . types [ 1 ] = add ( n , t )
while cur ( ) . kind == "&" and not ( stopAtFunctionMember and nextIsFunctionMember ( ) ) do
add ( n , advance ( ) )
n . types [ # n . types + 1 ] = add ( n , parsePosttype ( ) )
end

return n
end





local function parseTypeNested ( noUnion , stopAtFunctionMember ) 
local t = parseIntersection ( stopAtFunctionMember )
if noUnion or cur ( ) . kind ~= "|" then
return t
end
local n = _G.setmetatable({ types =  { } ,  kind =  "tunion" }, cst.Tunion)
n . types [ 1 ] = add ( n , t )
while cur ( ) . kind == "|" do
add ( n , advance ( ) )
n . types [ # n . types + 1 ] = add ( n , parseIntersection ( stopAtFunctionMember ) )
end

return n
end

parseType = function ( noUnion , stopAtFunctionMember ) 
nesting = nesting + 1
if nesting > 1000 then
tooDeepAt = cur ( )
error ( TOO_DEEP , 0 )
end
local n = parseTypeNested ( noUnion , stopAtFunctionMember )
nesting = nesting - 1

return n
end


parseTypePack = function ( allowBareList , stopAtFunctionMember ) 
if cur ( ) . kind == "name"
and cur ( ) . text == "unpackof"
and startsType ( tokens [ i + 1 ] )
and tokens [ i + 1 ] . line == cur ( ) . line
then
local n = _G.setmetatable({ kind =  "tpack" ,  types =  { } ,  tailKind =  "computed" }, cst.Tpack)
add ( n , advance ( ) ) . contextualOp = true
n . tail = add ( n , parseType ( nil , stopAtFunctionMember ) )
return n
end
if cur ( ) . kind == "..." then
local n = _G.setmetatable({ kind =  "tpack" ,  types =  { } ,  tailKind =  "homogeneous" }, cst.Tpack)
local dots = add ( n , advance ( ) )
dots . generic , dots . homogeneousPack = true , true
n . tail = add ( n , parseType ( nil , stopAtFunctionMember ) )
return n
end
if cur ( ) . kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "..." then
local n = _G.setmetatable({ kind =  "tpack" ,  types =  { } ,  tailKind =  "generic" }, cst.Tpack)
local tail = _G.setmetatable({ kind =  "tname" }, cst.Tname)
tail . base = add ( tail , advance ( ) )
n . tail = add ( n , tail )
add ( n , advance ( ) ) . generic = true
return n
end
if cur ( ) . kind ~= "(" then
local n = _G.setmetatable({ kind =  "tpack" ,  types =  { } }, cst.Tpack)
n . types [ 1 ] = add ( n , parseReturnType ( stopAtFunctionMember ) )
while allowBareList and cur ( ) . kind == "," and startsType ( tokens [ i + 1 ] ) do
add ( n , advance ( ) ) . typeSeparator = true
n . types [ # n . types + 1 ] = add ( n , parseReturnType ( stopAtFunctionMember ) )
end
return n
end
local n = _G.setmetatable({ kind =  "tpack" ,  types =  { } }, cst.Tpack)






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
local union = _G.setmetatable({ kind =  "tpackUnion" ,  packs =  { first } }, cst.TpackUnion)
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
do break end
end
if cur ( ) . kind == "name"
and cur ( ) . text == "unpackof"
and startsType ( tokens [ i + 1 ] )
and tokens [ i + 1 ] . line == cur ( ) . line
then
add ( n , advance ( ) ) . contextualOp = true
n . tailKind = "computed"
n . tail = add ( n , parseType ( nil , stopAtFunctionMember ) )
do break end
end
local item = add ( n , parseReturnType ( stopAtFunctionMember ) )
if cur ( ) . kind == "..." then
if item . kind ~= "tname" then
errAt ( cur ( ) , "only a generic pack name may precede '...'" )
end
add ( n , advance ( ) ) . generic = true
n . tail , n . tailKind = item , "generic"
do break end
end
n . types [ # n . types + 1 ] = item
if cur ( ) . kind ~= "," then
do break end
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




local function pluckGroupAhead ( open , close ) 
if cur ( ) . kind ~= open then
return false
end
local j = i + 1
if not tokens [ j ] or tokens [ j ] . kind ~= "name" then
return false
end
j = j + 1
if tokens [ j ]
and tokens [ j ] . kind == "name"
and tokens [ j ] . text == "as"
and tokens [ j + 1 ]
and tokens [ j + 1 ] . kind == "name"
then
j = j + 2
end
while tokens [ j ] and tokens [ j ] . kind == "," do
if not tokens [ j + 1 ] or tokens [ j + 1 ] . kind ~= "name" then
return false
end
j = j + 2
if tokens [ j ]
and tokens [ j ] . kind == "name"
and tokens [ j ] . text == "as"
and tokens [ j + 1 ]
and tokens [ j + 1 ] . kind == "name"
then
j = j + 2
end
end

return tokens [ j ] ~= nil and tokens [ j ] . kind == close and tokens [ j + 1 ] ~= nil and tokens [ j + 1 ] . kind == "="
end


local function parseCallargs ( typeFirst ) 
local kind = cur ( ) . kind
if kind == "(" then
local n = _G.setmetatable({ kind =  "args" }, cst.Args)
add ( n , advance ( ) )
n . exprs = { }
if cur ( ) . kind ~= ")" then
repeat
local argument
if typeFirst and # n . exprs == 0 then
argument = parseType ( )
n . typeArg = argument
elseif pluckGroupAhead ( "{" , "}" ) or pluckGroupAhead ( "(" , ")" ) then
local pluck = _G.setmetatable({ kind =  "pluckArg" ,  names =  { } }, cst.PluckArg)
local oldSpelling = cur ( ) . kind == "("
local closeKind = oldSpelling and ")" or "}"
local openTok = add ( pluck , advance ( ) )
pluck . names [ 1 ] = add ( pluck , advance ( ) )
local invalidAliases



= { }
if cur ( ) . kind == "name" and cur ( ) . text == "as" then
local asTok = add ( pluck , advance ( ) )
local alias = add ( pluck , expectName ( "after 'as' in plucked arguments" ) )
invalidAliases [
# invalidAliases + 1
] = { token = asTok , source = pluck . names [ 1 ] , alias = alias , }
end
while cur ( ) . kind == "," do
add ( pluck , advance ( ) )
pluck . names [ # pluck . names + 1 ] = add ( pluck , advance ( ) )
if cur ( ) . kind == "name" and cur ( ) . text == "as" then
local asTok = add ( pluck , advance ( ) )
local alias = add ( pluck , expectName ( "after 'as' in plucked arguments" ) )
invalidAliases [
# invalidAliases + 1
] = { token = asTok , source = pluck . names [ # pluck . names ] , alias = alias , }
end
end
local closeTok = add ( pluck , expect ( closeKind , "to close a plucked parameter group" ) )
add ( pluck , advance ( ) )



pluck . value = add ( pluck , resetNoMethod ( parseExp ) )
for _ , invalid in ipairs ( invalidAliases ) do
local fixes = nil
if # pluck . names == 1 and pluck . value then
local final = cst . lastToken ( pluck . value )
if final then
fixes = {
{
title = "use a named argument" ,
edits = {
{
offset = openTok . offset ,
length = final . offset + # final . text - openTok . offset ,
newText = invalid . alias . text
.. " = "
.. cst . textOf ( pluck . value ) : gsub ( "^%s+" , "" )
.. "."
.. invalid . source . text ,
} ,
} ,
}
}
end
end
errAt (
invalid . token ,
"'as' aliases bindings, not plucked arguments" ,
"NUPP1002" ,
"use an ordinary named argument to map a differently named field" ,
fixes
)
end
if oldSpelling then
errAt (
openTok ,
"plucked arguments use braces" ,
"NUPP1002" ,
"replace the parentheses around the plucked names with braces" ,
{
{
title = "use a braced pluck" ,
edits = {
{ offset = openTok . offset , length = # openTok . text , newText = "{" } ,
{ offset = closeTok . offset , length = # closeTok . text , newText = "}" } ,
} ,
}
}
)
end
argument = pluck
elseif cur ( ) . kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "=" then
local named = _G.setmetatable({ kind =  "namedArg" }, cst.NamedArg)
named . name = add ( named , advance ( ) )
add ( named , advance ( ) )
named . value = add ( named , resetNoMethod ( parseExp ) )
argument = named
else
argument = resetNoMethod ( parseExp )
end
n . exprs [ # n . exprs + 1 ] = add ( n , argument )
if cur ( ) . kind ~= "," then
do break end
end
add ( n , advance ( ) )
until false
end
add ( n , expect ( ")" , "to close arguments" ) )
return n
elseif kind == "{" then
local n = _G.setmetatable({ kind =  "args" }, cst.Args)
n . table = add ( n , resetNoMethod ( parseTableconstructor ) )
return n
elseif kind == "string" then
local n = _G.setmetatable({ kind =  "args" }, cst.Args)
n . str = add ( n , advance ( ) )
return n
end

return nil
end












local TYPE_ARGUMENT_TOKEN = { }

for kind in ("name . , ? | & : < > >> ( ) { } [ ] @ number string nil true false function ... -> const borrows takes scoped")


: gmatch ( "%S+" ) do
TYPE_ARGUMENT_TOKEN [ kind ] = true
end










local function opensCallTypeArguments ( at ) 
local depth , j = 0 , at
while tokens [ j ] do
local k = tokens [ j ] . kind
if k == "<" then
depth = depth + 1
elseif k == ">" or k == ">>" then
depth = depth - ( k == ">>" and 2 or 1 )
if depth <= 0 then
local next_ = tokens [ j + 1 ]

return depth == 0 and next_ ~= nil and next_ . kind == "("
end
elseif not TYPE_ARGUMENT_TOKEN [ k ] then
return false
end
j = j + 1
end

return false
end

local function parseMethodCall ( obj , safeObj ) 
local n = _G.setmetatable({ kind =  "methodCall" }, cst.MethodCall)
n . obj = add ( n , obj )
if safeObj then
n . safeObj = add ( n , safeObj )
end
add ( n , advance ( ) )
n . name = add ( n , expectName ( "for method call" ) )
if cur ( ) . kind == "<" then
add ( n , advance ( ) ) . generic = true
n . typeArgs = { }
repeat
n . typeArgs [ # n . typeArgs + 1 ] = add ( n , parseType ( ) )
if cur ( ) . kind ~= "," then
do break end
end
add ( n , advance ( ) ) . typeSeparator = true
until false
add ( n , expectGenericClose ( "to close method type arguments" ) ) . generic = true
end
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
local n = _G.setmetatable({ kind =  "name" }, cst.NameExpr)
n . token = add ( n , advance ( ) )
return n
elseif kind == "(" then
local n = _G.setmetatable({ kind =  "paren" }, cst.Paren)
add ( n , advance ( ) )
n . expr = add ( n , resetNoMethod ( parseExp ) )
add ( n , expect ( ")" , "to close parenthesized expression" ) )
return n
elseif kind == "error" then
local n = _G.setmetatable({ kind =  "errorExpr" }, cst.ErrorExpr)
add ( n , advance ( ) )
return n
end
errAt ( cur ( ) , ("expression expected; found %s") : format ( found ( cur ( ) ) ) , "NUPP1004" )
local n = _G.setmetatable({ kind =  "errorExpr" }, cst.ErrorExpr)
add ( n , missing ( "expr" ) )

return n
end


parseSuffixedexp = function ( ) 
local e = parsePrimaryexp ( )
while true do
local kind = cur ( ) . kind
if kind == "." then
local n = _G.setmetatable({ kind =  "dotIndex" }, cst.DotIndex)
n . obj = add ( n , e )
add ( n , advance ( ) )
n . name = add ( n , expectName ( "after '.'" ) )
e = n



local member = n . name
local base = n . obj
local baseTok = base and base . kind == "name" and base . token
if cur ( ) . kind == "<"
and member
and baseTok
and (
FFI_INTRINSIC [ member . text ] and baseTok . text == "ffi"
or member . text == "adopt" and baseTok . text == "nupp"
)
then
add ( n , advance ( ) ) . generic = true
local argument = add ( n , parseType ( ) )
if member . text == "adopt" and baseTok . text == "nupp" then
n . ownershipTypeArg = argument
else
n . ffiTypeArg = argument
end
add ( n , expectGenericClose ( "to close a type argument" ) ) . generic = true
end
elseif kind == "<" and opensCallTypeArguments ( i ) then
local n = _G.setmetatable({ kind =  "call" }, cst.Call)
n . obj = add ( n , e )
add ( n , advance ( ) ) . generic = true
n . typeArgs = { }
repeat
n . typeArgs [ # n . typeArgs + 1 ] = add ( n , parseType ( ) )
if cur ( ) . kind ~= "," then
do break end
end
add ( n , advance ( ) ) . typeSeparator = true
until false
add ( n , expectGenericClose ( "to close call type arguments" ) ) . generic = true
local args = parseCallargs ( false )
if not args then



errAt ( cur ( ) , "function arguments expected" )
add ( n , missing ( "args" ) )
return n
end
n . args = add ( n , args )
e = n
elseif kind == "[" then
local n = _G.setmetatable({ kind =  "bracketIndex" }, cst.BracketIndex)
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
"a safe method call cannot appear in the second arm of a ternary; parenthesize it"
)
end
e = parseMethodCall ( e , qtok )
elseif nk == "name" then
local n = _G.setmetatable({ kind =  "safeIndex" }, cst.SafeIndex)
n . obj = add ( n , e )
add ( n , qtok )
n . name = add ( n , advance ( ) )
e = n
elseif nk == "[" then
local n = _G.setmetatable({ kind =  "safeBracket" }, cst.SafeBracket)
n . obj = add ( n , e )
add ( n , qtok )
add ( n , advance ( ) )
n . expr = add ( n , resetNoMethod ( parseExp ) )
add ( n , expect ( "]" , "to close index" ) )
e = n
else
local args = parseCallargs ( )
if args then
local n = _G.setmetatable({ kind =  "safeCall" }, cst.SafeCall)
n . obj = add ( n , e )
add ( n , qtok )
n . args = add ( n , args )
e = n
else
errAt ( cur ( ) , "name, index, or arguments expected after '?.'" )
local n = _G.setmetatable({ kind =  "errorExpr" }, cst.ErrorExpr)
n . obj = add ( n , e )
add ( n , qtok )
e = n
end
end
else
local comptimeIntrinsic = cst . comptimeTypeIntrinsicSpelling ( e )
local args = parseCallargs ( comptimeIntrinsic ~= nil )
if args then
local n = _G.setmetatable({ kind =  "call" }, cst.Call)
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
local n = _G.setmetatable({ fields =  { } ,  kind =  "tableExpr" }, cst.TableExpr)
add ( n , expect ( "{" ) )
while cur ( ) . kind ~= "}" and cur ( ) . kind ~= "eof" do
local f
if cur ( ) . kind == "[" then
f = _G.setmetatable({ kind =  "fieldBracket" }, cst.FieldBracket)
add ( f , advance ( ) )
f . key = add ( f , resetNoMethod ( parseExp ) )
add ( f , expect ( "]" , "to close field key" ) )
add ( f , expect ( "=" , "in table field" ) )
f . value = add ( f , resetNoMethod ( parseExp ) )
elseif cur ( ) . kind == "name"
and cur ( ) . text == "const"
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "name"
and tokens [ i + 2 ]
and tokens [ i + 2 ] . kind == "="
then
f = _G.setmetatable({ kind =  "fieldNamed" }, cst.FieldNamed)
f . isConst = true
add ( f , advance ( ) )
f . name = add ( f , advance ( ) )
add ( f , advance ( ) )
f . value = add ( f , resetNoMethod ( parseExp ) )
elseif cur ( ) . kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "=" then
f = _G.setmetatable({ kind =  "fieldNamed" }, cst.FieldNamed)
f . name = add ( f , advance ( ) )
add ( f , advance ( ) )
f . value = add ( f , resetNoMethod ( parseExp ) )
elseif atExprStart ( ) then
f = _G.setmetatable({ kind =  "fieldItem" }, cst.FieldItem)
f . value = add ( f , resetNoMethod ( parseExp ) )
else
errAt ( cur ( ) , "unexpected symbol in table constructor" )
f = _G.setmetatable({ kind =  "errorExpr" }, cst.ErrorExpr)
add ( f , advance ( ) )
end
n . fields [ # n . fields + 1 ] = add ( n , f )
if cur ( ) . kind == "," or cur ( ) . kind == ";" then
add ( n , advance ( ) )
elseif cur ( ) . kind ~= "}" then
do break end
end
end
add ( n , expect ( "}" , "to close table constructor" ) )

return n
end






local function parseShortfn ( ) 
local n = _G.setmetatable({ params =  { } ,  kind =  "shortfn" }, cst.Shortfn)
if atEmptyPipes ( ) then



add ( n , advance ( ) )
elseif cur ( ) . kind == "|" then
local open = add ( n , advance ( ) )
open . _shortfnOpen = true
if cur ( ) . kind ~= "|" then
repeat
local p = _G.setmetatable({ kind =  "param" }, cst.Param)
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
do break end
end
add ( n , advance ( ) )
until false
end
local close = add ( n , expect ( "|" , "to close short function parameters" ) )
close . _shortfnClose = true
else
local p = _G.setmetatable({ kind =  "param" }, cst.Param)
p . name = add ( p , expectName ( "in short function" ) )
n . params [ 1 ] = add ( n , p )
end
add ( n , expect ( "->" , "in short function" ) )
if cur ( ) . kind == "do" then
add ( n , advance ( ) )
n . body = add ( n , parseFunctionBlock ( ) )
add ( n , expect ( "end" , "to close short function" ) )
else
local savedLoopDepth , savedValueBlockDepth = loopDepth , valueBlockDepth
local savedRepeatCondition = repeatConditionDepth
loopDepth , valueBlockDepth , repeatConditionDepth = 0 , 0 , 0
n . expr = add ( n , parseExp ( ) )
loopDepth , valueBlockDepth = savedLoopDepth , savedValueBlockDepth
repeatConditionDepth = savedRepeatCondition
end

return n
end




parseIstring = function ( ) 
local n = _G.setmetatable({ parts =  { } ,  kind =  "istring" }, cst.Istring)
add ( n , advance ( ) )
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






local function atSwitchexp ( ) 
local tok = cur ( )
if tok . kind ~= "name" or tok . text ~= "switch" or not tokens [ i + 1 ] then
return false
end
local savedI , savedErrors = i , # errors
local savedNoMethod , savedNoArrow = noMethod , noArrow
local savedGenericClose , savedGenericHalf = genericCloseHalfAt , genericCloseHalf
i = i + 1
parseExp ( )
local yes = cur ( ) . kind == "do"
i = savedI
noMethod , noArrow = savedNoMethod , savedNoArrow
genericCloseHalfAt , genericCloseHalf = savedGenericClose , savedGenericHalf
while # errors > savedErrors do
errors [ # errors ] = nil
end

return yes
end

local function parseDoexp ( ) 
local n = _G.setmetatable({ kind =  "doExpr" }, cst.DoExpr)
n . doTok = add ( n , advance ( ) )
local savedNoMethod = noMethod
noMethod = 0
valueBlockDepth = valueBlockDepth + 1
n . body = add ( n , parseBlock ( ) )
valueBlockDepth = valueBlockDepth - 1
noMethod = savedNoMethod
n . endTok = add ( n , expect ( "end" , "to close do expression" ) )

return n
end

local function parseSwitchResult ( n ) 
add ( n , expect ( "->" , "in switch arm" ) )
n . expr = add ( n , parseExp ( ) )
end


local function parseSwitchexp ( ) 
local n = _G.setmetatable({ kind =  "switchExpr" ,  cases =  { } }, cst.SwitchExpr)
n . switchTok = add ( n , advance ( ) )
n . switchTok . contextualOp = true
n . selector = add ( n , parseExp ( ) )
n . doTok = add ( n , expect ( "do" , "after switch selector" ) )
while cur ( ) . kind == "name" and cur ( ) . text == "case" do
local arm = _G.setmetatable({ patternKind =  "static" ,  kind =  "switchCase" ,  values =  { } ,  fields =  { } }, cst.SwitchCase)
add ( arm , advance ( ) ) . contextualOp = true
if cur ( ) . kind == "name" and cur ( ) . text == "is" then
arm . patternKind = "type"
add ( arm , advance ( ) ) . contextualOp = true
arm . type = add ( arm , parseType ( ) )
if cur ( ) . kind == "name" and cur ( ) . text == "as" then
add ( arm , advance ( ) ) . contextualOp = true
arm . binding = add ( arm , expectName ( "after 'as' in switch case" ) )
end
if cur ( ) . kind == "{" then
add ( arm , advance ( ) )
if cur ( ) . kind ~= "}" then
repeat
local field = _G.setmetatable({ kind =  "switchField" }, cst.SwitchField)
field . name = add ( field , expectName ( "in switch destructuring" ) )
if cur ( ) . kind == "name" and cur ( ) . text == "as" then
add ( field , advance ( ) ) . contextualOp = true
field . alias = add ( field , expectName ( "after 'as' in switch field" ) )
end
arm . fields [ # arm . fields + 1 ] = add ( arm , field )
if cur ( ) . kind ~= "," then
do break end
end
add ( arm , advance ( ) )
until false
end
add ( arm , expect ( "}" , "to close switch destructuring" ) )
end
else
arm . patternKind = "static"
repeat
arm . values [ # arm . values + 1 ] = add ( arm , parseExp ( ) )
if cur ( ) . kind ~= "," then
do break end
end
add ( arm , advance ( ) )
until false
end




if cur ( ) . kind == "name" and cur ( ) . text == "where" then
local guard = _G.setmetatable({ kind =  "whereClause" }, cst.WhereClause)
add ( guard , advance ( ) ) . contextualOp = true


noArrow = noArrow + 1
guard . expr = add ( guard , parseExp ( ) )
noArrow = noArrow - 1
arm . guard = add ( arm , guard )
end
parseSwitchResult ( arm )
n . cases [ # n . cases + 1 ] = add ( n , arm )
end
if cur ( ) . kind == "else" then
local arm = _G.setmetatable({ kind =  "switchElse" }, cst.SwitchElse)
add ( arm , advance ( ) )
parseSwitchResult ( arm )
n . elseCase = add ( n , arm )
end
n . endTok = add ( n , expect ( "end" , "to close switch" ) )

return n
end








local function parseNewexp ( ) 
local n = _G.setmetatable({ kind =  "newExpr" }, cst.NewExpr)
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

local function sourceText ( node ) 
local first , last = cst . firstToken ( node ) , cst . lastToken ( node )
if not first or not last then
return ""
end

return source : sub ( first . offset , last . offset + # last . text - 1 )
end

parseOwnership = function ( prefix ) 
local operation = cur ( ) . text
local n = _G.setmetatable({ kind =  "errorExpr" }, cst.ErrorExpr)
if prefix then
add ( n , prefix ) . contextualOp = true
end
local operationToken = advance ( )
add ( n , operationToken ) . contextualOp = true
local operand = add ( n , parseExp ( ) )
local replacement = nil
if operation == "adopt" and operand . kind == "castExpr" and operand . expr and operand . type then
replacement = (
prefix and "@unsafe " or ""
) .. "nupp.adopt<" .. sourceText ( operand . type ) .. ">(" .. sourceText ( operand . expr ) .. ")"
elseif operation == "release" then
replacement = ( prefix and "@unsafe " or "" ) .. "nupp.release(" .. sourceText ( operand ) .. ")"
end
local start = prefix or operationToken
local last = cst . lastToken ( operand )
local fixes = nil
if replacement and last then
fixes = {
{
title = "use the ownership intrinsic call" ,
edits = {
{
offset = start . offset ,
length = last . offset + # last . text - start . offset ,
newText = replacement ,
}
} ,
}
}
end
errAt (
operationToken ,
"ownership " .. operation .. " uses a nupp call" ,
"NUPP1005" ,
operation == "adopt" and "write @unsafe nupp.adopt<Owner>(raw)" or "write @unsafe nupp.release(owner)" ,
fixes
)

return n
end


local function parseSimpleexp ( ) 
local kind = cur ( ) . kind
if kind == "@" then
local application = parseAnnotationApplication ( _G.setmetatable({ kind =  "annotationApply" }, cst.AnnotationApply) )
application . expressionAttachment = true
local operand , permissionOperand
if application . name . text == "unsafe"
and cur ( ) . kind == "name"
and ( cur ( ) . text == "adopt" or cur ( ) . text == "release" )
then
operand = parseOwnership ( nil )
else
operand , permissionOperand = parseAnnotatedOperand ( )
end
operand . expressionPermissionOperand = permissionOperand ~= operand and permissionOperand or nil
operand . expressionAnnotations = operand . expressionAnnotations or { }
table . insert ( operand . expressionAnnotations , 1 , application )
table . insert ( operand , 1 , application )
return operand
elseif kind == "do" then
return parseDoexp ( )
elseif atSwitchexp ( ) then
return parseSwitchexp ( )
elseif kind == "name"
and cur ( ) . text == "dedent"
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "string"
and tokens [ i + 1 ] . text : sub ( 1 , 1 ) == "["
then
local n = _G.setmetatable({ kind =  "dedentString" }, cst.DedentString)
n . keyword = add ( n , advance ( ) )
n . token = add ( n , advance ( ) )
return n
elseif kind == "number" or kind == "string" then
local n
if kind == "number" then
n = _G.setmetatable({ kind =  "number" }, cst.NumberLit)
else
n = _G.setmetatable({ kind =  "string" }, cst.StringLit)
end
n . token = add ( n , advance ( ) )
return n
elseif kind == "|"
or atEmptyPipes ( )
or ( kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "->" and noArrow == 0 )
then
return parseShortfn ( )
elseif kind == "istringOpen" then
return parseIstring ( )
elseif kind == "nil" or kind == "true" or kind == "false" or kind == "..." then
local n
if kind == "..." then
n = _G.setmetatable({ kind =  "vararg" }, cst.Vararg)
elseif kind == "nil" then
n = _G.setmetatable({ kind =  "nilExpr" }, cst.NilExpr)
elseif kind == "true" then
n = _G.setmetatable({ kind =  "trueExpr" }, cst.TrueExpr)
else
n = _G.setmetatable({ kind =  "falseExpr" }, cst.FalseExpr)
end
n . token = add ( n , advance ( ) )
return n
elseif kind == "function" then
local n = _G.setmetatable({ kind =  "funcExpr" }, cst.FuncExpr)
add ( n , advance ( ) )
n . body = add ( n , parseFuncbody ( ) )
return n
elseif kind == "{" then
return parseTableconstructor ( )
elseif atNewexp ( ) then
return parseNewexp ( )
elseif atComptimeexp ( ) then
local n = _G.setmetatable({ kind =  "comptimeExpr" }, cst.ComptimeExpr)
add ( n , advance ( ) ) . contextualOp = true
add ( n , advance ( ) )
n . body = add ( n , parseBlock ( ) )
add ( n , expect ( "end" , "to close 'comptime do'" ) )
return n
else
return parseSuffixedexp ( )
end
end











local function orExitWord ( ) 
local op = cur ( )
if op . kind ~= "or" then
return nil
end
local word = tokens [ i + 1 ]
if not word or word . line ~= op . line then
return nil
end
if word . kind == "return" or word . kind == "break" then
return word . kind
end
if word . kind == "name" and word . text == "continue" then
return "continue"
end

return nil
end


local function contextualOp ( prevLine ) 
local tok = cur ( )
if tok . kind == "name" and tok . line == prevLine and ( tok . text == "as" or tok . text == "is" ) then
return tok . text
end

return nil
end


parseAnnotatedOperand = function ( ) 
local operand
if UNOPS [ cur ( ) . kind ] then
local n = _G.setmetatable({ kind =  "unop" }, cst.Unop)
n . op = add ( n , advance ( ) )
n . operand = add ( n , parseBinexp ( 12 ) )
operand = n
else
operand = parseSimpleexp ( )
end


local prefix = operand
while prefix . kind == "unop" do
prefix = prefix . operand
end
if prefix . kind == "binop" then
while prefix . kind == "binop" do
prefix = ( prefix ) . lhs
end
return operand , prefix
end
while contextualOp ( tokens [ i - 1 ] and tokens [ i - 1 ] . line or cur ( ) . line ) == "as" do
local n = _G.setmetatable({ kind =  "castExpr" }, cst.CastExpr)
n . expr = add ( n , operand )
add ( n , advance ( ) ) . contextualOp = true
n . type = add ( n , parseType ( ) )
operand = n
end

return operand , operand
end




local AFTER_EXIT_REFUSED = {
[ "@" ] = true ,
[ "number" ] = true ,
[ "string" ] = true ,
[ "nil" ] = true ,
[ "true" ] = true ,
[ "false" ] = true ,
[ "..." ] = true ,
[ "function" ] = true ,
[ "{" ] = true ,
[ "[" ] = true ,
[ "name" ] = true ,
[ "(" ] = true ,
[ "istringOpen" ] = true ,
[ "not" ] = true ,
[ "#" ] = true ,
[ "-" ] = true ,
[ "~" ] = true ,
}


local function parseOrExit ( operand , exitKind ) 
local n = _G.setmetatable({ kind =  "orExitExpr" ,  exitKind =  exitKind }, cst.OrExitExpr)
n . operand = add ( n , operand )
n . orToken = add ( n , advance ( ) )
n . exitToken = add ( n , advance ( ) )
if exitKind ~= "return" and loopDepth == 0 then
errAt (
n . exitToken ,
"no loop to " .. exitKind ,
"NUPP1005" ,
"a loop exit does not cross a function boundary; use `or return` to leave the function"
)
elseif exitKind == "continue" and repeatConditionDepth > 0 then
errAt (
n . exitToken ,
"a repeat condition is what `continue` jumps to, so it has no target here" ,
"NUPP1005" ,
"use `or break`, or move the test into the body"
)
end
if operand . kind == "orExitExpr" then
errAt (
n . exitToken ,
"one exit suffix applies to an expression" ,
"NUPP1005" ,
"remove the second `or " .. exitKind .. "`"
)
end
local following = cur ( )
if AFTER_EXIT_REFUSED [ following . kind ] and following . line == n . exitToken . line then
errAt (
following ,
("'%s' takes no value") : format ( exitKind ) ,
"NUPP1005" ,
exitKind == "return" and "write the explicit conditional when the failure path needs its own results"
or "the suffix names no label"
)
end

return n
end


local function parseBinexpNested ( limit ) 
local left
if UNOPS [ cur ( ) . kind ] then
local n = _G.setmetatable({ kind =  "unop" }, cst.Unop)
n . op = add ( n , advance ( ) )
n . operand = add ( n , parseBinexp ( 12 ) )
left = n
else
left = parseSimpleexp ( )
end
while true do
local prevLine = tokens [ i - 1 ] and tokens [ i - 1 ] . line or cur ( ) . line
local ctx = contextualOp ( prevLine )
if ctx == "as" and 11 > limit then
local n = _G.setmetatable({ kind =  "castExpr" }, cst.CastExpr)
n . expr = add ( n , left )
add ( n , advance ( ) ) . contextualOp = true
n . type = add ( n , parseType ( ) )
left = n
elseif ctx == "is" and 3 > limit then
local n = _G.setmetatable({ kind =  "isExpr" }, cst.IsExpr)
n . expr = add ( n , left )
add ( n , advance ( ) ) . contextualOp = true
n . type = add ( n , parseType ( ) )
left = n
else
local pri = BINPRI [ cur ( ) . kind ]
if not ( pri and pri [ 1 ] > limit ) then
do break end
end
local exitKind = orExitWord ( )
if exitKind then
left = parseOrExit ( left , exitKind )
else
local n = _G.setmetatable({ kind =  "binop" }, cst.Binop)
n . lhs = add ( n , left )
n . op = add ( n , advance ( ) )
n . rhs = add ( n , parseBinexp ( pri [ 2 ] ) )
left = n
end
end
end

return left
end

parseBinexp = function ( limit ) 
nesting = nesting + 1
if nesting > 1000 then
tooDeepAt = cur ( )
error ( TOO_DEEP , 0 )
end
local n = parseBinexpNested ( limit )
nesting = nesting - 1

return n
end


parseExp = function ( ) 
local e = parseBinexp ( 0 )
if cur ( ) . kind == "?" then
local n = _G.setmetatable({ kind =  "ternary" }, cst.Ternary)
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
local n = _G.setmetatable({ kind =  "captureClause" ,  names =  { } }, cst.CaptureClause)
n . mode = add ( n , advance ( ) )
n . mode . contextualOp = true
add ( n , expect ( "(" , "to open closure captures" ) )
if cur ( ) . kind ~= ")" then
repeat
n . names [ # n . names + 1 ] = add ( n , expectName ( "as closure capture" ) )
if cur ( ) . kind ~= "," then
do break end
end
add ( n , advance ( ) )
until false
end
add ( n , expect ( ")" , "to close closure captures" ) )

return n
end


parseFuncbody = function ( ) 
local n = _G.setmetatable({ params =  { } ,  kind =  "funcbody" }, cst.Funcbody)
parseGenerics ( n )
add ( n , expect ( "(" , "to begin parameter list" ) )
if cur ( ) . kind ~= ")" then
repeat
local p = _G.setmetatable({ kind =  "param" }, cst.Param)
local isFunctionConst = cur ( ) . kind == "name"
and cur ( ) . text == "const"
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "name"
and tokens [ i + 2 ]
and tokens [ i + 2 ] . kind == ":"
and tokens [ i + 3 ]
and tokens [ i + 3 ] . kind == "function"
if isFunctionConst then
p . constTok = add ( p , advance ( ) )
p . constTok . contextualOp = true
p . name = add ( p , advance ( ) )
annotationColon ( p , "after const function parameter" )
p . constDomainTok = add ( p , advance ( ) )
n . params [ # n . params + 1 ] = add ( n , p )
else
if cur ( ) . kind == "name"
and PARAM_MODES [ cur ( ) . text ]
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "..."
then
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
if cur ( ) . kind == "name"
and (
( tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "..." )
or ( cur ( ) . text == "unpackof" and startsType ( tokens [ i + 1 ] ) )
)
then
p . type = add ( p , parseTypePack ( ) )
else
p . type = add ( p , parseType ( ) )
end
end
n . params [ # n . params + 1 ] = add ( n , p )
if cur ( ) . kind == "," then
errAt ( cur ( ) , "'...' must be the last parameter" )
end
do break end
end
if cur ( ) . kind == "name"
and PARAM_MODES [ cur ( ) . text ]
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "name"
then
p . modeTok = add ( p , advance ( ) )
end
p . name = add ( p , expectName ( "as parameter" ) )
if cur ( ) . kind == ":" then
annotationColon ( p , "in parameter annotation" )
p . type = add ( p , parseType ( ) )
end
n . params [ # n . params + 1 ] = add ( n , p )
end
if cur ( ) . kind ~= "," then
do break end
end
add ( n , advance ( ) )
until false
end
add ( n , expect ( ")" , "to close parameter list" ) )
if cur ( ) . kind == ":" then

annotationColon ( n , "before return types" )
n . captureBorrowsCandidate = attachReturnPack ( n , parseTypePack ( true ) )
end
while cur ( ) . kind == "name"
and ( cur ( ) . text == "takes" or cur ( ) . text == "borrows" )
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "(" do
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
n . body = add ( n , parseFunctionBlock ( ) )
add ( n , expect ( "end" , "to close function" ) )

return n
end







local parseTypedecl




local function parseBorrowRelation ( result ) 









if cur ( ) . kind == "name"
and cur ( ) . text == "borrows"
and tokens [ i + 1 ]
and ( tokens [ i + 1 ] . kind == "name" or tokens [ i + 1 ] . kind == "(" )
then
local n = _G.setmetatable({ kind =  "tborrows" }, cst.Tborrows)
n . type = add ( n , result )
add ( n , advance ( ) )
n . params = { }
add ( n , expect ( "(" , "to open borrow sources" ) )
repeat
local param = add ( n , expectName ( "as borrow source" ) )
n . params [ # n . params + 1 ] = param
if cur ( ) . kind ~= "," then
do break end
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
local n = _G.setmetatable({ kind =  "tpredicate" }, cst.Tpredicate)
n . param = add ( n , advance ( ) )
add ( n , advance ( ) )
n . type = add ( n , parseType ( nil , stopAtFunctionMember ) )
return n
end
local result = parseType ( nil , stopAtFunctionMember )

if cur ( ) . kind == "name" and cur ( ) . text == "preserves" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "name" then
local n = _G.setmetatable({ kind =  "tpreserves" }, cst.Tpreserves)
n . type = add ( n , result )
add ( n , advance ( ) )
n . param = add ( n , advance ( ) )
return n
end

return parseBorrowRelation ( result )
end










parseAnnotationApplication = function ( n , typePosition ) 
add ( n , expect ( "@" ) )
local negated = cur ( ) . text == "!" and add ( n , advance ( ) ) or nil
n . name = add ( n , expectName ( "after '@'" ) )
if negated then
errAt ( n . name , "@!" .. n . name . text .. " is not supported; annotate one statement or expression" , "NUPP2112" )
end
if typePosition and ( n . name . text == "nosuspend" or n . name . text == "sendable" or n . name . text == "comptime" ) then
return n
elseif n . name . text == "unsafe" then
if cur ( ) . kind == "("
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "name"
and tokens [ i + 2 ]
and tokens [ i + 2 ] . kind == "="
then
errAt ( n . name , "@unsafe takes no configuration; parentheses enclose its operand" , "NUPP2112" )
end
return n
elseif cur ( ) . kind ~= "(" then
return n
end

n . open = add ( n , advance ( ) )
n . annotationArgs = { }
if cur ( ) . kind ~= ")" then
repeat
local arg = _G.setmetatable({ kind =  "annotationArg" }, cst.AnnotationArg)
if cur ( ) . kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "=" then
arg . name = add ( arg , advance ( ) )
arg . eq = add ( arg , advance ( ) )
end
arg . expr = add ( arg , resetNoMethod ( parseExp ) )
n . annotationArgs [ # n . annotationArgs + 1 ] = add ( n , arg )
if cur ( ) . kind ~= "," then
do break end
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
local n = _G.setmetatable({ kind =  "associatedDecl" }, cst.AssociatedDecl)
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
while cur ( ) . kind ~= "end" and cur ( ) . kind ~= "eof" do
local attached = { }
while cur ( ) . kind == "@" do
local application = parseAnnotationApplication ( _G.setmetatable({ kind =  "annotationApply" }, cst.AnnotationApply) )
attached [ # attached + 1 ] = add ( n , application )
end
local e
if startsAssociatedType ( i ) then
e = parseAssociatedType ( )
elseif startsTypedecl ( i ) then
e = parseTypedecl ( nil , "nested" )
elseif cur ( ) . kind == "function" then
e = _G.setmetatable({ kind =  "inlineMethod" }, cst.InlineMethod)
add ( e , advance ( ) )
e . name = add ( e , expectName ( "after 'function' in declaration" ) )
e . body = add ( e , parseFuncbody ( ) )
elseif cur ( ) . kind == "name"
and cur ( ) . text == "constructor"
and tokens [ i + 1 ]
and ( tokens [ i + 1 ] . kind == "(" or startsShortfn ( i + 1 ) )
then


e = _G.setmetatable({ kind =  "constructorDecl" }, cst.ConstructorDecl)
add ( e , advance ( ) )




if startsShortfn ( i ) then
e . body = add ( e , parseShortfn ( ) )
else
e . body = add ( e , parseFuncbody ( ) )
end
elseif cur ( ) . kind == "name"
and cur ( ) . text == "satisfies"
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind ~= ":"
then


e = _G.setmetatable({ kind =  "satisfiesDecl" }, cst.SatisfiesDecl)
add ( e , advance ( ) )




if startsShortfn ( i ) then
e . body = add ( e , parseShortfn ( ) )
else
e . body = add ( e , parseFuncbody ( ) )
end
elseif cur ( ) . kind == "name"
and cur ( ) . text == "metamethod"
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "name"
then
e = _G.setmetatable({ kind =  "metamethodDecl" }, cst.MetamethodDecl)
add ( e , advance ( ) )
e . name = add ( e , expectName ( "after 'metamethod'" ) )
annotationColon ( e , "in metamethod declaration" )
e . type = add ( e , parseType ( ) )
elseif cur ( ) . kind == "{" then


e = _G.setmetatable({ kind =  "arrayPart" }, cst.ArrayPart)
e . type = add ( e , parseType ( ) )
elseif cur ( ) . kind == "[" then
e = _G.setmetatable({ kind =  "indexerDecl" }, cst.IndexerDecl)
add ( e , expect ( "[" , "to open indexer key type" ) )
e . key = add ( e , parseType ( ) )
add ( e , expect ( "]" , "to close indexer key type" ) )
annotationColon ( e , "in indexer declaration" )
e . value = add ( e , parseType ( ) )
elseif cur ( ) . kind == "name" then
e = _G.setmetatable({ kind =  "fieldDecl" }, cst.FieldDecl)
e . name = add ( e , advance ( ) )
if cur ( ) . kind == "," then


errAt (
cur ( ) ,
"each field needs its own explicit type annotation (grouped fields are not supported)"
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
e = _G.setmetatable({ kind =  "errorStmt" }, cst.ErrorStmt)
add ( e , advance ( ) )
end
e . annotations = attached
n . entries [ # n . entries + 1 ] = add ( n , e )
end
add ( n , expect ( "end" , "to close declaration" ) )
end





local function parseDeclName ( n , what ) 
local segment = add ( n , expectName ( what ) )
while cur ( ) . kind == "." do
add ( n , advance ( ) )
n . qualifiers = n . qualifiers or { }
n . qualifiers [ # n . qualifiers + 1 ] = segment
segment = add ( n , expectName ( "after '.' in declaration name" ) )
end
n . name = segment
end


parseTypedecl = function ( modifierTok , visibility ) 
local sealedTok = nil
if cur ( ) . kind == "name" and cur ( ) . text == "sealed" and tokens [ i + 1 ] and TYPEDECL_KW [ tokens [ i + 1 ] . text ] then
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
local n = introduce ( _G.setmetatable({ kind =  "typeAlias" }, cst.TypeAlias) )
parseDeclName ( n , "after '" .. which .. "'" )
parseGenerics ( n )
add ( n , expect ( "=" , "in " .. which .. " declaration" ) )
n . value = add ( n , parseType ( ) )
return n
else
local n = introduce ( _G.setmetatable({ entries =  { } ,  kind =  "recordDecl" }, cst.RecordDecl) )
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
do break end
end
add ( n , advance ( ) )
until false
end
if cur ( ) . kind == "name" and cur ( ) . text == "where" then
local where = _G.setmetatable({ kind =  "whereClause" }, cst.WhereClause)
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
local n = _G.setmetatable({ params =  { } ,  kind =  "cdefFunc" }, cst.CdefFunc)
add ( n , cdefTok )
add ( n , advance ( ) )
n . name = add ( n , expectName ( "after 'cdef function'" ) )
add ( n , expect ( "(" , "in cdef function" ) )
if cur ( ) . kind ~= ")" then
repeat
local p = _G.setmetatable({ kind =  "param" }, cst.Param)
if cur ( ) . kind == "..." then
add ( p , advance ( ) )
n . varargs = true
n . params [ # n . params + 1 ] = add ( n , p )
do break end
end
if cur ( ) . kind == "name"
and ( PARAM_MODES [ cur ( ) . text ] or cur ( ) . text == "out" )
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "name"
then
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
do break end
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
local n = _G.setmetatable({ entries =  { } ,  kind =  "cdefStruct" }, cst.CdefStruct)
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

if kind == "name" and cur ( ) . text == "module" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "name" then
local n = _G.setmetatable({ kind =  "moduleStmt" ,  names =  { } }, cst.ModuleStmt)
n . keyword = add ( n , advance ( ) )
n . keyword . contextualOp = true
n . names [ 1 ] = add ( n , advance ( ) )
while cur ( ) . kind == "." do
add ( n , advance ( ) )
n . names [ # n . names + 1 ] = add ( n , expectName ( "after '.' in module name" ) )
end
hasDeclaredModule = true
return n
end

if kind == "name"
and cur ( ) . text == "export"
and hasDeclaredModule
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "="
then
local n = _G.setmetatable({ kind =  "exportStmt" }, cst.ExportStmt)
n . keyword = add ( n , advance ( ) )
n . keyword . contextualOp = true
n . equal = add ( n , advance ( ) )
n . value = add ( n , parseExp ( ) )
return n
end

if kind == "name" and cur ( ) . text == "export" and startsExport ( i ) then
local n = _G.setmetatable({ kind =  "exportStmt" }, cst.ExportStmt)
n . keyword = add ( n , advance ( ) )
n . keyword . contextualOp = true
n . stat = add ( n , parseStatement ( ) )
return n
end

if kind == "name"
and cur ( ) . text == "cdef"
and tokens [ i + 1 ]
and (
tokens [ i + 1 ] . kind == "function"
or (
tokens [ i + 1 ] . kind == "name"
and ( tokens [ i + 1 ] . text == "struct" or tokens [ i + 1 ] . text == "union" )
and tokens [ i + 2 ]
and tokens [ i + 2 ] . kind == "name"
)
)
then
return parseCdef ( )
end

if kind == "@" then
local n = _G.setmetatable({ kind =  "pragmaStmt" }, cst.PragmaStmt)
local application = parseAnnotationApplication ( n )
n . stat = add ( n , parseStatement ( ) )
if application . name and application . name . text == "comptime" then
local target = n . stat
while target and target . kind == "exportStmt" and target . stat do
target = target . stat
end
if target
and ( target . kind == "typeAlias" or target . kind == "localFuncStmt" or target . kind == "funcStmt" )
then
target . comptimeTok = application . name
if target . kind == "typeAlias" then
target . comptimeOnly = true
end
end
end
return n
end

if kind == ";" then
local n = _G.setmetatable({ kind =  "emptyStmt" }, cst.EmptyStmt)
add ( n , advance ( ) )
return n

elseif startsWith ( i ) then
local n = _G.setmetatable({ bindings =  { } ,  kind =  "withStmt" }, cst.WithStmt)
n . withTok = add ( n , advance ( ) )

local function binding ( ) 
local b = _G.setmetatable({ kind =  "withBinding" }, cst.WithBinding)
b . name = add ( b , expectName ( "in 'with' binding" ) )
if cur ( ) . kind == ":" then
annotationColon ( b , "in 'with' binding" )
b . type = add ( b , parseType ( ) )
end
b . eq = add ( b , expect ( "=" , "in 'with' binding" ) )
b . expr = add ( b , parseExp ( ) )
n . bindings [ # n . bindings + 1 ] = add ( n , b )
end

binding ( )
while cur ( ) . kind == "," do
add ( n , advance ( ) )
binding ( )
end
n . doTok = add ( n , expect ( "do" , "after 'with' acquisitions" ) )
n . body = add ( n , parseBlock ( ) )
n . endTok = add ( n , expect ( "end" , "to close 'with'" ) )
return n

elseif kind == "if" then
local n = _G.setmetatable({ clauses =  { } ,  kind =  "ifStmt" }, cst.IfStmt)




local function bindingClause ( clause ) 
if cur ( ) . kind == "name" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind == "=" then
clause . binding = add ( clause , advance ( ) )
clause . eq = add ( clause , advance ( ) )
end
clause . cond = add ( clause , parseExp ( ) )
end

local clause = _G.setmetatable({ kind =  "ifClause" }, cst.IfClause)
add ( clause , advance ( ) )
bindingClause ( clause )
add ( clause , expect ( "then" , "after condition" ) )
clause . body = add ( clause , parseBlock ( ) )
n . clauses [ 1 ] = add ( n , clause )
while cur ( ) . kind == "elseif" do
clause = _G.setmetatable({ kind =  "elseifClause" }, cst.ElseifClause)
add ( clause , advance ( ) )
bindingClause ( clause )
add ( clause , expect ( "then" , "after condition" ) )
clause . body = add ( clause , parseBlock ( ) )
n . clauses [ # n . clauses + 1 ] = add ( n , clause )
end
if cur ( ) . kind == "else" then
clause = _G.setmetatable({ kind =  "elseClause" }, cst.ElseClause)
add ( clause , advance ( ) )
clause . body = add ( clause , parseBlock ( ) )
n . elseClause = add ( n , clause )
end
add ( n , expect ( "end" , "to close 'if'" ) )
return n

elseif kind == "while" then
local n = _G.setmetatable({ kind =  "whileStmt" }, cst.WhileStmt)
add ( n , advance ( ) )
n . cond = add ( n , parseExp ( ) )
add ( n , expect ( "do" , "after condition" ) )
loopDepth = loopDepth + 1
n . body = add ( n , parseBlock ( ) )
loopDepth = loopDepth - 1
add ( n , expect ( "end" , "to close 'while'" ) )
return n

elseif kind == "do" then
local n = _G.setmetatable({ kind =  "doStmt" }, cst.DoStmt)
add ( n , advance ( ) )
n . body = add ( n , parseBlock ( ) )
add ( n , expect ( "end" , "to close 'do'" ) )
return n

elseif kind == "for" then
local fortok = advance ( )
local name1 = expectName ( "after 'for'" )
if cur ( ) . kind == "=" then
local n = _G.setmetatable({ kind =  "fornumStmt" }, cst.FornumStmt)
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
local n = _G.setmetatable({ names =  { } ,  exprs =  { } ,  kind =  "forinStmt" }, cst.ForinStmt)
add ( n , fortok )
n . names [ 1 ] = add ( n , name1 )
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
local n = _G.setmetatable({ kind =  "repeatStmt" }, cst.RepeatStmt)
add ( n , advance ( ) )
loopDepth = loopDepth + 1
n . body = add ( n , parseBlock ( ) )
loopDepth = loopDepth - 1
add ( n , expect ( "until" , "to close 'repeat'" ) )
repeatConditionDepth = repeatConditionDepth + 1
n . cond = add ( n , parseExp ( ) )
repeatConditionDepth = repeatConditionDepth - 1
local skipping , reading = cst . skippedUntilLocal ( n )
if skipping ~= nil then
local name = ( reading ) . text
errAt (
cst . firstToken ( skipping ) ,
("continue skips local '%s', which the until condition reads") : format ( name ) ,
nil ,
("declare '%s' before the first continue, or test the condition without it") : format ( name )
)
end
return n

elseif kind == "name"
and cur ( ) . text == "handle"
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "name"
and tokens [ i + 1 ] . text == "suspension"
then



local n = _G.setmetatable({ kind =  "errorStmt" }, cst.ErrorStmt)
local handleTok = add ( n , advance ( ) )
local suspensionTok = add ( n , advance ( ) )
suspensionTok . contextualOp = true
local withTok = nil
if cur ( ) . kind == "name" and cur ( ) . text == "with" then
withTok = add ( n , advance ( ) )
withTok . contextualOp = true
else
errAt ( cur ( ) , "'with' expected in 'handle suspension'" , "NUPP1002" )
end
local handler = add ( n , parseExp ( ) )
local handlerFirst , handlerLast = cst . firstToken ( handler ) , cst . lastToken ( handler )
if withTok and handlerFirst and handlerLast then
errAt (
handleTok ,
"handle suspension uses an owned with installation" ,
"NUPP1005" ,
"write with installation = nupp.suspension.host.install(handler) do ... end" ,
{
{
title = "install the handler with an owned scope" ,
edits = {
{
offset = handleTok . offset ,
length = handlerLast . offset + # handlerLast . text - handleTok . offset ,
newText = "with installation = nupp.suspension.host.install(" .. sourceText (
handler
) .. ")" ,
}
} ,
}
}
)
else
errAt (
handleTok ,
"handle suspension uses an owned with installation" ,
"NUPP1005" ,
"write with installation = nupp.suspension.host.install(handler) do ... end"
)
end
add ( n , expect ( "do" , "to open 'handle suspension'" ) )
add ( n , parseBlock ( ) )
add ( n , expect ( "end" , "to close 'handle suspension'" ) )
return n

elseif startsTypedecl ( i ) then
return parseTypedecl ( nil , "module" )

elseif kind == "name" and cur ( ) . text == "global" and startsTypedecl ( i + 1 ) then
local globalTok = advance ( )
return parseTypedecl ( globalTok , "global" )

elseif kind == "function" then
local n = _G.setmetatable({ kind =  "funcStmt" }, cst.FuncStmt)
add ( n , advance ( ) )
local fn = _G.setmetatable({ kind =  "funcname" }, cst.Funcname)
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

elseif kind == "name"
and cur ( ) . text == "const"
and tokens [ i + 1 ]
and ( tokens [ i + 1 ] . kind == "..." or tokens [ i + 1 ] . kind == "name" )
and (
( tokens [ i + 1 ] . kind == "name" and tokens [ i + 2 ] and tokens [ i + 2 ] . kind == "." )
or (
tokens [ i + 1 ] . kind == "..."
and tokens [ i + 2 ]
and tokens [ i + 2 ] . kind == "name"
and tokens [ i + 3 ]
and tokens [ i + 3 ] . kind == "."
)
)
then
local n = _G.setmetatable({ targets =  { } ,  exprs =  { } ,  kind =  "assignStmt" }, cst.AssignStmt)
n . isConst = true
add ( n , advance ( ) )
if cur ( ) . kind == "..." then
n . deepConst = true
add ( n , advance ( ) )
end
n . targets [ 1 ] = add ( n , parseSuffixedexp ( ) )

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

elseif kind == "local"
or (
kind == "name"
and cur ( ) . text == "const"
and tokens [ i + 1 ]
and ( tokens [ i + 1 ] . kind == "name" or tokens [ i + 1 ] . kind == "function" or tokens [ i + 1 ] . kind == "{" )
)
then



local isConst = kind == "name"
local loctok = advance ( )
if cur ( ) . kind == "function" then
local n = _G.setmetatable({ kind =  "localFuncStmt" }, cst.LocalFuncStmt)
n . isConst = isConst
add ( n , loctok )
add ( n , advance ( ) )
n . name = add ( n , expectName ( isConst and "after 'const function'" or "after 'local function'" ) )
n . body = add ( n , parseFuncbody ( ) )
return n
end



if not isConst and startsTypedecl ( i ) then
return parseTypedecl ( loctok , "local" )
end
local n = _G.setmetatable({ names =  { } ,  types =  { } ,  kind =  "localStmt" }, cst.LocalStmt)
n . isConst = isConst
add ( n , loctok )
if cur ( ) . kind == "{" then
n . pattern = { }
add ( n , advance ( ) )
if cur ( ) . kind == "}" then
errAt ( cur ( ) , "a binding pattern needs at least one field" , "NUPP1002" )
else
while true do
local entry = _G.setmetatable({ kind =  "bindingEntry" }, cst.BindingEntry)
if cur ( ) . kind == "name" and cur ( ) . text == "type" then
entry . typeOnly = add ( entry , advance ( ) )
entry . typeOnly . contextualOp = true
end
entry . sourceName = add ( entry , expectName ( "in binding pattern" ) )
if cur ( ) . kind == "name" and cur ( ) . text == "as" then
local asTok = add ( entry , advance ( ) )
asTok . contextualOp = true
entry . alias = add ( entry , expectName ( "after 'as' in binding pattern" ) )
end
if cur ( ) . kind == ":" then
if entry . typeOnly then
errAt ( cur ( ) , "a type selection cannot have a value annotation" , "NUPP1002" )
end
annotationColon ( entry , "in binding pattern" )
entry . type = add ( entry , parseType ( ) )
end
n . pattern [ # n . pattern + 1 ] = add ( n , entry )
local localName = entry . alias or entry . sourceName
n . names [ # n . names + 1 ] = localName
if entry . type then
n . types [ # n . names ] = entry . type
end
if cur ( ) . kind ~= "," then
do break end
end
add ( n , advance ( ) )
if cur ( ) . kind == "}" then
do break end
end
end
end
add ( n , expect ( "}" , "to close binding pattern" ) )
add ( n , expect ( "=" , "after binding pattern" ) )
n . patternSource = add ( n , parseExp ( ) )
if cur ( ) . kind == "," then
errAt ( cur ( ) , "a binding pattern has exactly one source value" , "NUPP1002" )
end
return n
end

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
local n = _G.setmetatable({ kind =  "labelStmt" }, cst.LabelStmt)
add ( n , advance ( ) )
n . name = add ( n , expectName ( "in label" ) )
add ( n , expect ( "::" , "to close label" ) )
return n

elseif kind == "goto" then
local n = _G.setmetatable({ kind =  "gotoStmt" }, cst.GotoStmt)
add ( n , advance ( ) )
n . name = add ( n , expectName ( "after 'goto'" ) )
return n

elseif kind == "break" then
local n = _G.setmetatable({ kind =  "breakStmt" }, cst.BreakStmt)
add ( n , advance ( ) )
return n

elseif kind == "name" and cur ( ) . text == "continue" and tokens [ i + 1 ] and BLOCK_FOLLOW [ tokens [ i + 1 ] . kind ] then
local n = _G.setmetatable({ kind =  "continueStmt" }, cst.ContinueStmt)
local tok = add ( n , advance ( ) )
if loopDepth == 0 then
errAt ( tok , "no loop to continue" )
end
return n

elseif kind == "return" then
local n = _G.setmetatable({ exprs =  { } ,  kind =  "returnStmt" }, cst.ReturnStmt)
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

if kind == "name" and cur ( ) . text == "yield" and valueBlockDepth > 0 then
local value = tokens [ i + 1 ]
local contextual = value
and value . line == cur ( ) . line
and value . kind ~= "("
and value . kind ~= "{"
and value . kind ~= "string"
and (
EXPR_START [ value . kind ]
or UNOPS [ value . kind ]
or value . kind == "error"
or ( value . kind == "or" and value . text == "||" )
)
if contextual then
local n = _G.setmetatable({ kind =  "yieldStmt" }, cst.YieldStmt)
add ( n , advance ( ) ) . contextualOp = true
n . value = add ( n , parseExp ( ) )
return n
end
end

if kind == "name" and cur ( ) . text == "drop" and tokens [ i + 1 ] and tokens [ i + 1 ] . kind ~= "(" then
local n = _G.setmetatable({ kind =  "errorStmt" }, cst.ErrorStmt)
local dropTok = add ( n , advance ( ) )
local value = add ( n , parseExp ( ) )
local last = cst . lastToken ( value )
local fixes = nil
if last then
fixes = {
{
title = "use nupp.drop" ,
edits = {
{
offset = dropTok . offset ,
length = last . offset + # last . text - dropTok . offset ,
newText = "nupp.drop(" .. sourceText ( value ) .. ")" ,
}
} ,
}
}
end
errAt ( dropTok , "drop uses nupp.drop(value)" , "NUPP1005" , "write nupp.drop(value)" , fixes )
return n
end


local e = parseSuffixedexp ( )
if compoundOp ( ) then
local n = _G.setmetatable({ kind =  "compoundAssign" }, cst.CompoundAssign)
n . target = add ( n , e )
n . op = add ( n , advance ( ) )
n . value = add ( n , parseExp ( ) )
if not ASSIGN_TARGETS [ e . kind ] then
errAt ( cst . firstToken ( e ) or cur ( ) , "cannot assign to this expression" )
end
return n
end
if cur ( ) . kind == "=" or cur ( ) . kind == "," then
local n = _G.setmetatable({ targets =  { } ,  exprs =  { } ,  kind =  "assignStmt" }, cst.AssignStmt)
n . targets [ 1 ] = add ( n , e )
while cur ( ) . kind == "," do
add ( n , advance ( ) )
n . targets [ # n . targets + 1 ] = add ( n , parseSuffixedexp ( ) )
end
add ( n , expect ( "=" , "in assignment" ) )
n . exprs = parseExplist ( n )
for _ , target in ipairs ( n . targets ) do
if not ASSIGN_TARGETS [ target . kind ] then
errAt ( cst . firstToken ( target ) or cur ( ) , "cannot assign to this expression" )
end
end
return n
end
local ek = e . kind
if ek == "call" or ek == "methodCall" or ek == "safeCall" or ek == "errorExpr" then
local n = _G.setmetatable({ kind =  "callStmt" }, cst.CallStmt)
n . expr = add ( n , e )
return n
end
errAt ( cur ( ) , "syntax error: expression is not a statement" )
local n = _G.setmetatable({ kind =  "errorStmt" }, cst.ErrorStmt)
add ( n , e )

return n
end






local function parseBlockNested ( ) 
local n = _G.setmetatable({ stats =  { } ,  kind =  "block" }, cst.Block)
local returned = false
while not BLOCK_FOLLOW [ cur ( ) . kind ] do



if returned then
errAt (
cur ( ) ,
"'return' must be the last statement in a block" ,
nil ,
"move the 'return' below the statements that follow it, or delete them"
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
local e = _G.setmetatable({ kind =  "errorStmt" }, cst.ErrorStmt)
errAt ( cur ( ) , ("unexpected '%s'") : format ( spelling ( cur ( ) ) ) )
add ( e , advance ( ) )
n . stats [ # n . stats + 1 ] = add ( n , e )
end
end

return n
end

parseBlock = function ( ) 
nesting = nesting + 1
if nesting > 1000 then
tooDeepAt = cur ( )
error ( TOO_DEEP , 0 )
end
local n = parseBlockNested ( )
nesting = nesting - 1

return n
end

local function parseChunk ( ) 
local root = _G.setmetatable({ blocks =  { } ,  kind =  "chunk" }, cst.Chunk)
while cur ( ) . kind == "@"
and tokens [ i + 1 ]
and tokens [ i + 1 ] . kind == "not"
and tokens [ i + 1 ] . text == "!"
and tokens [ i + 2 ]
and tokens [ i + 2 ] . kind == "name" do
local name = tokens [ i + 2 ] . text
if name ~= "nofmt" and name ~= "internal" then
do break end
end



root . innerAnnotations = root . innerAnnotations or { }
for offset = 0 , 2 do
root . innerAnnotations [ # root . innerAnnotations + 1 ] = tokens [ i + offset ]
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
do break end
end


local e = _G.setmetatable({ kind =  "errorStmt" }, cst.ErrorStmt)
errAt ( cur ( ) , ("unexpected '%s' at top level") : format ( spelling ( cur ( ) ) ) )
add ( e , advance ( ) )
add ( root , e )
end
root . eof = add ( root , advance ( ) )

return root
end

local parsed , root = pcall ( parseChunk )
if not parsed then



if root ~= TOO_DEEP and not tostring ( root ) : find ( "stack overflow" , 1 , true ) then
error ( tostring ( root ) , 0 )
end
local at = tooDeepAt or tokens [ i ] or tokens [ # tokens ]
errAt (
at ,
("nested more than %d levels deep") : format ( 1000 ) ,
"NUPP1005" ,
"name the inner parts with locals, or split the nesting into functions"
)
local chunk = _G.setmetatable({ blocks =  { } ,  kind =  "chunk" }, cst.Chunk)
local block = _G.setmetatable({ stats =  { } ,  kind =  "block" }, cst.Block)
local stray = _G.setmetatable({ kind =  "errorStmt" }, cst.ErrorStmt)
for index = 1 , # tokens - 1 do
add ( stray , tokens [ index ] )
end
block . stats [ 1 ] = add ( block , stray )
chunk . blocks [ 1 ] = add ( chunk , block )
chunk . eof = add ( chunk , tokens [ # tokens ] )
root = chunk
end

return { root = root , tokens = tokens , errors = errors , source = source }
end

local __nuppExportValue= parser ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.syntax.parser"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.syntax.parser"]=__nuppExports;return __nuppExports