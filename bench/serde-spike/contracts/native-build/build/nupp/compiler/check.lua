_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()
























local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.types.relations" )
local consteval = require ( "nupp.compiler.types.consteval" )
local lints = require ( "nupp.compiler.lints" )
local fixits = require ( "nupp.compiler.check.fixits" )
local annotate = require ( "nupp.compiler.check.annotate" )
local ownership = require ( "nupp.compiler.check.ownership" )
local loopclosure = require ( "nupp.compiler.check.loopclosure" )
local undocumentedraise = require ( "nupp.compiler.check.undocumentedraise" )
local unused = require ( "nupp.compiler.check.unused" )
local discard = require ( "nupp.compiler.check.discard" )
local privateexport = require ( "nupp.compiler.check.privateexport" )
local nativeonly = require ( "nupp.compiler.check.nativeonly" )
local nosuspendMod = require ( "nupp.compiler.check.nosuspend" )
local aotMod = require ( "nupp.compiler.check.aot" )
local effectregionsMod = require ( "nupp.compiler.check.effectregions" )
local analysis = require ( "nupp.compiler.analysis" )
local traceSource = require ( "nupp.compiler.tracesource" )
local narrow = require ( "nupp.compiler.check.narrow" )
local fixedWidthCheck = require ( "nupp.compiler.check.fixedwidth" )
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
local cst = require ( "nupp.compiler.syntax.cst" )
local checkpoint = require ( "nupp.compiler.syntax.checkpoint" )
local annotationMod = require ( "nupp.compiler.annotations" )
local state = require ( "nupp.compiler.check.state" )
local capabilities = require ( "nupp.compiler.capabilities" )
local hostOs = rawget ( _G , "os" )
local getenv = hostOs and hostOs . getenv or function ( ) 
return nil
end

local generics = require ( "nupp.compiler.types.generics" )
local methodslots = require ( "nupp.compiler.lua.methodslots" )
local comptime = require ( "nupp.compiler.comptime" )
local typeblueprint = require ( "nupp.compiler.types.typeblueprint" )
local reflection = require ( "nupp.compiler.reflection" )
local hash = require ( "nupp.compiler.hash" )
local stable = require ( "nupp.compiler.stable" )

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
local reduced = require ( "nupp.compiler.types.generics" ) . normalize ( t )
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



if isCdef and t . tag == "func" then
return true
end
if t . tag == "nominal" and t . declKind == "struct" then
return true
end


if t . tag == "nominal" then
local origin = ( t ) . origin or t
if origin . moduleName == "nupp.simd" and ( origin . name == "Vector" or origin . name == "Mask" ) then
return true
end
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
if isCdef and ( other == T . voidptr or other == T . cstring or other . tag == "func" ) then
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
return not ( filename : match ( "%.d%.nupp$" ) or filename : match ( "%.lua$" ) )
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
istring = "an interpolated string" ,
switchExpr = "a switch expression" ,
doExpr = "a do expression" ,
orExitExpr = "an exit suffix" ,
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
if ( node . kind == "ifClause" or node . kind == "elseifClause" ) and node . binding then
c . diag ( "NUPP1006" , node . binding , "an `if NAME = EXPR then` binding is not plain Lua" )
end


if node . kind == "binop" and node . op and node . op . kind == "//" then
c . diag ( "NUPP1006" , node . op , "`//` is not plain Lua" )
end
if node . kind == "compoundAssign" and node . op and ( node . op . kind == "//=" or node . op . kind == "??=" ) then
c . diag ( "NUPP1006" , node . op , "`" .. node . op . kind .. "` is not plain Lua" )
end
for _ , child in ipairs ( node ) do
reportTypedLayer ( c , child )
end
end


local MODULE_LOCAL_LIMIT = 200









local function reportModuleLocals ( c , root , declaredModule ) 
local count = 0
local reported = false

local function counted ( node , names ) 
count = count + names
if count > 200 and not reported then
reported = true
c . diag (
"NUPP3005" ,
node ,
("this module's top level declares more than %d locals, which is more than a Lua function can hold")

: format ( 200 ) ,
nil ,
{
help = "gather related values into a table, or split the module; records, structs, cdef items and exported functions of a declared module do not count"

}
)
end
end

for _ , block in ipairs ( root . blocks or { } ) do
for _ , statement in ipairs ( block . stats or { } ) do
local actual = statement
while actual and ( actual . kind == "exportStmt" or actual . kind == "pragmaStmt" ) do
actual = actual . stat
end
if not actual or actual . comptimeTok or actual . comptimeFunction then

elseif actual . kind == "localStmt" then
counted ( actual , # ( actual . names or { } ) )
elseif actual . kind == "localFuncStmt" and not ( declaredModule and actual . exported ) then
counted ( actual , 1 )
elseif not declaredModule
and (
actual . kind == "cdefStruct"
or actual . kind == "cdefFunc"
or actual . kind == "recordDecl"
and ( actual . declKind == "record" or actual . declKind == "struct" )
and actual . visibility ~= "global"
)
then
counted ( actual , actual . declKind == "struct" and 2 or 1 )
end
end
end
end










local function reportRedeclaredExports ( c , root ) 
local declared = { }

local exported = { }

local function bind ( token ) 
if token and token . text and declared [ token . text ] == nil then
declared [ token . text ] = token
end
end

for _ , block in ipairs ( root . blocks or { } ) do
for _ , statement in ipairs ( block . stats or { } ) do
local actual = statement
while actual and ( actual . kind == "exportStmt" or actual . kind == "pragmaStmt" ) do
actual = actual . stat
end
local exportedName = nil
if actual and actual . exported and not actual . comptimeTok and not actual . comptimeFunction then
if actual . kind == "localFuncStmt" then
exportedName = actual . name
elseif actual . kind == "funcStmt" and actual . name and actual . name . kind == "funcname" then
exportedName = actual . name . base
end
end
if exportedName then
local earlier = declared [ exportedName . text ]
if earlier and not exported [ earlier ] then
c . diag (
"NUPP2008" ,
exportedName ,
("cannot re-declare %s as an exported function; the module already declares it")

: format ( exportedName . text ) ,
nil ,
{ related = { c . related ( earlier , "declared here first" ) } , help = "rename one of the two" }
)
end
bind ( exportedName )
exported [ declared [ exportedName . text ] ] = true
elseif actual and actual . kind == "localStmt" then
for _ , name in ipairs ( actual . names or { } ) do
bind ( name )
end
elseif actual
and (
actual . kind == "localFuncStmt"
or actual . kind == "cdefStruct"
or actual . kind == "cdefFunc"
or actual . kind == "recordDecl" and ( actual . declKind == "record" or actual . declKind == "struct" )
)
then
bind ( actual . name )
end
end
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
if current ~= body
and ( kind == "funcExpr" or kind == "shortfn" or kind == "localFuncStmt" or kind == "funcStmt" )
then
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




if t . tag == "shape"
and t . indexReadKey == nil
and t . indexWriteKey == nil
and value
and not cst . isToken ( value )
and value . kind == "tableExpr"
then
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




local moduleName = c . result . moduleName
if moduleName and ( moduleName : match ( "^nupp%.compiler" ) or moduleName : match ( "^nupp%.tools" ) ) then
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
("exported capability-bearing parameter #%d of %q needs an explicit mode")

: format ( parameter , name ) ,
nil ,
{ help = "write takes, borrows, exclusive, or scoped as part of the public contract" }
)
end
end
for result = 1 , # signature . rets do
local source = signature . preservesResults and signature . preservesResults [ result ]
if source
and couldCarryPublicCapability ( signature . params [ source ] )
and not implicitCapabilityParams [ source ]
and not ( signature . explicitPreserves and signature . explicitPreserves [ result ] )
then
c . diag (
"NUPP2610" ,
c . moduleFieldTokens [ name ] or c . moduleReturnValue ,
("exported capability result #%d of %q must spell `preserves %s`")

: format ( result , name , signature . paramNames [ source ] or ( "parameter" .. tostring ( source ) ) ) ,
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
local names = { }
for name in pairs ( c . moduleFields ) do
names [ # names + 1 ] = name
end
table . sort ( names )
for _ , name in ipairs ( names ) do
local ft = c . moduleFields [ name ]
local qualified = qualifyExport ( ft , c . moduleFieldValues [ name ] )
c . moduleFields [ name ] = qualified





if c . moduleExports and c . moduleExports . values and c . moduleExports . values [ name ] then
c . moduleExports . values [ name ] = qualified
end
if c . moduleFieldConst [ name ] then
fields [ # fields + 1 ] = { name = name , read = qualified }
else
fields [ # fields + 1 ] = { name = name , type = qualified }
end
end
if # fields > 0 then

c . moduleType = T . shape ( fields , nil , nil , true )
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
return value . effectSummary , value . callableEffects , value . callableRelations
elseif value . kind == "funcExpr" or value . kind == "shortfn" then
return value . body
and value . body . effectSummary , value . body
and value . body . callableEffects , value . body
and value . body . callableRelations
elseif value . kind == "name" and value . token and queries then
local known = queries . known ( value . token )
return known and known . summary
or nil , known and { summary = known . summary , paramNames = known . paramNames }
or nil , known and known . relations
or nil
end

return nil
end

local function localTrace ( value ) 
if not value or cst . isToken ( value ) then
return nil
end
local body = value . kind == "funcbody" and value
or ( value . kind == "funcExpr" or value . kind == "shortfn" ) and value . body
or nil
if value . kind == "name" and value . token and queries then
local known = queries . known ( value . token )
body = known and known . body or nil
end
local findings = body and body . traceSummary and body . traceSummary . findings or nil
if not findings then
return nil
end
local stableFindings = { }
for _ , finding in ipairs ( findings ) do
stableFindings [
# stableFindings + 1
] = {
reason = finding . reason ,
class = finding . class ,
message = finding . message ,
help = finding . help ,
callPath = finding . callPath ,
}
end

return stableFindings
end

local function imported ( value ) 
local exact = value and not cst . isToken ( value ) and value . exactCallExport or nil
if not exact
and value
and not cst . isToken ( value )
and value . kind == "name"
and value . token
and value . token . definition
then
exact = value . token . definition . exactCallExport
end
if not exact or not c . env or not c . env . resolveCallGuarantees then
return nil
end

return c . env . resolveCallGuarantees ( c . env , exact . module , exact . member )
end

local function localFact ( value , family ) 
if not value then
return nil
end
local known = value . kind == "name" and queries and queries . known ( value . token )
local body = known and known . body or value . kind == "funcbody" and value or value . body

return body and body [ family ]
end

local function publish ( member , value ) 
if value and value . unstableFact then
return
end
local summary , callableEffects , callableRelations = localSummary ( value )
local source = not summary and imported ( value ) or nil
local traceFindings = localTrace ( value ) or source and source . traceFindings
if summary or source or traceFindings then
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
identity = source and source . identity
or ( ( c . result . moduleName or c . filename or "<module>" ) .. "." .. member ) ,
noAllocate = noAllocate ,
noRaise = noRaise ,
callableEffects = source and source . callableEffects or callableEffects ,
callableRelations = source and source . callableRelations or callableRelations ,
representation = source and source . representation or localFact ( value , "representation" ) ,
viewBody = source and source . viewBody or localFact ( value , "viewBody" ) ,
inlineBody = source and source . inlineBody or localFact ( value , "inlineBody" ) ,
inlineEligibility = source and source . inlineEligibility or localFact ( value , "inlineEligibility" ) ,
traceFindings = traceFindings ,
traceProfileId = source and source . traceProfileId or traceSource . profile ( ) . id ,
reasonCatalogId = source and source . reasonCatalogId or traceSource . CATALOG_ID ,
reasonCatalogVersion = source and source . reasonCatalogVersion or traceSource . CATALOG_VERSION ,
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






local value = field . value
local definition = value . kind == "name" and value . token and value . token . definition or nil
if definition ~= nil and c . moduleExports . valueDefs [ field . name . text ] == nil then
local exported = c . definition ( field . name , definition . kind or "function" )
c . nativeOnly . alias ( exported , definition , nil )
c . moduleExports . valueDefs [ field . name . text ] = exported
end
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
local inlineEntries = entry . static and entry . owner . staticEntries and entry . owner . staticEntries [ entry . member ]
or entry . owner . methodDispatchEntries and entry . owner . methodDispatchEntries [ entry . member ]
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
local checkedState = result
checkpoint . restore ( checkedState )
checkedState . optimizationSyntax = nil
opts = opts or { }
local selectedCompat , compatError = require ( "nupp.compiler.compat" ) . resolve ( opts . compat , env and env . compat )
if compatError then
error ( compatError , 2 )
end
opts . compat = selectedCompat
result . compat = selectedCompat
if filename and filename : match ( "%.lua$" ) then
require ( "nupp.compiler.annotatedlua" ) . decorate ( result , filename )
end
if opts . strict == nil then


opts . strict = not opts . declarationFile and checkMod . strictByDefault ( filename )
end
result . symbols = { }
result . implicitSideEffects = { }


result . effects = { }
result . host = env and env . artifactHost or "native"
result . preludeRuntime = env and env . preludeRuntime or nil
result . moduleName = opts and opts . moduleName
or env and env . moduleNameForPath and env . moduleNameForPath ( env , filename )
or nil
local declaredModuleName , declaredModuleNode = cst . declaredModule ( result . root )
result . declaredModuleName = declaredModuleName
local registry = opts and opts . annotations or env and env . annotations or annotationMod . default ( )
annotationMod . hydrateBuiltins ( registry , T )
if env then
annotationMod . bindBuiltinDeclarations ( registry , env . globalTypes , env . globalTypeDefs )
end
registry : removeSource ( filename )






local c = setmetatable (
{
result = result ,
filename = filename ,
env = env ,
opts = opts ,
reducerMemo = { } ,
comptimeDepth = 0 ,
comptimeFunctionDepth = 0 ,
comptimeFunctions = { } ,
typeFunctionMemo = { } ,




declarationFile = ( opts and ( opts . declarationFile or opts . declareGlobals ) ) and true
or ( filename and filename : match ( "%.d%.nupp$" ) ) and true
or false ,


moduleLocal = declaredModuleName and ( cst . exportedLocal ( result . root ) or "__nuppExports" )
or cst . returnedLocal ( result . root )
or result . foreignModuleLocal ,
annotationRegistry = registry ,
annotationDefinitions = { } ,
lintConfig = opts and opts . lints or env and env . config and env . config . lints or nil ,



edits = fixits . new ( result , env ) ,
diags = { } ,
moduleType = nil ,
moduleExports = opts and opts . initialExports
or { types = { } , typeDefs = { } , values = { } , valueDefs = { } , comptimeFunctions = { } , callGuarantees = { } , } ,
seenDefinitions = { } ,
scope = {
vars = { } ,
types = { } ,
packTypes = { } ,
typeDefs = { } ,
pending = { } ,
automaticOwners = { } ,
depth = 0 ,
completionScope = result . root ,
parent = nil
} ,
retStack = { } ,
retPackStack = { } ,
observedReturnStack = { } ,
ownReturnStack = { } ,
borrowReturnStack = { } ,
varargPackStack = { } ,
yieldPackStack = { } ,
blockYieldStack = { } ,
resumePackStack = { } ,
protocolStack = { } ,
consumingFieldStack = { } ,
constructorFieldStack = { } ,
validatedCleanupContracts = { } ,
unsafeDepth = 0 ,
noSuspendDepth = 0 ,
cleanupBindings = { } ,
effectRegionDepths = { allocates = 0 , raises = 0 } ,
functionDepth = 0 ,
functionBodies = { } ,
temporaryOwners = { } ,
jitHazards = { } ,
scopedCaptureDepth = 0 ,
closureCaptureStack = { } ,
captureWatches = { } ,
allowed = { } ,
nextStat = nil ,
hoisting = false ,


resolvingAlias = { } ,
lastCallRets = nil ,
moduleFields = { } ,
moduleFieldTokens = { } ,
moduleFieldDefs = { } ,
qualifiedFunctionEntries = { } ,
moduleFunctionDeclarations = { } ,
moduleFieldConst = { } ,
moduleFieldValues = { } ,
nominalEffectOwners = { } ,
nominalEffectEntries = { } ,
conformanceEffects = { } ,
constModulePaths = { } ,
moduleLocalAnnotated = false
} ,
state . Checker
)
c . rootScope = c . scope
c . moduleExports . valueDefs = c . moduleExports . valueDefs or { }
c . moduleExports . comptimeFunctions = c . moduleExports . comptimeFunctions or { }





if env and env . preludeComptimeFunctions then
for name , helper in pairs ( env . preludeComptimeFunctions ) do
if c . comptimeFunctions [ name ] == nil then
c . comptimeFunctions [ name ] = helper
end
end
end









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
local keyParts , memoIdentityParts , transported , permitted = { program . identity } , { } , { } , { }
local nominalOrdinals , nextNominalOrdinal = { } , 0
for position , argument in ipairs ( arguments ) do
local value = argument . value
if argument . kind == "type" or argument . kind == "typepack" then
local descriptor = reflection . describe ( value , nil , true )
keyParts [ # keyParts + 1 ] = argument . kind .. ":" .. descriptor . fingerprint
for index , node in ipairs ( descriptor . types or { } ) do
if node . nominal then
local declaration = descriptor . sources [ index ]
while declaration and declaration . tag == "nominal" and declaration . origin do
declaration = declaration . origin
end
local ordinal = nominalOrdinals [ declaration ]
if not ordinal then
nextNominalOrdinal = nextNominalOrdinal + 1
ordinal = nextNominalOrdinal
nominalOrdinals [ declaration ] = ordinal
end
keyParts [ # keyParts + 1 ] = "nominal:" .. tostring ( index ) .. ":" .. tostring ( ordinal )
memoIdentityParts [
# memoIdentityParts + 1
] = "nominal:" .. tostring ( index ) .. ":" .. tostring ( node . nominalIdentity )
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
local memoKey = hash . sha256 ( key .. "\0" .. table . concat ( memoIdentityParts , "\0" ) )
local cached = memo [ memoKey ]
if cached then
return cached . result , cached . failure
end
local persistent = c . env and c . env . openTypeFunctionStore and c . env . openTypeFunctionStore ( c . env ) or nil
local persisted = persistent and persistent . get ( key ) or nil
if persisted then
local persistedType = typeblueprint . validate ( persisted , permitted )
if persistedType then
memo [ memoKey ] = { result = persistedType }
return persistedType , nil
end
end
local root = getenv ( "NUPP_COMPILER_ROOT" )
local cliArguments = rawget ( _G , "arg" )
local executable = root and root .. "/bin/nupp"
or type ( cliArguments ) == "table" and type ( cliArguments [ 0 ] ) == "string" and cliArguments [ 0 ]
or nil
local envelope , evaluationFailure
local worker = c . env and c . env . compilerServices and c . env . compilerServices . comptimeworker or nil
if worker and executable and not getenv ( "NUPP_COMPTIME_WORKER_CHILD" ) then
worker = worker
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
memo [ memoKey ] = { failure = evaluationFailure }
return nil , evaluationFailure
end
local resultType , validationFailure = typeblueprint . validate ( envelope , permitted )
if resultType and persistent then
persistent . put ( key , envelope )
end
memo [ memoKey ] = { result = resultType , failure = validationFailure }

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
for j = # c . allowed , 1 , -1 do
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

for _ , diagnostic in ipairs ( result . annotationWarnings or { } ) do
c . diags [ # c . diags + 1 ] = diagnostic
end

if declaredModuleNode and declaredModuleName then
local first = nil
local declarations = 0
for _ , block in ipairs ( result . root . blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
if stat . kind ~= "emptyStmt" then
first = first or stat
end
if stat . kind == "moduleStmt" then
declarations = declarations + 1
end
end
end
if first ~= declaredModuleNode then
c . diag ( "NUPP1002" , declaredModuleNode , "the module declaration must be the first declaration in the file" )
end
if declarations > 1 then
c . diag ( "NUPP1002" , declaredModuleNode , "a source file declares exactly one module" )
end
if filename and filename : match ( "%.d%.nupp$" ) then
c . diag ( "NUPP1002" , declaredModuleNode , "declaration files cannot declare source modules" )
end
for segment in declaredModuleName : gmatch ( "[^.]+" ) do
if not segment : match ( "^[a-z][a-z0-9]*$" ) then
c . diag ( "NUPP1002" , declaredModuleNode , ("module segment %q must use lowercase luacase") : format ( segment ) )
do break end
end
end
if result . moduleName and declaredModuleName ~= result . moduleName then
c . diag (
"NUPP1002" ,
declaredModuleNode ,
("module %q does not match this file's canonical module name %q")

: format ( declaredModuleName , result . moduleName )
)
end
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


for _ , entry in pairs ( s . vars or { } ) do
c . releaseBorrowLinks ( entry )
end
for name , entry in pairs ( s . vars or { } ) do
local state = entry . ownershipOrigin or entry
if not entry . ownershipOrigin
and ownershipKind
and ownershipKind ( state . t ) == "affine"
and not state . moved
and not ( state . automaticOwner and state . automaticOwner . lowerable )
then
c . diag (
"NUPP2603" ,
entry . definition and entry . definition . token or entry . assignedAt ,
("owned value %q leaves scope without being consumed, dropped, returned, or released with @unsafe nupp.release")


: format ( name )
)
elseif not entry . ownershipOrigin
and ownershipKind
and ownershipKind ( state . t ) == "affine"
and not state . moved
and ( state . activeBorrows or 0 ) > 0
then



c . diag (
"NUPP2602" ,
entry . definition and entry . definition . token ,
("owner %q leaves scope while a derived borrow is still live") : format ( name ) ,
nil ,
c . own . conflictDetails ( state , nil )
)
elseif not entry . ownershipOrigin
and c . own . capabilityFacts ( state , nil , false ) . retention
and not state . moved
then
c . diag (
"NUPP2603" ,
entry . definition and entry . definition . token ,
("pinned handle %q is still retained by C; pass it to a declared releases parameter before it leaves scope")


: format ( name )
)
end
end
end

c . popScope = function ( ) 
auditScope ( c . scope )
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
for i = # c . captureWatches , 1 , -1 do






local watch = c . captureWatches [ i ]
local at = s . depth or 0
if at < watch . depth and at >= ( watch . floor or 0 ) then
watch . captured = true
if watch . entries and v . definition then
watch . entries [ v . definition ] = v
end
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
if waiting and c . preclaiming then
return nil
elseif waiting then
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
local declaration = deprecated
and def . token
and def . token . offset == tok . offset
and ( not def . filename or def . filename == filename )
if deprecated and not declaration and tok . deprecationReported ~= def then
tok . deprecationReported = def
local label = def . name or tok . text
local msg = label .. " is deprecated"
if deprecated . reason and deprecated . reason ~= "" then
msg = msg .. ": " .. deprecated . reason
end
c . diag ( "NUPP2513" , tok , msg , nil , {
help = deprecated . replacement
and deprecated . replacement ~= ""
and ( "use " .. deprecated . replacement .. " instead" )
or nil ,
related = def . token and { c . related ( def , "deprecated API is declared here" ) } or nil ,
} )
end
end



local bindingOrdinal = 0
c . bindVar = function ( name , t , annotated , tok , kind , constant ) 
local old = c . scope . vars [ name ]
bindingOrdinal = bindingOrdinal + 1
if tok then
local s = c . scope
while s do
local existing = s . vars [ name ]
if existing and existing . constant then
c . diag ( "NUPP2008" , tok , ("cannot re-declare const variable %s") : format ( name ) )
do break end
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
def . functionDepth = c . functionDepth
def . initialized = constant or kind == "parameter" or kind == "function" or nil
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
bindingOrdinal = bindingOrdinal ,
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
local tv = T . typevar (
tok . text ,
( filename ) .. ":" .. tostring ( tok . offset ) .. ":" .. ( role or "generic" )
)
if tv . tag == "typevar" and tv . name ~= tok . text then
tv . name = tok . text
end

return tv
end
c . packvarAt = function ( tok , role ) 
local pv = T . packvar (
tok . text ,
( filename ) .. ":" .. tostring ( tok . offset ) .. ":" .. ( role or "generic-pack" )
)
if pv . name ~= tok . text then
pv . name = tok . text
end

return pv
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
local params , bounds , packParams , constParams = { } , { } , { } , { }
local paramKinds = { }
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
local cv = predeclared and predeclared . constParams and predeclared . constParams [ # constParams + 1 ]
or c . constvarAt ( nameTok , domain , role )
constParams [ # constParams + 1 ] = cv
paramKinds [ j ] = "const"
c . bindType ( nameTok . text , consteval . singleton ( cv ) , nameTok )
elseif isPack then
sawPack = true
local pv = predeclared and predeclared . packParams and predeclared . packParams [ # packParams + 1 ]
or c . packvarAt ( nameTok , role )
packParams [ # packParams + 1 ] = pv
paramKinds [ j ] = "pack"
c . bindPack ( nameTok . text , pv , nameTok )
else
if sawPack then
c . diag ( "NUPP2121" , nameTok , "an ordinary type parameter cannot follow a pack parameter" )
end
if T . builtins [ nameTok . text ] then
c . diag (
"NUPP2145" ,
nameTok ,
("type parameter %q conflicts with the builtin type of the same name") : format ( nameTok . text ) ,
nil ,
{ help = "choose a parameter name such as T or Element" }
)
end
local tv = predeclared and predeclared . typeParams and predeclared . typeParams [ # params + 1 ]
or c . typevarAt ( nameTok , role )
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
elseif not isPack and not isConst then
params [ # params ] . bound = nil
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



local typeAt = 0
for j , kind in ipairs ( paramKinds ) do
if kind == "type" then
typeAt = typeAt + 1
local defaultNode = paramDefaults [ j ]
local tv = params [ typeAt ]
if defaultNode then
local value = c . resolveType ( defaultNode )
tv . default = value
if bounds [ typeAt ] and not relations . isA ( value , bounds [ typeAt ] ) then
c . diag (
"NUPP2116" ,
defaultNode ,
("default %s does not fit the bound %s declares for %s")

: format ( T . tostring ( value ) , T . tostring ( bounds [ typeAt ] ) , tv . name ) ,
nil ,
{ help = "a default has to satisfy the bound beside it" }
)
end
else
tv . default = nil
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
local decls = { }
local resolved = c . opts . _capabilityResolution or capabilities . resolve ( )
local cinterop = capabilities . get ( resolved , "cinterop" )
if cinterop . kind ~= "missing"
and ( c . env and c . env . compilerServices and c . env . compilerServices . cheader ~= nil )
and next ( c . cDeclared ) ~= nil
then
local cheader = assert (
c . env and c . env . compilerServices and c . env . compilerServices . cheader ,
"native C-header compiler service is unavailable"
)
decls = cheader . declaredFunctions (
function ( tag ) 
local found = c . lookupType ( tag )
if found and found . tag == "nominal" then
return found
end

return nil
end ,
c . cDeclared
)
end
local definedFunctions = c . cDefinedFunctions
for name , t in pairs ( definedFunctions ) do
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

local function inferListPack ( exprs , paramModes , destinationFor ) 
local head = { }
local modes , tail = { } , nil
exprs = exprs or { }
for j , e in ipairs ( exprs ) do
c . lastCallRets = nil





if destinationFor and ( e . kind == "call" or e . kind == "safeCall" ) then
e . expectedResult = destinationFor ( j , head )
end
local priorScoped = c . scopedCaptureDepth
if paramModes and paramModes [ j ] == "takes" and e . kind == "tableExpr" then
e . affineAggregateContext = true
end
if paramModes and paramModes [ j ] == "scoped" then
c . scopedCaptureDepth = priorScoped + 1
end
local literal = e . kind == "shortfn" or e . kind == "funcExpr"
local valueT
if literal and e . expectedCallable then
valueT = c . apply . inferExpected ( e , e . expectedCallable )
elseif literal then




c . provisionalDepth = ( c . provisionalDepth or 0 ) + 1
valueT = c . infer ( e )
c . provisionalDepth = c . provisionalDepth - 1
else
valueT = c . infer ( e )
end
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
if ( call ) . assertNever then
return true
end
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
while last and ( last . kind == "pragmaStmt" or last . kind == "exportStmt" ) do
last = last . stat
end
if not last then
return false
end
local kind = last . kind
if kind == "returnStmt"
or kind == "yieldStmt"
or kind == "breakStmt"
or kind == "continueStmt"
or kind == "gotoStmt"
then
return true
end
if kind == "callStmt" then
return neverReturns ( last . expr )
end

return false
end





local function breaksOut ( x ) 
if not x or cst . isToken ( x ) then
return false
end
local kind = x . kind
if kind == "breakStmt" or ( kind == "orExitExpr" and ( x ) . exitKind == "break" ) then
return true
end
if kind == "funcbody"
or kind == "shortfn"
or kind == "whileStmt"
or kind == "repeatStmt"
or kind == "fornumStmt"
or kind == "forinStmt"
then
return false
end
for _ , child in ipairs ( x ) do
if not cst . isToken ( child ) and breaksOut ( child ) then
return true
end
end

return false
end

local completesNormally









local function fallsThrough ( block ) 
local stats = block and block . kind == "block" and block . stats or { }
local reachable = true
for _ , stat in ipairs ( stats ) do
if stat . kind == "labelStmt" then
reachable = true
elseif reachable and not completesNormally ( stat ) then
reachable = false
end
end

return reachable
end




completesNormally = function ( node ) 
local stat = node
while stat and ( stat . kind == "pragmaStmt" or stat . kind == "exportStmt" ) do
stat = stat . stat
end
if not stat then
return true
end
local kind = stat . kind
if kind == "returnStmt"
or kind == "yieldStmt"
or kind == "breakStmt"
or kind == "continueStmt"
or kind == "gotoStmt"
then
return false
elseif kind == "callStmt" then
return not neverReturns ( stat . expr )
elseif kind == "doStmt" or kind == "withStmt" then
return fallsThrough ( stat . body )
elseif kind == "ifStmt" then
if not stat . elseClause then
return not stat . exhaustiveDispatch
end
for _ , clause in ipairs ( stat . clauses ) do
if fallsThrough ( clause . body ) then
return true
end
end
return fallsThrough ( stat . elseClause . body )
elseif kind == "whileStmt" then
local cond = stat . cond
return not ( cond and cond . kind == "trueExpr" ) or breaksOut ( stat . body )
elseif kind == "repeatStmt" then
local cond = stat . cond
return not ( cond and cond . kind == "falseExpr" ) or breaksOut ( stat . body )
end

return true
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

c . withUnsafe = function ( enabled , action ) 
local saved = c . unsafeDepth
c . unsafeDepth = enabled and saved + 1 or 0
local ok , result = pcall ( action )
c . unsafeDepth = saved
if not ok then
error ( result , 0 )
end

return result
end


expr . install ( c )







local marks = annotate . install ( c )
c . marks = marks
local validateAnnotation = marks . validateAnnotation

c . derives = derive . install ( c )
c . privateExport = privateexport . install ( c )
c . nativeOnly = nativeonly . install ( c )



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






local written = t or T . any
if written . tag == "literal" then
written = written . base or T . string
end
local previous = c . moduleFields [ member . text ]
if not constant then
if c . functionDepth > 0 and not previous then
written = T . union ( { written , T . nil_ } )
end
if previous and previous ~= written then
written = T . union ( { previous , written } )
end
end
c . moduleFields [ member . text ] = written
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
c . fallsThrough = fallsThrough
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

local function checkTypeDeclaration ( stat ) 
if declaredModuleName and stat . visibility == "global" then
c . diag ( "NUPP1002" , stat . modifier or stat , "'global' is not allowed in a declared module; use 'export'" )
stat . visibility = "local"
end
if stat . kind == "recordDecl" and stat . declKind == "struct" then
require ( "nupp.compiler.capabilities" ) . require ( c , "structvalue" , stat )
end
c . checkTypedecl ( stat )
end

statHandlers . recordDecl = checkTypeDeclaration
statHandlers . typeAlias = checkTypeDeclaration




local moduleValueAssignment = nil
local scannedModuleValue = false

local function exportAssignment ( ) 
if not scannedModuleValue then
scannedModuleValue = true
moduleValueAssignment = cst . exportAssignment ( result . root )
end

return moduleValueAssignment
end




local function exportValue ( nameTok , t , definition , value , constant , carriesValue ) 
if not nameTok then
return
end
local name = nameTok . text









if carriesValue and exportAssignment ( ) ~= nil then
local exportedName = cst . exportedLocal ( result . root )
c . diag (
"NUPP2143" ,
nameTok ,
("exported \"%s\" carries a runtime value, and this module's value is `export =` instead") : format ( name ) ,
nil ,
{
help = exportedName ~= nil
and ("declare it on the module value as %s.%s, or assign it there") : format ( exportedName , name )
or "declare it on the module value, or drop `export =` and export the declarations" ,
}
)

return
end
c . moduleFields [ name ] = t or T . any
c . moduleFieldTokens [ name ] = nameTok
c . moduleFieldDefs [ name ] = definition
c . moduleFieldValues [ name ] = value
if constant then
c . moduleFieldConst [ name ] = true
end
c . moduleExports . values [ name ] = t or T . any
c . moduleExports . valueDefs [ name ] = definition
if definition then
c . reads [ definition ] = true
end
end

statHandlers . moduleStmt = function ( stat ) 
if stat ~= declaredModuleNode then
c . diag ( "NUPP1002" , stat , "a module declaration is allowed only once at the top of a source file" )
end
if c . env and c . env . ensureProjectIndex then
local projectIndex = c . env . ensureProjectIndex ( c . env )
local prefix = ""
for _ , name in ipairs ( stat . names or { } ) do
prefix = prefix == "" and name . text or prefix .. "." .. name . text
local definition = projectIndex . moduleDefinitions and projectIndex . moduleDefinitions [ prefix ] or nil
c . markToken ( name , definition , nil , "module" )
end
end
end

statHandlers . exportStmt = function ( wrapper ) 
if not declaredModuleName then
c . diag ( "NUPP1002" , wrapper , "'export' is available only in a declared module" )
return
end
if c . scope ~= c . rootScope then
c . diag ( "NUPP1002" , wrapper , "an export declaration is allowed only at module top level" )
local nested = wrapper . stat
if nested and statHandlers [ nested . kind ] then
statHandlers [ nested . kind ] ( nested )
end
return
end
if wrapper . value then
local exportedLocal = cst . exportedLocal ( result . root )
local exportedType = c . infer ( wrapper . value )
c . moduleType = exportedType
c . moduleReturnValue = wrapper . value
if exportedLocal
and exportedType == T . table_
and not c . moduleLocalAnnotated
and exportedLocal == c . moduleLocal
then
local fields = { }
for name , ft in pairs ( c . moduleFields ) do
if c . moduleFieldConst [ name ] then
fields [ # fields + 1 ] = { name = name , read = ft }
else
fields [ # fields + 1 ] = { name = name , type = ft }
end
end
if # fields > 0 then
c . moduleType = T . shape ( fields , nil , nil , true )
c . moduleTypeFromFields = true
end
end
return
end
local stat = wrapper . stat
while stat and stat . kind == "pragmaStmt" do
stat = stat . stat
end
if not stat then
return
end
stat . exported = true
if stat . kind == "recordDecl" or stat . kind == "typeAlias" then
if stat . visibility == "global" then
c . diag ( "NUPP1002" , stat . modifier or stat , "'global' is not allowed in a declared module" )
end
stat . visibility = "module"
statHandlers [ stat . kind ] ( stat )
local t = stat . resolvedType
c . privateExport . exported ( stat . name , "types" )
if stat . kind == "recordDecl" and t then


local carriesValue = stat . declKind == "record" or stat . declKind == "struct"



local published = carriesValue and not stat . isAnnotationDefinition and T . typeObject ( t ) or t
exportValue ( stat . name , published , stat . name and stat . name . definition , stat , true , carriesValue )
end
return
end
if stat . kind == "localFuncStmt" or stat . kind == "funcStmt" then
if stat . kind == "funcStmt" and stat . name and ( # stat . name ~= 1 or stat . name . method ) then
c . diag ( "NUPP1002" , stat . name , "an exported function name cannot be qualified" )
return
end

if c . opts . strict then
for _ , parameter in ipairs ( stat . body and stat . body . params or { } ) do
if parameter . name and not parameter . type and not parameter . vararg then
c . diag (
"NUPP2106" ,
parameter . name ,
"an exported function must write every public parameter type"
)
end
end
if stat . body and not stat . body . rets and not stat . body . returnPack then
c . diag ( "NUPP2106" , stat . body , "an exported function must write its public result type" )
end
end
stat . isConst = true
statHandlers [ stat . kind ] ( stat )
local nameTok = stat . kind == "localFuncStmt" and stat . name or stat . name and stat . name . base
local entry = nameTok and c . scope . vars [ nameTok . text ]
exportValue ( nameTok , entry and entry . t , entry and entry . definition , stat . body , true , true )
c . privateExport . exported ( nameTok , "values" )
return
end
if stat . kind == "localStmt" and stat . isConst and not stat . pattern then
statHandlers . localStmt ( stat )
for _ , nameTok in ipairs ( stat . names or { } ) do
local entry = c . scope . vars [ nameTok . text ]
exportValue ( nameTok , entry and entry . t , entry and entry . definition , nil , true , true )
c . privateExport . exported ( nameTok , "values" )
end
return
end
c . diag (
"NUPP1002" ,
wrapper ,
"'export' must introduce a function, type declaration, record, interface, struct, or const"
)
end





local function checkStat ( stat ) 
local handle = statHandlers [ stat . kind ]




local temporaries = { }
stat . statementCleanupOwners = nil
c . temporaryOwners [ # c . temporaryOwners + 1 ] = temporaries
if handle then
handle ( stat )
end
c . temporaryOwners [ # c . temporaryOwners ] = nil
for _ , node in ipairs ( temporaries ) do
if not node . temporaryConsumed and not node . temporaryReported then
local inferred = node . inferredType
local cleanups = inferred and inferred . cleanups or { }
if node . temporaryStatementCleanup and c . ownershipKind ( inferred ) == "affine" and # cleanups > 0 then
local owner = { node = node , cleanups = cleanups , optional = c . own . optionalOwned ( inferred ) , }
node . statementOwner = owner
stat . statementCleanupOwners = stat . statementCleanupOwners or { }
stat . statementCleanupOwners [ # stat . statementCleanupOwners + 1 ] = owner
else
node . temporaryReported = true
c . diag (
"NUPP2603" ,
node ,
"owned temporary is neither bound to a name nor consumed, so its terminal never runs" ,
nil ,
{
help = "bind it to a local, which drops it when the scope ends, or pass it to a takes parameter"

}
)
end
end
end
end

c . checkStat = checkStat


local function requiredLiteral ( expr ) 
if not expr
or expr . kind ~= "call"
or not expr . obj
or expr . obj . kind ~= "name"
or expr . obj . token . text ~= "require"
or not expr . args
or expr . args . kind ~= "args"
then
return nil
end
local tok = expr . args . str
local exprs = expr . args . exprs or { }
if not tok and # exprs == 1 and exprs [ 1 ] . kind == "string" then
tok = exprs [ 1 ] . token
end
if not tok then
return nil
end

return tok . text : match ( "^\"(.*)\"$" ) or tok . text : match ( "^'(.*)'$" )
end








local begunNominals = { }
c . beginNominal = function ( n ) 
if begunNominals [ n ] then
return
end
begunNominals [ n ] = true
n . byname = { }
n . writeByname = { }
n . staticByname = { }
n . staticWriteByname = { }
end





local function hoistNestedNominals ( owner , entries , hoisted , owners ) 
owner . nestedTypes = owner . nestedTypes or { }
local within = { }
for j , enclosing in ipairs ( owners ) do
within [ j ] = enclosing
end
within [ # within + 1 ] = owner
for _ , entry in ipairs ( entries or { } ) do
if entry . kind == "recordDecl" then
local nested = entry . hoistedType
or T . nominal ( entry . name . text , entry . declKind , T . nestedDeclarationKey ( owner , entry . name . offset ) )
entry . hoistedType = nested
c . beginNominal ( nested )
nested . runtimePath = ( owner . runtimePath or owner . name ) .. "." .. entry . name . text
nested . awaitingBody = true
owner . nestedTypes [ entry . name . text ] = nested
hoisted [ # hoisted + 1 ] = { decl = entry , owners = within }
hoistNestedNominals ( nested , entry . entries , hoisted , within )
end
end
end





local function hoistDeclarations ( block ) 
local hoistedNominals = { }





local bound = { }
for _ , stat in ipairs ( block . stats or { } ) do
local decl = stat
local deriveApplications = { }
while decl and decl . kind == "pragmaStmt" do
if decl . name and decl . name . text == "derive" then
deriveApplications [ # deriveApplications + 1 ] = decl
end
decl = decl . stat
end
if decl and decl . kind == "exportStmt" then
decl = decl . stat
while decl and decl . kind == "pragmaStmt" do
decl = decl . stat
end
if decl and ( decl . kind == "recordDecl" or decl . kind == "typeAlias" ) then
decl . visibility = "module"
decl . exported = true
elseif decl then
decl . exported = true
end
end
local k = decl and decl . kind
if k == "recordDecl" and decl . name then
decl . documentationNode = stat
if # deriveApplications > 0 then
decl . deriveApplications = decl . deriveApplications or { }
for _ , application in ipairs ( deriveApplications ) do
local seen = false
for _ , prior in ipairs ( decl . deriveApplications ) do
if prior == application then
seen = true
do break end
end
end
if not seen then
decl . deriveApplications [ # decl . deriveApplications + 1 ] = application
end
end
end
local n , entry = c . declaredNominal ( decl , decl . declKind )
decl . hoistedType , decl . hoistedEntry = n , entry
n . deriveDeclaration = decl
n . deriveClaimsComplete = nil
n . deriveClaimedContracts = nil
c . beginNominal ( n )
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
constParams [
# constParams + 1
] = c . constvarAt ( nameTok , c . constDomain ( domainToken ) , "nominal" )
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
local visible = { }
for name , module in pairs ( bound ) do
visible [ name ] = module
end
local first = # hoistedNominals + 1
hoistedNominals [ first ] = { decl = decl , owners = { } , bound = visible }
hoistNestedNominals ( n , decl . entries , hoistedNominals , { } )
for index = first + 1 , # hoistedNominals do
hoistedNominals [ index ] . bound = visible
end
c . bindType ( key , n , nil )
n . awaitingBody = true
elseif k == "typeAlias" and decl . name and decl . value then
local waiting = { node = decl . value , tok = decl . name , decl = decl }
decl . hoistedAlias = waiting
local key = c . declKey ( decl )
c . scope . pending [ key ] = waiting



local definition = c . definition ( decl . name , "type" )
definition . comptimeOnly = decl . comptimeOnly or nil
c . scope . typeDefs [ key ] = definition
end
if decl and decl . kind == "localStmt" and decl . pattern then
local module = requiredLiteral ( decl . patternSource )
for _ , entry in ipairs ( decl . pattern ) do
local nameTok = entry . alias or entry . sourceName
if nameTok and not entry . typeOnly then
bound [ nameTok . text ] = module or false
end
end
elseif decl and decl . kind == "localStmt" then
for index , nameTok in ipairs ( decl . names or { } ) do
bound [ nameTok . text ] = requiredLiteral ( decl . exprs and decl . exprs [ index ] ) or false
end
elseif decl and decl . kind == "localFuncStmt" and decl . name then
bound [ decl . name . text ] = false
end
end
local wasHoisting = c . hoisting
c . hoisting = true





c . preclaiming = true
for _ = 1 , # hoistedNominals + 1 do
local changed = false
for _ , hoisted in ipairs ( hoistedNominals ) do
local decl = hoisted . decl
if decl . supertypes then
local aliased = next ( hoisted . bound ) ~= nil
if aliased then
c . pushScope ( )
for name , module in pairs ( hoisted . bound ) do
c . scope . vars [ name ] = { t = T . any , requiredModule = module or nil }
end
end
local nested = # hoisted . owners > 0
if nested then
c . pushScope ( )
for _ , owner in ipairs ( hoisted . owners ) do
for name , t in pairs ( owner . nestedTypes or { } ) do
c . bindType ( name , t , nil )
end
end
end
if c . preclaimAffine ( decl , decl . hoistedType ) then
changed = true
end
if nested then
c . popScope ( )
end
if aliased then
c . popScope ( )
end
end
end
if not changed then
do break end
end
end
c . preclaiming = nil

















local earlier = { }
local selected


= { }

local function selectedField ( field ) 
return function ( _ , name ) 
local selection = selected [ name ]
if not selection or not c . env or not c . env . resolveModuleExports then
return nil
end
local exports = c . env . resolveModuleExports ( c . env , selection . module )
local found = exports and exports [ field ]

return found and found [ selection . name ] or nil
end
end

local function resolvedBeforeBinding ( body , selfType ) 
if next ( earlier ) == nil and next ( selected ) == nil then
return c . signatureOf ( body , selfType )
end
local outer = c . scope
local vars = { }
for name , module in pairs ( earlier ) do
vars [ name ] = { t = T . any , requiredModule = module or nil }
end
local types = setmetatable ( { } , { __index = selectedField ( "types" ) } )
local typeDefs = setmetatable ( { } , { __index = selectedField ( "typeDefs" ) } )
c . scope = {
vars = vars ,
types = types ,
packTypes = { } ,
typeDefs = typeDefs ,
pending = { } ,
automaticOwners = { } ,
parent = outer ,
depth = outer and outer . depth or 0 ,
}
local signature = c . signatureOf ( body , selfType )
c . scope = outer

return signature
end

for _ , stat in ipairs ( block . stats or { } ) do
local decl = stat
while decl and decl . kind == "pragmaStmt" do
decl = decl . stat
end
if decl and decl . kind == "exportStmt" then
decl = decl . stat
while decl and decl . kind == "pragmaStmt" do
decl = decl . stat
end
end
if decl and decl . exported and ( decl . kind == "localFuncStmt" or decl . kind == "funcStmt" ) then
local nameTok = decl . kind == "localFuncStmt" and decl . name or decl . name and decl . name . base
if nameTok and decl . body then
local signature = resolvedBeforeBinding ( decl . body , nil )
local definition = nameTok . definition or c . definition ( nameTok , "function" )
definition . type = signature
c . moduleFields [ nameTok . text ] = signature
c . moduleFieldTokens [ nameTok . text ] = nameTok
c . moduleFieldDefs [ nameTok . text ] = definition
c . moduleFieldValues [ nameTok . text ] = decl . body
c . moduleFieldConst [ nameTok . text ] = true
c . moduleExports . values [ nameTok . text ] = signature
c . moduleExports . valueDefs [ nameTok . text ] = definition
end
end
local fname = decl and decl . kind == "funcStmt" and decl . name
local ownerKey , memberTok = nil , nil
if fname then
ownerKey , memberTok = c . funcOwner ( fname )
end
if ownerKey then
local owner = c . lookupType ( ownerKey )
local member = memberTok and memberTok . text
local nominalOwner = nil
if owner and owner . tag == "nominal" then
nominalOwner = owner
end
local isStatic = nominalOwner ~= nil
and not fname . method
and ( nominalOwner . declKind == "record" or nominalOwner . declKind == "interface" )
local members = nil
if nominalOwner then
members = isStatic and nominalOwner . staticByname or nominalOwner . byname
end
if nominalOwner and members and member and not members [ member ] then
local signature = resolvedBeforeBinding (
decl . body ,
fname . method and nominalOwner and generics . ownInstance ( nominalOwner ) or nil
)
members [ member ] = signature
if not isStatic then
nominalOwner . writeByname [ member ] = signature
else
nominalOwner . staticWriteByname [ member ] = signature
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
if decl and decl . kind == "localStmt" and decl . pattern then
local module = requiredLiteral ( decl . patternSource )
for _ , entry in ipairs ( decl . pattern ) do
local nameTok = entry . alias or entry . sourceName
if nameTok and entry . typeOnly then
selected [ nameTok . text ] = module
and entry . sourceName
and { module = module , name = entry . sourceName . text }
or nil
elseif nameTok then
earlier [ nameTok . text ] = module or false
end
end
elseif decl and decl . kind == "localStmt" then
for index , nameTok in ipairs ( decl . names or { } ) do
earlier [ nameTok . text ] = requiredLiteral ( decl . exprs and decl . exprs [ index ] ) or false
end
elseif decl and decl . kind == "localFuncStmt" and decl . name then
earlier [ decl . name . text ] = false
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
for j = # declarations , 1 , -1 do
local candidate = declarations [ j ]
local visible = c . scope
while visible and visible ~= candidate . scope do
visible = visible . parent
end
if visible then
pending = candidate
do break end
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






local runDeclarations = { }
local runBodies


= { }

local function settleRun ( ) 
for _ , pending in ipairs ( runBodies ) do
local hidden = { }
for later = ( pending . at ) + 1 , # runDeclarations do
local decl = runDeclarations [ later ]
if decl . name and not c . qualifierOf ( decl ) and c . visibilityOf ( decl ) ~= "global" then
local key = c . declKey ( decl )
local bound = c . scope . vars [ key ]
if bound and hidden [ key ] == nil then
hidden [ key ] = bound
c . scope . vars [ key ] = nil
end
end
end
pending . run ( )
for key , bound in pairs ( hidden ) do
c . scope . vars [ key ] = bound
end
end
runDeclarations , runBodies = { } , { }
end

for i , stat in ipairs ( stats ) do
c . nextStat = stats [ i + 1 ]
local decl = stat
while decl and ( decl . kind == "pragmaStmt" or decl . kind == "exportStmt" ) do
decl = decl . stat
end
if decl and ( decl . kind == "recordDecl" or decl . kind == "typeAlias" ) then
runDeclarations [ # runDeclarations + 1 ] = decl
local collected = { }
c . deferredBodies = collected
checkStat ( stat )
c . deferredBodies = nil
for _ , run in ipairs ( collected ) do
runBodies [ # runBodies + 1 ] = { at = # runDeclarations , run = run }
end
else
settleRun ( )
checkStat ( stat )
end
if c . callMayMutate then
c . facts . invalidateForCall ( )
c . callMayMutate = false
end
end
settleRun ( )
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







local function auditWithGotos ( block ) 
local labels = { }
local gotos


= { }

local function walk ( node , regions ) 
if not node or cst . isToken ( node ) then
return
end
if node . kind == "funcbody" or node . kind == "shortfn" then
if node . body then
auditWithGotos ( node . body )
end
return
end
local active = regions
if node . kind == "withStmt" then
active = { }
for region in pairs ( regions ) do
active [ region ] = true
end
active [ node ] = true
elseif node . kind == "labelStmt" and node . name then
labels [ node . name . text ] = labels [ node . name . text ] or { }
labels [ node . name . text ] [ # labels [ node . name . text ] + 1 ] = { node = node , regions = active }
elseif node . kind == "gotoStmt" and node . name then
gotos [ # gotos + 1 ] = { node = node , regions = active }
end
for _ , child in ipairs ( node ) do
walk ( child , active )
end
end

walk ( block , { } )
for _ , jump in ipairs ( gotos ) do
local targets = labels [ jump . node . name . text ]
local target = targets and targets [ 1 ]
if target then
for region in pairs ( target . regions ) do
if not jump . regions [ region ] then
c . diag ( "NUPP2706" , jump . node , "goto cannot enter a 'with' scope" )
do break end
end
end
end
end
end



if filename and filename : match ( "%.lua$" ) then
for _ , block in ipairs ( result . root . blocks ) do
reportTypedLayer ( c , block )
end
end



for _ , block in ipairs ( result . root . blocks ) do
c . checkBlock ( block , true )
auditWithGotos ( block )
end
if not opts . declarationFile then
reportModuleLocals ( c , result . root , declaredModuleName ~= nil )
end
if declaredModuleName then
reportRedeclaredExports ( c , result . root )
end
if declaredModuleName then
local assignment = cst . exportAssignment ( result . root )
if not assignment then
local fields = { }
for name , t in pairs ( c . moduleFields ) do
fields [ # fields + 1 ] = { name = name , read = t }
end
table . sort ( fields , function ( a , b ) 
return a . name < b . name
end )

c . moduleType = T . shape ( fields , nil , nil , true )
c . moduleTypeFromFields = true
else
for name , t in pairs ( c . moduleFields ) do
c . moduleExports . values [ name ] = t
c . moduleExports . valueDefs [ name ] = c . moduleFieldDefs [ name ]
end
if c . moduleType and c . moduleType . tag == "shape" then
for name , t in pairs ( c . moduleType . byname or { } ) do
c . moduleExports . values [ name ] = t
end
end
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
env . preludeComptimeFunctions = env . preludeComptimeFunctions or { }
for name , helper in pairs ( c . comptimeFunctions ) do
env . preludeComptimeFunctions [ name ] = helper
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

local optimizationDependencies = { }
local optimizationRoot = result . root
optimizationRoot . optimizationDependencies = optimizationDependencies
optimizationRoot . resolveCallableFact = function ( exact , family ) 
local key = table . concat ( { exact . module , exact . member , family } , "\0" )
optimizationDependencies [ key ] = true
return c . env
and c . env . resolveCallableFact
and c . env . resolveCallableFact ( c . env , exact . module , exact . member , family )
or nil
end



local function importEffects ( node ) 
if not node or cst . isToken ( node ) then
return
end
if node . kind == "call" then
local callee = node . obj
local exact = callee
and (
callee . exactCallExport
or callee . kind == "name"
and callee . token
and callee . token . definition
and callee . token . definition . exactCallExport
)
if exact and c . env and c . env . resolveCallableFact then
node . importedEffects = c . env . resolveCallableFact ( c . env , exact . module , exact . member , "callableEffects" )
node . importedRelations = c . env . resolveCallableFact (
c . env ,
exact . module ,
exact . member ,
"callableRelations"
)
end
end
for _ , child in ipairs ( node ) do
importEffects ( child )
end
end

importEffects ( result . root )

local analysisFacts = analysis . run ( result , c )




local effectQueries = analysis . queries ( analysisFacts )
local needsTrace = opts and opts . traceInspection or # c . jitHazards > 0
if not needsTrace then
for _ , info in ipairs ( analysisFacts . functions or { } ) do
if info . body and info . body . jitRequired then
needsTrace = true
do break end
end
end
end
if needsTrace and effectQueries then
traceSource . run ( result , c , analysisFacts , effectQueries )
end

local function cleanupNonRaising ( cleanup ) 
if cleanup . kind == "field" then
return cleanupNonRaising ( cleanup . cleanup )
end
if cleanup . kind ~= "function" then
return false
end
local queries = effectQueries
local known = queries and queries . known ( cleanup . token ) or nil
if known then
local visible = queries and queries . visible ( known . summary )
local free = visible and queries and queries . free ( known . summary , { "raises" } ) or false

return free == true
end




local module , qualified
if cleanup . key then
module , qualified = cleanup . key : match ( "^(.*)#(.*)$" )
end
local member = qualified and qualified : match ( "([^.]+)$" ) or nil
local guarantee = module
and member
and c . env
and c . env . resolveCallGuarantees
and c . env . resolveCallGuarantees ( c . env , module , member )
or nil

return guarantee and guarantee . noRaise == true or false
end





local function straightforwardWithBody ( body ) 
local straightforward = true

local function walk ( node , root ) 
if not node or not straightforward or cst . isToken ( node ) then
return
end
local kind = node . kind
if node ~= root
and (
kind == "localFuncStmt"
or kind == "funcStmt"
or kind == "inlineMethod"
or kind == "constructorDecl"
or kind == "funcExpr"
or kind == "shortfn"
)
then
return
end
local owners = node . automaticOwners or { }
if kind == "returnStmt"
or kind == "yieldStmt"
or kind == "breakStmt"
or kind == "continueStmt"
or kind == "gotoStmt"
or kind == "withStmt"
or # owners > 0
then
straightforward = false
return
end
for _ , child in ipairs ( node ) do
walk ( child , root )
end
end

walk ( body , body )

return straightforward
end

local function markDirectWith ( node ) 
if not node or cst . isToken ( node ) then
return
end
if node . kind == "withStmt" then
local bindings = node . bindings or { }
local direct = # bindings == 1
and straightforwardWithBody ( node . body )
and c . effectRegions . free ( node . body , "raises" , effectQueries )
for _ , cleanup in ipairs ( bindings [ 1 ] and bindings [ 1 ] . ownerCleanups or { } ) do
direct = direct and cleanupNonRaising ( cleanup )
end
if direct then
node . directCleanup = true
end
end
for _ , child in ipairs ( node ) do
markDirectWith ( child )
end
end

markDirectWith ( result . root )

for _ , block in ipairs ( analysisFacts . bodies or { } ) do
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
declare . checkEffectConformance ( c )
relations . invalidate ( )



own . finalizeCleanupBounds ( )
finalizeCallGuarantees ( c , effectQueries )
finalizeBoundary ( c )
c . privateExport . sweep ( )
c . nativeOnly . sweep ( result . root )







c . raises . sweep ( )
c . unused . sweep ( )
c . discard . sweep ( effectQueries )
c . nosuspend . sweep ( effectQueries )
c . effectRegions . sweep ( effectQueries )



for _ , named in ipairs ( c . cleanupBindings ) do
local definition = named . definition
if definition and definition . reassigned then
c . diag (
"NUPP2131" ,
named . at ,
("cleanup %q is reassigned, so it is not the const function affine needs") : format ( named . name ) ,
nil ,
{ help = "declare the terminal once and never assign to its name, or name a const function" }
)
end
end
for _ , literal in ipairs ( result . sendableLiterals or { } ) do
for _ , capture in ipairs ( literal . sendableCaptures or { } ) do
local definition = capture . definition
if definition and definition . reassigned then
c . diag (
"NUPP2006" ,
capture . token or literal ,
("sendable function capture %q is reassigned") : format ( capture . name ) ,
nil ,
{ help = "capture only a final or effectively final binding" }
)
end
end
end
require ( "nupp.compiler.compat" ) . checkSyntax ( c )
require ( "nupp.compiler.compat" ) . dependencies ( c , checkMod . check )
local comptimeNames = { }
local comptimeIdentities = { }
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
reflection . bindRuntimeDeclarations ( result . root , result . moduleName or result . declaredModuleName or "<chunk>" )

if opts . compat == "lua51" and not c . declarationFile then
local failed = false
for _ , diagnostic in ipairs ( c . diags ) do
failed = failed or diagnostic . severity == "error"
end
if not failed then
local _ , generated = require ( "nupp.compiler.lua.gen" ) . generate ( result , filename )
for _ , diagnostic in ipairs ( generated ) do
diagnostic . severity = diagnostic . severity or "error"
c . diags [ # c . diags + 1 ] = diagnostic
end
end
end

return c . diags , c . moduleType , c . moduleExports
end

local __nuppExportValue= checkMod ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check"]=__nuppExports;return __nuppExports