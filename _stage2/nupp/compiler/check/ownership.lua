_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);










local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.relations" )
local cst = require ( "nupp.compiler.cst" )
local state = require ( "nupp.compiler.check.state" )

local ownership = { }

local isA = relations . isA
local rawType = T . unwrapOwnership






















































































function ownership . install ( c )
local own = { }
local pendingGenericCleanupBounds = { }
local emptyCapabilityFacts = setmetatable({ }, T.CapabilityFacts)

function own . capabilityFacts ( entry , result , create )
entry = own . ownershipState ( entry )
if not entry then
return emptyCapabilityFacts
end
if not entry . capabilityFacts and create ~= false then
entry . capabilityFacts = setmetatable({ }, T.CapabilityFacts)
end
if result then
local existing = entry . resultCapabilityFacts and entry . resultCapabilityFacts [ result ]
if existing then
return existing
elseif create == false then
return result == 1 and entry . capabilityFacts or emptyCapabilityFacts
end
entry . resultCapabilityFacts = entry . resultCapabilityFacts or { }
entry . resultCapabilityFacts [ result ] = ( result == 1 and entry . capabilityFacts ) or setmetatable({ }, T.CapabilityFacts)
return entry . resultCapabilityFacts [ result ]
end

return entry . capabilityFacts or emptyCapabilityFacts
end

function own . capabilityOf ( t , entry )
entry = own . ownershipState ( entry )
t = t or ( entry and entry . t ) or T . any

return T . capability ( t , entry and own . capabilityFacts ( entry , nil , false ) or nil )
end

function own . ownershipKind ( t )
return t and T . capabilityKind ( own . capabilityOf ( t ) ) or nil
end

function own . ownershipState ( entry )
return entry and ( entry . ownershipOrigin or entry ) or nil
end

function own . borrowRoot ( entry )
entry = own . ownershipState ( entry )
local seen = { }
local roots = entry and own . capabilityFacts ( entry , nil , false ) . roots or nil
while entry and roots and roots [ 1 ] and not seen [ entry ] do
seen [ entry ] = true
entry = own . ownershipState ( roots [ 1 ] )
roots = entry and own . capabilityFacts ( entry , nil , false ) . roots or nil
end

return entry
end




function own . pointerShaped ( t )
t = rawType ( t )
if t . tag == "ptr" or t . tag == "carray" or t == T . cstring or t == T . voidptr then
return true
end
if t . tag == "union" and t . hasNil then
for _ , member in ipairs ( t . members ) do
if member ~= T . nil_ and not own . pointerShaped ( member ) then
return false
end
end
return true
end

return false
end

function own . optionalOwned ( t )
local inner = rawType ( t )
return own . ownershipKind ( t ) == "affine" and inner . tag == "union" and inner . hasNil
end




function own . resourceBehind ( t )
local resource = rawType ( t )
if resource . tag == "union" then
for _ , member in ipairs ( resource . members ) do
if member ~= T . nil_ then
return member
end
end
end

return resource
end

local function addRegistration ( node , cleanup , after )
if not node or cleanup . kind ~= "function" then
return
end
local registrations = node . cleanupRegistrations or { }
node . cleanupRegistrations = registrations
for _ , current in ipairs ( registrations ) do
if current . cleanup . id == cleanup . id and current . after == after then
return
end
end
registrations [ # registrations + 1 ] = { cleanup = cleanup , after = after }
end











local cleanupOrdinals = { }
local cleanupKeys = { }

local function stableOrigin ( origin )
while origin : sub ( 1 , 2 ) == "./" or origin : sub ( 1 , 2 ) == ".\\" do
origin = origin : sub ( 3 )
end
return origin
end

local function cleanupKey ( origin , name , definition )
local base = ( "%s#%s" ) : format ( origin , name )
if not definition then
return base
end
local known = cleanupKeys [ definition ]
if known then
return known
end
local seen = cleanupOrdinals [ base ] or 0
cleanupOrdinals [ base ] = seen + 1
local key = seen == 0 and base or ( "%s#%d" ) : format ( base , seen )
cleanupKeys [ definition ] = key

return key
end










function own . cleanupKeyFor ( name )
local entry = c . lookupEntry ( name ) or c . qualifiedFunctionEntries [ name ]
local definition = entry and entry . definition or nil
if not definition then
return nil , nil
end
local definitionModule = definition . filename and c . env and c . env . moduleNameForPath and c . env . moduleNameForPath (
c . env ,
definition . filename
)
local origin = stableOrigin (
definitionModule or definition and definition . filename or c . result . moduleName or c . filename or "<module>"
)
local key = cleanupKey ( origin , name , definition )
local bound = entry and entry . t or nil
if bound and bound . tag == "func" then
addRegistration ( definition . token , T . functionCleanup ( key , name , bound ) , false )
end

return key , entry
end

local function resolvedFunctionCleanup ( name , at , registrationNode , after , knownType )
local entry = c . lookupEntry ( name )
local definition = entry and entry . definition or nil
local definitionModule = definition
and definition . filename
and c . env
and c . env . moduleNameForPath
and c . env . moduleNameForPath (
c . env ,
definition . filename
)
local origin = stableOrigin (
definitionModule or definition and definition . filename or c . result . moduleName or c . filename or "<module>"
)
local key = cleanupKey ( origin , name , definition )
local cleanup = T . functionCleanup ( key , name , knownType or entry and entry . t or nil )
addRegistration ( registrationNode , cleanup , after == true )

return cleanup
end

function own . resolveCleanups ( cleanups , at , registrationNode )
local resolved = { }
registrationNode = registrationNode or at and at . cleanupRegistrationNode or nil
for j , cleanup in ipairs ( cleanups or { } ) do
if type ( cleanup ) == "table" and cleanup . kind then
if cleanup . kind == "function" and not cleanup . functionType then
resolved [ j ] = resolvedFunctionCleanup ( cleanup . name , at , registrationNode , false )
else
resolved [ j ] = cleanup
addRegistration ( registrationNode , cleanup , false )
end
else
resolved [ j ] = resolvedFunctionCleanup ( cleanup , at , registrationNode , false )
end
end

return resolved
end

function own . validateCleanups ( valueT , cleanups , at , code )
code = code or "NUPP2602"
local cleanupValue = rawType ( valueT )


if cleanupValue . tag == "union" and cleanupValue . hasNil then
local present = { }
for _ , member in ipairs ( cleanupValue . members ) do
if member ~= T . nil_ then
present [ # present + 1 ] = member
end
end
cleanupValue = T . union ( present )
end
local signature = { cleanupValue . id }
for _ , cleanup in ipairs ( cleanups or { } ) do
local cleanupT = cleanup . kind == "function" and ( cleanup . functionType or c . lookupVar ( cleanup . name ) ) or nil
signature [ # signature + 1 ] = cleanup . id .. ":" .. ( cleanupT and cleanupT . id or "?" )
end
local contractKey = table . concat ( signature , "|" )
if c . validatedCleanupContracts [ contractKey ] then
return
end
c . validatedCleanupContracts [ contractKey ] = true
for j , cleanup in ipairs ( cleanups or { } ) do
if cleanup . kind ~= "function" then
goto continue
end
local cleanupT = cleanup . functionType or c . lookupVar ( cleanup . name )
local cleanupFunc = cleanupT and cleanupT . tag == "func" and cleanupT or nil
local cleanupEntry = c . lookupEntry ( cleanup . name ) or c . qualifiedFunctionEntries [ cleanup . name ]
local cVoidTerminal = cleanupFunc
and # cleanupFunc . rets == 0
and cleanupFunc . retPack . tail == nil
and cleanupEntry
and cleanupEntry . definition
and cleanupEntry . definition . cdef
if cleanup . kind == "function" and c . nosuspend and c . nosuspend . cleanup then
local localDefinition = cleanupEntry
and cleanupEntry . definition
and cleanupEntry . definition . filename == c . filename
and cleanupEntry . definition
or nil
cleanup . token = localDefinition and localDefinition . token or nil
cleanup . visibleBody = localDefinition and (
not c . declarationFile or c . result . moduleName == "nupp.prelude"
) or nil
c . nosuspend . cleanup ( cleanup , at )
end
local firstParam = cleanupFunc and cleanupFunc . params [ 1 ] or nil
local genericBound = nil
if firstParam and firstParam . tag == "typevar" and cleanupFunc then
for parameter , typeParameter in ipairs ( cleanupFunc . typeParams or { } ) do
if typeParameter == firstParam then
genericBound = cleanupFunc . typeBounds and cleanupFunc . typeBounds [ parameter ] or nil
end
end
end
if not cleanupT and cleanup . key then






goto continue
elseif not cleanupT then
c . diag ( code , at , ( "cleanup %q is not declared" ) : format ( cleanup . name ) , nil , {
notes = {
"a cleanup is resolved here, where the owner "
.. "is declared, so it has to name a function this file "
.. "can see"
}
} )
elseif genericBound and not isA ( cleanupValue , genericBound ) then
pendingGenericCleanupBounds [
# pendingGenericCleanupBounds + 1
] = { cleanup = cleanup , value = cleanupValue , bound = genericBound , at = at , code = code , }
elseif cleanupT and cleanupT ~= T . any and not cleanupFunc then
c . diag ( code , at , ( "terminal %q must be a function" ) : format ( cleanup . name ) )
elseif cleanupFunc and (
# cleanupFunc . params ~= 1 or cleanupFunc . paramPack . tail ~= nil or cleanupFunc . paramModes [ 1 ] ~= "takes"
) then
c . diag ( code , at , ( "terminal %q must take exactly one consuming argument" ) : format ( cleanup . name ) )
elseif cleanupFunc and not genericBound and ( not firstParam or firstParam . id ~= cleanupValue . id ) then
c . diag ( code , at , ( "terminal %q must take exactly %s" ) : format ( cleanup . name , T . tostring ( cleanupValue ) ) )
elseif cleanupFunc and (
not cVoidTerminal and (
# cleanupFunc . rets ~= 1 or cleanupFunc . retPack . tail ~= nil or cleanupFunc . rets [ 1 ] ~= T . nil_
)
) then
c . diag ( code , at , ( "terminal %q must return nil" ) : format ( cleanup . name ) )
elseif cleanupFunc and not cleanupFunc . noYield and cleanup . visibleBody ~= true then
c . diag ( code , at , ( "terminal %q must be nosuspend" ) : format ( cleanup . name ) )
elseif cleanupFunc and j < # ( cleanups or { } ) and cleanupFunc . paramModes [ 1 ] == "takes" then
c . diag ( "NUPP2615" , at , ( "cleanup %q takes before the final step" ) : format ( cleanup . name ) )
end
if cleanupT then
cleanup . validated = true
end
:: continue ::
end
end

function own . finalizeCleanupBounds ( )
for _ , pending in ipairs ( pendingGenericCleanupBounds ) do
if not isA ( pending . value , pending . bound ) then
c . diag (
pending . code ,
pending . at ,
(
"cleanup %q requires %s to satisfy %s"
) : format ( pending . cleanup . name , T . tostring ( pending . value ) , T . tostring ( pending . bound ) )
)
end
end
end




function own . ownershipEntry ( expr )
while expr and ( expr . kind == "paren" or expr . kind == "castExpr" ) do
expr = expr . expr
end
if expr and expr . kind == "name" then
return own . ownershipState ( c . lookupEntry ( expr . token . text ) ) , expr
end

return nil , expr
end

function own . regionsOverlap ( left , right )
return T . regionsOverlap ( left , right )
end

function own . regionContains ( parent , child )
return T . regionContains ( parent , child )
end

function own . conflictDetails ( root , path , exclusiveOnly )
for borrowed , site in pairs ( root and root . activeBorrowSites or { } ) do
local borrowedFacts = own . capabilityFacts ( borrowed , nil , false )
if not borrowed . moved and (
not exclusiveOnly or borrowedFacts . exclusive
) and ( not path or own . regionsOverlap ( path , borrowedFacts . regionPath or "" ) ) then
local related = c . related ( site , "overlapping borrow is declared here" )
return {
help = "end the overlapping borrow before requesting this access" ,
related = related and { related } or nil ,
}
end
end

return { help = "end the overlapping borrow before requesting this access" }
end

function own . regionOf ( expr )
while expr and ( expr . kind == "paren" or expr . kind == "castExpr" ) do
expr = expr . expr
end
if not expr then
return nil , nil
end
local exprFacts = own . capabilityFacts ( expr , nil , false )
if exprFacts . regionRoot then
return exprFacts . regionRoot , exprFacts . regionPath or ""
end
if expr . kind == "name" then
local entry = own . ownershipState ( c . lookupEntry ( expr . token . text ) )
if entry then
local facts = own . capabilityFacts ( entry , nil , false )
if facts . exclusive then
own . capabilityFacts ( expr ) . exclusive = true
end
return facts . regionRoot or own . borrowRoot (
facts . roots and facts . roots [ 1 ] or entry
) , facts . regionPath or ""
end
elseif expr . kind == "dotIndex" or expr . kind == "safeIndex" then
local root , path = own . regionOf ( expr . obj )
local objectRef = c . refType ( expr . obj )
local objectType = objectRef and rawType ( objectRef ) or nil
if root and objectType and objectType . tag == "ptr" then
path = T . regionDeref ( path )
end
local fields = expr . obj . partitionFields
if not fields and expr . obj . kind == "name" then
local entry = own . ownershipState ( c . lookupEntry ( expr . obj . token . text ) )
fields = entry and entry . partitionFields or nil
end
local suffix = fields and fields [ expr . name . text ] or nil
if root and suffix then
own . capabilityFacts ( expr ) . exclusive = true
local side = suffix == "L" and "left" or suffix == "R" and "right" or suffix
return root , T . regionPartition ( path , side )
elseif root then
return root , T . regionField ( path , expr . name . text )
end
return root , path
elseif expr . kind == "bracketIndex" or expr . kind == "safeBracket" then
local root , path = own . regionOf ( expr . obj )
if root then
local key = expr . expr and c . infer ( expr . expr ) or nil
local exact = key and key . tag == "literal" and type (
key . constant
) == "number" and key . constant % 1 == 0 and key . constant or nil
local referenced = c . refType ( expr . obj )
local objectType = referenced and rawType ( referenced ) or nil
if objectType and objectType . tag == "tuple" and exact and exact >= 1 and exact <= # objectType . elems then
return root , T . regionTupleSlot ( path , exact )
end
if objectType and objectType . tag == "ptr" then
path = T . regionDeref ( path )
end
return root , T . regionIndex ( path , exact )
end
return root , path
end

local owner = own . provenanceOwner ( expr )

return owner , owner and "" or nil
end

function own . provenanceOwner ( expr )



while expr and ( expr . kind == "paren" or expr . kind == "castExpr" or expr . kind == "newExpr" ) do
expr = expr . kind == "newExpr" and expr . call or expr . expr
end
if not expr then
return nil
end
local exprRoots = own . capabilityFacts ( expr , nil , false ) . roots
if exprRoots and exprRoots [ 1 ] then
return own . borrowRoot ( exprRoots [ 1 ] )
end
if expr . kind == "name" then
local entry = own . ownershipState ( c . lookupEntry ( expr . token . text ) )
local roots = entry and own . capabilityFacts ( entry , nil , false ) . roots or nil
return own . borrowRoot ( entry and ( roots and roots [ 1 ] or entry ) )
elseif expr . kind == "dotIndex"
or expr . kind == "safeIndex"
or expr . kind == "bracketIndex"
or expr . kind == "safeBracket"
then
return own . provenanceOwner ( expr . obj )
elseif expr . kind == "tableExpr" then
for _ , field in ipairs ( expr . fields or { } ) do
local owner = own . provenanceOwner ( field . value )
if owner then
return owner
end
end
elseif expr . kind == "binop" then
local owner = own . provenanceOwner ( expr . lhs )
if owner then
return owner
end
return own . provenanceOwner ( expr . rhs )
elseif expr . kind == "call" and expr . recordConstruct then
for _ , binding in ipairs ( expr . recordFields or { } ) do
local owner = own . provenanceOwner ( binding . node )
if owner then
return owner
end
end
end

return nil
end

function own . provenanceOwners ( expr , out , seen )
out , seen = out or { } , seen or { }
if not expr or cst . isToken ( expr ) then
return out
end
if expr . kind == "newExpr" then
return own . provenanceOwners ( expr . call , out , seen )
end
local exprRoots = own . capabilityFacts ( expr , nil , false ) . roots
if exprRoots then
for _ , owner in ipairs ( exprRoots ) do
owner = own . borrowRoot ( owner )
if owner and not seen [ owner ] then
seen [ owner ] , out [ # out + 1 ] = true , owner
end
end
return out
end
local one = own . provenanceOwner ( expr )
if one and not seen [ one ] then
seen [ one ] , out [ # out + 1 ] = true , one
end
if expr . kind == "tableExpr" then
for _ , field in ipairs ( expr . fields or { } ) do
own . provenanceOwners ( field . value , out , seen )
end
elseif expr . kind == "call" and expr . recordConstruct then



for _ , binding in ipairs ( expr . recordFields or { } ) do
own . provenanceOwners ( binding . node , out , seen )
end
elseif expr . kind == "binop" then
own . provenanceOwners ( expr . lhs , out , seen )
own . provenanceOwners ( expr . rhs , out , seen )
end

return out
end

function own . liveSuspensionObligation ( )
local current , seen = c . scope , { }
while current do
for name , entry in pairs ( current . vars or { } ) do
local state = own . ownershipState ( entry )
if state and not seen [ state ] and ( state . functionDepth or 0 ) == c . functionDepth and not state . moved then
seen [ state ] = true
local capability = own . capabilityOf ( state . t , state )
if T . capabilityHasMovable (
capability
) or # capability . loans > 0 or ( state . activeBorrows or 0 ) > 0 then
return name
end
end
end
current = current . parent
end

return nil
end





function own . releaseBorrowLinks ( entry )
entry = own . ownershipState ( entry )



if entry . ownershipOrigin then
return
end
if not entry . capabilityFacts then
return
end
local facts = own . capabilityFacts ( entry , nil , false )
if facts . regionRoot and facts . regionPath then
local active = facts . regionRoot . activeRegions
if active and active [ facts . regionPath ] then
active [ facts . regionPath ] = math . max ( 0 , active [ facts . regionPath ] - 1 )
if active [ facts . regionPath ] == 0 then
active [ facts . regionPath ] = nil
end
end
if facts . exclusive then
local exclusive = facts . regionRoot . activeExclusiveRegions
if exclusive and exclusive [ facts . regionPath ] then
exclusive [ facts . regionPath ] = math . max ( 0 , exclusive [ facts . regionPath ] - 1 )
if exclusive [ facts . regionPath ] == 0 then
exclusive [ facts . regionPath ] = nil
end
end
end
end
for _ , owner in ipairs ( facts . roots or { } ) do
if owner . activeBorrowSites then
owner . activeBorrowSites [ entry ] = nil
end
owner . activeBorrows = math . max ( 0 , ( owner . activeBorrows or 1 ) - 1 )
if facts . exclusive then
owner . activeExclusiveBorrows = math . max ( 0 , ( owner . activeExclusiveBorrows or 1 ) - 1 )
end
end
facts . roots = nil
facts . exclusive = nil
facts . regionRoot = nil
facts . regionPath = nil
end

function own . moveExpression ( expr , t , reason , expectedKind , allowPartial )
expectedKind = expectedKind or "affine"
local dropOperation = c . consumingFieldStack [ # c . consumingFieldStack ]
if dropOperation
and expectedKind == "affine"
and expr
and expr . kind == "dotIndex"
and expr . obj
and expr . obj . kind == "name"
and expr . obj . token . text == dropOperation . root
then
local field = expr . name . text
if dropOperation . allowed [ field ] then
if dropOperation . done [ field ] then
c . diag ( "NUPP2602" , expr , ( "owned field %q is dropped more than once" ) : format ( field ) )
return false
end
dropOperation . done [ field ] = true
return true
end
end
local entry , nameNode = own . ownershipEntry ( expr )
entry = own . ownershipState ( entry )
if own . ownershipKind ( t ) ~= expectedKind then
c . diag ( "NUPP2602" , expr , ( reason or "ownership transfer" ) .. " requires a " .. expectedKind .. " value" )
return false
end
if expr and expr . kind == "dotIndex" and expectedKind == "affine" then
local container = expr . obj and own . ownershipState ( ( own . ownershipEntry ( expr . obj ) ) ) or nil
local field = expr . name and expr . name . text
local aggregate = container and rawType ( container . t ) or nil
local declared = aggregate and aggregate . tag == "nominal" and aggregate . byname [ field ] or nil
if not container or own . ownershipKind (
container . t
) ~= "affine" or own . ownershipKind ( declared ) ~= "affine" then
c . diag ( "NUPP2602" , expr , "only a declared affine field of a named owning record can move" )
return false
end
container . movedFields = container . movedFields or { }
if container . movedFields [ field ] then
c . diag ( "NUPP2601" , expr , ( "owned field %q was already moved" ) : format ( field ) )
return false
end
if aggregate
and aggregate . tag == "nominal"
and aggregate . borrowedRootFields
and aggregate . borrowedRootFields [
field
] then
c . diag ( "NUPP2602" , expr , ( "owned field %q cannot move while a sibling field borrows it" ) : format ( field ) )
return false
end
if ( container . activeBorrows or 0 ) > 0 then
c . diag ( "NUPP2602" , expr , ( "owned field %q cannot move while the record is borrowed" ) : format ( field ) )
return false
end
container . movedFields [ field ] = true
container . movedFieldTypes = container . movedFieldTypes or { }
container . movedFieldTypes [ field ] = t
if container . automaticOwner then
expr . automaticOwnerMove = { owner = container . automaticOwner , field = field }
container . automaticOwner . movedFields = container . automaticOwner . movedFields or { }
container . automaticOwner . movedFields [ field ] = true
end
return true
elseif expr and expr . kind == "bracketIndex" and expectedKind == "affine" then
c . diag ( "NUPP2602" , expr , "computed partial moves cannot prove which affine field moved" )
return false
end
if entry and entry . movedFields and next ( entry . movedFields ) and not allowPartial then
c . diag ( "NUPP2602" , nameNode or expr , "a partially moved record cannot be moved or consumed as a whole" )
return false
end
if entry then
if own . ownershipKind ( entry . t ) ~= expectedKind then
c . diag ( "NUPP2602" , expr , ( reason or "ownership transfer" ) .. " requires a " .. expectedKind .. " value" )
return false
end
if entry . moved then
if not nameNode . ownershipUseReported then
local related = entry . movedAt and c . related ( entry . movedAt , "owner was moved here" ) or nil
c . diag ( "NUPP2601" , nameNode , ( "owner %q was already moved" ) : format ( nameNode . token . text ) , nil , {
related = related and { related } or nil ,
help = "use the owner before this transfer, or borrow it " .. "instead of moving it"
} )
end
return false
end
if ( entry . activeBorrows or 0 ) > 0 then
c . diag ( "NUPP2602" , nameNode , ( "owner %q cannot move while it is borrowed" ) : format ( nameNode . token . text ) )
return false
end
if expectedKind == "pinned" and own . capabilityFacts ( entry , nil , false ) . retention then
c . diag (
"NUPP2602" ,
nameNode ,
( "pinned handle %q cannot move while C retains it" ) : format ( nameNode . token . text )
)
return false
end
if entry . automaticOwner then
nameNode . automaticOwnerMove = entry . automaticOwner
entry . automaticOwner . moved = true
end
entry . moved = true
entry . movedAt = nameNode or expr


own . releaseBorrowLinks ( entry )
end



return true
end



c . ownershipKind = own . ownershipKind
c . capabilityOf = own . capabilityOf
c . ownershipState = own . ownershipState
c . pointerShaped = own . pointerShaped
c . moveExpression = own . moveExpression
c . borrowRoot = own . borrowRoot
c . ownershipEntry = own . ownershipEntry
c . liveSuspensionObligation = own . liveSuspensionObligation
c . releaseBorrowLinks = own . releaseBorrowLinks
c . regionOf = own . regionOf
c . regionsOverlap = own . regionsOverlap
c . regionContains = own . regionContains
c . validateCleanups = own . validateCleanups

return own
end

return ownership
