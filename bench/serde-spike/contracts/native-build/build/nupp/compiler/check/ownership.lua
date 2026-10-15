_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()












local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.types.relations" )
local cst = require ( "nupp.compiler.syntax.cst" )
local state = require ( "nupp.compiler.check.state" )

local ownership = { }

local isA = relations . isA
local rawType = T . unwrapOwnership


















































































































function ownership . install ( c ) 
local own = { }
local pendingGenericCleanupBounds





= { }
local emptyCapabilityFacts = _G.setmetatable({ }, T.CapabilityFacts)





function own . capabilityFacts ( entry , result , create ) 
entry = own . ownershipState ( entry )
if not entry then
return emptyCapabilityFacts
end
if not entry . capabilityFacts and create ~= false then
entry . capabilityFacts = _G.setmetatable({ }, T.CapabilityFacts)
end
if result then
local existing = entry . resultCapabilityFacts and entry . resultCapabilityFacts [ result ]
if existing then
return existing
elseif create == false then
return result == 1 and entry . capabilityFacts or emptyCapabilityFacts
end
entry . resultCapabilityFacts = entry . resultCapabilityFacts or { }
entry . resultCapabilityFacts [ result ] = ( result == 1 and entry . capabilityFacts ) or _G.setmetatable({ }, T.CapabilityFacts)
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
while entry and not entry . withBinding and roots and roots [ 1 ] and not seen [ entry ] do
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
local base = ("%s#%s") : format ( origin , name )
if not definition then
return base
end





local identity = definition . token or definition
local known = cleanupKeys [ identity ]
if known then
return known
end
local seen = cleanupOrdinals [ base ] or 0
cleanupOrdinals [ base ] = seen + 1
local key = seen == 0 and base or ("%s#%d") : format ( base , seen )
cleanupKeys [ identity ] = key

return key
end





local function declaredFunctionEntry ( name ) 
local direct = c . lookupEntry ( name ) or c . qualifiedFunctionEntries [ name ]
if not direct
and not name : find ( "%." )
and c . moduleExports
and c . moduleExports . values
and c . moduleExports . values [ name ]
then
direct = {
t = c . moduleExports . values [ name ] ,
definition = c . moduleExports . valueDefs and c . moduleExports . valueDefs [ name ] or nil ,
}
end
if direct then





local ownName , ownMember = name : match ( "^(.*)%.([^.]*)$" )
if ownName ~= nil and ownName == c . moduleLocal and direct . canonicalName == nil then
return { t = direct . t , definition = direct . definition , canonicalName = ownMember }
end
return direct
end
local ownerName , member = name : match ( "^(.*)%.([^.]*)$" )
local owner = ownerName and c . lookupType ( ownerName ) or nil
if not owner or owner . tag ~= "nominal" then
local moduleName , exportName = name : match ( "^(.*)%.([^.]+)$" )





if moduleName then
local first = moduleName : match ( "^[^.]+" )
local holder = first and c . lookupEntry ( first ) or nil
if holder and holder . requiredModule then
local firstName = first
moduleName = holder . requiredModule .. moduleName : sub ( # firstName + 1 )
end
end
local exports = moduleName
and c . env
and c . env . resolveModuleExports
and c . env . resolveModuleExports ( c . env , moduleName )
or nil
local exported = exports and exports . values and exports . values [ exportName ] or nil
local exportedDefinition = exports and exports . valueDefs and exports . valueDefs [ exportName ] or nil
if exported and exportedDefinition then




return { t = exported , definition = exportedDefinition , canonicalName = exportName }
end
return nil
end
local functionType = owner . byname and owner . byname [ member ] or owner . staticByname and owner . staticByname [ member ]
local definition = owner . fieldDefs and owner . fieldDefs [ member ]
or owner . staticFieldDefs and owner . staticFieldDefs [ member ]
if not functionType or not definition then
return nil
end

return { t = functionType , definition = definition }
end










function own . cleanupKeyFor ( name ) 
local entry = declaredFunctionEntry ( name )
local definition = entry and entry . definition or nil
if not definition then
return nil , nil
end
local definitionModule = definition . filename
and c . env
and c . env . moduleNameForPath
and c . env . moduleNameForPath ( c . env , definition . filename )
local origin = stableOrigin (
definitionModule or definition and definition . filename or c . result . moduleName or c . filename or "<module>"
)
local key = cleanupKey ( origin , entry . canonicalName or name , definition )
local bound = entry and entry . t or nil
if bound and bound . tag == "func" then
addRegistration ( definition . token , T . functionCleanup ( key , name , bound ) , false )
end

return key , entry
end





local function sameDeclaredValue ( a , b ) 
if a . id == b . id then
return true
end
if a . tag ~= "nominal" or b . tag ~= "nominal" then
return false
end
local declaration = ( a . origin or a )
if declaration ~= ( ( b . origin or b ) ) then
return false
end



local applied = a . typeArgs and a or b . typeArgs and b or nil
if not applied or not declaration . typeParams then
return false
end
if # ( applied . typeArgs or { } ) ~= # declaration . typeParams then
return false
end
for j , binder in ipairs ( declaration . typeParams ) do
if applied . typeArgs [ j ] ~= binder then
return false
end
end

return true
end

local function resolvedFunctionCleanup ( name , at , registrationNode , after , knownType ) 
local entry = declaredFunctionEntry ( name )
local definition = entry and entry . definition or nil
local definitionModule = definition
and definition . filename
and c . env
and c . env . moduleNameForPath
and c . env . moduleNameForPath ( c . env , definition . filename )
local origin = stableOrigin (
definitionModule or definition and definition . filename or c . result . moduleName or c . filename or "<module>"
)
local key = cleanupKey ( origin , entry and entry . canonicalName or name , definition )
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
if cleanup . kind == "function" then
local function validateFunctionCleanup ( ) 
local cleanupT = cleanup . functionType or c . lookupVar ( cleanup . name )
local cleanupFunc = cleanupT and cleanupT . tag == "func" and cleanupT or nil
local cleanupEntry = declaredFunctionEntry ( cleanup . name )
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
cleanup . visibleBody = localDefinition
and ( not c . declarationFile or c . result . moduleName == "nupp.prelude" )
or nil
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







return
elseif not cleanupT then
c . diag ( code , at , ("cleanup %q is not declared") : format ( cleanup . name ) , nil , {
notes = {
"a cleanup is resolved here, where the owner is declared, so it has to name a function this file can see"


}
} )
elseif genericBound and not isA ( cleanupValue , genericBound ) then
pendingGenericCleanupBounds [
# pendingGenericCleanupBounds + 1
] = { cleanup = cleanup , value = cleanupValue , bound = genericBound , at = at , code = code , }
elseif cleanupT and cleanupT ~= T . any and not cleanupFunc then
c . diag ( code , at , ("terminal %q must be a function") : format ( cleanup . name ) )
elseif cleanupFunc
and (
# cleanupFunc . params ~= 1
or cleanupFunc . paramPack . tail ~= nil
or cleanupFunc . paramModes [ 1 ] ~= "takes"
)
then
c . diag ( code , at , ("terminal %q must take exactly one consuming argument") : format ( cleanup . name ) )
elseif cleanupFunc
and not genericBound
and ( not firstParam or not sameDeclaredValue ( firstParam , cleanupValue ) )
then
c . diag (
code ,
at ,
("terminal %q must take exactly %s") : format ( cleanup . name , T . tostring ( cleanupValue ) )
)
elseif cleanupFunc
and (
not cVoidTerminal
and (
# cleanupFunc . rets ~= 1
or cleanupFunc . retPack . tail ~= nil
or cleanupFunc . rets [ 1 ] ~= T . nil_
)
)
then
c . diag ( code , at , ("terminal %q must return nil") : format ( cleanup . name ) )
elseif cleanupFunc and j < # ( cleanups or { } ) and cleanupFunc . paramModes [ 1 ] == "takes" then
c . diag ( "NUPP2615" , at , ("cleanup %q takes before the final step") : format ( cleanup . name ) )
end
if cleanupT then
cleanup . validated = true
end
end

validateFunctionCleanup ( )
end
end
end

function own . finalizeCleanupBounds ( ) 
for _ , pending in ipairs ( pendingGenericCleanupBounds ) do
if not isA ( pending . value , pending . bound ) then
c . diag (
pending . code ,
pending . at ,
("cleanup %q requires %s to satisfy %s")

: format ( pending . cleanup . name , T . tostring ( pending . value ) , T . tostring ( pending . bound ) )
)
end
end
end





function own . ownershipEntry ( expr ) 
while expr and ( expr . kind == "paren" or expr . kind == "castExpr" or expr . kind == "orExitExpr" ) do
expr = expr . kind == "orExitExpr" and expr . operand or expr . expr
end
if expr and expr . kind == "name" then
return own . ownershipState ( c . lookupEntry ( expr . token . text ) ) , expr
end

return nil , expr
end

function own . pathBase ( expr ) 
while expr do
if expr . kind == "paren" or expr . kind == "castExpr" then
expr = expr . expr
elseif expr . kind == "orExitExpr" then
expr = expr . operand
elseif expr . kind == "dotIndex"
or expr . kind == "safeIndex"
or expr . kind == "bracketIndex"
or expr . kind == "safeBracket"
then
expr = expr . obj
else
do break end
end
end
if expr and expr . kind == "name" then
return own . ownershipState ( c . lookupEntry ( expr . token . text ) )
end

return nil
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
if not borrowed . moved
and ( not exclusiveOnly or borrowedFacts . exclusive )
and ( not path or own . regionsOverlap ( path , borrowedFacts . regionPath or "" ) )
then
local related = c . related ( site , "overlapping borrow is declared here" )
return {
help = "end the overlapping borrow before requesting this access" ,
related = related and { related } or nil ,
}
end
end

return { help = "end the overlapping borrow before requesting this access" }
end






function own . regionBlocked ( root , entry , entryFacts , regionRoot , regionPath , exclusive ) 
if regionRoot and regionPath and regionPath ~= "" then
local held = { }

local function hold ( candidate ) 
candidate = own . ownershipState ( candidate )
if not candidate or held [ candidate ] then
return
end
held [ candidate ] = true
for _ , derived in ipairs ( own . capabilityFacts ( candidate , nil , false ) . roots or { } ) do
hold ( derived )
end
end

hold ( entry )



local ownCount = 0
for borrowed in pairs ( held ) do
local facts = own . capabilityFacts ( borrowed , nil , false )
if not borrowed . moved
and facts . regionRoot == regionRoot
and facts . regionPath == regionPath
and ( not exclusive or facts . exclusive )
then
ownCount = ownCount + 1
end
end


local active = regionRoot . activeRegions
if exclusive then
active = regionRoot . activeExclusiveRegions
end
for activePath , count in pairs ( active or { } ) do
if ( activePath == regionPath and count > ownCount )
or (
activePath ~= regionPath
and own . regionsOverlap ( activePath , regionPath )
and not own . regionContains ( activePath , regionPath )
)
then
return true
end
end




for borrowed in pairs ( regionRoot . activeBorrowSites or { } ) do
local borrowedFacts = own . capabilityFacts ( borrowed , nil , false )
if not held [ borrowed ]
and not borrowed . moved
and ( not exclusive or borrowedFacts . exclusive )
and ( borrowedFacts . regionPath == nil or borrowedFacts . regionPath == "" )
then
return true
end
end
return false
end
if exclusive then
return ( root . activeExclusiveBorrows or 0 ) > 0
end

return ( root . activeBorrows or 0 ) > 0
end

function own . checkExclusiveReceiver ( receiver , at ) 
local entry , nameNode = own . ownershipEntry ( receiver )
entry = own . ownershipState ( entry )
local entryFacts = entry and own . capabilityFacts ( entry , nil , false ) or nil
local regionRoot , regionPath = own . regionOf ( receiver )
local roots = entry and { entry } or own . provenanceOwners ( receiver )
if # roots == 0 then
c . diag ( "NUPP2602" , at or receiver , "an indexed write requires a named or rooted exclusive view" )
return
end
local base = entry or own . pathBase ( receiver )
for _ , root in ipairs ( roots ) do
if own . regionBlocked ( root , base , entryFacts , regionRoot , regionPath , false ) then
c . diag (
"NUPP2607" ,
nameNode or at or receiver ,
"an indexed write cannot overlap a live derived view" ,
nil ,
own . conflictDetails ( regionRoot or root , regionPath )
)
return
end
end
end

function own . regionOf ( expr ) 
while expr and ( expr . kind == "paren" or expr . kind == "castExpr" or expr . kind == "orExitExpr" ) do
expr = expr . kind == "orExitExpr" and expr . operand or expr . expr
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
return facts . regionRoot
or own . borrowRoot ( facts . roots and facts . roots [ 1 ] or entry ) , facts . regionPath
or ""
end
elseif expr . kind == "dotIndex" or expr . kind == "safeIndex" then
if expr . indexedField and expr . obj and expr . obj . indexedAccess and expr . obj . obj then
local root , path = own . regionOf ( expr . obj . obj )
if root then
path = T . regionField ( path , expr . indexedField . name )
local key = expr . obj . expr and c . infer ( expr . obj . expr ) or nil
local exact = key
and key . tag == "literal"
and type ( key . constant ) == "number"
and key . constant % 1 == 0
and key . constant
or nil
return root , T . regionIndex ( path , exact )
end
end
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
local exact = key
and key . tag == "literal"
and type ( key . constant ) == "number"
and key . constant % 1 == 0
and key . constant
or nil
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










function own . carriesProvenance ( expr , t ) 
if t and own . ownershipKind ( t ) == "borrowed" then
return true
end
while expr and ( expr . kind == "paren" or expr . kind == "castExpr" or expr . kind == "orExitExpr" ) do
expr = expr . kind == "orExitExpr" and expr . operand or expr . expr
end
local roots = expr and own . capabilityFacts ( expr , nil , false ) . roots or nil

return roots ~= nil and roots [ 1 ] ~= nil
end

function own . rootsOf ( expr ) 
while expr
and (
expr . kind == "paren" or expr . kind == "castExpr" or expr . kind == "newExpr" or expr . kind == "orExitExpr"
) do
expr = expr . kind == "newExpr" and expr . call or expr . kind == "orExitExpr" and expr . operand or expr . expr
end
local out , seen = { } , { }
if not expr or cst . isToken ( expr ) then
return out
end




local function add ( roots ) 
for _ , root in ipairs ( roots or { } ) do
local owner = not own . ownershipState ( root ) . moved and own . borrowRoot ( root ) or nil
if owner and not seen [ owner ] then
seen [ owner ] , out [ # out + 1 ] = true , owner
end
end
end

local exprRoots = own . capabilityFacts ( expr , nil , false ) . roots
if exprRoots then
add ( exprRoots )
elseif expr . kind == "name" then
local entry = own . ownershipState ( c . lookupEntry ( expr . token . text ) )
add ( entry and own . capabilityFacts ( entry , nil , false ) . roots or nil )
elseif expr . kind == "dotIndex"
or expr . kind == "safeIndex"
or expr . kind == "bracketIndex"
or expr . kind == "safeBracket"
then
return own . rootsOf ( expr . obj )
end

return out
end

function own . provenanceOwner ( expr ) 



while expr
and (
expr . kind == "paren" or expr . kind == "castExpr" or expr . kind == "newExpr" or expr . kind == "orExitExpr"
) do
expr = expr . kind == "newExpr" and expr . call or expr . kind == "orExitExpr" and expr . operand or expr . expr
end
if not expr then
return nil
end
local exprRoots = own . capabilityFacts ( expr , nil , false ) . roots
if exprRoots and exprRoots [ 1 ] then
return own . borrowRoot ( exprRoots [ 1 ] )
end



local origin = own . capabilityFacts ( expr , nil , false ) . origin
if origin then
return own . borrowRoot ( origin )
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
if T . capabilityHasMovable ( capability )
or # capability . loans > 0
or ( state . activeBorrows or 0 ) > 0
then
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


if not facts . capturedBorrowRoots then
for _ , owner in ipairs ( facts . roots or { } ) do
if owner . activeBorrowSites then
owner . activeBorrowSites [ entry ] = nil
end
owner . activeBorrows = math . max ( 0 , ( owner . activeBorrows or 1 ) - 1 )
if facts . exclusive then
owner . activeExclusiveBorrows = math . max ( 0 , ( owner . activeExclusiveBorrows or 1 ) - 1 )
end
end
end
facts . roots = nil
facts . exclusive = nil
facts . regionRoot = nil
facts . regionPath = nil
end







local function temporaryNode ( node ) 
while node
and (
node . kind == "paren" or node . kind == "castExpr" or node . kind == "newExpr" or node . kind == "orExitExpr"
) do
node = node . kind == "newExpr" and node . call or node . kind == "orExitExpr" and node . operand or node . expr
end

return node
end

function own . temporaryProduced ( node ) 
local open = c . temporaryOwners [ # c . temporaryOwners ]
node = temporaryNode ( node )
if not open or not node or node . discardingResults then
return
end
for _ , seen in ipairs ( open ) do
if seen == node then
return
end
end


node . temporaryConsumed = nil
node . temporaryReported = nil
node . temporaryStatementCleanup = nil
node . statementOwner = nil
open [ # open + 1 ] = node
end

function own . expireTemporaryAfterStatement ( node ) 
node = temporaryNode ( node )
if node then
node . temporaryStatementCleanup = true
end
end

function own . markTemporaryConsumed ( node ) 
node = temporaryNode ( node )
if node then
node . temporaryConsumed = true
end
end

function own . moveExpression ( expr , t , reason , expectedKind , allowPartial ) 
expectedKind = expectedKind or "affine"

own . markTemporaryConsumed ( expr )
local dropOperation = c . consumingFieldStack [ # c . consumingFieldStack ]
if dropOperation
and expectedKind == "affine"
and expr
and expr . kind == "name"
and expr . token
and expr . token . text == dropOperation . root
then
dropOperation . wholeMoved = true
end
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



local rootState = own . ownershipState ( c . lookupEntry ( dropOperation . root ) )
if rootState and rootState . movedFields and rootState . movedFields [ field ] then
c . diag ( "NUPP2602" , expr , ("owned field %q is dropped more than once") : format ( field ) )
return false
end
dropOperation . done [ field ] = true
if rootState then
rootState . movedFields = rootState . movedFields or { }
rootState . movedFields [ field ] = true
end
return true
end
end
local entry , nameNode = own . ownershipEntry ( expr )
entry = own . ownershipState ( entry )
if own . ownershipKind ( t ) ~= expectedKind then
c . diag ( "NUPP2602" , expr , ( reason or "ownership transfer" ) .. " requires a " .. expectedKind .. " value" )
return false
end
if expr and expr . kind == "dotIndex" and expectedKind == "affine" and not expr . soaFieldProjection then
local container = expr . obj and own . ownershipState ( ( own . ownershipEntry ( expr . obj ) ) ) or nil
local field = expr . name and expr . name . text



local aggregate = container and rawType ( container . t ) or nil
if aggregate and aggregate . tag == "union" and aggregate . hasNil and # aggregate . members == 2 then
aggregate = rawType ( own . resourceBehind ( aggregate ) )
end
local declared = aggregate and aggregate . tag == "nominal" and aggregate . byname [ field ] or nil
if not container
or own . ownershipKind ( container . t ) ~= "affine"
or own . ownershipKind ( declared ) ~= "affine"
then
c . diag ( "NUPP2602" , expr , "only a declared affine field of a named owning record can move" )
return false
end
container . movedFields = container . movedFields or { }
if container . movedFields [ field ] then
c . diag ( "NUPP2601" , expr , ("owned field %q was already moved") : format ( field ) )
return false
end
if aggregate
and aggregate . tag == "nominal"
and aggregate . borrowedRootFields
and aggregate . borrowedRootFields [ field ]
then
c . diag ( "NUPP2602" , expr , ("owned field %q cannot move while a sibling field borrows it") : format ( field ) )
return false
end
if ( container . activeBorrows or 0 ) > 0 then
c . diag ( "NUPP2602" , expr , ("owned field %q cannot move while the record is borrowed") : format ( field ) )
return false
end




local wholeCleanup = false
for _ , cleanup in ipairs ( ( container . t ) . cleanups or { } ) do
wholeCleanup = wholeCleanup or ( cleanup . kind ~= "field" and cleanup . kind ~= "dropfield" )
end
if wholeCleanup then
local held = rawType ( declared )
if not ( held . tag == "union" and held . hasNil ) then
c . diag (
"NUPP2602" ,
expr ,
("owned field %q cannot move out of a record its own cleanup closes") : format ( field ) ,
nil ,
{
help = ("declare the field optional (`%s: %s?`) so moving it leaves nil, or consume the record whole")


: format ( field , T . tostring ( held ) ) ,
}
)
return false
end
expr . fieldTake = true
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
elseif expr and expr . kind == "bracketIndex" and expectedKind == "affine" and not expr . soaFieldProjection then
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
c . diag ( "NUPP2601" , nameNode , ("owner %q was already moved") : format ( nameNode . token . text ) , nil , {
related = related and { related } or nil ,
help = "use the owner before this transfer, or borrow it instead of moving it"
} )
end
return false
end
if ( entry . activeBorrows or 0 ) > 0 then
c . diag ( "NUPP2602" , nameNode , ("owner %q cannot move while it is borrowed") : format ( nameNode . token . text ) )
return false
end
if expectedKind == "pinned" and own . capabilityFacts ( entry , nil , false ) . retention then
c . diag (
"NUPP2602" ,
nameNode ,
("pinned handle %q cannot move while C retains it") : format ( nameNode . token . text )
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
c . markTemporaryConsumed = own . markTemporaryConsumed
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

local __nuppExportValue= ownership ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.ownership"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.ownership"]=__nuppExports;return __nuppExports