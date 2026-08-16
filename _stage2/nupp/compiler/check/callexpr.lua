_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);












local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.relations" )
local generics = require ( "nupp.compiler.generics" )
local lexer = require ( "nupp.compiler.lexer" )
local cst = require ( "nupp.compiler.cst" )
local ffiMod = require ( "nupp.compiler.check.ffi" )
local methodslots = require ( "nupp.compiler.methodslots" )
local native = require ( "nupp.compiler.native" )
local luaFormat = require ( "nupp.compiler.LuaFormat" )
local reflection = require ( "nupp.compiler.reflection" )
local targetLayout = require ( "nupp.compiler.target_layout" )
local fixedWidth = require ( "nupp.compiler.fixed_width" )
local state = require ( "nupp.compiler.check.state" )
local pegTyping = require (
"nupp.compiler.materialize.peg"
)

local isA = relations . isA
local packIsA = relations . packIsA
local rawType = T . unwrapOwnership
local dropSelf = generics . dropSelf
local specializeSelf = generics . specializeSelf
local specializeReceiver = generics . specializeReceiver

local callexpr = { }







local function ownershipIntrinsic ( c , callee )
local name , qualified = cst . ownershipIntrinsicSpelling ( callee )
if not name then
return nil
end
if not qualified then
return not c . lookupEntry ( name ) and name or nil
end
local globals = c . env and c . env . globals

return globals and c . lookupEntry ( "nupp" ) == globals [ "nupp" ] and name or nil
end


local LOG_SEVERITY = { error = 1 , warn = 2 , info = 3 , debug = 4 }







local function logIntrinsic ( c , callee )
if not callee or callee . kind ~= "dotIndex" or not callee . name then
return nil
end
local severity = LOG_SEVERITY [ callee . name . text ]
if not severity then
return nil
end
local path = callee . obj
if not path or path . kind ~= "dotIndex" or not path . name or path . name . text ~= "log" then
return nil
end
local root = path . obj
local token = root and root . kind == "name" and root . token or nil
if not token or token . text ~= "nupp" then
return nil
end
local global = c . env and c . env . globals and c . env . globals . nupp
local resolved = c . lookupEntry ( token . text )

return global and resolved and resolved . definition == global . definition and severity or nil
end



local function stringFormatIntrinsic ( c , callee )
if not callee or callee . kind ~= "dotIndex" or not callee . name or callee . name . text ~= "format" then
return false
end
local base = callee . obj
local token = base and base . kind == "name" and base . token or nil
local global = c . env and c . env . globals and c . env . globals . string
local resolved = token and c . lookupEntry ( token . text ) or nil

return token ~= nil
and token . text == "string"
and global ~= nil
and resolved ~= nil
and resolved . definition == global . definition
end

local function debugFormatPlan ( format )
local parsed = luaFormat . analyze ( format )
for _ , debug in ipairs ( parsed and parsed . debugArguments or { } ) do
if debug then
return parsed
end
end

return nil
end










local function zoneIntrinsic ( c , callee )
if not callee or callee . kind ~= "dotIndex" or not callee . name then
return nil
end
local name = callee . name . text
if name ~= "push" and name ~= "pop" then
return nil
end
local base = callee . obj
if not base or base . kind ~= "name" or not base . token then
return nil
end
local baseType = c . lookupVar ( base . token . text )
if not baseType then
return nil
end
local zoneType = c . env and c . env . resolveModule and c . env . resolveModule ( c . env , "nupp.zone" )
if not zoneType then
return nil
end
local owner = rawType ( baseType )
if owner . tag == "nominal" then
owner = owner . origin or owner
end

return owner == zoneType and name or nil
end














function callexpr . install ( c )
local inferFfiIntrinsic = ffiMod . install ( c )

local handlers = { }

local lpegEmpty = T . array ( T . never )
local lpegUnknown = T . array ( T . any )

local function lpegPatternOrigin ( callee )
if not callee or callee . kind ~= "dotIndex" or not callee . obj then
return nil
end
local owner = rawType ( c . infer ( callee . obj ) )
if owner . tag == "metatable" or owner . tag == "typeobject" then
owner = rawType ( owner . of )
end
if owner . tag ~= "nominal" or not owner . lpegLibrary then
return nil
end
local pattern = owner . lpegPatternOrigin
if pattern and pattern . tag == "nominal" and pattern . lpegPattern then
return pattern
end

return nil
end

local function lpegCapturesFromPack ( pack , skip )
local evaluated = generics . evaluatePack ( pack , c . reductionControl )
if evaluated . error or evaluated . pack . alternatives then
return lpegUnknown
end
local concrete , why = generics . expandComputedPack ( evaluated . pack , c . reductionControl )
if why then
return lpegUnknown
end
local values = { }
for index = ( skip or 0 ) + 1 , # concrete . head do
values [ # values + 1 ] = concrete . head [ index ]
end
if concrete . tail then
if # values == 0 and concrete . tail . kind == "homogeneous" then
return T . array ( concrete . tail . type )
end
return lpegUnknown
end

return # values == 0 and lpegEmpty or T . tuple ( values )
end

local function lpegPattern ( origin , captures )
local parameter = origin . typeParams and origin . typeParams [ 1 ]
return parameter and generics . instantiate ( origin , { [ parameter ] = captures } ) or origin
end

local function specializeLpegCall ( callee , memberName , argumentPack )
local origin = lpegPatternOrigin ( callee )
if not origin or not argumentPack then
return nil
end
if memberName == "Cc" then
return lpegPattern ( origin , lpegCapturesFromPack ( argumentPack ) )
elseif memberName == "Cmt" then
local callback = T . packAt ( argumentPack , 2 )
if callback and callback . tag == "func" then
return lpegPattern ( origin , lpegCapturesFromPack ( callback . retPack , 1 ) )
end
elseif memberName == "P" then
local callback = T . packAt ( argumentPack , 1 )
if callback and callback . tag == "func" then
return lpegPattern ( origin , lpegCapturesFromPack ( callback . retPack , 1 ) )
elseif callback and callback . tag == "nominal" and (
( callback . origin or callback )
) . lpegPattern then
return callback
elseif callback and ( isA ( callback , T . string ) or isA ( callback , T . number ) or isA ( callback , T . boolean ) ) then
return lpegPattern ( origin , lpegEmpty )
end
end

return nil
end

local function literalToken ( token )
if not token then
return nil
end
local chunk = loadstring ( "return " .. token . text )
if not chunk then
return nil
end
local ok , value = pcall ( chunk )

return ok and type ( value ) == "string" and value or nil
end

local function literalString ( expr )
local token = expr and expr . kind == "string" and expr . token or nil

return literalToken ( token )
end

local function readableField ( t , name )
if not t then
return nil
elseif t . tag == "literal" then
return readableField ( t . base , name )
elseif t . tag == "shape" or t . tag == "nominal" then
return t . byname and t . byname [ name ] or nil
elseif t . tag == "union" then
local members = { }
for _ , member in ipairs ( t . members ) do
if member ~= T . nil_ then
local field = readableField ( member , name )
if field then
members [ # members + 1 ] = field
end
end
end

return # members > 0 and T . union ( members ) or nil
end

return nil
end

local function pegCompilePath ( callee )
if not callee or callee . kind ~= "dotIndex" or not callee . name or callee . name . text ~= "compile" then
return false
end
local pegPath = callee . obj
if not pegPath or pegPath . kind ~= "dotIndex" or not pegPath . name or pegPath . name . text ~= "peg" then
return false
end
local root = pegPath . obj
local token = root and root . kind == "name" and root . token or nil
local global = c . env and c . env . globals and c . env . globals . nupp
local resolved = token and c . lookupEntry ( token . text ) or nil

return token ~= nil
and token . text == "nupp"
and global ~= nil
and resolved ~= nil
and resolved . definition == global . definition
end

local function pegMatcher ( result )
local pegTypes = c . env and c . env . globalTypes and c . env . globalTypes [ "nupp.peg" ]
local matcher = pegTypes and pegTypes . nestedTypes and pegTypes . nestedTypes . Peg
local binder = matcher and matcher . packParams and matcher . packParams [ 1 ]

return matcher and binder and generics . instantiate ( matcher , { [ binder ] = result } ) or nil
end





local function pegReplacementMember ( receiver , name , replacement )
if ( name ~= "replace" and name ~= "replaceAll" ) or not replacement then
return nil
end
local pegTypes = c . env and c . env . globalTypes and c . env . globalTypes [ "nupp.peg" ]
local matcher = pegTypes and pegTypes . nestedTypes and pegTypes . nestedTypes . Peg
local owner = rawType ( receiver )
if not matcher or owner . tag ~= "nominal" or ( owner . origin or owner ) ~= matcher then
return nil
end

local suffix
local replacementType = rawType ( replacement )
if replacement ~= T . any and replacement ~= T . unknown and isA ( replacement , T . string ) then
suffix = "Literal"
elseif replacementType . tag == "func" then
suffix = "Callback"
else
return nil
end

return "__nuppPegReplace" .. ( name == "replaceAll" and "All" or "" ) .. suffix
end

local function withoutNil ( t )
if t . tag ~= "union" then
return t
end
local nonnil = { }
for _ , member in ipairs ( t . members ) do
if member ~= T . nil_ then
nonnil [ # nonnil + 1 ] = member
end
end

return T . union ( nonnil )
end




local function concreteTypePath ( argument , typePosition )
if argument and typePosition then
local key = cst . textOf ( argument ) : gsub ( "%s+" , "" )
return key , c . resolveType ( argument )
end
local key = argument and c . pathKey ( argument ) or nil
local resolved = key and c . lookupType ( key ) or nil
if not resolved and key and not key : find ( "." , 1 , true ) then
local builtin = ( T ) [ key ]
if type ( builtin ) == "table" and builtin . tag then
resolved = builtin
end
end
if not resolved and key and c . env and c . env . resolveQualifiedType then
local moduleName , typeName = key : match ( "^(.*)%.([^.]+)$" )
if moduleName and typeName then
local first = moduleName : match ( "^[^.]+" )
local holder = first and c . lookupEntry ( first ) or nil
if holder and holder . requiredModule then
local firstName = first
moduleName = holder . requiredModule .. moduleName : sub ( # firstName + 1 )
end
resolved = c . env . resolveQualifiedType ( c . env , c . filename , moduleName , typeName )
end
end

return key , resolved
end

handlers . call = function ( node )




local callee = node . obj
local calleeName , baseName , memberName = "" , "" , ""
local typeArg = nil
if callee then
if callee . kind == "name" then
local calleeTok = callee . token
calleeName = calleeTok and calleeTok . text or ""
elseif callee . kind == "dotIndex" then
local memberTok = callee . name
memberName = memberTok and memberTok . text or ""
typeArg = callee . ffiTypeArg
local base = callee . obj
if base and base . kind == "name" then
local baseTok = base . token
baseName = baseTok and baseTok . text or ""
end
end
end
local argsNode = node . args
local argExprs = { }
local argStr = nil
local argTable = nil
local callArgs = argsNode and argsNode . kind == "args" and argsNode or nil
if callArgs then
argExprs = callArgs . exprs or { }
argStr = callArgs . str
argTable = callArgs . table
end
local deriveIntrinsic = callee and cst . textOf ( callee ) : gsub ( "%s+" , "" ) : match ( "^nupp%.derive%.[%w_]+$" )
if deriveIntrinsic and ( c . comptimeFunctionDepth or 0 ) == 0 then
c . diag ( "NUPP2809" , node , "nupp.derive builders are available only inside a comptime provider" )
return T . any
end



if baseName == "jit" and memberName == "off" and not argStr and not argTable then
local globalJit = c . env and c . env . globals and c . env . globals . jit or nil
local resolvedJit = c . lookupEntry ( "jit" )
if globalJit and resolvedJit == globalJit then
local subject = argExprs [ 1 ]
if not subject then
local body = c . functionBodies [ # c . functionBodies ]
if body then
body . jitDisabled = true
end
elseif subject . kind == "name" and subject . token then
local entry = c . lookupEntry ( subject . token . text )
local definition = entry and ( entry . jitTarget or entry . definition ) or nil
if definition then
definition . jitDisabled = true
end
elseif subject . kind == "funcExpr" or subject . kind == "shortfn" then
local body = subject . body or subject
body . jitDisabled = true
elseif subject . kind == "dotIndex" and subject . name and subject . name . definition then
subject . name . definition . jitDisabled = true
end
end
end
local comptimeIntrinsic , intrinsicQualified = cst . comptimeTypeIntrinsicSpelling ( callee )
local layoutIntrinsic = intrinsicQualified and comptimeIntrinsic ~= "reflect" and comptimeIntrinsic or nil
if layoutIntrinsic and not argStr and not argTable then
if ( c . comptimeDepth or 0 ) == 0 then
c . diag ( "NUPP2419" , node , "nupp." .. layoutIntrinsic .. " is available only inside a comptime block" )
return T . any
end
local globals = c . env and c . env . globals
local stable = globals and c . lookupEntry ( "nupp" ) == globals . nupp
local expected = layoutIntrinsic == "offsetof" and 2 or 1
if not stable or # argExprs ~= expected then
c . diag (
"NUPP2419" ,
node ,
( "nupp.%s expects %d argument%s" ) : format ( layoutIntrinsic , expected , expected == 1 and "" or "s" )
)
return T . any
end
local typeArgument = callArgs and callArgs . typeArg or argExprs [ 1 ]
local key , subject = concreteTypePath ( typeArgument , callArgs and callArgs . typeArg ~= nil )
if not key or not subject then
c . diag (
"NUPP2419" ,
argExprs [ 1 ] or node ,
"nupp." .. layoutIntrinsic .. " expects one concrete type name" ,
nil ,
{ help = "pass a declared or qualified type, not a runtime value" }
)
return T . any
end
local target = c . env and c . env . layoutTarget or nil
if not target then
c . diag ( "NUPP2419" , node , "nupp." .. layoutIntrinsic .. " needs an explicit build layout target" , nil , {
help = "set layoutTarget on the selected build target in nupp.lua"
} )
return T . any
end
local measured , why = targetLayout . of ( subject , target )
if not measured then
c . diag (
"NUPP2419" ,
argExprs [ 1 ] or node ,
( "%s has no layout for %s: %s" ) : format ( key , target , tostring ( why ) )
)
return T . any
end
if layoutIntrinsic == "offsetof" then
local fieldType = argExprs [ 2 ] and c . infer ( argExprs [ 2 ] ) or nil
local fieldName = literalString ( argExprs [ 2 ] )
if not fieldName and fieldType and fieldType . tag == "literal" and type (
fieldType . constant
) == "string" then
fieldName = fieldType . constant
end
if not fieldName then
c . diag (
"NUPP2419" ,
argExprs [ 2 ] or node ,
"nupp.offsetof field name must be a compile-time-known string"
)
return T . any
end
if measured . offsets [ fieldName ] == nil then
c . diag ( "NUPP2419" , argExprs [ 2 ] or node , ( "%s has no field %q" ) : format ( key , fieldName ) )
return T . any
end
end
node . targetLayout , node . targetLayoutKey = measured , key

return T . integer
end
if comptimeIntrinsic == "reflect" and intrinsicQualified and # argExprs == 1 and not argStr and not argTable then
if ( c . comptimeDepth or 0 ) == 0 then
c . diag ( "NUPP2418" , node , "nupp.reflect is available only inside a comptime block" )
return T . any
end
local globals = c . env and c . env . globals
local stable = globals and c . lookupEntry ( "nupp" ) == globals . nupp
local typeArgument = callArgs and callArgs . typeArg or argExprs [ 1 ]
local key , reflected = concreteTypePath ( typeArgument , callArgs and callArgs . typeArg ~= nil )
if not stable or not reflected then
c . diag ( "NUPP2418" , argExprs [ 1 ] or node , "nupp.reflect expects one concrete type name" , nil , {
help = "pass a declared or qualified type, not a runtime value"
} )
return T . any
end
local descriptor = reflection . describe ( reflected , key )
node . reflectedType , node . reflectedTypeKey = descriptor , key
local reflectTypes = c . env and c . env . globalTypes and c . env . globalTypes [ "nupp.reflect" ]
local typeInfo = reflectTypes and reflectTypes . nestedTypes and reflectTypes . nestedTypes . Info

return typeInfo or T . any
end




local severity = logIntrinsic ( c , callee )
if severity and not argTable and not argStr then
local format = argExprs [ 1 ]



local positional = true
for _ , argument in ipairs ( argExprs ) do
if argument . kind == "namedArg" or argument . kind == "pluckArg" then
positional = false
end
end
if positional and format and format . kind == "string" then
node . logIntrinsic = severity
node . logFormatIntrinsic = debugFormatPlan ( literalString ( format ) or "" )
end
end


local zoneOp = zoneIntrinsic ( c , callee )
if zoneOp and not argTable and not argStr then
local positional = true
for _ , argument in ipairs ( argExprs ) do
if argument . kind == "namedArg" or argument . kind == "pluckArg" then
positional = false
end
end
if positional then
if zoneOp == "push" and # argExprs == 1 then
node . zoneIntrinsic = "push"
elseif zoneOp == "pop" and # argExprs == 0 then
node . zoneIntrinsic = "pop"
end
end
end
local intrinsic = node . ownershipSyntax or ownershipIntrinsic ( c , callee )
if intrinsic then
local args = argExprs
if intrinsic == "borrow" then
local valueT = args [ 1 ] and c . infer ( args [ 1 ] ) or T . any
if # args ~= 1 or c . ownershipKind ( valueT ) ~= "affine" then
c . diag ( "NUPP2602" , node , "borrow expects one live owned value" )
end
node . ownershipIntrinsic = "borrow"
c . own . capabilityFacts ( node ) . roots = { c . borrowRoot ( ( c . ownershipEntry ( args [ 1 ] ) ) ) }
return T . borrowed ( rawType ( valueT ) )
elseif intrinsic == "borrowFrom" then
local valueT = args [ 1 ] and c . infer ( args [ 1 ] ) or T . any
if args [ 2 ] then
c . infer ( args [ 2 ] )
end
local source = args [ 2 ] and c . ownershipEntry ( args [ 2 ] ) or nil
if # args ~= 2 or c . ownershipKind ( valueT ) or not c . pointerShaped ( valueT ) or not source then
c . diag ( "NUPP2602" , node , "borrowFrom expects a raw pointer and a named source" )
end
if c . unsafeDepth == 0 then
c . diag ( "NUPP2604" , node , "borrowFrom requires an unsafe do block" )
end
node . ownershipIntrinsic = "borrowFrom"
c . own . capabilityFacts ( node ) . roots = { c . borrowRoot ( source ) }
return T . borrowed ( rawType ( valueT ) )
elseif intrinsic == "partition" then
if args [ 1 ] then
c . infer ( args [ 1 ] )
end
local leftT = args [ 2 ] and c . infer ( args [ 2 ] ) or T . any
local rightT = args [ 3 ] and c . infer ( args [ 3 ] ) or T . any
local parent = args [ 1 ] and c . ownershipEntry ( args [ 1 ] ) or nil
local root , parentPath = args [ 1 ] and c . regionOf ( args [ 1 ] ) or nil , ""
if root then
local _ , foundPath = c . regionOf ( args [ 1 ] )
parentPath = foundPath or ""
end
if # args ~= 3 or not parent then
c . diag ( "NUPP2602" , node , "partition expects a named writable parent and two children" )
end
if c . ownershipKind ( leftT ) or c . ownershipKind ( rightT ) then
c . diag ( "NUPP2602" , node , "partition children must not already carry ownership" )
end
if rawType ( leftT ) . id ~= rawType ( rightT ) . id then
c . diag ( "NUPP2602" , node , "partition children must have the same type" )
end
if c . unsafeDepth == 0 then
c . diag ( "NUPP2604" , node , "partition requires an unsafe do block" )
end
node . ownershipIntrinsic = "partition"
local partitionRoot = root or c . borrowRoot ( parent )
local leftFacts = c . own . capabilityFacts ( node , 1 )
leftFacts . roots = { parent }
leftFacts . exclusive = true
leftFacts . regionRoot = partitionRoot
leftFacts . regionPath = T . regionPartition ( parentPath , "left" )
local rightFacts = c . own . capabilityFacts ( node , 2 )
rightFacts . roots = { parent }
rightFacts . exclusive = true
rightFacts . regionRoot = partitionRoot
rightFacts . regionPath = T . regionPartition ( parentPath , "right" )
local left = T . borrowed ( rawType ( leftT ) )
local right = T . borrowed ( rawType ( rightT ) )
node . valuePack = T . pack ( { left , right } )
c . lastCallRets = { left , right }
return left
elseif intrinsic == "region" then
if args [ 1 ] then
c . infer ( args [ 1 ] )
end
local childT = args [ 2 ] and c . infer ( args [ 2 ] ) or T . any
local parent = args [ 1 ] and c . ownershipEntry ( args [ 1 ] ) or nil
local root , parentPath = args [ 1 ] and c . regionOf ( args [ 1 ] ) or nil , ""
if root then
local _ , foundPath = c . regionOf ( args [ 1 ] )
parentPath = foundPath or ""
end
local firstT = args [ 3 ] and c . infer ( args [ 3 ] ) or nil
local lastT = args [ 4 ] and c . infer ( args [ 4 ] ) or nil
local first = firstT and firstT . tag == "literal" and type (
firstT . constant
) == "number" and firstT . constant % 1 == 0 and firstT . constant or nil
local last = lastT and lastT . tag == "literal" and type (
lastT . constant
) == "number" and lastT . constant % 1 == 0 and lastT . constant or nil
if # args ~= 4 or not parent then
c . diag ( "NUPP2602" , node , "region expects a named parent, child, first index, and last index" )
elseif c . ownershipKind ( childT ) then
c . diag ( "NUPP2602" , node , "region child must not already carry ownership" )
elseif first and last and last < first - 1 then
c . diag ( "NUPP2602" , node , "region range ends before it begins" )
end
if c . unsafeDepth == 0 then
c . diag ( "NUPP2604" , node , "region requires an unsafe do block after runtime bounds validation" )
end
node . ownershipIntrinsic = "region"
local regionFacts = c . own . capabilityFacts ( node , 1 )
regionFacts . roots = { parent }
regionFacts . exclusive = true
regionFacts . regionRoot = root or c . borrowRoot ( parent )
regionFacts . regionPath = T . regionRange ( parentPath , first , last )
local child = T . borrowed ( rawType ( childT ) )
node . valuePack = T . pack ( { child } )
c . lastCallRets = { child }
return child
elseif intrinsic == "pin" then
local pointerT = args [ 1 ] and c . infer ( args [ 1 ] ) or T . any
if args [ 2 ] then
c . infer ( args [ 2 ] )
end
if # args ~= 2 or not c . pointerShaped ( pointerT ) then
c . diag ( "NUPP2602" , node , "pin expects a pointer and its managed anchor" )
end
if c . unsafeDepth == 0 then
local pointerRoots = args [ 1 ] and c . own . capabilityFacts ( args [ 1 ] , nil , false ) . roots
local pointerOwner = pointerRoots and pointerRoots [ 1 ]
local anchorEntry = args [ 2 ] and c . ownershipEntry ( args [ 2 ] )
if c . ownershipKind ( pointerT ) ~= "borrowed" or not pointerOwner or pointerOwner ~= anchorEntry then
c . diag (
"NUPP2604" ,
node ,
"pin must prove the pointer derives from its anchor; "
.. "use unsafe do for an opaque derivation"
)
end
end
node . ownershipIntrinsic = "pin"
return T . pinned ( rawType ( pointerT ) )
elseif intrinsic == "attemptAll" then






local valueT = args [ 1 ] and c . infer ( args [ 1 ] ) or T . any
local cleanups = { }
if # args < 2 then
c . diag ( "NUPP2602" , node , "attemptAll expects a value and at least one operation" )
end
for j = 2 , # args do
local operationT = c . infer ( args [ j ] )
local operationNode = args [ j ]
local operationTok = operationNode . kind == "name" and operationNode . token or nil
if not operationTok then
c . diag ( "NUPP2602" , args [ j ] , "attemptAll operations must be function names" )
else
cleanups [ # cleanups + 1 ] = operationTok . text
end
if operationT ~= T . any and (
operationT . tag ~= "func" or not operationT . params [
1
] or not isA ( rawType ( valueT ) , operationT . params [ 1 ] )
) then
c . diag ( "NUPP2602" , args [ j ] , "an attemptAll operation must accept the value" )
end


if operationT ~= T . any
and operationT . tag == "func"
and operationT . paramModes
and operationT . paramModes [
1
] == "takes" and j < # args then
c . diag ( "NUPP2615" , args [ j ] , "only the final attemptAll operation may take the value" )
end
end
c . moveExpression ( args [ 1 ] or node , valueT , "attemptAll" , nil , true )
node . ownershipIntrinsic = "attemptAll"


node . ownerCleanups = c . own . resolveCleanups ( cleanups , node , node )

return T . nil_
elseif intrinsic == "drop" then
local valueT = args [ 1 ] and c . infer ( args [ 1 ] ) or T . any



local dropped = valueT
if # args ~= 1 then
c . diag ( "NUPP2602" , node , "drop expects one owned value" )
end
c . moveExpression ( args [ 1 ] or node , valueT , "drop" , nil , true )
if c . ownershipKind ( valueT ) == "affine" and # ( dropped . cleanups or { } ) == 0 then
c . diag (
"NUPP2602" ,
args [ 1 ] or node ,
"drop needs a named terminal; transfer this owner " .. "to a declared takes parameter"
)
end
node . ownershipIntrinsic = "drop"
node . ownerCleanups = { }
local state = args [ 1 ] and c . ownershipState ( ( c . ownershipEntry ( args [ 1 ] ) ) ) or nil
for _ , cleanup in ipairs ( dropped . cleanups or { } ) do
if not (
cleanup . kind == "field" and state and state . movedFields and state . movedFields [ cleanup . field ]
) then
node . ownerCleanups [ # node . ownerCleanups + 1 ] = cleanup
end
end
return T . nil_
end
end
if calleeName ~= "" then
local entry = c . lookupEntry ( calleeName )
node . cdefCall = entry and entry . definition and entry . definition . cdef or false
node . cdefIdentity = node . cdefCall and entry . definition . cdefIdentity or nil
end



local requireGlobal = c . env and c . env . globals and c . env . globals . require
local requireEntry = calleeName == "require" and c . lookupEntry ( "require" ) or nil
local stableRequire = requireGlobal and requireEntry and requireGlobal . definition == requireEntry . definition
if calleeName == "require" and stableRequire and c . env and c . env . resolveModule then
local tok = nil
if argsNode then
local e1 = argExprs [ 1 ]
if e1 and e1 . kind == "string" then
tok = e1 . token
end
if argStr then
tok = argStr
end
end
if tok then
local text = tok . text
local modname = text : match ( '^"(.*)"$' ) or text : match ( "^'(.*)'$" )
if modname then
node . requiredModule = modname
local effect = native . forModule ( modname )
if effect and c . recordEffect then
( node ) . compilerFeatureEffect = effect
c . recordEffect ( effect )
end
local mt = c . env . resolveModule ( c . env , modname )
if mt then
return mt
end
end
end
return c . opts and c . opts . strict and T . unknown or T . any
end




local intrinsic = inferFfiIntrinsic ( node , calleeName , baseName , memberName , typeArg , argExprs , argStr )
if intrinsic then
return intrinsic
end
if callee and callee . kind == "dotIndex" then
callee . callCallee = true
end
local calleeT = callee and c . infer ( callee ) or T . any
if callee and callee . fixedWidthCallableUntrusted == true then
node . fixedWidthUntrustedResult = true
end
if callee and c . ownershipKind ( calleeT ) == "affine" and rawType ( calleeT ) . tag == "func" then
if node . kind == "safeCall" then
c . diag ( "NUPP2602" , callee , "an affine closure call cannot be conditional; narrow it first" )
else
c . moveExpression ( callee , calleeT , "affine closure call" , "affine" )
if callee . automaticOwnerMove then
node . automaticOwnerMoves = node . automaticOwnerMoves or { }
node . automaticOwnerMoves [ # node . automaticOwnerMoves + 1 ] = callee . automaticOwnerMove
end
end
node . affineClosureCall = true
calleeT = rawType ( calleeT )
elseif c . ownershipKind ( calleeT ) == "borrowed" and rawType ( calleeT ) . tag == "func" then
calleeT = rawType ( calleeT )
end
if calleeT . tag == "func" and calleeT . foreign then
node . cdefCall = true
end
if node . kind == "safeCall" then
calleeT = withoutNil ( calleeT )
end
node . calleeType = rawType ( calleeT )
node . scalarIntrinsic = callee
and callee . scalarIntrinsic
or callee
and callee . kind == "name"
and callee . token
and callee . token . definition
and callee . token . definition . scalarIntrinsic
c . nosuspend . call ( node )










if memberName == "yield" and callee and callee . kind == "dotIndex" then
local base = callee . obj
local baseTok = base and base . kind == "name" and base . token or nil
local coroutineGlobal = c . env and c . env . globals and c . env . globals . coroutine or nil
local resolved = baseTok and c . lookupEntry ( baseTok . text ) or nil



local isCoroutine = false
if resolved ~= nil and resolved . coroutineLibrary == true then

isCoroutine = true
elseif baseTok and coroutineGlobal then
if resolved ~= nil then
isCoroutine = resolved == coroutineGlobal or (
resolved . definition ~= nil and resolved . definition == coroutineGlobal . definition
)
else
isCoroutine = baseTok . text == "coroutine"
end
end
if isCoroutine then
local obligation = c . liveSuspensionObligation ( )
if obligation then
c . diag (
"NUPP2603" ,
node ,
( "cannot suspend while temporal obligation %q is live" ) : format ( obligation ) ,
nil ,
{
help = "suspend inside a `handle suspension` region, where a "
.. "handler is responsible for resuming or cancelling it" ,
}
)
end
end
end







local function bodyOfArgument ( index )
local argument = argExprs [ index ]
if not argument or cst . isToken ( argument ) then
return nil
end
if argument . kind == "funcExpr" or argument . kind == "shortfn" then
return argument . body or argument
end

return nil
end





if node . kind == "call" and callee and callee . kind == "dotIndex" then
local base = callee . obj
local baseTok = base and base . kind == "name" and base . token or nil
local globals = c . env and c . env . globals or { }
local isPrelude = function ( name )
local entry = globals [ name ]

return baseTok ~= nil and entry ~= nil and baseTok . definition == entry . definition
end
if memberName == "sort" and isPrelude ( "table" ) then
c . nosuspend . callback ( bodyOfArgument ( 2 ) , "`table.sort`" )
elseif memberName == "gsub" and isPrelude ( "string" ) then
c . nosuspend . callback ( bodyOfArgument ( 3 ) , "`string.gsub`" )
end
end
local wrappedEntry = calleeName ~= "" and c . lookupEntry ( calleeName ) or nil
if wrappedEntry and wrappedEntry . wrappedProtocol then
local protocol = wrappedEntry . wrappedProtocol
local input = wrappedEntry . wrappedPhase == "new" and protocol . startPack or protocol . resumePack
local output = T . packUnion ( { protocol . yieldPack , protocol . returnPack } )
calleeT = T . func (
input . head ,
output . head ,
input . tail ~= nil ,
input . modes ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
input ,
output
)
node . calleeType = calleeT
end




local tableGlobal = c . env and c . env . globals and c . env . globals . table or nil
local tableBase = callee and callee . kind == "dotIndex" and callee . obj or nil
local tableToken = tableBase and tableBase . kind == "name" and tableBase . token or nil
if node . kind == "call"
and callee
and callee . kind == "dotIndex"
and callee . immutablePath
and tableToken
and tableGlobal
and tableToken . definition == tableGlobal . definition
and (
memberName == "new" or memberName == "clear" or memberName == "clone"
) then
node . tableIntrinsic = memberName
end
local knownAts = nil



local pairParams = calleeT . tag == "func" and calleeT . typeParams
local pairMap = calleeT . tag == "func" and calleeT . params [ 1 ]
local isPairsContract = calleeName == "pairs"
and pairParams
and # pairParams == 2
and pairMap
and pairMap . tag == "map"
and pairMap . key == pairParams [
1
] and pairMap . value == pairParams [ 2 ]
if isPairsContract then
local args = argExprs
if # args == 1 then
local at = c . infer ( args [ 1 ] )
if at . tag == "nominal" or ( at . tag == "typevar" and at . bound and at . bound . tag == "nominal" ) then
local iterator = T . func ( { } , { T . any , T . any } , false )
c . lastCallRets = { iterator }
return iterator
end
knownAts = { at }
end
end





if calleeName == "setmetatable" and calleeT . tag ~= "func" then
c . checkMetatableLiteral ( argExprs [ 2 ] , nil , T . metatable ( T . any ) )
end
local first , rets , pack = c . inferCall ( node , calleeT , node . args , knownAts )
if node . kind == "call" and stringFormatIntrinsic ( c , callee ) then
local format = literalString ( argExprs [ 1 ] )
local plan = format and debugFormatPlan ( format ) or nil
local positional = true
for _ , argument in ipairs ( argExprs ) do
if argument . kind == "namedArg" or argument . kind == "pluckArg" then
positional = false
end
end
if positional and plan then
node . formatIntrinsic = { format = plan . format , debugArguments = plan . debugArguments , argumentOffset = 1 , }
end
end
local preciseLpeg = specializeLpegCall ( callee , memberName , node . argumentPack )
if preciseLpeg then
first , rets , pack = preciseLpeg , { preciseLpeg } , T . pack ( { preciseLpeg } )
end
if callee and callee . staticOverloadOwner and callee . staticOverloadName and node . overloadWinner then
local owner = callee . staticOverloadOwner
local name = callee . staticOverloadName
local selectedMember = methodslots . member ( name , node . overloadWinner )
for _ , entry in ipairs ( owner . staticEntries and owner . staticEntries [ name ] or { } ) do
local candidate = specializeSelf ( owner , entry . signature , owner )
if candidate . id == node . overloadWinner . id or entry . member == selectedMember then
callee . overloadMember = entry . member
break
end
end
callee . overloadMember = callee . overloadMember or selectedMember
end
if wrappedEntry and wrappedEntry . wrappedProtocol then
wrappedEntry . wrappedPhase = "started"
end
local globalEntry = calleeName ~= "" and c . env and c . env . globals and c . env . globals [ calleeName ] or nil
local localEntry = calleeName ~= "" and c . lookupEntry ( calleeName ) or nil
local stableGlobal = globalEntry and localEntry and globalEntry . definition == localEntry . definition
if stableGlobal and calleeName == "select" and node . argumentPack then
local source = node . argumentPack
local selector = argExprs [ 1 ]
local selectorToken = selector and (
selector . kind == "string" or selector . kind == "number"
) and selector . token or nil
local selectorText = selectorToken and selectorToken . text or ""
if selector and selector . kind == "string" and ( selectorText == '"#"' or selectorText == "'#'" ) then
pack = T . pack ( { T . integer } )
local discarded = { }
for j = 2 , # source . head do
discarded [ # discarded + 1 ] = source . head [ j ]
end
c . checkPackDiscard ( T . pack ( discarded , source . tail ) , 1 , node )
else
local selected = nil
if selector and selector . kind == "number" then
selected = tonumber ( ( selectorText : gsub ( "_" , "" ) ) )
elseif selector
and selector . kind == "unop"
and selector . op
and selector . op . kind == "-"
and selector . operand
and selector . operand . kind == "number"
and selector . operand . token
then
selected = - ( assert ( tonumber ( ( selector . operand . token . text : gsub ( "_" , "" ) ) ) ) )
end
local values = { }
for j = 2 , # source . head do
values [ # values + 1 ] = source . head [ j ]
end
local valuePack = T . pack ( values , source . tail )
if selected then
local start = selected < 0 and # values + selected + 1 or selected
if not source . tail and ( selected == 0 or start < 1 or start > # values ) then
c . diag ( "NUPP2010" , selector , "select index is outside its statically known argument pack" )
end
local discarded = { }
for j = 1 , math . max ( start - 1 , 0 ) do
discarded [ # discarded + 1 ] = values [ j ]
end
c . checkPackDiscard (
T . pack ( discarded , source . tail and start > # values and source . tail or nil ) ,
1 ,
selector or node
)
local sliced = { }
for j = math . max ( start , 1 ) , # values do
sliced [ # sliced + 1 ] = values [ j ]
end
pack = T . pack ( sliced , valuePack . tail )
else
local members = { }
for _ , value in ipairs ( values ) do
members [ # members + 1 ] = value
end
if source . tail and source . tail . type then
members [ # members + 1 ] = source . tail . type
end
pack = T . pack ( { } , { kind = "homogeneous" , type = # members > 0 and T . union ( members ) or T . any } )
c . checkPackDiscard ( valuePack , 1 , selector or node )
end
end
first , rets = T . packAt ( pack , 1 ) or T . nil_ , pack . head
end
if stableGlobal and calleeName == "unpack" and node . argumentPack then
local tableType = T . packAt ( node . argumentPack , 1 )
local elements , elementType = { } , nil
if tableType and tableType . tag == "tuple" then
for j , value in ipairs ( tableType . elems ) do
elements [ j ] = value
end
elseif tableType and tableType . tag == "array" then
elementType = tableType . elem
end
if # elements > 0 or elementType then
local function integerLiteral ( expr )
local tok = expr and expr . kind == "number" and expr . token or nil
if not tok then
return nil
end

return tonumber ( ( tok . text : gsub ( "_" , "" ) ) )
end

local from = integerLiteral ( argExprs [ 2 ] ) or 1
local through = integerLiteral ( argExprs [ 3 ] )
if # elements > 0 and (
not argExprs [ 2 ] or integerLiteral ( argExprs [ 2 ] )
) and ( not argExprs [ 3 ] or through ) then
through = through or # elements
local sliced = { }
for j = from , through do
sliced [ # sliced + 1 ] = elements [ j ] or T . nil_
end
pack = T . pack ( sliced )
elseif elementType then
pack = T . pack ( { } , { kind = "homogeneous" , type = elementType } )
else
pack = T . pack ( { } , { kind = "homogeneous" , type = T . union ( elements ) } )
end
first , rets = T . packAt ( pack , 1 ) or T . nil_ , pack . head
end
end
local tableEntry = baseName ~= "" and c . env and c . env . globals and c . env . globals [ baseName ] or nil
local baseEntry = baseName ~= "" and c . lookupEntry ( baseName ) or nil
local stableMember = tableEntry and baseEntry and tableEntry . definition == baseEntry . definition
if stableMember and baseName == "coroutine" then
node . coroutineIntrinsic = memberName
local actual = node . argumentPack or T . pack ( { } )
local function unknownPack ( )
return T . pack ( { } , { kind = "unknown" , type = T . any } )
end

local function checkProtocol ( expected , offset )
local head = { }
for j = offset + 1 , # actual . head do
head [ # head + 1 ] = actual . head [ j ]
end
local supplied = T . pack ( head , actual . tail )
local ok , why = packIsA ( supplied , expected )
local exact = expected . alternatives
or expected . tail
or not supplied . tail
and # supplied . head == # expected . head
if not ok or not exact then
c . diag (
"NUPP2010" ,
argExprs [ offset + 1 ] or node ,
why or ( "coroutine pack has %d values, expected %d" ) : format ( # supplied . head , # expected . head )
)
end
end

if memberName == "create" then
local bodyType = T . packAt ( actual , 1 )
if bodyType and bodyType . tag == "func" then
first = T . protocolThread (
bodyType . paramPack ,
bodyType . resumePack or unknownPack ( ) ,
bodyType . yieldPack or unknownPack ( ) ,
bodyType . retPack
)
pack , rets = T . pack ( { first } ) , { first }
end
elseif memberName == "resume" then
local threadType = T . packAt ( actual , 1 )
if threadType and threadType . tag == "protocolThread" then
local threadArg = argExprs [ 1 ]
local threadEntry = threadArg and threadArg . kind == "name" and threadArg . token and c . lookupEntry (
threadArg . token . text
) or nil




local phase = threadEntry and threadEntry . threadPhase or "unknown"
if phase == "dead" then
c . diag ( "NUPP2010" , threadArg or node , "a coroutine narrowed to dead cannot be resumed" )
end
local accepted = phase == "new"
and threadType . startPack
or phase == "started"
and threadType . resumePack
or phase == "dead"
and threadType . resumePack
or T . packUnion (
{
threadType . startPack ,
threadType . resumePack
}
)
if accepted . alternatives then
local fits = false
local suppliedHead = { }
for j = 2 , # actual . head do
suppliedHead [ # suppliedHead + 1 ] = actual . head [ j ]
end
local supplied = T . pack ( suppliedHead , actual . tail )
for _ , arm in ipairs ( accepted . alternatives ) do
local armFits = packIsA (
supplied ,
arm
) and ( arm . tail ~= nil or not supplied . tail and # supplied . head == # arm . head )
fits = fits or armFits
end
if not fits then
checkProtocol ( threadType . startPack , 1 )
end
else
checkProtocol ( accepted , 1 )
end
if threadEntry then
threadEntry . threadPhase = "started"
end
local function successful ( values )
local head = { T . literal ( true , T . boolean ) }
for _ , value in ipairs ( values . head ) do
head [ # head + 1 ] = value
end

return T . pack ( head , values . tail )
end

pack = T . packUnion ( {
successful ( threadType . yieldPack ) ,
successful ( threadType . returnPack ) ,
T . pack ( {
T . literal ( false , T . boolean ) ,
T . any
} )
} )
first , rets = T . packAt ( pack , 1 ) or T . boolean , pack . head
end
elseif memberName == "yield" then
local expected = c . yieldPackStack [ # c . yieldPackStack ]
local resumed = c . resumePackStack [ # c . resumePackStack ]
if expected then
checkProtocol ( expected , 0 )
end
local protocol = c . protocolStack [ # c . protocolStack ]
if protocol and not expected then
protocol . yieldPacks [ # protocol . yieldPacks + 1 ] = actual
end
if resumed then
pack , rets = resumed , resumed . head
first = T . packAt ( resumed , 1 ) or T . nil_
end
elseif memberName == "status" then
local threadArg = argExprs [ 1 ]
local threadEntry = threadArg and threadArg . kind == "name" and threadArg . token and c . lookupEntry (
threadArg . token . text
) or nil
if threadArg and threadArg . kind == "name" and threadArg . token then
node . coroutineStatusName = threadArg . token . text
end
local phase = threadEntry and threadEntry . threadPhase or "unknown"
local statuses = { }
if phase == "new" then
statuses [ 1 ] = T . literal ( "suspended" , T . string )
elseif phase == "dead" then
statuses [ 1 ] = T . literal ( "dead" , T . string )
elseif phase == "started" then
statuses = { T . literal ( "suspended" , T . string ) , T . literal ( "dead" , T . string ) }
else
statuses = {
T . literal ( "suspended" , T . string ) ,
T . literal ( "running" , T . string ) ,
T . literal ( "normal" , T . string ) ,
T . literal ( "dead" , T . string )
}
end
first = T . union ( statuses )
pack , rets = T . pack ( { first } ) , { first }
elseif memberName == "wrap" then
local bodyType = T . packAt ( actual , 1 )
if bodyType and bodyType . tag == "func" then
local wrappedReturns = T . packUnion ( { bodyType . yieldPack or unknownPack ( ) , bodyType . retPack } )
first = T . func (
bodyType . paramPack . head ,
wrappedReturns . head ,
bodyType . paramPack . tail ~= nil ,
bodyType . paramPack . modes ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
bodyType . paramPack ,
wrappedReturns ,
nil ,
nil ,
nil ,
nil ,
bodyType . paramNames
)
node . wrappedProtocol = T . protocolThread (
bodyType . paramPack ,
bodyType . resumePack or unknownPack ( ) ,
bodyType . yieldPack or unknownPack ( ) ,
bodyType . retPack
)
pack , rets = T . pack ( { first } ) , { first }
end
end
end




if node . kind == "call" and pegCompilePath ( callee ) then
local source = literalString ( argExprs [ 1 ] ) or literalToken ( argStr )
local sourceType = node . argumentPack and T . packAt ( node . argumentPack , 1 ) or nil
if not source and sourceType and sourceType . tag == "literal" and type ( sourceType . constant ) == "string" then
source = sourceType . constant
end
if source then
local options = node . argumentPack and T . packAt ( node . argumentPack , 2 ) or nil
local definitions = readableField ( options , "definitions" ) or readableField ( options , "actions" )
local result = pegTyping . inferSourceResult ( source , definitions )
local matcher = result and pegMatcher ( result )
if matcher then
first , rets , pack = matcher , { matcher } , T . pack ( { matcher } )
end
end
end
local dynamicExport = node . kind == "call" and callee and callee . exactCallExport or nil
if not dynamicExport
and node . kind == "call"
and callee
and callee . kind == "dotIndex"
and callee . obj
and callee . obj . kind == "name"
and callee . obj . token
and callee . name
then
local holder = c . lookupEntry ( callee . obj . token . text )
if holder and holder . requiredModule == "nupp.dynamic" then
dynamicExport = { module = "nupp.dynamic" , member = callee . name . text , }
end
end
if dynamicExport and dynamicExport . module == "nupp.dynamic" then
local source = argExprs [ 1 ]
local entry = source and c . ownershipEntry ( source ) or nil
entry = c . ownershipState ( entry )
if dynamicExport . member == "erase" then
if entry and entry . resourceCapability then
node . resourceCapability = entry . resourceCapability
end
elseif dynamicExport . member == "recover" and entry and entry . resourceCapability then
local capabilityType = entry . resourceCapability
local expected = node . argumentPack and T . packAt ( node . argumentPack , 2 ) or nil
local requested = expected and expected . tag == "typeobject" and expected . of or nil
if requested and requested . id ~= rawType ( capabilityType ) . id then
local fix = c . edits . typeFix ( argExprs [ 2 ] , T . tostring ( rawType ( capabilityType ) ) )
local related = entry . definition and c . related (
entry . definition ,
"erased handle policy was established here"
) or nil
c . diag (
"NUPP2613" ,
argExprs [ 2 ] or node ,
"dynamic handle recovery requests a different type or cleanup policy" ,
fix and { fix } or nil ,
{
help = "recover the representation recorded by the handle" ,
related = related and { related } or nil ,
}
)
else
local capability = c . capabilityOf ( capabilityType )
local policy = { T . tostring ( capabilityType ) }
for _ , cleanup in ipairs ( T . capabilityCleanups ( capability ) ) do
policy [ # policy + 1 ] = cleanup . id
end
node . dynamicRecoverPolicy = table . concat ( policy , "|" )
node . resourceCapability = capabilityType
end
end
end



local erasedResult = rawType ( first )
local erasedOrigin = erasedResult . tag == "nominal" and ( erasedResult . origin or erasedResult ) or nil
if erasedOrigin
and erasedOrigin . tag == "nominal"
and erasedOrigin . moduleName == "nupp.dynamic"
and erasedOrigin . name == "ErasedHandle"
and not node . resourceCapability
then
local source = argExprs [ 1 ]
local entry = source and c . ownershipEntry ( source ) or nil
entry = c . ownershipState ( entry )
node . resourceCapability = entry and entry . resourceCapability or nil
end
if node . kind == "safeCall" then
local calledPack = pack or ( rets and T . pack ( rets ) or T . pack ( { } , { kind = "unknown" , type = T . any } ) )
pack = T . packUnion ( { calledPack , T . pack ( { T . nil_ } ) } )
first = T . optional ( first )
rets = pack . head
end
c . lastCallRets = rets
node . valuePack = pack or ( rets and T . pack ( rets ) or T . pack ( { } , { kind = "unknown" , type = T . any } ) )

return first
end
handlers . safeCall = handlers . call

handlers . methodCall = function ( node )
local receiver , member = node . obj , node . name
if not receiver or not member then
return T . any
end
local ot = c . infer ( receiver )



local optional = node . safeObj ~= nil or node . safeMethod ~= nil
if node . safeObj then
ot = withoutNil ( ot )
end
local rawReceiver = rawType ( ot )
local staticOwner = (
rawReceiver . tag == "metatable" or rawReceiver . tag == "typeobject"
) and rawType ( rawReceiver . of ) or nil
local static = staticOwner
and staticOwner . tag == "nominal"
and staticOwner . staticByname
and staticOwner . staticByname [
member . text
]
if static then
local owner = staticOwner
c . diag (
"NUPP2004" ,
member ,
( "%q is a static function and does not accept a receiver" ) : format ( member . text ) ,
nil ,
{ help = ( "call it with `%s.%s(...)`" ) : format ( owner . name , member . text ) }
)
local first , rets , pack = c . inferCall ( node , static , node . args )
c . nosuspend . call ( node )
c . lastCallRets = rets
node . valuePack = pack or ( rets and T . pack ( rets ) or T . pack ( { } , { kind = "unknown" , type = T . any } ) )
return first
end
local mt , fieldDef , fieldDefs = c . fieldType ( ot , member . text )
if mt and node . safeMethod then
mt = withoutNil ( mt )
end
if mt then
local callable = mt . tag == "func"
local receiverMode = mt . tag == "func" and mt . paramModes [ 1 ] or "plain"
if mt . tag == "intersection" then
callable = true
for _ , signature in ipairs ( mt . members ) do
if signature . tag ~= "func" then
callable = false
break
end
end
end
c . markToken ( member , fieldDef , mt , callable and "method" or "property" )
member . additionalDefinitions = fieldDefs

local methodType = callable and specializeReceiver ( mt , ot ) or mt
local nominal = rawReceiver . tag == "nominal" and rawReceiver or nil
local origin = nominal and ( ( nominal . origin or nominal ) ) or nil
local spanElement = nil
if nominal and origin and origin . moduleName == "nupp.span" and nominal . typeArgs then
spanElement = nominal . typeArgs [ 1 ]
end
if callable and member . text == "set" and spanElement and fixedWidth . isPhysical ( spanElement ) then


node . fixedWidthPhysicalParameters = { [ 2 ] = true }
end
local first , rets , pack = c . inferCall ( node , callable and dropSelf ( methodType ) or methodType , node . args )
local literal = receiver
while literal and literal . kind == "paren" do
literal = literal . expr
end
local positional = true
local methodArgs = node . args and node . args . kind == "args" and ( node . args ) . exprs or { }
for _ , argument in ipairs ( methodArgs ) do
if argument . kind == "namedArg" or argument . kind == "pluckArg" then
positional = false
end
end
if positional and not optional and member . text == "format" and literal and literal . kind == "string" then
local format = literalString ( literal )
local plan = format and debugFormatPlan ( format ) or nil
if plan then
node . formatIntrinsic = {
format = plan . format ,
debugArguments = plan . debugArguments ,
argumentOffset = 0 ,
}
end
end
c . nosuspend . call ( node )
local owner = rawType ( ot )
local spanMethods = { get = true , getMut = true , set = true }
local spanTypes = { Span = true , FixedSpan = true , WriteSpan = true , FixedWriteSpan = true }
if owner . tag == "nominal" then
local nominal = owner
local origin = nominal . origin
if origin and origin . tag == "nominal" then
nominal = origin
end
if nominal . moduleName == "nupp.span" and spanTypes [ nominal . name ] and spanMethods [ member . text ] then
node . spanAccessorNoAllocate = true
end
end
node . overloadMember = pegReplacementMember (
ot ,
member . text ,
node . argumentPack and T . packAt ( node . argumentPack , 2 ) or nil
)
if owner . tag == "nominal" and owner . dynamicStore and member . text == "put" then
local adopted = node . argumentPack and T . packAt ( node . argumentPack , 1 ) or nil
local actualArgs = node . args and node . args . kind == "args" and node . args . exprs or { }
local entry = actualArgs [ 1 ] and c . ownershipEntry ( actualArgs [ 1 ] ) or nil
local capability = adopted and c . capabilityOf ( adopted , entry ) or nil
local selfContained = capability and T . capabilityHasMovable (
capability
) and not T . capabilityTransferOnly (
capability
) and # capability . loans == 0 and # capability . anchors == 0 and # capability . retentions == 0
local cleanups = capability and T . capabilityCleanups ( capability ) or { }
if selfContained and # cleanups > 0 then
local policy = { T . tostring ( adopted ) }
for _ , cleanup in ipairs ( cleanups ) do
policy [ # policy + 1 ] = cleanup . id
end
node . dynamicPutCleanups = cleanups
node . dynamicTypePolicy = table . concat ( policy , "|" )
node . resourceCapability = adopted
else
local related = entry and entry . definition and c . related (
entry . definition ,
"value supplied to the dynamic store is declared here"
) or nil
c . diag (
"NUPP2612" ,
actualArgs [ 1 ] or node ,
"dynamic.Store.put requires a self-contained capability with an exact cleanup policy" ,
nil ,
{
help = "remove borrows, pins, foreign retention, or transfer-only leaves before enrolling the value" ,
related = related and { related } or nil ,
}
)
end
elseif owner . tag == "nominal" and owner . dynamicStore and member . text == "take" then
local actualArgs = node . args and node . args . kind == "args" and node . args . exprs or { }
local entry = actualArgs [ 1 ] and c . ownershipEntry ( actualArgs [ 1 ] ) or nil
entry = c . ownershipState ( entry )
local capability = entry and entry . resourceCapability or nil
if capability then
local payload = T . optional ( rawType ( capability ) )
local returned = T . withOwnershipPayload ( capability , payload )
first = returned
rets = { returned , rets and rets [ 2 ] or T . any }
pack = T . pack ( rets )
node . resourceCapability = capability
end
elseif owner . tag == "nominal" and owner . resourceSet and member . text == "adopt" then
local adopted = node . argumentPack and T . packAt ( node . argumentPack , 1 ) or nil
local cleanups = adopted and adopted . tag == "affine" and adopted . cleanups or nil
local actualArgs = node . args and node . args . kind == "args" and node . args . exprs or { }
if cleanups and # cleanups > 0 then
if actualArgs [ 2 ] then
c . diag ( "NUPP2602" , actualArgs [ 2 ] , "a cleanup owner already carries its discharge contract" )
end
node . resourceAdoptCleanups = cleanups
node . resourceCapability = adopted
elseif cleanups and # cleanups == 0 then
if not actualArgs [ 2 ] then
c . diag ( "NUPP2602" , node , "an opaque owner needs an explicit terminal consumer when adopted" )
end
node . resourceCapability = adopted
else
c . diag ( "NUPP2602" , actualArgs [ 1 ] or node , "resources.Set.adopt requires an owned value" )
end
elseif owner . tag == "nominal" and owner . resourceSet and member . text == "remove" then
local actualArgs = node . args and node . args . kind == "args" and node . args . exprs or { }
local entry , nameNode = actualArgs [ 1 ] and c . ownershipEntry ( actualArgs [ 1 ] ) or nil
entry = c . ownershipState ( entry )
if not entry or not entry . resourceCapability or entry . moved then
c . diag (
"NUPP2602" ,
actualArgs [ 1 ] or node ,
"resources.Set.remove needs a live value returned by adopt"
)
else
local capability = entry . resourceCapability
entry . moved = true
entry . movedAt = nameNode or actualArgs [ 1 ]
c . releaseBorrowLinks ( entry )
first , rets , pack = capability , { capability } , T . pack ( { capability } )
node . resourceCapability = capability
end
end
if owner . tag == "nominal" and owner . overloadedMethods and owner . overloadedMethods [
member . text
] and node . overloadWinner then
local selectedMember = methodslots . member ( member . text , node . overloadWinner )
local dispatch = owner . methodDispatchEntries and owner . methodDispatchEntries [
member . text
] or ( owner . methodEntries and owner . methodEntries [ member . text ] ) or { }
for _ , entry in ipairs ( dispatch ) do
local candidate = dropSelf ( specializeSelf ( owner , entry . signature , owner ) )
if candidate . id == node . overloadWinner . id or entry . member == selectedMember then
receiverMode = entry . signature . paramModes [ 1 ] or "plain"
node . overloadMember = entry . member
node . methodEntry = entry
c . markToken ( member , entry . definition , specializeSelf ( owner , entry . signature , owner ) , "method" )
member . additionalDefinitions = nil
break
end
end
node . overloadMember = node . overloadMember or selectedMember
end
if receiverMode == "takes" then
if node . safeObj or node . safeMethod then
c . diag ( "NUPP2602" , receiver , "a conditional method call cannot take its receiver; narrow it first" )
else
c . moveExpression ( receiver , ot , "method receiver" )
if receiver . automaticOwnerMove then
node . automaticOwnerMoves = node . automaticOwnerMoves or { }
node . automaticOwnerMoves [ # node . automaticOwnerMoves + 1 ] = receiver . automaticOwnerMove
end
end
elseif receiverMode == "exclusive" then
local entry , nameNode = c . ownershipEntry ( receiver )
entry = c . ownershipState ( entry )
local entryFacts = entry and c . own . capabilityFacts ( entry , nil , false ) or nil
local regionRoot , regionPath = c . regionOf ( receiver )
local roots = entry and { entry } or c . own . provenanceOwners ( receiver )
if # roots == 0 then
c . diag ( "NUPP2602" , receiver , "an exclusive receiver requires a named or rooted value" )
else
for _ , root in ipairs ( roots ) do
local blocked = ( root . activeBorrows or 0 ) > 0
if regionRoot and regionPath and regionPath ~= "" then
blocked = false
for activePath , count in pairs ( regionRoot . activeRegions or { } ) do
local own = entry
and entryFacts
and entryFacts . regionRoot == regionRoot
and entryFacts . regionPath == regionPath
and 1
or 0
if (
activePath == regionPath and count > own
) or (
activePath ~= regionPath and c . regionsOverlap (
activePath ,
regionPath
) and not c . regionContains ( activePath , regionPath )
) then
blocked = true
break
end
end
end
if blocked then
c . diag (
"NUPP2607" ,
nameNode or receiver ,
"an exclusive receiver cannot invalidate a value while a derived borrow is live" ,
nil ,
c . own . conflictDetails ( regionRoot or root , regionPath )
)
break
end
end
end
if c . ownershipKind ( first ) then
local resultFacts = c . own . capabilityFacts ( node , 1 )
resultFacts . exclusive = true
if regionRoot and regionPath and regionPath ~= "" then
resultFacts . regionRoot = regionRoot
resultFacts . regionPath = regionPath
end
end
elseif receiverMode == "borrows" then
local entry , nameNode = c . ownershipEntry ( receiver )
entry = c . ownershipState ( entry )
local entryFacts = entry and c . own . capabilityFacts ( entry , nil , false ) or nil
local regionRoot , regionPath = c . regionOf ( receiver )
local roots = entry and { entry } or c . own . provenanceOwners ( receiver )
for _ , root in ipairs ( roots ) do
local blocked = ( root . activeExclusiveBorrows or 0 ) > 0
if regionRoot and regionPath and regionPath ~= "" then
blocked = false
for activePath , count in pairs ( regionRoot . activeExclusiveRegions or { } ) do
local own = entry
and entryFacts
and entryFacts . regionRoot == regionRoot
and entryFacts . regionPath == regionPath
and 1
or 0
if (
activePath == regionPath and count > own
) or (
activePath ~= regionPath and c . regionsOverlap (
activePath ,
regionPath
) and not c . regionContains ( activePath , regionPath )
) then
blocked = true
break
end
end
end
if blocked then
c . diag (
"NUPP2607" ,
nameNode or receiver ,
"a shared receiver cannot overlap a live exclusive view" ,
nil ,
c . own . conflictDetails ( regionRoot or root , regionPath , true )
)
break
end
end
if regionRoot and regionPath and regionPath ~= "" and c . ownershipKind ( first ) then
local resultFacts = c . own . capabilityFacts ( node )
resultFacts . regionRoot = regionRoot
resultFacts . regionPath = regionPath
end
end
if optional then
local calledPack = pack or ( rets and T . pack ( rets ) or T . pack ( { } , { kind = "unknown" , type = T . any } ) )
pack = T . packUnion ( { calledPack , T . pack ( { T . nil_ } ) } )
first = T . optional ( first )
rets = pack . head
end
c . lastCallRets = rets
node . valuePack = pack or ( rets and T . pack ( rets ) or T . pack ( { } , { kind = "unknown" , type = T . any } ) )
return first
end
if ot ~= T . any and ot ~= T . table_ and ot . tag ~= "map" then
if ot . tag == "shape" or ot . tag == "nominal" then
local fixes = c . edits . nameSpellingFix ( member , c . fieldNames ( ot ) )
c . diag ( "NUPP2004" , member , ( "no method %q in %s" ) : format ( member . text , T . tostring ( ot ) ) , fixes , {
help = fixes
and "use the suggested method spelling"
or "check the receiver type and available methods"
} )
end
end
if node . args then
c . inferCall ( node , T . any , node . args )
end
c . nosuspend . call ( node )



c . lastCallRets = nil
node . valuePack = T . pack ( { } , { kind = "unknown" , type = T . any } )

return T . any
end

return handlers
end

return callexpr
