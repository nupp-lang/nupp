_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);











local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.relations" )
local cst = require ( "nupp.compiler.cst" )
local fixedWidth = require ( "nupp.compiler.fixed_width" )
local state = require ( "nupp.compiler.check.state" )

local isA = relations . isA







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

local handlers = { }

handlers . localStmt = function ( stat )
local initializers = stat . exprs or { }
local annotations = { }
if # stat . names == 1 and stat . types and stat . types [ 1 ] and stat . types [ 1 ] . kind == "tfunc" then
c . raises . checkParams ( stat , ( stat . types [ 1 ] ) . params or { } )
end
for index , typeNode in ipairs ( stat . types or { } ) do
local annotation = c . resolveType ( typeNode )
annotations [ index ] = annotation
c . fixedWidth . storageOnly ( typeNode , annotation , "a local value" )
local initializer = initializers [ index ]
if initializer and initializer . kind == "comptimeExpr" then
initializer . materializationExpected = annotation
end
end
local inferred = inferList ( stat . exprs , # stat . names )
local initializerCount = # initializers
for j , nameTok in ipairs ( stat . names ) do
local ann = annotations [ j ]
local init = inferred [ j ]
if ann and init then
local initializer = initializers [
j
] or initializerCount > 0 and j >= initializerCount and initializers [ initializerCount ] or nil
if initializer and j >= initializerCount then
initializer . fixedWidthResultIndex = j - initializerCount + 1
end
if initializer then
initializer . fixedWidthTargetTypeNode = stat . types [ j ]
end
local ok , why , reported = c . fixedWidth . fits ( init , ann , initializer or stat )
if not ok and not reported then
c . diag ( "NUPP2001" , initializers [ j ] or stat , ( "cannot initialize %s: %s" ) : format ( nameTok . text , why ) )
end


c . checkMetatableLiteral ( initializers [ j ] , init , ann )
if ownershipKind ( init ) and ownershipKind ( init ) ~= ownershipKind ( ann ) then
local code = ann == T . any and "NUPP2611" or "NUPP2603"
c . diag (
code ,
initializers [ j ] or stat ,
ann == T . any and "a live capability cannot be erased into any" or (
ownershipKind ( init )
) .. " value needs a matching ownership annotation"
)
end
end








local bound = ann or init or T . any


if ann and init and ownershipKind ( ann ) == "affine" and ownershipKind ( init ) == "affine" then
bound = init
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
break
end
end
if not hasConst then
bound = T . table_
end
elseif bound == T . nil_ then
bound = T . any
end
end
if (
ownershipKind ( init ) == "affine" or ownershipKind ( init ) == "pinned"
) and stat . exprs and initializers [ j ] then
moveExpression ( initializers [ j ] , init , "local initialization" , ownershipKind ( init ) )
end
if ann and nameTok . text == c . moduleLocal then
c . moduleLocalAnnotated = true
end
c . bindVar ( nameTok . text , bound , ann ~= nil , nameTok , nil , stat . isConst )
local boundEntry = c . scope . vars [ nameTok . text ]
local initNode = initializers [
j
] or initializerCount > 0 and j >= initializerCount and initializers [ initializerCount ] or nil
local fixedResultIndex = initNode and j >= initializerCount and j - initializerCount + 1 or nil
if initNode and fixedResultIndex then
initNode . fixedWidthResultIndex = fixedResultIndex
end
if boundEntry then
boundEntry . annotationNode = stat . types and stat . types [ j ] or nil
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
local returnFacts = expandedCall and j >= exprCount and c . own . capabilityFacts (
expandedCall ,
j - exprCount + 1 ,
false
) or nil
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






if boundEntry and ann and not initNode and not c . declarationFile and ann . tag == "nominal" and (
ann . declKind == "record" or ann . declKind == "struct"
) then
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



local rangeExport = initNode
and initNode . kind == "call"
and initNode . obj
and initNode . obj . exactCallExport
or nil
if boundEntry
and boundEntry . definition
and stat . isConst
and rangeExport
and rangeExport . module == "nupp.span"
and rangeExport . member == "range"
then
local rangeCall = initNode
local args = rangeCall . args and rangeCall . args . kind == "args" and (
rangeCall . args
) . exprs or { }
local spanDefinitions , valid = { } , # args >= 3
for index = 3 , # args do
local argument = args [ index ]
local definition = argument
and argument . kind == "name"
and argument . token
and argument . token . definition
or nil
if not definition or not definition . constant then
valid = false
break
end
spanDefinitions [ definition ] = true
end
if valid then
boundEntry . definition . spanRangeWitness = { spans = spanDefinitions , }
end
end
local scalarIdentity = initNode
and initNode . scalarIntrinsic
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




if boundEntry and initNode and not ann and initNode . kind == "dotIndex" then
boundEntry . aliasNode = initNode
boundEntry . aliasPath = pathKey ( initNode )
end
if boundEntry and initNode and not ann and initNode . kind == "name" and initNode . token then
local sourceEntry = c . lookupEntry ( initNode . token . text )
if sourceEntry and sourceEntry . resourceCapability then



boundEntry . resourceCapability = sourceEntry . resourceCapability
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
elseif boundEntry and initNode then
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
if boundEntry and (
boundKind == "borrowed" or boundKind == "affine"
) and returnRoots and # returnRoots == 1 then
local boundFacts = c . own . capabilityFacts ( boundEntry )
boundFacts . roots = { returnRoots [ 1 ] }
returnRoots [ 1 ] . activeBorrows = ( returnRoots [ 1 ] . activeBorrows or 0 ) + 1
returnRoots [ 1 ] . activeBorrowSites = returnRoots [ 1 ] . activeBorrowSites or { }
returnRoots [ 1 ] . activeBorrowSites [ boundEntry ] = nameTok
if returnExclusiveBorrow then
boundFacts . exclusive = true
returnRoots [ 1 ] . activeExclusiveBorrows = ( returnRoots [ 1 ] . activeExclusiveBorrows or 0 ) + 1
end
elseif boundEntry and (
boundKind == "borrowed" or boundKind == "affine"
) and initNode and c . own . capabilityFacts (
initNode ,
nil ,
false
) . roots and # c . own . capabilityFacts ( initNode , nil , false ) . roots == 1 then
local owner = c . own . capabilityFacts ( initNode , nil , false ) . roots [ 1 ]
local boundFacts = c . own . capabilityFacts ( boundEntry )
boundFacts . roots = { owner }
owner . activeBorrows = ( owner . activeBorrows or 0 ) + 1
owner . activeBorrowSites = owner . activeBorrowSites or { }
owner . activeBorrowSites [ boundEntry ] = nameTok
if returnExclusiveBorrow then
boundFacts . exclusive = true
owner . activeExclusiveBorrows = ( owner . activeExclusiveBorrows or 0 ) + 1
end
end
if boundEntry and (
boundKind == "borrowed" or boundKind == "affine"
) and returnRoots and # returnRoots > 1 then
local boundFacts = c . own . capabilityFacts ( boundEntry )
boundFacts . roots = returnRoots
for _ , owner in ipairs ( returnRoots ) do
owner . activeBorrows = ( owner . activeBorrows or 0 ) + 1
owner . activeBorrowSites = owner . activeBorrowSites or { }
owner . activeBorrowSites [ boundEntry ] = nameTok
if returnExclusiveBorrow then
owner . activeExclusiveBorrows = ( owner . activeExclusiveBorrows or 0 ) + 1
end
end
boundFacts . exclusive = returnExclusiveBorrow or nil
elseif boundEntry and (
boundKind == "borrowed" or boundKind == "affine"
) and initNode and c . own . capabilityFacts (
initNode ,
nil ,
false
) . roots and # c . own . capabilityFacts ( initNode , nil , false ) . roots > 1 then
local initRoots = c . own . capabilityFacts ( initNode , nil , false ) . roots
local boundFacts = c . own . capabilityFacts ( boundEntry )
boundFacts . roots = initRoots
for _ , owner in ipairs ( initRoots ) do
owner . activeBorrows = ( owner . activeBorrows or 0 ) + 1
owner . activeBorrowSites = owner . activeBorrowSites or { }
owner . activeBorrowSites [ boundEntry ] = nameTok
if returnExclusiveBorrow then
owner . activeExclusiveBorrows = ( owner . activeExclusiveBorrows or 0 ) + 1
end
end
boundFacts . exclusive = returnExclusiveBorrow or nil
end
local boundFacts = boundEntry and c . own . capabilityFacts ( boundEntry , nil , false ) or nil
if boundFacts and boundFacts . regionRoot and boundFacts . regionPath and boundFacts . exclusive then
local root , path = boundFacts . regionRoot , boundFacts . regionPath
root . activeExclusiveRegions = root . activeExclusiveRegions or { }
root . activeExclusiveRegions [ path ] = ( root . activeExclusiveRegions [ path ] or 0 ) + 1
end


if boundEntry then
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
break
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
break
end
activation [ # activation + 1 ] = tests
end
end
local nameIndex = exprCount + resultIndex - 1
local entry = nameIndex >= 1 and c . lookupEntry ( stat . names [ nameIndex ] . text ) or nil
if compatible and ownedType and entry and not entry . automaticOwner and # (
ownedType . cleanups or { }
) > 0 then
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

handlers . assignStmt = function ( stat )
local values = stat . exprs or { }
local valueCount = # values
local inferred = inferList ( stat . exprs , # stat . targets )
for _ , target in ipairs ( stat . targets ) do
local key = pathKey ( target )
if key then
clearNarrowed ( key )
clearAliases ( key )
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
c . diag ( "NUPP2008" , target , ( "cannot assign to const variable %s" ) : format ( targetName ) )
elseif entry and entry . ann and et then
local declared = entry . decl or entry . t
if written then
written . fixedWidthTargetTypeNode = entry . annotationNode
end
local ok , why , reported = c . fixedWidth . fits ( et , declared , written or stat )
if not ok and not reported then
c . diag ( "NUPP2001" , written or stat , ( "cannot assign to %s: %s" ) : format ( targetName , why ) )
end
c . checkMetatableLiteral ( written , et , declared )
end
if entryState and ( entryState . activeBorrows or 0 ) > 0 then
c . diag (
"NUPP2602" ,
target ,
( "%q cannot be assigned while a derived borrow is live" ) : format ( targetName )
)
end
if entry and et and ( ownershipKind ( et ) == "affine" or ownershipKind ( et ) == "pinned" ) then

local incomingKind = ownershipKind ( et )
if entry . ann and ownershipKind ( entry . t ) ~= incomingKind then
local declared = entry . decl or entry . t
c . diag (
declared == T . any and "NUPP2611" or "NUPP2603" ,
written or stat ,
declared == T . any
and "a live capability cannot be erased into any"
or incomingKind
.. " assignment needs a matching destination"
)
end
if entry . ownership == incomingKind and not entryState . moved then
c . diag ( "NUPP2602" , target , ( "assignment overwrites live affine value %q" ) : format ( targetName ) )
end
if written then
moveExpression ( written , et , "assignment" , incomingKind )
if entryWasMoved and entry . automaticOwner then
written . automaticOwnerReinit = { owner = entry . automaticOwner }
end
end
entry . t , entry . ownership = et , incomingKind
entryState . t , entryState . ownership , entryState . moved = et , incomingKind , false
elseif et and ownershipKind ( et ) == "borrowed" and written then
c . diag ( "NUPP2608" , written , "borrowed value cannot escape through assignment" )
end
if entry then
c . fixedWidth . setBinding ( entry , written , fixedResultIndex )
end
elseif not wasConstModuleField then
target . writeContext = true
local tt = c . infer ( target )
target . writeContext = nil
local contractWrite = false
if target . usesIndexContract and et then
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
if et and ownershipKind ( et ) == "affine" and tt and ownershipKind ( tt ) == "affine" and container then
if not ( container . movedFields and container . movedFields [ field ] ) then
c . diag ( "NUPP2602" , target , ( "assignment overwrites live affine field %q" ) : format ( field ) )
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
if et and ownershipKind ( et ) and not partialReinit then
c . diag (
"NUPP2603" ,
written or stat ,
( ownershipKind ( et ) ) .. " value cannot be stored through a reference"
)
end




local removing = et == T . nil_ and target . kind == "bracketIndex" and (
target . containerTag == "array" or target . containerTag == "map" or target . containerIsSequence
)
if et and tt and target . metamethodName then



c . checkMetamethodValue ( written or stat , target . metamethodName , et , tt , target . metamethodReceiver )
elseif et and tt and tt ~= T . any and not removing and not contractWrite then
local ok , why , reported = c . fixedWidth . fits (
et ,
tt ,
written or stat ,
target . fixedWidthPhysicalStore == true
)
if not ok and not reported then
c . diag ( "NUPP2001" , written or stat , ( "cannot assign: %s" ) : format ( why ) )
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
if key and et and et ~= T . any then
applyFacts ( { [ key ] = et } )
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
c . diag ( "NUPP2008" , assignTarget , ( "cannot assign to const variable %s" ) : format ( targetName ) )
return
end
end
local op = opTok . kind : sub ( 1 , - 2 )
local operandsFit = true
if op == "??" then
if targetTok then
local entry = c . lookupEntry ( targetTok . text )
if entry and entry . ann then
local ok , why = isA ( valueT , entry . decl or entry . t )
if not ok then
c . diag ( "NUPP2001" , value , ( "cannot assign: %s" ) : format ( why ) )
end
end
end
elseif op == ".." then


local function concatenable ( t , at )
if t == T . any or isA ( t , T . number ) or isA ( t , T . string ) then
return
end
c . diag ( "NUPP2003" , at , ( "cannot concatenate %s" ) : format ( T . tostring ( t ) ) )
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
elseif not fixedWidth . isValue (
targetT
) and not fixedWidth . isValue (
valueT
) and targetT ~= T . any and valueT ~= T . any and isA (
targetT ,
T . integer
) and isA ( valueT , T . integer ) and op ~= "/" and op ~= "^" then
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
assignTarget . fixedWidthPhysicalStore == true
)
if not ok and not reported then
c . diag ( "NUPP2001" , stat , ( "cannot assign compound result: %s" ) : format ( why ) )
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

return bindings
