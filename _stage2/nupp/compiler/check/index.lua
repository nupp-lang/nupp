_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);











local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.relations" )
local cst = require ( "nupp.compiler.cst" )
local state = require ( "nupp.compiler.check.state" )
local scalarIntrinsics = require ( "nupp.compiler.scalar_intrinsics" )
local fixedWidth = require ( "nupp.compiler.fixed_width" )

local isA = relations . isA
local rawType = T . unwrapOwnership

local index = { }





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
local handlers = { }

handlers . dotIndex = function ( node )
local kind = node . kind
local member = node . name
local target = node . obj
if not member or not target then
return T . any
end
local memberName = member . text
node . fixedWidthUntrusted = nil

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
if declared then
local rootName = key : match ( "^[^.]+" )
local globalRoot = rootName and c . env and c . env . globals and c . env . globals [ rootName ]
local localRoot = globalRoot and c . lookupEntry ( rootName )
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
local intrinsicPath = c . pathKey ( node )
if intrinsicPath then
local root = target
while root and ( root . kind == "dotIndex" or root . kind == "safeIndex" ) do
root = root . obj
end
local token = root and root . kind == "name" and root . token or nil
local builtin = c . env and c . env . globals and c . env . globals . nupp or nil
if token and builtin and token . definition == builtin . definition then
node . scalarIntrinsic = scalarIntrinsics . forPath ( intrinsicPath )
end
end



if not node . writeContext and holderName ~= "" then
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
if base . tag == "ptr" and not c . ownershipKind ( trackedObject ) then
if c . unsafeDepth == 0 then
c . diag (
"NUPP2604" ,
node ,
"dereferencing a raw pointer requires unsafe do; use an "
.. "owned or borrowed value in checked code"
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
if t and t . tag == "nominal" and (
t . declKind == "record" or t . declKind == "struct" or t . declKind == "interface"
) then


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
and physicalOwner . writeFieldDefs
and physicalOwner . writeFieldDefs [
memberName
] then
node . fixedWidthPhysicalStore = true
end
local after = c . fieldType ( base , memberName )
if not after then
node . postWriteType = false
elseif after ~= ft then
node . postWriteType = after
end
else
ft , fieldDef , fieldDefs = c . fieldType ( base , memberName )
end
local nominal = base . tag == "nominal" and base or nil
local declaration = nominal and ( ( ( nominal ) . origin or nominal ) ) or nil
if declaration and declaration . privateFields and declaration . privateFields [
memberName
] and declaration . moduleName ~= c . result . moduleName then
c . diag (
"NUPP2209" ,
member ,
( "field %q is private to module %q" ) : format ( memberName , declaration . moduleName or "?" )
)
return T . any
end
if not fieldDef and not writing then
if holderName == c . moduleLocal then
fieldDef = c . moduleFieldDefs and c . moduleFieldDefs [ memberName ] or nil
else
local holder = holderName ~= "" and c . lookupEntry ( holderName ) or nil
local exporting = holder and holder . requiredModule
local exports = exporting and c . env and c . env . resolveModuleExports and c . env . resolveModuleExports (
c . env ,
exporting
) or nil
fieldDef = exports and exports . valueDefs and exports . valueDefs [ memberName ] or nil
end
end
if not ft then
local opposite = writing and c . fieldType ( base , memberName ) or c . fieldWriteType ( base , memberName )
if opposite then
c . diag (
"NUPP2009" ,
member ,
( "property %q is %s-only" ) : format ( memberName , writing and "read" or "write" ) ,
nil ,
{
help = writing
and "assign through a view that grants write access"
or "read through a view that grants read access"
}
)
return T . any
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
( "%s is a metamethod of %s, not a field of one" ) : format ( memberName , T . tostring ( base ) ) ,
nil ,
{
help = (
"write it on the declaration's own table, which is " .. "the metatable an instance carries"
)
}
)
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
c . diag ( "NUPP2004" , member , ( "no field %q in %s" ) : format ( memberName , T . tostring ( base ) ) , fixes , {
help = fixes and (
contracted and "use the suggested contract spelling" or "use the suggested field spelling"
) or "check the receiver type and available fields"
} )
return T . any
end
local staticOwner = ( base . tag == "metatable" or base . tag == "typeobject" ) and rawType ( base . of ) or nil
if not writing
and staticOwner
and staticOwner . tag == "nominal"
and staticOwner . overloadedStatics
and staticOwner . overloadedStatics [
memberName
] then
node . staticOverloadOwner = staticOwner
node . staticOverloadName = memberName
if not node . callCallee then
c . diag (
"NUPP2126" ,
member ,
( "overloaded static function %q has no single field value" ) : format ( memberName ) ,
nil ,
{ help = "call it through the declaration table so the arguments select one body" }
)
end
elseif not writing and base . tag == "nominal" and base . overloadedMethods and base . overloadedMethods [
memberName
] then
c . diag ( "NUPP2126" , member , ( "overloaded method %q has no single field value" ) : format ( memberName ) , nil , {
help = "call it with `:` so the arguments select one body"
} )
end


local effects = c . env and c . env . featureEffects or nil
local featureFields = effects and ( effects [ base ] or staticOwner and effects [ staticOwner ] ) or nil
local effect = featureFields and featureFields [ memberName ] or nil
if effect and c . recordEffect then
( node ) . compilerFeatureEffect = effect
c . recordEffect ( effect )
end
local ownerState = target . kind == "name" and c . ownershipState ( ( c . ownershipEntry ( target ) ) ) or nil
if ownerState and ownerState . movedFields and ownerState . movedFields [ memberName ] and not node . writeContext then
c . diag ( "NUPP2601" , node , ( "owned field %q was moved and has not been reinitialized" ) : format ( memberName ) )
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
if not writing and compilerOnlyValue (
ft
) and ( c . comptimeDepth or 0 ) == 0 and ( c . comptimeFunctionDepth or 0 ) == 0 then
c . diag ( "NUPP2421" , member , ( "compiler-only member %q is available only inside comptime" ) : format ( memberName ) )
return T . any
end
c . markToken ( member , fieldDef , ft , "property" )
member . additionalDefinitions = fieldDefs
local out = kind == "safeIndex" and T . optional ( ft ) or ft
node . resolvedType = out
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
node . immutablePath = kind == "dotIndex" and target . immutablePath == true and c . fieldWriteType (
base ,
memberName
) == nil

return out
end
handlers . safeIndex = handlers . dotIndex

handlers . bracketIndex = function ( node )
local kind = node . kind
local target , key = node . obj , node . expr
if not target or not key then
return T . any
end
local trackedObject = c . infer ( target )
local ot = rawType ( trackedObject )
local writing = node . writeContext == true
local it = c . infer ( key )
local staticallyBounded = ot . tag == "carray" and ot . count ~= nil and it . tag == "literal" and type (
it . constant
) == "number" and it . constant % 1 == 0 and it . constant >= 0 and it . constant < ot . count
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
"indexing C memory requires unsafe do; use a checked span " .. "when a runtime bound is available"
)
else
node . unsafeOwnershipOperation = "unchecked C memory indexing"
end
end
if ot == T . any or ot == T . table_ then
return T . any
end


node . containerTag = ot . tag
node . containerIsSequence = ot . tag == "nominal" and ot . arrayOf ~= nil
if ot . tag == "union" then



local outs = { }
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
outs = nil
break
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
outs = nil
break
end
end
if outs and writing then
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
elseif outs then
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
c . diag ( "NUPP2004" , key , ( "no intersection indexer accepts %s" ) : format ( T . tostring ( it ) ) )
return T . any
end
end
if ot . tag == "carray" then


if not ( it == T . any or isA ( it , T . number ) ) then
c . diag ( "NUPP2004" , key , ( "carray index must be numeric, got %s" ) : format ( T . tostring ( it ) ) )
end

if writing then
node . fixedWidthPhysicalStore = true
return ot . elem
end
local loaded = fixedWidth . loaded ( ot . elem )
c . fixedWidth . mark ( node , loaded )
return loaded
end
if ot . tag == "nominal" and ot . arrayOf then
if not ( it == T . any or isA ( it , T . integer ) ) then
c . diag ( "NUPP2004" , key , ( "array index must be integer, got %s" ) : format ( T . tostring ( it ) ) )
end
return ot . arrayOf or T . any
elseif ot . tag == "array" then
if not ( it == T . any or isA ( it , T . integer ) ) then
c . diag ( "NUPP2004" , key , ( "array index must be integer, got %s" ) : format ( T . tostring ( it ) ) )
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
c . diag ( "NUPP2004" , key , ( "map key: %s" ) : format ( why ) )
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
return T . union ( ot . elems )
end
if ot . tag == "shape" or ot . tag == "nominal" then
local keyType = writing and ot . indexWriteKey or ot . indexReadKey
local valueType = writing and ot . indexWriteValue or ot . indexReadValue
if keyType and valueType then
local ok , why = isA ( it , keyType )
if not ok then
c . diag ( "NUPP2004" , key , ( "indexer key: %s" ) : format ( why ) )
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
c . diag ( "NUPP2004" , node , ( "cannot index %s" ) : format ( T . tostring ( ot ) ) )

return T . any
end
handlers . safeBracket = handlers . bracketIndex

return handlers
end

return index
