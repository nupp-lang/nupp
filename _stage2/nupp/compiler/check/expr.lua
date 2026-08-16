_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);












local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.relations" )
local narrowing = require ( "nupp.compiler.narrowing" )
local cst = require ( "nupp.compiler.cst" )
local lexer = require ( "nupp.compiler.lexer" )
local operators = require ( "nupp.compiler.check.operators" )
local index = require ( "nupp.compiler.check.index" )
local state = require ( "nupp.compiler.check.state" )
local callexpr = require ( "nupp.compiler.check.callexpr" )
local comptime = require (
"nupp.compiler.comptime"
)
local materializeProviders = require ( "nupp.compiler.materialize.providers" )



local materializeIR = require ( "nupp.compiler.materialize.ir" )



local stable = require ( "nupp.compiler.build.cache" ) . stable
local fixedWidth = require ( "nupp.compiler.fixed_width" )

local expr = { }

local isA = relations . isA
local rawType = T . unwrapOwnership
local subtract = narrowing . subtract
















local EXPANDS = { call = true , methodCall = true , safeCall = true , vararg = true }

expr . EXPANDS = EXPANDS





function expr . install ( c )



local expectedShortfns = { }

local function visibleNames ( )
local names = { }
local scope = c . scope
while scope do
for name in pairs ( scope . vars or { } ) do
names [ name ] = true
end
scope = scope . parent
end
for name in pairs ( c . env and c . env . globals or { } ) do
names [ name ] = true
end

return names
end

c . numericOperand = function ( t , node , op )
if t == T . any or isA ( t , T . number ) then
return true
end
c . diag ( "NUPP2003" , node , ( "cannot apply '%s' to %s" ) : format ( op , T . tostring ( t ) ) )

return false
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


local function numberLiteralType ( text )
local lower = text : gsub ( "_" , "" ) : lower ( )
if lower : find ( "ull" , 1 , true ) then
return T . uint64
end
if lower : find ( "ll" , 1 , true ) then
return T . int64
end
if lower : sub ( - 1 ) == "i" then
return T . number
end
if lower : find ( "x" , 1 , true ) then
if lower : find ( "%." ) or lower : find ( "p" ) then
return T . number
end
return T . integer
end
if lower : find ( "%." ) or lower : find ( "e" ) then
return T . number
end

return T . integer
end
















local function comptimeType ( untypedNode )
local node = untypedNode
c . pushScope ( )
c . retStack [ # c . retStack + 1 ] = false
c . retPackStack [ # c . retPackStack + 1 ] = false
c . comptimeDepth = ( c . comptimeDepth or 0 ) + 1
if node . body then
c . checkBlock ( node . body , true )
end
c . comptimeDepth = c . comptimeDepth - 1
c . retPackStack [ # c . retPackStack ] = nil
c . retStack [ # c . retStack ] = nil
c . popScope ( )

local reflections , layouts = { } , { }
local function collectComptimeFacts ( value )
if type ( value ) ~= "table" then
return
end
if value . reflectedTypeKey and value . reflectedType then
reflections [ value . reflectedTypeKey ] = value . reflectedType
end
if value . targetLayoutKey and value . targetLayout then
layouts [ value . targetLayoutKey ] = value . targetLayout
end
for _ , child in ipairs ( value ) do
collectComptimeFacts ( child )
end
end

collectComptimeFacts ( node . body )
local quoted , resultType , failure , envelope = comptime . evaluate (
untypedNode ,
node . body ,
reflections ,
layouts ,
c . comptimeFunctions ,
c . env and c . env . host or nil
)
if failure then
c . diag (
failure . code ,
failure . node or node ,
failure . message ,
nil ,
failure . help and { help = failure . help } or nil
)
return T . any
end
if envelope then
local lowered , lowerFailure , lowering , inferredTarget = materializeProviders . lower (
envelope ,
node . materializationExpected ,
c . env
)
if lowerFailure then
c . diag (
lowerFailure . code ,
node ,
lowerFailure . message ,
nil ,
lowerFailure . help and { help = lowerFailure . help } or nil
)
return T . any
end
local rendered , renderFailure = materializeIR . render ( lowered )
if renderFailure then
c . diag ( "NUPP2416" , node , renderFailure . message )
return T . any
end
node . materializedIR = lowered
node . materializationEnvelope = envelope
lowering = lowering or { }
node . materializationObservation = {
provider = envelope . provider ,
schema = envelope . schema ,
fingerprint = envelope . fingerprint ,
backend = lowering . backend or "direct" ,
blueprintSize = # stable ( envelope . payload ) ,
generatedSize = # ( rendered or "" ) ,
runtimeFeatures = lowering . runtimeFeatures or { } ,
abis = {
provider = envelope . schema ,
registry = materializeProviders . ABI ,
emitter = lowering . emitterAbi or 1 ,
helper = lowering . helperAbi or 0 ,
runtimeExpression = materializeIR . ABI ,
} ,
blueprint = envelope ,
generated = rendered ,
}

if node . materializationExpected then
node . comptimeResultType = node . materializationExpected
return node . materializationExpected
end
node . comptimeResultType = inferredTarget or T . any
return node . comptimeResultType
end
node . comptimeValue = quoted
node . comptimeResultType = resultType or T . any

return node . comptimeResultType
end




local handlers = { }
for _ , installed in ipairs ( { operators . install ( c ) , index . install ( c ) , callexpr . install ( c ) , } ) do
for kind , handle in pairs ( installed ) do
handlers [ kind ] = handle
end
end



local function inferExpr ( node )
local handle = handlers [ node . kind ]
if handle then
return handle ( node )
end
local kind = node . kind
if kind == "number" then
local literal = node . token
if not literal then
return T . number
end
local base = numberLiteralType ( literal . text )
local value = tonumber ( ( literal . text : gsub ( "_" , "" ) ) )
if value and ( base == T . integer or base == T . number ) then
c . fixedWidth . markLiteral ( node , value )
return T . literal ( value , base )
end
return base
elseif kind == "string" then
local literal = node . token
if not literal then
return T . string
end
local text = literal . text
local body = text : match ( "^[\"']" ) and text : sub ( 2 , - 2 ) or nil
if body then
return T . literal ( body , T . string )
end
return T . string
elseif kind == "dedentString" then
return T . string
elseif kind == "nilExpr" then
return T . nil_
elseif kind == "trueExpr" then
return T . literal ( true , T . boolean )
elseif kind == "falseExpr" then
return T . literal ( false , T . boolean )
elseif kind == "vararg" then
local pack = c . varargPackStack [ # c . varargPackStack ]
if not pack then
return T . any
end
node . valuePack = pack
c . lastCallRets = pack . head
return T . packAt ( pack , 1 ) or T . nil_
elseif kind == "name" then
local nameTok = node . token
if not nameTok then
return T . any
end
local nameText = nameTok . text
local entry = c . lookupEntry ( nameText )



if entry and entry . requiredModule then
node . requiredModule = entry . requiredModule
end
local capturedType = nil
if entry and entry . definition and entry . definition . comptimeFunction and (
c . comptimeDepth or 0
) == 0 and ( c . comptimeFunctionDepth or 0 ) == 0 then
c . diag ( "NUPP2415" , node , ( "comptime function %q has no runtime value" ) : format ( nameText ) , nil , {
help = "call it from a comptime block or another comptime function"
} )
end
node . immutablePath = entry and entry . constant == true or false
local capabilityFacts = entry and c . own . capabilityFacts ( entry , nil , false ) or nil
if capabilityFacts and capabilityFacts . roots then
c . own . capabilityFacts ( node ) . roots = capabilityFacts . roots
end
if entry then
local state = c . ownershipState ( entry )
if state . moved then
local related = state . movedAt and c . related ( state . movedAt , "owner was moved here" ) or nil
c . diag ( "NUPP2601" , node , ( "owner %q was moved and cannot be used" ) : format ( nameText ) , nil , {
related = related and { related } or nil ,
help = "use the owner before this transfer, or borrow it " .. "instead of moving it"
} )
node . ownershipUseReported = true
elseif c . ownershipKind (
entry . t
) and (
entry . functionDepth or 0
) < c . functionDepth and not ( c . ownershipKind ( entry . t ) == "borrowed" and c . scopedCaptureDepth > 0 ) then
local context = c . closureCaptureStack [ # c . closureCaptureStack ]
local capture = context and context . allowed [ nameText ] or nil
if context and not capture and not context . body . captureBorrows then
capture = { name = nameText , token = nameTok , root = c . borrowRoot ( state ) , outer = state , }
context . allowed [ nameText ] = capture
context . body . borrowCaptures [ # context . body . borrowCaptures + 1 ] = capture
end
if capture then
c . own . capabilityFacts ( node ) . roots = { capture . root }
capturedType = T . borrowed ( rawType ( entry . t ) )
elseif not node . ownershipCaptureReported then

local capturedKind = c . ownershipKind ( entry . t )
c . diag (
"NUPP2603" ,
node ,
( "%s value %q has no closure borrow contract" ) : format ( capturedKind , nameText ) ,
nil ,
{ help = "name the source in borrows (...) or let an expression closure infer it" }
)
node . ownershipCaptureReported = true
end
end
end
if entry and entry . globalModule and entry . globalModule ~= c . result . moduleName then
c . result . implicitSideEffects [ entry . globalModule ] = true
end
if not entry and c . env and c . env . resolveProjectValue then
local valueType , valueDef , valueErr , sideEffectModule , conflicts = c . env . resolveProjectValue (
c . env ,
c . filename ,
nameText
)
if valueType then



if sideEffectModule then
c . result . implicitSideEffects [ sideEffectModule ] = true
end
c . markToken ( nameTok , valueDef , valueType , valueDef and valueDef . kind or "variable" )
return valueType
elseif valueErr then
local related , seen = { } , { }
for _ , conflict in ipairs ( conflicts or { } ) do
local definition = conflict . definition
local key = definition and (
tostring (
definition . filename
) .. ":" .. tostring ( definition . token and definition . token . offset )
) or tostring ( conflict )
if not seen [ key ] then
seen [ key ] = true
local item = c . related ( definition , "conflicting global value declared here" )
if item then
related [ # related + 1 ] = item
end
end
end
c . diag (
"NUPP2104" ,
node ,
( "ambiguous global %q; a project global must be unique" ) : format ( nameText ) ,
nil ,
{
related = related ,
help = "make all but one declaration local or attach " .. "them to their module tables"
}
)
return T . any
end
end
c . markToken (
nameTok ,
entry and entry . definition ,
entry and entry . t or T . any ,
entry and entry . definition and entry . definition . kind or "variable"
)
if not entry then




local advice , isModule , fixes = c . missingRequire ( nameText )
if advice then
c . diag ( "missing-require" , node , advice , fixes )
elseif not isModule and c . opts and c . opts . strict then
fixes = c . edits . nameSpellingFix ( nameTok , visibleNames ( ) )
c . diag ( "NUPP2105" , nameTok , ( "unknown variable %q" ) : format ( nameText ) , fixes , {
help = fixes
and "use the suggested visible name"
or "declare the value, require its module, or correct "
.. "the spelling"
} )
end
end
if entry and entry . unassigned then
c . diag ( "NUPP2207" , nameTok , ( "%s is read before it holds a value" ) : format ( nameText ) , nil , {
related = entry . unassignedAt and {
c . related (
{ filename = c . filename , token = entry . unassignedAt , name = nameText } ,
"declared here, with no value"
)
} or nil ,
help = (
"assign it first, or declare it as %s? if it is " .. "meant to start empty"
) : format ( T . tostring ( entry . t ) )
} )


entry . unassigned = nil
end
c . fixedWidth . copyBinding ( node , entry )
return capturedType or ( entry and entry . t or T . any )
elseif kind == "paren" then
local inner = node . expr
local out = inner and c . infer ( inner ) or T . any
if inner and inner . valuePack then
c . checkPackDiscard ( inner . valuePack , 2 , node )
end
node . immutablePath = inner and inner . immutablePath or false
c . fixedWidth . copy ( node , inner )
return out
elseif kind == "comptimeExpr" then
return comptimeType ( node )
elseif kind == "newExpr" then



local call = node . call
if not call then
return T . any
end
call . isNew = true



local named = call . obj and c . pathKey ( call . obj ) or nil
local declared = named and c . lookupType ( named ) or nil
local buildable = declared and declared . tag == "nominal" and (
declared . declKind == "record" or declared . declKind == "struct"
)
if declared and not buildable then
local why = "`new` builds a record or a struct"
if declared . tag == "nominal" and declared . declKind == "interface" then
why = "an interface declares a contract and has no runtime "
.. "table to stamp; construct a record that declares it "
.. "with `is`"
elseif declared . tag == "union" then
why = "a union is one of its members, and a value of it is " .. "written as one of them"
end
c . diag ( "NUPP2206" , call . obj or node , ( "%s cannot be constructed" ) : format ( named ) , nil , { help = why } )
call . newReported = true
end
local result = c . infer ( call )
node . partitionFields = call . partitionFields
c . fixedWidth . copy ( node , call )
return result
elseif kind == "unsafeOwnershipExpr" then
local value = node . expr
local valueT = value and c . infer ( value ) or T . any
if node . operation == "release" then
if c . ownershipKind ( valueT ) ~= "affine" then
c . diag ( "NUPP2602" , value or node , "unsafe release expects an affine value" )
end
c . moveExpression ( value or node , valueT , "unsafe release" )
node . ownershipIntrinsic = "release"
return rawType ( valueT )
else
local target = c . resolveType ( node . type )
if target . tag ~= "affine" then
c . diag ( "NUPP2602" , node . type or node , "unsafe adopt target must be an affine type" )
return target
end
if c . ownershipKind ( valueT ) then
c . diag ( "NUPP2602" , value or node , "unsafe adopt expects an unmanaged value" )
end
local representation = rawType ( target )
if valueT ~= T . any and not isA ( valueT , representation ) then
c . diag (
"NUPP2602" ,
value or node ,
( "cannot adopt %s as owner of %s" ) : format ( T . tostring ( valueT ) , T . tostring ( representation ) )
)
end
node . ownerCleanups = target . cleanups
node . ownershipIntrinsic = "adopt"
return target
end
elseif kind == "ternary" then
local cond , ifTrue , ifFalse = node . cond , node . ifTrue , node . ifFalse
if not cond or not ifTrue or not ifFalse then
return T . any
end
c . infer ( cond )
local facts = c . analyzeCond ( cond )
c . pushScope ( )
c . applyFacts ( facts . t )
local tt = c . infer ( ifTrue )
c . popScope ( )
c . pushScope ( )
c . applyFacts ( facts . f )
local ft = c . infer ( ifFalse )
c . popScope ( )
c . fixedWidth . intersect ( node , ifTrue , ifFalse )
return T . union ( { tt , ft } )
elseif kind == "castExpr" then
local cast = node . expr
if not cast then
return c . resolveType ( node . type )
end
local source = c . infer ( cast )
local target = c . resolveType ( node . type )
c . fixedWidth . storageOnly ( node . type , target , "a cast result" )
node . fixedWidthEstablished = nil
node . fixedWidthTrusted = nil
node . fixedWidthCallableUntrusted = target . tag == "func" and true or nil
if c . ownershipKind ( target ) then
if c . ownershipKind ( target ) == "pinned" and c . ownershipKind ( source ) ~= "pinned" then
c . diag ( "NUPP2604" , node , "a pinned(T) value must be constructed with nupp.pin(pointer, anchor)" )
end
return target
end
if source . tag == "affine" then
return T . affine ( target , source . cleanups , source . transferOnly , source . obligation )
elseif c . ownershipKind ( source ) == "borrowed" then
return T . borrowed ( target )
elseif c . ownershipKind ( source ) == "pinned" then
return T . pinned ( target )
end
return target
elseif kind == "isExpr" then
local subject = node . expr
local from = subject and c . infer ( subject ) or nil
local target = c . resolveType ( node . type )










if from and target and subject and c . pathKey (
subject
) and from ~= T . any and from . tag ~= "typevar" and from ~= T . never and target ~= T . any then



local admitsNil = isA ( T . nil_ , from )
local present = admitsNil and subtract ( from , T . nil_ ) or from
if present ~= T . never and present . tag ~= "typevar" and isA ( present , target ) then
node . provenStatically = true
node . provenNeedsNil = admitsNil




elseif (
rawType ( present ) . tag == "metatable" or rawType ( present ) . tag == "typeobject"
) and target . tag == "nominal" then
node . refutedStatically = true
end
end
return T . boolean
elseif kind == "funcExpr" then
local body = node . body
local inferred = body and c . checkFuncbody ( body ) or T . any
if body and not body . returnPack then
node . fixedWidthCallableUntrusted = true
end
local captures = body and body . borrowCaptures or { }
if # captures > 0 then
local roots = { }
for _ , capture in ipairs ( captures ) do
roots [ # roots + 1 ] = capture . root
end
c . own . capabilityFacts ( node ) . roots = roots
if not c . ownershipKind ( inferred ) then
inferred = T . borrowed ( inferred )
end
end
return inferred
elseif kind == "shortfn" then
c . pushScope ( )
c . scope . completionScope = node . body or node
local params , paramNames = { } , { }
local vararg = false
local expectedParams = nil
local expected = expectedShortfns [ node ]
if expected then
local expectedFunc = rawType ( expected )
if expectedFunc . tag == "func" then
expectedParams = expectedFunc . params
end
end
for _ , p in ipairs ( node . params ) do
if p . kind == "param" then
local pt = p . type and c . resolveType (
p . type
) or ( expectedParams and expectedParams [ # params + 1 ] ) or T . any
local pname = p . name
if p . namedVararg then
vararg = true
if pname then
c . bindVar ( pname . text , T . table_ , false , pname , "parameter" , true )
end
else
params [ # params + 1 ] = pt
paramNames [ # params ] = pname and pname . text or ""
if pname then
if p . type then
c . fixedWidth . storageOnly ( p . type , pt , "a parameter" )
end
c . bindVar ( pname . text , pt , p . type ~= nil , pname , "parameter" )
c . fixedWidth . mark ( c . scope . vars [ pname . text ] , pt )
c . fixedWidth . trust ( c . scope . vars [ pname . text ] , pt )
end
end
end
end
local rets
local retPack


local loopClosure = c . loops . begin ( c . functionDepth )
local wasReturning = c . loops . setReturning ( false )
if node . expr then
local first = c . infer ( node . expr )
retPack = node . expr . valuePack or T . pack ( { first } )
rets = retPack . head
for index , result in ipairs ( rets ) do
node . expr . fixedWidthResultIndex = index
if fixedWidth . isValue ( result ) and not c . fixedWidth . established ( node . expr , result ) then
node . fixedWidthCallableUntrusted = true
end
end
else
c . retStack [ # c . retStack + 1 ] = false
c . retPackStack [ # c . retPackStack + 1 ] = false
c . checkBlock ( node . body , true )
c . retStack [ # c . retStack ] = nil
c . retPackStack [ # c . retPackStack ] = nil
rets = { T . any }
retPack = T . pack ( { } , { kind = "unknown" , type = T . any } )
node . fixedWidthCallableUntrusted = true
end
c . loops . setReturning ( wasReturning )
c . loops . finish ( loopClosure , node )
c . popScope ( )
return T . func (
params ,
rets ,
vararg ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
T . pack ( params , vararg and { kind = "unknown" , type = T . any } or nil ) ,
retPack ,
nil ,
nil ,
nil ,
nil ,
paramNames
)
elseif kind == "istring" then

for _ , e in ipairs ( node . parts ) do
c . infer ( e )
end
return T . string
elseif kind == "tableExpr" then
local positional , named = { } , { }
local aggregateMoves , aggregateRoots = { } , { }
local ownsElements = false
local rootSeen = { }
if node . affineAggregateContext then
node . affineAggregate = true
end






local function widened ( t )
if t . tag == "literal" then
return t . base or T . string
end
return t
end



local function tableValue ( value , valueT )
if not c . ownershipKind ( valueT ) then
return valueT
end
if not node . affineAggregateContext then
c . diag (
"NUPP2603" ,
value ,
( c . ownershipKind ( valueT ) ) .. " value cannot be stored in a table"
)
return rawType ( valueT )
end
node . affineAggregate = true
if c . ownershipKind ( valueT ) == "affine" then
ownsElements = true
c . moveExpression ( value , valueT , "affine aggregate element" , "affine" )
if value . automaticOwnerMove then
aggregateMoves [ # aggregateMoves + 1 ] = value . automaticOwnerMove
end
else
local roots = c . own . capabilityFacts ( value , nil , false ) . roots or { }
for _ , root in ipairs ( roots ) do
if not rootSeen [ root ] then
rootSeen [ root ] = true
aggregateRoots [ # aggregateRoots + 1 ] = root
end
end
end
node . automaticOwnerMoves = aggregateMoves

return rawType ( valueT )
end

local function aggregateType ( valueT )
if ownsElements then
return T . affine ( valueT , { } , true )
elseif # aggregateRoots > 0 then
c . own . capabilityFacts ( node ) . roots = aggregateRoots
return T . borrowed ( valueT )
end

return valueT
end

for _ , f in ipairs ( node . fields ) do
if f . kind == "fieldItem" then
local value = f . value
if value then
local valueT = c . infer ( value )
positional [ # positional + 1 ] = widened ( tableValue ( value , valueT ) )
end
elseif f . kind == "fieldNamed" then
local value , fieldName = f . value , f . name
if value and fieldName then
local valueT = c . infer ( value )
valueT = tableValue ( value , valueT )




local keep = valueT . tag == "literal" and ( f . isConst or valueT . base == T . string )
local fieldT = keep and valueT or widened ( valueT )
local field = { name = fieldName . text , read = fieldT }
if not f . isConst then
field . write = fieldT
end
named [ # named + 1 ] = field
end
elseif f . kind == "fieldBracket" then
local value = f . value
if f . key then
c . infer ( f . key )
end
if value then
tableValue ( value , c . infer ( value ) )
end
return aggregateType ( T . table_ )
end
end
if # named > 0 and # positional == 0 then
return aggregateType ( T . shape ( named , nil , true ) )
elseif # positional > 0 and # named == 0 then
return aggregateType ( T . array ( T . union ( positional ) ) )
elseif # positional == 0 and # named == 0 then
return T . table_
end
return aggregateType ( T . table_ )
elseif kind == "errorExpr" then
return T . any
end

return T . any
end






c . infer = function ( node )
if not EXPANDS [ node . kind ] then
return inferExpr ( node )
end



node . valuePack = nil
node . fixedWidthEstablished = nil
node . fixedWidthTrusted = nil
node . fixedWidthResultEstablished = nil
node . fixedWidthResultTrusted = nil
node . fixedWidthUntrustedResult = nil
local first = inferExpr ( node )
if fixedWidth . isValue ( first ) and not node . fixedWidthUntrustedResult then
c . fixedWidth . mark ( node , first )
end
if not node . fixedWidthUntrustedResult then
c . fixedWidth . trust ( node , first )
end





node . valuePack = node . valuePack or T . pack ( { first } )
for index , result in ipairs ( node . valuePack . head or { } ) do
if fixedWidth . isValue ( result ) and not node . fixedWidthUntrustedResult then
node . fixedWidthResultEstablished = node . fixedWidthResultEstablished or { }
node . fixedWidthResultEstablished [ index ] = { [ T . unwrapOwnership ( result ) . tag ] = true }
end
if fixedWidth . requiresTrust ( result ) and not node . fixedWidthUntrustedResult then
node . fixedWidthResultTrusted = node . fixedWidthResultTrusted or { }
node . fixedWidthResultTrusted [ index ] = true
end
end

return first
end

c . apply . inferExpected = function ( node , expected )
if not expected then
return c . infer ( node )
end
if node . kind == "shortfn" then
expectedShortfns [ node ] = expected
local inferred = c . infer ( node )
expectedShortfns [ node ] = nil
return inferred
elseif node . kind == "funcExpr" and node . body then
local inferred = c . apply . checkFuncbodyExpected ( node . body , expected )
if not node . body . returnPack then
node . fixedWidthCallableUntrusted = true
end
local captures = ( node . body ) . borrowCaptures or { }
if # captures > 0 then
local roots = { }
for _ , capture in ipairs ( captures ) do
roots [ # roots + 1 ] = capture . root
end
c . own . capabilityFacts ( node ) . roots = roots
if not c . ownershipKind ( inferred ) then
inferred = T . borrowed ( inferred )
end
end
return inferred
end

return c . infer ( node )
end
end

return expr
