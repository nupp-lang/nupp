_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);






local cst = require ( "nupp.compiler.cst" )
local tree = require ( "nupp.compiler.lsp.tree" )
local text = require ( "nupp.compiler.lsp.text" )
local wire = require ( "nupp.compiler.lsp.wire" )
local lexer = require ( "nupp.compiler.lexer" )
local T = require ( "nupp.compiler.types" )

local semantic = { }














































semantic . semanticTypes = wire . array ( {
"namespace" ,
"type" ,
"class" ,
"enum" ,
"interface" ,
"struct" ,
"typeParameter" ,
"parameter" ,
"variable" ,
"property" ,
"enumMember" ,
"function" ,
"method" ,
"nuppKeyword" ,
"comment" ,
"string" ,
"number" ,
"operator" ,
"decorator" ,
"label" ,
} )

semantic . semanticModifiers = wire . array ( { "declaration" , "readonly" , "deprecated" } )



semantic . keywordType = "nuppKeyword"

semantic . semanticIndex = { }
for index , name in ipairs ( semantic . semanticTypes ) do
semantic . semanticIndex [ name ] = index - 1
end

semantic . semanticKindMap = {
namespace = "namespace" ,
type = "type" ,
struct = "struct" ,
interface = "interface" ,
typeParameter = "typeParameter" ,
parameter = "parameter" ,
variable = "variable" ,
property = "property" ,
[ "function" ] = "function" ,
method = "method" ,
decorator = "decorator" ,
label = "label" ,
}



semantic . TYPE_WORDS = {
[ "function" ] = true ,
[ "metatable" ] = true ,
[ "is" ] = true ,
[ "affine" ] = true ,
[ "borrowed" ] = true ,
[ "pinned" ] = true ,
[ "const" ] = true ,
}

function semantic . syntaxKinds ( result )
local kinds = { }
local keywordType = semantic . keywordType
local function mark ( tok , kind )
if tok and cst . isToken ( tok ) then
kinds [ tok ] = kind
end
end





local tokens = result . tokens or { }
local at = 1
while tokens [
at
] and tokens [
at
] . kind == "@" and tokens [
at + 1
] and tokens [
at + 1
] . kind == "not" and tokens [
at + 1
] . text == "!" and tokens [
at + 2
] and tokens [ at + 2 ] . kind == "name" and ( tokens [ at + 2 ] . text == "internal" or tokens [ at + 2 ] . text == "nofmt" ) do
mark ( tokens [ at + 2 ] , "decorator" )
at = at + 3
end

tree . walkNodes ( result . root , function ( node )
local kind = node . kind
if kind == "cdefFunc" or kind == "cdefStruct" then
for _ , child in ipairs ( node ) do
if cst . isToken ( child ) and ( child . text == "cdef" or child . text == "struct" or child . text == "from" ) then
mark ( child , keywordType )
end
end
elseif kind == "typeAlias" or kind == "recordDecl" then
for _ , child in ipairs ( node ) do
if cst . isToken ( child ) and child . kind == "name" and child ~= node . name then
if child . text == "type"
or child . text == "record"
or child . text == "interface"
or child . text == "struct"
or child . text == "global"
or child . text == "is"
or child . text == "where"
then
mark ( child , keywordType )
end
end
end
elseif kind == "generics" then
for _ , child in ipairs ( node ) do
if cst . isToken ( child ) and child . kind == "name" and child . text == "is" then
mark ( child , keywordType )
end
end
for _ , tok in ipairs ( ( node ) . names ) do
mark ( tok , "typeParameter" )
end
elseif kind == "newExpr" or kind == "constructorDecl" or kind == "satisfiesDecl" then
mark ( node [ 1 ] , keywordType )
elseif kind == "unsafeOwnershipExpr" then
mark ( node [ 1 ] , keywordType )
mark ( node [ 2 ] , keywordType )
elseif kind == "whereClause" then
mark ( node [ 1 ] , keywordType )
elseif kind == "metamethodDecl" then
mark ( node [ 1 ] , keywordType )
mark ( node . name , "method" )
elseif kind == "inlineMethod" then
mark ( node [ 1 ] , keywordType )
mark ( node . name , "method" )
elseif kind == "castExpr" or kind == "isExpr" then
for _ , child in ipairs ( node ) do
if cst . isToken ( child ) and child . text == "as" then
mark ( child , keywordType )
elseif cst . isToken ( child ) and child . text == "is" then
mark ( child , "operator" )
end
end
elseif kind == "tpredicate" then
for _ , child in ipairs ( node ) do
if cst . isToken ( child ) and child . text == "is" then
mark ( child , keywordType )
end
end
elseif kind == "tborrows" then
for _ , child in ipairs ( node ) do
if cst . isToken ( child ) and child . text == "borrows" then
mark ( child , keywordType )
end
end
elseif kind == "tpreserves" then
for _ , child in ipairs ( node ) do
if cst . isToken ( child ) and child . text == "preserves" then
mark ( child , keywordType )
end
end
elseif kind == "tconst" then
mark ( node [ 1 ] , keywordType )
elseif kind == "funcbody" or kind == "tfunc" then
for _ , child in ipairs ( node ) do
if cst . isToken ( child ) and ( child . text == "yields" or child . text == "resumes" ) then
mark ( child , keywordType )
end
end
if kind == "tfunc" and node . noSuspend then
mark ( node [ 1 ] , keywordType )
end
elseif kind == "pragmaStmt" or kind == "annotationApply" then
mark ( node . name , "decorator" )
elseif kind == "dedentString" then
mark ( node . keyword , keywordType )
elseif kind == "unsafeStmt" then
mark ( node . unsafeTok , keywordType )
elseif kind == "noSuspendStmt" then
mark ( node . keywordTok , keywordType )
elseif kind == "localFuncStmt" and node . isConst then
mark ( node [ 1 ] , keywordType )
if node . comptimeTok then
mark ( node . comptimeTok , keywordType )
end
elseif kind == "localStmt" and node . isConst then
mark ( node [ 1 ] , keywordType )
elseif ( kind == "localFuncStmt" or kind == "funcStmt" ) and node . comptimeTok then
mark ( node . comptimeTok , keywordType )
elseif kind == "continueStmt" then
mark ( node [ 1 ] , keywordType )
elseif kind == "labelStmt" or kind == "gotoStmt" then
mark ( node . name , "label" )
elseif kind == "param" or kind == "tfuncParam" then
if node . modeTok then
mark ( node . modeTok , keywordType )
end
mark ( node . name , "parameter" )
elseif kind == "fieldDecl" or kind == "tshapeField" then
if node . capability then
mark ( node . capability , keywordType )
end
mark ( node . name , "property" )
elseif kind == "fieldNamed" then
mark ( node . name , "property" )
elseif kind == "indexerDecl" or kind == "tmap" then
if node . capability then
mark ( node . capability , keywordType )
end
end
end )

return kinds
end



local EMBEDDED_STRING_FORMATS = { json = true , glsl = true , lua = true , nupp = true , peg = true }




local function embeddedStringTokens ( result )
local embedded = { }
tree . walkNodes ( result . root , function ( node )
if node . kind ~= "localStmt" then
return
end
if not EMBEDDED_STRING_FORMATS [ ( node ) . embeddedStringFormat ] then
return
end
for _ , value in ipairs ( node . exprs or { } ) do
if value and ( value . kind == "string" or value . kind == "dedentString" ) and value . token then
embedded [ value . token ] = true
end
end
end )

return embedded
end

function semantic . addSemanticSpan (
entries ,
source ,
offset ,
spanText ,
kind ,
modifiers
)
if not spanText or spanText == "" then
return
end
local pos = 1
while pos <= # spanText do
local newline = spanText : find ( "\n" , pos , true )
local finish = newline and newline - 1 or # spanText
if finish >= pos then
local startOffset = offset + pos - 1
local endOffset = offset + finish
local startPos = text . positionAtOffset ( source , startOffset )
local endPos = text . positionAtOffset ( source , endOffset )
if endPos . character > startPos . character then
entries [
# entries + 1
] = {
line = startPos . line ,
character = startPos . character ,
length = endPos . character - startPos . character ,
kind = semantic . semanticIndex [ kind ] ,
modifiers = modifiers or 0 ,
}
end
end
if not newline then
break
end
pos = newline + 1
end
end

















function semantic . install ( s )
local semanticIndex , semanticKindMap = semantic . semanticIndex , semantic . semanticKindMap
local syntaxKinds , addSemanticSpan = semantic . syntaxKinds , semantic . addSemanticSpan

local function semanticEntries ( doc )
local entries = { }
local syntax = syntaxKinds ( doc . result )
local embedded = embeddedStringTokens ( doc . result )
for _ , tok in ipairs ( doc . result . tokens or { } ) do
for triviaIndex = 1 , tok . triviaCount do
local trivia = lexer . triviaRecord ( tok , triviaIndex )
local docComment = trivia . kind == "comment" and trivia . text : sub (
1 ,
3
) == "---" and trivia . text : sub ( 4 , 4 ) ~= "-"




if not docComment and ( trivia . kind == "comment" or trivia . kind == "hashbang" ) then
addSemanticSpan ( entries , doc . text , trivia . offset , trivia . text , "comment" )
end
end
local kind = nil
if tok . kind == "number" then
kind = "number"
elseif tok . kind == "string"
or tok . kind == "istringOpen"
or tok . kind == "istringMid"
or tok . kind == "istringClose"
then
kind = not embedded [ tok ] and "string" or nil
elseif lexer . KEYWORDS [ tok . kind ] then
kind = semantic . keywordType
elseif tok . kind == "name" then
kind = syntax [
tok
] or semanticKindMap [ tok . semanticKind ] or ( T . builtins [ tok . text ] and "type" ) or "variable"
elseif semanticIndex [ syntax [ tok ] ] then
kind = syntax [ tok ]
elseif tok . kind ~= "eof"
and tok . kind ~= "error"
and tok . kind ~= "("
and tok . kind ~= ")"
and tok . kind ~= "["
and tok . kind ~= "]"
and tok . kind ~= "{"
and tok . kind ~= "}"
and tok . kind ~= ","
and tok . kind ~= ";"
and tok . kind ~= "."
then
kind = "operator"
end
if kind then






local def = tok . definition
local declaration = def ~= nil and def . token ~= nil and def . token . offset == tok . offset and (
def . filename == nil or def . filename == doc . path
)
local modifiers = declaration and 1 or 0
if tok . definition and tok . definition . constant then
modifiers = modifiers + 2
end
if tok . definition and tok . definition . deprecated then
modifiers = modifiers + 4
end
addSemanticSpan ( entries , doc . text , tok . offset , tok . text , kind , modifiers )
end
end
table . sort ( entries , function ( a , b )
return a . line < b . line or ( a . line == b . line and a . character < b . character )
end )

return entries
end




local function encodeSemanticEntries ( entries )
local data = wire . array ( { } )
local lastLine , lastCharacter = 0 , 0
for _ , entry in ipairs ( entries ) do
local deltaLine = entry . line - lastLine
local deltaCharacter = deltaLine == 0 and entry . character - lastCharacter or entry . character
data [ # data + 1 ] = deltaLine
data [ # data + 1 ] = deltaCharacter
data [ # data + 1 ] = entry . length
data [ # data + 1 ] = entry . kind
data [ # data + 1 ] = entry . modifiers
lastLine , lastCharacter = entry . line , entry . character
end

return data
end




local sentTokens = { }
local nextResultId = 0

local function rememberTokens ( uri , data )
nextResultId = nextResultId + 1
local resultId = tostring ( nextResultId )
sentTokens [ uri ] = { resultId = resultId , data = data }
return resultId
end





local function tokenEdits ( before , after )
local prefix = 0
while prefix + 5 <= # before and prefix + 5 <= # after do
local same = true
for offset = 1 , 5 do
if before [ prefix + offset ] ~= after [ prefix + offset ] then
same = false
break
end
end
if not same then
break
end
prefix = prefix + 5
end
local suffix = 0
while prefix + suffix + 5 <= # before and prefix + suffix + 5 <= # after do
local same = true
for offset = 1 , 5 do
if before [ # before - suffix - 5 + offset ] ~= after [ # after - suffix - 5 + offset ] then
same = false
break
end
end
if not same then
break
end
suffix = suffix + 5
end
local deleteCount = # before - prefix - suffix
local inserted = wire . array ( { } )
for index = prefix + 1 , # after - suffix do
inserted [ # inserted + 1 ] = after [ index ]
end
if deleteCount == 0 and # inserted == 0 then
return wire . array ( { } )
end

return wire . array ( { { start = prefix , deleteCount = deleteCount , data = inserted , } } )
end

return {
semanticEntries = semanticEntries ,
encodeSemanticEntries = encodeSemanticEntries ,
rememberTokens = rememberTokens ,
tokenEdits = tokenEdits ,


lastSent = function ( uri )
return sentTokens [ uri ]
end ,
}
end

return semantic
