_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()













local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.types.relations" )
local narrowing = require ( "nupp.compiler.types.narrowing" )
local cst = require ( "nupp.compiler.syntax.cst" )
local mutation = require ( "nupp.compiler.check.mutation" )
local fixedWidth = require ( "nupp.compiler.types.fixedwidth" )
local indexedViews = require ( "nupp.compiler.types.indexedviews" )
local state = require ( "nupp.compiler.check.state" )

local isA = relations . isA
local rawType = T . unwrapOwnership







local bindings = { }





function bindings . install ( c ) 
local apply , facts = c . apply , c . facts
local applyContract , metamethodOf = apply . applyContract , apply . metamethodOf
local clearNarrowed , clearAliases = facts . clearNarrowed , facts . clearAliases
local inferList , recordModuleField = c . inferList , c . recordModuleField
local constModuleField = c . constModuleField
local applyFacts , pathKey = c . applyFacts , c . pathKey
local moveExpression = c . moveExpression
local ownershipKind , ownershipState = c . ownershipKind , c . ownershipState

local handlers = __nuppNew(0,4)





handlers . localStmt = function ( stat ) 
if stat . pattern then
local source = stat . patternSource or stat


local typesOnly = # stat . pattern > 0
for _ , entry in ipairs ( stat . pattern ) do
typesOnly = typesOnly and entry . typeOnly ~= nil
end
if typesOnly and source . kind == "call" then
source . typeOnlyRequire = true
end
local sourceType = c . infer ( source )
if ownershipKind ( sourceType ) then
c . diag ( "NUPP2603" , source , "an owned or borrowed container cannot be selected by a binding pattern" )
end
local seenFields , seenLocals = { } , { }
for index , entry in ipairs ( stat . pattern ) do
local fieldTok = entry . sourceName
local nameTok = entry . alias or fieldTok
local fieldName = fieldTok and fieldTok . text or ""
local localName = nameTok and nameTok . text or ""
if seenFields [ fieldName ] then
c . diag ( "NUPP2006" , fieldTok or entry , ("a binding pattern repeats %q") : format ( fieldName ) )
end
seenFields [ fieldName ] = true
if seenLocals [ localName ] then
c . diag ( "NUPP2006" , nameTok or entry , ("a binding pattern declares %q twice") : format ( localName ) )
end
seenLocals [ localName ] = true

local fieldType , definition
local availableNames = c . fieldNames ( sourceType )
if entry . typeOnly then
local moduleName = source . requiredModule
local exports = moduleName
and c . env
and c . env . resolveModuleExports
and c . env . resolveModuleExports ( c . env , moduleName )
or nil
fieldType = exports and exports . types and exports . types [ fieldName ] or nil
definition = exports and exports . typeDefs and exports . typeDefs [ fieldName ] or nil
availableNames = { }
for name in pairs ( exports and exports . types or { } ) do
availableNames [ # availableNames + 1 ] = name
end
if not moduleName then
c . diag ( "NUPP1002" , entry . typeOnly , "'type' may select only from a literal module require" )
end
else
fieldType , definition = c . fieldType ( sourceType , fieldName )
end
entry . selectedDefinition = definition
if not fieldType then
c . diag (
"NUPP2004" ,
fieldTok or entry ,
entry . typeOnly and ("no exported type %q in this module") : format ( fieldName )
or ("no field %q in %s") : format ( fieldName , T . tostring ( sourceType ) ) ,
c . edits . nameSpellingFix ( fieldTok , availableNames )
)
fieldType = T . any
elseif fieldTok and ( not entry . typeOnly or entry . alias ) then
c . markToken ( fieldTok , definition , fieldType , "property" )
end
if not entry . typeOnly and ownershipKind ( fieldType ) then
c . diag (
"NUPP2603" ,
fieldTok or entry ,
"a binding pattern cannot partially move an owned or borrowed field"
)
end

local annotation = entry . type and c . resolveType ( entry . type ) or nil
if annotation then
c . fixedWidth . storageOnly ( entry . type , annotation , "a local value" )
local ok , why , reported = c . fixedWidth . fits ( fieldType , annotation , entry )
if not ok and not reported then
c . diag ( "NUPP2001" , entry , ("cannot initialize %s: %s") : format ( localName , why ) )
end
end
local bound = annotation or fieldType
if not annotation and not stat . isConst and bound . tag == "literal" then
bound = bound . base or T . string
if bound == T . integer then
bound = T . number
end
elseif not annotation and bound == T . nil_ then
bound = T . any
end
if nameTok and entry . typeOnly then
c . bindType ( localName , fieldType , nameTok )
elseif nameTok then
c . bindVar ( localName , bound , annotation ~= nil , nameTok , nil , stat . isConst )
local boundEntry = c . scope . vars [ localName ]
if boundEntry then
if boundEntry . definition then
boundEntry . definition . initialized = true
end
boundEntry . annotationNode = entry . type
boundEntry . patternFieldDefinition = definition
boundEntry . jitTarget = definition
c . fixedWidth . setBinding ( boundEntry , entry , nil )
if boundEntry . definition then
c . nativeOnly . alias (
boundEntry . definition ,
definition ,
source . requiredModule and { module = source . requiredModule , member = fieldName } or nil
)
end
if source . requiredModule then
boundEntry . requiredModule = source . requiredModule
boundEntry . exactCallExport = {
module = source . requiredModule ,
member = fieldName ,
identity = source . requiredModule .. "." .. fieldName ,
}
if boundEntry . definition then
boundEntry . definition . requiredModule = source . requiredModule
boundEntry . definition . exactCallExport = boundEntry . exactCallExport
end
end
c . unused . declared ( nameTok , boundEntry , boundEntry . requiredModule and "require" or "variable" )
end
end
end
return
end
local initializers = stat . exprs or { }
local annotations = { }
if # stat . names == 1 and stat . types and stat . types [ 1 ] and stat . types [ 1 ] . kind == "tfunc" then
c . raises . checkParams ( stat , ( stat . types [ 1 ] ) . params or { } )
end
for index , typeNode in ipairs ( stat . types or { } ) do
local annotation = c . resolveType ( typeNode )



typeNode . resolvedType = annotation
annotations [ index ] = annotation
c . fixedWidth . storageOnly ( typeNode , annotation , "a local value" )
local initializer = initializers [ index ]
if initializer ~= nil then
( initializer ) . expectedResult = annotation
end
if initializer and initializer . kind == "comptimeExpr" then
initializer . materializationExpected = annotation
end
local rawAnnotation = T . unwrapOwnership ( annotation )
if initializer and rawAnnotation . tag == "func" and rawAnnotation . sendable then
local contextual = initializer
contextual . sendableContext = true
end



if initializer
and rawAnnotation . tag == "func"
and ( initializer . kind == "shortfn" or initializer . kind == "funcExpr" )
then
local contextual = initializer
contextual . expectedCallable = annotation
end
end
local inferred = inferList ( stat . exprs , # stat . names )
local initializerCount = # initializers
for j , nameTok in ipairs ( stat . names ) do
local ann = annotations [ j ]
local init = inferred [ j ]
local moduleInitializer = initializers [ j ]
if nameTok . text == c . moduleLocal
and init
and init . tag == "shape"
and moduleInitializer
and moduleInitializer . kind == "tableExpr"
then
for _ , field in ipairs ( moduleInitializer . fields or { } ) do
if field . kind == "fieldNamed" and field . name then
local member = init . byname and init . byname [ field . name . text ]
if member then
local target = {
kind = "dotIndex" ,
obj = { kind = "name" , token = nameTok } ,
name = field . name ,
}
recordModuleField ( target , member , field . isConst , field . value )
end
end
end
end
if ann and init then
local initializer = initializers [ j ]
or initializerCount > 0 and j >= initializerCount and initializers [ initializerCount ]
or nil
if initializer and j >= initializerCount then
initializer . fixedWidthResultIndex = j - initializerCount + 1
end
if initializer then
initializer . fixedWidthTargetTypeNode = stat . types [ j ]
end
local ok , why , reported = c . fixedWidth . fits ( init , ann , initializer or stat )
if ok and relations . typevarMismatch ( init , ann ) then
ok = false
why = ("%s is not a value of the generic type %s") : format ( T . tostring ( init ) , T . tostring ( ann ) )
end
if not ok and not reported then
c . diag ( "NUPP2001" , initializers [ j ] or stat , ("cannot initialize %s: %s") : format ( nameTok . text , why ) )
end


c . checkMetatableLiteral ( initializers [ j ] , init , ann )
if ownershipKind ( init ) and ownershipKind ( init ) ~= ownershipKind ( ann ) then
local code = ann == T . any and "NUPP2611" or "NUPP2603"
c . diag (
code ,
initializers [ j ] or stat ,
ann == T . any and "a live capability cannot be erased into any"
or ( ownershipKind ( init ) ) .. " value needs a matching ownership annotation"
)
elseif ok
and not ownershipKind ( init )
and init ~= T . nil_
and ( ownershipKind ( ann ) == "affine" or ownershipKind ( ann ) == "pinned" )
then




local erased = init == T . any or init == T . unknown
c . diag (
erased and "NUPP2611" or "NUPP2603" ,
initializers [ j ] or stat ,
erased and "a value of type any cannot become an owner by annotation"
or ("%s cannot become an owner by annotation") : format ( T . tostring ( init ) ) ,
nil ,
{ help = "obtain the owner from a typed producer, or use @unsafe nupp.adopt<Owner>(value)" }
)
end
end







local bound = ann or init or T . any




if ann and init and ownershipKind ( ann ) == "affine" and ownershipKind ( init ) == "affine" then
if # ( ( ann ) . cleanups or { } ) > 0 then
bound = ann
elseif c . own . optionalOwned ( ann ) then
bound = T . affine ( rawType ( ann ) , ( init ) . cleanups )
else
bound = init
end
end
if not ann then
local initNode = initializers [ j ]
if bound . tag == "literal" and not stat . isConst then


bound = bound . base or T . string
if bound == T . integer then
bound = T . number
end
elseif bound . tag == "shape" and initNode and initNode . kind == "tableExpr" then
local hasConst = false
for _ , field in ipairs ( initNode . fields or { } ) do
if field . kind == "fieldNamed" and field . isConst then
hasConst = true ;
do break end
end
end
if not hasConst then
bound = T . table_
end
elseif bound == T . nil_
and ( not ( c . opts and c . opts . strict ) or initializerCount == 0 or initializers [ j ] ~= nil )
then
bound = T . any
end


bound = T . settled ( bound )
end
if ( ownershipKind ( init ) == "affine" or ownershipKind ( init ) == "pinned" )
and stat . exprs
and initializers [ j ]
then
moveExpression ( initializers [ j ] , init , "local initialization" , ownershipKind ( init ) )
end
if ann and nameTok . text == c . moduleLocal then
c . moduleLocalAnnotated = true
end
local boundInitializer = initializers [ j ]
if boundInitializer and boundInitializer . kind == "methodCall" and boundInitializer . name then
local descriptor = indexedViews . describe ( bound )
if descriptor and boundInitializer . name . text == "slice" then
boundInitializer . indexedViewOperation = { kind = "slice" , descriptor = descriptor , }
elseif descriptor and boundInitializer . name . text == "shared" then
boundInitializer . indexedViewOperation = { kind = "shared" , descriptor = descriptor , }
end
end
c . bindVar ( nameTok . text , bound , ann ~= nil , nameTok , nil , stat . isConst )
local boundEntry = c . scope . vars [ nameTok . text ]


if boundEntry and ownershipKind ( bound ) == "affine" and init == T . nil_ then
ownershipState ( boundEntry ) . emptySlot = true
end
local initNode = initializers [ j ]
or initializerCount > 0 and j >= initializerCount and initializers [ initializerCount ]
or nil
local fixedResultIndex = initNode and j >= initializerCount and j - initializerCount + 1 or nil
if initNode and fixedResultIndex then
initNode . fixedWidthResultIndex = fixedResultIndex
end
if boundEntry then
if boundEntry . definition and initNode then
boundEntry . definition . initialized = true
end
boundEntry . annotationNode = stat . types and stat . types [ j ] or nil
boundEntry . runtimeSurfaceRoot = require ( "nupp.compiler.runtimesurface" ) . tracked ( c , initNode )
c . fixedWidth . setBinding ( boundEntry , initNode , fixedResultIndex )
end
if boundEntry and initNode and ( initNode . kind == "funcExpr" or initNode . kind == "shortfn" ) then
local functionBody = initNode . body or initNode
functionBody . jitDefinition = boundEntry . definition
boundEntry . jitTarget = boundEntry . definition
elseif boundEntry and initNode and initNode . kind == "name" and initNode . token then
local sourceEntry = c . lookupEntry ( initNode . token . text )
if sourceEntry then
boundEntry . jitTarget = sourceEntry . jitTarget or sourceEntry . definition
end
end
if boundEntry and boundEntry . automaticOwner then
local automatic = boundEntry . automaticOwner
automatic . stat = stat
automatic . index = j
automatic . expr = initNode
automatic . type = bound
stat . automaticOwners = stat . automaticOwners or { }
stat . automaticOwners [ j ] = automatic
end
if boundEntry and bound . tag == "protocolThread" then
if initNode and initNode . coroutineIntrinsic == "create" then
boundEntry . threadPhase = "new"
elseif initNode and initNode . kind == "name" and initNode . token then
local source = c . lookupEntry ( initNode . token . text )
boundEntry . threadPhase = source and source . threadPhase or "unknown"
if source then
source . threadPhase = "unknown"
end
else
boundEntry . threadPhase = "unknown"
end
end












if boundEntry and initNode and initNode . kind == "name" and initNode . token then
local globals = c . env and c . env . globals or { }
local coroutineGlobal = globals . coroutine
local source = c . lookupEntry ( initNode . token . text )
local isLibrary = coroutineGlobal ~= nil and source == coroutineGlobal
if not isLibrary and source ~= nil then
isLibrary = source . coroutineLibrary == true
end





if not isLibrary
and coroutineGlobal ~= nil
and initNode . token . definition ~= nil
and initNode . token . definition == coroutineGlobal . definition
then
isLibrary = true
end
boundEntry . coroutineLibrary = isLibrary


boundEntry . coroutineYield = source ~= nil and source . coroutineYield == true
end




if boundEntry
and initNode
and initNode . kind == "dotIndex"
and initNode . name
and initNode . name . text == "yield"
and initNode . obj
and initNode . obj . kind == "name"
and initNode . obj . token
then
local globals = c . env and c . env . globals or { }
local coroutineGlobal = globals . coroutine
local baseTok = initNode . obj . token
local source = c . lookupEntry ( baseTok . text )
local isLibrary = false
if source ~= nil and source . coroutineLibrary == true then
isLibrary = true
elseif coroutineGlobal ~= nil then
if source ~= nil then
isLibrary = source == coroutineGlobal
or ( source . definition ~= nil and source . definition == coroutineGlobal . definition )
else
isLibrary = baseTok . text == "coroutine"
end
end
boundEntry . coroutineYield = isLibrary
end
if boundEntry and initNode and initNode . wrappedProtocol then
boundEntry . wrappedProtocol = initNode . wrappedProtocol
boundEntry . wrappedPhase = "new"
end
if boundEntry and initNode and initNode . coroutineStatusName then
boundEntry . coroutineStatusName = initNode . coroutineStatusName
end
local returnRoots = nil
local returnExclusiveBorrow = false
local returnRegionPath = nil
local returnPartitionFields = nil
local exprCount = # initializers
local expandedCall = exprCount > 0 and initializers [ exprCount ] or nil
local returnFacts = expandedCall
and j >= exprCount
and c . own . capabilityFacts ( expandedCall , j - exprCount + 1 , false )
or nil
if returnFacts then
returnRoots = returnFacts . roots
returnExclusiveBorrow = returnFacts . exclusive or false
returnRegionPath = returnFacts . regionPath
end
if expandedCall and expandedCall . returnPartitionFields and j >= exprCount then
returnPartitionFields = expandedCall . returnPartitionFields [ j - exprCount + 1 ]
end
if boundEntry then
boundEntry . partitionFields = returnPartitionFields or ( initNode and initNode . partitionFields ) or nil
end







local nominal = ann and ann . tag == "nominal" and ( ann . declKind == "record" or ann . declKind == "struct" )
local strict = c . opts and c . opts . strict
if boundEntry
and ann
and not initNode
and not c . declarationFile
and ( nominal or strict and not isA ( T . nil_ , ann ) )
then
boundEntry . unassigned = true
boundEntry . unassignedAt = nameTok
end
if boundEntry and initNode and initNode . requiredModule then
boundEntry . requiredModule = initNode . requiredModule




if boundEntry . definition then
boundEntry . definition . requiredModule = initNode . requiredModule
end
if boundEntry . t and T . unwrapOwnership ( boundEntry . t ) . tag == "func" then
boundEntry . exactCallExport = {
module = initNode . requiredModule ,
member = "$return" ,
identity = initNode . requiredModule .. ".$return" ,
}
if boundEntry . definition then
boundEntry . definition . exactCallExport = boundEntry . exactCallExport
end
end
end
if boundEntry and boundEntry . definition and initNode then
local sourceDefinition = initNode . kind == "name" and initNode . token and initNode . token . definition
or initNode . kind == "dotIndex" and initNode . name and initNode . name . definition
or nil
c . nativeOnly . alias ( boundEntry . definition , sourceDefinition , initNode . exactCallExport )
end
if boundEntry and initNode and initNode . exactCallExport then
boundEntry . exactCallExport = initNode . exactCallExport
if boundEntry . definition then
boundEntry . definition . exactCallExport = initNode . exactCallExport
end
elseif boundEntry
and initNode
and initNode . kind == "name"
and initNode . token
and initNode . token . definition
and initNode . token . definition . exactCallExport
then
boundEntry . exactCallExport = initNode . token . definition . exactCallExport
if boundEntry . definition then
boundEntry . definition . exactCallExport = boundEntry . exactCallExport
end
end



local rangeExport = initNode and initNode . kind == "call" and initNode . obj and initNode . obj . exactCallExport
or nil
local indexedRangeCall = initNode and initNode . kind == "call" and ( initNode ) . indexedRangeCall
or nil
if boundEntry
and boundEntry . definition
and stat . isConst
and rangeExport
and rangeExport . module == "nupp.mem.indexed"
and rangeExport . member == "range"
and indexedRangeCall
then
boundEntry . definition . indexedRangeWitness = { views = indexedRangeCall . views , }
end
local scalarIdentity = initNode and initNode . scalarIntrinsic
or initNode
and initNode . kind == "name"
and initNode . token
and initNode . token . definition
and initNode . token . definition . scalarIntrinsic
if boundEntry and scalarIdentity then
boundEntry . scalarIntrinsic = scalarIdentity
if boundEntry . definition then
boundEntry . definition . scalarIntrinsic = scalarIdentity
end
end



local initDynamic = initNode
local namespacePath = initDynamic and initDynamic . namespacePath
or initNode
and initNode . kind == "name"
and initNode . token
and initNode . token . definition
and initNode . token . definition . namespacePath
if boundEntry and boundEntry . definition and namespacePath then
boundEntry . definition . namespacePath = namespacePath
end




if boundEntry and initNode and initNode . kind == "dotIndex" then
boundEntry . aliasNode = initNode
boundEntry . aliasPath = pathKey ( initNode )
end
if boundEntry and initNode and initNode . kind == "name" and initNode . token then
local sourceEntry = c . lookupEntry ( initNode . token . text )
local source = init and rawType ( init ) or nil
if source
and (
source == T . table_
or source . tag == "array"
or source . tag == "map"
or source . tag == "tuple"
or source . tag == "shape"
or source . tag == "nominal"
)
then
boundEntry . aliasNode = initNode
boundEntry . aliasPath = pathKey ( initNode )
end
if sourceEntry and sourceEntry . resourceCapability then



boundEntry . resourceCapability = sourceEntry . resourceCapability
end
if sourceEntry then
boundEntry . mutationSummaryKnown = sourceEntry . mutationSummaryKnown
or ( sourceEntry . definition and sourceEntry . definition . mutationSummaryKnown )
or nil
boundEntry . mutatesParams = sourceEntry . mutatesParams
boundEntry . mutatesParamPaths = sourceEntry . mutatesParamPaths
boundEntry . mutatesCapturedEntries = sourceEntry . mutatesCapturedEntries
boundEntry . mutatesCapturedPaths = sourceEntry . mutatesCapturedPaths
boundEntry . mutatesSelf = sourceEntry . mutatesSelf
boundEntry . mutatesSelfPaths = sourceEntry . mutatesSelfPaths
if sourceEntry . definition then
boundEntry . mutatesParams = boundEntry . mutatesParams or sourceEntry . definition . mutatesParams
boundEntry . mutatesParamPaths = boundEntry . mutatesParamPaths
or sourceEntry . definition . mutatesParamPaths
boundEntry . mutatesSelfPaths = boundEntry . mutatesSelfPaths
or sourceEntry . definition . mutatesSelfPaths
boundEntry . mutatesCapturedEntries = boundEntry . mutatesCapturedEntries
or sourceEntry . definition . mutatesCapturedEntries
boundEntry . mutatesCapturedPaths = boundEntry . mutatesCapturedPaths
or sourceEntry . definition . mutatesCapturedPaths
boundEntry . mutatesSelf = boundEntry . mutatesSelf or sourceEntry . definition . mutatesSelf
end
end
if sourceEntry and sourceEntry . packCorrelation then
boundEntry . packCorrelation = sourceEntry . packCorrelation
boundEntry . packCorrelationIndex = sourceEntry . packCorrelationIndex
local group = sourceEntry . packCorrelation
group . extraNames = group . extraNames or { }
group . extraNames [
# group . extraNames + 1
] = { name = nameTok . text , index = sourceEntry . packCorrelationIndex , }
end
end
if boundEntry and initNode and initNode . kind == "funcExpr" then
local functionNode = initNode
boundEntry . mutatesParams = functionNode . mutatesParams
boundEntry . mutatesParamPaths = functionNode . mutatesParamPaths
boundEntry . mutatesCapturedEntries = functionNode . mutatesCapturedEntries
boundEntry . mutatesCapturedPaths = functionNode . mutatesCapturedPaths
boundEntry . mutatesSelf = functionNode . mutatesSelf
boundEntry . mutatesSelfPaths = functionNode . mutatesSelfPaths
boundEntry . mutationSummaryKnown = true
end
if boundEntry and ( ownershipKind ( bound ) == "affine" or ownershipKind ( bound ) == "pinned" ) and not init then
boundEntry . moved = true
end
local boundKind = ownershipKind ( bound )
if boundEntry and returnFacts and returnFacts . origin then
c . own . capabilityFacts ( boundEntry ) . retention = returnFacts . retention
end
if boundEntry and expandedCall and expandedCall . resourceCapability and j == exprCount then
boundEntry . resourceCapability = expandedCall . resourceCapability
end
if boundEntry and returnRegionPath then
local regionRoot = returnFacts and returnFacts . regionRoot or returnRoots and returnRoots [ 1 ]
local boundFacts = c . own . capabilityFacts ( boundEntry )
boundFacts . regionRoot = regionRoot
boundFacts . regionPath = returnRegionPath
if regionRoot then
regionRoot . activeRegions = regionRoot . activeRegions or { }
regionRoot . activeRegions [ returnRegionPath ] = ( regionRoot . activeRegions [ returnRegionPath ] or 0 ) + 1
end
elseif boundEntry and initNode and j <= exprCount then


local regionRoot , regionPath = c . regionOf ( initNode )
local initFacts = c . own . capabilityFacts ( initNode , nil , false )
local carriesRegion = boundKind ~= nil or initFacts . exclusive or initFacts . roots ~= nil
if carriesRegion and regionRoot and regionPath and regionPath ~= "" then
local boundFacts = c . own . capabilityFacts ( boundEntry )
boundFacts . regionRoot = regionRoot
boundFacts . regionPath = regionPath
regionRoot . activeRegions = regionRoot . activeRegions or { }
regionRoot . activeRegions [ regionPath ] = ( regionRoot . activeRegions [ regionPath ] or 0 ) + 1
if initFacts . exclusive then
returnExclusiveBorrow = true
end
end
end




local borrowRoots = returnRoots
or j <= exprCount and initNode and c . own . capabilityFacts ( initNode , nil , false ) . roots
or nil
if boundEntry
and ( boundKind == "borrowed" or boundKind == "affine" )
and borrowRoots
and # borrowRoots > 0
then
local boundFacts = c . own . capabilityFacts ( boundEntry )
local roots = { }
for index , owner in ipairs ( borrowRoots ) do
roots [ index ] = owner
owner . activeBorrows = ( owner . activeBorrows or 0 ) + 1
owner . activeBorrowSites = owner . activeBorrowSites or { }
owner . activeBorrowSites [ boundEntry ] = nameTok
if returnExclusiveBorrow then
owner . activeExclusiveBorrows = ( owner . activeExclusiveBorrows or 0 ) + 1
end
end
boundFacts . roots = roots
if returnExclusiveBorrow then
boundFacts . exclusive = true
end
end
local boundFacts = boundEntry and c . own . capabilityFacts ( boundEntry , nil , false ) or nil
if boundFacts and boundFacts . regionRoot and boundFacts . regionPath and boundFacts . exclusive then
local root , path = boundFacts . regionRoot , boundFacts . regionPath
root . activeExclusiveRegions = root . activeExclusiveRegions or { }
root . activeExclusiveRegions [ path ] = ( root . activeExclusiveRegions [ path ] or 0 ) + 1
end


if boundEntry and not stat . syntheticLoopOwner then
c . unused . declared ( nameTok , boundEntry , boundEntry . requiredModule and "require" or "variable" )
end
end





local automaticOwners = stat . automaticOwners or { }
local automaticLowerable = # initializers > 0 and # initializers <= # stat . names
for _ , automatic in pairs ( automaticOwners ) do
automatic . lowerable = automaticLowerable
end
local exprCount = # initializers
local expanded = exprCount > 0 and initializers [ exprCount ] or nil



if expanded and expanded . kind == "orExitExpr" and # stat . names > exprCount then
c . diag (
"exit-suffix-binding" ,
stat . names [ exprCount + 1 ] ,
("%q is always nil: an exit suffix supplies only its first result")

: format ( stat . names [ exprCount + 1 ] . text ) ,
nil ,
{ help = "bind the operand's results first, then test the one that decides" }
)
end
local correlated = expanded and expanded . valuePack
if correlated and correlated . alternatives then
local group = { pack = correlated , names = { } }
for j = exprCount , # stat . names do
local entry = c . lookupEntry ( stat . names [ j ] . text )
if entry then
local index = j - exprCount + 1
entry . packCorrelation = group
entry . packCorrelationIndex = index
group . names [ index ] = stat . names [ j ] . text
end
end





for resultIndex = 1 , # stat . names - exprCount + 1 do
local ownedType , activation , compatible = nil , { } , true
for _ , alternative in ipairs ( correlated . alternatives ) do
local resultType = alternative . head and alternative . head [ resultIndex ]
if resultType and ownershipKind ( resultType ) == "affine" then
if ownedType and ownedType . id ~= resultType . id then
compatible = false
do break end
end
ownedType = ownedType or resultType
local tests = { }
for slotIndex , slotType in ipairs ( alternative . head or { } ) do
if slotIndex ~= resultIndex and slotType . tag == "literal" then
tests [ # tests + 1 ] = { index = slotIndex , constant = slotType . constant , }
end
end
if # tests == 0 then
compatible = false
do break end
end
activation [ # activation + 1 ] = tests
end
end
local nameIndex = exprCount + resultIndex - 1
local entry = nameIndex >= 1 and c . lookupEntry ( stat . names [ nameIndex ] . text ) or nil
if compatible
and ownedType
and entry
and not entry . automaticOwner
and # ( ownedType . cleanups or { } ) > 0
then
local automatic = {
name = stat . names [ nameIndex ] . text ,
token = stat . names [ nameIndex ] ,
entry = entry ,
cleanups = ownedType . cleanups ,
optional = false ,
conditional = true ,
activation = activation ,
correlation = group ,
stat = stat ,
index = nameIndex ,
expr = expanded ,
type = ownedType ,
lowerable = true ,
}
entry . automaticOwner = automatic
c . scope . automaticOwners [ # c . scope . automaticOwners + 1 ] = automatic
stat . automaticOwners = stat . automaticOwners or { }
stat . automaticOwners [ nameIndex ] = automatic
end
end
end
end









local function holdProvenance ( state , target , written ) 
local writtenFacts = c . own . capabilityFacts ( written , 1 , false )
local roots = { }
for _ , root in ipairs ( writtenFacts . roots or { } ) do



if not ownershipState ( root ) . moved then
roots [ # roots + 1 ] = root
end
end
local regionRoot , regionPath = writtenFacts . regionRoot , writtenFacts . regionPath
if not roots [ 1 ] and not regionRoot then
return
end




local function outlived ( root ) 
local seen = { }
local entry = ownershipState ( root )
while entry and not seen [ entry ] do
seen [ entry ] = true
local kind = ownershipKind ( entry . t )
if ( kind == "affine" or kind == "pinned" )
and not entry . moved
and ( entry . bindingOrdinal or 0 ) > ( state . bindingOrdinal or 0 )
then
return entry
end
local next = c . own . capabilityFacts ( entry , nil , false ) . roots
entry = next and next [ 1 ] and ownershipState ( next [ 1 ] ) or nil
end

return nil
end

local candidates = { }
for _ , root in ipairs ( roots ) do
candidates [ # candidates + 1 ] = root
end
if regionRoot then
candidates [ # candidates + 1 ] = regionRoot
end
for _ , root in ipairs ( candidates ) do
local owner = outlived ( root )
if owner then
local ownerName = owner . definition and owner . definition . token and owner . definition . token . text or "?"
local related = owner . definition and c . related ( owner . definition , "the root is declared here" ) or nil
c . diag (
"NUPP2608" ,
written ,
("a value rooted in %q cannot be held by a binding that outlives it") : format ( ownerName ) ,
nil ,
{
help = "assign it to a binding declared after the root, or keep the root alive as long" ,
related = related and { related } or nil ,
}
)
return
end
end
local facts = c . own . capabilityFacts ( state )
local held = { }
for index , owner in ipairs ( roots ) do
held [ index ] = owner
owner . activeBorrows = ( owner . activeBorrows or 0 ) + 1
owner . activeBorrowSites = owner . activeBorrowSites or { }
owner . activeBorrowSites [ state ] = target
if writtenFacts . exclusive then
owner . activeExclusiveBorrows = ( owner . activeExclusiveBorrows or 0 ) + 1
end
end
if held [ 1 ] then
facts . roots = held
end
if writtenFacts . exclusive then
facts . exclusive = true
end
if regionRoot and regionPath then
facts . regionRoot , facts . regionPath = regionRoot , regionPath
regionRoot . activeRegions = regionRoot . activeRegions or { }
regionRoot . activeRegions [ regionPath ] = ( regionRoot . activeRegions [ regionPath ] or 0 ) + 1
if writtenFacts . exclusive then
regionRoot . activeExclusiveRegions = regionRoot . activeExclusiveRegions or { }
regionRoot . activeExclusiveRegions [ regionPath ] = ( regionRoot . activeExclusiveRegions [ regionPath ] or 0 ) + 1
end
end
end






local function recordWrite ( functionBody , rootEntry , suffix ) 
if suffix == "" then
return
end
if rootEntry . mutationSelf then
functionBody . mutatesSelf = true
functionBody . mutatesSelfPaths = functionBody . mutatesSelfPaths or { }
functionBody . mutatesSelfPaths [ suffix ] = true
elseif rootEntry . mutationParameter then
functionBody . mutatesParams = functionBody . mutatesParams or { }
functionBody . mutatesParams [ rootEntry . mutationParameter ] = true
functionBody . mutatesParamPaths = functionBody . mutatesParamPaths or { }
local paths = functionBody . mutatesParamPaths [ rootEntry . mutationParameter ] or { }
functionBody . mutatesParamPaths [ rootEntry . mutationParameter ] = paths
paths [ suffix ] = true
end
end

handlers . assignStmt = function ( stat ) 
local values = stat . exprs or { }
local valueCount = # values




if # stat . targets == valueCount then
for index , target in ipairs ( stat . targets ) do
local value = values [ index ]
if value and ( value . kind == "call" or value . kind == "safeCall" ) then







value . expectedResult = c . refType ( target )
elseif value
and ( value . kind == "funcExpr" or value . kind == "shortfn" )
and target . kind == "dotIndex"
and target . name
then






local receiver = c . refType ( target . obj )
local bare = receiver and rawType ( receiver ) or nil
if not ( bare and ( bare . tag == "metatable" or bare . tag == "typeobject" ) ) then
local key = target . obj and pathKey ( target . obj ) or nil
local named = key and c . lookupType ( key ) or nil
bare = named and named . tag == "nominal" and named or nil
end
local contract = bare and c . metamethodOf ( bare , target . name . text ) or nil
if contract and rawType ( contract ) . tag == "func" then
value . expectedCallable = contract
end
end
end
end
local inferred = inferList ( stat . exprs , # stat . targets )
for _ , target in ipairs ( stat . targets ) do
local key = pathKey ( target )
if key then
local root = key : match ( "^[^.]+" )
local rootEntry = root and c . lookupEntry ( root ) or nil
local functionBody = c . functionBodies [ # c . functionBodies ]
if root and rootEntry and functionBody then
if ( rootEntry . functionDepth or 0 ) < c . functionDepth then
local suffix = key : sub ( # root + 1 )
if suffix == "" then
functionBody . mutatesCapturedEntries = functionBody . mutatesCapturedEntries or { }
functionBody . mutatesCapturedEntries [ rootEntry ] = true
else
functionBody . mutatesCapturedPaths = functionBody . mutatesCapturedPaths or { }
local paths = functionBody . mutatesCapturedPaths [ rootEntry ] or { }
functionBody . mutatesCapturedPaths [ rootEntry ] = paths
paths [ suffix ] = true
end
else
recordWrite ( functionBody , rootEntry , key : sub ( # root + 1 ) )
end
end
if key : find ( "." , 1 , true ) then

facts . clearWrite ( key )
else
clearNarrowed ( key )
end
clearAliases ( key )
else


local base = target
while base and ( base . kind == "paren" or base . kind == "castExpr" ) do
base = base . expr
end
if base and ( base . kind == "bracketIndex" or base . kind == "safeBracket" ) then
local baseKey = base . obj and pathKey ( base . obj ) or nil
local index = base . expr
local shape , literal = mutation . indexShape ( index )
local indexT = index and index . inferredType and rawType ( index . inferredType ) or nil
if indexT and isA ( indexT , T . integer ) then


shape = "integer"
end
local written = nil
if baseKey and shape == "field" and literal then
written = baseKey .. "." .. literal
facts . clearWrite ( written )
clearAliases ( written )
elseif baseKey and shape ~= "integer" then
written = baseKey .. "*"
facts . clearWrite ( baseKey , true )
facts . clearAliasesBelow ( baseKey )
end
local root = written and written : match ( "^[^.*]+" ) or nil
local rootEntry = root and c . lookupEntry ( root ) or nil
local functionBody = c . functionBodies [ # c . functionBodies ]
if written
and root
and rootEntry
and functionBody
and ( rootEntry . functionDepth or 0 ) >= c . functionDepth
then
recordWrite ( functionBody , rootEntry , written : sub ( # root + 1 ) )
end
end
end
end
for j , target in ipairs ( stat . targets ) do
local et = inferred [ j ]
local written = values [ j ] or valueCount > 0 and j >= valueCount and values [ valueCount ] or nil
local fixedResultIndex = written and j >= valueCount and j - valueCount + 1 or nil
if written and fixedResultIndex then
written . fixedWidthResultIndex = fixedResultIndex
end
local wasConstModuleField = constModuleField ( target )
if wasConstModuleField then
c . diag ( "NUPP2008" , target , "cannot assign to const module field" )
end

if written and ownershipKind ( et ) == "affine" then
c . markTemporaryConsumed ( written )
end
recordModuleField ( target , et , stat . isConst , written )
local targetTok = target . kind == "name" and target . token or nil
if targetTok then
local targetName = targetTok . text
local entry = c . lookupEntry ( targetName )
local entryState = ownershipState ( entry )
local entryWasMoved = entryState and entryState . moved or false
c . markToken (
targetTok ,
entry and entry . definition ,
entry and entry . t or T . any ,
entry and entry . definition and entry . definition . kind or "variable"
)



if entry then
if c . opts . compat == "lua51" then
entry . runtimeSurfaceRoot = require ( "nupp.compiler.runtimesurface" ) . identity ( written )
or entry . runtimeSurfaceRoot
end
if entry . definition then
if entry . definition . initialized then
entry . definition . reassigned = true
else
entry . definition . initialized = true
end
end
local oldGroup = entry . packCorrelation
local oldIndex = entry . packCorrelationIndex
if oldGroup and oldIndex and oldGroup . names [ oldIndex ] == targetName then
oldGroup . names [ oldIndex ] = nil
end
entry . unassigned = nil
entry . packCorrelation = nil
entry . packCorrelationIndex = nil
if et and et . tag == "protocolThread" then
if written and written . coroutineIntrinsic == "create" then
entry . threadPhase = "new"
elseif written and written . kind == "name" and written . token then
local source = c . lookupEntry ( written . token . text )
entry . threadPhase = source and source . threadPhase or "unknown"
if source and source ~= entry then
source . threadPhase = "unknown"
end
else
entry . threadPhase = "unknown"
end
else
entry . threadPhase = nil
end
if written and written . wrappedProtocol then
entry . wrappedProtocol = written . wrappedProtocol
entry . wrappedPhase = "new"
elseif et and et . tag ~= "func" then
entry . wrappedProtocol , entry . wrappedPhase = nil , nil
end
end
if entry and entry . constant then
c . diag ( "NUPP2008" , target , ("cannot assign to const variable %s") : format ( targetName ) )
elseif entry and entry . ann and et then
local declared = entry . decl or entry . t
if written then
written . fixedWidthTargetTypeNode = entry . annotationNode
end
local ok , why , reported = c . fixedWidth . fits ( et , declared , written or stat )
if ok and relations . typevarMismatch ( et , declared ) then
ok = false
why = ("%s is not a value of the generic type %s") : format ( T . tostring ( et ) , T . tostring ( declared ) )
end
if not ok and not reported then
c . diag ( "NUPP2001" , written or stat , ("cannot assign to %s: %s") : format ( targetName , why ) )
end
c . checkMetatableLiteral ( written , et , declared )
end
if entryState and ( entryState . activeBorrows or 0 ) > 0 then
c . diag (
"NUPP2602" ,
target ,
("%q cannot be assigned while a derived borrow is live") : format ( targetName )
)
end



local fillsEmptySlot = false
if entry and entryState and ownershipKind ( entry . t ) == "affine" then
if et == T . nil_ then
if not entryState . moved and not entryState . emptySlot then
c . diag (
"NUPP2602" ,
target ,
("assignment overwrites live affine value %q") : format ( targetName )
)
end
entryState . emptySlot = true
elseif entryState . emptySlot and ownershipKind ( et ) == "affine" then
entryState . emptySlot = nil
entryState . moved = true
fillsEmptySlot = true
end
end
if entry and et and ( ownershipKind ( et ) == "affine" or ownershipKind ( et ) == "pinned" ) then

local incomingKind = ownershipKind ( et )
if entry . ann and ownershipKind ( entry . t ) ~= incomingKind then
local declared = entry . decl or entry . t
c . diag (
declared == T . any and "NUPP2611" or "NUPP2603" ,
written or stat ,
declared == T . any and "a live capability cannot be erased into any"
or incomingKind .. " assignment needs a matching destination"
)
end
if entry . ownership == incomingKind and not entryState . moved then
c . diag ( "NUPP2602" , target , ("assignment overwrites live affine value %q") : format ( targetName ) )
end
if written then
moveExpression ( written , et , "assignment" , incomingKind )
if entryWasMoved and entry . automaticOwner then
written . automaticOwnerReinit = { owner = entry . automaticOwner }
end
end
entry . t , entry . ownership = et , incomingKind
entryState . t , entryState . ownership , entryState . moved = et , incomingKind , false
if written then
holdProvenance ( entryState , target , written )
end
elseif et and ownershipKind ( et ) == "borrowed" and written then
c . diag ( "NUPP2608" , written , "borrowed value cannot escape through assignment" )
end
if entry then
c . fixedWidth . setBinding ( entry , written , fixedResultIndex )
end


if fillsEmptySlot and written and entry . automaticOwner then
entry . automaticOwner . moved = true
written . automaticOwnerReinit = { owner = entry . automaticOwner }
end
elseif not wasConstModuleField then
target . writeContext = true


target . assignmentTarget = true
local tt = c . infer ( target )
target . writeContext = nil
local contractWrite = false
if target . usesIndexContract and et and not target . indexedAccess then
local receiver = target . indexObjectType
local keyType = target . indexKeyType
local mm = receiver and metamethodOf ( receiver , "__newindex" ) or nil
if mm then
local receiverNode = target . kind == "bracketIndex" and target . obj or target
local keyNode = target . kind == "bracketIndex" and target . expr or target
applyContract (
mm ,
{ receiver , keyType , et } ,
{ receiverNode , keyNode or target , written } ,
target ,
"__newindex"
)
contractWrite = true
end
end
local partialReinit = false
if target . kind == "dotIndex" and target . obj and target . obj . kind == "name" and target . name then
local container = ownershipState ( ( c . ownershipEntry ( target . obj ) ) )
local field = target . name . text
local constructor = c . constructorFieldStack [ # c . constructorFieldStack ]
local constructorInit = target . obj . token
and target . obj . token . text == "self"
and constructor
and not constructor . assigned [ field ]
if constructorInit then
constructor . assigned [ field ] = true
if et and ownershipKind ( et ) then
moveExpression ( written , et , "constructor field initialization" , ownershipKind ( et ) )
partialReinit = true
end
elseif et == T . nil_
and tt
and ownershipKind ( tt ) == "affine"
and container
and ( container . movedFields and container . movedFields [ field ] )
and not ( container . conditionalMovedFields and container . conditionalMovedFields [ field ] )
then





container . movedFields [ field ] = nil
if container . movedFieldTypes then
container . movedFieldTypes [ field ] = nil
end
partialReinit = true
elseif et
and ownershipKind ( et ) == "affine"
and tt
and ownershipKind ( tt ) == "affine"
and container
then
if not ( container . movedFields and container . movedFields [ field ] ) then
c . diag ( "NUPP2602" , target , ("assignment overwrites live affine field %q") : format ( field ) )
elseif container . conditionalMovedFields and container . conditionalMovedFields [ field ] then
c . diag (
"NUPP2602" ,
target ,
("assignment may overwrite owned field %q, which is still live on some paths")

: format ( field )
)
else
local prior = container . movedFieldTypes and container . movedFieldTypes [ field ]
if prior and prior . id ~= et . id then
c . diag (
"NUPP2602" ,
written or stat ,
"reinitialized field must keep its exact cleanup contract"
)
end
moveExpression ( written , et , "affine field reinitialization" , "affine" )
if written and container . automaticOwner then
written . automaticOwnerReinit = { owner = container . automaticOwner , field = field , }
end
container . movedFields [ field ] = nil
container . movedFieldTypes [ field ] = et
partialReinit = true
end
end
end
local taskAggregateWrite = false
if et and ownershipKind ( et ) == "borrowed" and target . kind == "bracketIndex" and written then
local valueRoots = c . own . provenanceOwners ( written )
local containerRoots = c . own . provenanceOwners ( target . obj )
if # valueRoots > 0 and # valueRoots == # containerRoots then
taskAggregateWrite = true
for _ , root in ipairs ( valueRoots ) do
local matched = false
local state = c . ownershipState ( root )
local rootType = state and rawType ( state . t ) or nil
local origin = rootType
and rootType . tag == "nominal"
and ( ( rootType . origin or rootType ) )
or nil
if not origin
or ( origin . moduleName or origin . sealedModule ) ~= "nupp.tasks"
or origin . name ~= "Scope"
then
taskAggregateWrite = false
do break end
end
for _ , containerRoot in ipairs ( containerRoots ) do
matched = matched or c . borrowRoot ( containerRoot ) == c . borrowRoot ( root )
end
if not matched then
taskAggregateWrite = false
do break end
end
end
end
end



local rawTarget = tt and rawType ( tt ) or nil
local aggregateCopy = ownershipKind ( et ) == "borrowed"
and target . fixedWidthPhysicalStore == true
and rawTarget ~= nil
and ( rawTarget . tag == "carray" or rawTarget . tag == "nominal" and rawTarget . declKind == "struct" )
if et and ownershipKind ( et ) and not partialReinit and not taskAggregateWrite and not aggregateCopy then
c . diag (
"NUPP2603" ,
written or stat ,
( ownershipKind ( et ) ) .. " value cannot be stored through a reference"
)
end




local removing = et == T . nil_
and target . kind == "bracketIndex"
and ( target . containerTag == "array" or target . containerTag == "map" or target . containerIsSequence )
if et and tt and target . metamethodName then



c . checkMetamethodValue ( written or stat , target . metamethodName , et , tt , target . metamethodReceiver )
elseif et and tt and tt ~= T . any and not removing and not contractWrite then
local ok , why , reported = c . fixedWidth . fits (
et ,
tt ,
written or stat ,
target . fixedWidthPhysicalStore == true and "store" or false
)
if ok and relations . typevarMismatch ( et , tt ) then
ok = false
why = ("%s is not a value of the generic type %s") : format ( T . tostring ( et ) , T . tostring ( tt ) )
end
if not ok and not reported then
c . diag ( "NUPP2001" , written or stat , ("cannot assign: %s") : format ( why ) )
end
c . checkMetatableLiteral ( written , et , tt )
end
end
end



for j , target in ipairs ( stat . targets ) do
local key = pathKey ( target )
local et = inferred [ j ]
if target . postWriteType == false then
et = nil
elseif target . postWriteType then
et = target . postWriteType
end
local rawWritten = et and target . pointerStoreType and narrowing . subtract ( rawType ( et ) , T . nil_ ) or nil
if rawWritten and rawWritten . tag == "nominal" and rawWritten . declKind == "struct" then


et = rawWritten == rawType ( et ) and target . pointerStoreType or T . optional ( target . pointerStoreType )
end
if key and et and et ~= T . any then
local declared = c . lookupEntry ( key ) ~= nil
applyFacts ( { [ key ] = et } )


local made = not declared and target . kind == "name" and c . scope . vars [ key ] or nil
if made then
made . assignedAt = ( target ) . token
end
end
end
local exprCount = # ( values or { } )
local expanded = exprCount > 0 and values [ exprCount ] or nil
local correlated = expanded and expanded . valuePack
if correlated and correlated . alternatives then
local group = { pack = correlated , names = { } }
for j = exprCount , # stat . targets do
local target = stat . targets [ j ]
local tok = target . kind == "name" and target . token or nil
local entry = tok and c . lookupEntry ( tok . text ) or nil
if entry and tok then
local index = j - exprCount + 1
entry . packCorrelation = group
entry . packCorrelationIndex = index
group . names [ index ] = tok . text
end
end
end
end





handlers . compoundAssign = function ( stat ) 
local assignTarget , value , opTok = stat . target , stat . value , stat . op
if not assignTarget or not value or not opTok then
return
end
local targetT = c . infer ( assignTarget )
if constModuleField ( assignTarget ) then
c . diag ( "NUPP2008" , assignTarget , "cannot assign to const module field" )
return
end
assignTarget . writeContext = true
local writeT = c . infer ( assignTarget )
assignTarget . writeContext = nil
local valueT = c . infer ( value )
local targetTok = assignTarget . kind == "name" and assignTarget . token or nil
if targetTok then
local targetName = targetTok . text
local entry = c . lookupEntry ( targetName )
if entry and entry . constant then
c . diag ( "NUPP2008" , assignTarget , ("cannot assign to const variable %s") : format ( targetName ) )
return
end
end
local op = opTok . kind : sub ( 1 , -2 )
if op == "&" or op == "|" or op == "~" or op == "<<" or op == ">>" or op == "~>>" then
require ( "nupp.compiler.capabilities" ) . require ( c , "bitops" , opTok )
end
local operandsFit = true
if op == "??" then
if targetTok then
local entry = c . lookupEntry ( targetTok . text )
if entry and entry . ann then
local ok , why = isA ( valueT , entry . decl or entry . t )
if not ok then
c . diag ( "NUPP2001" , value , ("cannot assign: %s") : format ( why ) )
end
end
end
elseif op == ".." then


local function concatenable ( t , at ) 
if t == T . any or isA ( t , T . number ) or isA ( t , T . string ) then
return
end
c . diag ( "NUPP2003" , at , ("cannot concatenate %s") : format ( T . tostring ( t ) ) )
end

concatenable ( targetT , assignTarget )
concatenable ( valueT , value )
else
local targetFits = c . numericOperand ( targetT , assignTarget , op )
local valueFits = c . numericOperand ( valueT , value , op )
operandsFit = targetFits and valueFits
end



local resultT = T . number
if op == ".." then
resultT = T . string
elseif op == "??" then
resultT = valueT
elseif op == "&" or op == "|" or op == "~" or op == "<<" or op == ">>" or op == "~>>" then
resultT = T . integer
elseif not fixedWidth . isValue ( targetT )
and not fixedWidth . isValue ( valueT )
and targetT ~= T . any
and valueT ~= T . any
and isA ( targetT , T . integer )
and isA ( valueT , T . integer )
and op ~= "/"
and op ~= "^"
then
resultT = T . integer
end
if targetTok then
local entry = c . lookupEntry ( targetTok . text )
writeT = entry and ( entry . decl or entry . t ) or targetT
end
if writeT and op ~= "??" and operandsFit then
local ok , why , reported = c . fixedWidth . fits (
resultT ,
writeT ,
stat ,
assignTarget . fixedWidthPhysicalStore == true and "store" or false
)
if not ok and not reported then
c . diag ( "NUPP2001" , stat , ("cannot assign compound result: %s") : format ( why ) )
end
end
end





handlers . callStmt = function ( stat ) 
local called = stat . expr
if not called then
return
end



called . discardingResults = true
local resultT = c . infer ( called )
if c . callMayMutate then
facts . invalidateForCall ( )
c . callMayMutate = false
end




if called . kind == "call" then
local callee , args = called . obj , called . args
local globalAssert = c . env and c . env . globals and c . env . globals . assert
if callee
and callee . kind == "name"
and callee . token
and callee . token . text == "assert"
and globalAssert
and callee . token . definition == globalAssert . definition
and args
and args . kind == "args"
then
local exprs = args . exprs or { }
if exprs [ 1 ] then
applyFacts ( facts . analyzeCond ( exprs [ 1 ] ) . t )
end
end
end




c . discard . statement ( called )
if called . valuePack then
c . checkPackDiscard ( called . valuePack , 1 , called )
return
end
local ignoredOwner = ownershipKind ( resultT ) == "affine"
if called . ffiOutContracts then
for _ , returned in ipairs ( c . lastCallRets or { } ) do
if ownershipKind ( returned ) == "affine" then
ignoredOwner = true
end
end
end
if ignoredOwner then
c . diag ( "NUPP2603" , called , "owned call result is ignored instead of being consumed" )
end
end

return handlers
end

local __nuppExportValue= bindings ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.bindings"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.bindings"]=__nuppExports;return __nuppExports