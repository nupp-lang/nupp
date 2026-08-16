_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);









local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.relations" )
local cst = require ( "nupp.compiler.cst" )
local state = require ( "nupp.compiler.check.state" )
local comptimeFunction = require ( "nupp.compiler.check.comptime_function" )

local isA = relations . isA
local rawType = T . unwrapOwnership




local functions = { }





function functions . install ( c )

local ownershipState , pointerShaped = c . ownershipState , c . pointerShaped
local expectedFuncbodies = { }

local function inferredParameterModes ( body )
local modes , byname , declared = { } , { } , { }
for j , p in ipairs ( body . params or { } ) do
if p . name and not p . namedVararg then
modes [ j ] = p . modeTok and p . modeTok . text or "borrows"
declared [ j ] = p . modeTok ~= nil
if not p . modeTok then
byname [ p . name . text ] = j
end
end
end

local function raise ( name , effect )
local at = byname [ name ]
if not at then
return
end
local current = modes [ at ]
if current == "takes" or current == "plain" then
return
end
if effect == "takes" or effect == "plain" or effect == "exclusive" and current == "borrows" then
modes [ at ] = effect
end
end

local function directName ( expr )
while expr and ( expr . kind == "paren" or expr . kind == "castExpr" ) do
expr = expr . expr
end
return expr and expr . kind == "name" and expr . token . text or nil
end

local function returnBorrows ( name )
local first = body . rets and body . rets [ 1 ]
if not first or first . kind ~= "tborrows" then
return false
end
for _ , source in ipairs ( first . params or { first . param } ) do
if source and source . text == name then
return true
end
end

return false
end

local function returnPreserves ( name )
for _ , result in ipairs ( body . rets or { } ) do
if result . kind == "tpreserves" and result . param and result . param . text == name then
return true
end
end

return false
end

local walk
walk = function ( node , nested )
if not node or cst . isToken ( node ) then
return
end
local kind = node . kind
if nested and kind == "name" then
raise ( node . token . text , "plain" )
return
end
if kind == "localFuncStmt" or kind == "funcStmt" then
walk ( node . body , true )
return
elseif kind == "call" then
local calleeName = directName ( node . obj )
local calleeT = calleeName and c . lookupVar ( calleeName ) or nil



local intrinsic = node . ownershipSyntax or cst . ownershipIntrinsicSpelling ( node . obj )
local args = node . args and node . args . exprs or { }
for j , arg in ipairs ( args ) do
local name = directName ( arg )
if name then
local effect
if intrinsic == "drop" then
effect = "takes"
elseif intrinsic == "borrow" or intrinsic == "pin" then
effect = "borrows"
elseif calleeT and calleeT . tag == "func" then
effect = calleeT . paramModes [ j ] or "plain"
if effect == "takes" then
for _ , source in ipairs ( calleeT . preservesResults or { } ) do
if source == j then


effect = "plain"
break
end
end
end
else
effect = "plain"
end
if effect == "retains" or effect == "releases" then
effect = "borrows"
end
raise ( name , effect )
else
walk ( arg , nested )
end
end
walk ( node . obj , nested )
return
elseif kind == "methodCall" then
local receiver = directName ( node . obj )
if receiver then
raise ( receiver , "plain" )
end
for _ , arg in ipairs ( node . args and node . args . exprs or { } ) do
local name = directName ( arg )
if name then
raise ( name , "plain" )
else
walk ( arg , nested )
end
end
return
elseif kind == "assignStmt" then
for j , expr in ipairs ( node . exprs or { } ) do
local name = directName ( expr )
local target = node . targets and node . targets [ j ]
if name and not ( target and target . kind == "name" and target . token . text == name ) then
raise ( name , "plain" )
else
walk ( expr , nested )
end
end
for _ , target in ipairs ( node . targets or { } ) do
walk ( target , nested )
end
return
elseif kind == "returnStmt" then
for _ , expr in ipairs ( node . exprs or { } ) do
local name = directName ( expr )
if name then
if returnPreserves ( name ) or body . ownCleanups then
raise ( name , "takes" )
elseif not returnBorrows ( name ) then
raise ( name , "plain" )
end
else
walk ( expr , nested )
end
end
return
elseif kind == "tableExpr" then
for _ , child in ipairs ( node ) do
if not cst . isToken ( child ) then
local name = directName ( child . value or child )
if name then
raise ( name , "plain" )
else
walk ( child , nested )
end
end
end
return
end
for _ , child in ipairs ( node ) do
if not cst . isToken ( child ) then
walk ( child , nested )
end
end
end
walk ( body . body , false )

return modes , declared
end





local function couldCarryMovable ( t )
if not t or t == T . any or t == T . unknown then
return true
end
if t . tag == "affine" or t . tag == "pinned" then
return true
elseif t . tag == "typevar" then
return not t . bound or couldCarryMovable ( t . bound )
elseif t . tag == "union" or t . tag == "intersection" then
for _ , member in ipairs ( t . members or { } ) do
if couldCarryMovable ( member ) then
return true
end
end
elseif t . tag == "nominal" then
return t . affineFields ~= nil and # t . affineFields > 0
end

return false
end

local function preservationResults ( body , paramNames , paramTypes , resultTypes , paramModes , inferVisible , report )
local byname , results , explicit = { } , { } , { }
for j , name in ipairs ( paramNames or { } ) do
byname [ name ] = j
end
for result , ret in ipairs ( body and body . rets or { } ) do
if ret . kind == "tpreserves" and ret . param then
local source = byname [ ret . param . text ]
if not source then
if report then
c . diag ( "NUPP2109" , ret . param , ( "%s names no parameter of this function" ) : format ( ret . param . text ) )
end
else
results [ result ] , explicit [ result ] = source , true
if report and couldCarryMovable ( paramTypes [ source ] ) and paramModes [ source ] ~= "takes" then
c . diag (
"NUPP2606" ,
ret . param ,
(
"preserving capability-bearing parameter %q requires `takes %s`"
) : format ( ret . param . text , ret . param . text )
)
end
local resultType = resultTypes [ result ]
if resultType and resultType . tag == "neutral" then
resultType = require ( "nupp.compiler.generics" ) . normalize ( resultType ) . type
end
if report and resultType and not T . preservationPath ( resultType , paramTypes [ source ] ) then
c . diag (
"NUPP2606" ,
ret ,
(
"preserves %q must select one unambiguous component of the result shape"
) : format ( ret . param . text )
)
end
end
end
end

local returns = { }
local function walk ( node )
if not node or cst . isToken ( node ) then
return
end
if node . kind == "funcbody" or node . kind == "shortfn" or node . kind == "funcExpr" then
return
end
if node . kind == "returnStmt" then
returns [ # returns + 1 ] = node
return
end
for _ , child in ipairs ( node ) do
if not cst . isToken ( child ) then
walk ( child )
end
end
end

walk ( body and body . body )

local function directParameter ( expr )
while expr and ( expr . kind == "paren" or expr . kind == "castExpr" ) do
expr = expr . expr
end
if expr and expr . kind == "namedArg" then
return directParameter ( expr . value )
elseif expr and expr . kind == "newExpr" then
return directParameter ( expr . call )
end
if expr and expr . kind == "call" then
local source = expr . preservesArguments and expr . preservesArguments [ 1 ] or nil
if not source then
local callee = expr . obj
local calleeName = callee and callee . kind == "name" and callee . token . text or nil
local callable = calleeName and c . lookupVar ( calleeName ) or nil
source = callable
and callable . tag == "func"
and callable . preservesResults
and callable . preservesResults [
1
] or nil
end
local argument = source and expr . args and expr . args . exprs and expr . args . exprs [ source ] or nil
if argument then
return directParameter ( argument )
end
if ( expr . constructorCall or expr . recordConstruct ) and expr . args then
local found
for _ , value in ipairs ( expr . args . exprs or { } ) do
local nested = directParameter ( value )
if nested then
if found and found ~= nested then
return nil
elseif found == nested then


return nil
end
found = nested
end
end
return found
end
end

return expr and expr . kind == "name" and expr . token and byname [ expr . token . text ] or nil
end

local maxResults = # ( body and body . rets or { } )
if inferVisible and # returns > 0 then
for result = 1 , maxResults do
if not results [ result ] then
local source
for _ , ret in ipairs ( returns ) do
local found = directParameter ( ret . exprs and ret . exprs [ result ] )
if not found or source and source ~= found then
source = nil
break
end
source = found
end
results [ result ] = source
end
end
end



local used = { }
for result = 1 , maxResults do
local source = results [ result ]
if source and used [ source ] then
if explicit [ result ] and report then
c . diag (
"NUPP2602" ,
body . rets [ result ] ,
"one parameter capability cannot be preserved into two results"
)
end
results [ result ] = nil
results [ used [ source ] ] = nil
elseif source then
used [ source ] = result
end
end

if report then
for result = 1 , maxResults do
local source = results [ result ]
if explicit [ result ] then
for _ , ret in ipairs ( returns ) do
if directParameter ( ret . exprs and ret . exprs [ result ] ) ~= source then
c . diag (
"NUPP2602" ,
ret ,
"a preserves result must return its named parameter on every successful path"
)
end
end
end
end
end

return next ( results ) and results or nil , next ( explicit ) and explicit or nil
end





local function scopedCallbackParameters ( body , report )
local candidates , tokenByName = { } , { }
for _ , p in ipairs ( body and body . params or { } ) do
if p . name and not p . namedVararg then
candidates [ p . name . text ] = true
tokenByName [ p . name . text ] = p . name
end
end
local function walk ( node , parent )
if not node or cst . isToken ( node ) then
return
end
if node . kind == "name" and node . token and candidates [ node . token . text ] ~= nil then
local invoked = parent and parent . kind == "call" and parent . obj == node
if not invoked then
candidates [ node . token . text ] = false
end
return
end
for _ , child in ipairs ( node ) do
if not cst . isToken ( child ) then
walk ( child , node )
end
end
end

walk ( body and body . body , nil )
if report then
for _ , p in ipairs ( body and body . params or { } ) do
if p . modeTok and p . modeTok . text == "scoped" and candidates [ p . name . text ] == false then
c . diag (
"NUPP2602" ,
tokenByName [ p . name . text ] or p ,
"a scoped callback may only be invoked directly during the call"
)
end
end
end

return candidates
end

local function takenCaptures ( body )
if body . takenCaptures then
return body . takenCaptures
end
local captures , seen = { } , { }
local clause = body . captureTakes
if not clause then
body . takenCaptures = captures
return captures
end
if # ( clause . names or { } ) == 0 then
c . diag ( "NUPP2602" , clause , "takes () moves nothing; name what the closure takes or drop the clause" )
end
for _ , token in ipairs ( clause . names or { } ) do
if seen [ token . text ] then
c . diag ( "NUPP2602" , token , ( "closure capture %q is repeated" ) : format ( token . text ) )
else
seen [ token . text ] = true
local entry = c . lookupEntry ( token . text )
local state = c . ownershipState ( entry )
local valueType = state and state . t or nil
if not state then
c . diag ( "NUPP2109" , token , ( "%s names no value to capture" ) : format ( token . text ) )
elseif c . ownershipKind ( valueType ) ~= "affine" then
c . diag (
"NUPP2602" ,
token ,
(
"only an owner can be taken; %q is %s"
) : format ( token . text , valueType and T . tostring ( valueType ) or "unknown" )
)
elseif # ( valueType . cleanups or { } ) == 0 then
c . diag (
"NUPP2602" ,
token ,
( "opaque owner %q cannot be dropped by an uncalled closure" ) : format ( token . text )
)
else
local moveNode = { kind = "name" , token = token }
c . moveExpression ( moveNode , valueType , "closure capture" , "affine" )
captures [
# captures + 1
] = {
name = token . text ,
token = token ,
type = valueType ,
outer = state ,
move = moveNode . automaticOwnerMove ,
}
end
end
end
body . takenCaptures = captures

return captures
end

local function borrowedCaptures ( body )
if body . borrowCaptures then
return body . borrowCaptures
end
local captures , seen = { } , { }
local clause = body . captureBorrows
local names = clause and ( clause . names or clause . params ) or { }
for _ , token in ipairs ( names ) do
if seen [ token . text ] then
c . diag ( "NUPP2602" , token , ( "closure capture %q is repeated" ) : format ( token . text ) )
else
seen [ token . text ] = true
local entry = c . lookupEntry ( token . text )
local state = c . ownershipState ( entry )
if not state then
c . diag ( "NUPP2109" , token , ( "%s names no value to borrow" ) : format ( token . text ) )
elseif not c . ownershipKind ( state . t ) then
c . diag ( "NUPP2602" , token , ( "closure capture %q has no ownership lifetime" ) : format ( token . text ) )
else
captures [
# captures + 1
] = { name = token . text , token = token , root = c . borrowRoot ( state ) , outer = state , }
end
end
end
if clause and # names == 0 then
c . diag ( "NUPP2602" , clause , "borrows () retains nothing; name the closure's sources or drop the clause" )
end
body . borrowCaptures = captures

return captures
end

local function disambiguateBorrowCapture ( body )
local candidate = body . captureBorrowsCandidate
if not candidate or body . captureBorrows then
return
end
for _ , source in ipairs ( candidate . params or { } ) do
local entry = c . lookupEntry ( source . text )
local state = c . ownershipState ( entry )
if not state or not c . ownershipKind ( state . t ) then
return
end
end
body . captureBorrows = candidate
local inner = candidate . type
if inner then
if body . rets and body . rets [ 1 ] == candidate then
body . rets [ 1 ] = inner
end
local pack = body . returnPack
if pack and pack . kind == "tpack" and pack . types and pack . types [ 1 ] == candidate then
pack . types [ 1 ] = inner
end
end
end



c . checkFuncbody = function ( body , selfType )
local params , rets , paramModes , paramNames = { } , { } , { } , { }
disambiguateBorrowCapture ( body )
local captures = takenCaptures ( body )
local borrows = borrowedCaptures ( body )




local explicitSelf = selfType and body . params and body . params [ 1 ]
if not ( explicitSelf and explicitSelf . name and explicitSelf . name . text == "self" ) then
explicitSelf = nil
end
local inferredModes , declaredModes = inferredParameterModes ( body )
local receiverMode = nil
if explicitSelf then
local mode = inferredModes [ 1 ] or "borrows"
if not declaredModes [ 1 ] and mode ~= "takes" and not pointerShaped ( selfType ) then
mode = "plain"
end
body . receiverMode = mode
receiverMode = mode
end
local scopedCandidates = scopedCallbackParameters ( body , true )
local vararg = false
local varargType = nil
local varargMode = nil
local varargModeToken = nil
local typeParams , typeBounds , packParams , constParams , paramKinds
local expectedParams = nil
local expected = expectedFuncbodies [ body ]
if expected then
local expectedFunc = rawType ( expected )
if expectedFunc . tag == "func" then
expectedParams = expectedFunc . params
end
end
c . functionDepth = c . functionDepth + 1
c . functionBodies [ # c . functionBodies + 1 ] = body
c . pushScope ( )
c . scope . completionScope = body . body or body
local captureContext = { body = body , allowed = { } }
for _ , capture in ipairs ( borrows ) do
captureContext . allowed [ capture . name ] = capture
end
c . closureCaptureStack [ # c . closureCaptureStack + 1 ] = captureContext
if body . generics then
typeParams , typeBounds , packParams , constParams , paramKinds = c . bindGenerics ( body . generics , "function" )
end
for _ , capture in ipairs ( captures ) do
c . bindVar ( capture . name , capture . type , true , capture . token , "variable" )
local entry = c . scope . vars [ capture . name ]
if entry and entry . automaticOwner then
entry . automaticOwner . lowerable = true
entry . automaticOwner . capture = true
capture . inner = entry
capture . automaticOwner = entry . automaticOwner
end
end
body . takenCaptures = captures
if selfType then
local receiverType = receiverMode == "takes" and T . affine (
selfType
) or ( receiverMode == "borrows" or receiverMode == "exclusive" ) and T . borrowed ( selfType ) or selfType
c . bindVar (
"self" ,
receiverType ,
explicitSelf and explicitSelf . type ~= nil ,
explicitSelf and explicitSelf . name or nil ,
"parameter"
)
end
local paramPackTail = nil





for sourceIndex , p in ipairs ( body . params ) do
if p == explicitSelf then



elseif p . namedVararg then
vararg = true
varargMode = p . modeTok and p . modeTok . text or nil
varargModeToken = p . modeTok
if p . modeTok then
c . diag (
"NUPP2602" ,
p . modeTok ,
"an ownership-qualified typed vararg is unnamed and passes each original value directly"
)
end
if p . type then
if p . type . kind == "tpack" then
local pack = c . resolvePack ( p . type )
paramPackTail = pack . tail
else
varargType = c . resolveType ( p . type )
end
end
c . bindVar ( p . name . text , T . table_ , false , p . name , "parameter" , true )
elseif p . name then
local pt = p . constDomainTok and T . functionConst or p . type and c . resolveType (
p . type
) or ( expectedParams and expectedParams [ # params + 1 ] ) or T . any
if p . type then
c . fixedWidth . storageOnly ( p . type , pt , "a parameter" )





p . type . resolvedType = pt
end
params [ # params + 1 ] = pt
paramNames [ # params ] = p . name . text
local mode = inferredModes [ sourceIndex ] or "borrows"
if not declaredModes [ sourceIndex ] and scopedCandidates [ p . name . text ] and rawType ( pt ) . tag == "func" then
mode = "scoped"
end
if not declaredModes [ sourceIndex ] and mode ~= "takes" and not pointerShaped ( pt ) then
mode = "plain"
end
paramModes [ # params ] = mode
if mode == "retains" or mode == "releases" then
c . diag ( "NUPP2602" , p , mode .. " is only valid on imported cdef parameters" )
end
if ( mode == "retains" or mode == "releases" ) and not pointerShaped ( pt ) then
c . diag ( "NUPP2602" , p , mode .. " parameters must have a pointer-shaped type" )
end




local bound = mode == "takes" and (
pt . tag == "affine" and pt or T . affine ( pt )
) or ( mode == "borrows" or mode == "exclusive" ) and T . borrowed ( pt ) or pt
c . bindVar ( p . name . text , bound , p . type ~= nil , p . name , "parameter" )
c . fixedWidth . mark ( c . scope . vars [ p . name . text ] , pt )
c . fixedWidth . trust ( c . scope . vars [ p . name . text ] , pt )
if mode == "exclusive" then



c . own . capabilityFacts ( c . scope . vars [ p . name . text ] ) . exclusive = true
end
else
vararg = true
varargMode = p . modeTok and p . modeTok . text or nil
varargModeToken = p . modeTok
if p . type then
if p . type . kind == "tpack" then
local pack = c . resolvePack ( p . type )
paramPackTail = pack . tail
else
varargType = c . resolveType ( p . type )
end
end
end
end
if varargModeToken and not varargType then
c . diag ( "NUPP2602" , varargModeToken , "an ownership-qualified vararg needs one homogeneous type" )
end
if varargMode == "retains" or varargMode == "releases" then
c . diag ( "NUPP2602" , varargModeToken or body , varargMode .. " is only valid on imported cdef parameters" )
elseif varargMode == "takes" then
c . diag (
"NUPP2602" ,
varargModeToken or body ,
"takes is not valid on an unnamed typed vararg because the body cannot discharge individual owners"
)
end
local paramPack = T . pack (
params ,
paramPackTail or (
vararg and {
kind = varargType and "homogeneous" or "unknown" ,
type = varargType or T . any ,
mode = varargMode ,
} or nil
) ,
paramModes
)
local annotated = nil
local retPack
if body . returnPack then
retPack = c . resolvePack ( body . returnPack )
annotated = { }
for j , resultT in ipairs ( retPack . head ) do
annotated [ j ] , rets [ j ] = resultT , resultT
c . fixedWidth . storageOnly ( body . rets and body . rets [ j ] or body . returnPack , resultT , "a function result" )
end
else
rets [ 1 ] = T . any
retPack = T . pack ( { } , { kind = "unknown" , type = T . any } )
end
local yieldPack = body . yieldPack and c . resolvePack ( body . yieldPack ) or nil
local resumePack = body . resumePack and c . resolvePack ( body . resumePack ) or nil





local elidedSelfBorrow = selfType ~= nil and annotated ~= nil and annotated [
1
] ~= nil and annotated [
1
] . tag == "borrowed" and not ( body . rets and body . rets [ 1 ] and body . rets [ 1 ] . kind == "tborrows" )
if elidedSelfBorrow then
annotated [ 1 ] = rawType ( annotated [ 1 ] )
rets [ 1 ] = annotated [ 1 ]
end



local ownedReturns = { }
local ownsAResult = false



local normalized = T . pack ( annotated or { } , nil )
for j , ret in ipairs ( normalized . head or { } ) do
annotated [ j ] , rets [ j ] = ret , ret
if ret . tag == "affine" then
if j == 1 then
body . ownCleanups = ret . cleanups
end
ownsAResult = true
ownedReturns [ j ] = rawType ( ret )
end
end
for j , result in ipairs ( body . rets or { } ) do
if result . kind == "tpreserves" and annotated and annotated [ j ] then
ownsAResult = true
ownedReturns [ j ] = rawType ( annotated [ j ] )
end
end







if body . returnPack and not retPack . alternatives then
retPack = T . pack ( rets , retPack . tail , retPack . modes )
end
c . retStack [ # c . retStack + 1 ] = annotated or false
c . retPackStack [ # c . retPackStack + 1 ] = body . returnPack and retPack or false
c . varargPackStack [ # c . varargPackStack + 1 ] = vararg and T . pack ( { } , paramPack . tail ) or false
c . yieldPackStack [ # c . yieldPackStack + 1 ] = yieldPack or false
c . resumePackStack [ # c . resumePackStack + 1 ] = resumePack or false
local protocolContext = { yieldPacks = { } }
c . protocolStack [ # c . protocolStack + 1 ] = protocolContext
c . ownReturnStack [ # c . ownReturnStack + 1 ] = ownsAResult and ownedReturns or false
c . borrowReturnStack [
# c . borrowReturnStack + 1
] = ( body . rets and body . rets [ 1 ] and body . rets [ 1 ] . kind == "tborrows" and body . rets [ 1 ] ) or false
local consumingContext , consumingRoot
local resource , root = nil , nil
if selfType and receiverMode == "takes" then
resource , root = selfType , "self"
else
for j , p in ipairs ( body . params or { } ) do
if p . name and paramModes [ j ] == "takes" then
resource , root = params [ j ] , p . name . text
break
end
end
end
resource = resource and rawType ( resource ) or nil
consumingRoot = root
local affineFields = resource and resource . tag == "nominal" and resource . affineFields or nil
if affineFields and # affineFields > 0 then
local owned = { }
for _ , field in ipairs ( affineFields ) do
owned [ field ] = true
end
consumingContext = { root = root , allowed = owned , done = { } }
end
c . consumingFieldStack [ # c . consumingFieldStack + 1 ] = consumingContext or false


local loopClosure = c . loops . begin ( c . functionDepth - 1 )


local wasReturning = c . loops . setReturning ( false )
body . partitionResults = nil
body . partitionReturnSeen = { }
c . checkBlock ( body . body , true )
c . closureCaptureStack [ # c . closureCaptureStack ] = nil
if # captures > 0 and body . body and not body . captureBindingStat then
local captureStat = {
kind = "localStmt" ,
names = { } ,
types = { } ,
exprs = { } ,
automaticOwners = { } ,
syntheticCapture = true ,
}
for j , capture in ipairs ( captures ) do
local value = { kind = "name" , token = capture . token , captureValue = true }
value [ 1 ] = capture . token
captureStat . names [ j ] = capture . token
captureStat . exprs [ j ] = value
captureStat . automaticOwners [ j ] = capture . automaticOwner
if capture . automaticOwner then
capture . automaticOwner . stat = captureStat
capture . automaticOwner . index = j
capture . automaticOwner . expr = value
capture . automaticOwner . type = capture . type
end
end
body . captureBindingStat = captureStat
table . insert ( body . body . stats , 1 , captureStat )
table . insert ( body . body , 1 , captureStat )
end
c . loops . setReturning ( wasReturning )
c . loops . finish ( loopClosure , body )





if paramPackTail and paramPackTail . kind == "generic" then
local uses , transfers = 0 , 0
local transferred = { }
local function isVararg ( node )
return node and not cst . isToken ( node ) and node . kind == "vararg"
end

local function walk ( node )
if not node or cst . isToken ( node ) then
return
end
if node . kind == "funcbody" or node . kind == "shortfn" then
return
end
if node . kind == "vararg" then
uses = uses + 1
return
elseif node . kind == "returnStmt" then
local exprs = node . exprs or { }
local last = exprs [ # exprs ]
if isVararg (
last
) and retPack . tail and retPack . tail . kind == "generic" and retPack . tail . var == paramPackTail . var then
transfers = transfers + 1
transferred [ last ] = true
end
elseif node . kind == "call" or node . kind == "methodCall" or node . kind == "safeCall" then
local args = node . args and node . args . exprs or { }
local last = args [ # args ]
local signature = node . signatureType
local tail = signature and signature . tag == "func" and signature . paramPack . tail or nil
if isVararg ( last ) and tail and tail . kind == "generic" and tail . var == paramPackTail . var then
transfers = transfers + 1
transferred [ last ] = true
end
end
for _ , child in ipairs ( node ) do
if not cst . isToken ( child ) and not transferred [ child ] then
walk ( child )
end
end
end

walk ( body . body )
if uses ~= 0 or transfers ~= 1 then
c . diag (
"NUPP2605" ,
body ,
"a potentially affine generic argument pack must be " .. "forwarded exactly once"
)
end
end
if consumingRoot then
local terminal = ownershipState ( c . lookupEntry ( consumingRoot ) )
if terminal then
terminal . moved = true
end
end
c . consumingFieldStack [ # c . consumingFieldStack ] = nil
if consumingContext then
for field in pairs ( consumingContext . allowed ) do
if not consumingContext . done [ field ] then
c . diag ( "NUPP2603" , body , ( "consuming function leaves owned field %q live" ) : format ( field ) )
end
end
end
c . borrowReturnStack [ # c . borrowReturnStack ] = nil
c . protocolStack [ # c . protocolStack ] = nil
c . varargPackStack [ # c . varargPackStack ] = nil
c . yieldPackStack [ # c . yieldPackStack ] = nil
c . resumePackStack [ # c . resumePackStack ] = nil
c . ownReturnStack [ # c . ownReturnStack ] = nil
c . retStack [ # c . retStack ] = nil
c . retPackStack [ # c . retPackStack ] = nil
c . popScope ( )
c . functionBodies [ # c . functionBodies ] = nil
c . functionDepth = c . functionDepth - 1
if not yieldPack and # protocolContext . yieldPacks > 0 then
yieldPack = T . packUnion ( protocolContext . yieldPacks )
resumePack = T . pack ( { } , { kind = "unknown" , type = T . any } )
end






local noreturn = c . alwaysRaises ( body . body ) and not c . returnsSomewhere ( body . body )
local predicate
local first = body . rets and body . rets [ 1 ]
if first and first . kind == "tpredicate" then
local want = first . param . text
local at
for j , p in ipairs ( body . params or { } ) do
if p . name and p . name . text == want then
at = j
end
end
if not at then
c . diag ( "NUPP2109" , first , ( "%s names no parameter of this " .. "function" ) : format ( want ) )
else
local target = c . resolveType ( first . type )
if not ( isA ( target , params [ at ] ) or params [ at ] == T . any ) then
c . diag (
"NUPP2110" ,
first ,
( "%s cannot be a %s, so this " .. "predicate can never hold" ) : format ( want , T . tostring ( target ) )
)
else
predicate = { param = at , type = target }
end
end
end
local borrowsParam , borrowsSelf , borrowsParams
if elidedSelfBorrow then
borrowsSelf = true
end
if first and first . kind == "tborrows" then
borrowsParams = { }
for _ , sourceToken in ipairs ( first . params or { first . param } ) do
local want = sourceToken . text
local found


if want == "self" and selfType then
borrowsSelf = true
found = true
else
for j , p in ipairs ( body . params or { } ) do
if p . name and p . name . text == want then
found = j
end
end
end
if not found then
c . diag ( "NUPP2109" , sourceToken , ( "%s names no parameter of this function" ) : format ( want ) )
elseif type ( found ) == "number" and paramModes [ found ] == "takes" then
c . diag (
"NUPP2618" ,
sourceToken ,
( "%s is consumed by this function, so its result " .. "cannot borrow from it" ) : format ( want )
)
elseif type ( found ) == "number" then
borrowsParams [ # borrowsParams + 1 ] = found
end
end
if # borrowsParams == 1 then
borrowsParam , borrowsParams = borrowsParams [ 1 ] , nil
end
end



if ( borrowsParam or borrowsSelf or borrowsParams ) and rets [ 1 ] and rets [ 1 ] . tag ~= "affine" then
rets [ 1 ] = T . borrowed ( rawType ( rets [ 1 ] ) )
end
if body . returnPack and not retPack . alternatives then
retPack = T . pack ( rets , retPack . tail , retPack . modes )
end

local preservesResults , explicitPreserves = preservationResults (
body ,
paramNames ,
params ,
rets ,
paramModes ,
typeParams ~= nil ,
true
)
local callable = T . func (
params ,
rets ,
vararg ,
paramModes ,
predicate ,
typeParams ,
typeBounds ,
borrowsParam ,
borrowsSelf ,
borrowsParams ,
nil ,
varargType ,
noreturn ,
paramPack ,
retPack ,
packParams ,
yieldPack ,
resumePack ,
nil ,
paramNames ,
preservesResults ,
nil ,
constParams ,
paramKinds ,
body . partitionResults ,
nil ,
explicitPreserves
)
if # captures > 0 then
return T . affine ( callable , { T . closureCleanup ( ) } )
end

return callable
end




c . signatureOf = function ( body , selfType )
local params , modes , paramNames = { } , { } , { }
local inferredModes , declaredModes = inferredParameterModes ( body or { } )
local scopedCandidates = scopedCallbackParameters ( body or { } , false )
local explicitSelf = selfType and body and body . params and body . params [ 1 ]
if not ( explicitSelf and explicitSelf . name and explicitSelf . name . text == "self" ) then
explicitSelf = nil
end
local typeParams , typeBounds , packParams , constParams , paramKinds
c . pushScope ( )
if body and body . generics then
typeParams , typeBounds , packParams , constParams , paramKinds = c . bindGenerics ( body . generics , "function" )
end
if selfType then
params [ 1 ] = selfType
local mode = "plain"
if explicitSelf then
mode = inferredModes [ 1 ] or "borrows"
if not declaredModes [ 1 ] and mode ~= "takes" and not pointerShaped ( selfType ) then
mode = "plain"
end
body . receiverMode = mode
end
modes [ 1 ] = mode
paramNames [ 1 ] = "self"
end
local varargType = nil
local paramPackTail = nil
local vararg = body and body . varargs or false
for sourceIndex , p in ipairs ( body and body . params or { } ) do
if p == explicitSelf then

elseif p . name and not p . namedVararg then
local pt = p . constDomainTok and T . functionConst or p . type and c . resolveType ( p . type ) or T . any
local mode = inferredModes [ sourceIndex ] or "borrows"
if not declaredModes [ sourceIndex ] and scopedCandidates [ p . name . text ] and rawType ( pt ) . tag == "func" then
mode = "scoped"
end
if not declaredModes [ sourceIndex ] and mode ~= "takes" and not pointerShaped ( pt ) then
mode = "plain"
end
params [ # params + 1 ] = pt
modes [ # modes + 1 ] = mode
paramNames [ # params ] = p . name . text
else

vararg = true
if p . type then
if p . type . kind == "tpack" then
local pack = c . resolvePack ( p . type )
paramPackTail = pack . tail
else
varargType = c . resolveType ( p . type )
end
end
end
end
local paramPack = T . pack (
params ,
paramPackTail or (
vararg and { kind = varargType and "homogeneous" or "unknown" , type = varargType or T . any } or nil
) ,
modes
)
local retPack = body and body . returnPack and c . resolvePack ( body . returnPack ) or T . pack ( { } , {
kind = "unknown" ,
type = T . any
} )




local rets = body and body . returnPack and retPack . head or { T . any }
local yieldPack = body and body . yieldPack and c . resolvePack ( body . yieldPack ) or nil
local resumePack = body and body . resumePack and c . resolvePack ( body . resumePack ) or nil
c . popScope ( )

local preservesResults , explicitPreserves = preservationResults (
body ,
paramNames ,
params ,
rets ,
modes ,
typeParams ~= nil ,
false
)

return T . func (
params ,
rets ,
vararg ,
modes ,
nil ,
typeParams ,
typeBounds ,
nil ,
nil ,
nil ,
nil ,
varargType ,
false ,
paramPack ,
retPack ,
packParams ,
yieldPack ,
resumePack ,
nil ,
paramNames ,
preservesResults ,
nil ,
constParams ,
paramKinds ,
nil ,
nil ,
explicitPreserves
)
end

c . apply . checkFuncbodyExpected = function ( body , expected )
expectedFuncbodies [ body ] = expected
local inferred = c . checkFuncbody ( body )
expectedFuncbodies [ body ] = nil

return inferred
end

c . inferredParameterModes = inferredParameterModes

local handlers = { }

local function checkLocalFuncStmt ( stat )
local nameTok , body = stat . name , stat . body
if not nameTok or not body then
return
end

c . bindVar ( nameTok . text , T . any , false , nameTok , "function" , stat . isConst )
body . jitDefinition = nameTok . definition
if stat . comptimeFunction then
local entry = c . scope . vars [ nameTok . text ]
if entry and entry . definition then
entry . definition . comptimeFunction = true
end
end
local ft = c . checkFuncbody ( body )
c . bindVar ( nameTok . text , ft )
local functionEntry = c . scope . vars [ nameTok . text ]
if functionEntry then
functionEntry . jitTarget = functionEntry . definition
end
if ft . tag == "affine" then
local entry = c . scope . vars [ nameTok . text ]
local automatic = entry and entry . automaticOwner
local initializer = { kind = "funcExpr" , body = body , affineLocal = true }
stat . affineInitializer = initializer
if automatic then
automatic . lowerable = true
automatic . stat = stat
automatic . index = 1
automatic . expr = initializer
automatic . type = ft
stat . automaticOwners = { automatic }
end
end



c . unused . declared ( nameTok , c . scope . vars [ nameTok . text ] , "function" )
c . raises . check ( stat , body )
end

handlers . localFuncStmt = function ( stat )
if stat . comptimeTok then
comptimeFunction . checkLocal ( c , stat , checkLocalFuncStmt )
else
checkLocalFuncStmt ( stat )
end
end

local function checkFuncStmt ( stat )
local fname , body = stat . name , stat . body
if not fname or fname . kind ~= "funcname" or not body then
return
end
local selfType = nil


local owner , member = nil , nil
local ownerKey , memberTok = c . funcOwner ( fname )
if ownerKey then
local named = c . lookupType ( ownerKey )
if named and named . tag == "nominal" and named . byname then
owner = named
member = memberTok and memberTok . text
end
end
if fname . method then
selfType = owner or T . any
end
if not fname . method and # fname == 1 and fname . base then
c . bindVar ( fname . base . text , T . any , false , fname . base , "function" )
end
local earlyMemberDefinition = memberTok and c . definition (
memberTok ,
fname . method and "method" or "function"
) or nil
body . jitDefinition = earlyMemberDefinition or ( fname . base and fname . base . definition or nil )
local ft = c . checkFuncbody ( body , selfType )
c . raises . check ( stat , body )
local memberDefinition = earlyMemberDefinition
if memberDefinition then
memberDefinition . type = ft
c . markToken ( memberTok , memberDefinition , ft , memberDefinition . kind )
end
if not fname . method and ownerKey and memberTok and memberDefinition then
c . qualifiedFunctionEntries [ ownerKey .. "." .. memberTok . text ] = { t = ft , definition = memberDefinition , }
end
if stat . comptimeFunction then
stat . comptimeSignature = ft
stat . comptimeDefinition = memberDefinition
return
end


if not fname . method and ownerKey == c . moduleLocal and memberTok then
c . moduleFields [ memberTok . text ] = ft
c . moduleFieldTokens [ memberTok . text ] = memberTok
c . moduleFieldDefs [ memberTok . text ] = memberDefinition
c . moduleExports . valueDefs [ memberTok . text ] = memberDefinition


c . moduleFieldValues [ memberTok . text ] = body
local declarations = c . moduleFunctionDeclarations [ memberTok . text ] or { }
for j = # declarations , 1 , - 1 do
local pending = declarations [ j ]
if pending . body == body then
pending . signature = ft
break
end
end
end







if not fname . method and not owner and ownerKey and memberTok then
c . applyFacts ( { [ ownerKey .. "." .. memberTok . text ] = ft } )
end
if owner and owner . declKind == "struct" then

stat . structOwner = owner . runtimePath or ownerKey
stat . memberName = member
end
if owner and member and ft . tag == "func" then
local stored
if fname . method then


local params = { selfType }
for _ , p in ipairs ( ft . params ) do
params [ # params + 1 ] = p
end
local modes = { body . receiverMode or "plain" }
local names = { "self" }
for _ , mode in ipairs ( ft . paramModes or { } ) do
modes [ # modes + 1 ] = mode
end
for _ , name in ipairs ( ft . paramNames or { } ) do
names [ # names + 1 ] = name
end
local preserves = { }
for result = 1 , # ft . rets do
local source = ft . preservesResults and ft . preservesResults [ result ]
if source then
preserves [ result ] = source + 1
end
end
owner . byname [
member
] = T . func (
params ,
ft . rets ,
ft . vararg ,
modes ,
ft . predicate ,
ft . typeParams ,
ft . typeBounds ,
ft . borrowsParam ,
ft . borrowsSelf ,
ft . borrowsParams ,
ft . ffiOut ,
ft . varargType ,
ft . noreturn ,
T . pack ( params , ft . paramPack . tail , modes ) ,
ft . retPack ,
ft . packParams ,
ft . yieldPack ,
ft . resumePack ,
ft . noYield ,
names ,
next ( preserves ) and preserves or nil ,
ft . foreign ,
ft . constParams ,
ft . paramKinds ,
ft . partitionResults ,
ft . comptimeOnly ,
ft . explicitPreserves
)
owner . writeByname [ member ] = owner . byname [ member ]
owner . fieldDefs [ member ] = owner . fieldDefs [ member ] or memberDefinition
owner . writeFieldDefs [ member ] = owner . writeFieldDefs [ member ] or memberDefinition
stored = owner . byname [ member ]
elseif owner . declKind == "record" or owner . declKind == "interface" then
owner . staticByname [ member ] = ft
owner . staticWriteByname [ member ] = ft
owner . staticFieldDefs [ member ] = owner . staticFieldDefs [ member ] or memberDefinition
owner . staticWriteFieldDefs [ member ] = owner . staticWriteFieldDefs [ member ] or memberDefinition
stored = ft
else
owner . byname [ member ] = ft
owner . writeByname [ member ] = ft
owner . fieldDefs [ member ] = owner . fieldDefs [ member ] or memberDefinition
owner . writeFieldDefs [ member ] = owner . writeFieldDefs [ member ] or memberDefinition
stored = ft
end
if stored then
c . nominalEffectOwners [ owner ] = true
c . nominalEffectEntries [
# c . nominalEffectEntries + 1
] = {
owner = owner ,
member = member ,
static = not fname . method and ( owner . declKind == "record" or owner . declKind == "interface" ) ,
signature = stored ,
body = body ,
}
end
if owner . fieldOrder and ( fname . method or owner . declKind == "struct" ) then
owner . fieldOrder [ # owner . fieldOrder + 1 ] = member
end
end
if not fname . method and # fname == 1 and fname . base then
c . bindVar ( fname . base . text , ft )
end
end

handlers . funcStmt = function ( stat )
if stat . comptimeTok then
comptimeFunction . checkQualified ( c , stat , checkFuncStmt )
else
checkFuncStmt ( stat )
end
end

return handlers
end

return functions
