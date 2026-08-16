_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);


































local cst = require ( "nupp.compiler.cst" )
local predicate = require ( "nupp.compiler.predicate" )
local stdlib = require ( "nupp.compiler.stdlib" )
local cabi = require ( "nupp.compiler.cabi" )

local gen = { }




local COVERAGE_STATEMENTS = {
localStmt = true ,
assignStmt = true ,
compoundAssign = true ,
callStmt = true ,
ifStmt = true ,
whileStmt = true ,
fornumStmt = true ,
forinStmt = true ,
repeatStmt = true ,
doStmt = true ,
funcStmt = true ,
returnStmt = true ,
breakStmt = true ,
continueStmt = true ,
gotoStmt = true ,
unsafeStmt = true ,
noSuspendStmt = true ,
effectRegionStmt = true ,
}


local TYPE_KINDS = {
tname = true ,
topt = true ,
tptr = true ,
tunion = true ,
tintersection = true ,
tarray = true ,
tmap = true ,
ttuple = true ,
tshape = true ,
tshapeField = true ,
tfunc = true ,
tfuncParam = true ,
tparen = true ,
errorType = true ,
tpredicate = true ,
tborrows = true ,
tpreserves = true ,
tliteral = true ,
tconst = true ,
tcarray = true ,
generics = true ,



tpack = true ,
tpackUnion = true ,
captureClause = true ,



ttypecall = true ,
}



local DECL_KINDS = { recordDecl = true , typeAlias = true , }


local CP



local function cdefCType ( t )
if t . resolvedType then
local rendered = cabi . declaration ( t . resolvedType , "" , "ffi" )
if rendered then
return rendered
end
end
if t . kind == "topt" then
t = t . inner
end
if t . kind == "tname" then
local name = t . base . text
if name == "cstring" then
return "const char *"

elseif name == "voidptr" then
return "void *"
end

if ( name == "Success" or name == "Failure" ) and t . typeArgs and t . typeArgs [ 1 ] then
return cdefCType ( t . typeArgs [ 1 ] )
end
if t . cdefName then
return ( t . cdefKind or "struct" ) .. " " .. t . cdefName
end
return CP [ name ]
elseif t . kind == "tconst" then
local inner = cdefCType ( t . inner )
if inner then
return "const " .. inner
end
elseif t . kind == "tcarray" then



local element = cdefCType ( t . element )
if element then
return element .. "[" .. ( t . count and cst . textOf ( t . count ) or "?" ) .. "]"
end
elseif t . kind == "tptr" then
local inner = cdefCType ( t . inner )
if inner then
return inner .. " *"
end
elseif t . kind == "tfunc" then
local params = { }
for _ , param in ipairs ( t . params or { } ) do
if param . type then
local rendered = cdefCType ( param . type )
if not rendered then
return nil
end
params [ # params + 1 ] = rendered
elseif param . vararg or param [ 1 ] and cst . isToken ( param [ 1 ] ) and param [ 1 ] . kind == "..." then
params [ # params + 1 ] = "..."
end
end
local ret = "void"
if t . rets and # t . rets > 0 then
if # t . rets > 1 then
return nil
end
ret = cdefCType ( t . rets [ 1 ] )
if not ret then
return nil
end
end
return ( "%s (*)(%s)" ) : format ( ret , # params > 0 and table . concat ( params , ", " ) or "void" )
end

return nil
end

local C_PRIM = {
number = "double" ,
float = "float" ,
boolean = "bool" ,
integer = "int32_t" ,
int8 = "int8_t" ,
int16 = "int16_t" ,
int32 = "int32_t" ,
int64 = "int64_t" ,
uint8 = "uint8_t" ,
uint16 = "uint16_t" ,
uint32 = "uint32_t" ,
uint64 = "uint64_t" ,
}
CP = C_PRIM



local LOWERED_COMPOUND = { [ "//=" ] = true , [ "??=" ] = true }





local CONSTRUCTOR_MEMBER = "__nuppCtor"

local function constructorMember ( index )
return CONSTRUCTOR_MEMBER .. tostring ( index or 1 )
end


local IS_TYPE = {
string = "string" ,
number = "number" ,
boolean = "boolean" ,
table = "table" ,
thread = "thread" ,
userdata = "userdata" ,
integer = "number" ,
float = "number" ,
int8 = "number" ,
int16 = "number" ,
int32 = "number" ,
int64 = "number" ,
uint8 = "number" ,
uint16 = "number" ,
uint32 = "number" ,
uint64 = "number" ,
[ "function" ] = "function" ,
}




local literal = { }

function literal . quote ( s )
s = s : gsub ( "\\([`$])" , "%1" )
s = s : gsub ( '"' , '\\"' )
s = s : gsub ( "\n" , "\\n" )
return '"' .. s .. '"'
end






local function dedentLongString ( text )
local equals = text : match ( "^%[(=*)%[" )
if equals == nil then
return text
end
local delimiterLength = # equals + 2
local body = text : sub ( delimiterLength + 1 , # text - delimiterLength )
body = body : gsub ( "\r\n" , "\n" ) : gsub ( "\r" , "\n" )
if body : sub ( 1 , 1 ) == "\n" then
body = body : sub ( 2 )
end
local margin = body : match ( "\n([ \t]*)$" )
if margin then
body = body : sub ( 1 , # body - # margin )
else


for line in ( body .. "\n" ) : gmatch ( "([^\n]*)\n" ) do
if line : find ( "[^ \t]" ) then
local indent = line : match ( "^[ \t]*" ) or ""
if margin == nil then
margin = indent
else
local length = math . min ( # margin , # indent )
local shared = 0
while shared < length and margin : sub (
shared + 1 ,
shared + 1
) == indent : sub ( shared + 1 , shared + 1 ) do
shared = shared + 1
end
margin = margin : sub ( 1 , shared )
end
end
end
end
if margin and # margin > 0 then
local function strip ( line )
if line : sub ( 1 , # margin ) == margin then
return line : sub ( # margin + 1 )
end
return line
end

local first = body : match ( "^[^\n]*" ) or ""
body = strip ( first ) .. body : sub ( # first + 1 ) : gsub ( "\n([^\n]+)" , function ( line )
return "\n" .. strip ( line )
end )
end

return body
end




function literal . renderData ( value )
local recipeCodec = require ( "nupp.compiler.materialize.codec" )
local rendered , why = recipeCodec . render ( value )
if not rendered then
error ( "invalid closed compiler data: " .. tostring ( why ) )
end

return rendered
end




local function declPath ( x )
if not x . qualifiers then
return nil
end
local parts = { }
for _ , token in ipairs ( x . qualifiers ) do
parts [ # parts + 1 ] = token . text
end
parts [ # parts + 1 ] = x . name . text

return table . concat ( parts , "." )
end




















































function gen . generate (
result ,
filename ,
coverage ,
hot
)
local out = { }
local curLine = 1
local atLineStart = true
local diags = { }





local emittedFeatureEffects = { }
local function needRuntimeEffect ( effect )
emittedFeatureEffects [ effect ] = true
end

local tempCounter = 0
local usedNames = { }
for _ , tok in ipairs ( result . tokens or { } ) do
if tok . kind == "name" then
usedNames [ tok . text ] = true
end
end
local function nextTemp ( )
local name
repeat
tempCounter = tempCounter + 1
name = "__nuppT" .. tempCounter
until not usedNames [ name ]
usedNames [ name ] = true

return name
end

local needsMetatypeOnce = false
local metatypeOnceName


local structTag = { }
local structTagOrder = { }











local function planStructTags ( )
local structs , indexOf = { } , { }
local function collect ( node )
if not node or cst . isToken ( node ) then
return
end
if node . kind == "recordDecl" and node . declKind == "struct" and node . name then
structs [ # structs + 1 ] = node
indexOf [ node . name . text ] = # structs
end
for _ , child in ipairs ( node ) do
collect ( child )
end
end

collect ( result . root )









local moduleTag = ( result . moduleName or filename or "" ) : gsub ( "[^%w]" , "_" )
local function digest ( text )
local h = 2166136261
for i = 1 , # text do
h = bit . bxor ( h , text : byte ( i ) )
h = bit . band ( h * 16777619 , 0xffffffff )
end

return ( "%08x" ) : format ( bit . band ( h , 0x7fffffff ) )
end

local function tagFor ( name )
if structTag [ name ] then
return structTag [ name ]
end
local decl = structs [ indexOf [ name ] ]
local shape = { }
for _ , entry in ipairs ( decl and decl . entries or { } ) do
if entry . kind == "fieldDecl" and entry . name then
shape [ # shape + 1 ] = entry . name . text
end
end
local tag = "__nuppS_" .. name .. "_" .. digest ( moduleTag .. "|" .. name .. "|" .. table . concat ( shape , "," ) )
structTag [ name ] = tag
structTagOrder [ # structTagOrder + 1 ] = tag

return tag
end


local function referent ( entry )
local t = entry . type
if not t then
return nil
end
if t . kind == "topt" then
t = t . inner
end
if t . kind == "tptr" then
t = t . inner
end
local leaf = t and t . kind == "tname" and cst . lastName ( t ) or nil
if leaf and indexOf [ leaf ] then
return leaf
end

return nil
end



for at , decl in ipairs ( structs ) do
for _ , entry in ipairs ( decl . entries or { } ) do
if entry . kind == "fieldDecl" and entry . type then
local t = entry . type
if t . kind == "topt" then
t = t . inner
end
if t . kind == "tptr" and t . inner and t . inner . kind == "tname" then
local target = cst . lastName ( t . inner )
local targetAt = target and indexOf [ target ] or nil
if targetAt and targetAt >= at then
tagFor ( target )
end
end
end
end
end





local changed = true
while changed do
changed = false
for _ , decl in ipairs ( structs ) do
if structTag [ decl . name . text ] then
for _ , entry in ipairs ( decl . entries or { } ) do
local target = entry . kind == "fieldDecl" and referent ( entry )
if target and not structTag [ target ] then
tagFor ( target )
changed = true
end
end
end
end
end
end

local needsFfi = false
local needsArrayCache = false
local needsCArrayIndex = false
local carrayIndexName
local needsLibs = false
local needsNewTab = false
local needsClearTab = false
local needsCloneTab = false
local compilerModules = { }
local compilerModuleOrder = { }
local needsLayout = false
local layoutName
local needsSuspension = false
local suspensionName
local needsCleanupRegistry = false
local cleanupRegistryName
local cleanupResolvers = { }
local cleanupResolverOrder = { }
local newTabName , clearTabName , cloneTabName
local needsCleanupRegions = false
local cleanupPackName , cleanupIdName , cleanupFailureName




local cleanupGlobals


local cleanupCacheName
local cleanupCacheSites = 0
local cleanupStack = { }
local emitDepth = { loop = 0 , fn = 0 }
local coverageOn = coverage == true or type ( coverage ) == "table"
local coveragePath = coverageOn and (
type ( coverage ) == "table" and ( coverage ) . path or filename
) or nil
local coverageSites = nil
local coverageSiteCount = 0
local coverageName


local hotState = hot and {
mode = hot . mode ,
module = hot . module or result . moduleName or filename or "<chunk>" ,
baseGeneration = hot . baseGeneration ,
functions = { } ,
byNode = setmetatable ( { } , { __mode = "k" } ) ,
allByNode = setmetatable ( { } , { __mode = "k" } ) ,
captures = { } ,
only = hot . only ,
structure = { } ,
policies = { } ,
libraries = hot . libraries or { } ,
} or nil

local function reservedName ( preferred )
if not usedNames [ preferred ] then
usedNames [ preferred ] = true
return preferred
end

return nextTemp ( )
end

local function compactSource ( node )
if not node then
return ""
end
return ( cst . textOf ( node ) : gsub ( "%s+" , "" ) )
end

local function hotSignature ( body , implicitSelf )
local parts = { implicitSelf and "method(" or "function(" }
for index , param in ipairs ( body and body . params or { } ) do
if index > 1 then
parts [ # parts + 1 ] = ","
end
parts [ # parts + 1 ] = compactSource ( param )
end
parts [ # parts + 1 ] = "):"
parts [ # parts + 1 ] = compactSource ( body and body . returnPack )

return table . concat ( parts )
end

local function hotFunctionName ( node )
if node . kind == "localFuncStmt" and node . name then
return node . name . text
elseif node . kind == "funcStmt" and node . name then
return compactSource ( node . name )
elseif node . kind == "inlineMethod" and node . name then
return node . overloadMember or node . name . text
end

return nil
end

local function hotSelfReference ( node )
local definition = node . kind == "localFuncStmt" and node . name and node . name . definition or nil
if not definition then
return false
end
local found = false
local function walk ( child )
if found or not child or cst . isToken ( child ) then
return
end
if child . kind == "name" and child . token and child . token . definition == definition then
found = true
return
end
for _ , nested in ipairs ( child ) do
walk ( nested )
end
end

walk ( node . body and node . body . body )

return found
end

local function hotOuterCaptures ( node )
local captures = { }
local first = cst . firstToken ( node )
local last = cst . lastToken ( node )
local firstOffset = first and first . offset or 0
local lastOffset = last and last . offset or firstOffset
local own = node . kind == "localFuncStmt" and node . name and node . name . definition or nil
local function walk ( child )
if not child or cst . isToken ( child ) then
return
end
if child . kind == "name" and child . token and child . token . definition then
local definition = child . token . definition
local token = definition . token
if definition ~= own and token and token . line ~= 0 and (
token . offset < firstOffset or token . offset > lastOffset
) then
captures [ token . text ] = true
end
end
for _ , nested in ipairs ( child ) do
walk ( nested )
end
end

walk ( node . body )
local names = { }
for name in pairs ( captures ) do
names [ # names + 1 ] = name
end
table . sort ( names )

return names
end




local function hotCUses ( node )
local used , unknown = { } , false
local function walk ( child )
if not child or cst . isToken ( child ) then
return
end
if child . cdefIdentity then
used [ child . cdefIdentity ] = true
elseif child . kind == "name"
and child . token
and child . token . definition
and child . token . definition . cdefIdentity
then
used [ child . token . definition . cdefIdentity ] = true
elseif child . cdefCall or child . cdefDeclarationBlock or child . cheaderCdef then
unknown = true
end
if ( child . kind == "cdefFunc" or child . kind == "cdefStruct" ) and child . cdefIdentity then
used [ child . cdefIdentity ] = true
end
for _ , nested in ipairs ( child ) do
walk ( nested )
end
end

walk ( node . body )
local identities = { }
for identity in pairs ( used ) do
identities [ # identities + 1 ] = identity
end
table . sort ( identities )

return identities , unknown
end

local function planHotFunction ( node , owner )
if not hotState or not node . body or hotState . allByNode [ node ] then
return
end
local name = hotFunctionName ( node )
if not name then
return
end
local implicitSelf = node . kind == "funcStmt"
and node . name
and node . name . method ~= nil
or node . kind == "inlineMethod"
and not node . inlineStatic
local slot = # hotState . functions + 1
local kind = node . kind == "localFuncStmt" and "local" or node . kind == "inlineMethod" and "inline" or "field"
local id = table . concat ( { hotState . module , owner or "module" , kind , name } , "/" )
local captures = hotOuterCaptures ( node )
local affine = node . affineInitializer ~= nil or node . body and # ( node . body . takenCaptures or { } ) > 0
local affineCapture = affine and node . body and node . body . takenCaptures and node . body . takenCaptures [
1
] and node . body . takenCaptures [ 1 ] . name or nil
local cUses , cUnknown = hotCUses ( node )
local planned = {
node = node ,
slot = slot ,
id = id ,
name = node . hotRuntimeName or name ,
authoredName = name ,
selfName = node . kind == "localFuncStmt" and name or nil ,
selfRecursive = hotSelfReference ( node ) ,
signature = hotSignature ( node . body , implicitSelf ) ,
implicitSelf = implicitSelf ,
captures = captures ,
implementation = compactSource ( node . body and node . body . body ) ,
patchable = not affine ,
affineCapture = affineCapture ,
cUses = cUses ,
cUnknown = cUnknown ,
}
hotState . functions [ slot ] = planned
hotState . allByNode [ node ] = planned
if planned . patchable then
hotState . byNode [ node ] = planned
end
for _ , capture in ipairs ( captures ) do
hotState . captures [ capture ] = true
end
end

local function planHotRoot ( )
if not hotState then
return
end
local function rootStatement ( node )
if node and node . kind == "pragmaStmt" then
node = node . stat
end
if node and ( node . kind == "localFuncStmt" or node . kind == "funcStmt" ) then
if node . kind == "funcStmt" and node . structOwner and node . memberName then
node . hotRuntimeName = "__nuppMt_" .. node . structOwner .. ".__index" .. (
node . name and node . name . method and ":" or "."
) .. node . memberName
end
planHotFunction ( node , "module" )
elseif node and node . kind == "recordDecl" then
local runtimeOwner = declPath ( node ) or node . name and node . name . text
if node . declKind == "struct" then
runtimeOwner = "__nuppMt_" .. node . name . text .. ".__index"
end
for _ , entry in ipairs ( node . entries or { } ) do
if entry . kind == "inlineMethod" then
local member = entry . overloadMember or entry . name . text
entry . hotRuntimeName = runtimeOwner .. ( entry . inlineStatic and "." or ":" ) .. member
planHotFunction ( entry , "record:" .. tostring ( runtimeOwner ) )
end
end
end
end

for _ , node in ipairs ( result . root ) do
if not cst . isToken ( node ) then
if node . kind == "block" then
for _ , statement in ipairs ( node . stats or node ) do
if not cst . isToken ( statement ) then
rootStatement ( statement )
end
end
else
rootStatement ( node )
end
end
end
for _ , node in ipairs ( result . root ) do
if not cst . isToken ( node ) then
local statements = node . kind == "block" and ( node . stats or node ) or { node }
for _ , statement in ipairs ( statements ) do
if not cst . isToken ( statement ) then
local actual = statement . kind == "pragmaStmt" and statement . stat or statement
local planned = actual and hotState . allByNode [ actual ]
local structural = actual
while structural and structural . kind == "pragmaStmt" do
structural = structural . stat
end
if planned then
hotState . structure [ # hotState . structure + 1 ] = "function\0" .. planned . id
elseif structural and ( structural . kind == "cdefFunc" or structural . kind == "cdefStruct" ) then




else
local shape = compactSource ( statement )
local first , last = cst . firstToken ( statement ) , cst . lastToken ( statement )
for _ , nested in ipairs ( hotState . functions ) do
local nestedFirst , nestedLast = cst . firstToken ( nested . node ) , cst . lastToken ( nested . node )
if first
and last
and nestedFirst
and nestedLast
and nestedFirst . offset >= first . offset
and nestedLast . offset <= last . offset
and nested . implementation ~= ""
then
local pattern = nested . implementation : gsub ( "([^%w])" , "%%%1" )
shape = shape : gsub ( pattern , "<body>" , 1 )
end
end
hotState . structure [ # hotState . structure + 1 ] = shape
end
end
end
end
end
hotState . slotsExpr = reservedName ( "__nuppHotSlots" )
end

planHotRoot ( )

local helpers = { byBody = { } , order = { } }



















local function declareHelper ( prefix , params , body )
local key = params .. "|" .. body
local name = helpers . byBody [ key ]
if not name then
name = reservedName ( prefix .. tostring ( # helpers . order + 1 ) )
helpers . byBody [ key ] = name
helpers . order [ # helpers . order + 1 ] = { name = name , params = params , body = body }
end

return name
end





local function compilerModuleName ( moduleName )
if moduleName == "nupp.log" then



needRuntimeEffect ( "stdlib.log" )
end
local name = compilerModules [ moduleName ]
if not name then
local preferred = moduleName == "string.buffer" and "__nuppBuffer" or "__nuppModule"
name = reservedName ( preferred )
compilerModules [ moduleName ] = name
compilerModuleOrder [ # compilerModuleOrder + 1 ] = moduleName
end

return name
end

local function metatypeHelper ( )
needsMetatypeOnce = true
metatypeOnceName = metatypeOnceName or reservedName ( "__nuppMetatype" )
return metatypeOnceName
end

local function concatBufferName ( )
return compilerModuleName ( "string.buffer" )
end




local function suspensionModule ( )
needsSuspension = true
needRuntimeEffect ( "runtime.suspension" )
suspensionName = suspensionName or reservedName ( "__nuppSuspension" )

return suspensionName
end

local function tableIntrinsicName ( name )
if name == "new" then
needsNewTab = true
newTabName = newTabName or reservedName ( "__nuppNew" )

return newTabName
elseif name == "clone" then
needsCloneTab = true
cloneTabName = cloneTabName or reservedName ( "__nuppClone" )

return cloneTabName
end
needsClearTab = true
clearTabName = clearTabName or reservedName ( "__nuppClear" )

return clearTabName
end

local function cleanupRegistry ( )
needsCleanupRegistry = true
cleanupRegistryName = cleanupRegistryName or reservedName ( "__nuppCleanups" )

return cleanupRegistryName
end

local function cleanupFunctionName ( cleanup )
local found = cleanupResolvers [ cleanup . id ]
if found then
return found
end
local name = reservedName ( "__nuppCleanup" .. tostring ( # cleanupResolverOrder + 1 ) )
cleanupResolvers [ cleanup . id ] = name
cleanupResolverOrder [ # cleanupResolverOrder + 1 ] = { cleanup = cleanup , name = name }
cleanupRegistry ( )

return name
end

local function cleanupCall ( cleanup , value )
if cleanup . kind == "function" then
return cleanupFunctionName ( cleanup ) .. "(" .. value .. ")"
elseif cleanup . kind == "closure" then
return value .. ":__nuppRelease()"
elseif cleanup . kind == "method" then
return value .. ":" .. cleanup . name .. "()"
elseif cleanup . kind == "field" then
return cleanupCall ( cleanup . cleanup , value .. "." .. cleanup . field )
end

return nil
end




local function ensureCleanupRuntime ( )
needsCleanupRegions = true
if cleanupPackName then
return
end
cleanupPackName = nextTemp ( )
cleanupIdName = nextTemp ( )
cleanupFailureName = nextTemp ( )
cleanupCacheName = nextTemp ( )
cleanupGlobals = { }
for _ , name in ipairs ( { "pcall" , "xpcall" , "error" , "unpack" , "select" , "setmetatable" , "tostring" , "ipairs" } ) do
cleanupGlobals [ name ] = nextTemp ( )
end
end

local function protectedCleanupCall ( cleanup , value , pcallName )
if cleanup . kind == "function" then
return pcallName .. "(" .. cleanupFunctionName ( cleanup ) .. "," .. value .. ")"
elseif cleanup . kind == "closure" then
local caller = declareHelper ( "__nuppClosureCleanup" , "__nuppV" , "return __nuppV:__nuppRelease()" )
return pcallName .. "(" .. caller .. "," .. value .. ")"
elseif cleanup . kind == "method" then





local caller = declareHelper ( "__nuppCleanup" , "__nuppV" , ( "return __nuppV:%s()" ) : format ( cleanup . name ) )
return pcallName .. "(" .. caller .. "," .. value .. ")"
elseif cleanup . kind == "field" then
return protectedCleanupCall ( cleanup . cleanup , value .. "." .. cleanup . field , pcallName )
end

return nil
end

local function diag ( tok , code , msg , help )
diags [
# diags + 1
] = {
code = code ,
msg = msg ,
filename = filename ,
help = help ,
line = tok and tok . line or 0 ,
col = tok and tok . col or 0 ,
offset = tok and tok . offset or 0 ,
length = tok and # tok . text or 0
}
end


local function raw ( s )
out [ # out + 1 ] = s
local _ , n = s : gsub ( "\n" , "" )
if n > 0 then
curLine = curLine + n
atLineStart = s : sub ( - 1 ) == "\n"
elseif # s > 0 then
atLineStart = false
end
end


local function sync ( line )
while line and curLine < line do
local tail = out [ # out ]
if tail then
out [ # out ] = tail : gsub ( "[ \t]+$" , "" )
end
raw ( "\n" )
end
end


local function e ( text , line )
sync ( line )
if not atLineStart then
raw ( " " )
end
raw ( text )
end






















local function loweredFunction ( text , line , reason )
if emitDepth . loop > 0 and not reason then
error (
"gen: a lowering built a function inside a loop without saying why. "
.. "LuaJIT cannot record that, so the loop will never compile. Declare it "
.. "once with pluck.declareHelper and call it, or pass a reason when the "
.. "body assigns one of its own site's locals. Emitted: "
.. tostring (
text
) ,
0
)
end
e ( text , line )
end






local function finishConcatBuffer ( x , line )
if x . concatBuffer then
e ( ( "%s = %s:tostring()" ) : format ( x . concatBuffer . target , x . concatBuffer . name ) , line )
end
end

local function emitDerivedMembers ( x , runtimeName )
local recipe = x . deriveRecipe
if not recipe then
return
end
for effect in pairs ( recipe . effects or { } ) do
needRuntimeEffect ( effect )
end
local recipeCodec = require ( "nupp.compiler.materialize.codec" )
local renderedRecipe , renderError = recipeCodec . render ( recipe , { limit = recipeCodec . MAX_OUTPUT_BYTES , } )
if not renderedRecipe then
diag (
x . name ,
"NUPP2808" ,
renderError == "limit" and (
"derive output exceeds %d rendered bytes"
) : format ( recipeCodec . MAX_OUTPUT_BYTES ) or "derive output recipe is invalid" ,
"split the record or write the generated behavior explicitly"
)
return
end
needRuntimeEffect ( "stdlib.derives" )
e ( ";do local __nuppDerived=" .. renderedRecipe )
e ( ( ";local __nuppDerivedEntry=_G.nupp.__derive.register(%q,%s,__nuppDerived)" ) : format ( recipe . key , runtimeName ) )

local function forwardingArgument ( argument , parameters )
if argument . kind == "receiver" then
return "self"
elseif argument . kind == "entry" then
return "__nuppDerivedEntry"
elseif argument . kind == "argument" then
return parameters [ argument . name ] or error ( "invalid derived member argument " .. tostring ( argument . name ) )
elseif argument . kind == "field" then
return ( "self[%q]" ) : format ( argument . name )
elseif argument . kind == "constant" then
local rendered , why = recipeCodec . render ( argument . value , { limit = recipeCodec . MAX_OUTPUT_BYTES , } )
if not rendered then
error ( "invalid derived constant: " .. tostring ( why ) )
end
return rendered
elseif argument . kind == "array" then
local children = { }
for index , child in ipairs ( argument . values or { } ) do
children [ index ] = forwardingArgument ( child , parameters )
end
return "{" .. table . concat ( children , "," ) .. "}"
end
error ( "unknown derived forwarding argument " .. tostring ( argument . kind ) )
end

for _ , member in ipairs ( recipe . members or { } ) do
if member . operation == "forward.v1" then
local names , parameters = { } , { }
local first = 1
if member . namespace == "instance" then
names [ 1 ] = "self"
first = 2
end
for index = first , # ( member . paramNames or { } ) do
local declared = member . paramNames [ index ]
local runtimeParameter = declared ~= "" and declared or ( "argument" .. tostring ( index - first + 1 ) )
names [ # names + 1 ] = runtimeParameter
if declared ~= "" then
parameters [ declared ] = runtimeParameter
end
end
local arguments = { }
for index , argument in ipairs ( member . arguments or { } ) do
arguments [ index ] = forwardingArgument ( argument , parameters )
end
local helper = member . helper . localPath or (
"_G.require(" .. string . format (
"%q" ,
member . helper . module
) .. ")[" .. string . format ( "%q" , member . helper . member ) .. "]"
)
e (
(
";%s[%q]=function(%s)return %s(%s)end"
) : format ( runtimeName , member . name , table . concat ( names , "," ) , helper , table . concat ( arguments , "," ) )
)
else
error ( "unknown derived member operation " .. tostring ( member . operation ) )
end
end
e ( " end" )
end

local emit

local function sourceLine ( node )
if not node then
return nil
end
if cst . isToken ( node ) then
return node . line
end
for _ , child in ipairs ( node ) do
local line = sourceLine ( child )
if line then
return line
end
end

return nil
end















local pluck = {
plans = { } ,
statementActive = { } ,
helpers = helpers ,
declareHelper = declareHelper ,
loweredFunction = loweredFunction ,
emitDerivedMembers = emitDerivedMembers ,
quote = literal . quote ,
renderData = literal . renderData ,
hotLibraries = hot and hot . libraries or { } ,












reasons = {
capture = "the body sets this site's own capture flags" ,
reinit = "the body sets this site's own reinit flag" ,
move = "the body clears this site's own move flag" ,
cheader = "a C header is declared once where it is imported" ,
region = "the protected body reads and writes this region's own owners and flags" ,
} ,
}

local function dottedPathParts ( node )
if not node or cst . isToken ( node ) then
return nil , nil
end
if node . kind == "name" then
return node . token and node . token . text or nil , { }
end
if node . kind ~= "dotIndex" or not node . name then
return nil , nil
end
local root , parts = dottedPathParts ( node . obj )
if not root or not parts then
return nil , nil
end
parts [ # parts + 1 ] = node . name . text

return root , parts
end

local function pluckableCall ( call )
if call . kind == "methodCall" then
return call . obj ~= nil and call . name ~= nil
end

if call . kind ~= "call" and call . kind ~= "safeCall" then
return false
end
if call . kind == "safeCall" then
return not call . tableIntrinsic
and not call . ffiOutContracts
and not call . ownershipIntrinsic
and not call . ffiIntrinsic
and not call . carrayElem
and not call . cheaderCdef
and not call . constructorCall
and not call . recordConstruct
and not call . layoutOf
and not call . passPinnedPointer
end

return not call . ownershipIntrinsic
and not call . ffiIntrinsic
and not call . carrayElem
and not call . cheaderCdef
and not call . recordConstruct
and not call . layoutOf
and not call . passPinnedPointer
end

function pluck . callPlan ( call )
if not pluckableCall ( call ) or not call . obj or not call . args or not call . args . loweredArgs then
return nil
end
local hasDotted = false
for _ , argument in ipairs ( call . args . loweredArgs ) do
if argument . generatedKind == "field" and argument . source and argument . source . kind == "dotIndex" then
hasDotted = true
break
end
end
if not hasDotted then
return nil
end

local plan = {
call = call ,
setupSteps = { } ,
afterReceiverSteps = { } ,
steps = { } ,
pathAliases = { } ,
argAliases = { } ,
argFields = { } ,
}
plan . delegate = call . staticCallee or call . tableIntrinsic or call . ffiOutContracts or call . constructorCall
if call . kind == "methodCall" then
plan . receiverAlias = nextTemp ( )
plan . setupSteps [
# plan . setupSteps + 1
] = { kind = "expr" , name = plan . receiverAlias , expr = call . obj , at = call . obj }
plan . methodName = call . overloadMember or call . name . text
plan . safeReceiver = call . safeObj ~= nil
if call . safeMethod then
plan . methodAlias = nextTemp ( )
plan . afterReceiverSteps [
# plan . afterReceiverSteps + 1
] = {
kind = "field" ,
name = plan . methodAlias ,
base = plan . receiverAlias ,
field = plan . methodName ,
at = call ,
}
plan . safeMethod = true
end
plan . isSafe = plan . safeReceiver or plan . safeMethod
elseif call . kind == "safeCall" then
plan . calleeAlias = nextTemp ( )
plan . setupSteps [
# plan . setupSteps + 1
] = { kind = "expr" , name = plan . calleeAlias , expr = call . obj , at = call . obj }
plan . safeCallee = true
plan . isSafe = true
elseif call . obj . kind ~= "name" then



plan . calleeAlias = nextTemp ( )
plan . setupSteps [
# plan . setupSteps + 1
] = { kind = "expr" , name = plan . calleeAlias , expr = call . obj , at = call . obj }
end

local function bindPath ( source )
local root , parts = dottedPathParts ( source )
if not root or not parts then
return nil
end
local base = root
local key = root
for _ , field in ipairs ( parts ) do
key = key .. "\0" .. field
local alias = plan . pathAliases [ key ]
if not alias then
alias = nextTemp ( )
plan . pathAliases [ key ] = alias
plan . steps [
# plan . steps + 1
] = { kind = "field" , name = alias , base = base , field = field , at = source }
end
base = alias
end

return base
end

local lastDotted = 0
for index , argument in ipairs ( call . args . loweredArgs ) do
if argument . generatedKind == "field" and argument . source and argument . source . kind == "dotIndex" then
lastDotted = index
end
end

for index , argument in ipairs ( call . args . loweredArgs ) do
if argument . generatedKind == "field" then
local base
if argument . source and argument . source . kind == "name" then
base = argument . source . token and argument . source . token . text or nil
else
base = bindPath ( argument . source )
end
if base then
plan . argFields [ argument ] = { base = base , field = argument . name }
end
elseif argument . generatedKind == "expr" and not argument . pack and index < lastDotted then


local alias = nextTemp ( )
plan . argAliases [ argument ] = alias
plan . steps [ # plan . steps + 1 ] = { kind = "expr" , name = alias , expr = argument . expr , at = argument . expr }
end
end

return plan
end

function pluck . emitSteps ( steps )
for _ , step in ipairs ( steps ) do
e ( "const " .. step . name .. "=" , sourceLine ( step . at ) )
if step . kind == "field" then
e ( step . base .. "." .. step . field )
else
emit ( step . expr )
end
e ( ";" )
end
end

function pluck . directCall ( statement )
local kind = statement . kind
local direct
if kind == "callStmt" then
direct = statement . expr
elseif (
kind == "returnStmt" or kind == "localStmt" or kind == "assignStmt"
) and statement . exprs and # statement . exprs == 1 then
direct = statement . exprs [ 1 ]
end



if direct and direct . kind == "newExpr" then
return direct . call
end

return direct
end

function pluck . emitArgument ( argument , owner )
local alias = pluck . argumentAliases and pluck . argumentAliases [ argument ]
local field = pluck . argumentFields and pluck . argumentFields [ argument ]
if alias then
e ( alias , sourceLine ( argument . expr or argument . source or owner ) )
elseif field then
e ( field . base .. "." .. field . field , sourceLine ( argument . source or owner ) )
elseif argument . generatedKind == "field" then
emit ( argument . source )
e ( "." .. argument . name , sourceLine ( argument . source ) )
elseif argument . generatedKind == "nil" then
e ( "nil" , sourceLine ( owner ) )
else
emit ( argument . expr )
end
end

function pluck . emitArgs ( args )
for j , argument in ipairs ( args . loweredArgs or { } ) do
if j > 1 then
e ( "," )
end
pluck . emitArgument ( argument , args )
end
end

function pluck . formatHelper ( plan )
local params , arguments = { } , { }
for index , debug in ipairs ( plan . debugArguments or { } ) do
local name = "__nuppA" .. tostring ( index )
params [ index ] = name
arguments [ index ] = debug and name .. ":debug()" or name
end
local body = (
"return string.format(%q%s)"
) : format ( plan . format , # arguments > 0 and "," .. table . concat ( arguments , "," ) or "" )

return pluck . declareHelper ( "__nuppFormat" , table . concat ( params , "," ) , body )
end

function pluck . activate ( plan )
local prior = { aliases = pluck . argumentAliases , fields = pluck . argumentFields , }
pluck . argumentAliases = plan . argAliases
pluck . argumentFields = plan . argFields
pluck . plans [ plan . call ] = plan

return prior
end

function pluck . restore ( plan , prior )
pluck . plans [ plan . call ] = nil
pluck . argumentAliases = prior . aliases
pluck . argumentFields = prior . fields
end

function pluck . emitCall ( call , plan )
if plan . methodAlias then
e ( plan . methodAlias .. "(" .. plan . receiverAlias , sourceLine ( call ) )
if call . args and # ( call . args . loweredArgs or { } ) > 0 then
e ( "," )
pluck . emitArgs ( call . args )
end
e ( ")" )
elseif plan . receiverAlias then
e ( plan . receiverAlias .. ":" .. plan . methodName , sourceLine ( call ) )
emit ( call . args )
else
if plan . calleeAlias then
e ( plan . calleeAlias , sourceLine ( call ) )
else
emit ( call . obj )
end
emit ( call . args )
end
end

function pluck . emitStatement ( statement , call , plan )
pluck . emitSteps ( plan . setupSteps )
local guards = 0
if plan . safeReceiver then
e ( "if " .. plan . receiverAlias .. "~=nil then" )
guards = guards + 1
end
pluck . emitSteps ( plan . afterReceiverSteps )
if plan . safeCallee then
e ( "if " .. plan . calleeAlias .. "~=nil then" )
guards = guards + 1
end
if plan . safeMethod then
e ( "if " .. plan . methodAlias .. "~=nil then" )
guards = guards + 1
end
pluck . emitSteps ( plan . steps )
local prior = pluck . activate ( plan )
emit ( statement )
pluck . restore ( plan , prior )
for _ = 1 , guards do
e ( "end" )
end
end

function pluck . emitReturn ( statement , plan )
pluck . emitSteps ( plan . setupSteps )
if plan . safeReceiver then
e ( "if " .. plan . receiverAlias .. "==nil then return nil end;" )
end
pluck . emitSteps ( plan . afterReceiverSteps )
if plan . safeCallee then
e ( "if " .. plan . calleeAlias .. "==nil then return nil end;" )
end
if plan . safeMethod then
e ( "if " .. plan . methodAlias .. "==nil then return nil end;" )
end
pluck . emitSteps ( plan . steps )
local prior = pluck . activate ( plan )
emit ( statement )
pluck . restore ( plan , prior )
end

local function coverageRuntime ( )
coverageName = coverageName or reservedName ( "__nuppCoverage" )
return coverageName
end

local function coverageSite ( kind , node )
coverageSiteCount = coverageSiteCount + 1
local id = coverageSiteCount
local sites = coverageSites or { }
coverageSites = sites
sites [ # sites + 1 ] = { id = id , kind = kind , line = sourceLine ( node ) or 0 }

return id
end

local function coverageHit ( kind , node )
if not coverageOn then
return
end
local id = coverageSite ( kind , node )
e ( ( "%s.hit(%q,%d);" ) : format ( coverageRuntime ( ) , coveragePath , id ) , sourceLine ( node ) )
end

local function coverageStatement ( node )
if not node or cst . isToken ( node ) then
return false
end
if node . kind == "recordDecl" then
return node . declKind == "record" or node . declKind == "struct"
end

return COVERAGE_STATEMENTS [ node . kind ] == true
end

local function hotEmitImplementation ( planned )
local body = planned . node . body
local names = { }
if planned . implicitSelf then
names [ # names + 1 ] = "self"
end
for index , param in ipairs ( body . params or { } ) do
if not ( planned . implicitSelf and index == 1 and param . name and param . name . text == "self" ) then
if param . namedVararg then
names [ # names + 1 ] = "..."
elseif param . name then
names [ # names + 1 ] = param . name . text
elseif param [ 1 ] and cst . isToken ( param [ 1 ] ) and param [ 1 ] . kind == "..." then
names [ # names + 1 ] = "..."
end
end
end
local line = sourceLine ( planned . node )
e ( "function(" .. table . concat ( names , "," ) .. ")" , line )
if body . varargParam then
e ( ( "const %s={n=select(\"#\",...),...}" ) : format ( body . varargParam . name . text ) )
end
emitDepth . fn = emitDepth . fn + 1
if coverageOn then
coverageHit ( "function" , body )
end
if body . body then
emit ( body . body )
end
emitDepth . fn = emitDepth . fn - 1
local endToken
for index = # body , 1 , - 1 do
local child = body [ index ]
if cst . isToken ( child ) and child . kind == "end" then
endToken = child
break
end
end
e ( "end" , endToken and endToken . line or nil )
end

local function hotDefinePrefix ( planned )
return (
"_G.__nuppHotReload.define(%s,%d,%q,%q,%s,"
) : format (
hotState . slotsExpr ,
planned . slot ,
planned . id ,
planned . signature ,
planned . selfName and string . format ( "%q" , planned . selfName ) or "nil"
)
end

local function hotEmitFunction ( planned )
local node = planned . node
local line = sourceLine ( node )
if node . kind == "localFuncStmt" then
if hotState . mode == "initial" or planned . selfRecursive then
e ( "local " .. planned . name .. ";" , line )
end
e ( hotDefinePrefix ( planned ) , line )
hotEmitImplementation ( planned )
e ( ")" )
if hotState . mode == "initial" then
e ( ( ";%s=function(...) return %s[%d](...) end" ) : format ( planned . name , hotState . slotsExpr , planned . slot ) )
end
else
e ( hotDefinePrefix ( planned ) , line )
hotEmitImplementation ( planned )
e ( ")" )
if hotState . mode == "initial" then
local forwarded = planned . implicitSelf and "self,..." or "..."
e (
(
";function %s(...) return %s[%d](%s) end"
) : format ( planned . name , hotState . slotsExpr , planned . slot , forwarded )
)
end
end
end

local function hotSelected ( planned )
return planned . patchable and ( not hotState . only or hotState . only [ planned . id ] == true )
end




if hotState then
pluck . hotDispatch = { byNode = hotState . byNode , emit = hotEmitFunction }
end

local emitAutomaticBlock
local function emitChildren ( n )
if n . kind == "suspensionInstallExpr" then
e ( suspensionModule ( ) .. ".install(" , sourceLine ( n ) )
emit ( n . handler )
e ( ")" )
return
end
if n . kind == "block" and n . automaticOwners and # n . automaticOwners > 0 then
emitAutomaticBlock ( n )
return
end
for _ , child in ipairs ( n ) do
emit ( child )
end
end







local function emitInheritedDefaults ( x , runtimeName )
local taken = x . inheritedDefaultNames
if not taken or # taken == 0 then
return
end
local line = sourceLine ( x )
local parts = { }
for _ , one in ipairs ( taken ) do
parts [
# parts + 1
] = (
"%s.%s = %s.%s"
) : format ( runtimeName , one . member or one . name , one . from , one . fromMember or one . member or one . name )
end
e ( table . concat ( parts , " " ) , line )
end

local function labelsIn ( block )
local labels = { }
local function walk ( n )
if not n or cst . isToken ( n ) then
return
end
if n . kind == "funcbody" then
return
end
if n . kind == "cleanupRegion" then
return
end
if n . kind == "labelStmt" and n . name then
labels [ n . name . text ] = true
end
for _ , child in ipairs ( n ) do
walk ( child )
end
end

walk ( block )

return labels
end







local function usesVararg ( block )
local found = false
local function walk ( n )
if found or not n or cst . isToken ( n ) then
return
end
if n . kind == "funcbody" or n . kind == "shortfn" then
return
end
if n . kind == "vararg" then
found = true
return
end
for _ , child in ipairs ( n ) do
walk ( child )
end
end

walk ( block )

return found
end













local chunkLocals
local function isChunkLocal ( definition )
if not chunkLocals then
local found = { }
local function declare ( stat )
if cst . isToken ( stat ) then
return
end


if stat . kind == "block" then
for _ , inner in ipairs ( stat . stats or stat ) do
declare ( inner )
end

return
end
if stat . kind == "pragmaStmt" and stat . stat then
declare ( stat . stat )

return
end
if stat . kind ~= "localStmt" and stat . kind ~= "localFuncStmt" then
return
end
for _ , name in ipairs ( stat . names or ( stat . name and { stat . name } ) or { } ) do
if name . definition then
found [ name . definition ] = true
end
end
end

for _ , stat in ipairs ( result . root or { } ) do
declare ( stat )
end
chunkLocals = found
end

return chunkLocals [ definition ] == true
end











local function automaticCaptures ( block , bindings )
local localBindings = { }
local firstOffset
for _ , binding in ipairs ( bindings or { } ) do
localBindings [ binding . name and binding . name . definition ] = true
local offset = binding . name and binding . name . offset
if offset and ( not firstOffset or offset < firstOffset ) then
firstOffset = offset
end
end
local captured = false
local function walk ( node )
if captured or not node or cst . isToken ( node ) then
return
end
if node . kind == "name" and node . token and node . token . definition then
local definition = node . token . definition
local token = definition . token
if not localBindings [
definition
] and token and firstOffset and token . offset < firstOffset and token . line ~= 0 and not isChunkLocal (
definition
) then
captured = true
return
end
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

walk ( block )

return captured
end






emitAutomaticBlock = function ( block )
local stats = block . stats or { }
if block . automaticDirect then
for _ , stat in ipairs ( stats ) do
emit ( stat )
end
local owner = block . automaticDirect
for _ , cleanup in ipairs ( owner . cleanups or { } ) do
local call = cleanupCall ( cleanup , owner . name )
if call then
e ( call .. ";" , owner . boundary and owner . boundary . line or nil )
end
end
return
end
local first
for index , stat in ipairs ( stats ) do
if stat . automaticOwners and # stat . automaticOwners > 0 then
first = index
break
end
end
if not first then
for _ , child in ipairs ( block ) do
emit ( child )
end
return
end
for index = 1 , first - 1 do
emit ( stats [ index ] )
end
local bindings , sequence , bodyStats = { } , { } , { }
for index = first , # stats do
local stat = stats [ index ]
local owners = stat . automaticOwners or { }
local ownerCount = 0
local ownerNames = stat . names or ( stat . name and { stat . name } ) or { }
for j = 1 , # ownerNames do
if owners [ j ] and owners [ j ] . lowerable then
ownerCount = ownerCount + 1
end
end
if (
stat . kind == "localStmt" or stat . kind == "localFuncStmt" and stat . affineInitializer
) and ownerCount > 0 then
local group = { }
local names = stat . names or ( stat . name and { stat . name } ) or { }
local exprs = stat . exprs or ( stat . affineInitializer and { stat . affineInitializer } ) or { }
for j = 1 , # names do
local owner = owners [ j ]
if owner and owner . lowerable then
local expr = exprs [ j ] or exprs [ # exprs ]
local binding = {
kind = "cleanupBinding" ,
name = names [ j ] ,
expr = expr ,
declarationIndex = j ,
ownerCleanups = owner . cleanups ,
automaticOwner = owner ,
isConst = stat . isConst ,
}
bindings [ # bindings + 1 ] = binding
group [ # group + 1 ] = binding
end
end
local simple = # names == 1 and # exprs == 1
sequence [ # sequence + 1 ] = simple and { bindings = group } or { declaration = stat , bindings = group }
else
sequence [ # sequence + 1 ] = { stat = stat }
bodyStats [ # bodyStats + 1 ] = stat
end
end
if # bindings == 0 then



for _ , item in ipairs ( sequence ) do
emit ( item . stat )
end
return
end
local body = { kind = "block" , stats = bodyStats }
for _ , stat in ipairs ( bodyStats ) do
body [ # body + 1 ] = stat
end
local region = {
kind = "cleanupRegion" ,
startTok = bindings [ 1 ] . name ,
doTok = bindings [ 1 ] . name ,
endTok = cst . lastToken ( block ) ,
bindings = bindings ,
body = body ,
automaticRegion = true ,
automaticSequence = sequence ,
}
region . automaticComplex = # bindings == 1 and sequence [ 1 ] and sequence [ 1 ] . declaration ~= nil
region . capturesEnclosing = automaticCaptures ( body , bindings )
emit ( region )
end

local function activeWith ( move )
local owner = move and ( move . owner or move ) or nil
for index = # cleanupStack , 1 , - 1 do
local ctx = cleanupStack [ index ]
if ctx . functionDepth == emitDepth . fn then
if owner then
local state = ctx . automaticMap and ctx . automaticMap [ owner ]
if state then
if move . field and state . fields then
return state . fields [ move . field ]
end
return state . whole
end
else
return ctx
end
elseif not owner then
break
end
end

return nil
end

local function ownershipMoveOf ( expr )
while expr and ( expr . kind == "paren" or expr . kind == "castExpr" ) do
expr = expr . expr
end
return expr and expr . automaticOwnerMove or nil
end

local function automaticSlot ( move )
local owner = move and ( move . owner or move ) or nil
if not owner then
return nil
end
for index = # cleanupStack , 1 , - 1 do
local ctx = cleanupStack [ index ]
if ctx . functionDepth == emitDepth . fn then
local state = ctx . automaticMap and ctx . automaticMap [ owner ]
if state then
return state . slot
end
end
end

return nil
end




emitDepth . affineFunction = function ( x )
local body = x . body
local captures = body and body . takenCaptures or { }
local active = nextTemp ( )
local callable = nextTemp ( )
local wrapper = nextTemp ( )
local line = sourceLine ( x )
local names = { }
for _ , capture in ipairs ( captures ) do
names [ # names + 1 ] = capture . name
end
pluck . loweredFunction (
( "(function(%s) local %s=true; " ) : format ( table . concat ( names , "," ) , active ) ,
line ,
pluck . reasons . capture
)
for _ , capture in ipairs ( captures ) do
local outerActive = activeWith ( capture . move )
if outerActive then
e ( ( "%s=false; " ) : format ( outerActive ) )
end
end
e ( ( "local %s=function" ) : format ( callable ) )
local enclosingCleanupStack = cleanupStack
cleanupStack = { }
emit ( body )
cleanupStack = enclosingCleanupStack
e ( ( "; local %s={}; " ) : format ( wrapper ) )
e ( ( "%s.__nuppRelease=function() if not %s then return end; %s=false; " ) : format ( wrapper , active , active ) )
local errors = nextTemp ( )
local errorCount = nextTemp ( )
e ( ( "local %s={}; local %s=0; " ) : format ( errors , errorCount ) )
for captureIndex = # captures , 1 , - 1 do
local capture = captures [ captureIndex ]
for _ , cleanup in ipairs ( capture . type . cleanups or { } ) do
local call = protectedCleanupCall ( cleanup , capture . name , cleanupGlobals . pcall )
if call then
local ok , reason = nextTemp ( ) , nextTemp ( )
e (
(
"local %s,%s=%s; if not %s then %s=%s+1; %s[%s]=%s end; "
) : format ( ok , reason , call , ok , errorCount , errorCount , errors , errorCount , reason )
)
end
end
end
e (
(
"if %s>0 then if %s>1 then %s(%s(%s[1],%s,2),0) " .. "else %s(%s[1],0) end end end; "
) : format (
errorCount ,
errorCount ,
cleanupGlobals . error ,
cleanupFailureName ,
errors ,
errors ,
cleanupGlobals . error ,
errors
)
)
e (
(
"return setmetatable(%s,{__call=function(_,...) if not %s then %s(%q,2) end; "
) : format ( wrapper , active , cleanupGlobals . error , "nupp: affine closure was already called or dropped" )
)
e ( ( "%s=false; return %s(...) end}) end)(" ) : format ( active , callable ) )
for j , capture in ipairs ( captures ) do
if j > 1 then
e ( "," )
end
e ( capture . name , capture . token and capture . token . line or line )
end
e ( ")" )
end

local function emitPackedReturn ( ctx , x )
local actives , seen = { } , { }
for _ , expr in ipairs ( x . exprs or { } ) do
local move = expr . automaticOwnerMove
local active = move and activeWith ( move ) or nil
if active and not seen [ active ] then
seen [ active ] = true
actives [ # actives + 1 ] = active
end
end
local packed = # actives > 0 and nextTemp ( ) or nil
if packed then
e ( ( "do const %s=%s(" ) : format ( packed , cleanupPackName ) , sourceLine ( x ) )
else
e ( ( "return \"return\",%s(" ) : format ( cleanupPackName ) , sourceLine ( x ) )
end
for j , expr in ipairs ( x . exprs or { } ) do
if j > 1 then
e ( "," )
end
emit ( expr )
end
e ( ")" )
if packed then
for _ , active in ipairs ( actives ) do
e ( ( "; %s=false" ) : format ( active ) )
end
e ( ( "; return \"return\",%s end" ) : format ( packed ) )
end
end

emit = function ( x )
if cst . isToken ( x ) then
if x . missing or x . kind == "eof" then
return
end
if x . typeColon or x . typeSeparator or x . typeBracket then
return
end
local text = x . text
if x . kind == "string" and text : sub ( 1 , 1 ) == "`" then

text = pluck . quote ( text : sub ( 2 , - 2 ) )
end
e ( text , x . line )
return
end

local kind = x . kind
if kind == "block" and x . automaticOwners and # x . automaticOwners > 0 then
emitChildren ( x )
return
end
if kind == "dedentString" then
e ( string . format ( "%q" , dedentLongString ( x . token and x . token . text or "" ) ) , sourceLine ( x ) )
return
end
if coverageOn and kind == "block" then
for _ , child in ipairs ( x ) do
if coverageStatement ( child ) then
coverageHit ( "statement" , child )
end
emit ( child )
end
return
end
if kind == "assignStmt" and x . presizedIntoConstructor and not coverageOn then



return
end
if x . automaticOwnerReinit then
local active = activeWith ( x . automaticOwnerReinit )
if active then
local reinit = x . automaticOwnerReinit
local slot = not reinit . field and automaticSlot ( reinit ) or nil
x . automaticOwnerReinit = nil
pluck . loweredFunction ( "(function(__p) " , sourceLine ( x ) , pluck . reasons . reinit )
if slot then
e ( slot .. "=__p; " )
end
e ( active .. "=true; return __p end)(" )
emit ( x )
e ( ")" )
x . automaticOwnerReinit = reinit
return
end
end
if kind == "recordDecl" and x . isAnnotationDefinition then



return
end
if not pluck . statementActive [ x ] then
local direct = pluck . directCall ( x )
local plan = direct and pluck . callPlan ( direct ) or nil
if plan and ( not plan . isSafe or kind == "callStmt" or kind == "returnStmt" ) then
pluck . statementActive [ x ] = true
if plan . isSafe and kind == "returnStmt" then
pluck . emitReturn ( x , plan )
else
pluck . emitStatement ( x , direct , plan )
end
pluck . statementActive [ x ] = nil
return
end
end
if kind == "call" or kind == "safeCall" or kind == "methodCall" then
local activePlan = pluck . plans [ x ]
if activePlan and not activePlan . delegate then
pluck . emitCall ( x , activePlan )
return
end
end
if kind == "args" and x . loweredArgs then
e ( "(" , sourceLine ( x ) )
pluck . emitArgs ( x )
e ( ")" )
return
end
if x . passPinnedPointer then
x . passPinnedPointer = nil
e ( "(" , sourceLine ( x ) )
emit ( x )
e ( ").pointer" )
x . passPinnedPointer = true
return
end
if x . comptimeValue then





e ( x . comptimeValue , sourceLine ( x ) )
return
end
if x . materializedIR then
local materializeIR = require ( "nupp.compiler.materialize.ir" )
local rendered , failure = materializeIR . render ( x . materializedIR )
if not rendered then
error ( "checked materialization IR failed during generation: " .. tostring ( failure and failure . message ) )
end
e ( rendered , sourceLine ( x ) )
local observation = x . materializationObservation
for _ , effect in ipairs ( observation and observation . runtimeFeatures or { } ) do
needRuntimeEffect ( effect )
end
return
end
if x . folded then
e ( x . folded , sourceLine ( x ) )
return
end
if x . compilerFeatureEffect then
needRuntimeEffect ( x . compilerFeatureEffect )
end
for _ , effect in ipairs ( x . compilerFeatureEffects or { } ) do
needRuntimeEffect ( effect )
end
if kind == "dotIndex" and x . overloadMember then
emit ( x . obj )
e ( "." .. x . overloadMember , sourceLine ( x ) )
return
end
if x . callableBindings then
for _ , binding in ipairs ( x . callableBindings ) do
e ( "const " .. binding . name .. "=" , sourceLine ( x ) )
emit ( binding . value )
e ( ";" )
end
end
if ( kind == "call" or kind == "methodCall" ) and x . formatIntrinsic then
local plan = x . formatIntrinsic
local arguments = x . args and x . args . exprs or { }
e ( pluck . formatHelper ( plan ) .. "(" , sourceLine ( x ) )
for index = ( plan . argumentOffset or 0 ) + 1 , # arguments do
if index > ( plan . argumentOffset or 0 ) + 1 then
e ( "," )
end
emit ( arguments [ index ] )
end
e ( ")" )
return
end
if kind == "call" and x . ffiLoadLib and pluck . hotLibraries [ x . ffiLoadLib ] then
emit ( x . obj )
e ( "(" .. ( "%q" ) : format ( pluck . hotLibraries [ x . ffiLoadLib ] ) )
local arguments = x . args and x . args . exprs or { }
for index = 2 , # arguments do
e ( "," )
emit ( arguments [ index ] )
end
e ( ")" )
return
end
if kind == "call" and x . staticCallee then
e ( x . staticCallee , sourceLine ( x ) )
if x . args then
emit ( x . args )
end
return
end
if kind == "bracketIndex" and x . carrayBound then
needsCArrayIndex = true
carrayIndexName = carrayIndexName or reservedName ( "__nuppCArrayIndex" )
emit ( x . obj )
e ( "[" )
e ( carrayIndexName .. "(" )
emit ( x . expr )
e ( "," .. tostring ( x . carrayBound ) .. ")]" )
return
end
if kind == "call" and x . tableIntrinsic then
e ( tableIntrinsicName ( x . tableIntrinsic ) , sourceLine ( x ) )
if x . args then
emit ( x . args )
end
return
end
if kind == "assignStmt" and x . isConst then
for i , target in ipairs ( x . targets or { } ) do
if i > 1 then
e ( "," )
end
emit ( target )
end
e ( "=" )
for i , value in ipairs ( x . exprs or { } ) do
if i > 1 then
e ( "," )
end
emit ( value )
end
return
end
if kind == "fieldNamed" and x . isConst then
if x . name then
emit ( x . name )
end
e ( "=" )
if x . value then
emit ( x . value )
end
return
end
if x . constantLoopNone then



e ( "do" , sourceLine ( x ) )
local endTok
for i = # x , 1 , - 1 do
local child = x [ i ]
if cst . isToken ( child ) and child . kind == "end" then
endTok = child
break
end
end
e ( "end" , endTok and endTok . line or nil )
return
end
if kind == "ifStmt" and ( x . constantBranch or x . constantBranchNone ) then



e ( "do" , sourceLine ( x ) )
if x . constantBranch then
emit ( x . constantBranch )
end
local endTok
for i = # x , 1 , - 1 do
local child = x [ i ]
if cst . isToken ( child ) and child . kind == "end" then
endTok = child
break
end
end
e ( "end" , endTok and endTok . line or nil )
return
end
if coverageOn and ( kind == "ifClause" or kind == "elseifClause" ) then


local branch = coverageSite ( "branch" , x . cond )
for _ , child in ipairs ( x ) do
if child == x . cond then
e ( ( "%s.branch(%q,%d," ) : format ( coverageRuntime ( ) , coveragePath , branch ) , sourceLine ( child ) )
emit ( child )
e ( ")" )
else
emit ( child )
end
end
return
end
if kind == "recordDecl" and x . declKind == "record" then



local line = sourceLine ( x )
local path = declPath ( x )
local runtimeName = x . recordRuntimeName or path or x . name . text
local attached = x . recordRuntimeName or path
local storage = attached and "" or x . visibility == "global" and "" or "const "
local expr = ( "%s%s = {} %s.__index = %s" ) : format ( storage , runtimeName , runtimeName , runtimeName )
e ( expr , line )
local nominal = x . resolvedType
local jsonDerive = x . deriveRecipe and x . deriveRecipe . data and x . deriveRecipe . data . json
if nominal and ( nominal . runtimeReflectionNeeded or jsonDerive ) then
needRuntimeEffect ( "stdlib.reflection" )





local reflection = require ( "nupp.compiler.reflection" )
local descriptor = reflection . describe ( nominal , runtimeName )
e ( ";_G.nupp.__reflect.register(" .. runtimeName .. "," .. pluck . renderData ( descriptor ) .. ")" )
end
for _ , entry in ipairs ( x . entries or { } ) do
if entry . kind == "recordDecl" and entry . declKind == "record" then
entry . recordRuntimeName = runtimeName .. "." .. entry . name . text
emit ( entry )
elseif entry . kind == "inlineMethod" then
entry . inlineRuntimeOwner = runtimeName
entry . inlineDotted = entry . inlineStatic
emit ( entry )
elseif entry . kind == "constructorDecl" then
entry . inlineRuntimeOwner = runtimeName
emit ( entry )
end
end
emitInheritedDefaults ( x , runtimeName )
pluck . emitDerivedMembers ( x , runtimeName )
return
end

if kind == "recordDecl" and x . declKind == "interface" then




local defaults = { }
for _ , entry in ipairs ( x . entries or { } ) do
if entry . kind == "inlineMethod" then
defaults [ # defaults + 1 ] = entry
end
end
local inherits = false
for _ , super in ipairs ( x . supertypes or { } ) do
if super . interfaceName then
inherits = true
end
end
local nominal = x . resolvedType
local hasStatics = nominal and nominal . staticByname and next ( nominal . staticByname ) ~= nil
if # defaults == 0 and not inherits and not hasStatics then
return
end
local line = sourceLine ( x )
local path = declPath ( x )
local runtimeName = x . recordRuntimeName or path or x . name . text
local attached = x . recordRuntimeName or path
local storage = attached and "" or x . visibility == "global" and "" or "const "
e ( ( "%s%s = {}" ) : format ( storage , runtimeName ) , line )
for _ , entry in ipairs ( defaults ) do
entry . inlineRuntimeOwner = runtimeName
entry . inlineDotted = true
emit ( entry )
end
emitInheritedDefaults ( x , runtimeName )
return
end

if kind == "recordDecl" and x . declKind == "struct" then



needsFfi = true
local cdecl , params = { } , { }
for _ , entry in ipairs ( x . entries ) do
if entry . kind == "fieldDecl" then
local fname = entry . name . text
local t = entry . type




local width = entry . bitWidth and ( " : " .. entry . bitWidth . text ) or ""

if t . kind == "topt" then
t = t . inner
end
if t . kind == "tname" and C_PRIM [ t . base . text ] then
cdecl [ # cdecl + 1 ] = C_PRIM [ t . base . text ] .. " " .. fname .. width .. ";"
elseif t . kind == "tname" and structTag [ cst . lastName ( t ) or "" ] then
cdecl [ # cdecl + 1 ] = "struct " .. structTag [ cst . lastName ( t ) ] .. " " .. fname .. ";"
elseif t . kind == "tname" then
cdecl [ # cdecl + 1 ] = "$ " .. fname .. ";"
params [ # params + 1 ] = ( t . reified or cst . textOf ( t ) )
elseif t . kind == "tcarray" and t . count then



local element = t . element
local spelling = element and element . kind == "tname" and C_PRIM [ element . base . text ] or nil
if spelling then
cdecl [ # cdecl + 1 ] = spelling .. " " .. fname .. "[" .. cst . textOf ( t . count ) .. "];"
elseif element and element . kind == "tname" and structTag [ cst . lastName ( element ) or "" ] then
cdecl [
# cdecl + 1
] = "struct " .. structTag [
cst . lastName ( element )
] .. " " .. fname .. "[" .. cst . textOf ( t . count ) .. "];"
elseif element and element . kind == "tname" then
cdecl [ # cdecl + 1 ] = "$ " .. fname .. "[" .. cst . textOf ( t . count ) .. "];"
params [ # params + 1 ] = ( element . reified or cst . textOf ( element ) )
else
diag ( entry . name , "NUPP3002" , "cannot reify this array element type" )
end
elseif t . kind == "tptr" then
local inner = t . inner
if inner . kind == "tname" and C_PRIM [ inner . base . text ] then
cdecl [ # cdecl + 1 ] = C_PRIM [ inner . base . text ] .. " *" .. fname .. ";"
elseif inner . kind == "tname" and structTag [ cst . lastName ( inner ) or "" ] then


cdecl [
# cdecl + 1
] = "struct " .. structTag [ cst . lastName ( inner ) ] .. " *" .. fname .. ";"
elseif inner . kind == "tname" then
cdecl [ # cdecl + 1 ] = "$ *" .. fname .. ";"
params [ # params + 1 ] = ( inner . reified or cst . textOf ( inner ) )
else
diag ( entry . name , "NUPP3002" , "cannot reify this pointer field type" )
end
else
diag ( entry . name , "NUPP3002" , "cannot reify this field type" )
end
end
end
local first = x [ 1 ]
local line = first and cst . isToken ( first ) and first . line or nil
local path = declPath ( x )
local storage = path and "" or x . visibility == "global" and "" or "const "



local mt = "__nuppMt_" .. x . name . text
local tag = structTag [ x . name . text ]
local expr
if tag then



expr = (
"pcall(__nuppFfi.cdef, \"struct %s { %s };\") "
) : format (
tag ,
table . concat ( cdecl , " " )
) .. "const " .. mt .. " = {__index = {}} " .. storage .. (
path or x . name . text
) .. ( " = %s(__nuppFfi.typeof(\"struct %s\"), %s)" ) : format ( metatypeHelper ( ) , tag , mt )
else
expr = "const " .. mt .. " = {__index = {}} " .. storage .. (
path or x . name . text
) .. " = __nuppFfi.metatype(__nuppFfi.typeof(\"struct { " .. table . concat ( cdecl , " " ) .. " }\""
if # params > 0 then
expr = expr .. ", " .. table . concat ( params , ", " )
end
expr = expr .. "), " .. mt .. ")"
end
e ( expr , line )
for _ , entry in ipairs ( x . entries or { } ) do
if entry . kind == "inlineMethod" then
entry . inlineRuntimeOwner = mt .. ".__index"
emit ( entry )
end
end




emitInheritedDefaults ( x , mt .. ".__index" )
return
end

if kind == "cdefStruct" then
needsFfi = true
local fields = { }
for _ , entry in ipairs ( x . entries ) do
if entry . kind == "fieldDecl" then
local ct = cdefCType ( entry . type )
if ct then
local width = entry . bitWidth and " : " .. entry . bitWidth . text or ""
fields [ # fields + 1 ] = ct .. " " .. entry . name . text .. width .. ";"
else
diag ( entry . name , "NUPP3003" , "cdef field type has no C spelling" )
end
end
end
local first = x [ 1 ]
local line = first and cst . isToken ( first ) and first . line or nil

e (
(
'pcall(__nuppFfi.cdef, "%s %s { %s };") const %s = __nuppFfi.typeof("%s %s")'
) : format (
x . aggregateKind or "struct" ,
x . name . text ,
table . concat ( fields , " " ) ,
x . name . text ,
x . aggregateKind or "struct" ,
x . name . text
) ,
line
)
return

elseif kind == "cdefFunc" then
needsFfi = true
local name = x . name . text



local sig , signatureWhy = require ( "nupp.compiler.cabi" ) . prototype ( x . cAbiSignature , true )
if not sig then
diag ( x . name , "NUPP3003" , "cdef signature has no C spelling: " .. tostring ( signatureWhy ) )
sig = "void " .. name .. "(void);"
end
local first = x [ 1 ]
local line = first and cst . isToken ( first ) and first . line or nil


local ns = "__nuppFfi.C"
if x . fromLib then
needsLibs = true
local authored = x . fromLib . text : match ( '^"(.*)"$' ) or x . fromLib . text : match ( "^'(.*)'$" )
local mapped = authored and pluck . hotLibraries [ authored ] or nil
ns = mapped and ( "__nuppLib(%q)" ) : format ( mapped ) or ( "__nuppLib(%s)" ) : format ( x . fromLib . text )
end
if x . countedAbi then
local rawName = nextTemp ( )
e ( ( 'pcall(__nuppFfi.cdef, %q) const %s = %s.%s' ) : format ( sig , rawName , ns , name ) , line )
e ( ( " const %s=function(%s) " ) : format ( name , table . concat ( x . countedAbi . logicalNames or { } , "," ) ) )
local groups = { }
for _ , mapping in ipairs ( x . countedAbi . mappings or { } ) do
local group = groups [ mapping . countIndex ] or { }
group [ # group + 1 ] = mapping
groups [ mapping . countIndex ] = group
end
local countIndexes = { }
for countIndex in pairs ( groups ) do
countIndexes [ # countIndexes + 1 ] = countIndex
end
table . sort ( countIndexes )
for _ , countIndex in ipairs ( countIndexes ) do
local group = groups [ countIndex ]
local first = group [ 1 ]
for j = 2 , # group do
e (
(
"if %s.count~=%s.count then error(%q,2) end "
) : format (
first . pointerName ,
group [ j ] . pointerName ,
"spans counted by " .. first . countName .. " must have equal lengths"
)
)
end
end
local pointerValues , countValues = { } , { }
for _ , mapping in ipairs ( x . countedAbi . mappings or { } ) do
local pointerValue = nextTemp ( )
local countValue = countValues [ mapping . countIndex ]
if not countValue then
countValue = nextTemp ( )
countValues [ mapping . countIndex ] = countValue
e ( ( "const %s,%s=%s:ref() " ) : format ( pointerValue , countValue , mapping . pointerName ) )
else
local ignoredCount = nextTemp ( )
e ( ( "const %s,%s=%s:ref() " ) : format ( pointerValue , ignoredCount , mapping . pointerName ) )
end
pointerValues [ mapping . pointerIndex ] = pointerValue
end
e ( "return " .. rawName .. "(" )
for physicalIndex , physicalName in ipairs ( x . countedAbi . physicalNames or { } ) do
if physicalIndex > 1 then
e ( "," )
end
e ( pointerValues [ physicalIndex ] or countValues [ physicalIndex ] or physicalName )
end
e ( ") end" )
else
e ( ( 'pcall(__nuppFfi.cdef, %q) const %s = %s.%s' ) : format ( sig , name , ns , name ) , line )
end
for _ , registration in ipairs ( x . name . cleanupRegistrations or { } ) do
local cleanup = registration . cleanup
e ( ( ";%s[%q]=%s" ) : format ( cleanupRegistry ( ) , cleanup . key , cleanup . name ) , line )
end
return
end

if TYPE_KINDS [ kind ] or DECL_KINDS [ kind ] then




for _ , registration in ipairs ( x . cleanupRegistrations or { } ) do
local cleanup = registration . cleanup
e ( ( "%s[%q]=%s;" ) : format ( cleanupRegistry ( ) , cleanup . key , cleanup . name ) , sourceLine ( x ) )
end
return

elseif kind == "castExpr" then
emit ( x . expr )

elseif kind == "unsafeOwnershipExpr" then
local move = x . expr and x . expr . automaticOwnerMove or nil
local movedActive = move and activeWith ( move ) or nil
if x . operation == "release" and movedActive then
pluck . loweredFunction (
( "(function() %s=false; return " ) : format ( movedActive ) ,
sourceLine ( x ) ,
pluck . reasons . move
)
emit ( x . expr )
e ( " end)()" )
elseif x . expr then
emit ( x . expr )
else
e ( "nil" , sourceLine ( x ) )
end

elseif kind == "isExpr" then
local t = x . type
local firstTok = x [ 1 ] and ( cst . isToken ( x [ 1 ] ) and x [ 1 ] or x [ 1 ] [ 1 ] )
if x . provenStatically then




if x . provenNeedsNil then
e ( "(" , firstTok and firstTok . line )
emit ( x . expr )
e ( "~= nil )" )
else
e ( "( true )" , firstTok and firstTok . line )
end
elseif x . refutedStatically then


e ( "( false )" , firstTok and firstTok . line )
elseif t . kind == "tname" and t . base . kind == "nil" then
e ( "(" , firstTok and firstTok . line )
emit ( x . expr )
e ( "== nil )" )
elseif t . kind == "tname" and # t == 1 and IS_TYPE [ t . base . text ] then
e ( "( type(" , firstTok and firstTok . line )
emit ( x . expr )
e ( ') == "' .. IS_TYPE [ t . base . text ] .. '" )' )
elseif t . kind == "tfunc" then
e ( "( type(" , firstTok and firstTok . line )
emit ( x . expr )
e ( ') == "function" )' )
elseif t . wherePredicate then




local line = firstTok and firstTok . line
local subject = x . expr and x . expr . kind == "name" and x . expr . token and x . expr . token . text or nil
if subject then


e ( "( " .. predicate . test ( t . wherePredicate , subject ) .. " )" , line )
else





local name = pluck . declareHelper (
"__nuppIs" ,
"__nuppV" ,
"return " .. predicate . test ( t . wherePredicate , "__nuppV" )
)
e ( ( "%s(" ) : format ( name ) , line )
emit ( x . expr )
e ( ")" )
end
elseif t . recordName then












e ( "( getmetatable(" , firstTok and firstTok . line )
emit ( x . expr )
e ( ")?.__index == " .. t . recordName .. " )" )
elseif t . reified then

needsFfi = true
e ( "__nuppFfi.istype(" .. t . reified .. "," , firstTok and firstTok . line )
emit ( x . expr )
e ( ")" )
else




local at = t [ 1 ] and ( cst . isToken ( t [ 1 ] ) and t [ 1 ] or nil )
if t . interfaceName then
diag (
at ,
"NUPP3001" ,
"an interface has no runtime identity of its own, so " .. "this `is` has nothing to test" ,
"give it a literal-typed field and the tag becomes the "
.. "test; or a `matches` block, which says the test "
.. "outright; or test a subject whose own type declares "
.. "the interface, which needs no test at all"
)
else
diag (
at ,
"NUPP3001" ,
"this type has no runtime identity, so `is` has " .. "nothing to test" ,
"test against a record, a struct, or an interface that " .. "can say what it is"
)
end
e ( "true" )
end

elseif kind == "funcExpr" and x . body and # ( x . body . takenCaptures or { } ) > 0 then
emitDepth . affineFunction ( x )
return

elseif kind == "shortfn" then




local first = x [ 1 ]
local line = first and ( cst . isToken ( first ) and first . line or ( first [ 1 ] and first [ 1 ] . line ) )
if not x . varargParam then
local names = { }
for _ , p in ipairs ( x . params ) do
names [ # names + 1 ] = p . name . text
end
e ( "|" .. table . concat ( names , ", " ) .. "| ->" , line )
emitDepth . fn = emitDepth . fn + 1
if x . expr then



e ( "(" )
emit ( x . expr )
e ( ")" )
else
e ( "do" )
emit ( x . body )
e ( "end" )
end
emitDepth . fn = emitDepth . fn - 1
return
end
local names = { }
for _ , p in ipairs ( x . params ) do
names [ # names + 1 ] = p . namedVararg and "..." or p . name . text
end
e ( "function(" .. table . concat ( names , ", " ) .. ")" , line )
emitDepth . fn = emitDepth . fn + 1
e ( ( "const %s = { n = select(\"#\", ...), ... }" ) : format ( x . varargParam . name . text ) )
if x . expr then


e ( "return (" )
emit ( x . expr )
e ( ")" )
else
emit ( x . body )
end
emitDepth . fn = emitDepth . fn - 1
e ( "end" )

elseif kind == "funcbody" and x . varargParam then
emitDepth . fn = emitDepth . fn + 1
for _ , child in ipairs ( x ) do
if child == x . body then
e ( ( "const %s = { n = select(\"#\", ...), ... }" ) : format ( x . varargParam . name . text ) )
end
emit ( child )
end
emitDepth . fn = emitDepth . fn - 1

elseif kind == "istring" then
local piecesOpen = false
local line = x [ 1 ] and x [ 1 ] . line
e ( "(" , line )
for _ , child in ipairs ( x ) do
if cst . isToken ( child ) then
local text = child . text
local chunk
if child . kind == "istringOpen" then
chunk = text : sub ( 2 , - 3 )
elseif child . kind == "istringMid" then
chunk = text : sub ( 2 , - 3 )
elseif child . kind == "istringClose" then
chunk = text : sub ( 2 , - 2 )
end
if chunk and # chunk > 0 then
if piecesOpen then
e ( ".." )
end
e ( pluck . quote ( chunk ) , child . line )
piecesOpen = true
end
else
if piecesOpen then
e ( ".." )
end
e ( "tostring(" )
emit ( child )
e ( ")" )
piecesOpen = true
end
end
if not piecesOpen then
e ( '""' )
end
e ( ")" )

elseif kind == "binop" and x . op . kind == "//" then
e ( "math.floor((" , x . op . line )
emit ( x . lhs )
e ( ") / (" )
emit ( x . rhs )
e ( "))" )

elseif kind == "compoundAssign" and LOWERED_COMPOUND [ x . op . kind ] then



local base = x . op . kind : sub ( 1 , - 2 )
local target = x . target
local first = target [ 1 ]
local line = first and cst . isToken ( first ) and first . line or ( cst . isToken ( target ) and target . line or nil )




local function assignTo ( slot , at )
if base == "??" then
e ( ( "if %s == nil then %s = " ) : format ( slot , slot ) , at )
emit ( x . value )
e ( " end" )
else
e ( ( "%s = math.floor((%s) / (" ) : format ( slot , slot ) , at )
emit ( x . value )
e ( "))" )
end
end

local tkind = target . kind
if tkind == "name" then
assignTo ( target . token . text , line )
return
end
local safe = tkind == "safeIndex" or tkind == "safeBracket"
local dotted = tkind == "dotIndex" or tkind == "safeIndex"
local prefix = nextTemp ( )
e ( ( "do const %s = " ) : format ( prefix ) , line )
emit ( target . obj )
e ( "; " )
local reach = safe and "?." or "."
if dotted then
assignTo ( ( "%s%s%s" ) : format ( prefix , reach , target . name . text ) )
else
local key = nextTemp ( )
e ( ( "const %s = " ) : format ( key ) )
emit ( target . expr )
e ( "; " )
assignTo ( ( "%s%s[%s]" ) : format ( prefix , safe and "?." or "" , key ) )
end
e ( " end" )
return

elseif kind == "callStmt" and x . expr and x . expr . logIntrinsic then




local call = x . expr
local severity = call . logIntrinsic
local line = sourceLine ( call )
local exprs = call . args and call . args . exprs or { }





local logName = compilerModuleName ( "nupp.log" )
e ( ( "if %s.on[%d] then %s.emit(%d,%d," ) : format ( logName , severity , logName , severity , line ) , line )
local formatPlan = call . logFormatIntrinsic
if formatPlan then
e ( pluck . formatHelper ( formatPlan ) .. "(" )
elseif # exprs > 1 then
e ( "string.format(" )
end
local first = formatPlan and 2 or 1
for index = first , # exprs do
if index > first then
e ( "," )
end
emit ( exprs [ index ] )
end
if formatPlan or # exprs > 1 then
e ( ")" )
end
e ( ") end" )
return

elseif kind == "callStmt" and x . expr and x . expr . zoneIntrinsic then







local call = x . expr
local op = call . zoneIntrinsic
local line = sourceLine ( call )
local receiver = call . obj and call . obj . obj
local zoneName = nextTemp ( )
e ( ( "do const %s = " ) : format ( zoneName ) , line )
emit ( receiver )
e ( "; " )
if op == "push" then
local depthName = nextTemp ( )
e (
(
"if %s.__nuppActive then const %s=%s.__nuppDepth+1;%s.__nuppDepth=%s;%s.__nuppStack[%s]="
) : format ( zoneName , depthName , zoneName , zoneName , depthName , zoneName , depthName )
)
local exprs = call . args and call . args . exprs or { }
emit ( exprs [ 1 ] )
e ( ( ";%s.__nuppVersion=%s.__nuppVersion+1 end" ) : format ( zoneName , zoneName ) )
else
local depthName = nextTemp ( )
e (
(
"if %s.__nuppActive and %s.__nuppDepth>0 then const %s=%s.__nuppDepth;"
.. "%s.__nuppStack[%s]=nil;%s.__nuppDepth=%s-1;%s.__nuppVersion=%s.__nuppVersion+1 end"
) : format (
zoneName ,
zoneName ,
depthName ,
zoneName ,
zoneName ,
depthName ,
zoneName ,
depthName ,
zoneName ,
zoneName
)
)
end
e ( " end" )
return

elseif kind == "callStmt" and x . expr and x . expr . ownershipIntrinsic == "drop" then






local inner = x . expr
local innerArgs = inner . args and inner . args . exprs or { }
local innerMove = ownershipMoveOf ( innerArgs [ 1 ] )
local innerActive = innerMove and activeWith ( innerMove ) or nil
e ( "do" , sourceLine ( x ) )
if innerActive then
e ( ( "%s=false;" ) : format ( innerActive ) )
inner . ownershipMoveCleared = true
end
emit ( inner )
inner . ownershipMoveCleared = nil
e ( "end" )
return

elseif kind == "callStmt" and x . expr and x . expr . ownershipIntrinsic == "attemptAll" then



local inner = x . expr
for _ , registration in ipairs ( inner . cleanupRegistrations or { } ) do
if not registration . after then
local cleanup = registration . cleanup
e ( ( "%s[%q]=%s;" ) : format ( cleanupRegistry ( ) , cleanup . key , cleanup . name ) , sourceLine ( x ) )
end
end
e ( "do " , sourceLine ( x ) )
e ( "local " .. nextTemp ( ) .. "=" )
emit ( inner )
e ( " end" )
return

elseif kind == "callStmt" and x . expr and x . expr . ownershipIntrinsic then










local inner = x . expr
local innerArgs = inner . args and inner . args . exprs or { }
local innerMove = ownershipMoveOf ( innerArgs [ 1 ] )
local innerActive = innerMove and activeWith ( innerMove ) or nil
e ( "do " , sourceLine ( x ) )
if innerActive and inner . ownershipIntrinsic == "drop" then
e ( ( "%s=false; " ) : format ( innerActive ) )
inner . ownershipMoveCleared = true
end
e ( "local " .. nextTemp ( ) .. "=" )
emit ( inner )
inner . ownershipMoveCleared = nil
e ( " end" )
return

elseif kind == "callStmt" and x . expr and ( x . expr . automaticOwnerMoves or x . expr . dynamicPutCleanups ) then





e ( "do" , sourceLine ( x ) )
emit ( x . expr )
e ( "end" )
return

elseif kind == "call" and x . ffiOutContracts then















needsFfi = true
local line = sourceLine ( x )
local loweredArgs = x . args and x . args . loweredArgs or nil
local args = loweredArgs or ( x . args and x . args . exprs or { } )
local status = x . ffiOutContracts [ 1 ] . hasStatus and "__nuppS" or nil

local holders , outputAt , body = { } , { } , { }
for j , output in ipairs ( x . ffiOutContracts ) do
holders [ j ] = "__nuppH" .. tostring ( j )
outputAt [ output . cIndex ] = holders [ j ]
local spelling = cdefCType ( output . typeNode ) or "void **"
spelling = spelling : gsub ( "%s*%*$" , "" ) .. "[1]"
body [ # body + 1 ] = ( "const %s=__nuppFfi.new(%q); " ) : format ( holders [ j ] , spelling )
end



local params , callArguments , inputs = { "__nuppFn" } , { } , 0
for cIndex = 1 , # args + # holders do
if outputAt [ cIndex ] then
callArguments [ # callArguments + 1 ] = outputAt [ cIndex ]
else
inputs = inputs + 1
params [ # params + 1 ] = "__nuppA" .. tostring ( inputs )
callArguments [ # callArguments + 1 ] = params [ # params ]
end
end
body [
# body + 1
] = (
status and ( "const %s=" ) : format ( status ) or ""
) .. ( "__nuppFn(%s); return " ) : format ( table . concat ( callArguments , "," ) )

local results = { }
if status then
results [ # results + 1 ] = status
end
for j , output in ipairs ( x . ffiOutContracts ) do
if output . success == "zero" then
results [ # results + 1 ] = ( "(%s==0 and %s[0] or nil)" ) : format ( status , holders [ j ] )
elseif output . success == "nonzero" then
results [ # results + 1 ] = ( "(%s~=0 and %s[0] or nil)" ) : format ( status , holders [ j ] )
elseif output . success : match ( "^notequals:" ) then
local literal = output . success : sub ( # "notequals:" + 1 )
results [ # results + 1 ] = ( "(%s~=%s and %s[0] or nil)" ) : format ( status , literal , holders [ j ] )
elseif output . success : match ( "^equals:" ) then
local literal = output . success : sub ( # "equals:" + 1 )
results [ # results + 1 ] = ( "(%s==%s and %s[0] or nil)" ) : format ( status , literal , holders [ j ] )
else
results [ # results + 1 ] = holders [ j ] .. "[0]"
end
end
body [ # body + 1 ] = table . concat ( results , "," )

e ( pluck . declareHelper ( "__nuppOut" , table . concat ( params , "," ) , table . concat ( body ) ) .. "(" , line )
emit ( x . obj )
for j = 1 , inputs do
e ( "," )
if loweredArgs then
pluck . emitArgument ( args [ j ] , x . args )
else
emit ( args [ j ] )
end
end
e ( ")" )
return

elseif kind == "call" and x . ownershipIntrinsic then
local args = x . args and x . args . exprs or { }
local line = sourceLine ( x )
local move = ownershipMoveOf ( args [ 1 ] )
local movedActive = move and activeWith ( move ) or nil







local wrapsMove = movedActive ~= nil and not x . ownershipMoveCleared and x . ownershipIntrinsic == "drop"
if wrapsMove then
pluck . loweredFunction ( ( "(function() %s=false; return " ) : format ( movedActive ) , line , pluck . reasons . move )
end
if x . ownershipIntrinsic == "borrow" then
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" , line )
end
elseif x . ownershipIntrinsic == "borrowFrom" then
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" , line )
end
elseif x . ownershipIntrinsic == "partition" then
e ( "(function() return " , line )
if args [ 2 ] then
emit ( args [ 2 ] )
else
e ( "nil" )
end
e ( "," )
if args [ 3 ] then
emit ( args [ 3 ] )
else
e ( "nil" )
end
e ( " end)()" )
elseif x . ownershipIntrinsic == "region" then
if args [ 2 ] then
emit ( args [ 2 ] )
else
e ( "nil" , line )
end
elseif x . ownershipIntrinsic == "pin" then
e ( "{pointer=" , line )
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" )
end
e ( ",anchor=" )
if args [ 2 ] then
emit ( args [ 2 ] )
else
e ( "nil" )
end
e ( "}" )
elseif x . ownershipIntrinsic == "attemptAll" then



ensureCleanupRuntime ( )
local statements = { "if __nuppV == nil then return end local __errs,__n={},0; " }
for _ , cleanup in ipairs ( x . ownerCleanups or { } ) do
local call = protectedCleanupCall ( cleanup , "__nuppV" , cleanupGlobals . pcall )
if call then
statements [
# statements + 1
] = "do local __ok,__reason="
.. call
.. "; if not __ok then __n=__n+1; __errs[__n]=__reason end end; "
end
end
statements [
# statements + 1
] = (
"if __n>0 then if __n>1 then %s(%s(__errs[1],__errs,2),0) else %s(__errs[1],0) end end"
) : format ( cleanupGlobals . error , cleanupFailureName , cleanupGlobals . error )
e ( pluck . declareHelper ( "__nuppAttemptAll" , "__nuppV" , table . concat ( statements ) ) .. "(" , line )
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" )
end
e ( ")" )
else



local statements = { "if __nuppV == nil then return end " }
for _ , cleanup in ipairs ( x . ownerCleanups or { } ) do
local call = cleanupCall ( cleanup , "__nuppV" )
if call then
statements [ # statements + 1 ] = call .. "; "
end
end
e ( pluck . declareHelper ( "__nuppDrop" , "__nuppV" , table . concat ( statements ) ) .. "(" , line )
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" )
end
e ( ")" )
end
if wrapsMove then
e ( " end)()" )
end
return

elseif kind == "call" and x . ffiIntrinsic then

needsFfi = true
local first = x [ 1 ]
local line = first and cst . isToken ( first ) and first . line or nil


local ctypeExpr = x . ffiTypeName
if not ctypeExpr then
local typeNode = x . ffiTypeNode




if x . ffiIntrinsic == "cast" and typeNode and typeNode . kind == "tcarray" then
typeNode = typeNode . element
local element = typeNode and cdefCType ( typeNode )
if element then
e ( ( "__nuppFfi.cast(%q" ) : format ( element .. " *" ) , line )
for _ , arg in ipairs ( x . args and x . args . exprs or { } ) do
e ( "," )
emit ( arg )
end
e ( ")" )
return
end
end
local spelling = x . ffiTypeNode and cdefCType ( x . ffiTypeNode )
if not spelling then
diag (
x . name or ( x [ 1 ] and cst . isToken ( x [ 1 ] ) and x [ 1 ] ) ,
"NUPP3004" ,
"this type has no C spelling for an ffi operation"
)
spelling = "void *"
end
ctypeExpr = ( "%q" ) : format ( spelling )
end
e ( ( "__nuppFfi.%s(%s" ) : format ( x . ffiIntrinsic , ctypeExpr ) , line )
for _ , arg in ipairs ( x . args and x . args . exprs or { } ) do
e ( "," )
emit ( arg )
end
e ( ")" )
return

elseif kind == "call" and x . carrayElem then

needsFfi = true
needsArrayCache = true
local first = x [ 1 ]
local line = first and cst . isToken ( first ) and first . line or nil
e ( "__nuppArray(" , line )
emit ( x . carrayElem )
e ( ")(" )
local args = x . args and x . args . exprs or { }
if args [ 2 ] then
emit ( args [ 2 ] )
end
e ( ")" )
return

elseif kind == "call" and x . cheaderCdef then


needsFfi = true
local first = x [ 1 ]
local line = first and cst . isToken ( first ) and first . line or nil
local library = x . cheaderLib and ( pluck . hotLibraries [ x . cheaderLib ] or x . cheaderLib ) or nil
local ns = library and ( "__nuppFfi.load(%q)" ) : format ( library ) or "__nuppFfi.C"


pluck . loweredFunction (
( "(function() pcall(__nuppFfi.cdef, %q) return %s end)()" ) : format ( x . cheaderCdef , ns ) ,
line ,
pluck . reasons . cheader
)
return

elseif kind == "newExpr" then



if x . call then
emit ( x . call )
end
return

elseif kind == "call" and x . dynamicRecoverPolicy then




local callee = x . obj
if callee and callee . kind == "dotIndex" and callee . obj then
emit ( callee . obj )
e ( "._recover(" )
local args = x . args and x . args . exprs or { }
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" )
end
e ( ( ",%q)" ) : format ( x . dynamicRecoverPolicy ) )
return
end

elseif (
kind == "call" or kind == "methodCall"
) and x . automaticOwnerMoves and not x . resourceAdoptCleanups and not x . dynamicPutCleanups then




local activeNames , seen = { } , { }
for _ , move in ipairs ( x . automaticOwnerMoves or { } ) do
local activeName = activeWith ( move )
if activeName and not seen [ activeName ] then
seen [ activeName ] = true
activeNames [ # activeNames + 1 ] = activeName
end
end
local callable = nextTemp ( )
pluck . loweredFunction ( ( "(function(%s,...) " ) : format ( callable ) , sourceLine ( x ) , pluck . reasons . move )
for _ , activeName in ipairs ( activeNames ) do
e ( ( "%s=false; " ) : format ( activeName ) )
end
if kind == "methodCall" then
e ( ( "return %s:%s(...)" ) : format ( callable , x . overloadMember or x . name . text ) )
else
e ( ( "return %s(...)" ) : format ( callable ) )
end
e ( " end)(" )
emit ( x . obj )
local args = x . args
local values = args and args . exprs or { }
if args and args . table then
values = { args . table }
end
if args and args . string then
values = { args . string }
end
if args and args . loweredArgs then
if # args . loweredArgs > 0 then
e ( "," )
pluck . emitArgs ( args )
end
else
for _ , value in ipairs ( values ) do
e ( "," )
emit ( value )
end
end
e ( ")" )
return

elseif kind == "methodCall" and x . dynamicPutCleanups then
if hotState and x . dynamicTypePolicy then
hotState . policies [ x . dynamicTypePolicy ] = true
end
local line = sourceLine ( x )
local args = x . args and x . args . exprs or { }
local activeNames , seen = { } , { }
for _ , move in ipairs ( x . automaticOwnerMoves or { } ) do
local activeName = activeWith ( move )
if activeName and not seen [ activeName ] then
seen [ activeName ] = true
activeNames [ # activeNames + 1 ] = activeName
end
end
local object , value = nextTemp ( ) , nextTemp ( )
pluck . loweredFunction ( ( "(function(%s,%s) " ) : format ( object , value ) , line , pluck . reasons . move )
for _ , activeName in ipairs ( activeNames ) do
e ( ( "%s=false; " ) : format ( activeName ) )
end
local body = { "local __first,__suppressed=nil,0; " }
for _ , cleanup in ipairs ( x . dynamicPutCleanups ) do
local call = protectedCleanupCall ( cleanup , "__nuppV" , "pcall" )
if call then
body [
# body + 1
] = "do local __ok,__reason="
.. call
.. "; if not __ok then if __first==nil then __first=__reason "
.. "else __suppressed=__suppressed+1 end end end; "
end
end
body [
# body + 1
] = "if __first~=nil then if __suppressed>0 then "
.. "error(tostring(__first)..\" (suppressed \"..tostring(__suppressed)"
.. "..\" cleanup failure(s))\",0) else error(__first,0) end end"
e (
(
"return %s:_put(%s,%s,%q)"
) : format (
object ,
value ,
pluck . declareHelper ( "__nuppDynamicCleanup" , "__nuppV" , table . concat ( body ) ) ,
x . dynamicTypePolicy or ""
)
)
e ( " end)(" )
emit ( x . obj )
e ( "," )
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" )
end
e ( ")" )
return

elseif kind == "methodCall" and x . resourceAdoptCleanups then
local line = sourceLine ( x )
local args = x . args and x . args . exprs or { }
local activeNames , seen = { } , { }
for _ , move in ipairs ( x . automaticOwnerMoves or { } ) do
local activeName = activeWith ( move )
if activeName and not seen [ activeName ] then
seen [ activeName ] = true
activeNames [ # activeNames + 1 ] = activeName
end
end
local object , value = nextTemp ( ) , nextTemp ( )
pluck . loweredFunction ( ( "(function(%s,%s) " ) : format ( object , value ) , line , pluck . reasons . move )
for _ , activeName in ipairs ( activeNames ) do
e ( ( "%s=false; " ) : format ( activeName ) )
end







local body = { "local __first,__suppressed=nil,0; " }
for _ , cleanup in ipairs ( x . resourceAdoptCleanups ) do
local call = protectedCleanupCall ( cleanup , "__nuppV" , "pcall" )
if call then
body [
# body + 1
] = "do local __ok,__reason="
.. call
.. "; if not __ok then if __first==nil then __first=__reason "
.. "else __suppressed=__suppressed+1 end end end; "
end
end
body [
# body + 1
] = "if __first~=nil then if __suppressed>0 then "
.. "error(tostring(__first)..\" (suppressed \"..tostring(__suppressed)"
.. "..\" cleanup failure(s))\",0) else error(__first,0) end end"
e (
(
"return %s:adopt(%s,%s)"
) : format ( object , value , pluck . declareHelper ( "__nuppAdopt" , "__nuppV" , table . concat ( body ) ) )
)
e ( " end)(" )
emit ( x . obj )
e ( "," )
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" )
end
e ( ")" )
return

elseif kind == "methodCall" and x . overloadMember then



local line = sourceLine ( x )
emit ( x . obj )
if x . safeObj then
e ( "?.:" .. x . overloadMember , line )
else
e ( ":" .. x . overloadMember , line )
end
if x . safeMethod then
e ( "?." )
end
if x . args then
emit ( x . args )
end
return

elseif ( kind == "call" or kind == "safeCall" ) and x . constructorCall then


local first = x [ 1 ]
local line = first and cst . isToken ( first ) and first . line or nil
e ( x . constructorCall .. "." .. constructorMember ( x . constructorIndex ) , line )
if x . args then
emit ( x . args )
end
return

elseif ( kind == "call" or kind == "safeCall" ) and x . structConstruct then
local first = x [ 1 ]
local line = first and cst . isToken ( first ) and first . line or nil
e ( x . structConstruct .. "(" , line )
for index , binding in ipairs ( x . recordFields or { } ) do
if index > 1 then
e ( ", " )
end
if binding . isDefault then
e ( pluck . renderData ( binding . defaultValue ) )
else
emit ( binding . node )
end
end
e ( ")" )
return

elseif ( kind == "call" or kind == "safeCall" ) and x . recordConstruct then







local first = x [ 1 ]
local line = first and cst . isToken ( first ) and first . line or nil
e ( "setmetatable({" , line )
for index , binding in ipairs ( x . recordFields or { } ) do
if index > 1 then
e ( ", " )
end
e ( cst . identifier ( binding . name ) and ( binding . name .. " = " ) or ( "[%q] = " ) : format ( binding . name ) )
if binding . isDefault then
e ( pluck . renderData ( binding . defaultValue ) )
else
emit ( binding . node )
end
end
e ( "}, " .. x . recordConstruct .. ")" )
return

elseif kind == "constructorDecl" and x . inlineRuntimeOwner then




local body = x . body
local first = x [ 1 ]
local line = first and cst . isToken ( first ) and first . line or nil
local names = { }
for index , p in ipairs ( body . params or { } ) do




if index == 1 and p . name and p . name . text == "self" then

elseif p . namedVararg then
names [ # names + 1 ] = "..."
elseif p . name then
names [ # names + 1 ] = p . name . text
elseif p . vararg or p [ 1 ] and cst . isToken ( p [ 1 ] ) and p [ 1 ] . kind == "..." then
names [ # names + 1 ] = "..."
end
end
local owner = x . inlineRuntimeOwner
local seeded = { }
local nominal = x . ownerNominal
for _ , field in ipairs ( nominal and nominal . fieldOrder or { } ) do
local default = nominal . fieldDefaults and nominal . fieldDefaults [ field ] or nil
if default then
seeded [
# seeded + 1
] = (
cst . identifier ( field ) and ( field .. " = " ) or ( "[%q] = " ) : format ( field )
) .. pluck . renderData ( default . value )
end
end
e (
(
"function %s.%s(%s) local self = setmetatable({%s}, %s)"
) : format (
owner ,
constructorMember ( x . constructorIndex ) ,
table . concat ( names , ", " ) ,
table . concat ( seeded , ", " ) ,
owner
) ,
line
)
if body . varargParam then
e ( ( "const %s = { n = select(\"#\", ...), ... }" ) : format ( body . varargParam . name . text ) )
end
emitDepth . fn = emitDepth . fn + 1
if body . body then
emit ( body . body )
end
emitDepth . fn = emitDepth . fn - 1
local endTok
for j = # body , 1 , - 1 do
local child = body [ j ]
if cst . isToken ( child ) and child . kind == "end" then
endTok = child
break
end
end
e ( "return self end" , endTok and endTok . line or nil )
return

elseif kind == "inlineMethod" and x . inlineRuntimeOwner then
local dispatch = pluck . hotDispatch
local planned = dispatch and dispatch . byNode [ x ] or nil
if dispatch and planned then
dispatch . emit ( planned )
return
end
local body = x . body
local first = x [ 1 ]
local line = first and cst . isToken ( first ) and first . line or nil
local names = { }
for _ , p in ipairs ( body . params or { } ) do
if p . namedVararg then
names [ # names + 1 ] = "..."
elseif p . name then
names [ # names + 1 ] = p . name . text
elseif p . vararg or p [ 1 ] and cst . isToken ( p [ 1 ] ) and p [ 1 ] . kind == "..." then
names [ # names + 1 ] = "..."
end
end
if x . inlineDotted then



e (
(
"function %s.%s(%s)"
) : format ( x . inlineRuntimeOwner , x . overloadMember or x . name . text , table . concat ( names , ", " ) ) ,
line
)
else






if names [ 1 ] == "self" then
table . remove ( names , 1 )
end
e (
(
"function %s:%s(%s)"
) : format ( x . inlineRuntimeOwner , x . overloadMember or x . name . text , table . concat ( names , ", " ) ) ,
line
)
end
if body . varargParam then
e ( ( "const %s = { n = select(\"#\", ...), ... }" ) : format ( body . varargParam . name . text ) )
end
emitDepth . fn = emitDepth . fn + 1
if body . body then
emit ( body . body )
end
emitDepth . fn = emitDepth . fn - 1
local endTok
for j = # body , 1 , - 1 do
local child = body [ j ]
if cst . isToken ( child ) and child . kind == "end" then
endTok = child
break
end
end
e ( "end" , endTok and endTok . line or nil )
return

elseif kind == "funcStmt" and x . structOwner and x . memberName then
local dispatch = pluck . hotDispatch
local planned = dispatch and dispatch . byNode [ x ] or nil
if dispatch and planned then
dispatch . emit ( planned )
return
end
needsFfi = true
local first = x [ 1 ]
local line = first and cst . isToken ( first ) and first . line or nil
local names = { }
if x . name . method then
names [ 1 ] = "self"
end
for _ , p in ipairs ( x . body . params or { } ) do
if p . namedVararg then
names [ # names + 1 ] = "..."
elseif p . name then
names [ # names + 1 ] = p . name . text
elseif p . vararg or p [ 1 ] and cst . isToken ( p [ 1 ] ) and p [ 1 ] . kind == "..." then
names [ # names + 1 ] = "..."
end
end
e (
(
"__nuppMt_%s.__index.%s = function(%s)"
) : format ( x . structOwner , x . memberName , table . concat ( names , ", " ) ) ,
line
)
if x . body . varargParam then
e ( ( "const %s = { n = select(\"#\", ...), ... }" ) : format ( x . body . varargParam . name . text ) )
end
emitDepth . fn = emitDepth . fn + 1
if x . body . body then
emit ( x . body . body )
end
emitDepth . fn = emitDepth . fn - 1

local endTok
for j = # x . body , 1 , - 1 do
local child = x . body [ j ]
if cst . isToken ( child ) and child . kind == "end" then
endTok = child
break
end
end
e ( "end" , endTok and endTok . line or nil )
return

elseif kind == "handleStmt" then




local name = nextTemp ( )
local definition = { }
local binding = {
kind = "cleanupBinding" ,
name = {
kind = "name" ,
text = name ,
line = x . handleTok and x . handleTok . line or sourceLine ( x ) ,
offset = x . handleTok and x . handleTok . offset or 0 ,
definition = definition ,
} ,
expr = {
kind = "suspensionInstallExpr" ,
handler = x . handler ,
line = x . handleTok and x . handleTok . line or sourceLine ( x ) ,
} ,
ownerCleanups = { { kind = "method" , name = "release" , id = "method:release" } } ,
}
local region = {
kind = "cleanupRegion" ,
startTok = x . handleTok ,
doTok = x . doTok ,
endTok = x . endTok ,
bindings = { binding } ,
body = x . body ,
}
region . capturesEnclosing = automaticCaptures ( x . body , region . bindings )
emit ( region )

elseif kind == "cleanupRegion" then
ensureCleanupRuntime ( )
local count = nextTemp ( )
local ok = nextTemp ( )

local tag = nextTemp ( )
local payload = nextTemp ( )
local cleanupError = nextTemp ( )
local hasCleanupError = nextTemp ( )
local owners = { }
local active = { }
local fieldActive = { }
local fieldActiveOrder = { }
local automaticMap = { }
for j = 1 , # ( x . bindings or { } ) do
owners [ j ] = nextTemp ( )
local automatic = x . bindings [ j ] . automaticOwner
if automatic and ( automatic . conditional or automatic . moved or automatic . movedFields ) then
active [ j ] = nextTemp ( )
fieldActive [ j ] = { }
fieldActiveOrder [ j ] = { }
for field in pairs ( automatic . movedFields or { } ) do
fieldActiveOrder [ j ] [ # fieldActiveOrder [ j ] + 1 ] = field
end
table . sort ( fieldActiveOrder [ j ] )
for _ , field in ipairs ( fieldActiveOrder [ j ] ) do
fieldActive [ j ] [ field ] = nextTemp ( )
end
automaticMap [ automatic ] = { whole = active [ j ] , fields = fieldActive [ j ] , slot = owners [ j ] , }
end
end
local variadic = usesVararg ( x . body )
local ctx = {
entryLoopDepth = emitDepth . loop ,
functionDepth = emitDepth . fn ,
labels = labelsIn ( x . body ) ,
gotos = { } ,
automaticMap = automaticMap ,
}






local shared = not x . capturesEnclosing and # (
x . bindings or { }
) == 1 and not active [ 1 ] and not x . automaticComplex
if shared then
cleanupCacheSites = cleanupCacheSites + 1
local slot = cleanupCacheSites
local region = nextTemp ( )
local binding = x . bindings [ 1 ]
e ( "do const " , x . startTok and x . startTok . line or sourceLine ( x ) )
e ( ( "%s=" ) : format ( owners [ 1 ] ) , sourceLine ( binding . expr ) )
local move = binding . expr and binding . expr . automaticOwnerMove or nil
local movedActive = move and activeWith ( move ) or nil
emit ( binding . expr )
if movedActive then






e ( ( "; %s=false" ) : format ( movedActive ) )
end
e (
(
"; local %s=%s[%d]; if not %s then %s=function(%s%s)"
) : format (
region ,
cleanupCacheName ,
slot ,
region ,
region ,
binding . name . text ,
variadic and ",..." or ""
)
)
cleanupStack [ # cleanupStack + 1 ] = ctx
e ( "do" )
if x . body then
emit ( x . body )
end
e ( ( "end; return \"normal\" end; %s[%d]=%s end;" ) : format ( cleanupCacheName , slot , region ) )
e (
(
"const %s,%s,%s=%s(%s,%s,%s%s);"
) : format (
ok ,
tag ,
payload ,
cleanupGlobals . xpcall ,
region ,
cleanupIdName ,
owners [ 1 ] ,
variadic and ",..." or ""
)
)
cleanupStack [ # cleanupStack ] = nil
e ( ( "const %s=1;" ) : format ( count ) )
else
e ( ( "do local %s=0; local " ) : format ( count ) , x . startTok and x . startTok . line or sourceLine ( x ) )
e ( table . concat ( owners , "," ) )
for j = 1 , # ( x . bindings or { } ) do
if active [ j ] then
e ( ( "; local %s=false" ) : format ( active [ j ] ) )
end
for _ , field in ipairs ( fieldActiveOrder [ j ] or { } ) do
e ( ( "; local %s=false" ) : format ( fieldActive [ j ] [ field ] ) )
end
end
pluck . loweredFunction (
(
"; const %s,%s,%s=%s(function(%s)"
) : format ( ok , tag , payload , cleanupGlobals . xpcall , variadic and "..." or "" ) ,
nil ,
pluck . reasons . region
)
cleanupStack [ # cleanupStack + 1 ] = ctx







local function emitAcquired ( binding , expr )
emit ( expr )
local move = expr and expr . automaticOwnerMove or nil

return move and activeWith ( move ) or nil
end

local function activateValue ( j , binding , value )
e ( ( "%s=" ) : format ( owners [ j ] ) , sourceLine ( binding . expr ) )
e ( value )
e ( ( "; %s=%d;" ) : format ( count , j ) )
if active [ j ] then
e ( ( " %s=true;" ) : format ( active [ j ] ) )
end
for _ , field in ipairs ( fieldActiveOrder [ j ] or { } ) do
e ( ( " %s=true;" ) : format ( fieldActive [ j ] [ field ] ) )
end
end

local function activationCondition ( binding )
local alternatives = binding . automaticOwner and binding . automaticOwner . activation or nil
if not alternatives then
return nil
end
local clauses = { }
for _ , tests in ipairs ( alternatives ) do
local parts = { }
for _ , test in ipairs ( tests ) do
local name = binding . automaticOwner . correlation . names [ test . index ]
local constant = test . constant
local literal = type (
constant
) == "string" and ( "%q" ) : format ( constant ) or constant == nil and "nil" or tostring ( constant )
parts [ # parts + 1 ] = ( "%s==%s" ) : format ( name , literal )
end
clauses [ # clauses + 1 ] = "(" .. table . concat ( parts , " and " ) .. ")"
end

return table . concat ( clauses , " or " )
end

local function activate ( j , binding , deferName )
local value = nextTemp ( )
e ( ( "const %s=" ) : format ( value ) , sourceLine ( binding . expr ) )
local cleared = emitAcquired ( binding , binding . expr )
e ( ";" )
if cleared then
e ( ( " %s=false;" ) : format ( cleared ) )
end
activateValue ( j , binding , value )
if not deferName then
e ( ( " %s %s=%s;" ) : format ( binding . isConst and "const" or "local" , binding . name . text , owners [ j ] ) )
end
end

if x . automaticSequence then
local bindingIndex = { }
for j , binding in ipairs ( x . bindings or { } ) do
bindingIndex [ binding ] = j
end
e ( "do" )
for _ , item in ipairs ( x . automaticSequence ) do
if item . declaration then
local stat = item . declaration
local names , exprs = stat . names or { } , stat . exprs or { }
local bySlot = { }
for _ , binding in ipairs ( item . bindings ) do
bySlot [ binding . declarationIndex ] = binding
end
local staged = { }
for exprIndex , expr in ipairs ( exprs ) do
if exprIndex == # exprs and # names > # exprs then
local packed = nextTemp ( )
e ( ( "const %s=%s(" ) : format ( packed , cleanupPackName ) , sourceLine ( expr ) )
local cleared = emitAcquired ( bySlot [ exprIndex ] , expr )
e ( ");" )
if cleared then
e ( ( " %s=false;" ) : format ( cleared ) )
end
for nameIndex = exprIndex , # names do
staged [ nameIndex ] = ( "%s[%d]" ) : format ( packed , nameIndex - exprIndex + 1 )
end
else
local value = nextTemp ( )
e ( ( "const %s=" ) : format ( value ) , sourceLine ( expr ) )
local cleared = emitAcquired ( bySlot [ exprIndex ] , expr )
e ( ";" )
if cleared then
e ( ( " %s=false;" ) : format ( cleared ) )
end
staged [ exprIndex ] = value
end
if exprIndex < # exprs then
local binding = bySlot [ exprIndex ]
if binding then
activateValue ( bindingIndex [ binding ] , binding , staged [ exprIndex ] )
end
end
end
for nameIndex = # exprs , # names do
local binding = bySlot [ nameIndex ]
if binding and not binding . automaticOwner . conditional then
activateValue ( bindingIndex [ binding ] , binding , staged [ nameIndex ] )
end
end
e ( stat . isConst and " const " or " local " )
for nameIndex , name in ipairs ( names ) do
if nameIndex > 1 then
e ( "," )
end
e ( name . text )
end
e ( "=" )
for nameIndex = 1 , # names do
if nameIndex > 1 then
e ( "," )
end
e ( staged [ nameIndex ] or "nil" )
end
e ( ";" )
for _ , binding in ipairs ( item . bindings ) do
if binding . automaticOwner . conditional then
local j = bindingIndex [ binding ]
activateValue ( j , binding , staged [ binding . declarationIndex ] )
if active [ j ] then
e ( ( " %s=%s;" ) : format ( active [ j ] , activationCondition ( binding ) or "false" ) )
end
end
end
elseif item . bindings then




for _ , binding in ipairs ( item . bindings ) do
activate ( bindingIndex [ binding ] , binding , true )
end
for _ , binding in ipairs ( item . bindings ) do
e (
(
" %s %s=%s;"
) : format (
binding . isConst and "const" or "local" ,
binding . name . text ,
owners [ bindingIndex [ binding ] ]
)
)
end
elseif item . stat then
emit ( item . stat )
end
end
else
for j , binding in ipairs ( x . bindings or { } ) do
activate ( j , binding )
end
e ( "do" )
if x . body then
emit ( x . body )
end
end
e ( ( "end; return \"normal\" end,%s%s);" ) : format ( cleanupIdName , variadic and ",..." or "" ) )
cleanupStack [ # cleanupStack ] = nil
end
e ( ( "const %s={}; local %s=0;" ) : format ( cleanupError , hasCleanupError ) , x . endTok and x . endTok . line or nil )
for j = # ( x . bindings or { } ) , 1 , - 1 do
local binding = x . bindings [ j ]
local present = binding . automaticOwner and binding . automaticOwner . optional
if active [ j ] then
e (
(
"if %s>=%d and %s%s then "
) : format ( count , j , active [ j ] , present and ( " and " .. owners [ j ] .. "~=nil" ) or "" )
)
else
e ( ( "if %s>=%d%s then " ) : format ( count , j , present and ( " and " .. owners [ j ] .. "~=nil" ) or "" ) )
end
for _ , cleanup in ipairs ( binding . ownerCleanups or { } ) do
local fieldName = cleanup . kind == "field" and fieldActive [
j
] and fieldActive [ j ] [ cleanup . field ] or nil
if fieldName then
e ( ( "if %s then " ) : format ( fieldName ) )
end
local call = protectedCleanupCall ( cleanup , owners [ j ] , cleanupGlobals . pcall )
if call then
local cok , cerr = nextTemp ( ) , nextTemp ( )
e ( ( "const %s,%s=%s;" ) : format ( cok , cerr , call ) )
e (
(
" if not %s then %s=%s+1; %s[%s]=%s end;"
) : format ( cok , hasCleanupError , hasCleanupError , cleanupError , hasCleanupError , cerr )
)
end
if fieldName then
e ( "end;" )
end
end
e ( "end;" )
end
e (
(
"if not %s then if %s>0 then %s(%s(%s,%s,1),0) else %s(%s,0) end end;"
) : format (
ok ,
hasCleanupError ,
cleanupGlobals . error ,
cleanupFailureName ,
tag ,
cleanupError ,
cleanupGlobals . error ,
tag
)
)
e (
(
"if %s>0 then if %s>1 then %s(%s(%s[1],%s,2),0) else %s(%s[1],0) end end;"
) : format (
hasCleanupError ,
hasCleanupError ,
cleanupGlobals . error ,
cleanupFailureName ,
cleanupError ,
cleanupError ,
cleanupGlobals . error ,
cleanupError
)
)
local parent = cleanupStack [ # cleanupStack ]
e ( ( "if %s==\"return\" then " ) : format ( tag ) )
if parent then
e ( ( "return \"return\",%s" ) : format ( payload ) )
else
e ( ( "return %s(%s,1,%s.n)" ) : format ( cleanupGlobals . unpack , payload , payload ) )
end
e ( " end;" )
if ctx . breakExit then
e ( ( "if %s==\"break\" then " ) : format ( tag ) )
if parent and ctx . entryLoopDepth <= parent . entryLoopDepth then
parent . breakExit = true
e ( "return \"break\"" )
else
e ( "break" )
end
e ( " end;" )
end
if ctx . continueExit then
e ( ( "if %s==\"continue\" then " ) : format ( tag ) )
if parent and ctx . entryLoopDepth <= parent . entryLoopDepth then
parent . continueExit = true
e ( "return \"continue\"" )
else
e ( "continue" )
end
e ( " end;" )
end
local gotoTargets = { }
for target in pairs ( ctx . gotos ) do
gotoTargets [ # gotoTargets + 1 ] = target
end
table . sort ( gotoTargets )
for _ , target in ipairs ( gotoTargets ) do
e ( ( "if %s==%q then " ) : format ( tag , "goto:" .. target ) )
if parent and not parent . labels [ target ] then
parent . gotos [ target ] = true
e ( ( "return %q" ) : format ( "goto:" .. target ) )
else
e ( "goto " .. target )
end
e ( " end;" )
end
e ( "end" )

elseif kind == "returnStmt" and activeWith ( ) then
emitPackedReturn ( activeWith ( ) , x )

elseif (
kind == "breakStmt" or kind == "continueStmt"
) and activeWith ( ) and emitDepth . loop <= activeWith ( ) . entryLoopDepth then
local completion = kind == "breakStmt" and "break" or "continue"
activeWith ( ) [ completion .. "Exit" ] = true
e ( ( "return %q" ) : format ( completion ) , sourceLine ( x ) )

elseif kind == "gotoStmt" and activeWith ( ) and not activeWith ( ) . labels [ x . name . text ] then
local ctx = activeWith ( )
ctx . gotos [ x . name . text ] = true
e ( ( "return %q" ) : format ( "goto:" .. x . name . text ) , sourceLine ( x ) )

elseif kind == "forinStmt" and x . numericIpairs then
local operand = x . numericIpairs . operand
local names = x . names or { }



local index = names [ 1 ] and names [ 1 ] . text or nextTemp ( )
local first = x [ 1 ]
local line = first and cst . isToken ( first ) and first . line or sourceLine ( x )
e ( ( "for %s=1,%d do" ) : format ( index , x . numericIpairs . length ) , line )
if names [ 2 ] then
e ( ( "local %s=" ) : format ( names [ 2 ] . text ) )
emit ( operand )
e ( ( "[%s];" ) : format ( index ) )
end
for j = 3 , # names do
e ( ( "local %s=nil;" ) : format ( names [ j ] . text ) )
end
emitDepth . loop = emitDepth . loop + 1
if x . body then
emit ( x . body )
end
emitDepth . loop = emitDepth . loop - 1
local endTok
for j = # x , 1 , - 1 do
local child = x [ j ]
if cst . isToken ( child ) and child . kind == "end" then
endTok = child
break
end
end
e ( "end" , endTok and endTok . line or nil )
finishConcatBuffer ( x , endTok and endTok . line or nil )

elseif kind == "whileStmt" or kind == "fornumStmt" or kind == "forinStmt" or kind == "repeatStmt" then
local lastLine = nil
for _ , child in ipairs ( x ) do
if child == x . body then
emitDepth . loop = emitDepth . loop + 1
emit ( child )
emitDepth . loop = emitDepth . loop - 1
else
emit ( child )
end
if cst . isToken ( child ) then
lastLine = child . line
end
end


finishConcatBuffer ( x , lastLine )

elseif kind == "funcbody" then
emitDepth . fn = emitDepth . fn + 1
if x . varargParam then
for _ , child in ipairs ( x ) do
if child == x . body then
if coverageOn then
coverageHit ( "function" , x )
end
e ( ( "const %s = { n = select(\"#\", ...), ... }" ) : format ( x . varargParam . name . text ) )
end
emit ( child )
end
else
for _ , child in ipairs ( x ) do
if child == x . body then
if coverageOn then
coverageHit ( "function" , x )
end
end
emit ( child )
end
end
emitDepth . fn = emitDepth . fn - 1

elseif kind == "localFuncStmt" then
if x . comptimeFunction or x . comptimeTok then
return
end
local dispatch = pluck . hotDispatch
local planned = dispatch and dispatch . byNode [ x ] or nil
if dispatch and planned then
dispatch . emit ( planned )
else
emitChildren ( x )
end
for _ , registration in ipairs ( x . name and x . name . cleanupRegistrations or { } ) do
local cleanup = registration . cleanup
e ( ( ";%s[%q]=%s" ) : format ( cleanupRegistry ( ) , cleanup . key , cleanup . name ) , sourceLine ( x ) )
end

elseif kind == "funcStmt" then
if x . comptimeFunction or x . comptimeTok then
return
end
local dispatch = pluck . hotDispatch
local planned = dispatch and dispatch . byNode [ x ] or nil
if dispatch and planned then
dispatch . emit ( planned )
else
emitChildren ( x )
end




for _ , name in ipairs ( x . name or { } ) do
for _ , registration in ipairs ( name . cleanupRegistrations or { } ) do
local cleanup = registration . cleanup
e ( ( ";%s[%q]=%s" ) : format ( cleanupRegistry ( ) , cleanup . key , cleanup . name ) , sourceLine ( x ) )
end
end

elseif kind == "pragmaStmt" then
for _ , registration in ipairs ( x . cleanupRegistrations or { } ) do
if not registration . after then
local cleanup = registration . cleanup
e ( ( "%s[%q]=%s;" ) : format ( cleanupRegistry ( ) , cleanup . key , cleanup . name ) , sourceLine ( x ) )
end
end
if x . stat then
emit ( x . stat )
end
for _ , registration in ipairs ( x . cleanupRegistrations or { } ) do
if registration . after then
local cleanup = registration . cleanup
e ( ( ";%s[%q]=%s" ) : format ( cleanupRegistry ( ) , cleanup . key , cleanup . name ) , sourceLine ( x ) )
end
end

elseif kind == "noSuspendStmt" then


e ( "do" , x . keywordTok and x . keywordTok . line or nil )
if x . body then
emit ( x . body )
end
e ( "end" , x . endTok and x . endTok . line or nil )

elseif kind == "effectRegionStmt" then

e ( "do" , x . keywordTok and x . keywordTok . line or nil )
if x . body then
emit ( x . body )
end
e ( "end" , x . endTok and x . endTok . line or nil )

elseif kind == "unsafeStmt" then
e ( "do" , x . unsafeTok and x . unsafeTok . line or nil )
if x . body then
emit ( x . body )
end
e ( "end" , x . endTok and x . endTok . line or nil )

elseif kind == "tableExpr" and x . presizeFields and not coverageOn then



e ( "{" , sourceLine ( x ) )
for _ , field in ipairs ( x . presizeFields ) do
e ( field . name . text .. "=" , sourceLine ( field . stat ) )
emit ( field . value )
e ( "," )
end
e ( "}" )

elseif kind == "tableExpr" and x . presize then




local name = tableIntrinsicName ( "new" )
e ( ( "%s(%d,%d)" ) : format ( name , x . presize . narr , x . presize . nhash ) , sourceLine ( x ) )

elseif kind == "param" then

if x . vararg then
e ( "..." , sourceLine ( x ) )
elseif x . name then
emit ( x . name )
else
emitChildren ( x )
end

elseif kind == "call" and x . layoutOf then




needsLayout = true
layoutName = layoutName or reservedName ( "__nuppLayout" )
local line = sourceLine ( x )
e ( ( "%s(" ) : format ( layoutName ) , line )
emit ( x . args and x . args . exprs and x . args . exprs [ 1 ] or x . obj )
e ( ( ", %q, %q, %q" ) : format ( x . layoutOf . name , x . layoutOf . spec , x . layoutOf . printed ) )
for _ , nestedName in ipairs ( x . layoutOf . nested ) do
e ( ( ", %s" ) : format ( nestedName ) )
end
e ( ")" )
return

elseif kind == "dotIndex" and x . compilerModule then


e ( compilerModuleName ( x . compilerModule ) , sourceLine ( x ) )

elseif kind == "localStmt" and x . concatBuffer then



emitChildren ( x )
e ( ( "local %s = %s.new()" ) : format ( x . concatBuffer . name , concatBufferName ( ) ) , sourceLine ( x ) )

elseif kind == "assignStmt" and x . concatBuffer then





e ( ( "%s:put(" ) : format ( x . concatBuffer . name ) , sourceLine ( x ) )
for j , piece in ipairs ( x . concatBuffer . pieces ) do
if j > 1 then
e ( "," )
end
emit ( piece )
end
e ( ")" )

else
emitChildren ( x )
end
end

planStructTags ( )
if hotState and hotState . mode == "patch" then
local captured = { }
for _ , planned in ipairs ( hotState . functions ) do
if hotSelected ( planned ) then
for _ , name in ipairs ( planned . captures ) do
captured [ name ] = true
end
end
end
local captures = { }
for name in pairs ( captured ) do
captures [ # captures + 1 ] = name
end
table . sort ( captures )
if # captures > 0 then
e ( "local " .. table . concat ( captures , "," ) .. ";" , 1 )
end
for _ , planned in ipairs ( hotState . functions ) do
if hotSelected ( planned ) then
hotEmitFunction ( planned )
end
end
else
for _ , child in ipairs ( result . root ) do
emit ( child )
end
end
raw ( "\n" )

local code = table . concat ( out )








if # pluck . helpers . order > 0 then
local declarations = { }
for _ , helper in ipairs ( pluck . helpers . order ) do
declarations [
# declarations + 1
] = ( "const %s = function(%s) %s end;" ) : format ( helper . name , helper . params , helper . body )
end
code = table . concat ( declarations ) .. code
end
if needsCleanupRegistry then
local linked = {
( "local %s=_G.__nuppCleanupRegistry;" ) : format ( cleanupRegistryName ) ,
(
"if %s==nil then %s={};_G.__nuppCleanupRegistry=%s end;"
) : format ( cleanupRegistryName , cleanupRegistryName , cleanupRegistryName ) ,
}
for _ , resolver in ipairs ( cleanupResolverOrder ) do
local cleanup = resolver . cleanup
assert (
cleanup . key ,
"unresolved affine terminal reached lowering in " .. (
filename or "<source>"
) .. ": " .. cleanup . id .. " (" .. cleanup . name .. ")"
)
linked [
# linked + 1
] = (
"local %s;%s=function(value) local cleanup=%s[%q];"
) : format (
resolver . name ,
resolver . name ,
cleanupRegistryName ,
cleanup . key
) .. (
"if cleanup==nil then return _G.error(%q) end;"
) : format (
"Nupp cleanup provider is not loaded: " .. cleanup . key
) .. ( "%s=cleanup;return cleanup(value) end;" ) : format ( resolver . name )
end
code = table . concat ( linked ) .. code
end


local runtimeEffects = emittedFeatureEffects



if compilerModules [ "nupp.log" ] then
code = (
"const %s = _G.nupp.log.forModule(%q); "
) : format ( compilerModules [ "nupp.log" ] , result . moduleName or filename or "?" ) .. code
end
local nativeBootstrap = stdlib . bootstrap ( runtimeEffects , hotState ~= nil )
if nativeBootstrap ~= "" then
code = nativeBootstrap .. code
else
code = "_G.nupp=_G.nupp or {};" .. code
end
if needsCleanupRegions then
local names , values = { } , { }
for _ , name in ipairs ( { "pcall" , "xpcall" , "error" , "unpack" , "select" , "setmetatable" , "tostring" , "ipairs" } ) do
names [ # names + 1 ] = cleanupGlobals [ name ]
values [ # values + 1 ] = name
end
code = (
"const %s={}; "
) : format (
cleanupCacheName
) .. (
"const %s=%s; "
) : format (
table . concat ( names , "," ) ,
table . concat ( values , "," )
) .. (
"const function %s(...) return "
) : format (
cleanupPackName
) .. (
"{n=%s(\"#\",...),...} end; "
) : format (
cleanupGlobals . select
) .. (
"const function %s(value) return value end; "
) : format (
cleanupIdName
) .. (
"const function %s(primary,errors,start) "
) : format (
cleanupFailureName
) .. "const secondary={} for i=start,#errors do " .. (
"secondary[#secondary+1]=errors[i] end return %s("
) : format (
cleanupGlobals . setmetatable
) .. "{primary=primary,suppressed=secondary},{__tostring=function(v) " .. (
"local text=%s(v.primary) for _,reason in %s("
) : format (
cleanupGlobals . tostring ,
cleanupGlobals . ipairs
) .. (
"v.suppressed) do text=text..\"\\ncleanup: \"..%s(reason) "
) : format ( cleanupGlobals . tostring ) .. "end return text end}) end; " .. code
end



if result . implicitSideEffects and next ( result . implicitSideEffects ) then
local effects = { }
for moduleName in pairs ( result . implicitSideEffects ) do
effects [ # effects + 1 ] = moduleName
end
table . sort ( effects )
for j , moduleName in ipairs ( effects ) do
effects [ j ] = ( "require(%q); " ) : format ( moduleName )
end
code = table . concat ( effects ) .. code
end
if needsArrayCache then
code = "const __nuppArrayCache = {}; const function __nuppArray(ct) "
.. "local a = __nuppArrayCache[ct] if not a then "
.. 'a = __nuppFfi.typeof("$[?]", ct) __nuppArrayCache[ct] = a end '
.. "return a end; "
.. code
end
if needsCArrayIndex then
code = (
"local function %s(i,n) if i%%1~=0 or i<0 or i>=n then "
) : format ( carrayIndexName ) .. "error('C array index out of bounds',2) end return i end; " .. code
end
if needsLibs then
code = "const __nuppLibCache = {}; const function __nuppLib(n) "
.. "local l = __nuppLibCache[n] if not l then "
.. "l = __nuppFfi.load(n) __nuppLibCache[n] = l end return l end; "
.. code
end
if needsCloneTab then





code = (
"const function %s(t) const out = {} "
) : format (
cloneTabName
)
.. "for k, v in next, t do out[k] = v end "
.. "const mt = getmetatable(t) "
.. "if type(mt) == \"table\" then setmetatable(out, mt) end "
.. "return out end; "
.. code
end
if needsClearTab then
code = ( "const %s = require(\"table.clear\"); " ) : format ( clearTabName ) .. code
end
if needsNewTab then
code = ( "const %s = require(\"table.new\"); " ) : format ( newTabName ) .. code
end
if needsMetatypeOnce then



code = (
"const %s = function(ct, mt) const ok, got = pcall("
) : format ( metatypeOnceName ) .. "__nuppFfi.metatype, ct, mt) if ok then return got end return ct end; " .. code
needsFfi = true
end
if # structTagOrder > 0 then



local forwards = { }
for _ , tag in ipairs ( structTagOrder ) do
forwards [ # forwards + 1 ] = ( "pcall(__nuppFfi.cdef, \"struct %s;\"); " ) : format ( tag )
end
code = table . concat ( forwards ) .. code
needsFfi = true
end
if needsLayout then




code = (
"const %s = (function() const cache = setmetatable({}, {__mode = \"k\"}) "
.. "return function(ct, name, spec, printed, ...) "
.. "local hit = cache[ct] if hit then return hit end "
.. "const nested = {...} local at = 0 "
.. "const fields = {} "
.. "for fname, ctype in spec:gmatch(\"([^:,]+):([^,]+)\") do "
.. "local own local shown = ctype "
.. "if ctype:sub(1, 1) == \"$\" then at = at + 1 own = nested[at] "
.. "shown = ctype:sub(2) "
.. "const repeats = shown:match(\"%%[(%%d+)%%]$\") "
.. "if repeats then own = __nuppFfi.sizeof(own) * tonumber(repeats) end "
.. "elseif ctype:sub(-1) == \"*\" then own = \"void *\" "
.. "else own = ctype end "
.. "fields[#fields + 1] = {name = fname, ctype = shown, "
.. "offset = __nuppFfi.offsetof(ct, fname), size = type(own) == \"number\" and own or __nuppFfi.sizeof(own)} "
.. "end "
.. "const size = __nuppFfi.sizeof(ct) "
.. "for i = 1, #fields do "
.. "const after = fields[i + 1] and fields[i + 1].offset or size "
.. "fields[i].padding = after - fields[i].offset - fields[i].size end "
.. "const layout = {name = name, size = size, fields = fields, "
.. "fingerprint = printed .. \"|\" .. size} "
.. "cache[ct] = layout return layout end end)(); "
) : format ( layoutName ) .. code
needsFfi = true
end
if needsSuspension then
code = ( "const %s = require(\"nupp.suspension\"); " ) : format ( suspensionName ) .. code
end
for _ , moduleName in ipairs ( compilerModuleOrder ) do


if moduleName ~= "nupp.log" then
code = ( "const %s = require(%q); " ) : format ( compilerModules [ moduleName ] , moduleName ) .. code
end
end
if needsFfi then

code = 'const __nuppFfi = require("ffi"); ' .. code
end
if coverageOn and coverageName then



code = (
"local %s=_G.__nuppCoverage;if not %s then %s={hits={}};"
.. "function %s.hit(p,i)local f=%s.hits[p]or{};%s.hits[p]=f;"
.. "local k=tostring(i);f[k]=(f[k]or 0)+1 end;function %s.branch(p,i,v)local f=%s.hits[p]"
.. "or{};%s.hits[p]=f;local k=tostring(i)..(v and ':true'or ':false');"
.. "f[k]=(f[k]or 0)+1;return v end;_G.__nuppCoverage=%s end; "
) : format (
coverageName ,
coverageName ,
coverageName ,
coverageName ,
coverageName ,
coverageName ,
coverageName ,
coverageName ,
coverageName ,
coverageName ,
coverageName ,
coverageName
) .. code
end
if hotState then
local policies = { }
for policy in pairs ( hotState . policies ) do
policies [ # policies + 1 ] = policy
end
table . sort ( policies )
for j , policy in ipairs ( policies ) do
policies [ j ] = ( "_G.__nuppHotReload.policy(%s,%q); " ) : format ( hotState . slotsExpr , policy )
end
code = (
"local %s=_G.__nuppHotReload.module(%q); "
) : format ( hotState . slotsExpr , hotState . module ) .. table . concat ( policies ) .. code
end
local metadata = coverageOn and { path = coveragePath , sites = ( coverageSites or { } ) } or nil
local hotMetadata = nil
if hotState then
local functions = { }
for _ , planned in ipairs ( hotState . functions ) do
functions [
# functions + 1
] = {
slot = planned . slot ,
id = planned . id ,
name = planned . name ,
signature = planned . signature ,
selfName = planned . selfName ,
captures = planned . captures ,
implementation = planned . implementation ,
patchable = planned . patchable ,
affineCapture = planned . affineCapture ,
cUses = planned . cUses ,
cUnknown = planned . cUnknown ,
}
end
hotMetadata = {
module = hotState . module ,
mode = hotState . mode ,
baseGeneration = hotState . baseGeneration ,
functions = functions ,
structure = table . concat ( hotState . structure , "\1" ) ,
}
end




if result . preludeRuntime and result . preludeRuntime ~= "" then




local quotedPrelude = ( "%q" ) : format ( result . preludeRuntime ) : gsub ( "\n" , "n" )
code = ( "_G.assert(_G.loadstring(%s,%q))();" ) : format ( quotedPrelude , "@nupp-prelude" ) .. code
end



















if loadstring then
local chunk , reason = loadstring ( code , "@" .. tostring ( filename or "generated" ) )
if not chunk then
local text = tostring ( reason )


local line = tonumber ( text : match ( "function at line (%d+)" ) ) or tonumber ( text : match ( "^[^:]*:(%d+):" ) ) or 0




local cap = text : match ( "more than (%d+) upvalues" )
local message , help
if cap then
message = (
"this function captures more than %s names from around it, "
.. "which is more than a Lua function can hold"
) : format ( cap )
help = "pass some of them as arguments, or gather what it reads into one " .. "value and capture that"
else
message = "generated code does not load: " .. ( text : gsub ( "^[^:]*:%d+:%s*" , "" ) )
help = "this is a bug in the compiler rather than in this file; `nupp bc " .. tostring (
filename or ""
) .. "` shows what it generated"
end
diag ( { line = line , col = 1 , offset = 0 , text = "" } , "NUPP3005" , message , help )
end
end

return code , diags , metadata , emittedFeatureEffects , hotMetadata
end

return gen
