_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);








local operators = { }





operators . ffiTypeFirst = {
[ "new" ] = true ,
[ "cast" ] = true ,
[ "istype" ] = true ,
[ "typeof" ] = true ,
[ "sizeof" ] = true ,
[ "alignof" ] = true ,
}


operators . arith = {
[ "+" ] = true ,
[ "-" ] = true ,
[ "*" ] = true ,
[ "/" ] = true ,
[ "%" ] = true ,
[ "^" ] = true ,
[ "//" ] = true ,
}


operators . bitops = { [ "&" ] = true , [ "|" ] = true , [ "~" ] = true , [ "<<" ] = true , [ ">>" ] = true , [ "~>>" ] = true , }


operators . compare = { [ "<" ] = true , [ ">" ] = true , [ "<=" ] = true , [ ">=" ] = true , [ "==" ] = true , [ "~=" ] = true , }



operators . logical = { [ "and" ] = true , [ "or" ] = true , }


operators . metamethod = {
[ "+" ] = "__add" ,
[ "-" ] = "__sub" ,
[ "*" ] = "__mul" ,
[ "/" ] = "__div" ,
[ "%" ] = "__mod" ,
[ "^" ] = "__pow" ,
[ ".." ] = "__concat" ,
}


operators . contractMetamethod = {
__call = true ,
__index = true ,
__newindex = true ,
__add = true ,
__sub = true ,
__mul = true ,
__div = true ,
__mod = true ,
__pow = true ,
__unm = true ,
__concat = true ,
__len = true ,
__eq = true ,
__lt = true ,
__le = true ,
__tostring = true ,
}



operators . runtimeMetamethod = {
__call = true ,
__index = true ,
__newindex = true ,
__mode = true ,
__metatable = true ,
__tostring = true ,
__len = true ,
__add = true ,
__sub = true ,
__mul = true ,
__div = true ,
__mod = true ,
__pow = true ,
__unm = true ,
__concat = true ,
__eq = true ,
__lt = true ,
__le = true ,
__gc = true ,
__pairs = true ,
__ipairs = true ,
}

local T = require ( "nupp.compiler.types" )
local generics = require ( "nupp.compiler.generics" )
local relations = require ( "nupp.compiler.relations" )
local narrowing = require ( "nupp.compiler.narrowing" )
local cst = require ( "nupp.compiler.cst" )
local lexer = require ( "nupp.compiler.lexer" )
local state = require ( "nupp.compiler.check.state" )
local fixedWidth = require ( "nupp.compiler.fixed_width" )

local isA = relations . isA
local subtract = narrowing . subtract














local function customaryOperator ( c , opTok )


local classic = lexer . CUSTOMARY [ opTok . text ]
if not classic then
return
end
c . diag (
"NUPP2504" ,
opTok ,
( "%s is the customary spelling of %s" ) : format ( opTok . text , classic ) ,
{ c . edits . fix ( ( "change to `%s`" ) : format ( classic ) , c . edits . replaceToken ( opTok , classic ) ) } ,
{ help = ( "write %s" ) : format ( classic ) }
)
end





function operators . install ( c )

local lpegEmpty = T . array ( T . never )
local lpegUnknown = T . array ( T . any )

local function lpegPattern ( t )
local payload = T . unwrapOwnership ( t )
if payload . tag ~= "nominal" then
return nil
end
local origin = ( payload . origin or payload )
if not origin . lpegPattern then
return nil
end

return origin , payload . typeArgs and payload . typeArgs [ 1 ] or lpegUnknown
end

local function makeLpegPattern ( origin , captures )
local parameter = origin . typeParams and origin . typeParams [ 1 ]
if not parameter then
return origin
end

return generics . instantiate ( origin , { [ parameter ] = captures } )
end

local function reducedCaptures ( t )
local reduced = generics . evaluate ( t , nil , c . reductionControl )
return reduced . error and lpegUnknown or reduced . type
end

local function concatCaptures ( left , right )
left , right = reducedCaptures ( left ) , reducedCaptures ( right )
if left . tag == "array" and left . elem == T . never then
return right
end
if right . tag == "array" and right . elem == T . never then
return left
end
if left . tag == "tuple" and right . tag == "tuple" then
local values = { }
for _ , value in ipairs ( left . elems ) do
values [ # values + 1 ] = value
end
for _ , value in ipairs ( right . elems ) do
values [ # values + 1 ] = value
end
return T . tuple ( values )
end

return lpegUnknown
end

local function capturesFromPack ( pack )
local evaluated = generics . evaluatePack ( pack , c . reductionControl )
if evaluated . error or evaluated . pack . alternatives then
return lpegUnknown
end
local concrete , why = generics . expandComputedPack ( evaluated . pack , c . reductionControl )
if why then
return lpegUnknown
end
if not concrete . tail then
return # concrete . head == 0 and lpegEmpty or T . tuple ( concrete . head )
end
if concrete . tail . kind == "homogeneous" and # concrete . head == 0 then
return T . array ( concrete . tail . type )
end

return lpegUnknown
end

local function patternOperandCaptures ( t )
local _ , captures = lpegPattern ( t )
if captures then
return captures
end
if t == T . any or isA (
t ,
T . string
) or isA ( t , T . number ) or isA ( t , T . boolean ) or isA ( t , T . table_ ) or t . tag == "func" then
return lpegEmpty
end

return nil
end

local function lpegBinary ( op , lt , rt , node )
local leftOrigin , leftCaptures = lpegPattern ( lt )
local rightOrigin = lpegPattern ( rt )
local origin = leftOrigin or rightOrigin
if not origin then
return nil
end
if op == "*" or op == "+" or op == "-" then
local left = patternOperandCaptures ( lt )
local right = patternOperandCaptures ( rt )
if not left or not right then
c . diag ( "NUPP2003" , node , ( "cannot apply '%s' to %s and %s" ) : format ( op , T . tostring ( lt ) , T . tostring ( rt ) ) )
return T . any
end
if op == "*" then
return makeLpegPattern ( origin , concatCaptures ( left , right ) )
elseif op == "+" then
left , right = reducedCaptures ( left ) , reducedCaptures ( right )
return makeLpegPattern ( origin , left == right and left or lpegUnknown )
else
return makeLpegPattern ( origin , left )
end
elseif op == "^" and leftOrigin then
if not isA ( rt , T . integer ) then
c . diag ( "NUPP2003" , node , "an LPeg exponent must be an integer" )
end
local captures = reducedCaptures ( leftCaptures )
if captures . tag == "array" and captures . elem == T . never then
return makeLpegPattern ( leftOrigin , lpegEmpty )
elseif captures . tag == "tuple" and # captures . elems == 1 then
return makeLpegPattern ( leftOrigin , T . array ( captures . elems [ 1 ] ) )
end
return makeLpegPattern ( leftOrigin , lpegUnknown )
elseif op == "/" and leftOrigin then
local captures = leftCaptures
if isA ( rt , T . string ) then
return makeLpegPattern ( leftOrigin , T . tuple ( { T . string } ) )
elseif isA ( rt , T . integer ) then
if rt . tag == "literal" and rt . constant == 0 then
return makeLpegPattern ( leftOrigin , lpegEmpty )
end
captures = reducedCaptures ( captures )
if rt . tag == "literal" and captures . tag == "tuple" then
local selected = captures . elems [ rt . constant ]
return makeLpegPattern ( leftOrigin , selected and T . tuple ( { selected } ) or lpegUnknown )
end
return makeLpegPattern ( leftOrigin , lpegUnknown )
elseif rt . tag == "func" then
return makeLpegPattern ( leftOrigin , capturesFromPack ( rt . retPack ) )
elseif isA ( rt , T . table_ ) or rt . tag == "shape" or rt . tag == "array" or rt . tag == "map" then
local value = rt . tag == "array"
and rt . elem
or rt . tag == "map"
and rt . value
or rt . tag == "nominal"
and rt . indexReadValue
or T . any
return makeLpegPattern ( leftOrigin , value == T . any and lpegUnknown or T . tuple ( { value } ) )
end
c . diag ( "NUPP2003" , node , ( "invalid LPeg capture transformation %s" ) : format ( T . tostring ( rt ) ) )
return T . any
elseif op == "%" and leftOrigin then
if rt . tag ~= "func" and rt ~= T . any then
c . diag ( "NUPP2003" , node , "an LPeg accumulator capture needs a function" )
end
return makeLpegPattern ( leftOrigin , lpegEmpty )
end

return nil
end

local function orderingFamily ( t )
if t == T . any then
return "any"
end
if isA ( t , T . number ) then
return "number"
end
if isA ( t , T . string ) then
return "string"
end
if t . tag == "union" then
local family = nil
for _ , member in ipairs ( t . members ) do
if member ~= T . nil_ then
local found = orderingFamily ( member )
if not found or found == "any" then
return found
end
if family and family ~= found then
return nil
end
family = found
end
end
return family
end

return nil
end





c . minusNil = function ( t )
if t . tag == "union" and t . hasNil then
local m = { }
for _ , x in ipairs ( t . members ) do
if x ~= T . nil_ then
m [ # m + 1 ] = x
end
end
return T . union ( m )
end

return t
end

local handlers = { }

handlers . unop = function ( node )
local operand = node . operand
local opTok = node . op
if not operand or not opTok then
return T . any
end
customaryOperator ( c , opTok )
local t = c . infer ( operand )
local op = opTok . kind
if op == "-" then
local origin = lpegPattern ( t )
if origin then
return makeLpegPattern ( origin , lpegEmpty )
end
local mm = c . metamethodOf ( t , "__unm" )
if mm then
return c . applyContract ( mm , { t } , { operand } , node , "__unm" )
end
c . numericOperand ( t , node , op )
if t . tag == "literal" and type ( t . constant ) == "number" then
local value = - ( t . constant )
c . fixedWidth . markLiteral ( node , value )
return T . literal ( value , t . base )
end
return ( t == T . any or fixedWidth . isValue ( t ) ) and T . number or t
elseif op == "~" then
c . numericOperand ( t , node , op )
return T . integer
elseif op == "#" then
local origin = lpegPattern ( t )
if origin then
return makeLpegPattern ( origin , lpegEmpty )
end
local mm = c . metamethodOf ( t , "__len" )
if mm then
return c . applyContract ( mm , { t } , { operand } , node , "__len" )
end
if not ( t == T . any or isA ( t , T . string ) or isA ( t , T . table_ ) ) then
c . diag ( "NUPP2003" , node , ( "cannot apply '#' to %s" ) : format ( T . tostring ( t ) ) )
end
return T . integer
else
return T . boolean
end

return T . any
end

handlers . binop = function ( node )
local opTok , lhs , rhs = node . op , node . lhs , node . rhs
if not opTok or not lhs or not rhs then
return T . any
end
customaryOperator ( c , opTok )
local op = opTok . kind
local lt , rt
if operators . logical [ op ] then

lt = c . infer ( lhs )
local facts = c . analyzeCond ( lhs )
c . pushScope ( )
c . applyFacts ( op == "and" and facts . t or facts . f )
rt = c . infer ( rhs )
c . popScope ( )
else
lt , rt = c . infer ( lhs ) , c . infer ( rhs )
end
local lpegResult = lpegBinary ( op , lt , rt , node )
if lpegResult then
return lpegResult
end
if operators . arith [ op ] then
local mmName = op ~= "//" and operators . metamethod [ op ] or nil
local mm = mmName and ( c . metamethodOf ( lt , mmName ) or c . metamethodOf ( rt , mmName ) ) or nil
if mm then


return c . applyContract ( mm , { lt , rt } , { lhs , rhs } , node , mmName )
end
local leftPayload = T . unwrapOwnership ( lt )
if ( op == "+" or op == "-" ) and leftPayload . tag == "ptr" and isA ( rt , T . integer ) then
if c . ownershipKind ( lt ) ~= "borrowed" then
c . diag ( "NUPP2604" , node , "pointer arithmetic requires a rooted borrowed pointer" )
return leftPayload
end
local roots = c . own . provenanceOwners ( lhs )
if # roots > 0 then
c . own . capabilityFacts ( node ) . roots = roots
end
if c . unsafeDepth == 0 then
c . diag ( "NUPP2604" , node , "unchecked pointer arithmetic requires unsafe do; use a span for bounds" )
return T . borrowed ( leftPayload )
end


node . unsafeOwnershipOperation = "unchecked pointer arithmetic"
return leftPayload
end
c . numericOperand ( lt , lhs , op )
c . numericOperand ( rt , rhs , op )
if op == "/" or op == "^" then
return T . number
end
if fixedWidth . isValue ( lt ) or fixedWidth . isValue ( rt ) then
return T . number
end
if isA ( lt , T . integer ) and isA ( rt , T . integer ) and lt ~= T . any and rt ~= T . any then
return T . integer
end
return T . number
elseif op == ".." then
local mm = c . metamethodOf ( lt , "__concat" ) or c . metamethodOf ( rt , "__concat" )
if mm then
return c . applyContract ( mm , { lt , rt } , { lhs , rhs } , node , "__concat" )
end






local plain = true
for _ , pair in ipairs ( { { lt , lhs } , { rt , rhs } } ) do


local t = pair [ 1 ]
if not ( t == T . any or isA ( t , T . number ) or isA ( t , T . string ) ) then
c . diag ( "NUPP2003" , pair [ 2 ] , ( "cannot concatenate %s" ) : format ( T . tostring ( t ) ) )
plain = false
elseif t == T . any then
plain = false
end
end
node . plainConcat = plain
return T . string
elseif operators . bitops [ op ] then
c . numericOperand ( lt , lhs , op )
c . numericOperand ( rt , rhs , op )
return T . integer
elseif operators . compare [ op ] then
if op ~= "==" and op ~= "~=" then
local mmName = ( op == "<" or op == ">" ) and "__lt" or "__le"
local left , right = lt , rt
local leftNode , rightNode = lhs , rhs
if op == ">" or op == ">=" then
left , right , leftNode , rightNode = rt , lt , rhs , lhs
end
local mm = c . metamethodOf ( left , mmName ) or c . metamethodOf ( right , mmName )
if not mm and ( op == "<=" or op == ">=" ) then
mmName = "__lt"
left , right , leftNode , rightNode = right , left , rightNode , leftNode
mm = c . metamethodOf ( left , mmName ) or c . metamethodOf ( right , mmName )
end
if mm then
c . applyContract ( mm , { left , right } , { leftNode , rightNode } , node , mmName )
else
local lf , rf = orderingFamily ( lt ) , orderingFamily ( rt )
if not ( lf == "any" or rf == "any" or ( lf and lf == rf ) ) then
c . diag (
"NUPP2003" ,
node ,
( "cannot compare %s and %s with '%s'" ) : format ( T . tostring ( lt ) , T . tostring ( rt ) , op )
)
end
end
end
return T . boolean
elseif op == "??" then

return T . union ( { subtract ( lt , T . nil_ ) , rt } )
elseif operators . logical [ op ] then




if op == "and" then
local parts = { rt }
if lt == T . nil_ or ( lt . tag == "union" and lt . hasNil ) then
parts [ # parts + 1 ] = T . nil_
end
return T . union ( parts )
else
if lt == T . nil_ then
return rt
end
return T . union ( { c . minusNil ( lt ) , rt } )
end
end

return T . any
end

return handlers
end

return operators
