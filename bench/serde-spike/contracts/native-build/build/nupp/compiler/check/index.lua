_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()













local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.types.relations" )
local generics = require ( "nupp.compiler.types.generics" )
local cst = require ( "nupp.compiler.syntax.cst" )
local state = require ( "nupp.compiler.check.state" )
local scalarIntrinsics = require ( "nupp.compiler.scalarintrinsics" )
local fixedWidth = require ( "nupp.compiler.types.fixedwidth" )
local native = require ( "nupp.compiler.native" )
local indexedViews = require ( "nupp.compiler.types.indexedviews" )
local members = require ( "nupp.compiler.types.members" )
local runtimeSurface = require ( "nupp.compiler.runtimesurface" )
local standardSurface = require ( "nupp.compiler.standardsurface" )
local narrowing = require ( "nupp.compiler.types.narrowing" )

local isA = relations . isA
local rawType = T . unwrapOwnership
local subtract = narrowing . subtract




local index = { }








local INTRINSIC_NAMESPACE

= { [ "nupp.derive" ] = true , [ "nupp.types" ] = true , [ "nupp.reflect" ] = true , }





local COMPILER_MODULES = { [ "string.buffer" ] = "string.buffer" }





local function compilerOnlyValue ( t ) 
if t == T . type_ or t == T . typepack or t == T . functionConst or t . tag == "typeHandle" then
return true
end
if t . tag == "func" then
if t . comptimeOnly then
return true
end
for _ , parameter in ipairs ( t . params ) do
if compilerOnlyValue ( parameter ) then
return true
end
end
for _ , result in ipairs ( t . rets ) do
if compilerOnlyValue ( result ) then
return true
end
end
elseif t . tag == "intersection" or t . tag == "union" then
for _ , member in ipairs ( t . members ) do
if compilerOnlyValue ( member ) then
return true
end
end
end

return false
end





function index . install ( c ) 
local handlers = __nuppNew(0,3)





local function dottedPath ( node ) 
local parts = { }
local names = { }
local current = node
while current and current . kind == "dotIndex" do
if not current . name then
return nil , nil
end
table . insert ( parts , 1 , current . name . text )
table . insert ( names , 1 , current . name )
current = current . obj
end
if not current or current . kind ~= "name" or not current . token then
return nil , nil
end
table . insert ( parts , 1 , current . token . text )
table . insert ( names , 1 , current . token )

return table . concat ( parts , "." ) , current . token . text , names
end

local function qualifiedModule ( node ) 
if node . kind ~= "dotIndex" or node . writeContext or not c . env or not c . env . ensureProjectIndex then
return nil
end
local written , root , nameTokens = dottedPath ( node )
if not written or not root then
return nil
end
for intrinsic in pairs ( INTRINSIC_NAMESPACE ) do
if written == intrinsic or written : sub ( 1 , # intrinsic + 1 ) == intrinsic .. "." then
return nil
end
end
local lexical = c . lookupEntry ( root )
local builtin = c . env . globals and c . env . globals [ root ]
if lexical and ( not builtin or lexical . definition ~= builtin . definition ) then
return nil
end
local registry = c . env . ensureProjectIndex ( c . env )
local candidate = written
local suffix = { }
while candidate do




local declared = registry . declaredModules and registry . declaredModules [ candidate ] or false
if not declared and c . env . bundled then
local shipped = c . env . bundled [ candidate ]
declared = shipped ~= nil and shipped ~= false and shipped . declared == true
end
if declared then
local access = c . env . moduleAccess and c . env . moduleAccess ( c . env , c . result . moduleName , candidate )
if access and not c . opts . generatedSource then
c . diag ( "NUPP2144" , node . name or node , access )
return T . any
end
local moduleType = c . env . resolveModule and c . env . resolveModule ( c . env , candidate ) or nil
if not moduleType then
return nil
end
local resolved = moduleType
local definition = nil
for memberIndex , memberName in ipairs ( suffix ) do
resolved , definition = c . fieldType ( resolved , memberName )
if not resolved and memberIndex == 1 and c . env . exportedNominal then
local nominal , declared = c . env . exportedNominal ( c . env , candidate , memberName )
if nominal and nominal . tag == "nominal" then
resolved = nominal . declKind == "struct" and nominal or T . typeObject ( nominal )
definition = declared
end
end
if not resolved then
c . diag (
"NUPP2004" ,
node . name or node ,
("module %q has no exported member %q") : format ( candidate , memberName )
)
return T . any
end
end




local moduleEffect = suffix [ 1 ]
and (
standardSurface . requireMember ( c , candidate , suffix [ 1 ] , node . name or node )
or native . forModuleMember ( candidate , suffix [ 1 ] )
)
or standardSurface . requireModule ( c , candidate , node . name or node )
or native . forModule ( candidate )
if moduleEffect and c . recordEffect then
( node ) . compilerFeatureEffect = moduleEffect
c . recordEffect ( moduleEffect )
end
node . qualifiedModule = candidate
node . qualifiedMembers = suffix



if # suffix == 0 then
( node ) . requiredModule = candidate
end
( node ) . namespacePath = written
if # suffix == 1 then
node . exactCallExport = {
module = candidate ,
member = suffix [ 1 ] ,
identity = candidate .. "." .. suffix [ 1 ] ,
}
end
node . immutablePath = true
node . resolvedType = resolved
local qualifiedTokens = nameTokens or { }
local prefix = ""
for tokenIndex = 1 , # qualifiedTokens - # suffix do
local token = qualifiedTokens [ tokenIndex ]
prefix = prefix == "" and token . text or prefix .. "." .. token . text
local moduleDefinition = registry . moduleDefinitions and registry . moduleDefinitions [ prefix ] or nil
c . markToken ( token , moduleDefinition , nil , "module" )
end
if node . name then
local exports = c . env . resolveModuleExports and c . env . resolveModuleExports ( c . env , candidate ) or nil
local exported = # suffix == 0
and registry . moduleDefinitions
and registry . moduleDefinitions [ candidate ]
or # suffix == 1 and exports and exports . valueDefs and exports . valueDefs [ suffix [ 1 ] ]
or definition
c . markToken ( node . name , exported , resolved , exported and exported . kind or "property" )
end
return resolved
end
local parent , last = candidate : match ( "^(.*)%.([^.]+)$" )
if not parent then
do break end
end
table . insert ( suffix , 1 , last )
candidate = parent
end

return nil
end



local function moduleHolder ( holderName ) 
if holderName == "" then
return false
end
if c . moduleLocal and holderName == c . moduleLocal then
return true
end
local holder = c . lookupEntry ( holderName )

return holder ~= nil and holder . requiredModule ~= nil
end




local function aggregateValue ( t ) 
local raw = rawType ( t )
while raw . tag == "const" do
raw = rawType ( raw . inner )
end
if raw . tag == "nominal" and raw . declKind == "struct" then


local origin = ( ( raw ) . origin or raw )

return origin . nativeOnly ~= true
end

return raw . tag == "carray"
end




local function referenceRead ( node , parent , t ) 
if c . ownershipKind ( t ) or not aggregateValue ( t ) then
return t
end
local roots = c . own . provenanceOwners ( parent )
if # roots == 0 then
c . diag ( "NUPP2619" , node , "a reference into a temporary struct needs a rooted parent" , nil , {
help = "bind the struct or array it lives in to a local first"
} )
else
c . own . capabilityFacts ( node ) . roots = roots
end

return T . borrowed ( t )
end




local function soaColumn ( node , target , descriptor , name , at ) 
local element = rawType ( descriptor . element )
local ordinal = nil
if element . tag == "nominal" then
for position , fieldName in ipairs ( element . fieldOrder or { } ) do
if fieldName == name then
ordinal = position
do break end
end
end
end
if not ordinal then
c . diag ( "NUPP2403" , at or node , ("%s has no stored SoA field %q") : format ( T . tostring ( element ) , name ) )
return T . any
end
local nominalElement = element

local fieldType = c . fieldType ( element , name )
local exports = c . env and c . env . resolveModuleExports and c . env . resolveModuleExports ( c . env , "nupp.mem.span" )
or nil
local exported = exports and exports . types and exports . types [ descriptor . writable and "Writable" or "Span" ]
or nil
local projected = nil
if exported and exported . tag == "genericAlias" and exported . typeParams [ 1 ] then
projected = generics . materialize ( exported . body , { [ exported . typeParams [ 1 ] ] = fieldType } )
elseif exported and exported . tag == "nominal" and exported . typeParams and exported . typeParams [ 1 ] then
projected = generics . instantiate ( exported , { [ exported . typeParams [ 1 ] ] = fieldType } )
end
if not projected then
return T . any
end

node . soaFieldProjection = { name = name , ordinal = ordinal , writable = descriptor . writable , }
local projectedDescriptor = indexedViews . describe ( projected )
if projectedDescriptor then
node . indexedViewOperation = { kind = "field" , descriptor = projectedDescriptor , ordinal = ordinal , }
end
local definition = nominalElement . fieldDefs and nominalElement . fieldDefs [ name ] or nil
local token = at and at . token or at
if token then
c . markToken ( token , definition , fieldType , "property" )
token . soaColumn = {
identity = nominalElement . name .. "." .. name ,
ordinal = ordinal ,
access = descriptor . writable and "read-write" or "read-only" ,
}
end

if c . ownershipKind ( descriptor . nominal ) == "affine" then
c . own . expireTemporaryAfterStatement ( target )
end
local entry , nameNode = c . ownershipEntry ( target )
entry = c . ownershipState ( entry )
local entryFacts = entry and c . own . capabilityFacts ( entry , nil , false ) or nil
local regionRoot , regionPath = c . regionOf ( target )
regionPath = T . regionField ( regionPath , name )
local roots = entry and { entry } or c . own . provenanceOwners ( target )
local base = entry or c . own . pathBase ( target )
if descriptor . writable and # roots == 0 then
c . diag ( "NUPP2602" , target , "an exclusive receiver requires a named or rooted value" )
else
for _ , root in ipairs ( roots ) do
if c . own . regionBlocked ( root , base , entryFacts , regionRoot , regionPath , not descriptor . writable ) then
c . diag (
"NUPP2607" ,
nameNode or target ,
descriptor . writable
and "an exclusive receiver cannot invalidate a value while a derived borrow is live"
or "a shared receiver cannot overlap a live exclusive view" ,
nil ,
c . own . conflictDetails ( regionRoot or root , regionPath , not descriptor . writable )
)
do break end
end
end
end
local resultFacts = c . own . capabilityFacts ( node )
resultFacts . roots = # roots > 0 and roots or nil
resultFacts . exclusive = descriptor . writable or nil
if regionRoot and regionPath and regionPath ~= "" then
resultFacts . regionRoot = regionRoot
resultFacts . regionPath = regionPath
end
node . resolvedType = projected

return projected
end

local fieldOf
fieldOf = function ( node ) 
local kind = node . kind
local member = node . name
local target = node . obj
if not member or not target then
return T . any
end
local memberName = member . text
node . fixedWidthUntrusted = nil
local projected = qualifiedModule ( node )
if projected then
return projected
end

local holderName = ""
if target . kind == "name" then
local holderTok = target . token
holderName = holderTok and holderTok . text or ""
end
if kind == "dotIndex" and not node . writeContext then
local sourcePath = holderName ~= "" and holderName .. "." .. memberName or ""
local moduleName = COMPILER_MODULES [ sourcePath ]
local holder = moduleName and c . lookupEntry ( holderName ) or nil
local builtin = moduleName and c . env and c . env . globals and c . env . globals [ holderName ] or nil
if holder and builtin and holder . definition == builtin . definition and c . env and c . env . resolveModule then
local moduleType = c . env . resolveModule ( c . env , moduleName )
if moduleType then
c . infer ( target )
runtimeSurface . requireIdentity ( c , runtimeSurface . tracked ( c , target ) , memberName , member )
node . compilerModule = moduleName
node . immutablePath = true
node . resolvedType = moduleType
c . markToken ( member , nil , moduleType , "property" )
return moduleType
end
end
end
if kind == "dotIndex" and memberName == "C" and holderName == "ffi" then
return c . cNamespaceType ( )
end
if kind == "dotIndex" and not node . writeContext then
local key = c . pathKey ( node )
if c . moduleLocal and key == c . moduleLocal .. "." .. memberName then
c . resolveModuleFunction ( memberName )
end
local narrowed = key and c . lookupNarrowed ( key )
if narrowed then
local narrowedObject = c . infer ( target )
c . fixedWidth . mark ( node , narrowed )
c . fixedWidth . trust ( node , narrowed )
if holderName == c . moduleLocal then
local definition = c . moduleFieldDefs [ memberName ]
c . markToken ( member , definition , narrowed , definition and definition . kind or "function" )
else
local _ , definition , definitions = c . fieldType ( rawType ( narrowedObject ) , memberName )
c . markToken ( member , definition , narrowed , "property" )
member . additionalDefinitions = definitions
end
return narrowed
end








local declared = key and c . lookupEntry ( key )
if key and declared then
local rootName = key : match ( "^[^.]+" )
local globalRoot = rootName and c . env and c . env . globals and c . env . globals [ rootName ]
local localRoot = globalRoot and rootName and c . lookupEntry ( rootName )
local shadowed = globalRoot and localRoot and localRoot . definition ~= globalRoot . definition
if not shadowed then
c . infer ( target )
c . markToken (
member ,
declared . definition ,
declared . t ,
declared . definition and declared . definition . kind or "variable"
)
return declared . t
end
end
end
local trackedObject = c . infer ( target )
runtimeSurface . requireIdentity ( c , runtimeSurface . tracked ( c , target ) , memberName , member )
local intrinsicPath = c . pathKey ( node )
if intrinsicPath then
local root = target
while root and ( root . kind == "dotIndex" or root . kind == "safeIndex" ) do
root = root . obj
end
local token = root and root . kind == "name" and root . token or nil
local builtin = c . env and c . env . globals and c . env . globals . nupp or nil


local canonical = nil
if token and builtin and token . definition == builtin . definition then
canonical = intrinsicPath
elseif token and token . definition and token . definition . namespacePath then
canonical = token . definition . namespacePath .. intrinsicPath : sub ( # token . text + 1 )
end
if canonical then
( node ) . namespacePath = canonical
node . scalarIntrinsic = scalarIntrinsics . forPath ( canonical )
end
end



local targetDefinition = target . kind == "name" and target . token and target . token . definition or nil
local parentExport = not node . writeContext
and ( ( target ) . exactCallExport or targetDefinition and targetDefinition . exactCallExport )
or nil
if parentExport ~= nil then
node . exactCallExport = {
module = parentExport . module ,
member = parentExport . member .. "." .. memberName ,
identity = parentExport . identity .. "." .. memberName ,
}
elseif not node . writeContext and holderName ~= "" then
local holder = c . lookupEntry ( holderName )
if holder and holder . requiredModule then
node . exactCallExport = {
module = holder . requiredModule ,
member = memberName ,
identity = holder . requiredModule .. "." .. memberName ,
}
end
end
local ot = trackedObject
local base = kind == "safeIndex" and ot . tag == "union" and T . union ( ot . members ) or ot
base = rawType ( base )
local indexedView = indexedViews . describe ( base )
if base . tag == "ptr" and not c . ownershipKind ( trackedObject ) then
if c . unsafeDepth == 0 then
c . diag (
"NUPP2604" ,
node ,
"dereferencing a raw pointer requires @unsafe on the access; use an owned or borrowed value in checked code"

)
else
node . unsafeOwnershipOperation = "raw pointer dereference"
end
end





local function exportedValue ( ) 
local holder = holderName ~= "" and c . lookupEntry ( holderName ) or nil
local exporting = holder and holder . requiredModule
if not exporting or not c . env or not c . env . exportedNominal then
return nil
end
local t , def = c . env . exportedNominal ( c . env , exporting , memberName )
if t
and t . tag == "nominal"
and ( t . declKind == "record" or t . declKind == "struct" or t . declKind == "interface" )
then


local held = t . declKind == "struct" and t or T . typeObject ( t )
c . markToken ( member , def , held , def and def . kind or "variable" )
return held
end

return nil
end

if base == T . any or base == T . table_ then
local exported = exportedValue ( )
if exported then
return exported
end




node . gradualIndex = true
return T . any
end

if kind == "safeIndex" and base . tag == "union" then
local nonnil = { }
for _ , m in ipairs ( base . members ) do
if m ~= T . nil_ then
nonnil [ # nonnil + 1 ] = m
end
end
base = T . union ( nonnil )
end
local writing = node . writeContext == true
local ft , fieldDef , fieldDefs
if writing then
ft , fieldDef , fieldDefs = c . fieldWriteType ( base , memberName )
local physicalOwner = base
while physicalOwner . tag == "ptr" do
physicalOwner = rawType ( physicalOwner . elem )
end
if physicalOwner . tag == "nominal"
and physicalOwner . declKind == "struct"
and ( ( ( physicalOwner ) . origin or physicalOwner ) ) . nativeOnly == true
then



c . diag (
"NUPP2911" ,
member ,
("%s is a field of a native-only aggregate, which is a value: construct a new one")

: format ( memberName )
)
end
if physicalOwner . tag == "nominal"
and physicalOwner . declKind == "struct"
and physicalOwner . writeFieldDefs
and physicalOwner . writeFieldDefs [ memberName ]
then
node . fixedWidthPhysicalStore = true
end
local after = c . fieldType ( base , memberName )
if not after then
node . postWriteType = false
elseif node . fixedWidthPhysicalStore and after and aggregateValue ( after ) then


node . postWriteType = false
elseif node . fixedWidthPhysicalStore and after and fixedWidth . isPhysical ( after ) then


node . postWriteType = fixedWidth . loaded ( after )
elseif after ~= ft then
node . postWriteType = after
end
if after and physicalOwner . tag == "nominal" and physicalOwner . declKind == "struct" then


local pointer = subtract ( rawType ( after ) , T . nil_ )
if pointer . tag == "ptr" then
node . pointerStoreType = pointer
end
end
else
ft , fieldDef , fieldDefs = c . fieldType ( base , memberName )
end
local nominal = base . tag == "nominal" and base or nil
local declaration = nominal and ( ( ( nominal ) . origin or nominal ) ) or nil
if declaration
and declaration . privateFields
and declaration . privateFields [ memberName ]
and declaration . moduleName ~= c . result . moduleName
then
c . diag (
"NUPP2209" ,
member ,
("field %q is private to module %q") : format ( memberName , declaration . moduleName or "?" )
)
return T . any
end
if not fieldDef and not writing then
if holderName == c . moduleLocal then
fieldDef = c . moduleFieldDefs and c . moduleFieldDefs [ memberName ] or nil
else
local holder = holderName ~= "" and c . lookupEntry ( holderName ) or nil
local exporting = holder and holder . requiredModule
local exports = exporting
and c . env
and c . env . resolveModuleExports
and c . env . resolveModuleExports ( c . env , exporting )
or nil
fieldDef = exports and exports . valueDefs and exports . valueDefs [ memberName ] or nil
end
end
if not ft then
local opposite = writing and c . fieldType ( base , memberName ) or c . fieldWriteType ( base , memberName )
if opposite then
c . diag (
"NUPP2009" ,
member ,
("property %q is %s-only") : format ( memberName , writing and "read" or "write" ) ,
nil ,
{
help = writing and "assign through a view that grants write access"
or "read through a view that grants read access"
}
)
return T . any
end
if indexedView and indexedView . adapter == "soa" and not writing then
return soaColumn ( node , target , indexedView , memberName , member )
end




local contract = c . metamethodOf ( base , memberName )
if contract and ( base . tag == "metatable" or base . tag == "typeobject" ) then
node . metamethodName = memberName
node . metamethodReceiver = base
c . markToken ( member , nil , contract , "property" )
local installed = kind == "safeIndex" and T . optional ( contract ) or contract
node . resolvedType = installed
return installed
elseif contract then


c . diag (
"NUPP2004" ,
member ,
("%s is a metamethod of %s, not a field of one") : format ( memberName , T . tostring ( base ) ) ,
nil ,
{
help = "write it on the declaration's own table, which is the metatable an instance carries"


}
)
return T . any
end



if base . tag == "metatable" and ( memberName == "__index" or memberName == "__newindex" ) then
local handler = memberName == "__index" and T . func ( { T . any , T . any } , { T . any } , false )
or T . func ( { T . any , T . any , T . any } , { } , false )
local installed = T . optional ( T . union ( { T . table_ , handler } ) )
c . markToken ( member , nil , installed , "property" )
node . resolvedType = installed
return installed
end
if indexedView then
c . diag ( "NUPP2004" , member , ("no field %q in %s") : format ( memberName , T . tostring ( base ) ) , nil , {
help = "use #view for length and view[index] for element access"
} )
return T . any
end
local contractName = writing and "__newindex" or "__index"
local mm = c . metamethodOf ( base , contractName )
if mm then
local keyType = T . literal ( memberName , T . string )
node . indexObjectType , node . indexKeyType = base , keyType
node . usesIndexContract = true
if writing then
return T . any
end
local out = c . applyContract ( mm , { base , keyType } , { target , node } , node , contractName )
return kind == "safeIndex" and T . optional ( out ) or out
end
local exported = exportedValue ( )
if exported then
return exported
end
local fixes = c . edits . nameSpellingFix ( member , c . fieldNames ( base , writing ) )



local contracted = memberName : sub ( 1 , 2 ) == "__"
if not fixes and contracted then
fixes = c . edits . spellingFix ( member , c . metamethodNames ( base ) )
end
c . diag ( "NUPP2004" , member , ("no field %q in %s") : format ( memberName , T . tostring ( base ) ) , fixes , {
help = fixes
and ( contracted and "use the suggested contract spelling" or "use the suggested field spelling" )
or "check the receiver type and available fields"
} )
return T . any
end
local staticOwner = ( base . tag == "metatable" or base . tag == "typeobject" ) and rawType ( base . of ) or nil
if not writing
and staticOwner
and staticOwner . tag == "nominal"
and staticOwner . overloadedStatics
and staticOwner . overloadedStatics [ memberName ]
then
node . staticOverloadOwner = staticOwner
node . staticOverloadName = memberName
if not node . callCallee then
c . diag (
"NUPP2126" ,
member ,
("overloaded static function %q has no single field value") : format ( memberName ) ,
nil ,
{ help = "call it through the declaration table so the arguments select one body" }
)
end
elseif not writing
and base . tag == "nominal"
and base . overloadedMethods
and base . overloadedMethods [ memberName ]
then
c . diag ( "NUPP2126" , member , ("overloaded method %q has no single field value") : format ( memberName ) , nil , {
help = "call it with `:` so the arguments select one body"
} )
end


local effects = c . env and c . env . featureEffects or nil
local featureFields = effects and ( effects [ base ] or staticOwner and effects [ staticOwner ] ) or nil
local effect = featureFields and featureFields [ memberName ] or nil
if not effect and target . kind == "name" and target . token then
local holder = c . lookupEntry ( target . token . text )
if holder and holder . requiredModule then
effect = standardSurface . requireMember ( c , holder . requiredModule , memberName , member )
or native . forModuleMember ( holder . requiredModule , memberName )
end
end
if effect and c . recordEffect then
( node ) . compilerFeatureEffect = effect
c . recordEffect ( effect )
end
local ownerState = target . kind == "name" and c . ownershipState ( ( c . ownershipEntry ( target ) ) ) or nil
if ownerState and ownerState . movedFields and ownerState . movedFields [ memberName ] and not node . writeContext then
c . diag ( "NUPP2601" , node , ("owned field %q was moved and has not been reinitialized") : format ( memberName ) )
node . ownershipUseReported = true
end
if ownerState and c . ownershipKind ( ft ) == "affine" and c . ownershipKind ( ownerState . t ) == "affine" then
local exact = { }
for _ , cleanup in ipairs ( ownerState . t . cleanups or { } ) do
if cleanup . kind == "field" and cleanup . field == memberName and cleanup . cleanup then
exact [ # exact + 1 ] = cleanup . cleanup
end
end
ft = T . affine ( rawType ( ft ) , exact )
end
if not writing
and compilerOnlyValue ( ft )
and ( c . comptimeDepth or 0 ) == 0
and ( c . comptimeFunctionDepth or 0 ) == 0
then
c . diag ( "NUPP2421" , member , ("compiler-only member %q is available only inside comptime") : format ( memberName ) )
return T . any
end
c . markToken ( member , fieldDef , ft , "property" )
member . additionalDefinitions = fieldDefs
local out = kind == "safeIndex" and T . optional ( ft ) or ft
if not writing and aggregateValue ( base ) then
out = referenceRead ( node , target , out )
end
node . resolvedType = out
if kind == "dotIndex" and target . indexedAccess then
local access = target . indexedAccess
local element = access . element
local ordinal = nil
if access . adapter == "soa" and element . tag == "nominal" then
for position , name in ipairs ( element . fieldOrder or { } ) do
if name == memberName then
ordinal = position
do break end
end
end
end
if writing and not access . writable then
c . diag ( "NUPP2009" , member , "shared indexed views are read-only" , nil , {
help = "request an exclusive writable view from the owner"
} )
end
node . indexedField = {
adapter = access . adapter ,
name = memberName ,
ordinal = ordinal ,
writable = access . writable ,
element = element ,
access = target ,
}
if access . adapter == "soa" and ordinal then
node . soaField = { name = memberName , ordinal = ordinal , writable = access . writable , element = element , }
member . soaColumn = {
identity = ( element ) . name .. "." .. memberName ,
ordinal = ordinal ,
access = access . writable and "read-write" or "read-only" ,
}
if writing then
node . fixedWidthPhysicalStore = true
end
elseif access . adapter == "span" and writing then
node . fixedWidthPhysicalStore = true
end
end
if not writing and fixedWidth . isValue ( out ) then
if not ( base . tag == "nominal" and base . declKind == "record" ) or target . fixedWidthTrusted == true then
c . fixedWidth . mark ( node , out )
else
node . fixedWidthUntrusted = true
end
end
if not writing and fixedWidth . requiresTrust ( out ) and target . fixedWidthTrusted == true then
c . fixedWidth . trust ( node , out )
end
node . immutablePath = kind == "dotIndex"
and target . immutablePath == true
and c . fieldWriteType ( base , memberName ) == nil

return out
end










local function resolvedField ( node ) 
return fieldOf ( node )
end

handlers . dotIndex = function ( node ) 
local out = resolvedField ( node )
if node . kind ~= "dotIndex" or node . writeContext or out . tag ~= "func" then
return out
end
local target = node . obj
local holderTok = target and target . kind == "name" and target . token or nil
if not moduleHolder ( holderTok and holderTok . text or "" ) then
return out
end

return T . withSendable ( out )
end

handlers . safeIndex = resolvedField





local bracketIndex



handlers . bracketIndex = function ( node ) 
local out = bracketIndex ( node )
local target = node . obj
if node . writeContext or not target then
return out
end
local receiver = rawType ( c . infer ( target ) )
if receiver . tag == "const" then
return members . constRead ( out )
end

return out
end

bracketIndex = function ( node ) 
local kind = node . kind
local target , key = node . obj , node . expr
if not target or not key then
return T . any
end
local trackedObject = c . infer ( target )
if c . opts . compat == "lua51" then
local root = runtimeSurface . identity ( target )
if root then
local member = key . kind == "string"
and key . token
and require ( "nupp.compiler.syntax.lexer" ) . stringValue ( key . token . text )
or nil
if member then
runtimeSurface . requireIdentity ( c , root , member , key )
else
c . diag (
"NUPP3015" ,
key ,
"compatibility cannot verify dynamic access to the " .. root .. " runtime surface"
)
end
end
end
local ot = rawType ( trackedObject )
local writing = node . writeContext == true
if ot . tag == "const" then
if writing then
c . diag ( "NUPP2009" , node , "a const table view is read-only" )
end
ot = ot . inner
end
local it = c . infer ( key )
local view = indexedViews . describe ( ot )
if view then
local literalName = key . kind == "string"
and it . tag == "literal"
and type ( it . constant ) == "string"
and it . constant
or nil
if view . adapter == "soa" and literalName then
if writing then
c . diag ( "NUPP2009" , node , "an SoA column projection is not assignable" , nil , {
help = "index the projected column to read or write one element"
} )
return T . any
end
return soaColumn ( node , target , view , literalName , key )
elseif view . adapter == "soa" and isA ( it , T . string ) then
c . diag ( "NUPP2403" , key , "SoA field projection requires a string literal" , nil , {
help = "name one stored struct field so the compiler can select its typed column"
} )
return T . any
end
if not ( it == T . any or isA ( it , T . integer ) ) then
c . diag ( "NUPP2004" , key , ("indexed view index must be integer, got %s") : format ( T . tostring ( it ) ) )
end
if writing and not view . writable then
c . diag ( "NUPP2009" , node , "shared indexed views are read-only" , nil , {
help = "request an exclusive writable view from the owner"
} )
elseif writing then
c . own . checkExclusiveReceiver ( target , node )
end
local receiverDefinition = target . kind == "name" and target . token and target . token . definition or nil
local indexDefinition = key . kind == "name" and key . token and key . token . definition or nil
node . indexedAccess = {
adapter = view . adapter ,
element = view . element ,
writable = view . writable ,
writing = writing ,
descriptor = view ,
receiverDefinition = receiverDefinition ,
indexDefinition = indexDefinition ,
}
node . indexObjectType , node . indexKeyType = ot , it
node . usesIndexContract = true
if view . adapter == "soa" then
node . soaRow = { element = view . element , writable = view . writable }
end
node . containerTag = view . adapter
node . fixedWidthPhysicalStore = writing
local result = not writing and fixedWidth . loaded ( view . element ) or view . element
if not writing and fixedWidth . isValue ( result ) then
c . fixedWidth . markLoaded ( node , view . element )
c . fixedWidth . trust ( node , result )
end
if view . adapter == "span" then
if writing then
node . postWriteType = false
else
result = referenceRead ( node , target , result )
end
end
return result
end
local staticallyBounded = ot . tag == "carray"
and ot . count ~= nil
and it . tag == "literal"
and type ( it . constant ) == "number"
and it . constant % 1 == 0
and it . constant >= 0
and it . constant < ot . count
local literalIndex = it . tag == "literal" and type ( it . constant ) == "number" and it . constant % 1 == 0
local boundsReported = false
if ot . tag == "carray" and ot . count ~= nil and literalIndex and not staticallyBounded then
c . diag ( "NUPP2604" , node , "fixed C array index is outside its declared bound" )
boundsReported = true
elseif ot . tag == "carray" and ot . count ~= nil and not staticallyBounded then
node . carrayBound = ot . count
end
if ( ot . tag == "ptr" or ot . tag == "carray" ) and not staticallyBounded then
if boundsReported then

elseif node . carrayBound and c . unsafeDepth == 0 then

elseif c . unsafeDepth == 0 then
c . diag (
"NUPP2604" ,
node ,
"indexing C memory requires @unsafe on the access; use a checked span when a runtime bound is available"

)
else
node . unsafeOwnershipOperation = "unchecked C memory indexing"
end
end
if ot == T . any or ot == T . table_ then


( node ) . gradualIndex = true
return T . any
end


node . containerTag = ot . tag
node . containerIsSequence = ot . tag == "nominal" and ot . arrayOf ~= nil
if ot . tag == "union" then



local outs = { }
local validOuts = true
for _ , m in ipairs ( ot . members ) do
local mt = rawType ( m )
if mt == T . any or mt == T . table_ then
outs [ # outs + 1 ] = T . any
elseif mt . tag == "array" or mt . tag == "carray" then
outs [ # outs + 1 ] = mt . tag == "carray" and not writing and fixedWidth . loaded ( mt . elem ) or mt . elem
elseif mt . tag == "map" then
if writing and mt . writeValue then
outs [ # outs + 1 ] = mt . writeValue
elseif not writing and mt . readable then
outs [ # outs + 1 ] = T . optional ( mt . value )
else
validOuts = false
do break end
end
elseif mt . tag == "tuple" then
outs [ # outs + 1 ] = T . union ( mt . elems )
elseif mt . tag == "nominal" and mt . arrayOf then
outs [ # outs + 1 ] = mt . arrayOf
elseif ( mt . tag == "shape" or mt . tag == "nominal" ) and writing and mt . indexWriteValue then
outs [ # outs + 1 ] = mt . indexWriteValue
elseif ( mt . tag == "shape" or mt . tag == "nominal" ) and not writing and mt . indexReadValue then
outs [ # outs + 1 ] = T . optional ( mt . indexReadValue )
else
validOuts = false
do break end
end
end
if validOuts and writing then
node . postWriteType = false
local accepted = nil
for _ , candidate in ipairs ( outs ) do
if not accepted or isA ( candidate , accepted ) then
accepted = candidate
elseif not isA ( accepted , candidate ) then
accepted = T . never
end
end
return accepted or T . never
elseif validOuts then
return T . union ( outs )
end
end
if ot . tag == "intersection" then
local outs , sawCapability = { } , false
for _ , member in ipairs ( ot . members ) do
local mt = rawType ( member )
local keyType , valueType , optional = nil , nil , false
if mt . tag == "array" or mt . tag == "carray" then
keyType = T . integer
valueType = mt . tag == "carray" and not writing and fixedWidth . loaded ( mt . elem ) or mt . elem
elseif mt . tag == "tuple" then
keyType , valueType = T . integer , T . union ( mt . elems )
elseif mt . tag == "map" then
keyType = writing and mt . writeKey or ( mt . readable and mt . key or nil )
valueType = writing and mt . writeValue or ( mt . readable and mt . value or nil )
optional = not writing
elseif mt . tag == "nominal" and mt . arrayOf then
keyType , valueType = T . integer , mt . arrayOf
elseif mt . tag == "shape" or mt . tag == "nominal" then
keyType = writing and mt . indexWriteKey or mt . indexReadKey
valueType = writing and mt . indexWriteValue or mt . indexReadValue
optional = not writing
end
if keyType and valueType then
sawCapability = true
if isA ( it , keyType ) then
outs [ # outs + 1 ] = optional and T . optional ( valueType ) or valueType
end
end
end
if # outs > 0 then
if writing then
node . postWriteType = false
return T . union ( outs )
end
return T . intersection ( outs )
elseif sawCapability then
c . diag ( "NUPP2004" , key , ("no intersection indexer accepts %s") : format ( T . tostring ( it ) ) )
return T . any
end
end
if ot . tag == "ptr" then


if not ( it == T . any or isA ( it , T . number ) ) then
c . diag ( "NUPP2004" , key , ("pointer index must be numeric, got %s") : format ( T . tostring ( it ) ) )
end
local elem = ot . elem
local readOnly = false
while elem . tag == "const" do
elem , readOnly = elem . inner , true
end
if writing then
if readOnly then
c . diag ( "NUPP2009" , node , "cannot write through a const pointer" )
return T . any
end
node . fixedWidthPhysicalStore = true
if aggregateValue ( elem ) then
node . postWriteType = false
elseif fixedWidth . isPhysical ( elem ) then
node . postWriteType = fixedWidth . loaded ( elem )
end
return elem
end
local loaded = fixedWidth . loaded ( elem )
c . fixedWidth . markLoaded ( node , elem )
return referenceRead ( node , target , loaded )
end
if ot . tag == "carray" then


if not ( it == T . any or isA ( it , T . number ) ) then
c . diag ( "NUPP2004" , key , ("carray index must be numeric, got %s") : format ( T . tostring ( it ) ) )
end

if writing then
node . fixedWidthPhysicalStore = true
if aggregateValue ( ot . elem ) then
node . postWriteType = false
elseif fixedWidth . isPhysical ( ot . elem ) then
node . postWriteType = fixedWidth . loaded ( ot . elem )
end
return ot . elem
end
local loaded = fixedWidth . loaded ( ot . elem )
c . fixedWidth . markLoaded ( node , ot . elem )
return referenceRead ( node , target , loaded )
end
if ot . tag == "nominal" and ot . arrayOf then
if not ( it == T . any or isA ( it , T . integer ) ) then
c . diag ( "NUPP2004" , key , ("array index must be integer, got %s") : format ( T . tostring ( it ) ) )
end
return ot . arrayOf or T . any
elseif ot . tag == "array" then
if not ( it == T . any or isA ( it , T . integer ) ) then
c . diag ( "NUPP2004" , key , ("array index must be integer, got %s") : format ( T . tostring ( it ) ) )
end


return ot . elem
elseif ot . tag == "map" then
if writing and not ot . writeValue then
c . diag ( "NUPP2009" , node , "indexer is read-only" , nil , {
help = "assign through a view that grants write access"
} )
return T . any
elseif not writing and not ot . readable then
c . diag ( "NUPP2009" , node , "indexer is write-only" , nil , {
help = "read through a view that grants read access"
} )
return T . any
end
local keyType = writing and ot . writeKey or ot . key
local valueType = writing and ot . writeValue or ot . value
local ok , why = isA ( it , keyType )
if not ok then
c . diag ( "NUPP2004" , key , ("map key: %s") : format ( why ) )
end
if writing then
if not ot . readable then
node . postWriteType = false
elseif ot . value ~= valueType then
node . postWriteType = T . optional ( ot . value )
end
return valueType
end
return T . optional ( valueType )
elseif ot . tag == "tuple" then
if it . tag == "literal" and it . base == T . integer then
return ot . elems [ it . constant ] or T . nil_
end
return T . union ( ot . elems )
end
if ot . tag == "shape" or ot . tag == "nominal" then
local keyType = writing and ot . indexWriteKey or ot . indexReadKey
local valueType = writing and ot . indexWriteValue or ot . indexReadValue
if keyType and valueType then
local ok , why = isA ( it , keyType )
if not ok then
c . diag ( "NUPP2004" , key , ("indexer key: %s") : format ( why ) )
end
if writing then
if not ot . indexReadValue then
node . postWriteType = false
elseif ot . indexReadValue ~= valueType then
node . postWriteType = T . optional ( ot . indexReadValue )
end
return valueType
end
return T . optional ( valueType )
end
local opposite = writing and ot . indexReadValue or ot . indexWriteValue
if opposite then
c . diag ( "NUPP2009" , node , writing and "indexer is read-only" or "indexer is write-only" )
return T . any
end
end
local contractName = writing and "__newindex" or "__index"
local mm = c . metamethodOf ( ot , contractName )
if mm then
node . indexObjectType , node . indexKeyType = ot , it
node . usesIndexContract = true
if writing then
return T . any
end
local out = c . applyContract ( mm , { ot , it } , { target , key } , node , contractName )
return kind == "safeBracket" and T . optional ( out ) or out
end
c . diag ( "NUPP2004" , node , ("cannot index %s") : format ( T . tostring ( ot ) ) )

return T . any
end
handlers . safeBracket = handlers . bracketIndex

return handlers
end

local __nuppExportValue= index ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.index"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.index"]=__nuppExports;return __nuppExports