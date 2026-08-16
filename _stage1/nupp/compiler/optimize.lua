_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);



















local cst = require ( "nupp.compiler.cst" )

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
] = { name = "concat-buffer" , level = 1 , summary = "build a string accumulated round a loop with a string.buffer" , } ,
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
or # (
stat . targets or { }
) ~= 1 or # ( stat . exprs or { } ) ~= 1 then
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
for j = at + 1 , # stats do
local stat = stats [ j ]
local writes = fieldWrites ( stat , name )
if occurrences ( stat , name ) ~= # writes then
stoppedAt = stat
break
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
for _ , target in ipairs ( writes ) do
local kind , value = writtenKey ( target )
if kind == "array" then
if value > array then
array = value
end
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

return array , hashCount + opaque , stoppedAt , constructorFields
end




local function isEmptyTable ( node )
return node and not isToken ( node ) and node . kind == "tableExpr" and # ( node . fields or { } ) == 0
end

local function remark ( remarks , node , code , message , related )
local token = firstToken ( node )
remarks [
# remarks + 1
] = {
code = code ,
severity = "note" ,
msg = message ,
line = token and token . line or 0 ,
col = token and token . col or 0 ,
offset = token and token . offset or 0 ,
length = token and # token . text or 1 ,
related = related ,
}
end

local function presizeBlock ( stats , remarks )
for i , stat in ipairs ( stats ) do
if not isToken (
stat
)
and stat . kind == "localStmt"
and stat . names
and # stat . names == 1
and stat . exprs
and # stat . exprs == 1
and isEmptyTable (
stat . exprs [ 1 ]
) then
local name = stat . names [ 1 ] . text
local constructor = stat . exprs [ 1 ]
local array , hash , stoppedAt , constructorFields = planPresize ( stats , i , name )
if array + hash >= PRESIZE_MIN then
constructor . presize = { narr = array , nhash = hash }
if constructorFields then
constructor . presizeFields = constructorFields
for _ , field in ipairs ( constructorFields ) do
field . stat . presizedIntoConstructor = true
end
end
local message
if constructorFields then
message = ( "presize: %s is created with %d named fields" ) : format ( name , # constructorFields )
else
message = (
"presize: %s is created with room for %d array and %d hash entries"
) : format ( name , array , hash )
end
remark ( remarks , constructor , "OPT-1" , message )
elseif stoppedAt then
local token = firstToken ( stoppedAt )
remark (
remarks ,
constructor ,
"OPT-1" ,
(
"presize: %s is not presized, because it is used for "
.. "something other than a field assignment before its "
.. "fields are known"
) : format ( name ) ,
token and {
{
line = token . line ,
col = token . col ,
offset = token . offset ,
length = # token . text ,
message = "used here" ,
}
} or nil
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
if field . kind == "fieldItem" then
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
"numeric-ipairs: the declared array has a stable shape in this " .. "loop"
)
else
local at = related and firstToken ( related ) or nil
remark (
remarks ,
node ,
"OPT-2" ,
"numeric-ipairs: not rewritten because " .. reason ,
at and {
{
line = at . line ,
col = at . col ,
offset = at . offset ,
length = # at . text ,
message = "proof stopped here" ,
}
} or nil
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




local function soleAccumulation ( loop , definition , asked )
local found , other = nil , false
local function walk ( node )
if not node or isToken ( node ) or other then
return
end
if node . kind == "assignStmt" and # ( node . targets or { } ) == 1 and # ( node . exprs or { } ) == 1 then
local target = node . targets [ 1 ]
if target and not isToken (
target
) and target . kind == "name" and target . token and target . token . definition == definition then
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
if stat . kind == "localStmt" and # (
stat . names or { }
) == 1 and # ( stat . exprs or { } ) == 1 and emptyString ( stat . exprs [ 1 ] ) and stat . names [ 1 ] . definition then
local definition = stat . names [ 1 ] . definition



local loop , untouched = nil , true
for j = i + 1 , # stats do
local next = stats [ j ]
if LOOPS [ next . kind ] then
loop = next
break
end
if asked . uses ( definition , next ) > 0 then
untouched = false
break
end
end
local accumulation = untouched and loop and soleAccumulation ( loop , definition , asked ) or nil
if accumulation then
counter = counter + 1
local name = ( "__nuppBuf_%d" ) : format ( counter )
stat . concatBuffer = { name = name }
accumulation . stat . concatBuffer = { name = name , pieces = accumulation . pieces }
loop . concatBuffer = { name = name , target = stat . names [ 1 ] . text }
remark (
remarks ,
stat ,
"OPT-5" ,
(
"concat-buffer: %s is built with a string.buffer, " .. "which appends instead of rebuilding"
) : format ( stat . names [ 1 ] . text )
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
local scalarIntrinsics = require ( "nupp.compiler.scalar_intrinsics" )







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

local function integerLiteral ( node )
if not node . token then
return nil
end
local text = node . token . text
local lower = text : lower ( )
if lower : find ( "ll" , 1 , true ) or lower : sub ( - 1 ) == "i" then
return nil
end
local value = tonumber ( ( text : gsub ( "_" , "" ) ) )
if not value or value ~= value or value == math . huge or value == - math . huge or value ~= math . floor (
value
) or math . abs ( value ) > MAX_EXACT_INTEGER then
return nil
end

return literal ( "number" , value , ( "%.0f" ) : format ( value ) )
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

return literal ( "string" , value , string . format ( "%q" , value ) )
end






local function comptimeLiteral ( node )
local code = node and node . comptimeValue
if code == "nil" then
return literal ( "nil" , nil , "nil" )
elseif code == "true" or code == "false" then
return literal ( "boolean" , code == "true" , code )
elseif code and code : match ( "^-?%d+$" ) then
local value = tonumber ( code )
if value and math . abs ( value ) <= MAX_EXACT_INTEGER then
return literal ( "number" , value , code )
end
elseif code and code : sub ( 1 , 1 ) == '"' then
local chunk = loadstring ( "return " .. code )
if chunk then
local ok , value = pcall ( chunk )
if ok and type ( value ) == "string" then
return literal ( "string" , value , string . format ( "%q" , value ) )
end
end
end

return nil
end

local function truthy ( value )
return value . kind ~= "nil" and not ( value . kind == "boolean" and not value . value )
end

local function scope ( parent )
return { parent = parent , constants = { } , paths = { } }
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
if t . base and (
t . base . tag == "number" or t . base . tag == "integer"
) and type (
t . constant
) == "number" and t . constant == math . floor ( t . constant ) and math . abs ( t . constant ) <= MAX_EXACT_INTEGER then
return literal ( "number" , t . constant , ( "%.0f" ) : format ( t . constant ) )
elseif t . base and t . base . tag == "string" and type ( t . constant ) == "string" then
return literal ( "string" , t . constant , string . format ( "%q" , t . constant ) )
elseif t . base and t . base . tag == "boolean" and type ( t . constant ) == "boolean" then
return literal ( "boolean" , t . constant , tostring ( t . constant ) )
end

return nil
end

local foldBlock , foldFunction

local function foldExpr ( node , current )
if not node or isToken ( node ) then
return nil
end
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
return literal ( "nil" , nil , "nil" )
elseif kind == "trueExpr" or kind == "falseExpr" then
local value = kind == "trueExpr"
node . folded = tostring ( value )
return literal ( "boolean" , value , node . folded )
elseif kind == "comptimeExpr" then
return comptimeLiteral ( node )
elseif kind == "name" and node . token then
local value = lookupConstant ( current , node . token . text )
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
if not value or not node . op then
return nil
end
local op = node . op . kind
if op == "not" then
local answer = literal ( "boolean" , not truthy ( value ) , tostring ( not truthy ( value ) ) )
node . folded = answer . code
return answer
elseif op == "-" and value . kind == "number" and value . value ~= 0 then
local answer = - value . value
if math . abs ( answer ) <= MAX_EXACT_INTEGER then
local folded = literal ( "number" , answer , ( "%.0f" ) : format ( answer ) )
node . folded = folded . code
return folded
end
elseif op == "#" and value . kind == "string" then
local folded = literal ( "number" , # value . value , tostring ( # value . value ) )
node . folded = folded . code
return folded
elseif op == "~" and value . kind == "number" then
local answer = bit . bnot ( value . value )
local folded = literal ( "number" , answer , ( "%.0f" ) : format ( answer ) )
node . folded = folded . code
return folded
end
return nil
elseif kind == "binop" then
local left , right = foldExpr ( node . lhs , current ) , foldExpr ( node . rhs , current )
if not left or not right or not node . op then
return nil
end
local op = node . op . kind
if op == "and" then
local folded = truthy ( left ) and right or left
node . folded = folded . code
return folded
elseif op == "or" then
local folded = truthy ( left ) and left or right
node . folded = folded . code
return folded
elseif op == "??" then
local folded = left . kind == "nil" and right or left
node . folded = folded . code
return folded
elseif left . kind == "number" and right . kind == "number" then
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
if answer and math . abs ( answer ) <= MAX_EXACT_INTEGER then
local folded = literal ( "number" , answer , ( "%.0f" ) : format ( answer ) )
node . folded = folded . code
return folded
end
elseif op == ".." and left . kind == "string" and right . kind == "string" then
local folded = literal ( "string" , left . value .. right . value , string . format ( "%q" , left . value .. right . value ) )
node . folded = folded . code
return folded
end
local comparable = left . kind == right . kind or ( left . kind == "nil" or right . kind == "nil" )
if comparable and ( op == "==" or op == "~=" ) then
local equal = left . value == right . value
local folded = literal (
"boolean" ,
op == "==" and equal or not equal ,
tostring ( op == "==" and equal or not equal )
)
node . folded = folded . code
return folded
end
if left . kind == right . kind and (
left . kind == "number" or left . kind == "string"
) and ( op == "<" or op == ">" or op == "<=" or op == ">=" ) then
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
local arguments , allNumbers = { } , true
for _ , arg in ipairs ( node . args and node . args . exprs or { } ) do
local value = foldExpr ( arg , current )
arguments [ # arguments + 1 ] = value and value . value or nil
allNumbers = allNumbers and value ~= nil and value . kind == "number"
end
if node . scalarIntrinsic and allNumbers then
local answer = scalarIntrinsics . fold ( node . scalarIntrinsic , arguments )
if type ( answer ) == "number" and math . abs ( answer ) <= MAX_EXACT_INTEGER then
local numeric = answer
local folded = literal ( "number" , numeric , ( "%.0f" ) : format ( numeric ) )
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
for _ , arg in ipairs ( node . args and node . args . exprs or { } ) do
foldExpr ( arg , current )
end
elseif kind == "dotIndex" or kind == "safeIndex" then
foldExpr ( node . obj , current )
local value = resolvedLiteral ( node ) or lookupPath ( current , textPath ( node ) )
if value and value . kind ~= "table" then
node . folded = value . code
end
return value
elseif kind == "bracketIndex" or kind == "safeBracket" then
foldExpr ( node . obj , current )
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
elseif kind == "funcExpr" then
if node . body then
foldFunction ( node . body , current )
end
elseif kind == "shortfn" then
local inner = scope ( current )
for _ , param in ipairs ( node . params or { } ) do
if param . name then
inner . constants [ param . name . text ] = false
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
inner . constants [ param . name . text ] = false
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
current . constants [ name . text ] = stat . isConst and values [ i ] or false
if stat . isConst and values [ i ] and values [ i ] . kind == "table" then
bindObjectFields ( current , name . text , values [ i ] )
else
bindPath ( current , name . text , nil )
end
end
elseif kind == "assignStmt" then
for _ , expr in ipairs ( stat . exprs or { } ) do
foldExpr ( expr , current )
end
for i , target in ipairs ( stat . targets or { } ) do
local path = textPath ( target )
if target . kind == "name" and target . token then
current . constants [ target . token . text ] = false
bindPath ( current , target . token . text , nil )
else
foldExpr ( target , current )
if stat . isConst and path then
local value = foldExpr ( ( stat . exprs or { } ) [ i ] , current )
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
current . constants [ stat . target . token . text ] = false
end
elseif kind == "ifStmt" then
local selected , allConstant = nil , true
for _ , clause in ipairs ( stat . clauses or { } ) do
local condition = foldExpr ( clause . cond , current )
if not condition then
allConstant = false
elseif not selected and truthy ( condition ) then
selected = clause . body
end
if clause . body then
foldBlock ( clause . body , scope ( current ) )
end
end
if stat . elseClause and stat . elseClause . body then
foldBlock ( stat . elseClause . body , scope ( current ) )
end
if allConstant then
stat . constantBranch = selected or ( stat . elseClause and stat . elseClause . body )
stat . constantBranchNone = stat . constantBranch == nil
end
elseif kind == "whileStmt" then
local condition = foldExpr ( stat . cond , current )
if stat . body then
foldBlock ( stat . body , scope ( current ) )
end



if condition and not truthy ( condition ) then
stat . constantLoopNone = true
end
elseif kind == "repeatStmt" then
local inner = scope ( current )
if stat . body then
foldBlock ( stat . body , inner )
end
foldExpr ( stat . cond , inner )
elseif kind == "doStmt" or kind == "unsafeStmt" then
if stat . body then
foldBlock ( stat . body , scope ( current ) )
end
elseif kind == "fornumStmt" then
local from , to = foldExpr ( stat . start , current ) , foldExpr ( stat . stop , current )



local by = literal ( "number" , 1 , "1" )
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
inner . constants [ stat . var . text ] = false
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
inner . constants [ name . text ] = false
end
if stat . body then
foldBlock ( stat . body , inner )
end
elseif kind == "localFuncStmt" then
if stat . name then
current . constants [ stat . name . text ] = false
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

local function constantFoldWalk ( node )
if not node or isToken ( node ) then
return
end
if node . kind == "block" then
foldBlock ( node , scope ( nil ) )
return
end
for _ , child in ipairs ( node ) do
constantFoldWalk ( child )
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
( "static-callable: binds immutable callee %s once" ) : format ( path )
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























function optimize . run ( result , opts )
opts = opts or { }
local level = opts . level or 0
local disabled = opts . disabled or { }
local remarks = { }
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
if level >= optimize . passes [ "OPT-5" ] . level and not disabled [ "OPT-5" ] then
concatBufferWalk ( result , remarks )
end
for _ , entry in ipairs ( remarks ) do
entry . filename = result . filename or opts . filename
end

return remarks
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

return optimize
