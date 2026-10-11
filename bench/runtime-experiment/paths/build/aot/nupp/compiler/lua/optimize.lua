_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.lua.optimize\0runtime\0001") };





















local inlinefacts = require ( "nupp.compiler.inlinefacts" )
local viewfacts = require ( "nupp.compiler.viewfacts" )
local cst = require ( "nupp.compiler.syntax.cst" )
local checkpoint = require ( "nupp.compiler.syntax.checkpoint" )
local constspecialize = require ( "nupp.compiler.lua.constspecialize" )
local indexedViews = require ( "nupp.compiler.types.indexedviews" )

local optimize = { }

local isToken = cst . isToken
local firstToken = cst . firstToken







optimize . passes = {
[ "OPT-1" ] = { name = "presize" , level = 1 , summary = "size a table built field by field when it is created" , } ,
[
"OPT-2"
] = { name = "numeric-ipairs" , level = 1 , summary = "iterate a stable declared array with a numeric for loop" , } ,
[
"OPT-3"
] = {
name = "constant-fold" ,
level = 1 ,
summary = "fold exact primitive expressions, drop dead branches and loops, and propagate const bindings" ,
} ,
[
"OPT-4"
] = { name = "static-callable" , level = 1 , summary = "bind repeated immutable dotted callees at their first use" , } ,
[
"OPT-5"
] = {
name = "concat-buffer" ,
level = 1 ,
summary = "build a string accumulated round a loop with a nupp.text buffer" ,
} ,
[
"OPT-6"
] = {
name = "indexed-range" ,
level = 1 ,
summary = "lower proved trusted indexed-view accesses through their physical adapters" ,
} ,
[
"OPT-7"
] = {
name = "inline-return-helper" ,
level = 1 ,
summary = "inline eligible local and imported single-return helpers" ,
} ,
[
"OPT-8"
] = {
name = "const-monomorphize" ,
level = 1 ,
summary = "emit bounded private bodies for closed scalar const applications" ,
} ,
}








local PRESIZE_MIN = 2


local function nameText ( node ) 
if not node or isToken ( node ) then
return nil
end
if node . kind ~= "name" then
return nil
end

return node . token and node . token . text or nil
end





local function occurrences ( node , name ) 
if not node then
return 0
end
if isToken ( node ) then
return ( node . kind == "name" and node . text == name ) and 1 or 0
end
local total = 0
for _ , child in ipairs ( node ) do
total = total + occurrences ( child , name )
end

return total
end




local function fieldTargetBase ( target ) 
if not target or isToken ( target ) then
return nil
end
if target . kind ~= "dotIndex" and target . kind ~= "bracketIndex" then
return nil
end

return nameText ( target . obj )
end



local NEVER_NIL = {
boolean = true ,
string = true ,
number = true ,
integer = true ,
float = true ,
table = true ,
array = true ,
map = true ,
tuple = true ,
shape = true ,
func = true ,
nominal = true ,
}





local function oneNonNilValue ( value ) 
if not value or isToken ( value ) then
return false
end
local kind = value . kind
if kind == "paren" then
return oneNonNilValue ( value . expr )
end
if kind == "number"
or kind == "string"
or kind == "trueExpr"
or kind == "falseExpr"
or kind == "tableExpr"
or kind == "funcExpr"
or kind == "shortfn"
then
return true
end
if kind == "name" and value . token then
local t = value . token . inferredType
if t and t . tag == "literal" then
t = t . base
end
return t ~= nil and NEVER_NIL [ t . tag ] == true
end

return false
end




local function writtenKey ( target ) 
if target . kind == "dotIndex" then
return "hash" , target . name and target . name . text or nil
end
local key = target . expr
if key and not isToken ( key ) then
if key . kind == "string" then
local token = firstToken ( key )
return "hash" , token and token . text or nil
end
if key . kind == "number" then
local token = firstToken ( key )
local value = token and tonumber ( token . text ) or nil
if value and value >= 1 and value == math . floor ( value ) then
return "array" , value
end
end
end

return "opaque" , nil
end


local function fieldWrites ( stat , name ) 
if stat . kind ~= "assignStmt" then
return { }
end
local writes = { }
for _ , target in ipairs ( stat . targets or { } ) do
if fieldTargetBase ( target ) == name then
writes [ # writes + 1 ] = target
end
end

return writes
end




local function constructorField ( stat , name , keys ) 
if stat . kind ~= "assignStmt"
or stat . isConst
or stat . automaticOwner
or stat . automaticOwnerMove
or stat . automaticOwnerMoves
or stat . automaticOwnerReinit
or # ( stat . targets or { } ) ~= 1
or # ( stat . exprs or { } ) ~= 1
then
return nil
end
local target = stat . targets [ 1 ]
if not target or isToken ( target ) or target . kind ~= "dotIndex" or fieldTargetBase ( target ) ~= name then
return nil
end
local key = target . name and target . name . text or nil
if not key or keys [ key ] then
return nil
end
keys [ key ] = true

return { name = target . name , value = stat . exprs [ 1 ] , stat = stat }
end


















local function planPresize ( stats , at , name ) 
local hashKeys , opaque , array = { } , 0 , 0
local hashCount , writeCount = 0 , 0
local stoppedAt = nil
local constructorFields , constructorKeys = { } , { }
local constructorGap , constructorRejected = false , false
local hole = nil
for j = at + 1 , # stats do
local stat = stats [ j ]
local writes = fieldWrites ( stat , name )
if occurrences ( stat , name ) ~= # writes then
stoppedAt = stat
do break end
end
if # writes == 0 then
constructorGap = true
elseif constructorGap then
constructorRejected = true
end
if # writes > 0 and not constructorRejected then
local field = constructorField ( stat , name , constructorKeys )
if field then
constructorFields [ # constructorFields + 1 ] = field
else
constructorRejected = true
end
end
writeCount = writeCount + # writes


local sole = # writes == 1
and # ( stat . targets or { } ) == 1
and # ( stat . exprs or { } ) == 1
and oneNonNilValue ( stat . exprs [ 1 ] )
for _ , target in ipairs ( writes ) do
local kind , value = writtenKey ( target )
if kind == "array" and sole and value == array + 1 then
array = value
elseif kind == "array" then
hole = hole or target
elseif kind == "hash" and value then
if not hashKeys [ value ] then
hashKeys [ value ] = true
hashCount = hashCount + 1
end
else
opaque = opaque + 1
end
end
end

if constructorRejected or # constructorFields ~= writeCount then
constructorFields = nil
end
if hole then
return 0 , 0 , stoppedAt , nil , hole
end

return array , hashCount + opaque , stoppedAt , constructorFields , nil
end




local function isEmptyTable ( node ) 
return node and not isToken ( node ) and node . kind == "tableExpr" and # ( node . fields or { } ) == 0
end

local function remark ( remarks , node , code , message , related , status ) 
local token = node and node . importedCallAt or firstToken ( node )
local last = node and node . importedCallAt or cst . lastToken ( node )
remarks [
# remarks + 1
] = {
code = code ,
severity = "note" ,
status = status or "fired" ,
hotness = "unknown" ,
sourceEndLine = last and last . line or token and token . line or 0 ,
msg = message ,
line = token and token . line or 0 ,
col = token and token . col or 0 ,
offset = token and token . offset or 0 ,
length = token and # token . text or 1 ,
related = related ,
}
end


local function relatedAt ( token , message ) 
if not token then
return nil
end
return { { line = token . line , col = token . col , offset = token . offset , length = # token . text , message = message , } }
end

local function presizeBlock ( stats , remarks ) 
for i , stat in ipairs ( stats ) do
if not isToken ( stat )
and stat . kind == "localStmt"
and stat . names
and # stat . names == 1
and stat . exprs
and # stat . exprs == 1
and isEmptyTable ( stat . exprs [ 1 ] )
then
local name = stat . names [ 1 ] . text
local constructor = stat . exprs [ 1 ]
local array , hash , stoppedAt , constructorFields , hole = planPresize ( stats , i , name )
if hole then
remark (
remarks ,
constructor ,
"OPT-1" ,
("presize: %s is not presized, because an integer key that does not extend a sequence leaves a hole, and where it is placed decides what # answers")



: format ( name ) ,
relatedAt ( firstToken ( hole ) , "written here" ) ,
"declined"
)
elseif array + hash >= 2 then
constructor . presize = { narr = array , nhash = hash }
if constructorFields then
constructor . presizeFields = constructorFields
for _ , field in ipairs ( constructorFields ) do
field . stat . presizedIntoConstructor = true
end
end
local message
if constructorFields then
message = ("presize: %s is created with %d named fields") : format ( name , # constructorFields )
else
message = ("presize: %s is created with room for %d array and %d hash entries")

: format ( name , array , hash )
end
remark ( remarks , constructor , "OPT-1" , message )
elseif stoppedAt then
local token = firstToken ( stoppedAt )
remark (
remarks ,
constructor ,
"OPT-1" ,
("presize: %s is not presized, because it is used for something other than a field assignment before its fields are known")



: format ( name ) ,
relatedAt ( token , "used here" ) ,
"declined"
)
end
end
end
end

local function walk ( node , remarks ) 
if not node or isToken ( node ) then
return
end
if node . stats then
presizeBlock ( node . stats , remarks )
end
for _ , child in ipairs ( node ) do
walk ( child , remarks )
end
end







local NESTED_FUNCTION = { localFuncStmt = true , funcStmt = true , inlineMethod = true , funcExpr = true , shortfn = true , }






local function denseLiteralLengths ( body ) 
local lengths = { }

local function collect ( node ) 
if not node or isToken ( node ) or NESTED_FUNCTION [ node . kind ] then
return
end
if node . kind == "localStmt" then
for j , name in ipairs ( node . names or { } ) do
local value = node . exprs and node . exprs [ j ]
if value and value . kind == "tableExpr" then
local length , dense = 0 , true
for _ , field in ipairs ( value . fields or { } ) do
if field . kind == "fieldItem" and oneNonNilValue ( field . value ) then
length = length + 1
else
dense = false
end
end
if dense and name . definition then
lengths [ name . definition ] = length
end
end
end
end
for _ , child in ipairs ( node ) do
collect ( child )
end
end

collect ( body )

return lengths
end










local function numericIpairsBody ( body , facts , remarks ) 
local asked = facts . body ( body )
local lengths = denseLiteralLengths ( body )

local function walk ( node ) 
if not node or isToken ( node ) or NESTED_FUNCTION [ node . kind ] then
return
end
if node . kind == "forinStmt" and node . builtinIpairs then
local operand = node . builtinIpairs . operand
local token = operand . token
local length = token and lengths [ token . definition ] or nil
local ok , reason , related = true , nil , nil
if length == nil then
ok , reason , related = false , "the array's dense entry length is not statically known" , operand
elseif asked . uses ( token . definition ) > 2 then
ok , reason , related = false , "the literal array has another use that may alias or expose it" , operand
else




ok , reason , related = asked . shapeStable ( body , asked . aliasOf ( token ) , function ( value ) 
return value == node and node . body or nil
end )
end
if ok then
node . numericIpairs = { operand = operand , length = length }
remark (
remarks ,
node ,
"OPT-2" ,
"numeric-ipairs: the declared array has a stable shape in this loop"
)
else
local at = related and firstToken ( related ) or nil
remark (
remarks ,
node ,
"OPT-2" ,
"numeric-ipairs: not rewritten because " .. reason ,
relatedAt ( at , "proof stopped here" ) ,
"declined"
)
end
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

walk ( body )
end







local LOOPS = { fornumStmt = true , forinStmt = true , whileStmt = true , repeatStmt = true , }




local function emptyString ( node ) 
if not node or isToken ( node ) or node . kind ~= "string" then
return false
end
local token = firstToken ( node )
local text = token and token . text or ""

return text == "\"\"" or text == "''" or text == "[[]]"
end






local function appendedPieces ( expr , definition ) 
if not expr or isToken ( expr ) or expr . kind ~= "binop" then
return nil
end
if not expr . op or expr . op . text ~= ".." or not expr . plainConcat then
return nil
end
local left = expr . lhs
if not left or isToken ( left ) or left . kind ~= "name" or not left . token or left . token . definition ~= definition then
return nil
end
local pieces = { }
local rest = expr . rhs
while rest and not isToken ( rest ) and rest . kind == "binop" and rest . op and rest . op . text == ".." do
if not rest . plainConcat then
return nil
end
pieces [ # pieces + 1 ] = rest . lhs
rest = rest . rhs
end
if not rest then
return nil
end
pieces [ # pieces + 1 ] = rest

return pieces
end






local function leavesByGoto ( loop ) 
local enclosing = { }
local leaves = false

local function holdsLabel ( block , name ) 
for _ , stat in ipairs ( block . stats or { } ) do
if stat . kind == "labelStmt" and stat . name and stat . name . text == name then
return true
end
end

return false
end

local function walk ( node ) 
if leaves or not node or isToken ( node ) or NESTED_FUNCTION [ node . kind ] then
return
end
if node . kind == "gotoStmt" and node . name then
local found = false
for k = # enclosing , 1 , -1 do
if holdsLabel ( enclosing [ k ] , node . name . text ) then
found = true
do break end
end
end
leaves = not found
return
end
local block = node . kind == "block"
if block then
enclosing [ # enclosing + 1 ] = node
end
for _ , child in ipairs ( node ) do
walk ( child )
end
if block then
enclosing [ # enclosing ] = nil
end
end

walk ( loop )

return leaves
end




local function soleAccumulation ( loop , definition , asked ) 
if leavesByGoto ( loop ) then
return nil
end
local found , other = nil , false

local function walk ( node ) 
if not node or isToken ( node ) or other then
return
end
if node . kind == "assignStmt" and # ( node . targets or { } ) == 1 and # ( node . exprs or { } ) == 1 then
local target = node . targets [ 1 ]
if target
and not isToken ( target )
and target . kind == "name"
and target . token
and target . token . definition == definition
then
local pieces = appendedPieces ( node . exprs [ 1 ] , definition )
if pieces and not found then
found = { stat = node , pieces = pieces }


for _ , piece in ipairs ( pieces ) do
if asked . uses ( definition , piece ) > 0 then
other = true
end
end
return
end
other = true
return
end
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

walk ( loop )
if other or not found then
return nil
end

if asked . uses ( definition , loop ) ~= 2 then
return nil
end

return found
end





local function concatBufferBlocks ( node , asked , remarks , counter ) 


if not node or isToken ( node ) or NESTED_FUNCTION [ node . kind ] then
return counter
end
local stats = node . kind == "block" and node . stats or nil
for i , stat in ipairs ( stats or { } ) do
if stat . kind == "localStmt"
and # ( stat . names or { } ) == 1
and # ( stat . exprs or { } ) == 1
and emptyString ( stat . exprs [ 1 ] )
and stat . names [ 1 ] . definition
then
local definition = stat . names [ 1 ] . definition



local loop , loopIndex , untouched = nil , nil , true
for j = i + 1 , # stats do
local next = stats [ j ]
if LOOPS [ next . kind ] then
loop = next
loopIndex = j
do break end
end
if asked . uses ( definition , next ) > 0 then
untouched = false
do break end
end
end
local accumulation = untouched and loop and soleAccumulation ( loop , definition , asked ) or nil
if accumulation then
counter = counter + 1
local name = ("__nuppBuf_%d") : format ( counter )
stat . concatBuffer = { name = name , elide = false }
accumulation . stat . concatBuffer = { name = name , pieces = accumulation . pieces }
loop . concatBuffer = { name = name , target = stat . names [ 1 ] . text , directReturn = false }
local following = stats [ ( loopIndex or 0 ) + 1 ]
local returned = following
and following . kind == "returnStmt"
and # ( following . exprs or { } ) == 1
and following . exprs [ 1 ]
or nil


if returned
and returned . kind == "name"
and returned . token . definition == definition
and asked . uses ( definition ) == 4
then
stat . concatBuffer . elide = true
loop . concatBuffer . directReturn = true
returned . concatBufferResult = name
end
remark (
remarks ,
stat ,
"OPT-5" ,
("concat-buffer: %s is built with a nupp.text buffer, which appends instead of rebuilding")

: format ( stat . names [ 1 ] . text )
)
end
end
end
for _ , child in ipairs ( node ) do
counter = concatBufferBlocks ( child , asked , remarks , counter )
end

return counter
end



















local function concatBufferWalk ( result , remarks ) 
local facts = require ( "nupp.compiler.analysis" ) . queries ( result . analysis )
if not facts then
return
end
local counter = 0
for _ , body in ipairs ( result . analysis . bodies or { } ) do
counter = concatBufferBlocks ( body , facts . body ( body ) , remarks , counter )
end
end

local function numericIpairsWalk ( result , remarks ) 
local facts = require ( "nupp.compiler.analysis" ) . queries ( result . analysis )
if not facts then
return
end
for _ , body in ipairs ( result . analysis . bodies or { } ) do
numericIpairsBody ( body , facts , remarks )
end
end










local MAX_EXACT_INTEGER = 9007199254740991
local scalarIntrinsics = require ( "nupp.compiler.scalarintrinsics" )
local bit = require ( "nupp.compiler.bitops" )







local BITOPS = {
[ "&" ] = bit . band ,
[ "|" ] = bit . bor ,
[ "~" ] = bit . bxor ,
[ "<<" ] = bit . lshift ,
[ ">>" ] = bit . rshift ,
[ "~>>" ] = bit . arshift ,
}

local function literal ( kind , value , code ) 
return { kind = kind , value = value , code = code }
end




local function quoteString ( value ) 
return ( string . format ( "%q" , value ) : gsub ( "\n" , "n" ) )
end

local function integerLiteral ( node ) 
if not node . token then
return nil
end
local text = node . token . text
local lower = text : lower ( )
if lower : find ( "ll" , 1 , true ) or lower : sub ( -1 ) == "i" then
return nil
end
local value = tonumber ( ( text : gsub ( "_" , "" ) ) )
if not value
or value ~= value
or value == math . huge
or value == - math . huge
or value ~= math . floor ( value )
or math . abs ( value ) > 9007199254740991
then
return nil
end

return literal ( "number" , value , ("%.0f") : format ( value ) )
end

local function stringLiteral ( node ) 
if not node . token then
return nil
end
local chunk = loadstring ( "return " .. node . token . text )
if not chunk then
return nil
end
local ok , value = pcall ( chunk )
if not ok or type ( value ) ~= "string" then
return nil
end

return literal ( "string" , value , ( ( string . format ( "%q" , value ) : gsub ( "\n" , "n" ) ) ) )
end






local function comptimeLiteral ( node ) 
local code = node and node . comptimeValue
if code == "nil" then
return ( { kind = "nil" , value = nil , code = "nil" } )
elseif code == "true" or code == "false" then
return literal ( "boolean" , code == "true" , code )
elseif code and code : match ( "^-?%d+$" ) then
local value = tonumber ( code )
if value and math . abs ( value ) <= 9007199254740991 then
return ( { kind = "number" , value = value , code = code } )
end
elseif code and code : sub ( 1 , 1 ) == "\"" then
local chunk = loadstring ( "return " .. code )
if chunk then
local ok , value = pcall ( chunk )
if ok and type ( value ) == "string" then
return literal ( "string" , value , ( ( string . format ( "%q" , value ) : gsub ( "\n" , "n" ) ) ) )
end
end
end

return nil
end

local function truthy ( value ) 
return value . kind ~= "nil" and not ( value . kind == "boolean" and not value . value )
end

local function bindingKey ( token ) 
return token . definition or token . text
end

local function markWritten ( writes , token ) 
if token then
writes [ ( token . definition or token . text ) ] = true
end
end



local function writtenBindings ( node , writes ) 
if not node or isToken ( node ) then
return
end

if node . kind == "assignStmt" then
for _ , target in ipairs ( node . targets or { } ) do
if target . kind == "name" then
markWritten ( writes , target . token )
end
end
elseif node . kind == "compoundAssign" then
if node . target and node . target . kind == "name" then
markWritten ( writes , node . target . token )
end
elseif node . kind == "funcStmt" then
local name = node . name
if name and not name . method and # name == 1 then
markWritten ( writes , name . base )


writes [ name . base . text ] = true
end
end
for _ , child in ipairs ( node ) do
writtenBindings ( child , writes )
end
end

local function scope ( parent , writes ) 
return { parent = parent , constants = { } , paths = { } , writes = writes or parent and parent . writes or { } }
end

local function unchangedScalar ( name , value , current ) 
if not value
or not value . code
or not name . definition
or current . writes [ ( name . definition or name . text ) ]
or current . writes [ name . text ]
then
return false
end


local t = name . inferredType
if t and t . tag == "literal" then
t = t . base
end

return t and ( t . tag == "number" or t . tag == "integer" or t . tag == "string" or t . tag == "boolean" or t . tag == "nil" )
end

local function lookupConstant ( current , name ) 
while current do
local found = current . constants [ name ]
if found ~= nil then
return found or nil
end
current = current . parent
end

return nil
end

local function textPath ( node ) 
if not node or isToken ( node ) then
return nil
end
if node . kind == "name" and node . token then
return node . token . text
end
if node . kind == "dotIndex" and node . name then
local base = textPath ( node . obj )
return base and ( base .. "." .. node . name . text ) or nil
end

return nil
end

local function lookupPath ( current , path ) 




if not path then
return nil
end
local root = path : match ( "^[^.]+" )
while current do




local found = current . paths [ path ]
if found ~= nil then
return found or nil
end
if root and current . paths [ root ] == false then
return nil
end
current = current . parent
end

return nil
end

local function bindPath ( current , path , value ) 
if not path then
return
end


local prefix = path .. "."
for known in pairs ( current . paths ) do
if known == path or known : sub ( 1 , # prefix ) == prefix then
current . paths [ known ] = false
end
end
current . paths [ path ] = value or false
end

local function bindObjectFields ( current , path , value ) 
bindPath ( current , path , value )
if not value or value . kind ~= "table" then
return
end
for name , field in pairs ( value . fields ) do
bindObjectFields ( current , path .. "." .. name , field )
end
end

local function resolvedLiteral ( node ) 
local t = node and node . resolvedType
if not node or not node . immutablePath or not t or t . tag ~= "literal" then
return nil
end
if t . base
and ( t . base . tag == "number" or t . base . tag == "integer" )
and type ( t . constant ) == "number"
and t . constant == math . floor ( t . constant )
and math . abs ( t . constant ) <= 9007199254740991
then
return literal ( "number" , t . constant , ("%.0f") : format ( t . constant ) )
elseif t . base and t . base . tag == "string" and type ( t . constant ) == "string" then
return literal ( "string" , t . constant , quoteString ( t . constant ) )
elseif t . base and t . base . tag == "boolean" and type ( t . constant ) == "boolean" then
return literal ( "boolean" , t . constant , tostring ( t . constant ) )
end

return nil
end

local foldBlock , foldFunction








local function parenthesizeFoldedPrefix ( node ) 
if node and not isToken ( node ) and node . folded then
node . folded = "(" .. node . folded .. ")"
end
end


local function unfold ( node ) 
if not node or isToken ( node ) then
return
end
node . folded = nil
node . foldedExpression = nil
for _ , child in ipairs ( node ) do
unfold ( child )
end
end





local function parenthesizeFoldedNegative ( node ) 
if node and not isToken ( node ) and node . folded and node . folded : sub ( 1 , 1 ) == "-" then
node . folded = "(" .. node . folded .. ")"
end
end

local function foldExpr ( node , current ) 
if not node or isToken ( node ) then
return nil
end


node . folded = nil
node . foldedExpression = nil
local kind = node . kind
if kind == "number" then
local value = integerLiteral ( node )
if value then
node . folded = value . code
end
return value
elseif kind == "string" then
local value = stringLiteral ( node )
if value then
node . folded = value . code
end
return value
elseif kind == "nilExpr" then
node . folded = "nil"
return ( { kind = "nil" , value = nil , code = "nil" } )
elseif kind == "trueExpr" or kind == "falseExpr" then
local value = kind == "trueExpr"
node . folded = tostring ( value )
return literal ( "boolean" , value , node . folded )
elseif kind == "comptimeExpr" then
return comptimeLiteral ( node )
elseif kind == "name" and node . token then
local value = lookupConstant ( current , bindingKey ( node . token ) )
if value then
node . folded = value . code
end
return value or lookupPath ( current , node . token . text )
elseif kind == "paren" or kind == "castExpr" then
local value = foldExpr ( node . expr , current )
if value then
node . folded = value . code
end
return value
elseif kind == "unop" then
local value = foldExpr ( node . operand , current )
parenthesizeFoldedNegative ( node . operand )
if not value or not node . op then
return nil
end
local op = node . op . kind
if op == "not" then
local answer = literal ( "boolean" , not ( value . kind ~= "nil" and not ( value . kind == "boolean" and not value . value ) ) , tostring ( not ( value . kind ~= "nil" and not ( value . kind == "boolean" and not value . value ) ) ) )
node . folded = answer . code
return answer
elseif op == "-" and value . kind == "number" and value . value ~= 0 then
local answer = - value . value
if math . abs ( answer ) <= 9007199254740991 then
local folded = literal ( "number" , answer , ("%.0f") : format ( answer ) )
folded . float = value . float
node . folded = folded . code
return folded
end
elseif op == "#" and value . kind == "string" then
local folded = literal ( "number" , # value . value , tostring ( # value . value ) )
node . folded = folded . code
return folded
elseif op == "~" and value . kind == "number" then
local answer = bit . bnot ( value . value )
local folded = literal ( "number" , answer , ("%.0f") : format ( answer ) )
node . folded = folded . code
return folded
end
return nil
elseif kind == "binop" then
local left , right = foldExpr ( node . lhs , current ) , foldExpr ( node . rhs , current )
if not node . op then
return nil
end
local op = node . op . kind
if op == "^" then
parenthesizeFoldedNegative ( node . lhs )
end
if left and left . code and ( op == "and" or op == "or" or op == "??" ) then
local takeRight = op == "and" and ( left . kind ~= "nil" and not ( left . kind == "boolean" and not left . value ) )
or op == "or" and not ( left . kind ~= "nil" and not ( left . kind == "boolean" and not left . value ) )
or op == "??" and left . kind == "nil"
local selected = left
if takeRight then
selected = right


node . foldedExpression = node . rhs
end
if selected and selected . code then
node . folded = selected . code
return selected
end
return nil
end
if not left or not right then
return nil
end
if left . kind == "number" and right . kind == "number" then
if op == "/" and left . value == 0 then



unfold ( node . lhs )
unfold ( node . rhs )
return nil
end
local answer
if op == "+" then
answer = left . value + right . value
elseif op == "-" then
answer = left . value - right . value
elseif op == "*" then
answer = left . value * right . value
elseif op == "%" and right . value ~= 0 then
answer = left . value % right . value
elseif op == "//" and right . value ~= 0 then



answer = math . floor ( left . value / right . value )
elseif BITOPS [ op ] then
answer = BITOPS [ op ] ( left . value , right . value )
end





local float = not BITOPS [ op ] and ( op == "//" or left . float or right . float )
if answer == 0 and float then
unfold ( node . lhs )
unfold ( node . rhs )
return nil
end
if answer and math . abs ( answer ) <= 9007199254740991 then
local folded = literal ( "number" , answer , ("%.0f") : format ( answer ) )
folded . float = float or nil
node . folded = folded . code
return folded
end
elseif op == ".." and left . kind == "string" and right . kind == "string" then
local folded = literal ( "string" , left . value .. right . value , quoteString ( left . value .. right . value ) )
node . folded = folded . code
return folded
end



local scalar = left . kind ~= "table" and right . kind ~= "table"
local comparable = scalar and ( left . kind == right . kind or ( left . kind == "nil" or right . kind == "nil" ) )
if comparable and ( op == "==" or op == "~=" ) then
local equal = left . value == right . value
if op == "~=" then
equal = not equal
end
local folded = literal ( "boolean" , equal , tostring ( equal ) )
node . folded = folded . code
return folded
end
if left . kind == right . kind
and ( left . kind == "number" or left . kind == "string" )
and ( op == "<" or op == ">" or op == "<=" or op == ">=" )
then
local answer
if op == "<" then
answer = left . value < right . value
elseif op == ">" then
answer = left . value > right . value
elseif op == "<=" then
answer = left . value <= right . value
else
answer = left . value >= right . value
end
local folded = literal ( "boolean" , answer , tostring ( answer ) )
node . folded = folded . code
return folded
end
return nil
elseif kind == "call" or kind == "safeCall" then
foldExpr ( node . obj , current )
parenthesizeFoldedPrefix ( node . obj )






if nameText ( node . obj ) == "require" then
return nil
end
local arguments , allNumbers = { } , true
for _ , arg in ipairs ( node . args and node . args . exprs or { } ) do
local value = foldExpr ( arg , current )
arguments [ # arguments + 1 ] = value and value . value or nil
allNumbers = allNumbers and value ~= nil and value . kind == "number"
end
if node . scalarIntrinsic and allNumbers then
local answer = scalarIntrinsics . fold ( node . scalarIntrinsic , arguments )
if type ( answer ) == "number" and math . abs ( answer ) <= 9007199254740991 then
local numeric = answer
local folded = literal ( "number" , numeric , ("%.0f") : format ( numeric ) )
node . folded = folded . code
return folded
elseif type ( answer ) == "boolean" then
local folded = literal ( "boolean" , answer , tostring ( answer ) )
node . folded = folded . code
return folded
end
end
elseif kind == "methodCall" then
foldExpr ( node . obj , current )
parenthesizeFoldedPrefix ( node . obj )
for _ , arg in ipairs ( node . args and node . args . exprs or { } ) do
foldExpr ( arg , current )
end
elseif kind == "dotIndex" or kind == "safeIndex" then
foldExpr ( node . obj , current )
parenthesizeFoldedPrefix ( node . obj )
local value = resolvedLiteral ( node ) or lookupPath ( current , textPath ( node ) )
if value and value . kind ~= "table" then
node . folded = value . code
end
return value
elseif kind == "bracketIndex" or kind == "safeBracket" then
foldExpr ( node . obj , current )
parenthesizeFoldedPrefix ( node . obj )
foldExpr ( node . expr , current )
elseif kind == "tableExpr" then
local fields = { }
for _ , field in ipairs ( node . fields or { } ) do
foldExpr ( field . key , current )
local value = foldExpr ( field . value , current )
if field . kind == "fieldNamed" and field . isConst and field . name and value then
fields [ field . name . text ] = value
end
end
if next ( fields ) then
return { kind = "table" , fields = fields }
end
elseif kind == "istring" then
for _ , part in ipairs ( node . parts or { } ) do
foldExpr ( part , current )
end
elseif kind == "orExitExpr" then



foldExpr ( node . operand , current )
elseif kind == "doExpr" then
foldBlock ( node . body , scope ( current ) )
elseif kind == "switchExpr" then
foldExpr ( node . selector , current )
for _ , arm in ipairs ( node . cases or { } ) do
local inner = scope ( current )
for _ , value in ipairs ( arm . values or { } ) do
foldExpr ( value , current )
end
if arm . expr then
foldExpr ( arm . expr , inner )
elseif arm . body then
foldBlock ( arm . body , inner )
end
end
if node . elseCase then
local inner = scope ( current )
if node . elseCase . expr then
foldExpr ( node . elseCase . expr , inner )
elseif node . elseCase . body then
foldBlock ( node . elseCase . body , inner )
end
end
elseif kind == "funcExpr" then
if node . body then
foldFunction ( node . body , current )
end
elseif kind == "shortfn" then
local inner = scope ( current )
for _ , param in ipairs ( node . params or { } ) do
if param . name then
inner . constants [ bindingKey ( param . name ) ] = false
end
end
if node . expr then
foldExpr ( node . expr , inner )
end
if node . body then
foldBlock ( node . body , inner )
end
end

return nil
end

foldFunction = function ( body , current ) 
local inner = scope ( current )
for _ , param in ipairs ( body . params or { } ) do
if param . name then
inner . constants [ bindingKey ( param . name ) ] = false
end
end
if body . body then
foldBlock ( body . body , inner )
end
end

local function foldStatement ( stat , current ) 
local kind = stat . kind
if kind == "localStmt" then
local values = { }
for i , expr in ipairs ( stat . exprs or { } ) do
values [ i ] = foldExpr ( expr , current )
end
for i , name in ipairs ( stat . names or { } ) do
local known = stat . isConst or not stat . pattern and unchangedScalar ( name , values [ i ] , current )
current . constants [ ( name . definition or name . text ) ] = known and values [ i ] or false
if stat . isConst and values [ i ] and values [ i ] . kind == "table" then
bindObjectFields ( current , name . text , values [ i ] )
else
bindPath ( current , name . text , nil )
end
end
elseif kind == "assignStmt" then
local values = { }
for i , expr in ipairs ( stat . exprs or { } ) do
values [ i ] = foldExpr ( expr , current )
end
for i , target in ipairs ( stat . targets or { } ) do
local path = textPath ( target )
if target . kind == "name" and target . token then
current . constants [ bindingKey ( target . token ) ] = false
bindPath ( current , target . token . text , nil )
else
foldExpr ( target , current )
if stat . isConst and path then
local value = values [ i ]
if value and value . kind == "table" then
bindObjectFields ( current , path , value )
end
elseif path then
bindPath ( current , path , nil )
end
end
end
elseif kind == "returnStmt" then
for _ , expr in ipairs ( stat . exprs or { } ) do
foldExpr ( expr , current )
end
elseif kind == "callStmt" then
foldExpr ( stat . expr , current )
elseif kind == "compoundAssign" then
foldExpr ( stat . target , current )
foldExpr ( stat . value , current )
if stat . target and stat . target . kind == "name" and stat . target . token then
current . constants [ bindingKey ( stat . target . token ) ] = false
end
elseif kind == "yieldStmt" then
foldExpr ( stat . value , current )
elseif kind == "ifStmt" then
stat . constantBranch , stat . constantBranchNone = nil , nil
stat . constantClauses , stat . constantElse = nil , nil
local kept , selected , finished , changed , hasBinding = { } , nil , false , false , false
for _ , clause in ipairs ( stat . clauses or { } ) do
local condition = foldExpr ( clause . cond , current )
hasBinding = hasBinding or clause . binding ~= nil
if not finished then
if condition and condition . code and not clause . binding then
changed = true
if ( condition . kind ~= "nil" and not ( condition . kind == "boolean" and not condition . value ) ) then
selected , finished = clause . body , true
end
else
kept [ # kept + 1 ] = clause
end
end
if clause . body then
local inner = scope ( current )
if clause . binding then
inner . constants [ bindingKey ( clause . binding ) ] = false
bindPath ( inner , clause . binding . text , nil )
end
foldBlock ( clause . body , inner )
end
end
if stat . elseClause and stat . elseClause . body then
foldBlock ( stat . elseClause . body , scope ( current ) )
end
if not finished then
selected = stat . elseClause and stat . elseClause . body
end


if changed and not hasBinding then
if # kept == 0 then
stat . constantBranch = selected
stat . constantBranchNone = selected == nil
else
stat . constantClauses , stat . constantElse = kept , selected
end
end
elseif kind == "whileStmt" then
local condition = foldExpr ( stat . cond , current )
if stat . body then
foldBlock ( stat . body , scope ( current ) )
end



if condition and not ( condition . kind ~= "nil" and not ( condition . kind == "boolean" and not condition . value ) ) then
stat . constantLoopNone = true
end
elseif kind == "repeatStmt" then
local inner = scope ( current )
if stat . body then
foldBlock ( stat . body , inner )
end
foldExpr ( stat . cond , inner )
elseif kind == "doStmt" then
if stat . body then
foldBlock ( stat . body , scope ( current ) )
end
elseif kind == "fornumStmt" then
local from , to = foldExpr ( stat . start , current ) , foldExpr ( stat . stop , current )



local by = ( { kind = "number" , value = 1 , code = "1" } )
if stat . step then
by = foldExpr ( stat . step , current )
end





local function known ( value ) 
return value ~= nil and value . kind == "number"
end

if known ( from ) and known ( to ) and known ( by ) and by . value ~= 0 then
local runs = by . value > 0 and from . value <= to . value or by . value < 0 and from . value >= to . value
if not runs then
stat . constantLoopNone = true
end
end
local inner = scope ( current )
if stat . var then
inner . constants [ bindingKey ( stat . var ) ] = false
end
if stat . body then
foldBlock ( stat . body , inner )
end
elseif kind == "forinStmt" then
for _ , expr in ipairs ( stat . exprs or { } ) do
foldExpr ( expr , current )
end
local inner = scope ( current )
for _ , name in ipairs ( stat . names or { } ) do
inner . constants [ ( name . definition or name . text ) ] = false
end
if stat . body then
foldBlock ( stat . body , inner )
end
elseif kind == "localFuncStmt" then
if stat . name then
current . constants [ bindingKey ( stat . name ) ] = false
end
if stat . body then
foldFunction ( stat . body , current )
end
elseif kind == "funcStmt" or kind == "inlineMethod" then
if stat . body then
foldFunction ( stat . body , current )
end
elseif kind == "pragmaStmt" and stat . stat then
foldStatement ( stat . stat , current )
end
end

foldBlock = function ( block , current ) 
for _ , stat in ipairs ( block . stats or { } ) do
foldStatement ( stat , current )
end
end

local function constantFoldWalk ( node , writes ) 
if not node or isToken ( node ) then
return
end
if not writes then
writes = { }
writtenBindings ( node , writes )
end
if node . kind == "block" then
foldBlock ( node , scope ( nil , writes ) )
return
end
for _ , child in ipairs ( node ) do
constantFoldWalk ( child , writes )
end
end




local function deadScalarLocals ( root ) 
local candidates = { }
local declarations , uses = { } , { }

local function collect ( node , depth ) 
if not node then
return
end
if isToken ( node ) then
local definition = node . definition


if definition and definition . functionDepth and definition . functionDepth < depth then
uses [ definition ] = true
end
return
end
if NESTED_FUNCTION [ node . kind ] then
depth = depth + 1
end
node . deadScalarLocal = nil
if node . kind == "localStmt"
and not node . pattern
and not node . concatBuffer
and not node . exported
and # ( node . names or { } ) == 1
and # ( node . exprs or { } ) == 1
then
local name , value = node . names [ 1 ] , node . exprs [ 1 ]


if value . folded
and not value . folded : find ( "@requires-dynamically" , 1 , true )
and unchangedScalar ( name , { code = value . folded } , { writes = { } } )
then
candidates [ # candidates + 1 ] = node
declarations [ name ] = true
end
end
for _ , child in ipairs ( node ) do
collect ( child , depth )
end
end

local function visit ( node ) 
if not node then
return
end
if isToken ( node ) then
if node . definition and not declarations [ node ] then
uses [ node . definition ] = true
end
return
end
if node . folded or node . constantLoopNone then
return
end
if node . foldedExpression then
visit ( node . foldedExpression )
return
end
if node . kind == "ifStmt" and ( node . constantBranch or node . constantBranchNone ) then
visit ( node . constantBranch )
return
end
if node . constantClauses then
for _ , clause in ipairs ( node . constantClauses ) do
visit ( clause )
end
visit ( node . constantElse )
return
end
for _ , child in ipairs ( node ) do
visit ( child )
end
end

collect ( root , 0 )
visit ( root )
for _ , stat in ipairs ( candidates ) do
stat . deadScalarLocal = not uses [ stat . names [ 1 ] . definition ]
end
end





local function hasJumpScope ( block ) 
for _ , stat in ipairs ( block . stats or { } ) do
if stat . kind == "gotoStmt" or stat . kind == "labelStmt" then
return true
end
end

return false
end

local function directImmutableCall ( stat ) 
if stat . kind ~= "callStmt" then
return nil
end
local call = stat . expr
if not call or call . kind ~= "call" then
return nil
end
if call . ffiOutContracts
or call . ffiIntrinsic
or call . carrayElem
or call . cheaderCdef
or call . recordConstruct
or call . ownershipIntrinsic
or call . cdefCall
or call . tableIntrinsic
then
return nil
end



for _ , argument in ipairs ( call . args and call . args . loweredArgs or { } ) do
if argument . generatedKind == "field" and argument . source and argument . source . kind == "dotIndex" then
return nil
end
end
local callee = call . obj
local t = callee and callee . resolvedType
if not callee or callee . kind ~= "dotIndex" or not callee . immutablePath or not t or t . tag ~= "func" then
return nil
end

return textPath ( callee ) , call , callee
end

local function collectNames ( node , names ) 
if not node then
return
end
if isToken ( node ) then
if node . kind == "name" then
names [ node . text ] = true
end
return
end
for _ , child in ipairs ( node ) do
collectNames ( child , names )
end
end

local function staticCallableWalk ( root , remarks ) 
local usedNames = { }
collectNames ( root , usedNames )
local nextAlias = 0

local function aliasName ( ) 
repeat
nextAlias = nextAlias + 1
until not usedNames [ "__nupp_call_" .. nextAlias ]
local name = "__nupp_call_" .. nextAlias
usedNames [ name ] = true

return name
end

local visit
visit = function ( node ) 
if not node or isToken ( node ) then
return
end
if node . kind == "block" and not hasJumpScope ( node ) then
local counts = { }
for _ , stat in ipairs ( node . stats or { } ) do
local path = directImmutableCall ( stat )
if path then
counts [ path ] = ( counts [ path ] or 0 ) + 1
end
end
local aliases = { }
for _ , stat in ipairs ( node . stats or { } ) do
local path , call , callee = directImmutableCall ( stat )
if path and counts [ path ] and counts [ path ] >= 2 then
local alias = aliases [ path ]
if not alias then
alias = aliasName ( )
aliases [ path ] = alias
stat . callableBindings = { { name = alias , value = callee } }
remark (
remarks ,
callee ,
"OPT-4" ,
("static-callable: binds immutable callee %s once") : format ( path )
)
end
call . staticCallee = alias
end
end
end
for _ , child in ipairs ( node ) do
visit ( child )
end
end
visit ( root )
end








local function directViewUse ( node , parent ) 
if not parent then
return false
end
if parent . kind == "unop" then
return parent . indexedLength and parent . operand == node
elseif parent . kind == "bracketIndex" then
return parent . obj == node
and parent . indexedAccess ~= nil
and ( not parent . soaRow or parent . indexedDirectAccess == true )
elseif parent . kind == "localStmt" then
return parent . isConst and parent . exprs and parent . exprs [ 1 ] == node
end

return false
end




local function importedViewHelpers ( result , remarks ) 
local root = result . root
local resolveFact = root . resolveCallableFact
local block = root . blocks and root . blocks [ 1 ]
if not resolveFact or not block or not result . analysis then
return
end
local names , additions = { } , { }
collectNames ( root , names )
local serial = 0

local function visit ( node ) 
if not node or isToken ( node ) then
return
end
if node . kind == "call" and not node . unstableCall then
local callee = node . obj
local exact = callee
and (
callee . exactCallExport
or callee . kind == "name"
and callee . token
and callee . token . definition
and callee . token . definition . exactCallExport
)
local args = node . args and node . args . exprs
local eligible , hasView = args ~= nil , false
for _ , argument in ipairs ( args or { } ) do
if argument . kind ~= "name" then
eligible = false
end
local t = argument . resolvedType or argument . token and argument . token . inferredType
if t and indexedViews . describe ( t ) then
hasView = true
end
end
if exact and eligible and hasView then
local representation = resolveFact ( exact , "representation" )
local reason = representation and representation . reason
or not representation and "missing-representation-fact"
if not reason and # additions >= 4 then
reason = "body-budget"
end
if reason then
remark (
remarks ,
node ,
"OPT-6" ,
"view-scalar-replacement: declines imported " .. exact . identity .. " (" .. reason .. ")" ,
nil ,
"declined"
)
else
repeat
serial = serial + 1
until not names [ "__nupp_view_" .. serial ]
local name = "__nupp_view_" .. serial
local at = firstToken ( node )
local artifact = resolveFact ( exact , "viewBody" )
local declaration = at
and viewfacts . instantiate (
artifact ,
args ,
name ,
at ,
node . callBoundsProven ,
firstToken ( block ) or at
)
if declaration and at then
local token = {
kind = "name" ,
text = name ,
trivia = { } ,
line = at . line ,
col = at . col ,
offset = at . offset ,
definition = declaration . name . definition
}
local replacement = { token , kind = "name" , token = token }
for i , child in ipairs ( node ) do
if child == callee then
node [ i ] = replacement
end
end
node . obj , node . staticCallee = replacement , nil
additions [ # additions + 1 ] = declaration
remark (
remarks ,
node ,
"OPT-6" ,
"view-scalar-replacement: imports borrowed helper " .. exact . identity
)
else
remark (
remarks ,
node ,
"OPT-6" ,
"view-scalar-replacement: declines imported "
.. exact . identity
.. " (incompatible-view-abi)" ,
nil ,
"declined"
)
end
end
end
end
for _ , child in ipairs ( node ) do
visit ( child )
end
end

visit ( root )
root . importedViewDeclarations = additions
for i = # additions , 1 , -1 do
local declaration = additions [ i ]
table . insert ( block , 1 , declaration )
if block . stats ~= block then
table . insert ( block . stats , 1 , declaration )
end
result . analysis . bodies [ # result . analysis . bodies + 1 ] = declaration . body . body
end
end

local function indexedRangeWalk ( result , remarks ) 
for _ , body in ipairs ( result . analysis and result . analysis . bodies or { } ) do
local loops = { }
local ordered



= { }
local loopDepth = 0

local function collect ( node , parent ) 
if not node or isToken ( node ) or NESTED_FUNCTION [ node . kind ] then
return
end
if node . relationalAccess and node . rangeProvenNoRaise and node . indexedAccess then
node . indexedDirectAccess = true
local obligation = node . relationalAccess
local view = obligation . receiverDefinition and obligation . receiverDefinition . name or "view"
local index = obligation . indexDefinition and obligation . indexDefinition . name or "index"
remark (
remarks ,
node ,
"OPT-6" ,
"indexed-range: discharges inferred access bounds (1 <= " .. index .. " <= #" .. view .. ")"
)
end
local isLoop = node . kind == "whileStmt"
or node . kind == "fornumStmt"
or node . kind == "forinStmt"
or node . kind == "repeatStmt"
if isLoop then
loopDepth = loopDepth + 1
end
if node . kind == "bracketIndex" and node . rangeProvenNoRaise and node . indexedRangeAccess then
local proof = node . indexedRangeAccess
local loop = proof and proof . loop
if loop then
local entry = loops [ loop ]
if not entry then
entry = { loop = loop , accesses = { } , nested = loopDepth > 1 , }
loops [ loop ] = entry
ordered [ # ordered + 1 ] = entry
end
entry . accesses [ # entry . accesses + 1 ] = { node = node , parent = parent , }
end
end
for _ , child in ipairs ( node ) do
collect ( child , node )
end
if isLoop then
loopDepth = loopDepth - 1
end
end

collect ( body , nil )

for _ , entry in ipairs ( ordered ) do
local adapters = { }
local soaByView = { }
local soaBindings






= { }
local declinedNested = false
local loopDefinition = entry . loop . var and entry . loop . var . definition
for _ , found in ipairs ( entry . accesses ) do
local access = found . node
access . indexedDirectAccess = true
local adapter = access . indexedAccess and access . indexedAccess . adapter or "indexed"
adapters [ adapter ] = ( adapters [ adapter ] or 0 ) + 1










local view = access . soaRow and access . obj or nil
local index = access . soaRow and access . expr or nil
local field = found . parent and found . parent . soaField or nil
local viewDefinition = view and view . kind == "name" and view . token and view . token . definition or nil
local indexDefinition = index and index . kind == "name" and index . token and index . token . definition or nil
if field and entry . nested and not declinedNested then
declinedNested = true
remark (
remarks ,
entry . loop ,
"OPT-6" ,
"soa-loop-bindings: declines nested loop because repeated setup is left to LuaJIT hoisting" ,
nil ,
"declined"
)
end
if field
and not entry . nested
and viewDefinition
and indexDefinition
and indexDefinition == loopDefinition
then
local plan = soaByView [ viewDefinition ]
if not plan then
plan = {
view = view ,
viewDefinition = viewDefinition ,
index = index ,
indexDefinition = indexDefinition ,
fields = { } ,
fieldOrder = { } ,
}
soaByView [ viewDefinition ] = plan
soaBindings [ # soaBindings + 1 ] = plan
end
if not plan . fields [ field . ordinal ] then
plan . fields [ field . ordinal ] = true
plan . fieldOrder [ # plan . fieldOrder + 1 ] = field . ordinal
end
end
end
if # soaBindings > 0 then
for _ , plan in ipairs ( soaBindings ) do
table . sort ( plan . fieldOrder )
end
entry . loop . soaLoopBindings = soaBindings
end
local parts = { }
for adapter , count in pairs ( adapters ) do
parts [ # parts + 1 ] = ("%d %s access%s") : format ( count , adapter , count == 1 and "" or "es" )
end
table . sort ( parts )
remark ( remarks , entry . loop , "OPT-6" , "indexed-range: lowers " .. table . concat ( parts , ", " ) )
end





local candidates = { }
local byConstructor = { }

local function findCandidates ( node ) 
if not node or isToken ( node ) or NESTED_FUNCTION [ node . kind ] then
return
end
if node . kind == "localStmt" and # ( node . names or { } ) == 1 and # ( node . exprs or { } ) == 1 then
local constructor = node . exprs [ 1 ]
local producer = constructor and constructor . indexedViewProducer
if not producer and constructor and constructor . kind == "call" then
local exact = constructor . obj and constructor . obj . exactCallExport
local resultName = node . names [ 1 ]
local resultDefinition = resultName and resultName . definition
local resultType = resultName and resultName . inferredType
or resultDefinition and ( resultDefinition . inferredType or resultDefinition . type )
local root = exact
and resultType
and indexedViews . exportProducer ( exact . module , exact . member , resultType )
or nil
local producerArgs = constructor . args and constructor . args . exprs or { }
if root then
producer = { producer = root , source = producerArgs [ 1 ] , count = producerArgs [ 2 ] , }
constructor . indexedViewProducer = producer
end
end
local source = producer and producer . source or ( constructor and constructor . obj )
local operation = constructor and constructor . indexedViewOperation
if producer then
operation = {
kind = "root" ,
descriptor = producer . producer . descriptor ,
producer = producer . producer ,
}
end
if not operation
and constructor
and constructor . kind == "methodCall"
and constructor . name
and source
and source . kind == "name"
and source . token
then
local descriptor = indexedViews . describe ( source . token . inferredType )
if descriptor and constructor . name . text == "slice" then
operation = { kind = "slice" , descriptor = descriptor , }
elseif descriptor and constructor . name . text == "shared" then
operation = { kind = "shared" , descriptor = descriptor , }
end
end
if not operation and node . isConst and constructor and constructor . kind == "name" then
local token = constructor . token
local descriptor = indexedViews . describe (
token and ( token . inferredType or token . definition and token . definition . type )
)
if descriptor then
operation = { kind = "alias" , descriptor = descriptor , }
source = constructor
end
end
local args = constructor and constructor . args and constructor . args . exprs or { }
local definition = node . names [ 1 ] and node . names [ 1 ] . definition
if operation
and (
operation . kind == "root"
or operation . kind == "slice"
or operation . kind == "shared"
or operation . kind == "alias"
or operation . kind == "field"
)
and (
producer and producer . transport
or source and source . kind == "name" and source . token and source . token . definition
)
and ( operation . kind ~= "slice" or args [ 1 ] )
and ( node . isConst or operation . kind == "root" and operation . descriptor . writable )
and definition
then
local candidate = {
kind = operation . kind ,
definition = definition ,
constructor = constructor ,
source = source ,
sourceDefinition = source and source . token and source . token . definition or nil ,
first = args [ 1 ] ,
last = args [ 2 ] ,
descriptor = operation . descriptor ,
producer = operation . producer ,
count = producer and producer . count or nil ,
transport = producer and producer . transport or nil ,
ordinal = operation . ordinal ,
stat = node ,
admitted = true ,
dependencies = { } ,
}
candidates [ definition ] = candidate
byConstructor [ constructor ] = candidate
end
elseif node . kind == "withStmt" and # ( node . bindings or { } ) == 1 then
local binding = node . bindings [ 1 ]
local constructor = binding . expr
local producer = constructor and constructor . indexedViewProducer
local source = producer and producer . source
local definition = binding . name and binding . name . definition
if producer
and producer . producer . descriptor . writable
and source
and source . kind == "name"
and source . token
and source . token . definition
and definition
then
local candidate = {
kind = "root" ,
definition = definition ,
constructor = constructor ,
source = source ,
sourceDefinition = source . token . definition ,
descriptor = producer . producer . descriptor ,
producer = producer . producer ,
count = producer . count ,
stat = node ,
withBinding = binding ,
admitted = true ,
dependencies = { } ,
}
candidates [ definition ] = candidate
byConstructor [ constructor ] = candidate
end
end
for _ , child in ipairs ( node ) do
findCandidates ( child )
end
end

findCandidates ( body )






local function classify ( node , parent , ancestors ) 
if not node or isToken ( node ) then
return
end
if node . kind == "name" and node . token and candidates [ node . token . definition ] then
local candidate = candidates [ node . token . definition ]
local allowed = directViewUse ( node , parent )
if parent and parent . obj == node and parent . indexedViewOperation then
local child = byConstructor [ parent ]
if child then
candidate . dependencies [ child . definition ] = true
allowed = true
end
end
for _ , ancestor in ipairs ( ancestors ) do
if ancestor . kind == "call" and ancestor . ownershipIntrinsic == "drop" then
allowed = true
end
local transport = ancestor . kind == "call" and ancestor . indexedViewParameterTransport or nil
if transport then
for index in pairs ( transport . params ) do
if ancestor . args and ancestor . args . exprs and ancestor . args . exprs [ index ] == node then
allowed = true
end
end
end
if ancestor . kind == "call" and ancestor . indexedRangeCall then
for index = 3 , # ( ancestor . args and ancestor . args . exprs or { } ) do
if ancestor . args . exprs [ index ] == node then
allowed = true
end
end
end
end
if parent
and parent . kind == "callStmt"
and parent . expr
and parent . expr . ownershipIntrinsic == "drop"
then
allowed = true
end
if not allowed then
candidate . admitted = false
candidate . decline = parent and parent . kind or "escape"
end
end
ancestors [ # ancestors + 1 ] = node
for _ , child in ipairs ( node ) do
classify ( child , node , ancestors )
end
ancestors [ # ancestors ] = nil
end

classify ( body , nil , { } )

local changed = true
while changed do
changed = false
for _ , candidate in pairs ( candidates ) do
if candidate . admitted then
for dependency in pairs ( candidate . dependencies ) do
if not candidates [ dependency ] or not candidates [ dependency ] . admitted then
candidate . admitted = false
changed = true
do break end
end
end
end
end
end
for definition , candidate in pairs ( candidates ) do
if candidate . admitted then
definition . virtualIndexedView = candidate
if candidate . kind ~= "alias" then
candidate . constructor . virtualIndexedView = candidate
end
if candidate . withBinding then
candidate . withBinding . virtualIndexedView = candidate
end
local owner = candidate . stat . automaticOwners and candidate . stat . automaticOwners [ 1 ]
if owner then
owner . lowerable = false
end
remark (
remarks ,
candidate . constructor ,
"OPT-6" ,
"view-scalar-replacement: virtualizes one " .. candidate . kind .. (
candidate . kind == "root" and " (anchor=rooted-access)" or ""
)
)
else
remark (
remarks ,
candidate . constructor ,
"OPT-6" ,
"view-scalar-replacement: declines "
.. candidate . kind
.. " (unsupported-view-operation: "
.. tostring (
candidate . decline or "dependent-view-escapes"
) .. ")" ,
nil ,
"declined"
)
end
end
end
end

local function declineRecursiveViewTransports ( functions , ordered ) 
local state , stack , position = { } , { } , { }

local function visit ( definition ) 
local plan = functions [ definition ]
if not plan or state [ definition ] == 2 then
return
end
if state [ definition ] == 1 then
for index = position [ definition ] , # stack do
local recursive = functions [ stack [ index ] ]
recursive . admitted = false
recursive . decline = "recursive-call"
end
return
end
state [ definition ] = 1
stack [ # stack + 1 ] = definition
position [ definition ] = # stack
for callee in pairs ( plan . callees ) do
visit ( callee )
end
position [ definition ] = nil
stack [ # stack ] = nil
state [ definition ] = 2
end

for _ , plan in ipairs ( ordered ) do
visit ( plan . node . name . definition )
end
end




local function collectTransportReferences ( root , functions ) 
local function references ( node , parent , currentFunction ) 
if not node or isToken ( node ) then
return
end
local enclosing = currentFunction
if node . kind == "localFuncStmt" then
enclosing = node
end
if node . kind == "name" and node . token then
local plan = functions [ node . token . definition ]
if plan then
if parent and parent . kind == "call" and parent . obj == node then
local callerDefinition = enclosing and enclosing . name and enclosing . name . definition or nil
local caller = functions [ callerDefinition ]
if caller then
caller . callees [ node . token . definition ] = true
end
if enclosing == plan . node then
plan . admitted = false
plan . decline = "recursive-call"
else
plan . calls [ # plan . calls + 1 ] = parent
end
else
plan . admitted = false
plan . decline = "dynamic-call-boundary"
end
end
end
for _ , child in ipairs ( node ) do
references ( child , node , enclosing )
end
end

references ( root , nil , nil )
end





local function indexedViewReturnTransportWalk ( result , remarks ) 
local functions = { }
local ordered = { }

local function collect ( node ) 
if not node or isToken ( node ) then
return
end
if node . kind == "localFuncStmt" and node . name and node . body and node . body . body then
local stats = node . body . body . stats or { }
local terminal = stats [ # stats ]
local value = terminal
and terminal . kind == "returnStmt"
and # ( terminal . exprs or { } ) == 1
and terminal . exprs [ 1 ]
or nil
local producer = value and value . indexedViewProducer or nil
if producer
and producer . source
and producer . source . kind == "name"
and producer . source . token
and producer . source . token . definition
then
local plan = {
node = node ,
terminal = terminal ,
value = value ,
producer = producer ,
calls = { } ,
callees = { } ,
admitted = true ,
}
functions [ node . name . definition ] = plan
ordered [ # ordered + 1 ] = plan
end
end
for _ , child in ipairs ( node ) do
collect ( child )
end
end

collect ( result . root )

collectTransportReferences ( result . root , functions )
declineRecursiveViewTransports ( functions , ordered )

for _ , plan in ipairs ( ordered ) do
if plan . admitted and # plan . calls > 0 then
plan . node . indexedViewReturnTransport = plan
plan . terminal . indexedViewReturnTransport = plan
for _ , call in ipairs ( plan . calls ) do
call . indexedViewReturnTransport = plan
call . indexedViewProducer = { producer = plan . producer . producer , transport = true , }
remark ( remarks , call , "OPT-6" , "view-scalar-replacement: transports view through static call" )
end
else
remark (
remarks ,
plan . value ,
"OPT-6" ,
"view-scalar-replacement: declines static return (" .. tostring (
plan . decline or "no-static-caller"
) .. ")" ,
nil ,
"declined"
)
end
end
end

local function indexedViewParameterTransportPlan ( result , remarks ) 
local bindings = { }
local functions = { }
local ordered = { }

local function collect ( node ) 
if not node or isToken ( node ) then
return
end
if node . kind == "localStmt" and # ( node . names or { } ) == 1 and # ( node . exprs or { } ) == 1 then
local value = node . exprs [ 1 ]
local producer = value . indexedViewProducer
local operation = value . indexedViewOperation
if producer or operation then
bindings [
node . names [ 1 ] . definition
] = {
producer = producer and producer . producer or nil ,
source = producer and producer . source or value . obj ,
}
end
elseif node . kind == "localFuncStmt" and node . name and node . body and not node . indexedViewReturnTransport then
local params = { }
for index , param in ipairs ( node . body . params or { } ) do
local name = param . name
local descriptor = name
and indexedViews . describe ( name . inferredType or name . definition and name . definition . type )
if descriptor then
params [ index ] = { param = param , descriptor = descriptor , }
end
end
if next ( params ) then
local plan = { node = node , params = params , calls = { } , callees = { } , admitted = true , }
functions [ node . name . definition ] = plan
ordered [ # ordered + 1 ] = plan
end
end
for _ , child in ipairs ( node ) do
collect ( child )
end
end

collect ( result . root )

local function rootProducer ( definition , seen ) 
if not definition or seen [ definition ] then
return nil
end
seen [ definition ] = true
local binding = bindings [ definition ]
if not binding then
return nil
end
if binding . producer then
return binding . producer
end
local source = binding . source

return source and source . kind == "name" and source . token and rootProducer ( source . token . definition , seen ) or nil
end

collectTransportReferences ( result . root , functions )
declineRecursiveViewTransports ( functions , ordered )

local planned = { }
for _ , plan in ipairs ( ordered ) do
local parameterDefinitions = { }
for _ , paramPlan in pairs ( plan . params ) do
parameterDefinitions [ paramPlan . param . name . definition ] = true
end

local function validateUses ( node , parent ) 
if not node or isToken ( node ) or node ~= plan . node and NESTED_FUNCTION [ node . kind ] then
return
end
if node . kind == "name" and node . token and parameterDefinitions [ node . token . definition ] then
local allowed = directViewUse ( node , parent )
allowed = allowed or parent and parent . obj == node and parent . indexedViewOperation ~= nil
if not allowed then
plan . admitted = false
plan . decline = "unsupported-view-operation"
end
end
for _ , child in ipairs ( node ) do
validateUses ( child , node )
end
end

validateUses ( plan . node , nil )
if plan . admitted and # plan . calls > 0 then
for index , paramPlan in pairs ( plan . params ) do
local selected
for _ , call in ipairs ( plan . calls ) do
local argument = call . args and call . args . exprs and call . args . exprs [ index ]
local producer = argument
and argument . kind == "name"
and argument . token
and rootProducer ( argument . token . definition , { } )
or nil
if not producer
or producer . descriptor . adapter ~= paramPlan . descriptor . adapter
or producer . descriptor . writable ~= paramPlan . descriptor . writable
or selected and selected . kind ~= producer . kind
then
plan . admitted = false
plan . decline = "incompatible-view-abi"
do break end
end
selected = selected or producer
end
paramPlan . producer = selected
if not plan . admitted then
do break end
end
end
else
plan . admitted = false
plan . decline = plan . decline or "no-static-caller"
end
if plan . admitted then
for _ , paramPlan in pairs ( plan . params ) do
local definition = paramPlan . param . name . definition
local view = {
kind = "root" ,
descriptor = paramPlan . descriptor ,
producer = paramPlan . producer ,
parameterTransport = true ,
}
definition . virtualIndexedView = view
paramPlan . param . indexedViewParameterTransport = view
end
for _ , call in ipairs ( plan . calls ) do
call . indexedViewParameterTransport = plan
end
planned [ # planned + 1 ] = plan
else
remark (
remarks ,
plan . node ,
"OPT-6" ,
"view-scalar-replacement: declines static parameter (" .. tostring ( plan . decline ) .. ")" ,
nil ,
"declined"
)
end
end

return planned
end

local function finalizeIndexedViewParameterTransport ( plans , remarks ) 
for _ , plan in ipairs ( plans ) do
local admitted = true
for index in pairs ( plan . params ) do
for _ , call in ipairs ( plan . calls ) do
local argument = call . args and call . args . exprs and call . args . exprs [ index ]
local definition = argument and argument . kind == "name" and argument . token and argument . token . definition
or nil
if not definition or not definition . virtualIndexedView then
admitted = false
end
end
end
if admitted then
for _ , call in ipairs ( plan . calls ) do
remark ( remarks , call , "OPT-6" , "view-scalar-replacement: transports view through static call" )
end
else
for _ , paramPlan in pairs ( plan . params ) do
paramPlan . param . name . definition . virtualIndexedView = nil
paramPlan . param . indexedViewParameterTransport = nil
end
for _ , call in ipairs ( plan . calls ) do
call . indexedViewParameterTransport = nil
end
remark (
remarks ,
plan . node ,
"OPT-6" ,
"view-scalar-replacement: declines static parameter (dependent-view-escapes)" ,
nil ,
"declined"
)
end
end
end









local INLINE_MAX_CALL_GROWTH = 64
local INLINE_MAX_CALLER_GROWTH = 512


local INLINE_MAX_DUPLICATED_OPS = 1

























local function fieldNameTokens ( node , found ) 
if not node or isToken ( node ) then
return found
end
local kind = node . kind
if ( kind == "dotIndex" or kind == "methodCall" or kind == "fieldNamed" ) and node . name then
found [ node . name ] = true
end
for _ , child in ipairs ( node ) do
fieldNameTokens ( child , found )
end

return found
end


local function referencedNames ( node , found , fields ) 
if not node or node . kind == "annotationApply" then
return found
end
if isToken ( node ) then
if node . kind == "name" and not fields [ node ] then
found [ node . text ] = true
end

return found
end
for _ , child in ipairs ( node ) do
referencedNames ( child , found , fields )
end

return found
end




local SPLICE_ANNOTATION_DEPTH = 3









local spliceCopy
local spliceTree
spliceTree = function ( node , subs , at , params , copies , owned ) 
if isToken ( node ) then
local copied = { }
for key , value in pairs ( node ) do
copied [ key ] = value
end
copied . line = at . line
copied . col = at . col
copied . offset = at . offset
copies [ node ] = copied

return copied
end
if node . kind == "name" and node . token and subs [ node . token . text ] then


if node . token . definition == params [ node . token . text ] then
local copied = spliceCopy ( subs [ node . token . text ] , { } , at , { } )




if copied . kind == "binop" or copied . kind == "unop" or copied . kind == "castExpr" then
local open = { kind = "(" , text = "(" , trivia = "" , line = at . line , col = at . col , offset = at . offset }
local close = { kind = ")" , text = ")" , trivia = "" , line = at . line , col = at . col , offset = at . offset }
copied = { open , copied , close , kind = "paren" , expr = copied , inferredType = copied . inferredType }
end
copies [ node ] = copied

return copied
end
end

local copied = { }
for index , child in ipairs ( node ) do
copied [ index ] = spliceTree ( child , subs , at , params , copies , owned )
end
copies [ node ] = copied
owned [ # owned + 1 ] = node

return copied
end











local function spliceField ( value , copies , depth ) 
if type ( value ) ~= "table" then
return value
end
local copied = copies [ value ]
if copied then
return copied
end
if isToken ( value ) or rawget ( value , "kind" ) ~= nil or rawget ( value , "tag" ) ~= nil then
return value
end
if depth >= 3 or getmetatable ( value ) ~= nil then
return value
end
local result = value
for key , entry in pairs ( value ) do
local freshKey , fresh = spliceField ( key , copies , depth + 1 ) , spliceField ( entry , copies , depth + 1 )
if freshKey ~= key or fresh ~= entry then
if result == value then
result = { }
for k , v in pairs ( value ) do
result [ k ] = v
end
end
result [ key ] = nil
result [ freshKey ] = fresh
end
end

return result
end





spliceCopy = function ( node , subs , at , params ) 
local copies , owned = { } , { }
local root = spliceTree ( node , subs , at , params , copies , owned )
for _ , original in ipairs ( owned ) do
local copied = copies [ original ]
for key , value in pairs ( original ) do
if type ( key ) ~= "number" then
copied [ key ] = spliceField ( value , copies , 0 )
end
end
end

return root
end






local function prefixParameters ( node , params , found ) 
if not node or isToken ( node ) then
return found
end
local kind = node . kind
if kind == "dotIndex" or kind == "methodCall" or kind == "bracketIndex" or kind == "call" then
local base = node . obj
local name = base and not isToken ( base ) and base . kind == "name" and base . token and base . token . text or nil
if name and params [ name ] then
found [ name ] = true
end
end
for _ , child in ipairs ( node ) do
prefixParameters ( child , params , found )
end

return found
end






local function substitutableArgument ( node ) 
if not node or isToken ( node ) then
return false
end
local kind = node . kind

if kind == "name" and node . token ~= nil
or kind == "number"
or kind == "string"
or kind == "nilExpr"
or kind == "trueExpr"
or kind == "falseExpr"
then
return true
elseif kind == "paren" or kind == "castExpr" then
return substitutableArgument ( node . expr )
elseif kind == "unop" then
return node . op ~= nil and node . op . kind ~= "#" and substitutableArgument ( node . operand )
elseif kind == "binop" then
return node . op ~= nil
and node . op . kind ~= ".."
and substitutableArgument ( node . lhs )
and substitutableArgument ( node . rhs )
end

return false
end


local function callParens ( args ) 
local open , close = nil , nil
for _ , child in ipairs ( args or { } ) do
if isToken ( child ) and child . text == "(" and not open then
open = child
elseif isToken ( child ) and child . text == ")" then
close = child
end
end

return open , close
end



local function inlineArgumentWork ( node ) 
if not node or isToken ( node ) or node . folded then
return 0
end
if node . kind == "paren" or node . kind == "castExpr" then
return inlineArgumentWork ( node . expr )
elseif node . kind == "unop" then
return 1 + inlineArgumentWork ( node . operand )
elseif node . kind == "binop" then
return 1 + inlineArgumentWork ( node . lhs ) + inlineArgumentWork ( node . rhs )
end

return 0
end








local function measureInline ( node , measured ) 
if not node
or isToken ( node )
or measured . size > measured . limit
or measured . duplicated > 1
then
return
end
local kind = node . kind
if kind == "paren" or kind == "castExpr" then
measureInline ( node . expr , measured )
return
end
local argument = kind == "name" and node . token and measured . arguments [ node . token . text ] or nil
if argument then
local uses = measured . uses [ node . token . text ] or 0
measured . uses [ node . token . text ] = uses + 1
measured . size = measured . size + argument . size
if uses > 0 then
measured . duplicated = measured . duplicated + argument . work
end
return
end
measured . size = measured . size + 1
if kind == "args" and node . exprs then
for _ , child in ipairs ( node . exprs ) do
measureInline ( child , measured )
end
elseif kind == "newExpr" then
measureInline ( node . call , measured )
elseif kind == "call" or kind == "methodCall" then
measureInline ( node . obj , measured )
measureInline ( node . args , measured )
elseif kind == "namedArg" or kind == "fieldNamed" or kind == "fieldItem" then
measureInline ( node . value , measured )
elseif kind == "fieldBracket" then
measureInline ( node . key , measured )
measureInline ( node . value , measured )
else
for _ , child in ipairs ( node ) do
measureInline ( child , measured )
end
end
end

local function inlineMeasure ( node , arguments , limit ) 
local measured = { size = 0 , duplicated = 0 , uses = { } , arguments = arguments or { } , limit = limit }
measureInline ( node , measured )
return measured
end



local function inlineDecision ( node , helper , subs , callerGrowth ) 
local arguments = { }
for _ , param in ipairs ( helper . params ) do
local argument = subs [ param ]
arguments [ param ] = { size = inlineMeasure ( argument , nil , math . huge ) . size , work = inlineArgumentWork ( argument ) , }
end
local before = inlineMeasure ( node , nil , math . huge ) . size
local remaining = 512 - callerGrowth
local allowance = math . min ( 64 , remaining )
local measured = inlineMeasure ( helper . expr , arguments , before + allowance )
if measured . duplicated > 1 then
return nil , ("duplicates argument computation; allowance %d operations") : format ( 1 )
end
local growth = math . max ( 0 , measured . size - before )
if growth > allowance then
if remaining < 64 then
return nil , ("caller growth would exceed %d nodes (%d already used)")

: format ( 512 , callerGrowth )
end
return nil , ("call growth would exceed %d nodes") : format ( 64 )
end

return growth
end



local function hasInlineScope ( node ) 
if not node or isToken ( node ) then
return false
end
if node . kind == "doExpr" or node . kind == "funcExpr" or node . kind == "shortfn" or node . kind == "orExitExpr" then
return true
end
for _ , child in ipairs ( node ) do
if hasInlineScope ( child ) then
return true
end
end

return false
end




local function observesFrames ( node , free ) 
if free . debug or free . getfenv or free . setfenv then
return true
end
local found = false

local function walk ( at ) 
if found or not at or isToken ( at ) then
return
end
if at . kind == "call" and nameText ( at . obj ) == "error" and at . args and # ( at . args . exprs or { } ) > 1 then
found = true
return
end
for _ , child in ipairs ( at ) do
walk ( child )
end
end

walk ( node )

return found
end


local function inlinableHelpers ( root ) 
local found = { }
for _ , block in ipairs ( root . blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
if stat . kind == "localFuncStmt" and stat . name and stat . name . definition and stat . body then
local body = stat . body
local stats = body . body and body . body . stats or { }
local returned = stats [ 1 ]
local single = # stats == 1
and returned
and returned . kind == "returnStmt"
and returned . exprs
and # returned . exprs == 1



local expr = single and returned . exprs [ 1 ] or nil
local multi = expr ~= nil
and ( expr . kind == "call" or expr . kind == "methodCall" or expr . kind == "vararg" )
if multi and ( body . rets == nil or # body . rets ~= 1 ) then
single = false
end
if single and not body . varargParam and not body . generics and not hasInlineScope ( expr ) then
local params = { }
local definitions = { }
local ok = true
for _ , param in ipairs ( body . params or { } ) do
local name = param . name and param . name . text or nil
if not name or param . modeTok or param . vararg or param . constTok or not param . name . definition then
ok = false
else
params [ # params + 1 ] = name
definitions [ name ] = param . name . definition
end
end
local expr = returned . exprs [ 1 ]
local free = referencedNames ( expr , { } , fieldNameTokens ( expr , { } ) )
for _ , name in ipairs ( params ) do
free [ name ] = nil
end



if ok
and expr
and not free [ stat . name . text ]
and not free . self
and not observesFrames ( expr , free )
then
local named = { }
for _ , name in ipairs ( params ) do
named [ name ] = true
end
found [
stat . name . text
] = {
definition = stat . name . definition ,
params = params ,
definitions = definitions ,
expr = expr ,
free = free ,
prefix = prefixParameters ( expr , named , { } ) ,
}
end
end
end
end
end

return found
end



local function dropReassigned ( node , candidates ) 
if not node or isToken ( node ) then
return
end
if node . kind == "assignStmt" then
for _ , target in ipairs ( node . targets or { } ) do
local name = nameText ( target )
if name then
candidates [ name ] = nil
end
end
end
for _ , child in ipairs ( node ) do
dropReassigned ( child , candidates )
end
end




local function dropRebound ( root , candidates ) 
local declared = { }
for _ , block in ipairs ( root . blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
if stat . kind == "localStmt" then
for _ , name in ipairs ( stat . names or { } ) do
declared [ name . text ] = ( declared [ name . text ] or 0 ) + 1
end
elseif stat . kind == "localFuncStmt" and stat . name then
declared [ stat . name . text ] = ( declared [ stat . name . text ] or 0 ) + 1
end
end
end
for name , helper in pairs ( candidates ) do
if ( declared [ name ] or 0 ) > 1 then
candidates [ name ] = nil
else
for free in pairs ( helper . free ) do
if ( declared [ free ] or 0 ) > 1 then
candidates [ name ] = nil
end
end
end
end
end




local SCOPE_NODES = { block = true , funcbody = true , shortfn = true , fornumStmt = true , forinStmt = true , }






local function declarationScopes ( root ) 
local scopes = { }
local stack = { }

local function visit ( node , parent ) 
if isToken ( node ) then
local definition = node . kind == "name" and node . definition or nil
if definition and definition . token == node then
local owner = stack [ # stack ]
local first = owner and firstToken ( owner ) or nil
local last = owner and cst . lastToken ( owner ) or nil
local list = scopes [ node . text ]
if not list then
list = { }
scopes [ node . text ] = list
end
list [
# list + 1
] = {
definition = definition ,
at = node . offset or 0 ,
from = first and first . offset or 0 ,
to = last and last . offset and ( last . offset + # ( last . text or "" ) ) or math . huge ,
}
end
return
end
local owner = SCOPE_NODES [ node . kind ] and node or nil
if owner and node . kind == "block" and parent and parent . kind == "repeatStmt" then
owner = parent
end
if owner then
stack [ # stack + 1 ] = owner
end
for _ , child in ipairs ( node ) do
visit ( child , node )
end
if owner then
stack [ # stack ] = nil
end
end

visit ( root , nil )

return scopes
end




local function freeReads ( helper ) 
local fields = fieldNameTokens ( helper . expr , { } )
local reads = { }

local function walk ( node ) 
if not node or node . kind == "annotationApply" then
return
end
if isToken ( node ) then
if node . kind == "name" and not fields [ node ] then
local param = helper . definitions [ node . text ]
if param == nil or node . definition ~= param then
reads [ # reads + 1 ] = node
end
end
return
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

walk ( helper . expr )

return reads
end





local function sameBindingAt ( scopes , text , definition , offset ) 
for _ , declared in ipairs ( scopes [ text ] or { } ) do
if declared . definition ~= definition
and declared . at < offset
and declared . from <= offset
and offset < declared . to
then
return false
end
end

return true
end



local function makesCall ( node ) 
if not node or isToken ( node ) then
return false
end
local kind = node . kind
if kind == "call" or kind == "methodCall" or kind == "safeCall" or kind == "newExpr" then
return true
end
for _ , child in ipairs ( node ) do
if makesCall ( child ) then
return true
end
end

return false
end


local function readsWrittenBinding ( node , writes ) 
if not node or isToken ( node ) then
return false
end
if node . kind == "name" and node . token then
return writes [ bindingKey ( node . token ) ] == true or writes [ node . token . text ] == true
end
for _ , child in ipairs ( node ) do
if readsWrittenBinding ( child , writes ) then
return true
end
end

return false
end




local function numericOperands ( node ) 
if not node or isToken ( node ) then
return false
end
local kind = node . kind
if kind == "number" then
return true
elseif kind == "name" and node . token then
local t = node . token . inferredType
if t and t . tag == "literal" then
t = t . base
end
return t ~= nil and ( t . tag == "number" or t . tag == "integer" or t . tag == "float" )
elseif kind == "paren" or kind == "castExpr" then
return numericOperands ( node . expr )
elseif kind == "unop" then
return numericOperands ( node . operand )
elseif kind == "binop" then
return numericOperands ( node . lhs ) and numericOperands ( node . rhs )
end

return false
end



local function inlineReturnHelperWalk ( result , remarks ) 
local root = result . root
local candidates = inlinableHelpers ( root )
dropReassigned ( root , candidates )
dropRebound ( root , candidates )
local byDefinition = { }
for name , helper in pairs ( candidates ) do
helper . name = name
byDefinition [ helper . definition ] = helper
end
local scopes = declarationScopes ( root )
local writes = { }
writtenBindings ( root , writes )

local changed = false
local callerGrowth = 0



local statementCalls = { }
local walkNode


local function helperFor ( node ) 
if node . kind ~= "call" or not node . obj or not node . args or statementCalls [ node ] then
return nil
end


if node . ffiOutContracts
or node . ffiIntrinsic
or node . carrayElem
or node . cheaderCdef
or node . recordConstruct
or node . ownershipIntrinsic
or node . cdefCall
or node . tableIntrinsic
or node . requiredModule
then
return nil
end
local callee = node . obj
local token = not isToken ( callee ) and callee . kind == "name" and callee . token or nil
local helper = token and token . definition and byDefinition [ token . definition ] or nil
if not helper then
local exact = callee . exactCallExport or token and token . definition and token . definition . exactCallExport
local resolveFact = ( root ) . resolveCallableFact
local args = node . args . exprs
if not exact or not resolveFact or not args or node . unstableCall then
return nil
end
for _ , argument in ipairs ( args ) do
if not substitutableArgument ( argument ) then
remark (
remarks ,
node ,
"OPT-7" ,
"inline-return-helper: declines imported "
.. exact . identity
.. " (argument-effects-or-representation)" ,
nil ,
"declined"
)
return nil
end
end
local eligibility = resolveFact ( exact , "inlineEligibility" )
if not eligibility or eligibility . reason or eligibility . parameters ~= # args then
remark (
remarks ,
node ,
"OPT-7" ,
"inline-return-helper: declines imported " .. exact . identity .. " (" .. tostring (
eligibility and eligibility . reason or "missing-body-fact"
) .. ")" ,
nil ,
"declined"
)
return nil
end
local at = firstToken ( node )
helper = at and inlinefacts . instantiate ( resolveFact ( exact , "inlineBody" ) , at )
if not helper then
return nil
end
helper . name = exact . identity
end
local at = firstToken ( node )
local offset = at and at . offset
if not offset then
return nil
end
for _ , read in ipairs ( freeReads ( helper ) ) do
if not sameBindingAt ( scopes , read . text , read . definition , offset ) then
return nil
end
end
local args = node . args . exprs
if not args or # args ~= # helper . params or node . args . table or node . args . str or node . args . typeArg then
return nil
end


local calls = makesCall ( helper . expr )
local subs = { }
for position , param in ipairs ( helper . params ) do
local argument = args [ position ]
if not substitutableArgument ( argument ) then
return nil
end
if helper . prefix [ param ] and argument . kind ~= "name" then
return nil
end
if calls and readsWrittenBinding ( argument , writes ) then
return nil
end
local kind = argument . kind
if ( kind == "binop" or kind == "unop" ) and not numericOperands ( argument ) then
return nil
end
subs [ param ] = argument
end

return helper , subs , helper . name
end



local function inlineInto ( node , helper , subs ) 
local open , close = callParens ( node . args )
if not open or not close then
return false
end
local at = firstToken ( node )
if not at then
return false
end
local spliced = spliceCopy ( helper . expr , subs , at , helper . definitions )
local inferred , resolved = node . inferredType , node . resolvedType
for key in pairs ( node ) do
node [ key ] = nil
end
node [ 1 ] , node [ 2 ] , node [ 3 ] = open , spliced , close
node . kind = "paren"
node . expr = spliced
node . inferredType = inferred
node . resolvedType = resolved

return true
end

walkNode = function ( node ) 
if not node or isToken ( node ) then
return
end
local kind = node . kind
if kind == "callStmt" then
if node . expr then
statementCalls [ node . expr ] = true
end
for _ , child in ipairs ( node ) do
walkNode ( child )
end

return
elseif kind == "call" then
for _ , child in ipairs ( node ) do
walkNode ( child )
end
local helper , subs , name = helperFor ( node )
if helper then
local growth , reason = inlineDecision ( node , helper , subs , callerGrowth )
if growth == nil then
remark (
remarks ,
node ,
"OPT-7" ,
("inline-return-helper: keeps %s: %s") : format ( name , reason ) ,
nil ,
"declined"
)
elseif inlineInto ( node , helper , subs ) then
callerGrowth = callerGrowth + growth
changed = true
remark ( remarks , node , "OPT-7" , ("inline-return-helper: inlines %s") : format ( name ) )
end
end

return
elseif kind == "funcbody" or kind == "shortfn" then
local enclosingGrowth = callerGrowth
callerGrowth = 0
for _ , child in ipairs ( node ) do
walkNode ( child )
end
callerGrowth = enclosingGrowth

return
end
for _ , child in ipairs ( node ) do
walkNode ( child )
end
end

for _ , block in ipairs ( root . blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
walkNode ( stat )
end
end

return changed
end









local function constMonomorphizeWalk ( result , remarks , selection , selectedFilename ) 



local filename = selectedFilename or "<source>"
local accepted , declined
if selection ~= nil then
accepted , declined = selection . accepted , selection . declined
else
local plans = constspecialize . collect ( result , filename )
accepted , declined = constspecialize . select ( plans )
end
local acceptedByOwner = { }
local aliasesByOwner = { }
for _ , specialization in ipairs ( accepted ) do
local owner = specialization . owner
if owner . filename == filename then
local aliases = aliasesByOwner [ owner ]
if aliases == nil then
aliases = { }
aliasesByOwner [ owner ] = aliases
end
aliases [ # aliases + 1 ] = specialization
if specialization . physical == specialization then
local bodies = acceptedByOwner [ owner ]
if bodies == nil then
bodies = { }
acceptedByOwner [ owner ] = bodies
end
bodies [ # bodies + 1 ] = specialization
end
end
for _ , call in ipairs ( specialization . calls ) do
if specialization . callFiles [ call ] == filename then
call . constSpecialization = specialization
call . constSpecializationExternal = owner . filename ~= filename
remark ( remarks , call , "OPT-8" , "const-monomorphize: calls private " .. specialization . name )
end
end
end

local function byConstKey ( a , b ) 
return a . key < b . key
end



local emittedBodies = 0
for owner , bodies in pairs ( acceptedByOwner ) do
table . sort ( bodies , byConstKey )
owner . declaration . constSpecializations = bodies
owner . declaration . constSpecializationAliases = aliasesByOwner [ owner ]
emittedBodies = emittedBodies + # bodies
end
for _ , specialization in ipairs ( declined ) do
for _ , call in ipairs ( specialization . calls ) do
if specialization . callFiles [ call ] == filename then
remark (
remarks ,
call ,
"OPT-8" ,
("const-monomorphize: declines body because this module already selected %d body classes")

: format ( constspecialize . maxBodiesPerModule ) ,
nil ,
"declined"
)
end
end
end

return emittedBodies
end


































function optimize . run ( result , opts ) 
opts = opts or { }
local level = opts . level or 0
if level > 0 then
checkpoint . prepare ( result )
else
checkpoint . restore ( result )
end
local disabled = opts . disabled or { }
local remarks = { }
local factRoot = result . root
for key in pairs ( factRoot . optimizationDependencies or { } ) do
factRoot . optimizationDependencies [ key ] = nil
end
if level >= optimize . passes [ "OPT-1" ] . level and not disabled [ "OPT-1" ] then
walk ( result . root , remarks )
end
if level >= optimize . passes [ "OPT-2" ] . level and not disabled [ "OPT-2" ] then
numericIpairsWalk ( result , remarks )
end
if level >= optimize . passes [ "OPT-3" ] . level and not disabled [ "OPT-3" ] then
constantFoldWalk ( result . root )
end
if level >= optimize . passes [ "OPT-4" ] . level and not disabled [ "OPT-4" ] then
staticCallableWalk ( result . root , remarks )
end
if level >= optimize . passes [ "OPT-5" ] . level and not disabled [ "OPT-5" ] and result . compat ~= "lua51" then
concatBufferWalk ( result , remarks )
end
if level >= optimize . passes [ "OPT-6" ] . level and not disabled [ "OPT-6" ] then
importedViewHelpers ( result , remarks )
indexedViewReturnTransportWalk ( result , remarks )
local parameterTransports = indexedViewParameterTransportPlan ( result , remarks )
indexedRangeWalk ( result , remarks )
finalizeIndexedViewParameterTransport ( parameterTransports , remarks )
end
if level >= optimize . passes [ "OPT-7" ] . level and not disabled [ "OPT-7" ] then
local inlined = inlineReturnHelperWalk ( result , remarks )
if inlined and not disabled [ "OPT-3" ] then
constantFoldWalk ( result . root )
end
end
local specializedBodies = 0
if level >= optimize . passes [ "OPT-8" ] . level and not disabled [ "OPT-8" ] then
specializedBodies = constMonomorphizeWalk ( result , remarks , opts . constSelection , opts . filename )
end
if level >= optimize . passes [ "OPT-3" ] . level and not disabled [ "OPT-3" ] then
deadScalarLocals ( result . root )
end
for _ , entry in ipairs ( remarks ) do
entry . filename = opts . filename
end

return remarks , specializedBodies
end


optimize.AllocationSite = {} optimize.AllocationSite.__index = optimize.AllocationSite ;_G.nupp.__reflect.link(optimize.AllocationSite,__nuppT1[1],{ })























function optimize . allocationSites ( result ) 
local sites = { }

local function visit ( node ) 
if not node or isToken ( node ) then
return
end
if node . constantLoopNone then
return
end
if node . kind == "ifStmt" and ( node . constantBranch or node . constantBranchNone ) then
if node . constantBranch then
visit ( node . constantBranch )
end

return
end
if node . comptimeValue or node . folded then
return
end
if node . foldedExpression then
visit ( node . foldedExpression )
return
end
if node . constantClauses then
for _ , clause in ipairs ( node . constantClauses ) do
visit ( clause )
end
visit ( node . constantElse )
return
end
local kind = nil
if node . kind == "tableExpr" then
kind = "table"
elseif node . kind == "shortfn" or node . kind == "funcbody" then



kind = "closure"
end
if kind then
local token = firstToken ( node )
sites [
# sites + 1
] = _G.setmetatable({ kind =
kind ,  line =
token and token . line or 0 ,  col =
token and token . col or 0 }, optimize.AllocationSite)

end
for _ , child in ipairs ( node ) do
visit ( child )
end
end

visit ( result . root )

return sites
end




function optimize . liveEffects ( result ) 
local effects = { }

local function visit ( node ) 
if not node or isToken ( node ) then
return
end
if node . constantLoopNone then
return
end
if node . kind == "ifStmt" and ( node . constantBranch or node . constantBranchNone ) then
if node . constantBranch then
visit ( node . constantBranch )
end
return
end
if node . materializedIR then
for _ , effect in ipairs (
node . materializationObservation and node . materializationObservation . runtimeFeatures or { }
) do
effects [ effect ] = true
end
return
end
if node . comptimeValue or node . folded then
return
end
if node . foldedExpression then
visit ( node . foldedExpression )
return
end
if node . constantClauses then
for _ , clause in ipairs ( node . constantClauses ) do
visit ( clause )
end
visit ( node . constantElse )
return
end
if node . compilerFeatureEffect then
effects [ node . compilerFeatureEffect ] = true
end
for _ , effect in ipairs ( node . compilerFeatureEffects or { } ) do
effects [ effect ] = true
end
for _ , child in ipairs ( node ) do
visit ( child )
end
end

visit ( result . root )

return effects
end

local __nuppExportValue= optimize ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.lua.optimize"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.lua.optimize"]=__nuppExports;return __nuppExports