_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()














local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.types.relations" )
local generics = require ( "nupp.compiler.types.generics" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local cst = require ( "nupp.compiler.syntax.cst" )
local ffiMod = require ( "nupp.compiler.check.ffi" )
local methodslots = require ( "nupp.compiler.lua.methodslots" )
local native = require ( "nupp.compiler.native" )
local luaFormat = require ( "nupp.compiler.lua.luaformat" )
local reflection = require ( "nupp.compiler.reflection" )
local narrowing = require ( "nupp.compiler.types.narrowing" )
local predicate = require ( "nupp.compiler.types.predicate" )
local targetLayout = require ( "nupp.compiler.targetlayout" )
local fixedWidth = require ( "nupp.compiler.types.fixedwidth" )
local indexedViews = require ( "nupp.compiler.types.indexedviews" )
local state = require ( "nupp.compiler.check.state" )
local pegTyping = require (
"nupp.compiler.comptime.materialize.peg"
)
local runtimeSurface = require ( "nupp.compiler.runtimesurface" )

local isA = relations . isA
local packIsA = relations . packIsA



local function protocolPackFits ( have , want ) 
if have . alternatives then
for _ , arm in ipairs ( have . alternatives ) do
local ok , why = protocolPackFits ( arm , want )
if not ok then
return false , why
end
end
return true , nil
end
if want . alternatives then
for _ , arm in ipairs ( want . alternatives ) do
if protocolPackFits ( have , arm ) then
return true , nil
end
end
return false , "coroutine pack fits no declared alternative"
end
local ok , why = packIsA ( have , want )
if not ok then
return false , why
end
if not want . tail and ( have . tail or # have . head ~= # want . head ) then
return false , ("coroutine pack has %d values, expected %d") : format ( # have . head , # want . head )
end

return true , nil
end

local rawType = T . unwrapOwnership


local LANE_MATH = { sqrt = true , abs = true , floor = true , ceil = true }


local function floatingVector ( t ) 
if t . tag ~= "nominal" then
return false
end
local nominal = t
local origin = ( nominal . origin or nominal )
if origin . name ~= "Vector" or ( origin . moduleName ~= "nupp.simd" and origin . sealedModule ~= "nupp.simd" ) then
return false
end
local element = nominal . typeArgs and ( nominal . typeArgs ) [ 1 ] or nil
if element == nil then
return false
end
local payload = T . unwrapOwnership ( element )

return payload . tag == "float" or payload . tag == "number"
end

local dropSelf = generics . dropSelf
local specializeSelf = generics . specializeSelf
local specializeReceiver = generics . specializeReceiver

local callexpr = { }

local COMPILER_SURFACES = require ( "nupp.compiler.check.surfaces" ) . COMPILER_SURFACES
local RECEIVER_INTRINSICS = require ( "nupp.compiler.check.receiverintrinsics" )



local function opensTaskScope ( c , callee ) 
if callee . kind ~= "dotIndex" then
return false
end
local member = callee . name
if member == nil or member . text ~= "open" then
return false
end
local base = callee . obj
if base == nil then
return false
end
if base . qualifiedModule == "nupp.tasks" and # ( base . qualifiedMembers or { } ) == 0 then
return true
end
local token = base . kind == "name" and base . token or nil
local holder = token and c . lookupEntry ( token . text ) or nil

return holder ~= nil and holder . requiredModule == "nupp.tasks"
end











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
if RECEIVER_INTRINSICS [ name ] ~= "nupp.profile.zone" then
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
local zoneType = c . env and c . env . resolveModule and c . env . resolveModule ( c . env , RECEIVER_INTRINSICS [ name ] )
if not zoneType then
return nil
end
local owner = rawType ( baseType )
if owner . tag == "nominal" then
owner = owner . origin or owner
end

return owner == zoneType and name or nil
end





local function keepIntrinsic ( c , callee ) 
if not callee or callee . kind ~= "dotIndex" or not callee . name then
return false
end
local benchModule = RECEIVER_INTRINSICS [ callee . name . text ]
if benchModule ~= "nupp.bench" then
return false
end
local base = callee . obj
if not base or base . kind ~= "name" or not base . token then
return false
end
local baseType = c . lookupVar ( base . token . text )
if not baseType then
return false
end
local benchType = c . env and c . env . resolveModule and c . env . resolveModule ( c . env , benchModule )
if not benchType then
return false
end
local owner = rawType ( baseType )
if owner . tag == "nominal" then
owner = owner . origin or owner
end

return owner == benchType
end
















local function positionalOnly ( exprs ) 
for _ , argument in ipairs ( exprs ) do
if argument . kind == "namedArg" or argument . kind == "pluckArg" then
return false
end
end

return true
end

local function soaLayoutSpec ( c , subject , at ) 
if subject . tag ~= "nominal" or subject . declKind ~= "struct" then
c . diag ( "NUPP2403" , at , "SoA storage requires a reified struct type" , nil , {
help = "pass ffi.typeof<Struct>() for a struct whose fields have fixed C storage"
} )
return nil
end

local owner = subject

local function expand ( t ) 
if not t then
return nil
end
if t . tag == "nominal" and t . declKind == "struct" then
local inner = { }
for _ , name in ipairs ( t . fieldOrder or { } ) do
local one = expand ( t . byname [ name ] )
if not one then
return nil
end
inner [ # inner + 1 ] = name .. ":" .. one
end
return "{" .. table . concat ( inner , "," ) .. "}"
end

return T . cName ( t )
end

local parts , nested , printed = { } , { } , { }
for _ , name in ipairs ( owner . fieldOrder or { } ) do
local fieldType = owner . byname and owner . byname [ name ] or nil
local definition = owner . fieldDefs and owner . fieldDefs [ name ] or nil
if definition and definition . bitWidth then
c . diag ( "NUPP2403" , definition , ("SoA field %q is a bitfield and cannot form a column") : format ( name ) )
return nil
end
local spelling = fieldType and T . cName ( fieldType ) or nil
local elementOf = fieldType and fieldType . tag == "carray" and fieldType . count and fieldType . elem or nil
local byValue = fieldType
and (
( fieldType . tag == "nominal" and fieldType . declKind == "struct" )
or ( elementOf and elementOf . tag == "nominal" and elementOf . declKind == "struct" )
)
if not spelling then
c . diag (
"NUPP2403" ,
definition or at ,
("SoA field %q of %s has no fixed C storage type") : format ( name , owner . name )
)
return nil
end
parts [ # parts + 1 ] = name .. ":" .. ( byValue and ( "$" .. spelling ) or spelling )
printed [ # printed + 1 ] = name .. ":" .. ( expand ( fieldType ) or spelling )
if byValue then
nested [ # nested + 1 ] = elementOf and ( elementOf ) . name or spelling
end
end
if # parts == 0 then
c . diag ( "NUPP2403" , at , ("%s declares no stored fields") : format ( owner . name ) )
return nil
end

return { name = owner . name , spec = table . concat ( parts , "," ) , printed = table . concat ( printed , "," ) , nested = nested , }
end





function callexpr . install ( c ) 
local inferFfiIntrinsic = ffiMod . install ( c )

local handlers = { }

local function forwardProtocol ( node ) 



local protocol = c . protocolStack [ # c . protocolStack ]
local signature = node . signatureType
if protocol and signature and signature . tag == "func" and signature . yieldPack then
local expected = c . yieldPackStack [ # c . yieldPackStack ]
local resumed = c . resumePackStack [ # c . resumePackStack ]
if expected then
local ok , why = protocolPackFits ( signature . yieldPack , expected )
if not ok then
c . diag (
"NUPP2010" ,
node ,
"callee yields values outside the caller's protocol: " .. ( why or "incompatible packs" )
)
end
else
protocol . yieldPacks [ # protocol . yieldPacks + 1 ] = signature . yieldPack
end
if signature . resumePack then
if resumed then
local ok , why = packIsA ( resumed , signature . resumePack )
if not ok then
c . diag (
"NUPP2010" ,
node ,
"callee cannot accept the caller's resume values: " .. ( why or "incompatible packs" )
)
end
else
protocol . resumePacks [ # protocol . resumePacks + 1 ] = signature . resumePack
end
end
end
end

local lpegEmpty = T . array ( T . never )
local lpegUnknown = T . array ( T . any )





local function lpegPatternOrigin ( callee ) 
if not callee or callee . kind ~= "dotIndex" or not callee . obj then
return nil
end


local base = callee . obj
local owner = rawType ( base . inferredType or c . infer ( callee . obj ) )
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
elseif callback
and callback . tag == "nominal"
and ( ( callback . origin or callback ) ) . lpegPattern
then
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

local function managedGeneric ( name , payload ) 
local declared = c . lookupType ( "nupp." .. name )
if declared and declared . tag == "nominal" and declared . typeParams and declared . typeParams [ 1 ] then
local core = ( declared . origin or declared )
if name == "Managed" then
core . managedCell = true
else
core . managedAlias = true
end
return generics . instantiate ( declared , { [ declared . typeParams [ 1 ] ] = payload } )
end

return T . any
end

local function policyFor ( value ) 
local policy = { T . tostring ( value ) }
for _ , cleanup in ipairs ( T . capabilityCleanups ( T . capability ( value ) ) ) do
policy [ # policy + 1 ] = cleanup . id
end

return table . concat ( policy , "|" )
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












local function admitted ( node , result ) 
local callee = node . obj
if not callee or callee . kind ~= "dotIndex" then
return result
end
local base = callee . obj
if not base or base . kind ~= "name" or not base . token or base . token . text ~= "nupp" then
return result
end
if not callee . name or callee . name . text ~= "admit" then
return result
end
local args = ( node . args )
local exprs = args and args . exprs or nil
if not exprs or # exprs ~= 1 then
c . diag ( "NUPP2013" , node , "nupp.admit takes one value" )
return result
end
local constraint = T . constraintOf ( result )
if not constraint then
c . diag (
"NUPP2013" ,
node ,
("nupp.admit needs a constrained destination, and this one is %s") : format ( T . tostring ( result ) ) ,
nil ,
{ help = "annotate the binding, result or parameter with a constrained type" }
)
return result
end
local into = T . unconstrained ( result )
local supplied = c . infer ( exprs [ 1 ] )
local fits , why = isA ( T . unconstrained ( supplied ) , into )
if not fits and T . unconstrained ( supplied ) ~= T . any then
c . diag (
"NUPP2013" ,
exprs [ 1 ] ,
("nupp.admit narrows %s, and this value is %s") : format ( T . tostring ( into ) , T . tostring ( supplied ) ) ,
nil ,
{ help = why }
)
return result
end



local proved = isA ( supplied , result )




local test = constraint
local bare = T . unconstrained ( supplied )
if bare == T . any or bare == T . unknown then
local luaType = T . luaTypeName ( into )
if luaType then
test = predicate . normalize (
_G.setmetatable({ op =
"and" ,  a =
_G.setmetatable({ op =  "typeis" ,  path =  { } ,  luaType =  luaType }, predicate.Node) ,  b =
constraint }, predicate.Node)

)
end
end


if not proved then
node . admitPredicate = test
end
node . admitName = T . tostring ( result )

return result
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
("nupp.%s expects %d argument%s") : format ( layoutIntrinsic , expected , expected == 1 and "" or "s" )
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
("%s has no layout for %s: %s") : format ( key , target , tostring ( why ) )
)
return T . any
end
if layoutIntrinsic == "offsetof" then
local fieldType = argExprs [ 2 ] and c . infer ( argExprs [ 2 ] ) or nil
local fieldName = literalString ( argExprs [ 2 ] )
if not fieldName
and fieldType
and fieldType . tag == "literal"
and type ( fieldType . constant ) == "string"
then
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
c . diag ( "NUPP2419" , argExprs [ 2 ] or node , ("%s has no field %q") : format ( key , fieldName ) )
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



if positionalOnly ( argExprs ) and format and format . kind == "string" then
node . logIntrinsic = severity
node . logFormatIntrinsic = debugFormatPlan ( literalString ( format ) or "" )
end
end


local zoneOp = zoneIntrinsic ( c , callee )
if zoneOp and not argTable and not argStr then
if positionalOnly ( argExprs ) then
if zoneOp == "push" and # argExprs == 1 then
node . zoneIntrinsic = "push"
elseif zoneOp == "pop" and # argExprs == 0 then
node . zoneIntrinsic = "pop"
end
end
end



if not argTable and not argStr and # argExprs == 1 and positionalOnly ( argExprs ) and keepIntrinsic ( c , callee ) then
node . keepIntrinsic = true
end
local intrinsic = ownershipIntrinsic ( c , callee )
if intrinsic then
local args = argExprs
if intrinsic == "adopt" then
local valueT = args [ 1 ] and c . infer ( args [ 1 ] ) or T . any
local targetNode = callee and callee . kind == "dotIndex" and callee . ownershipTypeArg or nil
local target = targetNode and c . resolveType ( targetNode ) or T . any
if not targetNode then
c . diag ( "NUPP2602" , node , "nupp.adopt needs an owner type: nupp.adopt<Owner>(value)" )
elseif target . tag ~= "affine" then
c . diag ( "NUPP2602" , targetNode , "nupp.adopt target must be an affine type" )
end
if # args ~= 1 then
c . diag ( "NUPP2602" , node , "nupp.adopt expects one unmanaged value" )
elseif c . ownershipKind ( valueT ) then
c . diag ( "NUPP2602" , args [ 1 ] , "nupp.adopt expects an unmanaged value" )
end
if c . unsafeDepth == 0 then
c . diag ( "NUPP2604" , node , "nupp.adopt requires @unsafe on the call" )
end
local representation = rawType ( target )
if valueT ~= T . any and target ~= T . any and not isA ( valueT , representation ) then
c . diag (
"NUPP2602" ,
args [ 1 ] or node ,
("cannot adopt %s as owner of %s") : format ( T . tostring ( valueT ) , T . tostring ( representation ) )
)
end
node . ownerCleanups = target . tag == "affine" and target . cleanups or nil
node . ownershipIntrinsic = "adopt"
return target
elseif intrinsic == "release" then
local valueT = args [ 1 ] and c . infer ( args [ 1 ] ) or T . any
if # args ~= 1 or c . ownershipKind ( valueT ) ~= "affine" then
c . diag ( "NUPP2602" , args [ 1 ] or node , "nupp.release expects one affine value" )
end
if c . unsafeDepth == 0 then
c . diag ( "NUPP2604" , node , "nupp.release requires @unsafe on the call" )
end
c . moveExpression ( args [ 1 ] or node , valueT , "nupp.release" )
node . ownershipIntrinsic = "release"
return rawType ( valueT )
elseif intrinsic == "manage" then
local valueT = args [ 1 ] and c . infer ( args [ 1 ] ) or T . any

c . markTemporaryConsumed ( args [ 1 ] )
local entry = args [ 1 ] and c . ownershipEntry ( args [ 1 ] ) or nil
local capability = c . capabilityOf ( valueT , entry )
local selfContained = # args == 1
and capability
and T . capabilityHasMovable ( capability )
and not T . capabilityTransferOnly ( capability )
and # T . capabilityCleanups ( capability ) > 0
and # capability . loans == 0
and # capability . anchors == 0
and # capability . retentions == 0
if not selfContained then
c . diag (
"NUPP2612" ,
args [ 1 ] or node ,
"nupp.manage requires one self-contained owner with an exact cleanup policy" ,
nil ,
{
help = "remove borrows, pins, foreign retention, or transfer-only leaves before managing the value"
}
)
return T . any
end
c . moveExpression ( args [ 1 ] , valueT , "nupp.manage" )
node . ownershipIntrinsic = "manage"
node . managedCleanups = T . capabilityCleanups ( capability )
node . managedPolicy = policyFor ( valueT )
local cell = managedGeneric ( "Managed" , valueT )
local owned = T . affine ( cell , { T . methodCleanup ( "close" ) } )
node . valuePack = T . pack ( { owned } )
c . lastCallRets = { owned }
return owned
elseif intrinsic == "borrow" then
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
c . diag ( "NUPP2604" , node , "borrowFrom requires @unsafe on the call" )
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
local root , parentPath
if args [ 1 ] then
root , parentPath = c . regionOf ( args [ 1 ] )
end
parentPath = root and parentPath or ""
if # args ~= 3 or not parent then
c . diag ( "NUPP2602" , node , "partition expects a named writable parent and two children" )
end


local leftKind , rightKind = c . ownershipKind ( leftT ) , c . ownershipKind ( rightT )
if ( leftKind and leftKind ~= "borrowed" ) or ( rightKind and rightKind ~= "borrowed" ) then
c . diag ( "NUPP2602" , node , "partition children must not already carry ownership" )
end
if rawType ( leftT ) . id ~= rawType ( rightT ) . id then
c . diag ( "NUPP2602" , node , "partition children must have the same type" )
end
if c . unsafeDepth == 0 then
c . diag ( "NUPP2604" , node , "partition requires @unsafe on the call" )
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
local root , parentPath
if args [ 1 ] then
root , parentPath = c . regionOf ( args [ 1 ] )
end
parentPath = root and parentPath or ""
local firstT = args [ 3 ] and c . infer ( args [ 3 ] ) or nil
local lastT = args [ 4 ] and c . infer ( args [ 4 ] ) or nil
local first = firstT
and firstT . tag == "literal"
and type ( firstT . constant ) == "number"
and firstT . constant % 1 == 0
and firstT . constant
or nil
local last = lastT
and lastT . tag == "literal"
and type ( lastT . constant ) == "number"
and lastT . constant % 1 == 0
and lastT . constant
or nil
if # args ~= 4 or not parent then
c . diag ( "NUPP2602" , node , "region expects a named parent, child, first index, and last index" )
elseif c . ownershipKind ( childT ) then
c . diag ( "NUPP2602" , node , "region child must not already carry ownership" )
elseif first and last and last < first - 1 then
c . diag ( "NUPP2602" , node , "region range ends before it begins" )
end
if c . unsafeDepth == 0 then
c . diag ( "NUPP2604" , node , "region requires @unsafe on the call after runtime bounds validation" )
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
"pin must prove the pointer derives from its anchor; use @unsafe on the call for an opaque derivation"

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
if operationT ~= T . any
and (
operationT . tag ~= "func"
or not operationT . params [ 1 ]
or not isA ( rawType ( valueT ) , operationT . params [ 1 ] )
)
then
c . diag ( "NUPP2602" , args [ j ] , "an attemptAll operation must accept the value" )
end


if operationT ~= T . any
and operationT . tag == "func"
and operationT . paramModes
and operationT . paramModes [ 1 ] == "takes"
and j < # args
then
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
"drop needs a named terminal; transfer this owner to a declared takes parameter"
)
end
node . ownershipIntrinsic = "drop"
node . ownerType = valueT
node . ownerCleanups = { }
node . ownerCleanupGuards = nil
local state = args [ 1 ] and c . ownershipState ( ( c . ownershipEntry ( args [ 1 ] ) ) ) or nil
for _ , cleanup in ipairs ( dropped . cleanups or { } ) do
local movedField = cleanup . kind == "field"
and state
and state . movedFields
and state . movedFields [ cleanup . field ]
or false



local conditional = movedField
and state . automaticOwner
and state . conditionalMovedFields
and state . conditionalMovedFields [ cleanup . field ]
or false
if conditional then
node . ownerCleanups [ # node . ownerCleanups + 1 ] = cleanup
node . ownerCleanupGuards = node . ownerCleanupGuards or { }
node . ownerCleanupGuards [
# node . ownerCleanups
] = { owner = state . automaticOwner , field = cleanup . field }
elseif not movedField then
node . ownerCleanups [ # node . ownerCleanups + 1 ] = cleanup
end
end
return T . nil_
end
end
local calleeEntry = calleeName ~= "" and c . lookupEntry ( calleeName ) or nil
if calleeName ~= "" then
node . cdefCall = calleeEntry and calleeEntry . definition and calleeEntry . definition . cdef or false
node . cdefIdentity = node . cdefCall and calleeEntry . definition . cdefIdentity or nil
end



local requireGlobal = c . env and c . env . globals and c . env . globals . require
local requireEntry = calleeName == "require" and c . lookupEntry ( "require" ) or nil
local stableRequire = requireGlobal and requireEntry and requireGlobal . definition == requireEntry . definition
if calleeName == "require" and stableRequire then
( node ) . runtimeLoader = "require"
end
if calleeName == "require" and stableRequire and c . env and c . env . resolveModule then


if # argExprs > 1 then
c . diag ( "NUPP2007" , node , ("require takes 1 arguments, got %d") : format ( # argExprs ) )
end
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
local modname = text : match ( "^\"(.*)\"$" ) or text : match ( "^'(.*)'$" )
if modname then
local access = c . env . moduleAccess and c . env . moduleAccess ( c . env , c . result . moduleName , modname )
if access and not c . opts . generatedSource then
c . diag ( "NUPP2144" , tok , access )
return T . any
end
runtimeSurface . requireModule ( c , modname , tok )
local portableEffect = require ( "nupp.compiler.standardsurface" ) . requireModule ( c , modname , tok )
node . requiredModule = modname
local modulePath = c . env . findModulePath and c . env . findModulePath ( c . env , modname ) or nil
local canonical = modulePath
and c . env . moduleNameForPath
and c . env . moduleNameForPath ( c . env , modulePath )
or nil
local projectIndex = canonical and c . env . ensureProjectIndex and c . env . ensureProjectIndex ( c . env )
or nil
if canonical
and canonical ~= modname
and projectIndex
and projectIndex . declaredModules
and projectIndex . declaredModules [ canonical ]
then
c . diag (
"NUPP1002" ,
tok ,
("module %q is an alias; require its canonical name %q") : format ( modname , canonical )
)
node . requiredModule = canonical
modname = canonical
end
local effect = portableEffect or native . forModule ( modname )
local typeOnly = node . typeOnlyRequire == true
if effect and c . recordEffect and not typeOnly then
( node ) . compilerFeatureEffect = effect
c . recordEffect ( effect )
end

local accelerators = require ( "nupp.compiler.standardsurface" ) . accelerators ( modname )
if accelerators and c . recordEffect and not typeOnly then
local carried = ( node ) . compilerFeatureEffects or { }
for _ , accelerated in ipairs ( accelerators ) do
carried [ # carried + 1 ] = accelerated
c . recordEffect ( accelerated )
end
( node ) . compilerFeatureEffects = carried
end
local mt = c . env . resolveModule ( c . env , modname )
if mt then
return mt
end
end
end







for index , argument in ipairs ( argExprs ) do
local argumentType = c . infer ( argument )
if index == 1 then
local fits , why = isA ( argumentType , T . string )
if not fits then
c . diag ( "NUPP2006" , argument , ("require argument 1: %s") : format ( why ) )
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
local calleeDefinition = callee and callee . kind == "name" and callee . token and callee . token . definition or nil
local selectedExport = callee
and ( callee . exactCallExport or calleeDefinition and calleeDefinition . exactCallExport )
or nil
if selectedExport and selectedExport . module == "nupp.spi" and selectedExport . member == "load" then
local _ , subject = concreteTypePath ( argExprs [ 1 ] )
local declared = subject and rawType ( subject ) or nil
local origin = declared and declared . tag == "nominal" and ( declared . origin or declared ) or nil
if # argExprs ~= 1
or argStr
or argTable
or not origin
or origin . tag ~= "nominal"
or origin . declKind ~= "interface"
or not origin . moduleName
or # ( origin . typeParams or { } ) > 0
then
c . diag ( "NUPP2006" , node , "spi.load expects one concrete exported interface" )
return T . any
end
local typeName = origin . name : match ( "[^.]+$" ) or origin . name
local exported = origin . deriveDeclaration == nil or c . visibilityOf ( origin . deriveDeclaration ) == "module"
if origin . moduleName ~= c . result . moduleName then
local exports = c . env . resolveModuleExports ( c . env , origin . moduleName )
local member = exports and exports . types [ typeName ]
exported = member ~= nil and ( member . origin or member ) == origin
end
if not exported then
c . diag ( "NUPP2006" , node , "spi.load expects one concrete exported interface" )
return T . any
end
local name = origin . moduleName .. "." .. typeName
node . spiInterface = name
return T . func ( { } , { T . optional ( declared ) } , false )
end





if LANE_MATH [ memberName ] == true and baseName == "math" and # argExprs == 1 and not argStr and not argTable then
local globals = c . env and c . env . globals or nil
local library = globals and globals . math or nil
if library ~= nil and c . lookupEntry ( "math" ) == library then
local vector = rawType ( c . infer ( argExprs [ 1 ] ) )
if floatingVector ( vector ) then
( node ) . simdMath = memberName
return vector
end
end
end
if selectedExport
and # c . functionBodies == 0
and c . env
and c . env . moduleInitializing
and c . env . moduleInitializing ( c . env , selectedExport . module )
then
c . diag (
"NUPP1002" ,
callee ,
("eager module cycle calls %s before module %q has finished initializing")

: format ( selectedExport . identity , selectedExport . module ) ,
nil ,
{ help = "move this call behind an exported function so it runs after module initialization" }
)
end
if callee and callee . fixedWidthCallableUntrusted == true then
node . fixedWidthUntrustedResult = true
end
local calleeEntry = callee and c . ownershipEntry ( callee ) or nil
local calleeFacts = calleeEntry and c . own . capabilityFacts ( calleeEntry , nil , false ) or nil
if calleeFacts and calleeFacts . capturedBorrowRoots then
for _ , root in ipairs ( calleeFacts . roots or { } ) do
if root . moved then
local related = root . movedAt and c . related ( root . movedAt , "captured owner was moved here" ) or nil
c . diag (
"NUPP2602" ,
callee ,
"a local function cannot read a captured owner after it was moved" ,
nil ,
{ related = related and { related } or nil }
)
do break end
end
end
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




local captured = callee and c . ownershipEntry ( callee ) or nil
captured = c . ownershipState ( captured )
if captured
and c . ownershipKind ( captured . t ) == "affine"
and rawType ( captured . t ) . tag == "func"
and ( captured . functionDepth or 0 ) < c . functionDepth
then
c . diag ( "NUPP2602" , callee , "a captured affine closure cannot be invoked through a borrow" , nil , {
help = "name it in takes (...) so the invocation moves it into this closure" ,
} )
end
calleeT = rawType ( calleeT )
end
if calleeT . tag == "func" and calleeT . foreign then
node . cdefCall = true
end
if node . kind == "safeCall" then
calleeT = withoutNil ( calleeT )
end
node . calleeType = rawType ( calleeT )
node . scalarIntrinsic = callee and callee . scalarIntrinsic
or callee
and callee . kind == "name"
and callee . token
and callee . token . definition
and callee . token . definition . scalarIntrinsic
c . nosuspend . call ( node )

















local isCoroutine = false
if callee and callee . kind == "name" and callee . token then
local resolved = c . lookupEntry ( callee . token . text )
isCoroutine = resolved ~= nil and resolved . coroutineYield == true
elseif memberName == "yield" and callee and callee . kind == "dotIndex" then
local base = callee . obj
local baseTok = base and base . kind == "name" and base . token or nil
local coroutineGlobal = c . env and c . env . globals and c . env . globals . coroutine or nil
local resolved = baseTok and c . lookupEntry ( baseTok . text ) or nil



if resolved ~= nil and resolved . coroutineLibrary == true then

isCoroutine = true
elseif baseTok and coroutineGlobal then
if resolved ~= nil then
isCoroutine = resolved == coroutineGlobal
or ( resolved . definition ~= nil and resolved . definition == coroutineGlobal . definition )
else
isCoroutine = baseTok . text == "coroutine"
end
end
end
if isCoroutine and c . unsafeDepth > 0 then




node . trustedYield = true
elseif isCoroutine then
node . rawYield = true
local obligation = c . liveSuspensionObligation ( )
if obligation then
c . diag (
"NUPP2603" ,
node ,
("cannot suspend while temporal obligation %q is live") : format ( obligation ) ,
nil ,
{
help = "suspend inside a `with` installation scope, where a handler is responsible for resuming or cancelling it"
,
}
)
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
local wrappedEntry = calleeEntry
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
and ( memberName == "new" or memberName == "clear" or memberName == "clone" )
then
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
and pairMap . key == pairParams [ 1 ]
and pairMap . value == pairParams [ 2 ]
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
local collectionGlobal = ( calleeName == "pairs" or calleeName == "ipairs" )
and c . env
and c . env . globals
and c . env . globals [ calleeName ]
or nil
if collectionGlobal and c . lookupEntry ( calleeName ) == collectionGlobal and # argExprs == 1 then
local at = knownAts and knownAts [ 1 ] or c . infer ( argExprs [ 1 ] )
local raw = rawType ( at )
if raw . tag == "const" then
knownAts = { raw . inner }
end
end





if calleeName == "setmetatable" and calleeT . tag ~= "func" then
c . checkMetatableLiteral ( argExprs [ 2 ] , nil , T . metatable ( T . any ) )
end
local first , rets , pack = c . inferCall ( node , calleeT , node . args , knownAts )
forwardProtocol ( node )
if selectedExport
and selectedExport . module == "nupp.simd"
and selectedExport . member : match ( "^horizontal%." ) ~= nil
then
local vector = argExprs [ 1 ] and rawType ( c . infer ( argExprs [ 1 ] ) ) or nil
local nominal = nil
if vector and vector . tag == "nominal" then
nominal = vector
end
local origin = nil
if nominal then
origin = ( nominal . origin or nominal )
end
local element = origin
and origin . name == "Vector"
and ( origin . moduleName == "nupp.simd" or origin . sealedModule == "nupp.simd" )
and nominal
and nominal . typeArgs
and nominal . typeArgs [ 1 ]
or nil
local operation = selectedExport . member : match ( "^horizontal%.(.+)$" )




local named = ( operation or "" )
local extremum = named : match ( "^propagating" ) ~= nil or named : match ( "^number" ) ~= nil
local indexed = named : match ( "Arg" ) ~= nil



local integerContract = named == "wrappingSum"
or named == "wrappingProduct"
or named == "andBits"
or named == "orBits"
or named == "xorBits"
or named == "integerMin"
or named == "integerMax"
local floating = element ~= nil and ( element . tag == "float" or element . tag == "number" )
if element and indexed then
( node ) . simdHorizontal = selectedExport . member
elseif element and integerContract and floating then
c . diag ( "NUPP2006" , argExprs [ 1 ] , "simd.horizontal." .. named .. " requires an integer vector" )
elseif element and ( integerContract or extremum or floating ) then


local answered = ( element . tag == "uint8" or element . tag == "uint16" ) and T . uint32
or ( element . tag == "int8" or element . tag == "int16" ) and T . int32
or element
first , rets , pack = answered , { answered } , T . pack ( { answered } )
if answered . tag ~= "number" then
c . fixedWidth . mark ( node , answered )
end
( node ) . simdHorizontal = selectedExport . member
elseif element then
c . diag ( "NUPP2006" , argExprs [ 1 ] , "explicit SIMD horizontal arithmetic requires a floating-point vector" )
end
end
local globalsForAssert = c . env and c . env . globals
local stableAssert = calleeName == "assert"
and globalsForAssert
and c . lookupEntry ( "assert" ) == globalsForAssert . assert
if stableAssert then
local input = node . argumentPack and T . packAt ( node . argumentPack , 1 ) or T . any
local truthy = narrowing . truthiness ( input )
if input ~= T . any then
first = truthy or T . never
rets = { first }
pack = T . pack ( rets )
local dynamicNode = node
dynamicNode . assertNever = first == T . never
end
end
if node . kind == "call" and stringFormatIntrinsic ( c , callee ) then
local format = literalString ( argExprs [ 1 ] )
local plan = format and debugFormatPlan ( format ) or nil
if positionalOnly ( argExprs ) and plan then
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
do break end
end
end
callee . overloadMember = callee . overloadMember or selectedMember
end
if wrappedEntry and wrappedEntry . wrappedProtocol then
wrappedEntry . wrappedPhase = "started"
end
local globalEntry = calleeName ~= "" and c . env and c . env . globals and c . env . globals [ calleeName ] or nil
local stableGlobal = globalEntry and calleeEntry and globalEntry . definition == calleeEntry . definition
node . resolvedGlobal = stableGlobal and calleeName or nil
if stableGlobal and ( calleeName == "assert" or calleeName == "error" ) then
node . aotGuardBuiltin = calleeName
end
if stableGlobal and calleeName == "select" and node . argumentPack then
local source = node . argumentPack
local selector = argExprs [ 1 ]
local selectorToken = selector
and ( selector . kind == "string" or selector . kind == "number" )
and selector . token
or nil
local selectorText = selectorToken and selectorToken . text or ""
if selector and selector . kind == "string" and ( selectorText == "\"#\"" or selectorText == "'#'" ) then
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
if # elements > 0
and ( not argExprs [ 2 ] or integerLiteral ( argExprs [ 2 ] ) )
and ( not argExprs [ 3 ] or through )
then
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
if stableMember and baseName == "coroutine" or isCoroutine then
local intrinsic = isCoroutine and "yield" or memberName
node . coroutineIntrinsic = intrinsic
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
or not supplied . tail and # supplied . head == # expected . head
if not ok or not exact then
c . diag (
"NUPP2010" ,
argExprs [ offset + 1 ] or node ,
why or ("coroutine pack has %d values, expected %d") : format ( # supplied . head , # expected . head )
)
end
end

if intrinsic == "create" then
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
elseif intrinsic == "resume" then
local threadType = T . packAt ( actual , 1 )
if threadType and threadType . tag == "protocolThread" then
local threadArg = argExprs [ 1 ]
local threadEntry = threadArg
and threadArg . kind == "name"
and threadArg . token
and c . lookupEntry ( threadArg . token . text )
or nil




local phase = threadEntry and threadEntry . threadPhase or "unknown"
if phase == "dead" then
c . diag ( "NUPP2010" , threadArg or node , "a coroutine narrowed to dead cannot be resumed" )
end
local accepted = phase == "new" and threadType . startPack
or phase == "started" and threadType . resumePack
or phase == "dead" and threadType . resumePack
or T . packUnion ( { threadType . startPack , threadType . resumePack } )
if accepted . alternatives then
local fits = false
local suppliedHead = { }
for j = 2 , # actual . head do
suppliedHead [ # suppliedHead + 1 ] = actual . head [ j ]
end
local supplied = T . pack ( suppliedHead , actual . tail )
for _ , arm in ipairs ( accepted . alternatives ) do
local armFits = packIsA ( supplied , arm )
and ( arm . tail ~= nil or not supplied . tail and # supplied . head == # arm . head )
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
elseif intrinsic == "yield" then
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
elseif intrinsic == "status" then
local threadArg = argExprs [ 1 ]
local threadEntry = threadArg
and threadArg . kind == "name"
and threadArg . token
and c . lookupEntry ( threadArg . token . text )
or nil
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
elseif intrinsic == "wrap" then
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
local definitions = readableField ( options , "definitions" )
local result = pegTyping . inferSourceResult ( source , definitions )
local matcher = result and pegMatcher ( result )
if matcher then
first , rets , pack = matcher , { matcher } , T . pack ( { matcher } )
end
end
end

if node . kind == "call" and callee and opensTaskScope ( c , callee ) and c . recordEffect then
local deadline = node . argumentPack and T . packAt ( node . argumentPack , 2 ) or nil
if deadline ~= nil and deadline ~= T . nil_ then
c . recordEffect ( "runtime.time" ) ;
( node ) . compilerFeatureEffect = "runtime.time"
end
end
local soaExport = node . kind == "call" and callee and callee . exactCallExport or nil
if soaExport
and soaExport . module == "nupp.mem.soa"
and ( soaExport . member == "allocate" or soaExport . member == "layoutof" )
then
local witness = argExprs [ 1 ] and rawType ( c . infer ( argExprs [ 1 ] ) ) or nil
local subject = witness and witness . tag == "ctype" and witness . of or nil
if not subject then
c . diag ( "NUPP2403" , argExprs [ 1 ] or node , "SoA storage needs a concrete ctype witness" )
else
local spec = soaLayoutSpec ( c , subject , argExprs [ 1 ] or node )
if spec then
node . soaLayout = spec
node . soaOperation = soaExport . member
end
end
end
local indexedExport = node . kind == "call" and callee and callee . exactCallExport or nil
if indexedExport and indexedExport . module == "nupp.mem.indexed" and indexedExport . member == "range" then
local views , valid = { } , # argExprs >= 3
for position = 3 , # argExprs do
local argument = argExprs [ position ]
local descriptor = argument and indexedViews . describe ( c . infer ( argument ) ) or nil
local definition = argument and argument . kind == "name" and argument . token and argument . token . definition
or nil
if not descriptor then
valid = false
c . diag ( "NUPP2403" , argument or node , "indexed.range requires a standard Span or SoA view" )
elseif not definition or not definition . constant then
valid = false
c . diag ( "NUPP2403" , argument or node , "indexed.range views must be const names" , nil , {
help = "bind the stable view to const before validating its range"
} )
else
views [ definition ] = descriptor
end
end
if # argExprs < 3 then
c . diag ( "NUPP2403" , node , "indexed.range requires at least one indexed view" )
end
if valid then
node . indexedRangeCall = { views = views , }
end
end
local indexedProducer = node . kind == "call"
and callee
and callee . exactCallExport
and indexedViews . exportProducer ( callee . exactCallExport . module , callee . exactCallExport . member , first )
or nil
if indexedProducer then
node . indexedViewProducer = { producer = indexedProducer , source = argExprs [ 1 ] , count = argExprs [ 2 ] , }
end
local globals = c . env and c . env . globals
local stableNupp = globals and c . lookupEntry ( "nupp" ) == globals . nupp
if stableNupp and baseName == "nupp" and memberName == "recoverAlias" then
if # argExprs == 1 then
local aliasType = managedGeneric ( "Alias" , T . unknown )
first = T . optional ( aliasType )
rets = { first , rets and rets [ 2 ] or T . any }
pack = T . pack ( rets )
node . recoverManagedAlias = true
end
end
if node . kind == "safeCall" then
local calledPack = pack or ( rets and T . pack ( rets ) or T . pack ( { } , { kind = "unknown" , type = T . any } ) )
pack = T . packUnion ( { calledPack , T . pack ( { T . nil_ } ) } )
first = T . optional ( first )
rets = pack . head
end
c . lastCallRets = rets
node . valuePack = pack or ( rets and T . pack ( rets ) or T . pack ( { } , { kind = "unknown" , type = T . any } ) )

return admitted ( node , first )
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
local indexedView = indexedViews . describe ( rawReceiver )
if indexedView and member . text == "slice" then
node . indexedViewOperation = { kind = "slice" , descriptor = indexedView , }
elseif indexedView and member . text == "shared" then
node . indexedViewOperation = { kind = "shared" , descriptor = indexedView , }
end
local staticOwner = ( rawReceiver . tag == "metatable" or rawReceiver . tag == "typeobject" )
and rawType ( rawReceiver . of )
or nil
local static = staticOwner
and staticOwner . tag == "nominal"
and staticOwner . staticByname
and staticOwner . staticByname [ member . text ]
if static then
local owner = staticOwner
c . diag (
"NUPP2004" ,
member ,
("%q is a static function and does not accept a receiver") : format ( member . text ) ,
nil ,
{ help = ("call it with `%s.%s(...)`") : format ( owner . name , member . text ) }
)
local first , rets , pack = c . inferCall ( node , static , node . args )
forwardProtocol ( node )
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
do break end
end
end
end
c . markToken ( member , fieldDef , mt , callable and "method" or "property" )
member . additionalDefinitions = fieldDefs



if callable and rawReceiver . tag == "const" then
local signatures = mt . tag == "intersection" and mt . members or { mt }
local accepts = false
for _ , signature in ipairs ( signatures ) do
local selfParam = signature . tag == "func" and signature . params [ 1 ] or nil
if not selfParam
or selfParam == T . any
or selfParam == T . unknown
or rawType ( selfParam ) . tag == "const"
then
accepts = true
do break end
end
end
if not accepts then
c . diag (
"NUPP2006" ,
receiver ,
("receiver: %s is read-only; %s does not take a const self")

: format ( T . tostring ( rawReceiver ) , member . text ) ,
nil ,
{ help = "declare the receiver as `self: const T`, or call the method on a mutable value" }
)
end
end

local methodType = callable and specializeReceiver ( mt , ot ) or mt
local nominal = rawReceiver . tag == "nominal" and rawReceiver or nil
if not nominal and rawReceiver . tag == "intersection" then
for _ , candidate in ipairs ( rawReceiver . members ) do
if candidate . tag == "nominal" then
local candidateNominal = candidate
local candidateOrigin = ( candidateNominal . origin or candidateNominal )
if (
candidateOrigin . moduleName or candidateNominal . moduleName or candidateOrigin . sealedModule
) == "nupp.mem.soa"
and candidateOrigin . name == "WriteSpan"
then
nominal = candidateNominal
do break end
end
end
end
end
local origin = nominal and ( ( nominal . origin or nominal ) ) or nil
local spanElement = nil
if nominal and origin and origin . moduleName == "nupp.mem.span" and nominal . typeArgs then
spanElement = nominal . typeArgs [ 1 ]
end
if callable and member . text == "set" and spanElement and fixedWidth . isPhysical ( spanElement ) then


node . fixedWidthPhysicalParameters = { [ 2 ] = true }
end
local callArgs = node . args







local originModule = origin
and ( origin . moduleName or ( nominal and nominal . moduleName ) or origin . sealedModule )
or nil
local publicName = originModule and ( originModule ) or nil
local surfaceModule = publicName and COMPILER_SURFACES [ publicName ] or nil
local surfaceNominal = surfaceModule and origin and surfaceModule [ origin . name ] or nil
local surface = surfaceNominal and surfaceNominal [ member . text ] or nil
if surface and surface . effect and c . recordEffect then
c . recordEffect ( surface . effect ) ;
( node ) . compilerFeatureEffect = surface . effect
end
local originalExprs = callArgs and callArgs . kind == "args" and ( callArgs ) . exprs or nil
local rotated = surface ~= nil and surface . rotate == true and originalExprs ~= nil and # originalExprs > 0
if rotated and surface and originalExprs then
local callableArgument = originalExprs [ # originalExprs ]
if surface . sendableLast
and ( callableArgument . kind == "funcExpr" or callableArgument . kind == "shortfn" )
then
local sendableArgument = callableArgument
sendableArgument . sendableContext = true
end
local reordered = { callableArgument }
for index = 1 , # originalExprs - 1 do
reordered [ # reordered + 1 ] = originalExprs [ index ]
end
( callArgs ) . exprs = reordered
local rotatedNode = node
rotatedNode . trailingCallableCall = true
rotatedNode . trailingCallableMember = member . text
if surface . bodyMayBorrowScope then
local scopeEntry = c . ownershipEntry ( receiver )
rotatedNode . bodyScopeRoot = scopeEntry and c . borrowRoot ( scopeEntry ) or nil
end
end
local first , rets , pack = c . inferCall ( node , callable and dropSelf ( methodType ) or methodType , callArgs )
forwardProtocol ( node )
if rotated and originalExprs then
( callArgs ) . exprs = originalExprs
end
if rotated and surface and surface . overloadMembers then


local chosen = ( node ) . overloadWinner
for index , candidate in ipairs ( ( node ) . overloadCandidates or { } ) do
if candidate == chosen then
local routed = surface . overloadMembers [ index ]
if routed ~= nil then
( node ) . trailingCallableMember = routed
end
end
end
end
if nominal ~= nil
and origin ~= nil
and ( origin . moduleName or ( nominal ) . moduleName or origin . sealedModule ) == "nupp.simd"
and origin . name == "Vector"
and member . text == "extract"
and ( nominal ) . typeArgs
then
local concrete = nominal
local element = T . unwrapOwnership ( ( concrete . typeArgs ) [ 1 ] )
local widened = ( element . tag == "uint8" or element . tag == "uint16" ) and T . uint32
or ( element . tag == "int8" or element . tag == "int16" ) and T . int32
or nil
if widened then
first , rets , pack = widened , { widened } , T . pack ( { widened } )
c . fixedWidth . mark ( node , widened )
end
end
local indexedProducer = callable and indexedViews . methodProducer ( rawReceiver , member . text , first ) or nil
if indexedProducer then
node . indexedViewProducer = { producer = indexedProducer , source = receiver , }
end
local literal = receiver
while literal and literal . kind == "paren" do
literal = literal . expr
end
local methodArgs = node . args and node . args . kind == "args" and ( node . args ) . exprs or { }
local positional = positionalOnly ( methodArgs )
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
node . overloadMember = pegReplacementMember (
ot ,
member . text ,
node . argumentPack and T . packAt ( node . argumentPack , 2 ) or nil
)
local aliasDeclaration = c . lookupType ( "nupp.Alias" )
local aliasOrigin = aliasDeclaration
and aliasDeclaration . tag == "nominal"
and ( ( aliasDeclaration . origin or aliasDeclaration ) )
or nil
if origin and aliasOrigin and origin == aliasOrigin and member . text == "take" then
local capability = nominal and nominal . typeArgs and nominal . typeArgs [ 1 ] or nil
if capability and c . ownershipKind ( capability ) == "affine" then
local returned = T . withOwnershipPayload ( capability , T . optional ( rawType ( capability ) ) )
first = returned
rets = { returned , rets and rets [ 2 ] or T . any }
pack = T . pack ( rets )
node . resourceCapability = capability
end
elseif origin and aliasOrigin and origin == aliasOrigin and member . text == "downcast" then
local typeArgs = node . typeArgs or { }
if # typeArgs ~= 1 then
c . diag ( "NUPP2613" , node , "alias.downcast expects one explicit target type" )
else
local requested = c . resolveType ( typeArgs [ 1 ] )
local capability = c . capabilityOf ( requested )
if # T . capabilityCleanups ( capability ) == 0 then
c . diag ( "NUPP2613" , typeArgs [ 1 ] , "alias.downcast requires an exactly droppable owner type" )
else
local aliasType = managedGeneric ( "Alias" , requested )
first = T . optional ( aliasType )
rets = { first , rets and rets [ 2 ] or T . any }
pack = T . pack ( rets )
node . managedAliasPolicy = policyFor ( requested )
end
end
end
if owner . tag == "nominal"
and owner . overloadedMethods
and owner . overloadedMethods [ member . text ]
and node . overloadWinner
then
local selectedMember = methodslots . member ( member . text , node . overloadWinner )
local dispatch = owner . methodDispatchEntries and owner . methodDispatchEntries [ member . text ]
or ( owner . methodEntries and owner . methodEntries [ member . text ] )
or { }
for _ , entry in ipairs ( dispatch ) do
local candidate = dropSelf ( specializeSelf ( owner , entry . signature , owner ) )
if candidate . id == node . overloadWinner . id or entry . member == selectedMember then
receiverMode = entry . signature . paramModes [ 1 ] or "plain"
node . overloadMember = entry . member
node . methodEntry = entry
c . markToken ( member , entry . definition , specializeSelf ( owner , entry . signature , owner ) , "method" )
member . additionalDefinitions = nil
do break end
end
end
node . overloadMember = node . overloadMember or selectedMember
end
if receiverMode ~= "takes" then



local receiverEntry = c . ownershipState ( ( c . ownershipEntry ( receiver ) ) )
if receiverEntry and receiverEntry . movedFields and next ( receiverEntry . movedFields ) then
c . diag ( "NUPP2602" , receiver , "a partially moved record cannot be borrowed as a whole" , nil , {
help = "borrow the fields that remain, or refill the moved field first"
} )
end
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
if c . ownershipKind ( ot ) == "affine" then
c . own . expireTemporaryAfterStatement ( receiver )
end
local entry , nameNode = c . ownershipEntry ( receiver )
entry = c . ownershipState ( entry )
local entryFacts = entry and c . own . capabilityFacts ( entry , nil , false ) or nil
local regionRoot , regionPath = c . regionOf ( receiver )
local roots = entry and { entry } or c . own . provenanceOwners ( receiver )
local base = entry or c . own . pathBase ( receiver )
if # roots == 0 and c . ownershipKind ( ot ) ~= "affine" then
c . diag ( "NUPP2602" , receiver , "an exclusive receiver requires a named or rooted value" )
else
for _ , root in ipairs ( roots ) do
if c . own . regionBlocked ( root , base , entryFacts , regionRoot , regionPath , false ) then
c . diag (
"NUPP2607" ,
nameNode or receiver ,
"an exclusive receiver cannot invalidate a value while a derived borrow is live" ,
nil ,
c . own . conflictDetails ( regionRoot or root , regionPath )
)
do break end
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
if c . ownershipKind ( ot ) == "affine" then
c . own . expireTemporaryAfterStatement ( receiver )
end
local entry , nameNode = c . ownershipEntry ( receiver )
entry = c . ownershipState ( entry )
local entryFacts = entry and c . own . capabilityFacts ( entry , nil , false ) or nil
local regionRoot , regionPath = c . regionOf ( receiver )
local roots = entry and { entry } or c . own . provenanceOwners ( receiver )
local base = entry or c . own . pathBase ( receiver )
for _ , root in ipairs ( roots ) do
if c . own . regionBlocked ( root , base , entryFacts , regionRoot , regionPath , true ) then
c . diag (
"NUPP2607" ,
nameNode or receiver ,
"a shared receiver cannot overlap a live exclusive view" ,
nil ,
c . own . conflictDetails ( regionRoot or root , regionPath , true )
)
do break end
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





local named = ot
local underlying = rawType ( ot ) . tag
if named . tag ~= "shape"
and named . tag ~= "nominal"
and ( underlying == "shape" or underlying == "nominal" )
then
local terminal = false
for _ , cleanup in ipairs ( ( ot ) . cleanups or { } ) do
if cleanup . name == member . text then
terminal = true
end
end
if not terminal then
named = rawType ( ot )
end
end

local receiverDetails = receiver
while receiverDetails . kind == "paren" and receiverDetails . expr do
receiverDetails = receiverDetails . expr
end


local receiverType = rawType ( named )

local function stringLike ( t ) 
if t == T . string or t . tag == "literal" and t . base == T . string then
return true
end
if t . tag ~= "union" then
return false
end
for _ , alternative in ipairs ( t . members ) do
if not stringLike ( alternative ) then
return false
end
end

return true
end

local gradual = receiverType == T . any or receiverType == T . table_ or receiverType . tag == "map"



local ownedNominal = named ~= receiverType and receiverType . tag == "nominal" and named . tag ~= "borrowed"




if not receiverDetails . primitiveUntrusted
and not gradual
and not ownedNominal
and not stringLike ( receiverType )
and receiverType ~= T . never
then
local fixes = ( named . tag == "shape" or named . tag == "nominal" )
and c . edits . nameSpellingFix ( member , c . fieldNames ( named ) )
or nil
local help = fixes and "use the suggested method spelling"
or "check the receiver type and available methods"
if receiverType . tag == "union" then
local maybeNil = false
for _ , alternative in ipairs ( receiverType . members ) do
if alternative == T . nil_ then
maybeNil = true
end
end
help = maybeNil
and ("the receiver may be nil: test it first, or call it as `?.:%s(...)`") : format ( member . text )
or "not every alternative has this method: narrow the receiver first"
elseif receiverType == T . unknown then
help = "narrow the unknown value with a test or an `is` check first"
elseif receiverType . tag == "typevar" then
help = "bound the type parameter by a type that declares this method"
end
c . diag ( "NUPP2004" , member , ("no method %q in %s") : format ( member . text , T . tostring ( named ) ) , fixes , {
help = help
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

local __nuppExportValue= callexpr ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.callexpr"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.callexpr"]=__nuppExports;return __nuppExports