_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);



















local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.relations" )
local consteval = require ( "nupp.compiler.consteval" )
local lints = require ( "nupp.compiler.lints" )
local fixits = require ( "nupp.compiler.check.fixits" )
local annotate = require ( "nupp.compiler.check.annotate" )
local ownership = require ( "nupp.compiler.check.ownership" )
local loopclosure = require ( "nupp.compiler.check.loopclosure" )
local undocumentedraise = require ( "nupp.compiler.check.undocumentedraise" )
local unused = require ( "nupp.compiler.check.unused" )
local discard = require ( "nupp.compiler.check.discard" )
local nosuspendMod = require ( "nupp.compiler.check.nosuspend" )
local aotMod = require ( "nupp.compiler.check.aot" )
local effectregionsMod = require ( "nupp.compiler.check.effectregions" )
local analysis = require ( "nupp.compiler.analysis" )
local narrow = require ( "nupp.compiler.check.narrow" )
local fixedWidthCheck = require ( "nupp.compiler.check.fixed_width" )
local calls = require ( "nupp.compiler.check.calls" )
local expr = require ( "nupp.compiler.check.expr" )
local declare = require ( "nupp.compiler.check.declare" )
local resolve = require ( "nupp.compiler.check.resolve" )
local bindings = require ( "nupp.compiler.check.bindings" )
local control = require ( "nupp.compiler.check.control" )
local functions = require ( "nupp.compiler.check.functions" )
local cdef = require ( "nupp.compiler.check.cdef" )
local pragma = require ( "nupp.compiler.check.pragma" )
local derive = require ( "nupp.compiler.check.derive" )
local metatable = require ( "nupp.compiler.check.metatable" )
local cst = require ( "nupp.compiler.cst" )
local annotationMod = require ( "nupp.compiler.annotations" )
local state = require ( "nupp.compiler.check.state" )
local generics = require ( "nupp.compiler.generics" )
local methodslots = require ( "nupp.compiler.methodslots" )
local comptime = require ( "nupp.compiler.comptime" )
local typeblueprint = require ( "nupp.compiler.typeblueprint" )
local reflection = require ( "nupp.compiler.reflection" )
local hash = require ( "nupp.compiler.build.hash" )
local stable = require ( "nupp.compiler.build.cache" ) . stable

local checkMod = { }






























checkMod . lints = lints . all
checkMod . lintCategories = lints . categories
checkMod . lintLevels = lints . levels
checkMod . lintOptIn = lints . optIn
checkMod . lintLevel = lints . level
checkMod . lintFor = lints . get



local REIFIABLE_PRIM = {
number = true ,
float = true ,
boolean = true ,
integer = true ,
int8 = true ,
int16 = true ,
int32 = true ,
int64 = true ,
uint8 = true ,
uint16 = true ,
uint32 = true ,
uint64 = true ,
}


local function reifiableField ( t , isCdef )






if t . tag == "projection" then
local reduced = require ( "nupp.compiler.generics" ) . normalize ( t )
if reduced . cycle then


return true
end

return reduced . type . tag ~= "projection" and reifiableField ( reduced . type , isCdef ) or false
end
if REIFIABLE_PRIM [ t . tag ] then
return true
end


if isCdef and ( t . tag == "cstring" or t . tag == "voidptr" ) then
return true
end
if t . tag == "nominal" and t . declKind == "struct" then
return true
end




if t . tag == "carray" and t . count then
return reifiableField ( t . elem , isCdef )
end
if t . tag == "ptr" then
return true
end
if t . tag == "union" and # t . members == 2 and t . hasNil then
local other = t . members [ 1 ] == T . nil_ and t . members [ 2 ] or t . members [ 1 ]


if other . tag == "ptr" then
return true
end
if isCdef and ( other == T . voidptr or other == T . cstring ) then
return true
end
return false
end

return false
end


















function checkMod . strictByDefault ( filename )
if not filename then
return true
end
return not ( filename : match ( "%.g%.nupp$" ) or filename : match ( "%.d%.nupp$" ) or filename : match ( "%.lua$" ) )
end



local TYPED_LAYER

= {
recordDecl = "a type declaration" ,
typeAlias = "a type alias" ,
castExpr = "an `as` cast" ,
tname = "a type annotation" ,
tarray = "a type annotation" ,
tmap = "a type annotation" ,
tshape = "a type annotation" ,
ttuple = "a type annotation" ,
tunion = "a type annotation" ,
tintersection = "a type annotation" ,
topt = "a type annotation" ,
tfunc = "a type annotation" ,
tpack = "a type annotation" ,
tparen = "a type annotation" ,
tptr = "a type annotation" ,
tcarray = "a type annotation" ,
tconst = "a type annotation" ,
tliteral = "a type annotation" ,
tborrows = "a type annotation" ,
tpreserves = "a type annotation" ,
tpredicate = "a type annotation" ,
ternary = "a type annotation" ,
}











local function reportTypedLayer ( c , node )
if type ( node ) ~= "table" or cst . isToken ( node ) then
return
end
local named = TYPED_LAYER [ node . kind ]
if named then
c . diag ( "NUPP1006" , node , named .. " is not plain Lua" )
return
end
for _ , child in ipairs ( node ) do
reportTypedLayer ( c , child )
end
end




local function bodyOf ( value )
if not value or cst . isToken ( value ) then
return nil
end
if value . kind == "funcbody" then
return value
end
if value . kind == "funcExpr" or value . kind == "shortfn" then
return value . body
end

return nil
end










local function provenNonYielding ( node , body )
local contract = node and node . effectContract or body and body . effectContract
if contract and contract . yields ~= nil then
return contract . yields ~= true
end
local summary = body and body . effectSummary
if not summary then
return false
end
if summary . yields == true then
return false
end
if summary . top == true or summary . external == true then




local visited = { }
local function callsAreNonYielding ( current )
if not current or cst . isToken ( current ) then
return true
end
if visited [ current ] then
return true
end
visited [ current ] = true
local kind = current . kind
if current ~= body and (
kind == "funcExpr" or kind == "shortfn" or kind == "localFuncStmt" or kind == "funcStmt"
) then
return true
end
if kind == "call" or kind == "safeCall" or kind == "methodCall" then
local call = current
local target = call . calleeType or call . signatureType
if not call . ownershipIntrinsic and ( not target or target . tag ~= "func" or not target . noYield ) then
return false
end
end
for _ , child in ipairs ( ( current ) . stats or { } ) do
if not callsAreNonYielding ( child ) then
return false
end
end
for _ , child in ipairs ( current ) do
if not callsAreNonYielding ( child ) then
return false
end
end

return true
end

return callsAreNonYielding ( body )
end

return true
end











local function qualifyExport ( t , value )
if not t then
return t
end
if t . tag == "func" then






local body = bodyOf ( value )
local contract = value and not cst . isToken ( value ) and value . effectContract or nil
if not body and not contract then
return t
end

return T . withYields ( t , not provenNonYielding ( value , body ) )
end




if t . tag == "shape" and t . indexReadKey == nil and t . indexWriteKey == nil and value and not cst . isToken (
value
) and value . kind == "tableExpr" then
local written = { }
for _ , field in ipairs ( value . fields or { } ) do
if field . kind == "fieldNamed" and field . name and field . value then
written [ field . name . text ] = field . value
end
end
local fields = { }
for _ , field in ipairs ( t . fields or { } ) do
local paired = written [ field . name ]
fields [
# fields + 1
] = {
name = field . name ,
read = field . read and qualifyExport ( field . read , paired ) or nil ,
write = field . write and qualifyExport ( field . write , paired ) or nil ,
type = field . type and qualifyExport ( field . type , paired ) or nil ,
}
end

return T . shape ( fields , nil , true )
end

return t
end









local function couldCarryPublicCapability ( t )
if not t or t == T . any or t == T . unknown then


return false
end
if t . tag == "affine" or t . tag == "borrowed" or t . tag == "pinned" then
return true
elseif t . tag == "typevar" then
return not t . bound or couldCarryPublicCapability ( t . bound )
elseif t . tag == "union" or t . tag == "intersection" then
for _ , member in ipairs ( t . members or { } ) do
if couldCarryPublicCapability ( member ) then
return true
end
end
elseif t . tag == "nominal" then
return t . affineFields ~= nil and # t . affineFields > 0 or t . fieldBorrowSources ~= nil
elseif t . tag == "tuple" then
for _ , member in ipairs ( t . elems or { } ) do
if couldCarryPublicCapability ( member ) then
return true
end
end
end

return false
end

local function requirePublicCapabilityContracts ( c )




if c . result . moduleName and c . result . moduleName : match ( "^nupp%.compiler" ) then
return
end
for name , exported in pairs ( c . moduleFields or { } ) do
local signatures = exported . tag == "intersection" and exported . members or { exported }
for _ , signature in ipairs ( signatures ) do
if signature . tag == "func" then
local implicitCapabilityParams = { }
for parameter , t in ipairs ( signature . params or { } ) do
if couldCarryPublicCapability ( t ) and signature . paramModes [ parameter ] == "plain" then
implicitCapabilityParams [ parameter ] = true
c . diag (
"NUPP2610" ,
c . moduleFieldTokens [ name ] or c . moduleReturnValue ,
(
"exported capability-bearing parameter #%d of %q needs an explicit mode"
) : format ( parameter , name ) ,
nil ,
{ help = "write takes, borrows, exclusive, or scoped as part of the public contract" }
)
end
end
for result = 1 , # signature . rets do
local source = signature . preservesResults and signature . preservesResults [ result ]
if source and couldCarryPublicCapability (
signature . params [ source ]
) and not implicitCapabilityParams [
source
] and not ( signature . explicitPreserves and signature . explicitPreserves [ result ] ) then
c . diag (
"NUPP2610" ,
c . moduleFieldTokens [ name ] or c . moduleReturnValue ,
(
"exported capability result #%d of %q must spell `preserves %s`"
) : format ( result , name , signature . paramNames [ source ] or ( "parameter" .. tostring ( source ) ) ) ,
nil ,
{ help = "write preserves source on the public result type" }
)
end
end
end
end
end
end

local function finalizeBoundary ( c )
if not c . moduleType then
return
end
requirePublicCapabilityContracts ( c )


if c . moduleTypeFromFields then
local fields = { }
for name , ft in pairs ( c . moduleFields ) do
local qualified = qualifyExport ( ft , c . moduleFieldValues [ name ] )
c . moduleFields [ name ] = qualified
if c . moduleFieldConst [ name ] then
fields [ # fields + 1 ] = { name = name , read = qualified }
else
fields [ # fields + 1 ] = { name = name , type = qualified }
end
end
if # fields > 0 then
c . moduleType = T . shape ( fields )
end
return
end




c . moduleType = qualifyExport ( c . moduleType , c . moduleReturnValue )
end



local function finalizeCallGuarantees ( c , queries )
local published = { }
local function localSummary ( value )
if not value or cst . isToken ( value ) then
return nil
end
if value . kind == "funcbody" then
return value . effectSummary
elseif value . kind == "funcExpr" or value . kind == "shortfn" then
return value . body and value . body . effectSummary
elseif value . kind == "name" and value . token and queries then
local known = queries . known ( value . token )
return known and known . summary or nil
end

return nil
end

local function imported ( value )
local exact = value and not cst . isToken ( value ) and value . exactCallExport or nil
if not exact and value and not cst . isToken (
value
) and value . kind == "name" and value . token and value . token . definition then
exact = value . token . definition . exactCallExport
end
if not exact or not c . env or not c . env . resolveCallGuarantees then
return nil
end

return c . env . resolveCallGuarantees ( c . env , exact . module , exact . member )
end

local function publish ( member , value )
local summary = localSummary ( value )
local source = not summary and imported ( value ) or nil
if summary or source then
local noAllocate , noRaise
if source then
noAllocate , noRaise = source . noAllocate , source . noRaise
else
noAllocate = not summary . top and summary . allocates ~= true and true or nil
noRaise = not summary . top and summary . raises ~= true and true or nil
end
published [
member
] = {
identity = source and source . identity or (
( c . result . moduleName or c . filename or "<module>" ) .. "." .. member
) ,
noAllocate = noAllocate ,
noRaise = noRaise ,
}
end
end

for member , value in pairs ( c . moduleFieldValues or { } ) do
publish ( member , value )
end
local returned = c . moduleReturnValue
if returned and not cst . isToken ( returned ) and returned . kind == "tableExpr" then
for _ , field in ipairs ( returned . fields or { } ) do
if field . kind == "fieldNamed" and field . name and field . value then
publish ( field . name . text , field . value )
end
end
elseif returned then
publish ( "$return" , returned )
end
c . moduleExports . callGuarantees = published
end





local function finalizeNominalEffects ( c )
local function matchingSurface ( entry , surface , static )
if not surface then
return nil
end
local candidates = surface . tag == "intersection" and surface . members or { surface }
for _ , candidate in ipairs ( candidates ) do
local callable = static and candidate or generics . dropSelf ( candidate )
if callable . tag == "func" and methodslots . parameters ( callable ) == entry . parameterKey then
return candidate
end
end

return # candidates == 1 and candidates [ 1 ] or nil
end

local function qualifyEntry ( entry , surface )
local declaration = entry and entry . declaration
local body = declaration and declaration . body
if not body then
return surface or entry and entry . signature
end




local qualified = qualifyExport ( surface or entry . signature , body )
entry . signature = qualified
if entry . definition then
entry . definition . type = qualified
end

return qualified
end

for ownerType in pairs ( c . nominalEffectOwners or { } ) do
local owner = ownerType
for name , entries in pairs ( owner . methodDispatchEntries or { } ) do
local members , seen = { } , { }
local surface = owner . byname [ name ]
for _ , entry in ipairs ( entries ) do
local qualified = qualifyEntry ( entry , matchingSurface ( entry , surface , false ) )
if qualified and not seen [ entry . member ] then
seen [ entry . member ] = true
members [ # members + 1 ] = qualified
end
end
if # members > 0 then
local combined = # members == 1 and members [ 1 ] or T . intersection ( members )
owner . byname [ name ] = combined
owner . writeByname [ name ] = combined
end
end
for name , entries in pairs ( owner . staticEntries or { } ) do
local members = { }
local surface = owner . staticByname [ name ]
for _ , entry in ipairs ( entries ) do
members [ # members + 1 ] = qualifyEntry ( entry , matchingSurface ( entry , surface , true ) )
end
if # members > 0 then
local combined = # members == 1 and members [ 1 ] or T . intersection ( members )
owner . staticByname [ name ] = combined
owner . staticWriteByname [ name ] = combined
end
end
end



for _ , entry in ipairs ( c . nominalEffectEntries or { } ) do
local inlineEntries = entry . static and entry . owner . staticEntries and entry . owner . staticEntries [
entry . member
] or entry . owner . methodDispatchEntries and entry . owner . methodDispatchEntries [ entry . member ]
if not inlineEntries or # inlineEntries == 0 then
local qualified = qualifyExport ( entry . signature , entry . body )
local reads = entry . static and entry . owner . staticByname or entry . owner . byname
local writes = entry . static and entry . owner . staticWriteByname or entry . owner . writeByname
reads [ entry . member ] = qualified
writes [ entry . member ] = qualified
if entry . definition then
entry . definition . type = qualified
end
end
end





local parts , seen = { } , { }
local function effect ( t , method )
if not t then
return nil
end
if t . tag == "func" then
local callable = method and generics . dropSelf ( t ) or t
return methodslots . parameters ( callable ) .. "=" .. ( t . noYield and "quiet" or "may-yield" )
end
if t . tag == "intersection" then
local members = { }
for _ , member in ipairs ( t . members or { } ) do
if member . tag ~= "func" then
return nil
end
local callable = method and generics . dropSelf ( member ) or member
members [
# members + 1
] = methodslots . parameters ( callable ) .. "=" .. ( member . noYield and "quiet" or "may-yield" )
end
table . sort ( members )
return # members > 0 and table . concat ( members , "," ) or nil
end

return nil
end

local function visit ( nominal , path )
if seen [ nominal ] then
return
end
seen [ nominal ] = true
local function record ( which , members , method )
local names = { }
for name , member in pairs ( members ) do
if effect ( member , method ) then
names [ # names + 1 ] = name
end
end
table . sort ( names )
for _ , name in ipairs ( names ) do
local answer = effect ( members [ name ] , method )
if answer then
parts [ # parts + 1 ] = path .. ":" .. which .. ":" .. name .. "=" .. answer
end
end
end

record ( "byname" , nominal . byname or { } , true )
record ( "staticByname" , nominal . staticByname or { } , false )
for _ , name in ipairs ( nominal . fieldOrder or { } ) do
local default = nominal . fieldDefaults and nominal . fieldDefaults [ name ] or nil
if default then
parts [ # parts + 1 ] = path .. ":default:" .. name .. "=" .. stable ( default . value )
end
end
local nested = { }
for name in pairs ( nominal . nestedTypes or { } ) do
nested [ # nested + 1 ] = name
end
table . sort ( nested )
for _ , name in ipairs ( nested ) do
local child = nominal . nestedTypes [ name ]
if child and child . tag == "nominal" then
visit ( child , path .. "." .. name )
end
end
end

local names = { }
for name in pairs ( c . moduleExports . types or { } ) do
names [ # names + 1 ] = name
end
table . sort ( names )
for _ , name in ipairs ( names ) do
local exported = c . moduleExports . types [ name ]
if exported . tag == "nominal" then
visit ( exported , name )
end
end
c . moduleExports . nominalEffectFingerprint = table . concat ( parts , "\0" )
end



function checkMod . check (
result ,
filename ,
env ,
opts
)
opts = opts or { }
if opts . strict == nil then


opts . strict = not opts . declarationFile and checkMod . strictByDefault ( filename )
end
result . symbols = { }
result . implicitSideEffects = { }


result . effects = { }
result . preludeRuntime = env and env . preludeRuntime or nil
result . moduleName = opts and opts . moduleName or env and env . moduleNameForPath and env . moduleNameForPath (
env ,
filename
) or nil
local registry = opts and opts . annotations or env and env . annotations or annotationMod . default ( )
annotationMod . hydrateBuiltins ( registry , T )
if env then
annotationMod . bindBuiltinDeclarations ( registry , env . globalTypes , env . globalTypeDefs )
end
registry : removeSource ( filename )



local c = setmetatable({ result =
result ,  filename =
filename ,  env =
env ,  opts =
opts ,  reducerMemo =
{ } ,  comptimeDepth =
0 ,  comptimeFunctionDepth =
0 ,  comptimeFunctions =
{ } ,  typeFunctionMemo =
{ } ,  declarationFile =




(
opts and ( opts . declarationFile or opts . declareGlobals )
) and true or ( filename and filename : match ( "%.d%.nupp$" ) ) and true or false ,  moduleLocal =


cst . returnedLocal ( result . root ) ,  annotationRegistry =
registry ,  annotationDefinitions =
{ } ,  lintConfig =
opts and opts . lints or env and env . config and env . config . lints or nil ,  edits =



fixits . new ( result , env ) ,  diags =
{ } ,  moduleType =
nil ,  moduleExports =
opts and opts . initialExports or {
types = { } ,
typeDefs = { } ,
values = { } ,
valueDefs = { } ,
comptimeFunctions = { } ,
callGuarantees = { } ,
} ,  seenDefinitions =
{ } ,  scope =
{
vars = { } ,
types = { } ,
packTypes = { } ,
typeDefs = { } ,
pending = { } ,
automaticOwners = { } ,
depth = 0 ,
completionScope = result . root ,
parent = nil
} ,  retStack =
{ } ,  retPackStack =
{ } ,  ownReturnStack =
{ } ,  borrowReturnStack =
{ } ,  varargPackStack =
{ } ,  yieldPackStack =
{ } ,  resumePackStack =
{ } ,  protocolStack =
{ } ,  consumingFieldStack =
{ } ,  validatedCleanupContracts =
{ } ,  unsafeDepth =
0 ,  noSuspendDepth =
0 ,  effectRegionDepths =
{ allocates = 0 , raises = 0 } ,  handledDepth =
0 ,  functionDepth =
0 ,  functionBodies =
{ } ,  jitHazards =
{ } ,  scopedCaptureDepth =
0 ,  closureCaptureStack =
{ } ,  captureWatches =
{ } ,  allowed =
{ } ,  nextStat =
nil ,  hoisting =
false ,  resolvingAlias =
{ } ,  lastCallRets =
nil ,  moduleFields =
{ } ,  moduleFieldTokens =
{ } ,  moduleFieldDefs =
{ } ,  qualifiedFunctionEntries =
{ } ,  moduleFunctionDeclarations =
{ } ,  moduleFieldConst =
{ } ,  moduleFieldValues =
{ } ,  nominalEffectOwners =
{ } ,  nominalEffectEntries =
{ } ,  constModulePaths =
{ } ,  moduleLocalAnnotated =
false }, state.Checker)

c . rootScope = c . scope
c . moduleExports . valueDefs = c . moduleExports . valueDefs or { }
c . moduleExports . comptimeFunctions = c . moduleExports . comptimeFunctions or { }



c . cDeclared = { }
c . cDefinedFunctions = { }
c . recordEffect = function ( effect )
result . effects [ effect ] = true
end



result . moduleLocal = c . moduleLocal

c . visibilityOf = function ( stat )
return cst . declVisibility ( stat , c . moduleLocal )
end

local fix = c . edits . fix
local insertBefore = c . edits . insertBefore
c . missingRequire = c . edits . missingRequire



local own = ownership . install ( c )
c . own = own



c . loops = loopclosure . install ( c )
c . raises = undocumentedraise . install ( c )




c . unused = unused . install ( c )
c . discard = discard . install ( c )
c . nosuspend = nosuspendMod . install ( c )

c . aot = aotMod . install ( c )
c . effectRegions = effectregionsMod . install ( c )
c . typeFunctionEvaluator = function ( helper , arguments , helpers )
local program = comptime . typeFunctionProgram ( helper , helpers )
local memo = c . typeFunctionMemo [ program . identity ]
if not memo then
memo = { }
c . typeFunctionMemo [ program . identity ] = memo
end
local keyParts , transported , permitted = { program . identity } , { } , { }
for position , argument in ipairs ( arguments ) do
local value = argument . value
if argument . kind == "type" or argument . kind == "typepack" then
local descriptor = reflection . describe ( value , nil , true )
keyParts [ # keyParts + 1 ] = argument . kind .. ":" .. descriptor . fingerprint
for index , node in ipairs ( descriptor . types or { } ) do
if node . nominal then
permitted [
"argument" .. tostring ( position ) .. ":" .. tostring ( index )
] = { source = descriptor . sources [ index ] , fingerprint = node . referenceFingerprint , }
end
local source = descriptor . sources [ index ]
if node . kind == "affine" and source and not source . transferOnly then
local cleanup = source . cleanups and source . cleanups [ 1 ]
if cleanup and cleanup . key then
permitted [ "function:" .. cleanup . key ] = { cleanup = cleanup }
end
end
end
descriptor . sources = nil
transported [ position ] = { kind = argument . kind , descriptor = descriptor }
elseif argument . kind == "const" and value . tag == "constLiteral" and value . domain == "function" then
local cleanup = c . functionConstCleanup and c . functionConstCleanup ( value ) or nil
if cleanup and cleanup . key then
permitted [ "function:" .. cleanup . key ] = { cleanup = cleanup }
end
transported [ position ] = { kind = "function" , key = value . value }
keyParts [ # keyParts + 1 ] = "function:" .. tostring ( value . value )
else
transported [ position ] = { kind = argument . kind , value = value }
keyParts [ # keyParts + 1 ] = argument . kind .. ":" .. stable ( value )
end
end
local key = hash . sha256 ( table . concat ( keyParts , "\0" ) )
local cached = memo [ key ]
if cached then
return cached . result , cached . failure
end
local persistent = c . env and c . env . openTypeFunctionStore and c . env . openTypeFunctionStore ( c . env ) or nil
local persisted = persistent and persistent . get ( key ) or nil
if persisted then
local persistedType = typeblueprint . validate ( persisted , permitted )
if persistedType then
memo [ key ] = { result = persistedType }
return persistedType , nil
end
end
local root = os . getenv ( "NUPP_COMPILER_ROOT" )
local executable = root and root .. "/bin/nupp" or type (
arg
) == "table" and type ( arg [ 0 ] ) == "string" and arg [ 0 ] or nil
local envelope , evaluationFailure
if executable and not os . getenv ( "NUPP_COMPTIME_WORKER_CHILD" ) then
local worker = require (
"nupp.compiler.comptime_worker"
)
envelope , evaluationFailure = worker . evaluateTypeFunction (
program ,
transported ,
executable ,
c . env and c . env . host or nil
)
else
envelope , evaluationFailure = comptime . evaluateTypeFunctionDirect ( helper , arguments , helpers )
end
if not envelope then
memo [ key ] = { failure = evaluationFailure }
return nil , evaluationFailure
end
local resultType , validationFailure = typeblueprint . validate ( envelope , permitted )
if resultType and persistent then
persistent . put ( key , envelope )
end
memo [ key ] = { result = resultType , failure = validationFailure }

return resultType , validationFailure
end
c . reductionControl = {
evaluateTypeFunction = function ( helper , arguments )
return c . typeFunctionEvaluator ( helper , arguments , c . comptimeFunctions )
end
}
c . fixedWidth = fixedWidthCheck . install ( c )
resolve . install ( c )
local ownershipKind = own . ownershipKind




local function isAllowed ( lint , code )
if not lint then
return false
end
for j = # c . allowed , 1 , - 1 do
local set = c . allowed [ j ]
if set [ lint . name ] or set [ code ] or set [ "*" ] then
return true
end
end

return false
end






c . suppressed = function ( code )



local lint = lints . get ( code )
return isAllowed ( lint , lint and lint . code or code )
end

c . related = function ( nodeOrTok , message , relatedFilename )
local value = nodeOrTok
local atFilename = relatedFilename
if value and value . token then
atFilename = atFilename or value . filename
value = value . token
end
local at = cst . firstToken ( value )
if not at then
return nil
end

return {
message = message ,
filename = atFilename or filename ,
line = at . line ,
col = at . col ,
offset = at . offset ,
length = # at . text
}
end

c . diag = function ( code , nodeOrTok , msg , fixes , details )
local lint = lints . get ( code )
local severity = "error"
if lint then
severity = lints . level ( lint , c . lintConfig )
if severity == "off" then
return
end
end
if c . hoisting or isAllowed ( lint , lint and lint . code or code ) then
return
end
local at = cst . firstToken ( nodeOrTok )
c . diags [
# c . diags + 1
] = {
code = lint and lint . code or code ,
lint = lint and lint . name or nil ,
msg = msg ,
filename = filename ,
severity = severity ,
line = at and at . line or 0 ,
col = at and at . col or 0 ,
offset = at and at . offset or 0 ,
length = at and # at . text or 0 ,
fixes = fixes and # fixes > 0 and fixes or nil ,
help = details and details . help or nil ,
notes = details and details . notes or nil ,
related = details and details . related or nil ,
}
end






c . pushScope = function ( )
c . scope = {
vars = { } ,
types = { } ,
packTypes = { } ,
typeDefs = { } ,
pending = { } ,
automaticOwners = { } ,
parent = c . scope ,
depth = ( c . scope and c . scope . depth or 0 ) + 1
}
end

local function auditScope ( s )
for name , entry in pairs ( s . vars or { } ) do
local state = entry . ownershipOrigin or entry
if not entry . ownershipOrigin and ownershipKind and ownershipKind (
state . t
) == "affine" and not state . moved and not ( state . automaticOwner and state . automaticOwner . lowerable ) then
c . diag (
"NUPP2603" ,
entry . definition and entry . definition . token ,
(
"owned value %q leaves scope without being consumed, "
.. "dropped, returned, or released with unsafe release"
) : format ( name )
)
elseif not entry . ownershipOrigin and c . own . capabilityFacts (
state ,
nil ,
false
) . retention and not state . moved then
c . diag (
"NUPP2603" ,
entry . definition and entry . definition . token ,
(
"pinned handle %q is still retained by C; pass it to a "
.. "declared releases parameter before it leaves scope"
) : format ( name )
)
end
end
end

c . popScope = function ( )
auditScope ( c . scope )
for _ , entry in pairs ( c . scope . vars or { } ) do
c . releaseBorrowLinks ( entry )
end
c . scope = c . scope . parent
end



c . lookupEntry = function ( name )
local s = c . scope
while s do
local v = s . vars [ name ]
if v then


if v . definition then
c . reads [ v . definition ] = true
end
for i = # c . captureWatches , 1 , - 1 do






local watch = c . captureWatches [ i ]
local at = s . depth or 0
if at < watch . depth and at >= ( watch . floor or 0 ) then
watch . captured = true
end
end
return v
end
s = s . parent
end
if env and env . globals then
return env . globals [ name ]
end

return nil
end


c . lookupVar = function ( name )
local e = c . lookupEntry ( name )
return e and e . t or nil
end




c . lookupType = function ( name )
local s = c . scope
while s do
local t = s . types [ name ]
if t then
return t , s . typeDefs [ name ]
end
local waiting = s . pending and s . pending [ name ]
if waiting then
local resolved = c . resolvePendingAlias ( name , waiting , s )
if resolved then
return resolved , s . typeDefs [ name ]
end
end
s = s . parent
end
if env and env . globalTypes then
local t = env . globalTypes [ name ]
if t then
return t , env . globalTypeDefs and env . globalTypeDefs [ name ] or nil
end
end
if env and env . resolveProjectType then
return env . resolveProjectType ( env , filename , name )
end

return nil
end
c . lookupPack = function ( name )
local s = c . scope
while s do
local p = s . packTypes and s . packTypes [ name ]
if p then
return p , s . typeDefs [ name ]
end
s = s . parent
end

return nil
end
c . definition = function ( tok , kind )
if not tok then
return nil
end
local def = tok . definition
if not def or def . filename ~= filename or def . token ~= tok then
def = { filename = filename , token = tok , name = tok . text }
end
if not c . seenDefinitions [ def ] then
result . symbols [ # result . symbols + 1 ] = def
c . seenDefinitions [ def ] = true
end
if kind and ( not def . kind or def . kind == "variable" ) then
def . kind = kind
end
if c . scope and c . scope . completionScope then
local first = cst . firstToken ( c . scope . completionScope )
local last = cst . lastToken ( c . scope . completionScope )
def . scopeFrom = first and first . offset or nil
def . scopeTo = last and last . offset + # last . text or nil
def . scopeDepth = c . scope . depth or 0
end
if tok . deprecation then
def . deprecated = tok . deprecation
def . documentationToken = tok . deprecationToken
end
tok . definition = def

return def
end
c . generatedDefinition = function ( tok , name , kind , identity )
if not tok then
return nil
end
local def = { filename = filename , token = tok , name = name , kind = kind , generatedIdentity = identity , }
result . symbols [ # result . symbols + 1 ] = def
c . seenDefinitions [ def ] = true

return def
end
c . markToken = function ( tok , def , t , kind )
if not tok then
return
end
tok . definition = def
tok . inferredType = t
tok . semanticKind = kind or def and def . kind or "variable"
local deprecated = def and def . deprecated
local declaration = deprecated and def . token and def . token . offset == tok . offset and (
not def . filename or def . filename == filename
)
if deprecated and not declaration and tok . deprecationReported ~= def then
tok . deprecationReported = def
local label = def . name or tok . text
local msg = label .. " is deprecated"
if deprecated . reason and deprecated . reason ~= "" then
msg = msg .. ": " .. deprecated . reason
end
c . diag ( "NUPP2513" , tok , msg , nil , {
help = deprecated . replacement and deprecated . replacement ~= "" and (
"use " .. deprecated . replacement .. " instead"
) or nil ,
related = def . token and { c . related ( def , "deprecated API is declared here" ) } or nil ,
} )
end
end
c . bindVar = function ( name , t , annotated , tok , kind , constant )
local old = c . scope . vars [ name ]
if tok then
local s = c . scope
while s do
local existing = s . vars [ name ]
if existing and existing . constant then
c . diag ( "NUPP2008" , tok , ( "cannot re-declare const variable %s" ) : format ( name ) )
break
end
s = s . parent
end
end
kind = kind or ( t and t . tag == "func" and "function" or "variable" )
local def = tok and c . definition ( tok , kind ) or old and old . definition or nil
if def then
def . type = t
def . lexical = true
def . constant = constant == true or ( tok == nil and old and old . constant ) or false
if not def . kind or def . kind == "variable" then
def . kind = kind
end
end
local entry = {
t = t ,
ann = annotated ~= nil and annotated or old and old . ann or false ,
constant = constant == true or ( tok == nil and old and old . constant ) or false ,
definition = def ,
ownership = t and ( t . tag == "affine" or t . tag == "borrowed" or t . tag == "pinned" ) and t . tag or nil ,
moved = false ,
functionDepth = c . functionDepth ,
}
c . scope . vars [ name ] = entry




if kind ~= "parameter" and t and t . tag == "affine" and # ( t . cleanups or { } ) > 0 then
local automatic = {
name = name ,
token = tok ,
entry = entry ,
cleanups = t . cleanups ,
optional = own . optionalOwned ( t ) ,
}
entry . automaticOwner = automatic
c . scope . automaticOwners = c . scope . automaticOwners or { }
c . scope . automaticOwners [ # c . scope . automaticOwners + 1 ] = automatic
end
c . markToken ( tok , def , t , def and def . kind or kind )
end
c . bindType = function ( name , t , tok )
c . scope . types [ name ] = t
local kind = t and t . tag == "nominal" and t . declKind or "type"
if kind == "record" then
kind = "type"
end
if t and t . tag == "typevar" then
kind = "typeParameter"
end
local def = tok and c . definition ( tok , kind ) or c . scope . typeDefs [ name ]
if def then
def . type , def . kind = t , kind
def . lexical = true
end
c . scope . typeDefs [ name ] = def
c . markToken ( tok , def , t , kind )
end
c . bindPack = function ( name , p , tok )
c . scope . packTypes [ name ] = p
local def = tok and c . definition ( tok , "typeParameter" ) or c . scope . typeDefs [ name ]
if def then
def . type , def . kind = p , "typeParameter"
def . lexical = true
end
c . scope . typeDefs [ name ] = def
c . markToken ( tok , def , nil , "typeParameter" )
end



c . qualifierOf = function ( stat )
local qualifiers = stat . qualifiers
local only = qualifiers and # qualifiers == 1 and qualifiers [ 1 ] or nil
return only and only . text or nil
end





c . declKey = function ( stat )
local qualifier = c . qualifierOf ( stat )
if not qualifier then
return stat . name . text
end

return qualifier .. "." .. stat . name . text
end



c . bindDeclaredType = function ( stat , t )
local key = c . declKey ( stat )


if t and t . tag == "nominal" and c . qualifierOf ( stat ) then
t . runtimePath = key
end


for _ , qualifier in ipairs ( stat . qualifiers or { } ) do
c . markToken ( qualifier , nil , nil , "namespace" )
end
c . bindType ( key , t , stat . name )


if c . qualifierOf ( stat ) and stat . name . definition then
stat . name . definition . qualifiedName = key
end
end




c . bindDeclaredVar = function ( stat , t )
c . bindVar ( c . declKey ( stat ) , t , false , stat . name )
end








c . typevarAt = function ( tok , role )
return T . typevar ( tok . text , ( filename ) .. ":" .. tostring ( tok . offset ) .. ":" .. ( role or "generic" ) )
end
c . packvarAt = function ( tok , role )
return T . packvar (
tok . text ,
( filename ) .. ":" .. tostring ( tok . offset ) .. ":" .. ( role or "generic-pack" )
)
end









c . constDomain = function ( domainToken )
local written = domainToken and domainToken . text or nil
if written == "string" or written == "boolean" or written == "integer" or written == "function" then
return written
end

return nil
end

c . constvarAt = function ( tok , domain , role )
return T . constvar (
tok . text ,
domain ,
( filename ) .. ":" .. tostring ( tok . offset ) .. ":" .. ( role or "generic-const" )
)
end



c . bindGenerics = function ( generics , role , predeclared )
local params , bounds , packParams , constParams , paramKinds = { } , { } , { } , { } , { }
local paramDefaults = { }
local sawPack = false
for j , nameTok in ipairs ( generics and generics . names or { } ) do
local isPack = generics . packs and generics . packs [ j ]
local isConst = generics . consts and generics . consts [ j ]
if isConst then
local domainToken = generics . domains and generics . domains [ j ]
local domain = c . constDomain ( domainToken )
if not domain then
c . diag (
"NUPP2131" ,
domainToken or nameTok ,
"const parameter domain must be string, boolean, integer, or function"
)
end
domain = domain or "string"
local cv = predeclared and predeclared . constParams and predeclared . constParams [
# constParams + 1
] or c . constvarAt ( nameTok , domain , role )
constParams [ # constParams + 1 ] = cv
paramKinds [ j ] = "const"
c . bindType ( nameTok . text , consteval . singleton ( cv ) , nameTok )
elseif isPack then
sawPack = true
local pv = predeclared and predeclared . packParams and predeclared . packParams [
# packParams + 1
] or c . packvarAt ( nameTok , role )
packParams [ # packParams + 1 ] = pv
paramKinds [ j ] = "pack"
c . bindPack ( nameTok . text , pv , nameTok )
else
if sawPack then
c . diag ( "NUPP2121" , nameTok , "an ordinary type parameter cannot follow a pack parameter" )
end
local tv = predeclared and predeclared . typeParams and predeclared . typeParams [
# params + 1
] or c . typevarAt ( nameTok , role )
params [ # params + 1 ] = tv
paramKinds [ j ] = "type"
c . bindType ( nameTok . text , tv , nameTok )
end
local boundNode = generics . bounds and generics . bounds [ j ]
if boundNode then
if isPack then
c . diag ( "NUPP2121" , boundNode , "generic pack bounds are not supported" )
else
bounds [ # params ] = c . resolveType ( boundNode )
params [ # params ] . bound = bounds [ # params ]
end
end




local defaultNode = generics . defaults and generics . defaults [ j ]
if defaultNode then
if isPack then
c . diag ( "NUPP2121" , defaultNode , "a generic pack parameter cannot have a default" )
else
paramDefaults [ j ] = defaultNode
end
end
end


local defaulted = nil
for j = 1 , # paramKinds do
if paramDefaults [ j ] then
defaulted = defaulted or j
elseif defaulted and paramKinds [ j ] ~= "pack" then
c . diag (
"NUPP2121" ,
generics . names [ j ] ,
"a generic parameter without a default cannot follow one with a default"
)
end
end

return params , bounds , packParams , constParams , paramKinds , paramDefaults
end



















c . cNamespaceType = function ( )
local decls = require ( "nupp.compiler.cheader" ) . declaredFunctions (
function ( tag )
local found = c . lookupType ( tag )
if found and found . tag == "nominal" then
return found
end

return nil
end ,
c . cDeclared
)
for name , t in pairs ( c . cDefinedFunctions ) do
decls [ name ] = t
end
local fields = { }
for name , t in pairs ( decls ) do
fields [ # fields + 1 ] = { name = name , type = t }
end

return T . shape ( fields )
end


c . recordCDeclarations = function ( names )
for name in pairs ( names or { } ) do
c . cDeclared [ name ] = true
end
end



local EXPANDS = expr . EXPANDS

local function affineType ( t )
if not t then
return false
end
if t . tag == "affine" or t . tag == "pinned" then
return true
end
if t . tag == "union" or t . tag == "intersection" then
for _ , member in ipairs ( t . members ) do
if affineType ( member ) then
return true
end
end
end

return false
end

local function valueMode ( t )
if not t then
return "plain"
end
if t . tag == "affine" or t . tag == "pinned" then
return "takes"
end
if t . tag == "borrowed" then
return "borrows"
end

return "plain"
end

local function checkPackDiscard ( pack , first , at )
if not pack then
return false
end
local discarded = false
if pack . alternatives then
for _ , arm in ipairs ( pack . alternatives ) do
discarded = checkPackDiscard ( arm , first , at ) or discarded
end
return discarded
end
for j = first , # pack . head do
local facts = at and c . own . capabilityFacts ( at , j , false ) or nil
if affineType ( pack . head [ j ] ) and not ( facts and facts . origin ) then
discarded = true
end
end
if pack . tail and ( pack . tail . kind == "generic" or affineType ( pack . tail . type ) ) then
discarded = true
end
if discarded then
c . diag ( "NUPP2605" , at , "an affine value in this result pack would be discarded" )
end

return discarded
end

local function inferListPack ( exprs , paramModes )
local head , modes , tail = { } , { } , nil
exprs = exprs or { }
for j , e in ipairs ( exprs ) do
c . lastCallRets = nil
local priorScoped = c . scopedCaptureDepth
if paramModes and paramModes [ j ] == "takes" and e . kind == "tableExpr" then
e . affineAggregateContext = true
end
if paramModes and paramModes [ j ] == "scoped" then
c . scopedCaptureDepth = priorScoped + 1
end
local valueT = c . infer ( e )
c . scopedCaptureDepth = priorScoped
local produced = e . valuePack
local pack = j == # exprs and EXPANDS [ e . kind ] and produced or nil
if pack then
if pack . alternatives then
local alternatives = { }
for armIndex , arm in ipairs ( pack . alternatives ) do
local armHead , armModes = { } , { }
for k , value in ipairs ( head ) do
armHead [ k ] , armModes [ k ] = value , modes [ k ]
end
for k , resultT in ipairs ( arm . head ) do
armHead [ # armHead + 1 ] = resultT
local mode = arm . modes [ k ]
armModes [ # armModes + 1 ] = mode and mode ~= "plain" and mode or valueMode ( resultT )
end
alternatives [ armIndex ] = T . pack ( armHead , arm . tail , armModes )
end
return T . packUnion ( alternatives )
end
for k , resultT in ipairs ( pack . head ) do
head [ # head + 1 ] = resultT
local mode = pack . modes [ k ]
modes [ # modes + 1 ] = mode and mode ~= "plain" and mode or valueMode ( resultT )
end
tail = pack . tail
else
head [ # head + 1 ] = valueT
modes [ # modes + 1 ] = valueMode ( valueT )
if produced then
checkPackDiscard ( produced , 2 , e )
end
end
end

return T . pack ( head , tail , modes )
end

local function inferList ( exprs , count )
local pack = inferListPack ( exprs )
local out = { }
local hasExpressions = exprs and # exprs > 0
local limit = count and hasExpressions and count or math . min ( count or # pack . head , # pack . head )
for j = 1 , limit do
out [ j ] = T . packAt ( pack , j ) or T . nil_
end
if count then
checkPackDiscard ( pack , count + 1 , exprs and exprs [ # exprs ] or nil )
end

return out
end









local facts = narrow . install ( c )
c . facts = facts
local pathKey = facts . pathKey






local function neverReturns ( call )
if not call then
return false
end
local kind = call . kind
if kind ~= "call" and kind ~= "methodCall" then
return false
end
local signature = call . signatureType
if signature and signature . tag == "func" and signature . noreturn then
return true
end
if kind == "call" then
local callee = call . obj
if callee and callee . kind == "name" then
local tok = callee . token
if tok and tok . text == "error" then
return true
end
end
end

return false
end




local function alwaysExits ( block )
local stats = block and block . kind == "block" and block . stats or { }
local last = stats [ # stats ]
if not last then
return false
end
local kind = last . kind
if kind == "returnStmt" or kind == "breakStmt" or kind == "continueStmt" then
return true
end
if kind == "callStmt" then
return neverReturns ( last . expr )
end

return false
end







local function alwaysRaises ( block )
local stats = block and block . kind == "block" and block . stats or { }
local last = stats [ # stats ]
if not last then
return false
end
local kind = last . kind
if kind == "callStmt" then
return neverReturns ( last . expr )

elseif kind == "doStmt" then
return alwaysRaises ( last . body )

elseif kind == "ifStmt" then
local otherwise = last . elseClause
if not otherwise then
return false
end
for _ , clause in ipairs ( last . clauses ) do
if clause . kind ~= "ifClause" and clause . kind ~= "elseifClause" then
return false
end
if not alwaysRaises ( clause . body ) then
return false
end
end
if otherwise . kind ~= "elseClause" then
return false
end
return alwaysRaises ( otherwise . body )
end

return false
end





local function returnsSomewhere ( x )
if x . kind == "returnStmt" then
return true
end
if x . kind == "funcbody" or x . kind == "shortfn" then
return false
end
for _ , child in ipairs ( x ) do
if not cst . isToken ( child ) and returnsSomewhere ( child ) then
return true
end
end

return false
end



local apply = calls . install ( c )
c . apply = apply




metatable . install ( c )


expr . install ( c )







local marks = annotate . install ( c )
c . marks = marks
local validateAnnotation = marks . validateAnnotation

c . derives = derive . install ( c )



declare . install ( c , reifiableField , fix , insertBefore , validateAnnotation )








local function modulePath ( target )
local key = pathKey ( target )
if not key or not c . moduleLocal then
return nil
end
if key : sub ( 1 , # c . moduleLocal + 1 ) ~= c . moduleLocal .. "." then
return nil
end

return key
end

local function recordConstTableFields ( path , value )
if not value or value . kind ~= "tableExpr" then
return
end
for _ , field in ipairs ( value . fields or { } ) do
if field . kind == "fieldNamed" and field . isConst and field . name then
local fieldPath = path .. "." .. field . name . text
c . constModulePaths [ fieldPath ] = true
recordConstTableFields ( fieldPath , field . value )
end
end
end

local function recordModuleField ( target , t , constant , value )
if not c . moduleLocal or target . kind ~= "dotIndex" then
return
end
local base , member = target . obj , target . name
if not base or not member or base . kind ~= "name" then
return
end
local baseTok = base . token
if not baseTok or baseTok . text ~= c . moduleLocal then
return
end
c . moduleFields [ member . text ] = t or T . any
c . moduleFieldTokens [ member . text ] = member
if value then
c . moduleFieldValues [ member . text ] = value
end
if constant then
c . moduleFieldConst [ member . text ] = true
local path = modulePath ( target )
if path then
c . constModulePaths [ path ] = true
recordConstTableFields ( path , value )
end
end
end

local function constModuleField ( target )
local path = modulePath ( target )
return path ~= nil and c . constModulePaths [ path ] == true
end



c . inferList = inferList
c . inferListPack = inferListPack
c . checkPackDiscard = checkPackDiscard
c . recordModuleField = recordModuleField
c . constModuleField = constModuleField
c . alwaysExits = alwaysExits
c . alwaysRaises = alwaysRaises
c . returnsSomewhere = returnsSomewhere




local statHandlers = { }
for _ , installed in ipairs ( {
bindings . install ( c ) ,
control . install ( c ) ,
functions . install ( c ) ,
cdef . install ( c , reifiableField ) ,
pragma . install ( c ) ,
} ) do
for kind , handle in pairs ( installed ) do
statHandlers [ kind ] = handle
end
end
statHandlers . recordDecl = c . checkTypedecl
statHandlers . typeAlias = c . checkTypedecl

local function checkStat ( stat )
local handle = statHandlers [ stat . kind ]
if handle then
handle ( stat )
end
end

c . checkStat = checkStat




local function hoistNestedNominals ( owner , entries )
owner . nestedTypes = owner . nestedTypes or { }
for _ , entry in ipairs ( entries or { } ) do
if entry . kind == "recordDecl" then
local nested = entry . hoistedType or T . nominal ( entry . name . text , entry . declKind )
entry . hoistedType = nested
nested . byname = nested . byname or { }
nested . writeByname = nested . writeByname or { }
nested . staticByname = nested . staticByname or { }
nested . staticWriteByname = nested . staticWriteByname or { }
nested . runtimePath = ( owner . runtimePath or owner . name ) .. "." .. entry . name . text
owner . nestedTypes [ entry . name . text ] = nested
hoistNestedNominals ( nested , entry . entries )
end
end
end





local function hoistDeclarations ( block )
for _ , stat in ipairs ( block . stats or { } ) do
local decl = stat
while decl and decl . kind == "pragmaStmt" do
decl = decl . stat
end
local k = decl and decl . kind
if k == "recordDecl" and decl . name then
local n , entry = c . declaredNominal ( decl , decl . declKind )
decl . hoistedType , decl . hoistedEntry = n , entry
n . byname = n . byname or { }
n . writeByname = n . writeByname or { }
n . staticByname = n . staticByname or { }
n . staticWriteByname = n . staticWriteByname or { }
if decl . declKind == "interface" and decl . sealedTok then
n . sealedModule = c . result . moduleName or c . filename
end
local key = c . declKey ( decl )
if c . qualifierOf ( decl ) then
n . runtimePath = key
end





if decl . generics then
local typeParams , packParams , constParams , paramKinds = { } , { } , { } , { }
for position , nameTok in ipairs ( decl . generics . names or { } ) do
local isPack = decl . generics . packs and decl . generics . packs [ position ]
local isConst = decl . generics . consts and decl . generics . consts [ position ]
if isConst then
local domainToken = decl . generics . domains and decl . generics . domains [ position ]
constParams [ # constParams + 1 ] = c . constvarAt ( nameTok , c . constDomain ( domainToken ) , "nominal" )
paramKinds [ position ] = "const"
elseif isPack then
packParams [ # packParams + 1 ] = c . packvarAt ( nameTok , "nominal" )
paramKinds [ position ] = "pack"
else
typeParams [ # typeParams + 1 ] = c . typevarAt ( nameTok , "nominal" )
paramKinds [ position ] = "type"
end
end
n . typeParams , n . packParams , n . constParams = typeParams , packParams , constParams
n . paramKinds = paramKinds
end
hoistNestedNominals ( n , decl . entries )
c . bindType ( key , n , nil )
elseif k == "typeAlias" and decl . name and decl . value then
local waiting = { node = decl . value , tok = decl . name , decl = decl }
decl . hoistedAlias = waiting
c . scope . pending [ c . declKey ( decl ) ] = waiting
end
end
local wasHoisting = c . hoisting
c . hoisting = true







for _ , stat in ipairs ( block . stats or { } ) do
local decl = stat
while decl and decl . kind == "pragmaStmt" do
decl = decl . stat
end
local fname = decl and decl . kind == "funcStmt" and decl . name
local ownerKey , memberTok = nil , nil
if fname then
ownerKey , memberTok = c . funcOwner ( fname )
end
if ownerKey then
local owner = c . lookupType ( ownerKey )
local member = memberTok and memberTok . text
local isStatic = owner and not fname . method and (
owner . declKind == "record" or owner . declKind == "interface"
)
local members = owner and ( isStatic and owner . staticByname or owner . byname )
if owner and owner . tag == "nominal" and members and member and not members [ member ] then
local signature = c . signatureOf ( decl . body , fname . method and owner or nil )
members [ member ] = signature
if not isStatic then
owner . writeByname [ member ] = signature
else
owner . staticWriteByname [ member ] = signature
end
elseif not fname . method and ownerKey == c . moduleLocal and memberTok then
local definition = c . definition ( memberTok , "function" )
c . moduleFieldTokens [ memberTok . text ] = memberTok
c . moduleFieldDefs [ memberTok . text ] = definition
c . moduleExports . valueDefs [ memberTok . text ] = definition
local declarations = c . moduleFunctionDeclarations [ memberTok . text ] or { }
c . moduleFunctionDeclarations [ memberTok . text ] = declarations
declarations [
# declarations + 1
] = { body = decl . body , token = memberTok , definition = definition , scope = c . scope , }
end
end
end
c . hoisting = wasHoisting
end







c . resolveModuleFunction = function ( name )
if not c . moduleLocal then
return nil
end
local declarations = c . moduleFunctionDeclarations [ name ]
if not declarations then
return nil
end
local pending = nil
for j = # declarations , 1 , - 1 do
local candidate = declarations [ j ]
local visible = c . scope
while visible and visible ~= candidate . scope do
visible = visible . parent
end
if visible then
pending = candidate
break
end
end
if not pending then
return nil
end
local signature = pending . signature
if not signature then
local callerScope = c . scope
c . scope = pending . scope
signature = c . signatureOf ( pending . body , nil )
c . scope = callerScope
pending . signature = signature
if pending . definition then
pending . definition . type = signature
end
c . moduleFields [ name ] = signature
end
c . moduleFieldTokens [ name ] = pending . token
c . moduleFieldDefs [ name ] = pending . definition
c . moduleExports . valueDefs [ name ] = pending . definition
c . applyFacts ( { [ c . moduleLocal .. "." .. name ] = signature } )

return signature
end






c . checkBlock = function ( block , scopeManaged )
if not scopeManaged then
c . pushScope ( )
end
if block and block . kind == "block" then
c . scope . block = block
c . scope . completionScope = c . scope . completionScope or block
end
hoistDeclarations ( block )
local stats = block and block . kind == "block" and block . stats or { }
local wasNext = c . nextStat
for i , stat in ipairs ( stats ) do
c . nextStat = stats [ i + 1 ]
checkStat ( stat )
end
c . nextStat = wasNext
if block and block . kind == "block" and # ( c . scope . automaticOwners or { } ) > 0 then
block . automaticOwners = c . scope . automaticOwners
local boundary = cst . lastToken ( block )
local function cleanupName ( cleanup )
if cleanup . kind == "function" then
return cleanup . name or cleanup . id
elseif cleanup . kind == "closure" then
return "generated closure terminal"
elseif cleanup . kind == "method" then
return ":" .. cleanup . name
elseif cleanup . kind == "field" then
return cleanup . field .. " -> " .. cleanupName ( cleanup . cleanup )
end

return cleanup . id or cleanup . kind
end

for _ , owner in ipairs ( c . scope . automaticOwners ) do
owner . boundary = boundary
local cleanups = { }
for _ , cleanup in ipairs ( owner . cleanups or { } ) do
cleanups [ # cleanups + 1 ] = cleanupName ( cleanup )
end
if owner . entry and owner . entry . definition then
owner . entry . definition . automaticCleanup = {
line = boundary and boundary . line or 0 ,
column = boundary and boundary . col or 0 ,
cleanups = cleanups ,
status = owner . moved and "moved" or "automatic" ,
}
end
end
end
if not scopeManaged then
c . popScope ( )
end
end



if filename and filename : match ( "%.lua$" ) then
for _ , block in ipairs ( result . root . blocks ) do
reportTypedLayer ( c , block )
end
end



for _ , block in ipairs ( result . root . blocks ) do
c . checkBlock ( block , true )
end
for _ , hazard in ipairs ( c . jitHazards ) do
local body = hazard . body
local definition = body and body . jitDefinition or nil
if not hazard . suppressed and not (
body and body . jitDisabled
) and not (
definition and definition . jitDisabled
) and not (
hazard . disabledBody and hazard . disabledBody . jitDisabled
) and not ( hazard . disabledDefinition and hazard . disabledDefinition . jitDisabled ) then
c . diag ( body and body . jitRequired and "NUPP2707" or hazard . code , hazard . at , hazard . message , nil , {
help = hazard . help
} )
end
end
c . derives . finalize ( )
auditScope ( c . rootScope )





if opts and opts . declareGlobals and env then




local pendingNames = { }
for name in pairs ( c . rootScope . pending ) do
pendingNames [ # pendingNames + 1 ] = name
end
for _ , name in ipairs ( pendingNames ) do
local waiting = c . rootScope . pending [ name ]
if waiting then
c . resolvePendingAlias ( name , waiting , c . rootScope )
end
end
env . globals = env . globals or { }
env . globalTypes = env . globalTypes or { }
for name , entry in pairs ( c . rootScope . vars ) do
env . globals [ name ] = entry
end
for name , t in pairs ( c . rootScope . types ) do
env . globalTypes [ name ] = t
end
env . globalTypeDefs = env . globalTypeDefs or { }
for name , def in pairs ( c . rootScope . typeDefs ) do
env . globalTypeDefs [ name ] = def
end
end

local facts = analysis . run ( result , c )




local effectQueries = analysis . queries ( facts )
local function cleanupNonRaising ( cleanup )
if cleanup . kind == "field" then
return cleanupNonRaising ( cleanup . cleanup )
end
if cleanup . kind ~= "function" or not effectQueries then
return false
end
local known = effectQueries . known ( cleanup . token )
if not known then
return false
end
local visible = effectQueries . visible ( known . summary )
local free = visible and effectQueries . free ( known . summary , { "raises" } ) or false

return free == true
end

for _ , block in ipairs ( facts . bodies or { } ) do
local owners = block . automaticOwners or { }
if # owners == 1 then
local owner = owners [ 1 ]
local last = block . stats and block . stats [ # block . stats ] or nil
local direct = owner . lowerable
and owner . stat == last
and not owner . optional
and not owner . moved
and owner . movedFields == nil
for _ , cleanup in ipairs ( owner . cleanups or { } ) do
direct = direct and cleanupNonRaising ( cleanup )
end
if direct then
block . automaticDirect = owner
end
end
end
finalizeNominalEffects ( c )
relations . invalidate ( )



own . finalizeCleanupBounds ( )
finalizeCallGuarantees ( c , effectQueries )
finalizeBoundary ( c )


c . unused . sweep ( )
c . discard . sweep ( analysis . queries ( facts ) )
c . nosuspend . sweep ( analysis . queries ( facts ) )
c . effectRegions . sweep ( effectQueries )
local comptimeNames , comptimeIdentities = { } , { }
for name in pairs ( c . moduleExports . comptimeFunctions or { } ) do
comptimeNames [ # comptimeNames + 1 ] = name
end
table . sort ( comptimeNames )
for _ , name in ipairs ( comptimeNames ) do
comptimeIdentities [
# comptimeIdentities + 1
] = name .. "=" .. tostring ( c . moduleExports . comptimeFunctions [ name ] . identity )
end
c . moduleExports . comptimeFunctionFingerprint = table . concat ( comptimeIdentities , "\0" )
table . sort ( c . diags , function ( a , b )
return a . offset < b . offset
end )
result . moduleExports = c . moduleExports
result . cNamespaceType = c . cNamespaceType ( )

return c . diags , c . moduleType , c . moduleExports
end

return checkMod
