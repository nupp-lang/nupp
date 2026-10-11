_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppBuffer = require("nupp.text"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






































local cst = require ( "nupp.compiler.syntax.cst" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local parser = require ( "nupp.compiler.syntax.parser" )
local predicate = require ( "nupp.compiler.types.predicate" )
local switchplan = require ( "nupp.compiler.lua.switchplan" )
local stdlib = require ( "nupp.compiler.stdlib" )
local native = require ( "nupp.compiler.native" )
local capabilities = require ( "nupp.compiler.capabilities" )
local cabi = require ( "nupp.compiler.cinterop.cabi" )
local bit = require ( "nupp.compiler.bitops" )

local gen = { }


function gen . runtimeModules ( code ) 
local parsed = parser . parse ( code , "=generated" )
local found = { }

local function visit ( node ) 
if type ( node ) ~= "table" then
return
end
if node . kind == "call" and node . obj and node . args then
local callee = node . obj
local direct = callee . kind == "name" and callee . token and callee . token . text == "require"
local global = callee . kind == "dotIndex"
and callee . obj
and callee . obj . kind == "name"
and callee . obj . token
and callee . obj . token . text == "_G"
and callee . name
and callee . name . text == "require"
local argument = node . args . exprs and node . args . exprs [ 1 ]
if callee . kind == "name"
and callee . token
and callee . token . text == "pcall"
and argument
and argument . kind == "name"
and argument . token
and argument . token . text == "require"
then
direct = true
argument = node . args . exprs [ 2 ]
end
if ( direct or global ) and argument and argument . kind == "string" then
local name = lexer . stringValue ( argument . token . text )
if name ~= nil then
found [ name ] = true
end
end
end
for _ , child in ipairs ( node ) do
visit ( child )
end
end

visit ( parsed . root )
local modules = { }
for name in pairs ( found ) do
modules [ # modules + 1 ] = name
end
table . sort ( modules )

return modules
end




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
withStmt = true ,
yieldStmt = true ,
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
return ("%s (*)(%s)") : format ( ret , # params > 0 and table . concat ( params , ", " ) or "void" )
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
local INITIALIZER_MEMBER = "__nuppInit"


local function initializerMember ( index ) 
return "__nuppInit" .. tostring ( index or 1 )
end

local function constructorMember ( index ) 
return "__nuppCtor" .. tostring ( index or 1 )
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
}




local literal = { }

function literal . quote ( s ) 
return lexer . quoteBacktickBody ( s )
end




local function quoteLine ( value ) 
return ( string . format ( "%q" , value ) : gsub ( "\n" , "n" ) )
end





local function cDeclarations ( text ) 
local found = { }
local depth , start , at = 0 , 1 , 1
local length = # text
while at <= length do
local c = text : sub ( at , at )
if c == "/" and text : sub ( at + 1 , at + 1 ) == "*" then
local close = text : find ( "*/" , at + 2 , true )
at = close and close + 2 or length + 1
elseif c == "/" and text : sub ( at + 1 , at + 1 ) == "/" then
local close = text : find ( "\n" , at + 2 , true )
at = close and close + 1 or length + 1
elseif c == "\"" or c == "'" then
at = at + 1
while at <= length and text : sub ( at , at ) ~= c do
at = at + ( text : sub ( at , at ) == "\\" and 2 or 1 )
end
at = at + 1
else
if c == "{" or c == "(" or c == "[" then
depth = depth + 1
elseif c == "}" or c == ")" or c == "]" then
depth = depth - 1
elseif c == ";" and depth <= 0 then
found [ # found + 1 ] = text : sub ( start , at )
start = at + 1
end
at = at + 1
end
end
local rest = text : sub ( start )
if rest : find ( "%S" ) then
found [ # found + 1 ] = rest
end

return found
end




local function quotedCDeclarations ( text ) 
local quoted = { }
for _ , declaration in ipairs ( cDeclarations ( text ) ) do
if declaration : find ( "%S" ) then
quoted [ # quoted + 1 ] = ( ( string . format ( "%q" , declaration ) : gsub ( "\n" , "n" ) ) )
end
end

return quoted
end






local function dedentLongString ( text ) 
local equals = text : match ( "^%[(=*)%[" )
if equals == nil then
return text
end
local delimiterLength = # equals + 2
local body = text : sub ( delimiterLength + 1 , # text - delimiterLength )
body = body : gsub ( "\13\n" , "\n" ) : gsub ( "\13" , "\n" )
if body : sub ( 1 , 1 ) == "\n" then
body = body : sub ( 2 )
end
local margin = body : match ( "\n([ \9]*)$" )
if margin then
body = body : sub ( 1 , # body - # margin )
else


for line in ( body .. "\n" ) : gmatch ( "([^\n]*)\n" ) do
if line : find ( "[^ \9]" ) then
local indent = line : match ( "^[ \9]*" ) or ""
if margin == nil then
margin = indent
else
local length = math . min ( # margin , # indent )
local shared = 0
while shared < length
and margin : sub ( shared + 1 , shared + 1 ) == indent : sub ( shared + 1 , shared + 1 ) do
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
local recipeCodec = require ( "nupp.compiler.comptime.materialize.codec" )
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
































































local spillNextModule = false



local function nativeOnlyStruct ( decl ) 
local nominal = decl . resolvedType or decl . hoistedType
if nominal == nil or nominal . tag ~= "nominal" then
return false
end
local origin = nominal . origin or nominal

return origin . nativeOnly == true
end






local function simdFamilyOf ( t ) 
if t == nil then
return nil , nil
end
if t . tag == "const" then
t = t . inner
end
if t == nil or t . tag ~= "nominal" then
return nil , nil
end
local origin = t . origin or t
if origin . moduleName ~= "nupp.simd" and origin . sealedModule ~= "nupp.simd" then
return nil , nil
end
local name = origin . name
if name ~= "Vector" and name ~= "Mask" and name ~= "Species" then
return nil , nil
end
local element = ( t . typeArgs or { } ) [ 1 ]
local elementName = element ~= nil and tostring ( element . tag ) or "number"
if elementName == "literal" and element . base ~= nil then
elementName = tostring ( element . base . tag )
end

return name , elementName
end





local function storageVectorField ( x ) 
if x . kind ~= "dotIndex" or x . name == nil or x . obj == nil or x . assignmentTarget == true then
return nil , nil
end
local objectType = x . obj . inferredType
while objectType ~= nil
and (
objectType . tag == "ptr"
or objectType . tag == "const"
or objectType . tag == "borrowed"
or objectType . tag == "affine"
or objectType . tag == "pinned"
) do
objectType = objectType . tag == "ptr" and objectType . elem or objectType . inner
end
if objectType == nil or objectType . tag ~= "nominal" or objectType . declKind ~= "struct" then
return nil , nil
end
local origin = objectType . origin or objectType
if origin . nativeOnly == true then
return nil , nil
end

return require ( "nupp.compiler.targetlayout" ) . storageVector ( x . inferredType )
end









function gen . generate (
result ,
filename ,
coverage ,
hot ,
bytecodeBoundary ,
forcedEffects
) 


if result . moduleName == "nupp.runtime.target" then
return ("return {dialect=\"luajit\",host=%q}") : format ( result . host or "native" ) , { } , nil , { }
end
local out = { }
local capabilityResolution = capabilities . resolve ( )
























local SCALAR_INLINE = {
[ "i32.wrap" ] = { arity = 1 , parts = { "@tobit(" , 1 , ")" } , } ,
[ "i32.add" ] = { arity = 2 , parts = { "@tobit((" , 1 , ")+(" , 2 , "))" } , } ,
[ "i32.sub" ] = { arity = 2 , parts = { "@tobit((" , 1 , ")-(" , 2 , "))" } , } ,
[ "i32.andBits" ] = { arity = 2 , parts = { "@band(" , 1 , "," , 2 , ")" } , } ,
[ "i32.orBits" ] = { arity = 2 , parts = { "@bor(" , 1 , "," , 2 , ")" } , } ,
[ "i32.xorBits" ] = { arity = 2 , parts = { "@bxor(" , 1 , "," , 2 , ")" } , } ,
[ "i32.notBits" ] = { arity = 1 , parts = { "@bnot(" , 1 , ")" } , } ,
[ "i32.shiftLeft" ] = { arity = 2 , parts = { "@lshift(" , 1 , ",@band(" , 2 , ",31))" } , } ,
[ "i32.shiftRightArithmetic" ] = { arity = 2 , parts = { "@arshift(" , 1 , ",@band(" , 2 , ",31))" } , } ,
[ "i32.rotateLeft" ] = { arity = 2 , parts = { "@rol(" , 1 , ",@band(" , 2 , ",31))" } , } ,
[ "i32.rotateRight" ] = { arity = 2 , parts = { "@ror(" , 1 , ",@band(" , 2 , ",31))" } , } ,
[ "i32.fromU32" ] = { arity = 1 , parts = { "@tobit(" , 1 , ")" } , } ,
[ "u32.toI32" ] = { arity = 1 , parts = { "@tobit(" , 1 , ")" } , } ,






[ "u32.wrap" ] = { arity = 1 , parts = { "(@tobit(" , 1 , ")%4294967296)" } , } ,
[ "u32.fromI32" ] = { arity = 1 , parts = { "(@tobit(" , 1 , ")%4294967296)" } , } ,
[ "u32.add" ] = { arity = 2 , parts = { "(@tobit((" , 1 , ")+(" , 2 , "))%4294967296)" } , } ,
[ "u32.sub" ] = { arity = 2 , parts = { "(@tobit((" , 1 , ")-(" , 2 , "))%4294967296)" } , } ,
[ "u32.andBits" ] = { arity = 2 , parts = { "(@band(" , 1 , "," , 2 , ")%4294967296)" } , } ,
[ "u32.orBits" ] = { arity = 2 , parts = { "(@bor(" , 1 , "," , 2 , ")%4294967296)" } , } ,
[ "u32.xorBits" ] = { arity = 2 , parts = { "(@bxor(" , 1 , "," , 2 , ")%4294967296)" } , } ,
[ "u32.notBits" ] = { arity = 1 , parts = { "(@bnot(" , 1 , ")%4294967296)" } , } ,
[ "u32.shiftLeft" ] = { arity = 2 , parts = { "(@lshift(" , 1 , ",@band(" , 2 , ",31))%4294967296)" } , } ,
[ "u32.shiftRightLogical" ] = { arity = 2 , parts = { "(@rshift(" , 1 , ",@band(" , 2 , ",31))%4294967296)" } , } ,
[ "u32.rotateLeft" ] = { arity = 2 , parts = { "(@rol(" , 1 , ",@band(" , 2 , ",31))%4294967296)" } , } ,
[ "u32.rotateRight" ] = { arity = 2 , parts = { "(@ror(" , 1 , ",@band(" , 2 , ",31))%4294967296)" } , } ,
}

local declaredModuleName = result . declaredModuleName
local curLine = 1
local atLineStart = true
local diags = { }










local emittedFeatureEffects = { }
for effect in pairs ( forcedEffects or { } ) do
emittedFeatureEffects [ effect ] = true
end

local function needRuntimeEffect ( effect , moduleName ) 
if effect ~= nil then
emittedFeatureEffects [ effect ] = true
end
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
local structs = { }
local indexOf = { }

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
local h = bit . tobit ( 2166136261 )
for i = 1 , # text do
local mixed = bit . bxor ( h , text : byte ( i ) )
h = bit . tobit ( bit . lshift ( mixed , 24 ) + bit . lshift ( mixed , 8 ) + mixed * 147 )
end

return ("%08x") : format ( bit . band ( h , 2147483647 ) )
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
while t . kind == "topt" or t . kind == "tconst" do
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
if structTag [ ( decl . name ) . text ] then
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
local cleanupResolverOrder


= { }
local newTabName , clearTabName , cloneTabName
local needsCleanupRegions = false
local cleanupPackName , cleanupIdName , cleanupFailureName
local yieldableXpcallName
local yieldablePcallName




local cleanupGlobals


local cleanupCacheName
local cleanupCacheSites = 0
local cleanupStack = { }
local emitDepth = {
loop = 0 ,
fn = 0 ,
activations = { } ,
activationPlaceholders = { } ,
loopNodes = { } ,
loopWrappers = { } ,
captureFrames = { } ,
captureFrameStack = { } ,
constructorReturnName = nil ,
spill = nil ,


storageVectorReading = { } ,
}
local coverageOn = coverage == true or type ( coverage ) == "table"
local coveragePath = coverageOn
and ( type ( coverage ) == "table" and ( coverage ) . path or filename )
or nil
local coverageSites = nil
local coverageSiteCount = 0
local coverageName



local coverageFunctions = nil
if coverageOn then
local found = { }

local function collect ( node ) 
if not node or cst . isToken ( node ) then
return
end
if cst . FUNCTION_DECLARATIONS [ node . kind ] and node . body then
local last = cst . lastToken ( node )
found [ node . body ] = { name = cst . functionName ( node ) , endLine = last and last . line or nil , }
end
for _ , child in ipairs ( node ) do
collect ( child )
end
end

collect ( result . root )
coverageFunctions = found
end


local hotState = hot
and {
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
}
or nil





local function reservedName ( preferred ) 
if not usedNames [ preferred ] then
usedNames [ preferred ] = true
return preferred
end

return nextTemp ( )
end





local INLINE_BITOPS = { "arshift" , "band" , "bnot" , "bor" , "bxor" , "lshift" , "rol" , "ror" , "rshift" , "tobit" , }
local inlineBitopNames = { }

local function inlineBitop ( name ) 
local reserved = inlineBitopNames [ name ]
if reserved then
return reserved
end
local fresh = reservedName ( "__nuppBit" .. name : sub ( 1 , 1 ) : upper ( ) .. name : sub ( 2 ) )
inlineBitopNames [ name ] = fresh

return fresh
end

emitDepth . exportTableName = declaredModuleName and reservedName ( "__nuppExports" ) or nil








local spillsModuleScope = spillNextModule
spillNextModule = false
if spillsModuleScope and declaredModuleName and hot == nil then
local spill = { decls = { } , names = { } , order = { } , scopeName = reservedName ( "__nuppScope" ) }
for _ , block in ipairs ( result . root . blocks or { } ) do
for _ , statement in ipairs ( block . stats or { } ) do
local actual = statement
while actual and ( actual . kind == "exportStmt" or actual . kind == "pragmaStmt" ) do
actual = actual . stat
end
if actual
and (
actual . kind == "cdefStruct"
or actual . kind == "cdefFunc"
or actual . kind == "recordDecl" and actual . visibility ~= "global" and not declPath ( actual )
or actual . kind == "localFuncStmt" and actual . exported
or actual . kind == "funcStmt" and actual . exported
)
then
spill . decls [ actual ] = true
end
end
end



spill . name = function ( name ) 
if not spill . names [ name ] then
spill . names [ name ] = true
spill . order [ # spill . order + 1 ] = name
end
end
emitDepth . spill = spill
end
if declaredModuleName and cst . exportAssignment ( result . root ) then
emitDepth . exportAssignmentValueName = reservedName ( "__nuppExportValue" )
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
if definition ~= own
and token
and token . line ~= 0
and ( token . offset < firstOffset or token . offset > lastOffset )
then
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
local implicitSelf = node . kind == "funcStmt" and node . name and node . name . method ~= nil
or node . kind == "inlineMethod" and not node . inlineStatic
local slot = # hotState . functions + 1
local kind = node . kind == "localFuncStmt" and "local" or node . kind == "inlineMethod" and "inline" or "field"
local id = table . concat ( { hotState . module , owner or "module" , kind , name } , "/" )
local captures = hotOuterCaptures ( node )
local affine = node . affineInitializer ~= nil or node . body and # ( node . body . takenCaptures or { } ) > 0
local affineCapture = affine
and node . body
and node . body . takenCaptures
and node . body . takenCaptures [ 1 ]
and node . body . takenCaptures [ 1 ] . name
or nil
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



local structName = node . structOwner : match ( "[^.]+$" ) or node . structOwner
node . hotRuntimeName = "__nuppMt_" .. structName .. ".__index" .. (
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




local PROLOGUE_CONSTANT_LOCALS = 32
local constants = { byBody = { } , order = { } , spilled = { } , spillName = nil }



















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

local function declareConstant ( prefix , body ) 
local found = constants . byBody [ body ]
if found then
return found
end
local name
if # constants . order < 32 then
name = reservedName ( prefix .. tostring ( # constants . order + 1 ) )
constants . order [ # constants . order + 1 ] = { name = name , body = body }
else
constants . spillName = constants . spillName or reservedName ( "__nuppSwitchConstants" )
local index = # constants . spilled + 1
constants . spilled [ index ] = body
name = constants . spillName .. "[" .. tostring ( index ) .. "]"
end
constants . byBody [ body ] = name

return name
end






local function compilerModuleName ( moduleName ) 
local name = compilerModules [ moduleName ]
if not name then
local preferred = moduleName == "nupp.text" and "__nuppBuffer" or "__nuppModule"
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
return compilerModuleName ( "nupp.text" )
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





local caller = declareHelper ( "__nuppCleanup" , "__nuppV" , ("return __nuppV:%s()") : format ( cleanup . name ) )
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
atLineStart = s : sub ( -1 ) == "\n"
elseif # s > 0 then
atLineStart = false
end
end


local function sync ( line ) 
while line and curLine < line do
local tail = out [ # out ]
if tail then
out [ # out ] = tail : gsub ( "[ \9]+$" , "" )
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







local function beginActivation ( ) 
local index = # emitDepth . activationPlaceholders + 1
local ctx = {
name = nextTemp ( ) ,
marker = ("--[[__nuppActivationCache%d__]]") : format ( index ) ,
used = false ,
outerLoops = emitDepth . loopNodes ,
}
emitDepth . activationPlaceholders [ index ] = ctx
emitDepth . activations [ # emitDepth . activations + 1 ] = ctx
emitDepth . loopNodes = { }
e ( ctx . marker )
end

local function endActivation ( ) 
local ctx = emitDepth . activations [ # emitDepth . activations ]
if not ctx then
return
end
emitDepth . loopNodes = ctx . outerLoops
emitDepth . activations [ # emitDepth . activations ] = nil
end

emitDepth . beginActivation = beginActivation
emitDepth . endActivation = endActivation






















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
if x . concatBuffer and not x . concatBuffer . directReturn then
e ( ("%s = %s:tostring()") : format ( x . concatBuffer . target , x . concatBuffer . name ) , line )
end
end

local function emitDerivedMembers ( x , runtimeName , memberRuntimeName ) 
local recipe = x . deriveRecipe
if not recipe then
return
end
for effect in pairs ( recipe . effects or { } ) do
needRuntimeEffect ( effect )
end
local recipeCodec = require ( "nupp.compiler.comptime.materialize.codec" )
local renderedRecipe , renderError = recipeCodec . render ( recipe , { limit = recipeCodec . MAX_OUTPUT_BYTES , } )
if not renderedRecipe then
diag (
x . name ,
"NUPP2808" ,
renderError == "limit"
and ("derive output exceeds %d rendered bytes") : format ( recipeCodec . MAX_OUTPUT_BYTES )
or "derive output recipe is invalid" ,
"split the record or write the generated behavior explicitly"
)
return
end
needRuntimeEffect ( "stdlib.derives" )



local receiverName = reservedName ( "self" )
local recipeName = reservedName ( "__nuppDerived" )
local entryName = reservedName ( "__nuppDerivedEntry" )
local nominal = x . resolvedType
if recipe . initializer and nominal and # ( nominal . constructorEntries or { } ) == 0 then




local memberOwner = memberRuntimeName or runtimeName
local parameters , writes = { } , { }
local position = 0
for _ , field in ipairs ( nominal . fieldOrder or { } ) do
local fieldType = nominal . byname and nominal . byname [ field ] or nil
local stored = fieldType ~= nil
and fieldType . tag ~= "typeobject"
and not ( nominal . nestedTypes and nominal . nestedTypes [ field ] )
and not ( nominal . privateFields and nominal . privateFields [ field ] )
if stored then
position = position + 1
local parameter = reservedName ( "a" .. tostring ( position ) )
parameters [ position ] = parameter
local default = nominal . fieldDefaults and nominal . fieldDefaults [ field ] or nil
local target = cst . identifier ( field ) and ( receiverName .. "." .. field )
or ("%s[%q]") : format ( receiverName , field )
if default then
local rendered , why = recipeCodec . render ( default . value , { limit = recipeCodec . MAX_OUTPUT_BYTES , } )
if not rendered then
error ( "invalid field default: " .. tostring ( why ) )
end
writes [
# writes + 1
] = (" if %s == nil then %s = %s else %s = %s end")

: format ( parameter , target , rendered , target , parameter )
else
writes [ # writes + 1 ] = (" %s = %s") : format ( target , parameter )
end
end
end
e (
(";%s.%s=function(%s%s)%s return %s end")

: format (
memberOwner ,
recipe . initializer ,
receiverName ,
# parameters > 0 and ( ", " .. table . concat ( parameters , ", " ) ) or "" ,
table . concat ( writes ) ,
receiverName
)
)
end
e ( ";do local " .. recipeName .. "=" .. renderedRecipe )
e ( (";local %s=_G.nupp.__derive.register(%q,%s,%s)") : format ( entryName , recipe . key , runtimeName , recipeName ) )

local function forwardingArgument ( argument , parameters ) 
if argument . kind == "receiver" then
return receiverName
elseif argument . kind == "entry" then
return entryName
elseif argument . kind == "argument" then
return parameters [ argument . name ] or error ( "invalid derived member argument " .. tostring ( argument . name ) )
elseif argument . kind == "field" then
return ("%s[%q]") : format ( receiverName , argument . name )
elseif argument . kind == "constant" then
local rendered , why = recipeCodec . render ( argument . value , { limit = recipeCodec . MAX_OUTPUT_BYTES , } )
if not rendered then
error ( "invalid derived constant: " .. tostring ( why ) )
end
return rendered
elseif argument . kind == "witness" then
local subject = x . deriveWitnesses and x . deriveWitnesses [ argument . witnessIndex ]
local path = argument . runtimePath or error ( "invalid derived type witness" )
assert ( subject , "missing semantic derived type witness" )
needRuntimeEffect ( "stdlib.typewitness" )
local reflection = require ( "nupp.compiler.reflection" )
local data = literal . renderData (
reflection . describe ( subject , subject . runtimePath or subject . name )
) .. "," .. literal . renderData ( reflection . runtimeReferences ( subject ) )
return "(_G.nupp.__reflect.known("
.. path
.. ") and "
.. path
.. " or _G.nupp.__reflect.ensure("
.. path
.. ",function() return "
.. data
.. " end))"
elseif argument . kind == "array" then
local children = { }
for index , child in ipairs ( argument . values or { } ) do
children [ index ] = forwardingArgument ( child , parameters )
end
return "{" .. table . concat ( children , "," ) .. "}"
end
error ( "unknown derived forwarding argument " .. tostring ( argument . kind ) )
end

local memberOwner = memberRuntimeName or runtimeName
for _ , member in ipairs ( recipe . members or { } ) do
if member . operation == "forward.v1" then
local names , parameters = { } , { }
local first = 1
if member . namespace == "instance" then
names [ 1 ] = receiverName
first = 2
end
for index = first , # ( member . paramNames or { } ) do
local declared = member . paramNames [ index ]
local runtimeParameter = reservedName (
declared ~= "" and declared or ( "argument" .. tostring ( index - first + 1 ) )
)
names [ # names + 1 ] = runtimeParameter
if declared ~= "" then
parameters [ declared ] = runtimeParameter
end
end
local arguments = { }
for index , argument in ipairs ( member . arguments or { } ) do
arguments [ index ] = forwardingArgument ( argument , parameters )
end
local helper = member . helper . localPath
or (
"_G.require(" .. string . format (
"%q" ,
member . helper . module
) .. ")[" .. string . format ( "%q" , member . helper . member ) .. "]"
)
e (
(";%s[%q]=function(%s)return %s(%s)end")

: format ( memberOwner , member . name , table . concat ( names , "," ) , helper , table . concat ( arguments , "," ) )
)
else
error ( "unknown derived member operation " .. tostring ( member . operation ) )
end
end
e ( " end" )
end

local emit
local outliningSendable = nil

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





local function soaFieldTarget ( target ) 
if not target or target . kind ~= "dotIndex" then
return nil , nil
end
local row = target . obj
if not row or not row . soaRow then
return nil , nil
end
if target . soaField then
return row , target . soaField . ordinal
end
local element = row . soaRow . element
local wanted = target . name and target . name . text
if element and element . tag == "nominal" and wanted then
for ordinal , name in ipairs ( element . fieldOrder or { } ) do
if name == wanted then
return row , ordinal
end
end
end

return nil , nil
end





local function soaUncheckedRow ( row ) 
return row ~= nil and row . indexedDirectAccess == true
end

local function soaSlot ( view , ordinal , index , unchecked ) 
if unchecked then
return ("%s.columns[%d][%s.offset+%s-1]") : format ( view , ordinal , view , index )
end
return ("%s.columns[%d][%s:checkedIndex(%s)]") : format ( view , ordinal , view , index )
end


emitDepth . soa = { unchecked = soaUncheckedRow , slot = soaSlot , }

local function virtualView ( node ) 
return node
and node . kind == "name"
and node . token
and node . token . definition
and node . token . definition . virtualIndexedView
or nil
end

local function emitViewRoot ( node ) 
local view = virtualView ( node )
if view then
if view . kind == "root" and view . anchorName then
e ( view . anchorName )
else
emitViewRoot ( view . source )
end
else
emit ( node )
end
end

local function emitViewCount ( node ) 
local view = virtualView ( node )
if view then
if view . kind == "root" then
if view . countName then
e ( view . countName )
else
emit ( node )
end
elseif view . kind == "slice" then
e ( "(" )
emit ( node )
e ( "-" )
e ( view . firstName )
e ( "+1)" )
else
emit ( node )
end
else
emit ( node )
e ( ".count" )
end
end

local function emitViewOffset ( node ) 
local view = virtualView ( node )
if view then
if view . kind == "root" then
e ( view . offsetName or "0" )
else
emitViewOffset ( view . source )
end
if view . kind == "slice" then
e ( "+" )
e ( view . firstName )
e ( "-1" )
end
else
emit ( node )
e ( ".offset" )
end
end

local function projectedView ( node ) 
local view = virtualView ( node )
if not view then
return nil
end
if view . kind == "field" then
return view
end

return projectedView ( view . source )
end

local function rootView ( node ) 
local view = virtualView ( node )
if not view then
return nil
end
if view . kind == "root" then
return view
end

return rootView ( view . source )
end

local function emitIndex ( index ) 
if type ( index ) == "string" then
e ( index )
else
emit ( index )
end
end

local function emitCheckedViewIndex ( view , index ) 
local descriptor = virtualView ( view ) . descriptor
local message = descriptor . adapter == "soa" and "SoA row index out of bounds"
or descriptor . writable and "write span index out of bounds"
or "span index out of bounds"
e ( compilerModuleName ( "nupp.mem.indexed" ) .. "._checkedIndex(" )
emitViewCount ( view )
e ( "," )
emitIndex ( index )
e ( (",%q)") : format ( message ) )
end

local function emitSpanSlot ( view , index , field , checked ) 
local projection = projectedView ( view )
if projection then
emitViewRoot ( projection . source )
e ( (".columns[%d][") : format ( projection . ordinal ) )
else
local root = rootView ( view )
local producerKind = root and root . producer and root . producer . kind or nil
if producerKind == "string" and capabilities . get ( capabilityResolution , "cstorage" ) . kind == "runtime" then
e ( "string.byte(" )
emitViewRoot ( view )
e ( "," )
emitViewOffset ( view )
e ( "+" )
if checked then
emitCheckedViewIndex ( view , index )
else
emitIndex ( index )
end
e ( ")" )
return
elseif producerKind == "string" then
needsFfi = true
e ( "__nuppFfi.cast(\"const uint8_t *\"," )
emitViewRoot ( view )
e ( ")[" )
else
emitViewRoot ( view )
if producerKind ~= "carray" and producerKind ~= "fixed-carray" then
e ( ".pointer" )
end
e ( "[" )
end
end
emitViewOffset ( view )
e ( "+" )
if checked then
emitCheckedViewIndex ( view , index )
else
emitIndex ( index )
end
e ( "-1]" )
if field then
e ( "." .. field )
end
end

emitDepth . soa . active = { }
emitDepth . soa . plan = function ( view , index , ordinal ) 
local viewDefinition = view and view . kind == "name" and view . token and view . token . definition or nil
local indexDefinition = index and index . kind == "name" and index . token and index . token . definition or nil
if not viewDefinition or not indexDefinition then
return nil
end
for position = # emitDepth . soa . active , 1 , -1 do
local plan = emitDepth . soa . active [ position ]
if plan . viewDefinition == viewDefinition
and plan . indexDefinition == indexDefinition
and plan . columnNames
and plan . columnNames [ ordinal ]
then
return plan
end
end

return nil
end

emitDepth . soa . boundName = function ( view , ordinal , index ) 
local plan = emitDepth . soa . plan ( view , index , ordinal )
if not plan then
return nil
end

return ("%s[%s]") : format ( plan . columnNames [ ordinal ] , plan . physicalName )
end

emitDepth . soa . boundSlot = function ( view , ordinal , index ) 
local name = emitDepth . soa . boundName ( view , ordinal , index )
if not name then
return false
end
e ( name )

return true
end

emitDepth . soa . requiredBoundName = function ( view , ordinal , index ) 
local name = emitDepth . soa . boundName ( view , ordinal , index )
if not name then
error ( "an active SoA binding lost its selected column" )
end

return name
end

local function emitSoaSlot ( view , ordinal , index , checked ) 
if not checked and emitDepth . soa . boundSlot ( view , ordinal , index ) then
return
end
emitViewRoot ( view )
e ( (".columns[%d][") : format ( ordinal ) )
emitViewOffset ( view )
e ( "+" )
if checked then
emitCheckedViewIndex ( view , index )
else
emitIndex ( index )
end
e ( "-1]" )
end

emitDepth . view = {
info = virtualView ,
root = emitViewRoot ,
count = emitViewCount ,
offset = emitViewOffset ,
spanSlot = emitSpanSlot ,
soaSlot = emitSoaSlot ,
}

emitDepth . soa . openLoop = function ( loop ) 
local bindings = loop . soaLoopBindings or { }
if # bindings == 0 then
return
end
e ( "do" , sourceLine ( loop ) )
for _ , plan in ipairs ( bindings ) do
plan . columnsName = plan . columnsName or nextTemp ( )
plan . offsetName = plan . offsetName or nextTemp ( )
plan . physicalName = plan . physicalName or nextTemp ( )
plan . columnNames = plan . columnNames or { }
e ( (" const %s=") : format ( plan . columnsName ) )
emitDepth . view . root ( plan . view )
e ( ".columns" )
e ( ("; const %s=") : format ( plan . offsetName ) )
emitDepth . view . offset ( plan . view )
e ( "-1" )
for _ , ordinal in ipairs ( plan . fieldOrder ) do
plan . columnNames [ ordinal ] = plan . columnNames [ ordinal ] or nextTemp ( )
e ( ("; const %s=%s[%d]") : format ( plan . columnNames [ ordinal ] , plan . columnsName , ordinal ) )
end
end
end

emitDepth . soa . beginIteration = function ( loop ) 
for _ , plan in ipairs ( loop . soaLoopBindings or { } ) do
e ( ("const %s=%s+") : format ( plan . physicalName , plan . offsetName ) , sourceLine ( loop . body ) )
emit ( plan . index )
e ( ";" )
emitDepth . soa . active [ # emitDepth . soa . active + 1 ] = plan
end
end

emitDepth . soa . endIteration = function ( loop ) 
for _ = 1 , # ( loop . soaLoopBindings or { } ) do
emitDepth . soa . active [ # emitDepth . soa . active ] = nil
end
end

emitDepth . soa . closeLoop = function ( loop , line ) 
if # ( loop . soaLoopBindings or { } ) > 0 then
e ( "end" , line )
end
end

local function emitRuntimeLayout ( spec , line , emitCtype ) 
needsLayout = true
layoutName = layoutName or reservedName ( "__nuppLayout" )
e ( ("%s(") : format ( layoutName ) , line )
emitCtype ( )
e ( (", %q, %q, %q") : format ( spec . name , spec . spec , spec . printed ) )
for _ , nestedName in ipairs ( spec . nested or { } ) do
e ( (", %s") : format ( nestedName ) )
end
e ( ")" )
end
















local pluck = {
compat = result . compat ,
witnessPlan = require ( "nupp.compiler.lua.typewitness" ) . collect ( result . root , result . moduleExports ) ,
witnessDescriptions = { } ,
plans = { } ,
loweredPlans = { } ,
statementActive = { } ,
helpers = helpers ,
declareHelper = declareHelper ,
needRuntimeEffect = needRuntimeEffect ,
loweredFunction = loweredFunction ,
emitDerivedMembers = emitDerivedMembers ,
quote = literal . quote ,
renderData = literal . renderData ,
hotLibraries = hot and hot . libraries or { } ,




separator = function ( ) 
for index = # out , 1 , -1 do
local tail = out [ index ] : match ( "(%S+)%s*$" )
if tail then
local word = ( " " .. tail ) : match ( "[^%w_]([%a_]+)$" )
if tail : sub ( -1 ) == ";" or word == "do" or word == "then" or word == "else" or word == "repeat" then
return " "
end
return ";"
end
end

return " "
end ,




wideFloorDivision = function ( ... ) 
for index = 1 , select ( "#" , ... ) do
local node = select ( index , ... )
local t = node and not cst . isToken ( node ) and node . inferredType or nil
if t and t . tag == "literal" then
t = t . base
end
if t and ( t . tag == "int64" or t . tag == "uint64" ) then
return declareHelper (
"__nuppFloorDiv" ,
"a,b" ,
"local q=a/b;if q*b~=a and (a<0)~=(b<0) then q=q-1 end;return q"
)
end
end

return nil
end ,



endToken = function ( node ) 
for index = # node , 1 , -1 do
local child = node [ index ]
if cst . isToken ( child ) and child . kind == "end" then
return child
end
end

return nil
end ,


hasBindingClause = function ( node ) 
for _ , clause in ipairs ( node . clauses or { } ) do
if clause . binding then
return true
end
end

return false
end ,












reasons = {
capture = "the body sets this site's own capture flags" ,
reinit = "the body sets this site's own reinit flag" ,
move = "the body clears this site's own move flag" ,
cheader = "a C header is declared once where it is imported" ,
region = "the protected body reads and writes this region's own owners and flags" ,
lazy = "the body defers an operand until the test that guards it has passed" ,
} ,



scalarInline = { forms = SCALAR_INLINE , bitop = inlineBitop , } ,
storage = {
enabled = capabilities . get ( capabilityResolution , "cstorage" ) . kind == "runtime" ,
name = reservedName ( "__nuppCstorage" )
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













function pluck . beginHoistedRegion ( ) 
local state = { output = out , line = curLine , start = atLineStart }
out , atLineStart = { } , false
return state
end

function pluck . saveHoistedRegion ( state ) 
state . helperOutput , state . helperLine , state . helperStart = out , curLine , atLineStart
out , curLine , atLineStart = state . output , 2147483647 , state . start
end

function pluck . finishHoistedRegion ( state ) 
e ( "end;" )
curLine = state . line
raw ( table . concat ( state . helperOutput ) )
curLine , atLineStart = state . helperLine , state . helperStart
end

function pluck . skipHoistedEnd ( line ) 
sync ( line )
end

function pluck . beginsWithLoweredWrapper ( expr ) 
local at = expr
while at ~= nil do
if at . automaticOwnerMoves ~= nil or at . trailingCallableCall == true then
return true
end
local kind = at . kind
if kind ~= "call" and kind ~= "methodCall" and kind ~= "dotIndex" and kind ~= "index" then
return false
end
at = at . obj
end

return false
end

function pluck . needsBindings ( call ) 
if not pluckableCall ( call ) or not call . obj or not call . args or not call . args . loweredArgs then
return false
end
for _ , argument in ipairs ( call . args . loweredArgs ) do
if argument . generatedKind == "field" and argument . source and argument . source . kind == "dotIndex" then
return true
end
end

return false
end

function pluck . callPlan ( call ) 
if not pluck . needsBindings ( call ) then
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
elseif argument . generatedKind == "expr" and index < lastDotted then


local alias = nextTemp ( )
plan . argAliases [ argument ] = alias
plan . steps [ # plan . steps + 1 ] = { kind = "expr" , name = alias , expr = argument . expr , at = argument . expr }
end
end

return plan
end

function pluck . emitSteps ( steps , lower ) 
for _ , step in ipairs ( steps ) do
if lower and step . kind == "expr" then
emitDepth . lowerSwitches ( step . expr )
end
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
elseif ( kind == "returnStmt" or kind == "localStmt" or kind == "assignStmt" )
and statement . exprs
and # statement . exprs == 1
then
direct = statement . exprs [ 1 ]
end



if direct and direct . kind == "newExpr" then
return direct . call
end

return direct
end

function pluck . statementCall ( statement ) 
local call = pluck . directCall ( statement )
if call
and (
statement . kind == "callStmt"
or statement . kind == "returnStmt"
or ( call . kind ~= "safeCall" and not call . safeObj and not call . safeMethod )
)
then
return call
end

return nil
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
local body = ("return string.format(%q%s)")

: format ( plan . format , # arguments > 0 and "," .. table . concat ( arguments , "," ) or "" )

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

return "_G.__nuppCoverage"
end

local function coverageSite ( kind , node ) 
coverageSiteCount = coverageSiteCount + 1
local id = coverageSiteCount
local sites = coverageSites or { }
coverageSites = sites
local site = { id = id , kind = kind , line = sourceLine ( node ) or 0 }



local declared = kind == "function" and coverageFunctions and coverageFunctions [ node ] or nil
if declared then
site . name = declared . name
site . endLine = declared . endLine
end
sites [ # sites + 1 ] = site

return id
end

local function coverageHit ( kind , node ) 
if not coverageOn then
return
end
local id = coverageSite ( kind , node )
e ( ("%s.hit(%q,%d);") : format ( coverageRuntime ( ) , coveragePath , id ) , sourceLine ( node ) )
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








function pluck . paramNames ( params , dropSelf ) 
local names = { }
for index , param in ipairs ( params or { } ) do
if dropSelf and index == 1 and param . name and param . name . text == "self" then

elseif param . namedVararg then
names [ # names + 1 ] = "..."
elseif param . name then
names [ # names + 1 ] = param . name . text
elseif param . vararg or param [ 1 ] and cst . isToken ( param [ 1 ] ) and param [ 1 ] . kind == "..." then
names [ # names + 1 ] = "..."
end
end

return names
end




function pluck . emitRegistrations ( list , line , after , declarationName ) 
for _ , registration in ipairs ( list or { } ) do
if after == nil or ( registration . after and true or false ) == after then
local cleanup = registration . cleanup
e ( ("%s[%q]=%s;") : format ( cleanupRegistry ( ) , cleanup . key , declarationName or cleanup . name ) , line )
end
end
end





function pluck . emitCompoundValue ( x , emitRead , lead , line ) 
if lead then
e ( lead , line )
end
emitRead ( )
e ( (" %s (") : format ( x . op . kind : sub ( 1 , -2 ) ) , x . op . line )
emit ( x . value )
e ( ")" )
end



function pluck . emitCompoundInto ( x , emitSlot ) 
emitSlot ( )
e ( (" %s ") : format ( x . op . kind ) , x . op . line )
emit ( x . value )
end

local function hotEmitImplementation ( planned ) 
local body = planned . node . body
local names = pluck . paramNames ( body . params , planned . implicitSelf )
if planned . implicitSelf then
table . insert ( names , 1 , "self" )
end
local line = sourceLine ( planned . node )
e ( "function(" .. table . concat ( names , "," ) .. ")" , line )
if body . varargParam then
e ( ("local %s={n=_G.select(\"#\",...),...}") : format ( body . varargParam . name . text ) )
end
emitDepth . fn = emitDepth . fn + 1
beginActivation ( )
if coverageOn then
coverageHit ( "function" , body )
end
if body . body then
emit ( body . body )
end
endActivation ( )
emitDepth . fn = emitDepth . fn - 1
local endToken = pluck . endToken ( body )
e ( "end" , endToken and endToken . line or nil )
end

local function hotDefinePrefix ( planned ) 
return ("_G.__nuppHotReload.define(%s,%d,%q,%q,%s,")

: format (
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
e ( (";%s=function(...) return %s[%d](...) end") : format ( planned . name , hotState . slotsExpr , planned . slot ) )
end
else
e ( hotDefinePrefix ( planned ) , line )
hotEmitImplementation ( planned )
e ( ")" )
if hotState . mode == "initial" then
local forwarded = planned . implicitSelf and "self,..." or "..."
e (
(";function %s(...) return %s[%d](%s) end")

: format ( planned . name , hotState . slotsExpr , planned . slot , forwarded )
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
if n . kind == "block" and n . automaticOwners and # n . automaticOwners > 0 then
emitAutomaticBlock ( n )
return
end
for _ , child in ipairs ( n ) do
emit ( child )
end
end




pluck . constSpecialize = { emission = nil , }
pluck . constSpecialize . integer = function ( node ) 
if node == nil or cst . isToken ( node ) then
return nil
end
if node . kind == "number" and node . token ~= nil then
local value = tonumber ( ( node . token . text : gsub ( "_" , "" ) ) )
if value ~= nil and value == math . floor ( value ) then
return value
end
elseif node . kind == "name" and node . token ~= nil and pluck . constSpecialize . emission ~= nil then
local emission = pluck . constSpecialize . emission
local written = emission . substitutions [ node . token . definition ]
local value = written ~= nil and tonumber ( written ) or nil
if value ~= nil and value == math . floor ( value ) then
return value
end
elseif node . kind == "castExpr" then
return pluck . constSpecialize . integer ( node . expr )
elseif node . folded ~= nil then
local value = tonumber ( node . folded )
if value ~= nil and value == math . floor ( value ) then
return value
end
end

return nil
end

pluck . constSpecialize . unrollableBody = function ( node ) 
local admitted = true

local function walkConst ( child ) 
if not admitted or child == nil or cst . isToken ( child ) then
return
end
if child ~= node and ( child . kind == "funcbody" or child . kind == "funcExpr" or child . kind == "shortfn" ) then
return
end
if child . kind == "breakStmt"
or child . kind == "continueStmt"
or child . kind == "gotoStmt"
or child . kind == "labelStmt"
then
admitted = false
return
end
for _ , nested in ipairs ( child ) do
walkConst ( nested )
end
end

walkConst ( node )

return admitted
end

pluck . constSpecialize . emitSpecialization = function ( declaration , specialization ) 
local prior = pluck . constSpecialize . emission

local priorSwitchTemps = emitDepth . switchTemps
local priorValueTemps = emitDepth . switchValueTemps
local priorMethods = emitDepth . blockMethods
local priorPlucks = pluck . loweredPlans
emitDepth . switchTemps = { }
emitDepth . switchValueTemps = { }
emitDepth . blockMethods = { }
pluck . loweredPlans = { }
pluck . constSpecialize . emission = { substitutions = { } , specialization = specialization , }
for definition , value in pairs ( specialization . substitutions ) do
pluck . constSpecialize . emission . substitutions [ definition ] = value
end
local body = declaration . body
e ( ";local function " .. specialization . name .. "(" , sourceLine ( declaration ) )
local wrote = false
for position , param in ipairs ( body . params or { } ) do
if not specialization . omitted [ position ] then
if wrote then
e ( "," )
end
emit ( param )
wrote = true
end
end
e ( ")" )
emitDepth . fn = emitDepth . fn + 1
emitDepth . beginActivation ( )
if coverageOn then
coverageHit ( "function" , body )
end
if body . varargParam then
e ( ("local %s = { n = _G.select(\"#\", ...), ... }") : format ( body . varargParam . name . text ) )
end
if body . body then
emit ( body . body )
end
emitDepth . endActivation ( )
emitDepth . fn = emitDepth . fn - 1
e ( "end" )
pluck . constSpecialize . emission = prior
emitDepth . switchTemps = priorSwitchTemps
emitDepth . switchValueTemps = priorValueTemps
emitDepth . blockMethods = priorMethods
pluck . loweredPlans = priorPlucks
end

pluck . constSpecialize . emitRegistrations = function ( declaration ) 
local specializations = declaration . constSpecializationAliases or declaration . constSpecializations or { }
if # specializations == 0 or declaration . name == nil then
return
end
local registry = nextTemp ( )
local family = nextTemp ( )
e ( ";local " .. registry .. "=_G.rawget(_G,\"__nuppConstSpecializations\")" , sourceLine ( declaration ) )
e ( ";if not " .. registry .. " then " .. registry .. "=_G.setmetatable({},{__mode=\"k\"});" )
e ( "_G.rawset(_G,\"__nuppConstSpecializations\"," .. registry .. ") end" )
e ( ";local " .. family .. "=" .. registry .. "[" .. declaration . name . text .. "]" )
e ( ";if not " .. family .. " then " .. family .. "={};" .. registry .. "[" )
e ( declaration . name . text .. "]=" .. family .. " end" )
for _ , specialization in ipairs ( specializations ) do
local physical = specialization . physical or specialization
e ( ";" .. family .. "[" .. string . format ( "%q" , specialization . key ) .. "]=" .. physical . name )
end
end

emitDepth . switchTemps = setmetatable ( { } , { __mode = "k" } )
emitDepth . switchValueTemps = setmetatable ( { } , { __mode = "k" } )
emitDepth . switchResult = nil
emitDepth . valueBlocks = { }
emitDepth . switchStatementActive = nil
emitDepth . diag = diag







local function switchContains ( node , direct ) 



if not node or cst . isToken ( node ) or node . folded or node . comptimeValue then
return false
end
if node . foldedExpression then
return switchContains ( node . foldedExpression , direct )
end
if node . kind == "switchExpr" or node . kind == "doExpr" or node . kind == "orExitExpr" then
return true
end
if node ~= direct and pluck . needsBindings ( node ) then
return true
end
if node . kind == "funcExpr" or node . kind == "shortfn" or node . kind == "funcbody" then
return false
end
for _ , child in ipairs ( node ) do
if switchContains ( child , direct ) then
return true
end
end

return false
end




emitDepth . switchTest = function ( t , subject , line , recordIdentity , recordIdentitySafe ) 
if t . kind == "tname" and t . base . kind == "nil" then
e ( "(" .. subject .. "==nil)" , line )
elseif t . kind == "tname" and # t == 1 and IS_TYPE [ t . base . text ] then
e ( ("(_G.type(%s)==%q)") : format ( subject , IS_TYPE [ t . base . text ] ) , line )
elseif t . primitiveTest then
e ( ("(_G.type(%s)==%q)") : format ( subject , t . primitiveTest ) , line )
elseif t . kind == "tfunc" then
e ( ("(_G.type(%s)==\"function\")") : format ( subject ) , line )
elseif t . wherePredicate then
e ( "(" .. predicate . test ( t . wherePredicate , subject ) .. ")" , line )
elseif t . recordName and recordIdentity then
e ( ("(%s==%s)") : format ( recordIdentity , t . recordName ) , line )
elseif t . recordName and recordIdentitySafe then
e ( ("(_G.getmetatable(%s).__index==%s)") : format ( subject , t . recordName ) , line )
elseif t . recordName then
e ( ("(_G.getmetatable(%s)?.__index==%s)") : format ( subject , t . recordName ) , line )
elseif t . reified then
needsFfi = true
e ( ("__nuppFfi.istype(%s,%s)") : format ( t . reified , subject ) , line )
else
local at = cst . firstToken ( t )
diag (
at ,
"NUPP3001" ,
"this switch type case has no runtime identity to test" ,
"use a record, struct, primitive, or a refined interface"
)
e ( "true" , line )
end
end









emitDepth . admitCall = function ( x ) 
local args = x . args
local supplied = args and args . exprs and args . exprs [ 1 ] or nil
if not x . admitPredicate then


emit ( supplied )
return
end



local test = predicate . render ( x . admitPredicate , "__nuppV" )
local name = declareHelper (
"__nuppAdmit" ,
"__nuppV" ,
("if %s then return __nuppV end error(%q, 2)")

: format ( test , ("value is not established as %s") : format ( x . admitName or "a constrained type" ) )
)
e ( name .. "(" , sourceLine ( x ) )
emit ( supplied )
e ( ")" )
end

local lowerSwitch
local planSwitchStatement
local activeFlag , ownershipMoveOf





function emitDepth . emitArmResult ( resultName , expr ) 
e ( resultName .. "=" )
emit ( expr )
local move = ownershipMoveOf ( expr )
local flag = move and activeFlag ( move ) or nil
if flag then
e ( ("; %s=false") : format ( flag ) )
end
end

function emitDepth . returnsConstruction ( statement ) 
if # statement . exprs ~= 1 then
return false
end
local expr = statement . exprs [ 1 ]
while expr and ( expr . kind == "paren" or expr . kind == "castExpr" ) do
expr = expr . expr
end

return expr ~= nil and expr . kind == "newExpr"
end

local function switchOperands ( node ) 
local kind = node . kind
if kind == "paren" or kind == "castExpr" or kind == "isExpr" then
return node . expr and { node . expr } or { }
elseif kind == "unop" then
return node . operand and { node . operand } or { }
elseif kind == "newExpr" then
return node . call and { node . call } or { }
elseif kind == "binop" then
return { node . lhs , node . rhs }
elseif kind == "dotIndex" then
return node . obj and { node . obj } or { }
elseif kind == "bracketIndex" then
return { node . obj , node . expr }
elseif kind == "call" or kind == "methodCall" then
local values = { node . obj }
local args = node . args
if args then
for _ , value in ipairs ( args . exprs or { } ) do
if value . kind == "namedArg" or value . kind == "pluckArg" then
values [ # values + 1 ] = value . value
else
values [ # values + 1 ] = value
end
end
if args . table then
values [ # values + 1 ] = args . table
end
end
return values
elseif kind == "tableExpr" then
local values = { }
for _ , field in ipairs ( node . fields or { } ) do
if field . kind == "fieldBracket" then
values [ # values + 1 ] = field . key
end
values [ # values + 1 ] = field . value
end
return values
elseif kind == "istring" then
return node . parts or { }
end

return nil
end

local function captureSwitchPrefix ( node ) 
if not node or emitDepth . switchValueTemps [ node ] then
return
end
local temporary = nextTemp ( )
e ( ("local %s=") : format ( temporary ) , sourceLine ( node ) )
emit ( node )
e ( ";" )
emitDepth . switchValueTemps [ node ] = temporary
end

function emitDepth . blockCallPack ( node ) 
local pack = node . valuePack
if pack and not pack . tail and not pack . alternatives and # pack . head <= 1 then
return nil , nil
end
local packName = pluck . declareHelper ( "__nuppBlockPack" , "..." , "return {n=select(\"#\",...),...}" )
local unpackName = pluck . declareHelper (
"__nuppBlockUnpack" ,
"value" ,
"if value==nil then return nil end;return (unpack or table.unpack)(value,1,value.n)"
)

return packName , unpackName
end

local function lowerSwitches ( node , lazy ) 
if not node
or cst . isToken ( node )
or node . folded
or node . comptimeValue
or emitDepth . switchValueTemps [ node ]
or emitDepth . switchTemps [ node ]
or pluck . loweredPlans [ node ]
then
return
end
if node . foldedExpression then
lowerSwitches ( node . foldedExpression , lazy )
return
end
local kind = node . kind
if kind == "funcExpr" or kind == "shortfn" or kind == "funcbody" then
return
end
if kind == "doExpr" then
emitDepth . lowerDo ( node )
return
elseif kind == "switchExpr" then
lowerSwitch ( node )
return
elseif kind == "orExitExpr" then
emitDepth . lowerOrExit ( node )
return
end
if not switchContains ( node ) then
return
end
if pluck . needsBindings ( node ) then
pluck . lowerCall ( node )
return
elseif kind == "binop"
and node . op
and ( node . op . kind == "and" or node . op . kind == "or" or node . op . kind == "??" )
then
lowerSwitches ( node . lhs )
local result = nextTemp ( )
e ( "local " .. result .. "=" , sourceLine ( node ) )
emit ( node . lhs )
e (
";if " .. (
node . op . kind == "and" and result or node . op . kind == "or" and "not " .. result or result .. "==nil"
) .. " then "
)
lowerSwitches ( node . rhs )
emitDepth . emitArmResult ( result , node . rhs )
e ( ";end;" )
emitDepth . switchValueTemps [ node ] = result
return
elseif kind == "ternary" then
lowerSwitches ( node . cond )
local result = nextTemp ( )
e ( "local " .. result .. ";if " , sourceLine ( node ) )
emit ( node . cond )
e ( " then " )
lowerSwitches ( node . ifTrue )
emitDepth . emitArmResult ( result , node . ifTrue )
e ( ";else " )
lowerSwitches ( node . ifFalse )
emitDepth . emitArmResult ( result , node . ifFalse )
e ( ";end;" )
emitDepth . switchValueTemps [ node ] = result
return
elseif kind == "methodCall" and not node . automaticOwnerMoves and not node . trailingCallableCall then
lowerSwitches ( node . obj )
captureSwitchPrefix ( node . obj )
local receiver = emitDepth . switchValueTemps [ node . obj ]
local method , result = nextTemp ( ) , nextTemp ( )
local safe = node . safeObj or node . safeMethod
if safe then
e ( "local " .. result .. ";" )
end
if node . safeObj then
e ( "if " .. receiver .. "~=nil then " )
end
e ( "local " .. method .. "=" .. receiver .. "." .. ( node . overloadMember or node . name . text ) .. ";" )
if node . safeMethod then
e ( "if " .. method .. "~=nil then " )
end
local values = { }
for _ , arg in ipairs ( node . args and node . args . exprs or { } ) do
values [ # values + 1 ] = ( arg . kind == "namedArg" or arg . kind == "pluckArg" ) and arg . value or arg
end
if node . args and node . args . table then
values [ # values + 1 ] = node . args . table
end
emitDepth . lowerValues ( values )
emitDepth . blockMethods = emitDepth . blockMethods or { }
emitDepth . blockMethods [ node ] = { receiver = receiver , method = method }
if safe then
local packName , unpackName = emitDepth . blockCallPack ( node )
e ( result .. "=" )
if packName then
e ( packName .. "(" )
end
emit ( node )
if packName then
e ( ")" )
end
e ( ";" )
if node . safeMethod then
e ( "end;" )
end
if node . safeObj then
e ( "end;" )
end
emitDepth . switchValueTemps [ node ] = unpackName and unpackName .. "(" .. result .. ")" or result
end
return
elseif kind == "safeCall" or kind == "safeIndex" or kind == "safeBracket" then
lowerSwitches ( node . obj )
captureSwitchPrefix ( node . obj )
local receiver = emitDepth . switchValueTemps [ node . obj ]
local result = nextTemp ( )
e ( "local " .. result .. ";if " .. receiver .. "~=nil then " )
if node . expr then
lowerSwitches ( node . expr )
end
local pending = { }
for _ , arg in ipairs ( node . args and node . args . exprs or { } ) do
local value = ( arg . kind == "namedArg" or arg . kind == "pluckArg" ) and arg . value or arg
if switchContains ( value ) then
for _ , prefix in ipairs ( pending ) do
captureSwitchPrefix ( prefix )
end
pending = { }
lowerSwitches ( value )
pending [ # pending + 1 ] = value
else
pending [ # pending + 1 ] = value
end
end
if node . args and node . args . table then
lowerSwitches ( node . args . table )
end
local packName , unpackName = nil , nil
if kind == "safeCall" then
packName , unpackName = emitDepth . blockCallPack ( node )
end
e ( result .. "=" .. ( packName and packName .. "(" or "" ) .. receiver )
if kind == "safeIndex" then
e ( "." .. node . name . text )
elseif kind == "safeBracket" then
e ( "[" ) ;
emit ( node . expr ) ;
e ( "]" )
else
emit ( node . args )
end
if packName then
e ( ")" )
end
e ( ";end;" )
emitDepth . switchValueTemps [ node ] = unpackName and unpackName .. "(" .. result .. ")" or result
return
end

local operands = switchOperands ( node )
if not operands then
local descended = false
for _ , child in ipairs ( node ) do
if not cst . isToken ( child ) and switchContains ( child ) then
descended = true
if emitDepth . switchStatementRoot and emitDepth . switchStatementRoot [ child . kind ] then
planSwitchStatement ( child )
elseif child . kind == "block"
or child . kind == "ifClause"
or child . kind == "elseifClause"
or child . kind == "elseClause"
or child . kind == "doStmt"
or child . kind == "withStmt"
or child . kind == "pragmaStmt"
then
lowerSwitches ( child , lazy )
else
diag (
cst . firstToken ( child ) ,
"NUPP2142" ,
"a switch in this expression placement is not supported yet" ,
"move the switch to a local before this expression"
)
end
end
end
if not descended and switchContains ( node ) then
diag (
cst . firstToken ( node ) ,
"NUPP2142" ,
"this block or switch expression cannot be lifted from its placement"
)
end
return
end

local pending = { }
for _ , operand in ipairs ( operands ) do
if operand and switchContains ( operand ) then



for _ , prefix in ipairs ( pending ) do
captureSwitchPrefix ( prefix )
end
pending = { }
lowerSwitches ( operand , lazy )
pending [ # pending + 1 ] = operand
elseif operand then
pending [ # pending + 1 ] = operand
end
end
end




function pluck . lowerCall ( call ) 
local plan = pluck . callPlan ( call )
if not plan . calleeAlias and call . kind == "call" and not plan . delegate then
plan . calleeAlias = nextTemp ( )
plan . setupSteps [
# plan . setupSteps + 1
] = { kind = "expr" , name = plan . calleeAlias , expr = call . obj , at = call . obj , }
elseif call . kind == "methodCall" and not plan . methodAlias then
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
end
pluck . emitSteps ( plan . setupSteps , true )
local result = plan . isSafe and nextTemp ( ) or nil
if result then
e ( "local " .. result .. ";" )
end
local guards = 0
if plan . safeReceiver or plan . safeCallee then
e ( "if " .. ( plan . receiverAlias or plan . calleeAlias ) .. "~=nil then " )
guards = guards + 1
end
pluck . emitSteps ( plan . afterReceiverSteps , true )
if plan . safeMethod then
e ( "if " .. plan . methodAlias .. "~=nil then " )
guards = guards + 1
end
pluck . emitSteps ( plan . steps , true )
local prior = pluck . activate ( plan )
local lastLowered = 0
for index , argument in ipairs ( call . args . loweredArgs ) do
if argument . generatedKind == "expr" and not plan . argAliases [ argument ] and switchContains ( argument . expr ) then
lastLowered = index
end
end
for index , argument in ipairs ( call . args . loweredArgs ) do
if index > lastLowered then
do break end
end
if not plan . argAliases [ argument ] then
if argument . generatedKind == "expr" then
lowerSwitches ( argument . expr )
end
if index < lastLowered then
local alias = nextTemp ( )
e ( "local " .. alias .. "=" , sourceLine ( argument . expr or argument . source or call ) )
pluck . emitArgument ( argument , call . args )
e ( ";" )
plan . argAliases [ argument ] = alias
end
end
end
pluck . restore ( plan , prior )
pluck . loweredPlans [ call ] = plan
if result then
local packName , unpackName = emitDepth . blockCallPack ( call )
e ( result .. "=" .. ( packName and packName .. "(" or "" ) )
emit ( call )
e ( ( packName and ")" or "" ) .. ";" )
emitDepth . switchValueTemps [ call ] = unpackName and unpackName .. "(" .. result .. ")" or result
end
for _ = 1 , guards do
e ( "end;" )
end
end

local function renderSwitchScalar ( value ) 
if value . kind == "nil" then
return "nil"
end
return literal . renderData ( value . value )
end

local function switchMap ( node , plan , resultName ) 
local facts = plan . facts
local sentinel = facts . nilResult and declareConstant ( "__nuppSwitchNil" , "{}" ) or nil

local function renderedResult ( value ) 
if value . kind == "nil" then
return sentinel or "nil"
end
return renderSwitchScalar ( value )
end

local entries = { }
local offset = ""
if plan . tag == "DenseIntegerMap" then
local byIndex = { }
for _ , entry in ipairs ( facts . entries ) do
local index = ( entry . key . value - facts . minimum ) + 1
byIndex [ index ] = renderedResult ( entry . value )
end
for index = 1 , facts . span do
entries [ index ] = byIndex [ index ] or "nil"
end
offset = facts . minimum == 0 and "+1"
or ("-(%s)+1") : format ( renderSwitchScalar ( _G.setmetatable({ kind =  "number" ,  value =  facts . minimum }, switchplan.Scalar) ) )
else
for _ , entry in ipairs ( facts . entries ) do
entries [ # entries + 1 ] = "[" .. renderSwitchScalar ( entry . key ) .. "]=" .. renderedResult ( entry . value )
end
end
local map = declareConstant ( "__nuppSwitchMap" , "{" .. table . concat ( entries , "," ) .. "}" )
e ( "local " .. resultName .. "=" .. map .. "[" , sourceLine ( node ) )
if node . selector . kind == "name" then
emit ( node . selector )
else
e ( "(" ) ;
emit ( node . selector ) ;
e ( ")" )
end
e ( offset .. "];" )
local fallback = renderSwitchScalar ( facts . fallback )
if sentinel then
e ( "if " .. resultName .. "==nil then " .. resultName .. "=" .. fallback )
e ( " elseif " .. resultName .. "==" .. sentinel .. " then " .. resultName .. "=nil end;" )
elseif facts . fallback . kind ~= "nil" then
e ( "if " .. resultName .. "==nil then " .. resultName .. "=" .. fallback .. " end;" )
end
end

function emitDepth . switchScalar ( t ) 
if not t then
return false
end
if t . tag == "literal" then
return emitDepth . switchScalar ( t . base )
end
if t . tag == "union" then
for _ , member in ipairs ( t . members ) do
if not emitDepth . switchScalar ( member ) then
return false
end
end
return true
end

return t . tag == "number" or t . tag == "integer" or t . tag == "string" or t . tag == "boolean" or t . tag == "nil"
end

function emitDepth . switchMentions ( node , name ) 
if not node then
return false
end
if cst . isToken ( node ) then
return node . kind == "name" and node . text == name
end
for _ , child in ipairs ( node ) do
if emitDepth . switchMentions ( child , name ) then
return true
end
end

return false
end

function emitDepth . switchLocalSelector ( node ) 
local selector = node . selector
if selector . kind ~= "name"
or not selector . token . definition
or not selector . token . definition . lexical
or not emitDepth . switchScalar ( selector . inferredType )
or emitDepth . captureFrames [ selector . token . definition ]
then
return nil
end
for _ , arm in ipairs ( node . cases or { } ) do
if arm . patternKind ~= "static" then
return nil
end
for _ , value in ipairs ( arm . values or { } ) do
local kind = value . kind
if not value . folded
and kind ~= "number"
and kind ~= "string"
and kind ~= "nilExpr"
and kind ~= "trueExpr"
and kind ~= "falseExpr"
then
return nil
end
end
end

return selector . folded or selector . token . text
end



function emitDepth . implicitGlobal ( name ) 
return (" _G assert collectgarbage coroutine debug dofile error getfenv getmetatable io ipairs load loadfile loadstring math module newproxy next os package pairs pcall print rawequal rawget rawset require select setfenv setmetatable string table tonumber tostring type unpack xpcall ")

: find ( " " .. name .. " " , 1 , true ) ~= nil
end

function emitDepth . switchDestination ( statement ) 
if statement . kind ~= "localStmt"
or statement . isConst
or statement . pattern
or # ( statement . names or { } ) ~= 1
or # ( statement . exprs or { } ) ~= 1
then
return nil
end
local node , name = statement . exprs [ 1 ] , statement . names [ 1 ]
if node . kind ~= "switchExpr" or not emitDepth . switchScalar ( name . inferredType ) then
return nil
end
local dispatch = switchplan . regular ( node , coverageOn )
if dispatch . tag == "OrderedBranches" then
if emitDepth . implicitGlobal ( name . text ) then
return nil
end
for _ , arm in ipairs ( node . cases or { } ) do
if arm . patternKind ~= "static" then
return nil
end
end
end
if dispatch . tag ~= "OrderedBranches" or not emitDepth . switchMentions ( node , name . text ) then
return name . text
end

return nil
end

lowerSwitch = function ( node , destination ) 
if emitDepth . switchTemps [ node ] then
return
end
lowerSwitches ( node . selector )
local line = sourceLine ( node )

local dispatch = switchplan . regular ( node , coverageOn )
node . switchPlanTag = dispatch . tag
node . switchPlanReason = dispatch . reason
local mapped = dispatch . tag == "DenseIntegerMap"
or dispatch . tag == "SparseIntegerMap"
or dispatch . tag == "StringMap"
if mapped then
local resultName = destination or nextTemp ( )
emitDepth . switchTemps [ node ] = resultName
switchMap ( node , dispatch , resultName )
return
end

local selectorName = emitDepth . switchLocalSelector ( node )
if not selectorName then
selectorName = nextTemp ( )
e ( ("local %s=") : format ( selectorName ) , line )
emit ( node . selector )
e ( ";" )
end
local resultName = destination or nextTemp ( )
emitDepth . switchTemps [ node ] = resultName
e ( ("local %s;") : format ( resultName ) , line )




local recordRun = 0
for _ , arm in ipairs ( node . cases or { } ) do
if arm . patternKind == "type" and arm . type and arm . type . recordName and arm . switchRecordIdentitySafe then
recordRun = recordRun + 1
else
do break end
end
end
local recordIdentity
if recordRun >= 2 then
recordIdentity = nextTemp ( )
e ( ("local %s=getmetatable(%s).__index;") : format ( recordIdentity , selectorName ) , line )
end






local guarded = false
for _ , arm in ipairs ( node . cases or { } ) do
if arm . guard then
guarded = true
do break end
end
end
local doneLabel
if guarded then
doneLabel = ("__nuppS%d") : format ( tempCounter + 1 )
tempCounter = tempCounter + 1
usedNames [ doneLabel ] = true
end

local first = true
for armIndex , arm in ipairs ( node . cases or { } ) do
if guarded then
e ( "if " , sourceLine ( arm ) )
else
e ( first and "if " or "elseif " , sourceLine ( arm ) )
end
first = false
if coverageOn then
local branch = coverageSite ( "branch" , arm )
e ( ("%s.branch(%q,%d,") : format ( coverageRuntime ( ) , coveragePath , branch ) , sourceLine ( arm ) )
end
if arm . patternKind == "static" then
for index , value in ipairs ( arm . values or { } ) do
if index > 1 then
e ( " or " )
end
e ( selectorName .. "==" )
emit ( value )
end
else
emitDepth . switchTest (
arm . type ,
selectorName ,
sourceLine ( arm ) ,
armIndex <= recordRun and recordIdentity or nil ,
arm . switchRecordIdentitySafe
)
end
if coverageOn then
e ( ")" )
end
e ( " then " )
coverageHit ( "statement" , arm )
if arm . binding then
e ( ("local %s=%s;") : format ( arm . binding . text , selectorName ) )
end
for _ , field in ipairs ( arm . fields or { } ) do
local name = field . name and field . name . text or ""
local binding = field . alias and field . alias . text or name
e ( ("local %s=%s.%s;") : format ( binding , selectorName , name ) )
end

if arm . guard and arm . guard . expr then
e ( "if " , sourceLine ( arm . guard ) )
lowerSwitches ( arm . guard . expr )
emit ( arm . guard . expr )
e ( " then " )
end
if arm . expr then
lowerSwitches ( arm . expr )
emitDepth . emitArmResult ( resultName , arm . expr )
elseif arm . body then
local prior = emitDepth . switchResult
emitDepth . switchResult = resultName
emit ( arm . body )
emitDepth . switchResult = prior
end
if guarded then
e ( ("goto %s;") : format ( doneLabel ) )
if arm . guard then
e ( "end;" )
end
e ( "end;" )
end
end
if node . elseCase then
if guarded then
e ( "do " , sourceLine ( node . elseCase ) )
else
e ( first and "if true then " or "else " , sourceLine ( node . elseCase ) )
end
first = false
local arm = node . elseCase
coverageHit ( "statement" , arm )
if arm . expr then
lowerSwitches ( arm . expr )
emitDepth . emitArmResult ( resultName , arm . expr )
elseif arm . body then
local prior = emitDepth . switchResult
emitDepth . switchResult = resultName
emit ( arm . body )
emitDepth . switchResult = prior
end
end
if guarded then
if node . elseCase then
e ( "end;" , node . endTok and node . endTok . line or nil )
end
e ( ("::%s::;") : format ( doneLabel ) , node . endTok and node . endTok . line or nil )
elseif not first then
e ( "end;" , node . endTok and node . endTok . line or nil )
end
end





emitDepth . lowerSwitch = lowerSwitch

local function preserveAssignmentTarget ( target ) 
if not target then
return
end
if target . kind == "dotIndex" then
captureSwitchPrefix ( target . obj )
elseif target . kind == "bracketIndex" then
captureSwitchPrefix ( target . obj )
captureSwitchPrefix ( target . expr )
end
end

planSwitchStatement = function ( stat ) 
if stat . kind == "callStmt" then
lowerSwitches ( stat . expr )
return
end
local exprs = stat . exprs
or ( stat . kind == "compoundAssign" and { stat . value } )
or ( stat . kind == "exportStmt" and { stat . value } )
or { }
if stat . kind == "assignStmt" or stat . kind == "compoundAssign" then
for _ , target in ipairs ( stat . targets or { stat . target } ) do
lowerSwitches ( target )
preserveAssignmentTarget ( target )
end
if stat . kind == "compoundAssign" then
captureSwitchPrefix ( stat . target )
end
end
local pending = { }
for _ , expr in ipairs ( exprs ) do
if switchContains ( expr ) then
for _ , prefix in ipairs ( pending ) do
captureSwitchPrefix ( prefix )
end
pending = { }
lowerSwitches ( expr )
pending [ # pending + 1 ] = expr
else
pending [ # pending + 1 ] = expr
end
end
end

local SWITCH_STATEMENT_ROOT = {
localStmt = true ,
assignStmt = true ,
returnStmt = true ,
callStmt = true ,
exportStmt = true
}
emitDepth . switchStatementRoot = SWITCH_STATEMENT_ROOT
emitDepth . switchContains = switchContains
emitDepth . capturePrefix = captureSwitchPrefix
emitDepth . lowerSwitches = lowerSwitches
emitDepth . planSwitchStatement = planSwitchStatement

function emitDepth . hasBlockCondition ( node ) 
for _ , clause in ipairs ( node . clauses or { } ) do
if switchContains ( clause . cond ) then
return true
end
end

return false
end

function emitDepth . lowerValues ( values ) 
local pending = { }
for _ , value in ipairs ( values ) do
if switchContains ( value ) then
for _ , prefix in ipairs ( pending ) do
captureSwitchPrefix ( prefix )
end
pending = { }
lowerSwitches ( value )
pending [ # pending + 1 ] = value
else
pending [ # pending + 1 ] = value
end
end
end

function emitDepth . valueFrame ( ) 
local frame = emitDepth . valueBlocks [ # emitDepth . valueBlocks ]
return frame and frame . functionDepth == emitDepth . fn and frame or nil
end



function emitDepth . valueExit ( frame , value , rendered ) 
local region = pluck . currentRegion ( )
if region and # cleanupStack > frame . cleanupDepth then
local tag = "yield:" .. frame . result
region . valueExits = region . valueExits or { }
region . valueExits [ tag ] = frame
local temporary = nextTemp ( )
e ( "do local " .. temporary .. "=" )
if rendered then
e ( rendered )
else
emit ( value )
end
local move = value and ownershipMoveOf ( value )
local flag = move and activeFlag ( move )
if flag then
e ( ";" .. flag .. "=false" )
end
e ( (";return %q,%s end") : format ( tag , temporary ) )
else
e ( "do " )
if rendered then
e ( frame . result .. "=" .. rendered )
else
emitDepth . emitArmResult ( frame . result , value )
end
e ( ";" .. frame . done .. "=true;break end" )
end
end




function emitDepth . beginCondition ( header ) 
if header then
header . savedLoop = emitDepth . loop
header . parent = emitDepth . conditionHeader
emitDepth . conditionHeader = header
emitDepth . loop = header . loopDepth
end
end

function emitDepth . endCondition ( header ) 
if header then
emitDepth . loop = header . savedLoop
emitDepth . conditionHeader = header . parent
end
end

function emitDepth . conditionControl ( header , kind , line ) 
header . controls [ kind ] = true
local region = pluck . currentRegion ( )
if region and # cleanupStack > header . cleanupDepth then
local tag = "condition:" .. header . action .. ":" .. kind
region . conditionExits = region . conditionExits or { }
region . conditionExits [ tag ] = { header = header , kind = kind }
e ( ("do return %q end") : format ( tag ) , line )
else
e ( ("do %s=%q;break end") : format ( header . action , kind ) , line )
end
end

function emitDepth . valueControl ( kind , line ) 
local frame = emitDepth . valueFrame ( )
local region = pluck . currentRegion ( )
local header = emitDepth . conditionHeader
if header
and header . functionDepth == emitDepth . fn
and # emitDepth . valueBlocks <= header . frames
and emitDepth . loop <= header . loopDepth
then
emitDepth . conditionControl ( header , kind , line )
elseif frame and emitDepth . loop <= frame . loopDepth and ( not region or # cleanupStack <= frame . cleanupDepth ) then
frame . controls [ kind ] = true
e ( ("do %s=%q;break end") : format ( frame . action , kind ) , line )
elseif region and emitDepth . loop <= region . entryLoopDepth then
region [ kind .. "Exit" ] = true
e ( ("do return %q end") : format ( kind ) , line )
else
local loop = emitDepth . loopWrappers [ # emitDepth . loopWrappers ]
if loop and loop . action then
e ( "do " , line )
pluck . loopExit ( loop , kind )
e ( " end" )
else
e ( "do " .. kind .. " end" , line )
end
end
end







function emitDepth . orExitReturn ( node , temps ) 
local line = sourceLine ( node ) or 0
local first = cst . firstToken ( node )
local token = {
kind = "return" ,
text = "return" ,
trivia = { } ,
triviaFirst = 1 ,
triviaCount = 0 ,
offset = first and first . offset or 0 ,
line = line ,
col = first and first . col or 1 ,
}
local stat = { token , kind = "returnStmt" , exprs = { } }
for index , temp in ipairs ( temps ) do
local value = { kind = "assignmentTemporary" , name = temp , line = line }
stat . exprs [ index ] = value
if index > 1 then
stat [ # stat + 1 ] = { kind = "assignmentTemporary" , name = "," , line = line }
end
stat [ # stat + 1 ] = value
end

return stat
end









function emitDepth . lowerOrExit ( node ) 
local operand = node . operand
local line = sourceLine ( node )
lowerSwitches ( operand )
local width = node . exitKind == "return" and math . max ( node . orExitWidth or 1 , 1 ) or 1
local temps = { }
for index = 1 , width do
temps [ index ] = nextTemp ( )
end
e ( "local " .. table . concat ( temps , "," ) .. "=" , line )
emit ( operand )
e ( ";if " )
local branch = coverageOn and coverageSite ( "branch" , node ) or nil
if branch then
e ( ("%s.branch(%q,%d,") : format ( coverageRuntime ( ) , coveragePath , branch ) )
end
e ( "not " .. temps [ 1 ] )
if branch then
e ( ")" )
end
e ( " then " )
if node . exitKind == "return" then
emit ( emitDepth . orExitReturn ( node , temps ) )
else
emitDepth . valueControl ( node . exitKind , line )
end
e ( " end;" )
emitDepth . switchTemps [ node ] = temps [ 1 ]
end

function emitDepth . lowerDo ( node ) 
local result , done , action = nextTemp ( ) , nextTemp ( ) , nextTemp ( )
emitDepth . switchTemps [ node ] = result
local frame = {
result = result ,
done = done ,
action = action ,
controls = { } ,
functionDepth = emitDepth . fn ,
loopDepth = emitDepth . loop ,
cleanupDepth = # cleanupStack
}
e ( "local " .. result .. ";do local " .. done .. "," .. action .. ";repeat " , sourceLine ( node ) )
emitDepth . valueBlocks [ # emitDepth . valueBlocks + 1 ] = frame
emit ( node . body )
emitDepth . valueBlocks [ # emitDepth . valueBlocks ] = nil
e ( " until true;" , node . endTok and node . endTok . line )
for _ , kind in ipairs ( { "break" , "continue" } ) do
if frame . controls [ kind ] then
e ( ("if %s==%q then ") : format ( action , kind ) )
emitDepth . valueControl ( kind )
e ( " end;" )
end
end
e ( "end;" )
end

function emitDepth . propagateValueLoop ( ) 
local frame = emitDepth . valueFrame ( )
if frame and # cleanupStack == frame . cleanupDepth then
e ( " if " .. frame . done .. " then break end;" )
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
] = ("%s.%s = %s.%s")

: format ( runtimeName , one . member or one . name , one . from , one . fromMember or one . member or one . name )
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









function pluck . loopNeedsWrapper ( loop ) 
return loop . kind == "repeatStmt" and cst . repeatContinue ( loop ) ~= nil and cst . skippedUntilLocal ( loop ) == nil
end







function pluck . loopUntilTest ( loopWrapper ) 
if not loopWrapper . untilTest then
local savedOut , savedLine , savedLineStart = out , curLine , atLineStart
out , curLine , atLineStart = { } , 2147483647 , true
emitDepth . beginCondition ( loopWrapper . blockCondition )
lowerSwitches ( loopWrapper . untilCond )
e ( loopWrapper . untilFlag .. "=" )
emit ( loopWrapper . untilCond )
e ( ";" )
emitDepth . endCondition ( loopWrapper . blockCondition )
loopWrapper . untilTest = table . concat ( out )
out , curLine , atLineStart = savedOut , savedLine , savedLineStart
end

return loopWrapper . untilTest
end



function pluck . loopExit ( loopWrapper , completion , line ) 
if completion == "continue" and loopWrapper . untilFlag then
e ( pluck . loopUntilTest ( loopWrapper ) , line )
line = nil
end
e ( ("%s=%q;break") : format ( loopWrapper . action , completion ) , line )
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






local definitionLoops = setmetatable ( { } , { __mode = "k" } )
emitDepth . bindingWrites = { }

local function planDefinitionLoops ( ) 
local function walk ( node , loops ) 
if not node then
return
end
if cst . isToken ( node ) then
local definition = node . definition
if definition and definition . token == node then
local copy = { }
for index , loop in ipairs ( loops ) do
copy [ index ] = loop
end
definitionLoops [ definition ] = copy
for _ , write in ipairs ( rawget ( node , "writes" ) or { } ) do
if write . path == node . text then
emitDepth . bindingWrites [ write . offset ] = definition
end
end
end
return
end
local kind = node . kind
if kind == "funcbody" or kind == "shortfn" then
local inner = { }
for _ , child in ipairs ( node ) do
walk ( child , inner )
end
return
end
local isLoop = kind == "whileStmt" or kind == "fornumStmt" or kind == "forinStmt" or kind == "repeatStmt"
if isLoop then
loops [ # loops + 1 ] = node
end
for _ , child in ipairs ( node ) do
walk ( child , loops )
end
if isLoop then
loops [ # loops ] = nil
end
end

for _ , node in ipairs ( result . root or { } ) do
walk ( node , { } )
end
end

planDefinitionLoops ( )



function pluck . hoistDeclaration ( node ) 
if emitDepth . fn ~= 0 or not node . body or not node . body . body or node . body . body . automaticDirect then
return nil
end
local ownerCount = 0
for _ , stat in ipairs ( node . body . body . stats or { } ) do
ownerCount = ownerCount + # ( stat . automaticOwners or { } )
end
if ownerCount < 2 then
return nil
end
if not emitDepth . hoistDeclarations then
local declarations = { }

local function collect ( stat ) 
if not stat or cst . isToken ( stat ) then
return
end
if stat . kind == "block" then
for _ , child in ipairs ( stat . stats or stat ) do
collect ( child )
end
elseif stat . kind == "pragmaStmt" or stat . kind == "exportStmt" then
collect ( stat . stat )
elseif stat . kind == "localFuncStmt" or stat . kind == "funcStmt" then
declarations [ stat ] = true
end
end

for _ , child in ipairs ( result . root ) do
collect ( child )
end
emitDepth . hoistDeclarations = declarations
end
if emitDepth . hoistDeclarations [ node ] then
return { body = node . body . body , endTok = cst . lastToken ( node . body ) }
end

return nil
end




function pluck . functionAssignment ( node ) 
local name = node and node . kind == "funcStmt" and node . name or nil
if name and name . base and # name == 1 and not name . method then
return emitDepth . bindingWrites [ name . base . offset ]
end

return nil
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
local captured = { }







local implicitReceiver

local function walk ( node ) 
if not node or cst . isToken ( node ) then
return
end



if node . kind == "name" and node . token and not node . folded or pluck . functionAssignment ( node ) then
local definition = pluck . functionAssignment ( node ) or node . token . definition
if definition then
local token = definition . token
if not localBindings [ definition ]
and token
and firstOffset
and token . offset < firstOffset
and token . line ~= 0
and not isChunkLocal ( definition )
then
captured [ definition ] = true
end
elseif node . token . text == "self" then
implicitReceiver = implicitReceiver or { name = "self" , kind = "parameter" }
captured [ implicitReceiver ] = true
end
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

walk ( block )

local definitions = { }
for definition in pairs ( captured ) do
definitions [ # definitions + 1 ] = definition
end
table . sort ( definitions , function ( left , right ) 
local leftToken , rightToken = left . token , right . token
local leftOffset = leftToken and leftToken . offset or 0
local rightOffset = rightToken and rightToken . offset or 0
if leftOffset == rightOffset then
return tostring (
left . name or leftToken and leftToken . text
) < tostring ( right . name or rightToken and rightToken . text )
end

return leftOffset < rightOffset
end )

return definitions
end

local function activationStable ( captures ) 
local active = { }
for _ , loop in ipairs ( emitDepth . loopNodes ) do
active [ loop ] = true
end
for _ , definition in ipairs ( captures or { } ) do
for _ , loop in ipairs ( definitionLoops [ definition ] or { } ) do
if active [ loop ] then
return false
end
end
end

return true
end

emitDepth . activationStable = activationStable


emitDepth . simdFamilyOf = simdFamilyOf
emitDepth . storageVectorField = storageVectorField
emitDepth . nativeOnlyStruct = nativeOnlyStruct

local function captureUsage ( block , captures ) 
local wanted , written , nested = { } , { } , { }
for _ , definition in ipairs ( captures or { } ) do
wanted [ definition ] = true
end

local function markName ( node , into ) 
local definition = node and node . kind == "name" and node . token and node . token . definition or nil
if definition and ( captures == nil or wanted [ definition ] ) then
into [ definition ] = true
end
end

local function walk ( node , functionDepth ) 
if not node or cst . isToken ( node ) then
return
end
local kind = node . kind
local childFunctionDepth = functionDepth
if kind == "funcbody" or kind == "shortfn" then
childFunctionDepth = functionDepth + 1
end
if childFunctionDepth > 0 then
markName ( node , nested )
end
if kind == "assignStmt" then
for _ , target in ipairs ( node . targets or { } ) do
markName ( target , written )
end
elseif kind == "compoundAssign" then
markName ( node . target , written )
else
local definition = pluck . functionAssignment ( node )
if definition and ( captures == nil or wanted [ definition ] ) then
written [ definition ] = true


nested [ definition ] = true
end
end
for _ , child in ipairs ( node ) do
walk ( child , childFunctionDepth )
end
end

walk ( block , 0 )

return written , nested
end

local function frameEligible ( captures , nested ) 
for _ , definition in ipairs ( captures or { } ) do
local t = definition . type



if not definition . token
or nested [ definition ]
or definition . virtualIndexedView
or t and ( t . tag == "affine" or t . tag == "borrowed" or t . tag == "pinned" or t . tag == "func" )
then
return false
end
end

return true
end

local function pushCaptureFrame ( captures , frameName ) 
local restore = { }
for index , definition in ipairs ( captures or { } ) do
restore [ definition ] = emitDepth . captureFrames [ definition ] or false
emitDepth . captureFrames [ definition ] = ("%s[%d]") : format ( frameName , index )
end
emitDepth . captureFrameStack [ # emitDepth . captureFrameStack + 1 ] = restore
end

local function popCaptureFrame ( ) 
local restore = emitDepth . captureFrameStack [ # emitDepth . captureFrameStack ]
if not restore then
return
end
for definition , prior in pairs ( restore ) do
emitDepth . captureFrames [ definition ] = prior or nil
end
emitDepth . captureFrameStack [ # emitDepth . captureFrameStack ] = nil
end

emitDepth . captureUsage = captureUsage
emitDepth . captureWrites = captureUsage ( result . root , nil )
emitDepth . frameEligible = frameEligible
emitDepth . pushCaptureFrame = pushCaptureFrame
emitDepth . popCaptureFrame = popCaptureFrame






emitAutomaticBlock = function ( block ) 
local stats = block . stats or { }
local loop = emitDepth . loopNodes [ # emitDepth . loopNodes ]
local repeatCondition = loop
and loop . kind == "repeatStmt"
and loop . body == block
and loop . cleanupConditionTemp
and loop . cond
or nil
local function emitRepeatCondition ( ) 
if repeatCondition then
emitDepth . beginCondition ( loop . blockCondition )
emitDepth . lowerSwitches ( repeatCondition )
e ( ("%s=") : format ( loop . cleanupConditionTemp ) , sourceLine ( repeatCondition ) )
emit ( repeatCondition )
emitDepth . endCondition ( loop . blockCondition )
e ( ";" )
end
end

if block . automaticDirect and not ( repeatCondition and emitDepth . switchContains ( repeatCondition ) ) then
for _ , stat in ipairs ( stats ) do
emit ( stat )
end
emitRepeatCondition ( )
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
do break end
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
local bindings = { }
local sequence



= { }
local bodyStats = { }
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
if ( stat . kind == "localStmt" or stat . kind == "localFuncStmt" and stat . affineInitializer )
and ownerCount > 0
then
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
automaticBlock = block ,
automaticSequence = sequence ,
repeatCondition = repeatCondition ,
repeatConditionTemp = loop and loop . cleanupConditionTemp or nil ,
repeatConditionHeader = loop and loop . blockCondition or nil ,
}
if repeatCondition then
region . analysisBody = { kind = "block" , body , repeatCondition }
end
region . automaticComplex = # bindings == 1 and sequence [ 1 ] and sequence [ 1 ] . declaration ~= nil
region . enclosingCaptures = automaticCaptures ( region . analysisBody or body , bindings )
region . capturesEnclosing = # region . enclosingCaptures > 0
emit ( region )
end



function pluck . currentRegion ( ) 
local ctx = cleanupStack [ # cleanupStack ]
if ctx and ctx . functionDepth == emitDepth . fn then
return ctx
end

return nil
end




function pluck . statementOwnerState ( owner ) 
for index = # cleanupStack , 1 , -1 do
local ctx = cleanupStack [ index ]
if ctx . functionDepth == emitDepth . fn and ctx . statementOwnerMap then
local found = ctx . statementOwnerMap [ owner ]
if found then
return found
end
end
end

return nil
end

function pluck . statementOwnerCapture ( ) 
return declareHelper (
"__nuppStatementOwner" ,
"__nuppState,__nuppIndex,..." ,
"local __nuppValue=...;__nuppState[__nuppIndex]=__nuppValue;__nuppState[-__nuppIndex]=true;return ..."
)
end




local function plainDeclaration ( stat ) 
if stat . kind ~= "localStmt" or stat . pattern or stat . concatBuffer or # ( stat . exprs or { } ) == 0 then
return false
end
for _ , name in ipairs ( stat . names or { } ) do
if name . definition and name . definition . virtualIndexedView then
return false
end
end
for _ , expression in ipairs ( stat . exprs ) do
if expression . virtualIndexedView then
return false
end
end

return true
end

function pluck . emitStatementCleanup ( stat ) 





if plainDeclaration ( stat ) then
e ( "local " , sourceLine ( stat ) )
local assignment = {
kind = "assignStmt" ,
targets = { } ,
exprs = stat . exprs ,
statementCleanupOwners = stat . statementCleanupOwners ,
}
for index , name in ipairs ( stat . names ) do
if index > 1 then
e ( "," )
assignment [ # assignment + 1 ] = { kind = "assignmentTemporary" , name = "," }
end
emit ( name )
local target = { name , kind = "name" , token = name }
assignment . targets [ index ] = target
assignment [ # assignment + 1 ] = target
end
e ( ";" )
assignment [ # assignment + 1 ] = { kind = "assignmentTemporary" , name = "=" }
for index , expression in ipairs ( stat . exprs ) do
if index > 1 then
assignment [ # assignment + 1 ] = { kind = "assignmentTemporary" , name = "," }
end
assignment [ # assignment + 1 ] = expression
end
pluck . emitStatementRegion ( assignment , cst . firstToken ( stat . exprs [ 1 ] ) )
return
end
pluck . emitStatementRegion ( stat , nil )
end




function pluck . emitStatementRegion ( stat , from ) 
local first = cst . firstToken ( stat )
local last = cst . lastToken ( stat )
local start = from or first
local stateName = nextTemp ( )
local definition = { }
local binding = {
kind = "cleanupBinding" ,
name = {
kind = "name" ,
text = stateName ,
line = first and first . line or sourceLine ( stat ) ,
offset = start and start . offset or 0 ,
definition = definition ,
} ,
expr = { kind = "statementCleanupStateExpr" , line = first and first . line or sourceLine ( stat ) } ,
ownerCleanups = { } ,
statementOwners = stat . statementCleanupOwners ,
}
local body = { kind = "block" , stats = { stat } }
body [ 1 ] = stat
local region = {
kind = "cleanupRegion" ,
startTok = first ,
doTok = first ,
endTok = last ,
bindings = { binding } ,
body = body ,
statementCleanup = true ,
}
region . enclosingCaptures = automaticCaptures ( body , region . bindings )
region . capturesEnclosing = # region . enclosingCaptures > 0
stat . statementCleanupActive = true
emit ( region )
stat . statementCleanupActive = nil
end





activeFlag = function ( move ) 
local owner = move . owner or move
for index = # cleanupStack , 1 , -1 do
local ctx = cleanupStack [ index ]
if ctx . functionDepth == emitDepth . fn then
local state = ctx . automaticMap and ctx . automaticMap [ owner ]
if state then
if move . field and state . fields then
return state . fields [ move . field ]
end
return state . whole
end
end
end

return nil
end

ownershipMoveOf = function ( expr ) 
while expr and ( expr . kind == "paren" or expr . kind == "castExpr" or expr . kind == "orExitExpr" ) do
expr = expr . kind == "orExitExpr" and expr . operand or expr . expr
end
return expr and expr . automaticOwnerMove or nil
end

local function automaticSlot ( move ) 
local owner = move and ( move . owner or move ) or nil
if not owner then
return nil
end
for index = # cleanupStack , 1 , -1 do
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
("(function(%s) local %s=true; ") : format ( table . concat ( names , "," ) , active ) ,
line ,
pluck . reasons . capture
)
for _ , capture in ipairs ( captures ) do





local outerActive = capture . move and activeFlag ( capture . move ) or nil
if not outerActive and capture . outer and capture . outer . automaticOwner then
outerActive = activeFlag ( capture . outer . automaticOwner )
end
if not outerActive then
for index = # cleanupStack , 1 , -1 do
local ctx = cleanupStack [ index ]
for _ , state in pairs ( ctx . automaticMap or { } ) do
if state . definition == ( capture . token and capture . token . definition )
or state . definition == ( capture . outer and capture . outer . definition )
then
outerActive = state . whole
do break end
end
end
if outerActive then
do break end
end
end
end
if outerActive then
e ( ("%s=false; ") : format ( outerActive ) )
end
end
e ( ("local %s=function") : format ( callable ) )
local enclosingCleanupStack = cleanupStack
cleanupStack = { }
emit ( body )
cleanupStack = enclosingCleanupStack
e ( ("; local %s={}; ") : format ( wrapper ) )
e ( ("%s.__nuppRelease=function() if not %s then return end; %s=false; ") : format ( wrapper , active , active ) )
local errors = nextTemp ( )
local errorCount = nextTemp ( )
e ( ("local %s={}; local %s=0; ") : format ( errors , errorCount ) )
for captureIndex = # captures , 1 , -1 do
local capture = captures [ captureIndex ]
for _ , cleanup in ipairs ( capture . type . cleanups or { } ) do
local call = protectedCleanupCall ( cleanup , capture . name , cleanupGlobals . pcall )
if call then
local ok , reason = nextTemp ( ) , nextTemp ( )
e (
("local %s,%s=%s; if not %s then %s=%s+1; %s[%s]=%s end; ")

: format ( ok , reason , call , ok , errorCount , errorCount , errors , errorCount , reason )
)
end
end
end
e (
("if %s>0 then if %s>1 then %s(%s(%s[1],%s,2),0) else %s(%s[1],0) end end end; ")

: format (
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
("return _G.setmetatable(%s,{__call=function(_,...) if not %s then %s(%q,2) end; ")

: format ( wrapper , active , cleanupGlobals . error , "nupp: affine closure was already called or dropped" )
)
e ( ("%s=false; return %s(...) end}) end)(") : format ( active , callable ) )
for j , capture in ipairs ( captures ) do
if j > 1 then
e ( "," )
end
e ( capture . name , capture . token and capture . token . line or line )
end
e ( ")" )
end





local function emitPackedReturn ( ctx , x ) 
if x . constructorReturn then
e (
("do return \"return\",%s(%s) end") : format ( cleanupPackName , emitDepth . constructorReturnName ) ,
sourceLine ( x )
)
return
end
local actives = { }
local seen = { }
for _ , expr in ipairs ( x . exprs or { } ) do
local move = ownershipMoveOf ( expr )
local active = move and activeFlag ( move ) or nil
if active and not seen [ active ] then
seen [ active ] = true
actives [ # actives + 1 ] = active
end
end
local packed = # actives > 0 and nextTemp ( ) or nil
if packed then
e ( ("do local %s=%s(") : format ( packed , cleanupPackName ) , sourceLine ( x ) )
else
e ( ("return \"return\",%s(") : format ( cleanupPackName ) , sourceLine ( x ) )
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
e ( ("; %s=false") : format ( active ) )
end
e ( ("; return \"return\",%s end") : format ( packed ) )
end
end




function pluck . multiIndexedAssignment ( statement ) 
local targets , expressions = statement . targets or { } , statement . exprs or { }
if # targets == 1 and # expressions == 1 then
return false
end
local needed = false
for _ , target in ipairs ( targets ) do
if target . indexedAccess or target . indexedField or target . soaRow or target . soaField then
needed = true
end
end
if not needed then
return false
end

local function temporary ( origin , name ) 
return { cst . firstToken ( origin ) , kind = "assignmentTemporary" , name = name }
end

local function replace ( node , before , after ) 
local copy = { }
for key , value in pairs ( node ) do
copy [ key ] = value == before and after or value
end

return copy
end

local function capture ( expression ) 
local name = nextTemp ( )
e ( "local " .. name .. "=" )
emit ( expression )
e ( ";" )

return temporary ( expression , name )
end

local frozen = { }
local values = { }
e ( "do " , sourceLine ( statement ) )
for index , target in ipairs ( targets ) do
local row = soaFieldTarget ( target )
if target . kind == "dotIndex" and target . indexedField and target . indexedField . adapter == "span" then
local access , name = target . obj , nextTemp ( )
local virtual = emitDepth . view . info ( access . obj )
local object = virtual and access . obj or capture ( access . obj )
local key = capture ( access . expr )
e ( "local " .. name .. "=" )
if virtual then
emitDepth . view . spanSlot ( object , key , nil , not access . indexedDirectAccess )
elseif access . indexedDirectAccess then
emit ( object ) ;
e ( ".pointer[" ) ;
emit ( object ) ;
e ( ".offset+" ) ;
emit ( key ) ;
e ( "-1]" )
else
emit ( object ) ;
e ( ":getMut(" ) ;
emit ( key ) ;
e ( ")" )
end
e ( ";" )
target = replace ( target , access , temporary ( access , name ) )
target . indexedField = nil
elseif row then
local object = emitDepth . view . info ( row . obj ) and row . obj or capture ( row . obj )
local key = capture ( row . expr )
local copied = replace ( replace ( row , row . obj , object ) , row . expr , key )
target = replace ( target , row , copied )
elseif target . obj then
local object = emitDepth . view . info ( target . obj ) and target . obj or capture ( target . obj )
target = replace ( target , target . obj , object )
if target . expr then
local key
if target . kind == "safeBracket" then
local name = nextTemp ( )
e ( "local " .. name .. ";if " ) ;
emit ( object ) ;
e ( "~=nil then " .. name .. "=" )
emit ( target . expr ) ;
e ( " end;" )
key = temporary ( target . expr , name )
else
key = capture ( target . expr )
end
target = replace ( target , target . expr , key )
end
end
frozen [ index ] = target
values [ index ] = temporary ( statement , nextTemp ( ) )
end
e ( "local " )
for index , value in ipairs ( values ) do
if index > 1 then
e ( "," )
end
emit ( value )
end
e ( "=" )
for index , expression in ipairs ( expressions ) do
if index > 1 then
e ( "," )
end
emit ( expression )
end
for index = # frozen , 1 , -1 do
e ( ";" )
local target , value = frozen [ index ] , values [ index ]
emit ( {
target ,
{ kind = "assignmentTemporary" , name = "=" } ,
value ,
kind = "assignStmt" ,
targets = { target } ,
exprs = { value }
} )
end
e ( " end" )

return true
end





for _ , item in ipairs ( pluck . witnessPlan . ordered ) do
if not item . group . name then
item . group . name = nextTemp ( )
end
end

function pluck . emitWitnessTargets ( node , runtimeName ) 
local item = pluck . witnessPlan . declarations [ node ]
if not item then
return
end
pluck . needRuntimeEffect ( "stdlib.typewitness" )
e ( (";_G.nupp.__reflect.link(%s,%s[%d],{") : format ( runtimeName , item . group . name , item . slot ) )
for index , target in ipairs ( item . targets ) do
if index > 1 then
e ( "," )
end
if target . localTarget then
local child = target . localTarget
e ( ("%s[%d]") : format ( child . group . name , child . slot ) )
else
e ( ("_G.nupp.__reflect.reference(%q,%q)") : format ( target . key , target . module ) )
end
end
e ( "})" )
end

emit = function ( x ) 
if cst . isToken ( x ) then
if x . missing or x . kind == "eof" then
return
end


if x . typeColon or x . typeSeparator or x . typeBracket or x . generic then
return
end
local text = x . text
if x . kind == "string" and text : sub ( 1 , 1 ) == "`" then

text = pluck . quote ( text : sub ( 2 , -2 ) )
end
e ( text , x . line )
return
end

local kind = x . kind
local witnessGroup = pluck . witnessPlan . blocks [ x ]
if witnessGroup and not witnessGroup . active then
witnessGroup . active = true
pluck . needRuntimeEffect ( "stdlib.typewitness" )
e ( "local " .. witnessGroup . name .. "={" , sourceLine ( x ) )
for index , item in ipairs ( witnessGroup . items ) do
if index > 1 then
e ( "," )
end
local declarationKey = item . type . runtimeDeclarationKey or item . type . declarationKey
if item . top and declarationKey then
e ( ("_G.nupp.__reflect.declaration(%q)") : format ( declarationKey ) )
else
e ( ("{key=%q}") : format ( declarationKey ) )
end
end
e ( "};" )
emit ( x )
witnessGroup . active = false
return
end
local witnessed = pluck . witnessPlan . values [ x ]
if witnessed then
pluck . needRuntimeEffect ( "stdlib.typewitness" )
local data = pluck . witnessDescriptions [ witnessed ]
if not data then
local description = require (
"nupp.compiler.reflection"
) . describe ( witnessed , witnessed . runtimePath or witnessed . name )
data = pluck . renderData (
description
) .. "," .. pluck . renderData ( require ( "nupp.compiler.reflection" ) . runtimeReferences ( witnessed ) )
pluck . witnessDescriptions [ witnessed ] = data
end
pluck . witnessPlan . values [ x ] = nil



if kind == "name" then
e ( "(_G.nupp.__reflect.known(" , sourceLine ( x ) )
emit ( x )
e ( ") and " )
emit ( x )
e ( " or " )
end
e ( "_G.nupp.__reflect.ensure(" , sourceLine ( x ) )
emit ( x )
e ( ",function() return " .. data .. " end)" )
if kind == "name" then
e ( ")" )
end
pluck . witnessPlan . values [ x ] = witnessed
return
end
if kind == "assignmentTemporary" then
e ( x . name ) ;
return
end
if x . deadScalarLocal and not emitDepth . implicitGlobal ( x . names [ 1 ] . text ) then
return
end
if x . concatBufferResult then
e ( x . concatBufferResult .. ":tostring()" , sourceLine ( x ) )
return
end
if x . statementCleanupOwners and not x . statementCleanupActive then
pluck . emitStatementCleanup ( x )
return
end
if x . statementOwner then
local state = pluck . statementOwnerState ( x . statementOwner )
if state then
local owner = x . statementOwner
x . statementOwner = nil
e ( ("%s(%s,%d,") : format ( pluck . statementOwnerCapture ( ) , state . name , state . index ) , sourceLine ( x ) )
emit ( x )
e ( ")" )
x . statementOwner = owner
return
end
end
if x . sendableCaptures and outliningSendable ~= x and ( kind == "funcExpr" or kind == "shortfn" ) then
local workersName = compilerModuleName ( "nupp.workers" )
e ( workersName .. ".__sendable(" , sourceLine ( x ) )
local priorOutline = outliningSendable
outliningSendable = x
emit ( x )
outliningSendable = priorOutline
e ( (",%q,%q") : format ( x . sendableModule , x . sendableMember ) )
for _ , capture in ipairs ( x . sendableCaptures ) do
e ( "," .. capture . name )
end
e ( ")" )
return
end



if kind == "name" and x . token and x . token . definition and not x . folded then
local framed = emitDepth . captureFrames [ x . token . definition ]
if framed then
e ( framed , sourceLine ( x ) )
return
end
end
local switchValueTemporary = emitDepth . switchValueTemps [ x ]
if switchValueTemporary then
e ( switchValueTemporary , sourceLine ( x ) )
return
end
local loweredPluck = pluck . loweredPlans [ x ]
if loweredPluck and not pluck . plans [ x ] then
local prior = pluck . activate ( loweredPluck )
emit ( x )
pluck . restore ( loweredPluck , prior )
return
end
if kind == "methodCall" and emitDepth . blockMethods and emitDepth . blockMethods [ x ] then
local method = emitDepth . blockMethods [ x ]
e ( method . method .. "(" .. method . receiver , sourceLine ( x ) )
local args = x . args
if args and args . loweredArgs then
if # args . loweredArgs > 0 then
e ( "," ) ;
pluck . emitArgs ( args )
end
elseif args then
for _ , arg in ipairs ( args . exprs or { } ) do
e ( "," ) ;
emit ( arg )
end
if args . table then
e ( "," ) ;
emit ( args . table )
end
if args . str then
e ( "," ) ;
emit ( args . str )
end
end
e ( ")" )
return
end
local switchDestination = emitDepth . switchDestination ( x )
if switchDestination then
emitDepth . lowerSwitch ( x . exprs [ 1 ] , switchDestination )
return
end
if emitDepth . switchStatementRoot [ kind ]
and emitDepth . switchStatementActive ~= x
and emitDepth . switchContains ( x , pluck . statementCall ( x ) )
then
local priorSwitchStatement = emitDepth . switchStatementActive
emitDepth . switchStatementActive = true
local target = kind == "assignStmt" and # ( x . targets or { } ) == 1 and x . targets [ 1 ] or nil
local guarded = target and ( target . kind == "safeIndex" or target . kind == "safeBracket" )
if guarded then
emitDepth . lowerSwitches ( target . obj )
emitDepth . capturePrefix ( target . obj )
e ( "if " .. emitDepth . switchValueTemps [ target . obj ] .. "~=nil then " )
emitDepth . lowerSwitches ( target . expr )
emitDepth . capturePrefix ( target . expr )
emitDepth . lowerValues ( x . exprs or { } )
else
emitDepth . planSwitchStatement ( x )
end
emitDepth . switchStatementActive = x
emit ( x )
if guarded then
e ( " end;" )
end
emitDepth . switchStatementActive = priorSwitchStatement
return
elseif kind == "callStmt" and emitDepth . switchValueTemps [ x . expr ] then
return
elseif kind == "switchExpr" or kind == "doExpr" or kind == "orExitExpr" then
local temporary = emitDepth . switchTemps [ x ]
if temporary then
e ( temporary , sourceLine ( x ) )
else
emitDepth . diag (
cst . firstToken ( x ) ,
"NUPP2142" ,
"this expression cannot be lifted from its placement" ,
"assign it to a local in a statement before using it here"
)
e ( "nil" , sourceLine ( x ) )
end
return
elseif kind == "yieldStmt" then
local frame = emitDepth . valueFrame ( )
if frame and x . value then
emitDepth . lowerSwitches ( x . value )
e ( "" , sourceLine ( x ) )
emitDepth . valueExit ( frame , x . value )
else
emitDepth . diag ( cst . firstToken ( x ) , "NUPP2141" , "yield requires an enclosing do expression" )
end
return
elseif kind == "breakStmt" or kind == "continueStmt" then
emitDepth . valueControl ( kind == "breakStmt" and "break" or "continue" , sourceLine ( x ) )
return
elseif kind == "statementCleanupStateExpr" then
e ( "{}" , sourceLine ( x ) )
return
end
if kind == "assignStmt" and pluck . multiIndexedAssignment ( x ) then
return
end
if kind == "assignStmt" and # ( x . targets or { } ) == 1 and # ( x . exprs or { } ) == 1 then
local target = x . targets [ 1 ]
if target
and target . kind == "dotIndex"
and target . indexedField
and target . indexedField . adapter == "span"
and target . obj
and target . obj . indexedAccess
then
local access = target . obj
local direct = access . indexedDirectAccess == true
if emitDepth . view . info ( access . obj ) then
emitDepth . view . spanSlot ( access . obj , access . expr , target . name . text , not direct )
e ( "=" , sourceLine ( target ) )
emit ( x . exprs [ 1 ] )
return
elseif direct then
emit ( access . obj )
e ( ".pointer[" )
emit ( access . obj )
e ( ".offset+" )
emit ( access . expr )
e ( "-1]" )
else
emit ( access . obj )
e ( ":getMut(" )
emit ( access . expr )
e ( ")" )
end
e ( "." .. target . name . text .. "=" , sourceLine ( target ) )
emit ( x . exprs [ 1 ] )
return
elseif target
and target . kind == "bracketIndex"
and target . indexedAccess
and target . indexedAccess . adapter == "span"
then
if emitDepth . view . info ( target . obj ) then
emitDepth . view . spanSlot ( target . obj , target . expr , nil , not target . indexedDirectAccess )
e ( "=" , sourceLine ( target ) )
emit ( x . exprs [ 1 ] )
return
else
emit ( target . obj )
end
if target . indexedDirectAccess then
e ( ".pointer[" )
emit ( target . obj )
e ( ".offset+" )
emit ( target . expr )
e ( "-1]=" , sourceLine ( target ) )
emit ( x . exprs [ 1 ] )
else
e ( ":set(" , sourceLine ( target ) )
emit ( target . expr )
e ( "," )
emit ( x . exprs [ 1 ] )
e ( ")" )
end
return
end
local row , ordinal = soaFieldTarget ( target )
if row and ordinal then
if emitDepth . soa . boundSlot ( row . obj , ordinal , row . expr ) then
e ( "=" , sourceLine ( x ) )
emit ( x . exprs [ 1 ] )
elseif emitDepth . view . info ( row . obj ) then
emitDepth . view . soaSlot ( row . obj , ordinal , row . expr , not emitDepth . soa . unchecked ( row ) )
e ( "=" , sourceLine ( x ) )
emit ( x . exprs [ 1 ] )
else
local viewName , indexName = nextTemp ( ) , nextTemp ( )
e ( ("do const %s=") : format ( viewName ) , sourceLine ( x ) )
emit ( row . obj )
e ( ("; const %s=") : format ( indexName ) )
emit ( row . expr )
e ( ("; %s=") : format ( emitDepth . soa . slot ( viewName , ordinal , indexName , emitDepth . soa . unchecked ( row ) ) ) )
emit ( x . exprs [ 1 ] )
e ( " end" )
end
return
elseif target and target . soaRow then
if target . indexedDirectAccess and target . soaRow . element and target . soaRow . element . tag == "nominal" then
local viewName , indexName , valueName = nextTemp ( ) , nextTemp ( ) , nextTemp ( )
e ( "do" , sourceLine ( x ) )
if not emitDepth . view . info ( target . obj ) then
e ( (" const %s=") : format ( viewName ) )
emit ( target . obj )
e ( ("; const %s=") : format ( indexName ) )
emit ( target . expr )
end
e ( ( ( emitDepth . view . info ( target . obj ) and " const %s=" or "; const %s=" ) : format ( valueName ) ) )
emit ( x . exprs [ 1 ] )
for ordinal , field in ipairs ( target . soaRow . element . fieldOrder or { } ) do
e ( ";" )
if emitDepth . view . info ( target . obj ) then
emitDepth . view . soaSlot ( target . obj , ordinal , target . expr )
e ( ("=%s.%s") : format ( valueName , field ) )
else
e (
(" %s.columns[%d][%s.offset+%s-1]=%s.%s")

: format ( viewName , ordinal , viewName , indexName , valueName , field )
)
end
end
e ( " end" )
else
emit ( target . obj )
e ( ":set(" , sourceLine ( x ) )
emit ( target . expr )
e ( "," )
emit ( x . exprs [ 1 ] )
e ( ")" )
end
return
end
elseif kind == "compoundAssign" and x . target then
local target = x . target
if target . kind == "bracketIndex" and target . indexedAccess and target . indexedAccess . adapter == "span" then
e ( "do " , sourceLine ( x ) )
if emitDepth . view . info ( target . obj ) then
local indexName = nextTemp ( )
e ( ("const %s=") : format ( indexName ) )
emit ( target . expr )
e ( ";" )
pluck . emitCompoundInto ( x , function ( ) 
emitDepth . view . spanSlot ( target . obj , indexName , nil , not target . indexedDirectAccess )
end )
elseif target . indexedDirectAccess then
pluck . emitCompoundInto ( x , function ( ) 
emit ( target . obj )
e ( ".pointer[" )
emit ( target . obj )
e ( ".offset+" )
emit ( target . expr )
e ( "-1]" )
end )
else
local viewName , indexName = nextTemp ( ) , nextTemp ( )
e ( ("const %s=") : format ( viewName ) )
emit ( target . obj )
e ( (";const %s=") : format ( indexName ) )
emit ( target . expr )
e ( (";%s:set(%s,") : format ( viewName , indexName ) )
pluck . emitCompoundValue ( x , function ( ) 
e ( ("%s:get(%s)") : format ( viewName , indexName ) )
end )
e ( ")" )
end
e ( " end" )
return
elseif target . kind == "dotIndex"
and target . indexedField
and target . indexedField . adapter == "span"
and target . obj
and target . obj . indexedAccess
then
local access = target . obj
if emitDepth . view . info ( access . obj ) then
e ( "do " , sourceLine ( x ) )
local indexName = nextTemp ( )
e ( ("const %s=") : format ( indexName ) )
emit ( access . expr )
e ( ";" )
pluck . emitCompoundInto ( x , function ( ) 
emitDepth . view . spanSlot ( access . obj , indexName , target . name . text , not access . indexedDirectAccess )
end )
e ( " end" )
return
end
local viewName , indexName = nextTemp ( ) , nextTemp ( )
e ( ("do const %s=") : format ( viewName ) , sourceLine ( x ) )
emit ( access . obj )
e ( ("; const %s=") : format ( indexName ) )
emit ( access . expr )
local slot
if access . indexedDirectAccess then
slot = ("%s.pointer[%s.offset+%s-1].%s") : format ( viewName , viewName , indexName , target . name . text )
else
slot = ("%s:getMut(%s).%s") : format ( viewName , indexName , target . name . text )
end
e ( ";" )
pluck . emitCompoundInto ( x , function ( ) 
e ( slot )
end )
e ( " end" )
return
end
local row , ordinal = soaFieldTarget ( target )
if row and ordinal then
local bound = emitDepth . soa . boundName ( row . obj , ordinal , row . expr )
if bound then
pluck . emitCompoundInto ( x , function ( ) 
e ( bound )
end )
return
elseif emitDepth . view . info ( row . obj ) then
e ( "do " , sourceLine ( x ) )
local indexName = nextTemp ( )
e ( ("const %s=") : format ( indexName ) )
emit ( row . expr )
e ( ";" )
pluck . emitCompoundInto ( x , function ( ) 
emitDepth . view . soaSlot ( row . obj , ordinal , indexName , not emitDepth . soa . unchecked ( row ) )
end )
e ( " end" )
return
end
local viewName , indexName = nextTemp ( ) , nextTemp ( )
e ( ("do const %s=") : format ( viewName ) , sourceLine ( x ) )
emit ( row . obj )
e ( ("; const %s=") : format ( indexName ) )
emit ( row . expr )
local slot = emitDepth . soa . slot ( viewName , ordinal , indexName , emitDepth . soa . unchecked ( row ) )
e ( ";" )
pluck . emitCompoundInto ( x , function ( ) 
e ( slot )
end )
e ( " end" )
return
end
end
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
local active = activeFlag ( x . automaticOwnerReinit )
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
local plan = direct and not pluck . loweredPlans [ direct ] and pluck . callPlan ( direct ) or nil
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
if kind == "call" and x . spiInterface then
emit ( x . obj )
e ( "(" .. string . format ( "%q" , x . spiInterface ) .. ")" , sourceLine ( x ) )
return
end
if kind == "call" or kind == "safeCall" or kind == "methodCall" then
local activePlan = pluck . plans [ x ]
if activePlan and not activePlan . delegate then
pluck . emitCall ( x , activePlan )
return
end
end
if kind == "call" and x . constSpecialization ~= nil and x . args ~= nil then
local specialization = x . constSpecialization
local physical = specialization . physical or specialization
if x . constSpecializationExternal then
e ( "(_G.__nuppConstSpecializations[" , sourceLine ( x ) )
emit ( x . obj )
e ( "][" .. string . format ( "%q" , specialization . key ) .. "])(" )
else
e ( physical . name .. "(" , sourceLine ( x ) )
end
local wrote = false
if x . args . loweredArgs ~= nil then
for position , argument in ipairs ( x . args . loweredArgs ) do
if not specialization . omitted [ position ] then
if wrote then
e ( "," )
end
pluck . emitArgument ( argument , x . args )
wrote = true
end
end
else
for position , argument in ipairs ( x . args . exprs or { } ) do
if not specialization . omitted [ position ] then
if wrote then
e ( "," )
end
emit ( argument )
wrote = true
end
end
end
e ( ")" )
return
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





if x . wideIntegerLiteralText ~= nil then



e ( x . wideIntegerLiteralText .. ( x . wideIntegerLiteralTag == "uint64" and "ULL" or "LL" ) , sourceLine ( x ) )
return
end
if x . materializedIR then
local materializeIR = require ( "nupp.compiler.comptime.materialize.ir" )
local rendered , failure = materializeIR . render ( x . materializedIR )
if not rendered then
error ( "checked materialization IR failed during generation: " .. tostring ( failure and failure . message ) )
end
e ( rendered , sourceLine ( x ) )
local observation = x . materializationObservation
for _ , effect in ipairs ( observation and observation . runtimeFeatures or { } ) do
pluck . needRuntimeEffect ( effect )
end
return
end
if pluck . constSpecialize . emission ~= nil and kind == "name" and x . token ~= nil then
local emission = pluck . constSpecialize . emission
local replacement = emission . substitutions [ x . token . definition ]
if replacement ~= nil then
e ( replacement , sourceLine ( x ) )
return
end
end
if x . folded then
e ( x . folded , sourceLine ( x ) )
return
end
if x . foldedExpression then
e ( "(" , sourceLine ( x ) )
emit ( x . foldedExpression )
e ( ")" )
return
end
if ( kind == "binop" or kind == "unop" ) and x . simdIntrinsic then





local operand = kind == "unop" and x . operand or x . lhs
local family , element = emitDepth . simdFamilyOf ( operand and operand . inferredType )
local tag = family == "Mask" and "mask" or element or "number"
e (
("%s.lane.%s(%q,%q,")

: format ( compilerModuleName ( "nupp.simd" ) , kind == "unop" and "unary" or "binary" , x . op . text , tag ) ,
x . op . line
)
if kind == "unop" then
emit ( x . operand )
else
emit ( x . lhs )
e ( "," )
emit ( x . rhs )
end
e ( ")" )
return
end
if kind == "call" and x . simdMath and x . args and x . args . exprs and # x . args . exprs == 1 then


local _ , element = emitDepth . simdFamilyOf ( x . args . exprs [ 1 ] . inferredType )
e (
("%s.lane.method(%q,%q,") : format ( compilerModuleName ( "nupp.simd" ) , x . simdMath , element or "number" ) ,
sourceLine ( x )
)
emit ( x . args . exprs [ 1 ] )
e ( ")" )
return
end
if kind == "methodCall" and x . obj and x . name and not x . safeObj and not x . safeMethod then
local family , element = emitDepth . simdFamilyOf ( x . obj . inferredType )
local args = x . args and x . args . exprs or { }
local method = x . name . text
if family == "Vector" or family == "Mask" then
e (
("%s.lane.method(%q,%q,")

: format (
compilerModuleName ( "nupp.simd" ) ,
method ,
family == "Mask" and "mask" or element or "number"
) ,
sourceLine ( x )
)
emit ( x . obj )
for _ , argument in ipairs ( args ) do
e ( "," )
emit ( argument )
end
e ( ")" )
return
elseif family == "Species" and x . args and not x . args . table and not x . args . str then





emit ( x . obj )
e ( ":" .. method .. "(" , sourceLine ( x ) )
for index , argument in ipairs ( args ) do
if index > 1 then
e ( "," )
end
emit ( argument )
end
if ( method == "convert" or method == "reinterpret" ) and # args == 1 then
local _ , from = emitDepth . simdFamilyOf ( args [ 1 ] . inferredType )
e ( (",%q") : format ( from or "number" ) )
end
e ( ")" )
return
end
end
if ( kind == "binop" or kind == "unop" ) and x . fixedArithmetic then




local form = pluck . scalarInline . forms [ x . fixedArithmetic ]
if form ~= nil then
local sides = kind == "unop" and { x . operand } or { x . lhs , x . rhs }
for index , piece in ipairs ( form . parts ) do
if type ( piece ) == "number" then
emit ( sides [ piece ] )
else
e ( ( piece ) : gsub ( "@(%a+)" , pluck . scalarInline . bitop ) , index == 1 and x . op . line or nil )
end
end
else
pluck . needRuntimeEffect ( "stdlib.math" )
e ( "nupp.math." .. x . fixedArithmetic .. "(" , x . op . line )
if kind == "unop" then
emit ( x . operand )
else
emit ( x . lhs )
e ( "," )
emit ( x . rhs )
end
e ( ")" )
end
return
end
if kind == "unop" and x . indexedLength and x . operand then
emitDepth . view . count ( x . operand )
return
end
if kind == "dotIndex" and not emitDepth . storageVectorReading [ x ] then


local element , lanes = emitDepth . storageVectorField ( x )
if element ~= nil then
emitDepth . storageVectorReading [ x ] = true
e (
("%s.lane.fromStorage(%q,%d,") : format ( compilerModuleName ( "nupp.simd" ) , element , lanes ) ,
sourceLine ( x )
)
emit ( x )
e ( ")" )
emitDepth . storageVectorReading [ x ] = nil
return
end
end
if kind == "dotIndex"
and x . indexedField
and x . indexedField . adapter == "span"
and x . obj
and x . obj . indexedAccess
then
local access = x . obj
if emitDepth . view . info ( access . obj ) then
emitDepth . view . spanSlot (
access . obj ,
access . expr ,
x . name and x . name . text or nil ,
not access . indexedDirectAccess
)
return
end
emit ( access . obj )
if access . indexedDirectAccess then
e ( ".pointer[" )
emit ( access . obj )
e ( ".offset+" )
emit ( access . expr )
e ( "-1]" )
else
e ( ":get(" )
emit ( access . expr )
e ( ")" )
end
if x . name then
e ( "." .. x . name . text , sourceLine ( x ) )
end
return
end
if kind == "bracketIndex" and x . indexedAccess and x . indexedAccess . adapter == "span" then
if emitDepth . view . info ( x . obj ) then
emitDepth . view . spanSlot ( x . obj , x . expr , nil , not x . indexedDirectAccess )
return
end
emit ( x . obj )
if x . indexedDirectAccess then
e ( ".pointer[" )
emit ( x . obj )
e ( ".offset+" )
emit ( x . expr )
e ( "-1]" )
else
e ( ":get(" , sourceLine ( x ) )
emit ( x . expr )
e ( ")" )
end
return
end
if x . compilerFeatureEffect then
pluck . needRuntimeEffect ( x . compilerFeatureEffect )
end
if x . requiredModule then
pluck . needRuntimeEffect ( nil , x . requiredModule )
end
for _ , effect in ipairs ( x . compilerFeatureEffects or { } ) do
pluck . needRuntimeEffect ( effect )
end
if kind == "dotIndex" and x . overloadMember then
emit ( x . obj )
e ( "." .. x . overloadMember , sourceLine ( x ) )
return
end


if kind == "dotIndex" and x . fieldTake and x . name then
local take = pluck . declareHelper (
"__nuppTake" ,
"__nuppO,__nuppK" ,
"local __nuppV=__nuppO[__nuppK]; __nuppO[__nuppK]=nil; return __nuppV"
)
e ( take .. "(" , sourceLine ( x ) )
emit ( x . obj )
e ( (",%q)") : format ( x . name . text ) )
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
e ( "(" .. ("%q") : format ( pluck . hotLibraries [ x . ffiLoadLib ] ) )
local arguments = x . args and x . args . exprs or { }
for index = 2 , # arguments do
e ( "," )
emit ( arguments [ index ] )
end
e ( ")" )
return
end
if kind == "call" and x . indexedRangeCall then
local arguments = x . args and x . args . exprs or { }
local virtual = false
for index = 3 , # arguments do
virtual = virtual or emitDepth . view . info ( arguments [ index ] ) ~= nil
end
if virtual then
e ( compilerModuleName ( "nupp.mem.indexed" ) .. "._rangeCounts(" , sourceLine ( x ) )
for index , argument in ipairs ( arguments ) do
if index > 1 then
e ( "," )
end
if index >= 3 then
emitDepth . view . count ( argument )
else
emit ( argument )
end
end
e ( ")" )
return
end
end
if kind == "call" and x . indexedViewParameterTransport then
local plan = x . indexedViewParameterTransport
emit ( x . obj )
e ( "(" , sourceLine ( x ) )
for index , argument in ipairs ( x . args and x . args . exprs or { } ) do
if index > 1 then
e ( "," )
end
if plan . params [ index ] then
emitDepth . view . root ( argument )
e ( "," )
emitDepth . view . offset ( argument )
e ( "," )
emitDepth . view . count ( argument )
else
emit ( argument )
end
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
if kind == "call" and x . scalarIntrinsic then
local form = pluck . scalarInline . forms [ x . scalarIntrinsic ]
local exprs = x . args and x . args . exprs or nil
local plain = form ~= nil and exprs ~= nil and # exprs == form . arity and not ( x . args and x . args . table )
for _ , argument in ipairs ( plain and exprs or { } ) do
if argument . kind == "namedArg" or argument . kind == "pluckArg" then
plain = false
end
end
if plain then
for index , piece in ipairs ( form . parts ) do
if type ( piece ) == "number" then
emit ( exprs [ piece ] )
else
e (
( piece ) : gsub ( "@(%a+)" , pluck . scalarInline . bitop ) ,
index == 1 and sourceLine ( x ) or nil
)
end
end

return
end
end
if kind == "call" and x . tableIntrinsic then
e ( tableIntrinsicName ( x . tableIntrinsic ) , sourceLine ( x ) )
if x . args then
emit ( x . args )
end
return
end
if kind == "localStmt" and x . pattern then
local values = { }
for _ , entry in ipairs ( x . pattern ) do
if not entry . typeOnly then
values [ # values + 1 ] = entry
end
end
if # values == 0 then
return
end
local sourceName = nextTemp ( )
e ( ("local %s=") : format ( sourceName ) , sourceLine ( x ) )
emit ( x . patternSource )
e ( ";" )
e ( x . isConst and "const " or "local " )
for index , entry in ipairs ( values ) do
if index > 1 then
e ( "," )
end
local name = entry . alias or entry . sourceName
e ( name and name . text or "__nuppMissing" )
end
e ( "=" )
for index , entry in ipairs ( values ) do
if index > 1 then
e ( "," )
end
e ( sourceName .. "." .. ( entry . sourceName and entry . sourceName . text or "__nuppMissing" ) )
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
if pluck . constSpecialize . emission ~= nil and kind == "fornumStmt" and x . var ~= nil and x . body ~= nil then
local first = pluck . constSpecialize . integer ( x . start )
local last = pluck . constSpecialize . integer ( x . stop )
local step = x . step ~= nil and pluck . constSpecialize . integer ( x . step ) or 1
if first ~= nil
and last ~= nil
and step ~= nil
and step ~= 0
and pluck . constSpecialize . unrollableBody ( x . body )
then
local count = step > 0 and first <= last and math . floor ( ( last - first ) / step ) + 1
or step < 0 and first >= last and math . floor ( ( first - last ) / - step ) + 1
or 0
if count <= 8 then
local definition = x . var . definition
local emission = pluck . constSpecialize . emission
local prior = definition ~= nil and emission . substitutions [ definition ] or nil
e ( "do" , sourceLine ( x ) )
local value = first
for _ = 1 , count do
if definition ~= nil then
emission . substitutions [ definition ] = tostring ( value )
end
e ( "do" )
emit ( x . body )
e ( "end" )
value = value + step
end
if definition ~= nil then
emission . substitutions [ definition ] = prior
end
e ( "end" )
return
end
end
end
if x . constantLoopNone then



e ( "do" , sourceLine ( x ) )
local endTok = pluck . endToken ( x )
e ( "end" , endTok and endTok . line or nil )
return
end
if kind == "ifStmt"
and not ( x . constantBranch or x . constantBranchNone )
and ( x . constantClauses or emitDepth . hasBlockCondition ( x ) )
then
local clauses = x . constantClauses or x . clauses
e ( "do " , sourceLine ( x ) )
for index , clause in ipairs ( clauses ) do
if index > 1 then
e ( "else " , sourceLine ( clause ) )
end
emitDepth . lowerSwitches ( clause . cond )
local binding = clause . binding and nextTemp ( ) or nil
if binding then
e ( "local " .. binding .. "=" )
emit ( clause . cond )
e ( ";" )
end
e ( "if " )
if coverageOn then
e ( ("%s.branch(%q,%d,") : format ( coverageRuntime ( ) , coveragePath , coverageSite ( "branch" , clause . cond ) ) )
end
if binding then
e ( binding .. "~=nil" )
else
emit ( clause . cond )
end
if coverageOn then
e ( ")" )
end
e ( " then " )
if binding then
e ( "local " .. clause . binding . text .. "=" .. binding .. ";" )
end
emit ( clause . body )
end
if x . constantClauses then
if x . constantElse then
e ( "else " , sourceLine ( x . constantElse ) )
emit ( x . constantElse )
end
elseif x . elseClause then
emit ( x . elseClause )
end
local endTok = pluck . endToken ( x )
for _ = 1 , # clauses + 1 do
e ( "end " , endTok and endTok . line )
end
return
end
if kind == "ifStmt" and pluck . hasBindingClause ( x ) then





local opened = 0
for index , clause in ipairs ( x . clauses ) do
if clause . binding and clause . cond then
local temp = nextTemp ( )
local head = clause [ 1 ]
local headLine = cst . isToken ( head ) and head . line or sourceLine ( clause )
e ( ( index == 1 and "do local %s =" or "else local %s =" ) : format ( temp ) , headLine )
opened = opened + 1
emit ( clause . cond )
local thenLine = nil
for _ , child in ipairs ( clause ) do
if cst . isToken ( child ) and child . kind == "then" then
thenLine = child . line
end
end
e ( ("if %s ~= nil then local %s = %s") : format ( temp , clause . binding . text , temp ) , thenLine )
if clause . body then
emit ( clause . body )
end
else
emit ( clause )
end
end
if x . elseClause then
emit ( x . elseClause )
end
local endTok = pluck . endToken ( x )
e ( "end" , endTok and endTok . line or nil )
for _ = 1 , opened do
e ( "end" )
end
return
end
if kind == "ifStmt" and ( x . constantBranch or x . constantBranchNone ) then



e ( "do" , sourceLine ( x ) )
if x . constantBranch then
emit ( x . constantBranch )
end
local endTok = pluck . endToken ( x )
e ( "end" , endTok and endTok . line or nil )
return
end
if coverageOn and ( kind == "ifClause" or kind == "elseifClause" ) then


local branch = coverageSite ( "branch" , x . cond )
for _ , child in ipairs ( x ) do
if child == x . cond then
e ( ("%s.branch(%q,%d,") : format ( coverageRuntime ( ) , coveragePath , branch ) , sourceLine ( child ) )
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
local spilled = emitDepth . spill and emitDepth . spill . decls [ x ]
if spilled then
emitDepth . spill . name ( runtimeName )
end
local storage = ( attached or spilled ) and "" or x . visibility == "global" and "" or "local "
local expr = ("%s%s = {} %s.__index = %s") : format ( storage , runtimeName , runtimeName , runtimeName )
e ( expr , line )
local nominal = x . resolvedType
local jsonDerive = x . deriveRecipe and x . deriveRecipe . data and x . deriveRecipe . data . json
if nominal and ( nominal . runtimeReflectionNeeded or jsonDerive ) then
pluck . needRuntimeEffect ( "stdlib.reflection" )





local reflection = require ( "nupp.compiler.reflection" )
local descriptor = reflection . describe ( nominal , runtimeName )
e (
";_G.nupp.__reflect.register(" .. runtimeName .. "," .. pluck . renderData (
descriptor
) .. "," .. pluck . renderData ( reflection . runtimeReferences ( nominal ) ) .. ")"
)
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
pluck . emitWitnessTargets ( x , runtimeName )
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
local spilled = emitDepth . spill and emitDepth . spill . decls [ x ]
if spilled then
emitDepth . spill . name ( runtimeName )
end
local storage = ( attached or spilled ) and "" or x . visibility == "global" and "" or "local "
e ( ("%s%s = {}") : format ( storage , runtimeName ) , line )
for _ , entry in ipairs ( defaults ) do
entry . inlineRuntimeOwner = runtimeName
entry . inlineDotted = true
emit ( entry )
end
emitInheritedDefaults ( x , runtimeName )
return
end

if kind == "recordDecl" and x . declKind == "struct" and emitDepth . nativeOnlyStruct ( x ) then





local line = sourceLine ( x )
local path = declPath ( x )
local spilled = emitDepth . spill and emitDepth . spill . decls [ x ]
local storage = ( path or spilled ) and "" or x . visibility == "global" and "" or "const "
local mt = "__nuppMt_" .. x . name . text
local mtStorage = spilled and "" or "const "
if spilled then
emitDepth . spill . name ( x . name . text )
emitDepth . spill . name ( mt )
end
local names , fields = { } , { }
for _ , entry in ipairs ( x . entries ) do
if entry . kind == "fieldDecl" then
local fname = entry . name . text
names [ # names + 1 ] = "__nuppF" .. tostring ( # names + 1 )
fields [ # fields + 1 ] = fname .. " = " .. names [ # names ]
end
end
e (
mtStorage .. mt .. " = {__index = {}} " .. storage .. (
path or x . name . text
) .. (" = setmetatable({}, {__call = function(_, %s) return setmetatable({%s}, %s) end})")

: format ( table . concat ( names , ", " ) , table . concat ( fields , ", " ) , mt ) ,
line
)
for _ , entry in ipairs ( x . entries or { } ) do
if entry . kind == "inlineMethod" then
entry . inlineRuntimeOwner = mt .. ".__index"
emit ( entry )
end
end
emitInheritedDefaults ( x , mt .. ".__index" )
pluck . emitDerivedMembers ( x , path or x . name . text , mt .. ".__index" )
pluck . emitWitnessTargets ( x , path or x . name . text )
return
elseif kind == "recordDecl" and x . declKind == "struct" then



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
local vectorElement , vectorLanes = require (
"nupp.compiler.targetlayout"
) . storageVector ( ( entry ) . fieldType )
if vectorElement ~= nil then




local targetLayout = require ( "nupp.compiler.targetlayout" )
local bytes = targetLayout . VECTOR_ELEMENT_BYTES [ vectorElement ]
cdecl [
# cdecl + 1
] = ("%s %s[%d] __attribute__((aligned(%d)));")

: format (
C_PRIM [ vectorElement ] ,
fname ,
vectorLanes ,
targetLayout . luaVectorAlignment ( bytes , vectorLanes )
)
elseif t . kind == "tname" and C_PRIM [ t . base . text ] then
cdecl [ # cdecl + 1 ] = C_PRIM [ t . base . text ] .. " " .. fname .. width .. ";"
elseif t . kind == "tname" and structTag [ cst . lastName ( t ) or "" ] then
cdecl [ # cdecl + 1 ] = "struct " .. structTag [ cst . lastName ( t ) ] .. " " .. fname .. ";"
elseif t . kind == "tname" then
cdecl [ # cdecl + 1 ] = "$ " .. fname .. ";"
params [ # params + 1 ] = ( t . reified or cst . textOf ( t ) )
elseif t . kind == "tcarray" and t . count then



local element = t . element
local cType = element and element . kind == "tname" and C_PRIM [ element . base . text ] or nil
if cType then
cdecl [ # cdecl + 1 ] = cType .. " " .. fname .. "[" .. cst . textOf ( t . count ) .. "];"
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
emitDepth . diag ( entry . name , "NUPP3002" , "cannot reify this array element type" )
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
emitDepth . diag ( entry . name , "NUPP3002" , "cannot reify this pointer field type" )
end
else
emitDepth . diag ( entry . name , "NUPP3002" , "cannot reify this field type" )
end
end
end
local line = sourceLine ( x )
local path = declPath ( x )
local spilled = emitDepth . spill and emitDepth . spill . decls [ x ]
local storage = ( path or spilled ) and "" or x . visibility == "global" and "" or "const "



local mt = "__nuppMt_" .. x . name . text
local mtStorage = spilled and "" or "const "
if spilled then
emitDepth . spill . name ( x . name . text )
emitDepth . spill . name ( mt )
end
local tag = structTag [ x . name . text ]
local expr
if tag then



expr = ("_G.pcall(__nuppFfi.cdef, \"struct %s { %s };\") ")

: format (
tag ,
table . concat ( cdecl , " " )
) .. mtStorage .. mt .. " = {__index = {}} " .. storage .. (
path or x . name . text
) .. (" = %s(__nuppFfi.typeof(\"struct %s\"), %s)") : format ( metatypeHelper ( ) , tag , mt )
else
expr = mtStorage .. mt .. " = {__index = {}} " .. storage .. (
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
elseif entry . kind == "constructorDecl" then




entry . inlineRuntimeOwner = mt .. ".__index"
entry . structAllocator = path or x . name . text
emit ( entry )
end
end




emitInheritedDefaults ( x , mt .. ".__index" )




pluck . emitDerivedMembers ( x , path or x . name . text , mt .. ".__index" )
pluck . emitWitnessTargets ( x , path or x . name . text )
return
end

if kind == "cdefStruct" then
needsFfi = true
local fields = { }
for _ , entry in ipairs ( x . entries ) do
if entry . kind == "fieldDecl" then



local ct = entry . type . resolvedType
and require (
"nupp.compiler.cinterop.cabi"
) . declaration ( entry . type . resolvedType , entry . name . text , "ffi" )
if not ct then
local bare = cdefCType ( entry . type )
ct = bare and ( bare .. " " .. entry . name . text ) or nil
end
if ct then
local width = entry . bitWidth and " : " .. entry . bitWidth . text or ""
fields [ # fields + 1 ] = ct .. width .. ";"
else
emitDepth . diag ( entry . name , "NUPP3003" , "cdef field type has no C representation" )
end
end
end
local line = sourceLine ( x )
local aggregate = x . aggregateKind or "struct"



local declared = false
for _ , entry in ipairs ( x . entries ) do
declared = declared or entry . kind == "fieldDecl"
end
local declaration = declared and ("%s %s { %s };") : format ( aggregate , x . name . text , table . concat ( fields , " " ) )
or ("%s %s;") : format ( aggregate , x . name . text )

local spilled = emitDepth . spill and emitDepth . spill . decls [ x ]
if spilled then
emitDepth . spill . name ( x . name . text )
end
e (
("_G.pcall(__nuppFfi.cdef, \"%s\") %s%s = __nuppFfi.typeof(\"%s %s\")")

: format ( declaration , spilled and "" or "const " , x . name . text , aggregate , x . name . text ) ,
line
)
return

elseif kind == "cdefFunc" then
needsFfi = true
local name = x . name . text



local sig , signatureWhy = require ( "nupp.compiler.cinterop.cabi" ) . prototype ( x . cAbiSignature , true )
if not sig then
emitDepth . diag ( x . name , "NUPP3003" , "cdef signature has no C representation: " .. tostring ( signatureWhy ) )
sig = "void " .. name .. "(void);"
end
local line = sourceLine ( x )


local ns = "__nuppFfi.C"
if x . fromLib then
needsLibs = true
local authored = x . fromLib . text : match ( "^\"(.*)\"$" ) or x . fromLib . text : match ( "^'(.*)'$" )
local mapped = authored and pluck . hotLibraries [ authored ] or nil
ns = mapped and ("__nuppLib(%q)") : format ( mapped ) or ("__nuppLib(%s)") : format ( x . fromLib . text )
end
local storage = "const "
if emitDepth . spill and emitDepth . spill . decls [ x ] then
storage = ""
emitDepth . spill . name ( name )
end
if x . countedAbi then
local rawName = nextTemp ( )
if storage == "" then
emitDepth . spill . name ( rawName )
end
e ( ("_G.pcall(__nuppFfi.cdef, %q) %s%s = %s.%s") : format ( sig , storage , rawName , ns , name ) , line )
e ( (" %s%s=function(%s) ") : format ( storage , name , table . concat ( x . countedAbi . logicalNames or { } , "," ) ) )
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
("if %s.count~=%s.count then error(%q,2) end ")

: format (
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
e ( ("const %s,%s=%s:ref() ") : format ( pointerValue , countValue , mapping . pointerName ) )
else
local ignoredCount = nextTemp ( )
e ( ("const %s,%s=%s:ref() ") : format ( pointerValue , ignoredCount , mapping . pointerName ) )
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
e ( ("_G.pcall(__nuppFfi.cdef, %q) %s%s = %s.%s") : format ( sig , storage , name , ns , name ) , line )
end
pluck . emitRegistrations ( x . name . cleanupRegistrations , line , nil , x . name . text )
return
end

if TYPE_KINDS [ kind ] or DECL_KINDS [ kind ] then




pluck . emitRegistrations ( x . cleanupRegistrations , sourceLine ( x ) )
return

elseif kind == "castExpr" then
emit ( x . expr )

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
e ( "( _G.type(" , firstTok and firstTok . line )
emit ( x . expr )
e ( ") == \"" .. IS_TYPE [ t . base . text ] .. "\" )" )
elseif t . primitiveTest then


e ( "( _G.type(" , firstTok and firstTok . line )
emit ( x . expr )
e ( ") == \"" .. t . primitiveTest .. "\" )" )
elseif t . kind == "tfunc" then
e ( "( _G.type(" , firstTok and firstTok . line )
emit ( x . expr )
e ( ") == \"function\" )" )
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
e ( ("%s(") : format ( name ) , line )
emit ( x . expr )
e ( ")" )
end
elseif t . recordName then












e ( "( _G.getmetatable(" , firstTok and firstTok . line )
emit ( x . expr )
e ( ")?.__index == " .. t . recordName .. " )" )
elseif t . recordNames then



local test = pluck . declareHelper (
"__nuppIsRecordIn" ,
"value,..." ,
"local mt=getmetatable(value);if mt==nil then return false end;local identity=mt.__index;for index=1,select(\"#\",...) do if select(index,...)==identity then return true end end;return false"


)
e ( test .. "(" , firstTok and firstTok . line )
emit ( x . expr )
e ( "," .. table . concat ( t . recordNames , "," ) .. ")" )
elseif t . reified then

needsFfi = true
e ( "__nuppFfi.istype(" .. t . reified .. "," , firstTok and firstTok . line )
emit ( x . expr )
e ( ")" )
else





e ( "true" )
end

elseif kind == "funcExpr" and x . body and # ( x . body . takenCaptures or { } ) > 0 then
emitDepth . affineFunction ( x )
return

elseif kind == "shortfn" then




local first = x [ 1 ]
local line = first and ( cst . isToken ( first ) and first . line or ( first [ 1 ] and first [ 1 ] . line ) )
if not x . varargParam and not emitDepth . switchContains ( x . expr ) then
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
emitDepth . beginActivation ( )
emit ( x . body )
emitDepth . endActivation ( )
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
emitDepth . beginActivation ( )
if x . varargParam then
e ( ("local %s = { n = _G.select(\"#\", ...), ... }") : format ( x . varargParam . name . text ) )
end
if x . expr then


emitDepth . lowerSwitches ( x . expr )
e ( "return (" )
emit ( x . expr )
e ( ")" )
else
emit ( x . body )
end
emitDepth . endActivation ( )
emitDepth . fn = emitDepth . fn - 1
e ( "end" )

elseif kind == "istring" then
local piecesOpen = false
local line = x [ 1 ] and x [ 1 ] . line
e ( "(" , line )
for _ , child in ipairs ( x ) do
if cst . isToken ( child ) then
local text = child . text
local chunk
if child . kind == "istringOpen" then
chunk = text : sub ( 2 , -3 )
elseif child . kind == "istringMid" then
chunk = text : sub ( 2 , -3 )
elseif child . kind == "istringClose" then
chunk = text : sub ( 2 , -2 )
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
e ( "_G.tostring(" )
emit ( child )
e ( ")" )
piecesOpen = true
end
end
if not piecesOpen then
e ( "\"\"" )
end
e ( ")" )

elseif kind == "binop" and x . op . kind == "//" then
local wide = pluck . wideFloorDivision ( x . lhs , x . rhs )
if wide then
e ( wide .. "(" , x . op . line )
emit ( x . lhs )
e ( "," )
emit ( x . rhs )
e ( ")" )
return
end
e ( "_G.math.floor((" , x . op . line )
emit ( x . lhs )
e ( ") / (" )
emit ( x . rhs )
e ( "))" )

elseif kind == "compoundAssign" and ( emitDepth . switchContains ( x ) or LOWERED_COMPOUND [ x . op . kind ] ) then



local base = x . op . kind : sub ( 1 , -2 )
local target = x . target
local line = sourceLine ( target )





local function assignTo ( slot , at ) 
local read = slot
if base ~= "??" and emitDepth . switchContains ( x . value ) then
read = nextTemp ( )
e ( "local " .. read .. "=" .. slot .. ";" , at )
emitDepth . lowerSwitches ( x . value )
end
if base == "??" then
e ( ("if %s == nil then ") : format ( slot ) , at )
emitDepth . lowerSwitches ( x . value )
e ( slot .. "=" )
emit ( x . value )
e ( " end" )
elseif base == "//" and pluck . wideFloorDivision ( target , x . value ) then
e ( ("%s = %s(%s,") : format ( slot , pluck . wideFloorDivision ( target , x . value ) , read ) , at )
emit ( x . value )
e ( ")" )
elseif base == "//" then
e ( ("%s = _G.math.floor((%s) / (") : format ( slot , read ) , at )
emit ( x . value )
e ( "))" )
else
pluck . emitCompoundValue (
x ,
function ( ) 
e ( read )
end ,
slot .. "=" ,
at
)
end
end

local tkind = target . kind
if tkind == "name" then
assignTo ( target . token . text , line )
return
end
local safe = tkind == "safeIndex" or tkind == "safeBracket"
local dotted = tkind == "dotIndex" or tkind == "safeIndex"
emitDepth . lowerSwitches ( target . obj )
local prefix = nextTemp ( )
e ( ("do const %s = ") : format ( prefix ) , line )
emit ( target . obj )
e ( "; " )
if safe then
e ( ("if %s~=nil then ") : format ( prefix ) )
end
if dotted then
assignTo ( ("%s.%s") : format ( prefix , target . name . text ) )
else
emitDepth . lowerSwitches ( target . expr )
local key = nextTemp ( )
e ( ("const %s = ") : format ( key ) )
emit ( target . expr )
e ( "; " )
assignTo ( ("%s[%s]") : format ( prefix , key ) )
end
if safe then
e ( " end" )
end
e ( " end" )
return

elseif kind == "callStmt" and x . expr and x . expr . logIntrinsic then




local call = x . expr
local severity = call . logIntrinsic
local line = sourceLine ( call )
local exprs = call . args and call . args . exprs or { }






local logName = compilerModuleName ( "nupp.log#view" )
e ( ("if %s.on[%d] then %s.emit(%d,%d,") : format ( logName , severity , logName , severity , line ) , line )
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
e ( ("do const %s = ") : format ( zoneName ) , line )
emit ( receiver )
e ( "; " )
if op == "push" then
local depthName = nextTemp ( )
e (
("if %s.__nuppActive then const %s=%s.__nuppDepth+1;%s.__nuppDepth=%s;%s.__nuppStack[%s]=")

: format ( zoneName , depthName , zoneName , zoneName , depthName , zoneName , depthName )
)
local exprs = call . args and call . args . exprs or { }
emit ( exprs [ 1 ] )
e ( (";%s.__nuppVersion=%s.__nuppVersion+1 end") : format ( zoneName , zoneName ) )
else
local depthName = nextTemp ( )
e (
("if %s.__nuppActive and %s.__nuppDepth>0 then const %s=%s.__nuppDepth;%s.__nuppStack[%s]=nil;%s.__nuppDepth=%s-1;%s.__nuppVersion=%s.__nuppVersion+1 end")


: format (
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

elseif kind == "callStmt" and x . expr and x . expr . keepIntrinsic then




local call = x . expr
local receiver = call . obj and call . obj . obj
local sinkName = nextTemp ( )
e ( ("do const %s = ") : format ( sinkName ) , sourceLine ( call ) )
emit ( receiver )
e ( ("; %s.__nuppSink = ") : format ( sinkName ) )
local exprs = call . args and call . args . exprs or { }
emit ( exprs [ 1 ] )
e ( " end" )
return

elseif kind == "callStmt" and x . expr and x . expr . ownershipIntrinsic == "drop" then






local inner = x . expr
local innerArgs = inner . args and inner . args . exprs or { }
local innerMove = ownershipMoveOf ( innerArgs [ 1 ] )
local innerActive = innerMove and activeFlag ( innerMove ) or nil
e ( "do" , sourceLine ( x ) )
if innerActive then
e ( ("%s=false;") : format ( innerActive ) )
inner . ownershipMoveCleared = true
end
local virtualDrop = innerArgs [ 1 ] and emitDepth . view . info ( innerArgs [ 1 ] )
if not virtualDrop then
emit ( inner )
end
inner . ownershipMoveCleared = nil
e ( "end" )
return

elseif kind == "callStmt" and x . expr and x . expr . ownershipIntrinsic == "attemptAll" then



local inner = x . expr
pluck . emitRegistrations ( inner . cleanupRegistrations , sourceLine ( x ) , false )
e ( "do " , sourceLine ( x ) )
e ( "local " .. nextTemp ( ) .. "=" )
emit ( inner )
e ( " end" )
return

elseif kind == "callStmt" and x . expr and x . expr . ownershipIntrinsic then








e ( "do " , sourceLine ( x ) )
e ( "local " .. nextTemp ( ) .. "=" )
emit ( x . expr )
e ( " end" )
return

elseif kind == "callStmt" and x . expr and pluck . beginsWithLoweredWrapper ( x . expr ) then






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
local cType = cdefCType ( output . typeNode ) or "void **"
cType = cType : gsub ( "%s*%*$" , "" ) .. "[1]"
body [ # body + 1 ] = ("const %s=__nuppFfi.new(%q); ") : format ( holders [ j ] , cType )
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
status and ("const %s=") : format ( status ) or ""
) .. ("__nuppFn(%s); return ") : format ( table . concat ( callArguments , "," ) )

local results = { }
if status then
results [ # results + 1 ] = status
end
for j , output in ipairs ( x . ffiOutContracts ) do
if output . success == "zero" then
results [ # results + 1 ] = ("(%s==0 and %s[0] or nil)") : format ( status , holders [ j ] )
elseif output . success == "nonzero" then
results [ # results + 1 ] = ("(%s~=0 and %s[0] or nil)") : format ( status , holders [ j ] )
elseif output . success : match ( "^notequals:" ) then
local literal = output . success : sub ( 11 )
results [ # results + 1 ] = ("(%s~=%s and %s[0] or nil)") : format ( status , literal , holders [ j ] )
elseif output . success : match ( "^equals:" ) then
local literal = output . success : sub ( 8 )
results [ # results + 1 ] = ("(%s==%s and %s[0] or nil)") : format ( status , literal , holders [ j ] )
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

elseif kind == "call" and x . ownershipIntrinsic and x . ownershipIntrinsic ~= "manage" then
local args = x . args and x . args . exprs or { }
local line = sourceLine ( x )
local move = ownershipMoveOf ( args [ 1 ] )
local movedActive = move and activeFlag ( move ) or nil







local wrapsMove = movedActive ~= nil
and not x . ownershipMoveCleared
and ( x . ownershipIntrinsic == "drop" or x . ownershipIntrinsic == "release" )
if wrapsMove then
pluck . loweredFunction ( ("(function() %s=false; return ") : format ( movedActive ) , line , pluck . reasons . move )
end
if x . ownershipIntrinsic == "adopt" or x . ownershipIntrinsic == "release" then
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" , line )
end
elseif x . ownershipIntrinsic == "borrow" then
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
] = ("if __n>0 then if __n>1 then %s(%s(__errs[1],__errs,2),0) else %s(__errs[1],0) end end")

: format ( cleanupGlobals . error , cleanupFailureName , cleanupGlobals . error )
e ( pluck . declareHelper ( "__nuppAttemptAll" , "__nuppV" , table . concat ( statements ) ) .. "(" , line )
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" )
end
e ( ")" )
else




local statements = { "if __nuppV == nil then return end " }
local params = "__nuppV"
local guardFlags = { }
for index , cleanup in ipairs ( x . ownerCleanups or { } ) do
local call = cleanupCall ( cleanup , "__nuppV" )
local guard = x . ownerCleanupGuards and x . ownerCleanupGuards [ index ] or nil
local flag = guard and activeFlag ( guard ) or nil
if call and guard and flag then
local param = ("__nuppG%d") : format ( # guardFlags + 1 )
guardFlags [ # guardFlags + 1 ] = flag
params = params .. "," .. param
statements [ # statements + 1 ] = "if " .. param .. " then " .. call .. " end; "
elseif call and not guard then
statements [ # statements + 1 ] = call .. "; "
end
end
e ( pluck . declareHelper ( "__nuppDrop" , params , table . concat ( statements ) ) .. "(" , line )
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" )
end
for _ , flag in ipairs ( guardFlags ) do
e ( "," .. flag )
end
e ( ")" )
end
if wrapsMove then
e ( " end)()" )
end
return

elseif kind == "call" and x . admitName then
emitDepth . admitCall ( x )
return

elseif kind == "call" and x . ffiIntrinsic then

needsFfi = true
local line = sourceLine ( x )


local ctypeExpr = x . ffiTypeName
if not ctypeExpr then
local typeNode = x . ffiTypeNode




if x . ffiIntrinsic == "cast" and typeNode and typeNode . kind == "tcarray" then
typeNode = typeNode . element
local element = typeNode and cdefCType ( typeNode )
if element then
e ( ("__nuppFfi.cast(%q") : format ( element .. " *" ) , line )
for _ , arg in ipairs ( x . args and x . args . exprs or { } ) do
e ( "," )
emit ( arg )
end
e ( ")" )
return
end
end
local cType = x . ffiTypeNode and cdefCType ( x . ffiTypeNode )
if not cType then
emitDepth . diag (
x . name or ( x [ 1 ] and cst . isToken ( x [ 1 ] ) and x [ 1 ] ) ,
"NUPP3004" ,
"this type has no C representation for an ffi operation"
)
cType = "void *"
end
ctypeExpr = ("%q") : format ( cType )
end
e ( ("__nuppFfi.%s(%s") : format ( x . ffiIntrinsic , ctypeExpr ) , line )
for _ , arg in ipairs ( x . args and x . args . exprs or { } ) do
e ( "," )
emit ( arg )
end
e ( ")" )
return

elseif kind == "call" and x . carrayElem then
if pluck . storage . enabled then
pluck . needRuntimeEffect ( "runtime.cstorage" )
e ( pluck . storage . name .. ".allocateArray(" , sourceLine ( x ) )
emit ( x . carrayElem )
e ( "," )
emit ( x . args . exprs [ 2 ] )
e ( ")" )
return
end

needsFfi = true
needsArrayCache = true
local line = sourceLine ( x )
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
local line = sourceLine ( x )
local library = x . cheaderLib and ( pluck . hotLibraries [ x . cheaderLib ] or x . cheaderLib ) or nil
local ns = library and ("__nuppFfi.load(%q)") : format ( library ) or "__nuppFfi.C"



local quoted = quotedCDeclarations ( x . cheaderCdef )
pluck . loweredFunction (
("(function() local d,p,c=__nuppFfi.cdef,_G.pcall,{%s} for i=1,#c do p(d,c[i]) end return %s end)()")

: format ( table . concat ( quoted , "," ) , ns ) ,
line ,
pluck . reasons . cheader
)
return

elseif kind == "newExpr" then







local flags = { }
for _ , move in ipairs ( x . call and x . call . constructionOwnerMoves or { } ) do
local flag = activeFlag ( move )
if flag then
flags [ # flags + 1 ] = flag .. "=false; "
end
end
if # flags > 0 then
local value = nextTemp ( )
pluck . loweredFunction (
("(function(%s) %sreturn %s end)(") : format ( value , table . concat ( flags ) , value ) ,
sourceLine ( x ) ,
pluck . reasons . move
)
emit ( x . call )
e ( ")" )
return
end
if x . call then
emit ( x . call )
end
return

elseif kind == "call" and x . managedCleanups then
if hotState and x . managedPolicy then
hotState . policies [ x . managedPolicy ] = true
end
local line = sourceLine ( x )
local args = x . args and x . args . exprs or { }
local activeNames = { }
local seen = { }
local directMove = ownershipMoveOf ( args [ 1 ] )
local directActive = directMove and activeFlag ( directMove ) or nil
if directActive then
seen [ directActive ] = true
activeNames [ # activeNames + 1 ] = directActive
end
for _ , move in ipairs ( x . automaticOwnerMoves or { } ) do
local activeName = activeFlag ( move )
if activeName and not seen [ activeName ] then
seen [ activeName ] = true
activeNames [ # activeNames + 1 ] = activeName
end
end
local value = nextTemp ( )
pluck . loweredFunction ( ("(function(%s) ") : format ( value ) , line , pluck . reasons . move )
for _ , activeName in ipairs ( activeNames ) do
e ( ("%s=false; ") : format ( activeName ) )
end
local body = { "local __first,__suppressed=nil,0; " }
for _ , cleanup in ipairs ( x . managedCleanups ) do
local call = protectedCleanupCall ( cleanup , "__nuppV" , "pcall" )
if call then
body [
# body + 1
] = "do local __ok,__reason="
.. call
.. "; if not __ok then if __first==nil then __first=__reason else __suppressed=__suppressed+1 end end end; "

end
end
body [
# body + 1
] = "if __first~=nil then if __suppressed>0 then _G.error(_G.tostring(__first)..\" (suppressed \".._G.tostring(__suppressed)..\" cleanup failure(s))\",0) else _G.error(__first,0) end end"


e (
("return __nupp.__manage(%s,%s,%q)")

: format (
value ,
pluck . declareHelper ( "__nuppManagedCleanup" , "__nuppV" , table . concat ( body ) ) ,
x . managedPolicy or ""
)
)
e ( " end)(" )
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" )
end
e ( ")" )
return

elseif kind == "call" and x . recoverManagedAlias then
local args = x . args and x . args . exprs or { }
e ( "__nupp.__recoverAlias(" , sourceLine ( x ) )
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" )
end
e ( ")" )
return

elseif kind == "methodCall" and x . managedAliasPolicy then
emit ( x . obj )
e ( (":_downcast(%q)") : format ( x . managedAliasPolicy ) , sourceLine ( x ) )
return

elseif kind == "methodCall" and x . trailingCallableCall then



local member = x . trailingCallableMember
if type ( member ) ~= "string" then
error ( "a rotated trailing-callable call without its member" )
end
local args = x . args and x . args . exprs or { }
local receiver = nextTemp ( )
local parameters = { receiver }
for _ = 1 , # args do
parameters [ # parameters + 1 ] = nextTemp ( )
end
e ( ("(function(%s) return %s:%s(") : format ( table . concat ( parameters , "," ) , receiver , member ) , sourceLine ( x ) )
if # args > 0 then
e ( parameters [ # parameters ] )
for index = 1 , # args - 1 do
e ( "," .. parameters [ index + 1 ] )
end
end
e ( ") end)(" )
emit ( x . obj )
for _ , argument in ipairs ( args ) do
e ( "," )
emit ( argument )
end
e ( ")" )
return

elseif ( kind == "call" or kind == "methodCall" ) and x . automaticOwnerMoves then




local activeNames = { }
local seen = { }
for _ , move in ipairs ( x . automaticOwnerMoves or { } ) do
local activeName = activeFlag ( move )
if activeName and not seen [ activeName ] then
seen [ activeName ] = true
activeNames [ # activeNames + 1 ] = activeName
end
end
local callable = nextTemp ( )
local current = cleanupStack [ # cleanupStack ]
local moveFrame = current and current . moveFrame
for _ , activeName in ipairs ( activeNames ) do
if not moveFrame or activeName : sub ( 1 , # moveFrame + 1 ) ~= moveFrame .. "[" then
moveFrame = nil
do break end
end
end
local body = { }
for _ , activeName in ipairs ( activeNames ) do
body [ # body + 1 ] = ("%s=false; ") : format ( activeName )
end
body [ # body + 1 ] = kind == "methodCall"
and ("return %s:%s(...)") : format ( callable , x . overloadMember or x . name . text )
or ("return %s(...)") : format ( callable )
if moveFrame then
e (
pluck . declareHelper (
"__nuppMove" ,
callable .. "," .. moveFrame .. ",..." ,
table . concat ( body )
) .. "(" ,
sourceLine ( x )
)
else
pluck . loweredFunction ( ("(function(%s,...) ") : format ( callable ) , sourceLine ( x ) , pluck . reasons . move )
e ( table . concat ( body ) )
e ( " end)(" )
end
emit ( x . obj )
if moveFrame then
e ( "," .. moveFrame )
end
local args = x . args
local values = args and args . exprs or { }
if args and args . table then
values = { args . table }
end
if args and args . str then
values = { args . str }
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
pluck . needRuntimeEffect ( x . obj and x . obj . compilerFeatureEffect )


local line = sourceLine ( x )
emit ( x . obj )
e ( "." .. constructorMember ( x . constructorIndex ) , line )
if x . args then
emit ( x . args )
end
return

elseif ( kind == "call" or kind == "safeCall" ) and x . structConstruct then
local line = sourceLine ( x )
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







local line = sourceLine ( x )
e ( "_G.setmetatable({" , line )
for index , binding in ipairs ( x . recordFields or { } ) do
if index > 1 then
e ( ", " )
end
e ( cst . identifier ( binding . name ) and ( binding . name .. " = " ) or ("[%q] = ") : format ( binding . name ) )
if binding . isDefault then
e ( pluck . renderData ( binding . defaultValue ) )
else
emit ( binding . node )
end
end



if x . obj and x . obj . qualifiedModule then
e ( "}, " )
emit ( x . obj )
e ( ")" )
else
e ( "}, " .. x . recordConstruct .. ")" )
end
return

elseif kind == "constructorDecl" and x . inlineRuntimeOwner then




local body = x . body
local line = sourceLine ( x )




local names = pluck . paramNames ( body . params , true )
local owner = x . inlineRuntimeOwner
local seeded = { }
local nominal = x . ownerNominal
for _ , field in ipairs ( nominal and nominal . fieldOrder or { } ) do
local default = nominal . fieldDefaults and nominal . fieldDefaults [ field ] or nil
if default then
seeded [
# seeded + 1
] = (
cst . identifier ( field ) and ( field .. " = " ) or ("[%q] = ") : format ( field )
) .. pluck . renderData ( default . value )
end
end





local split = nominal and nominal . initializerNeeded or false
local initializer = split and initializerMember ( x . constructorIndex ) or nil
local defaultWrites = { }
for _ , assignment in ipairs ( seeded ) do
defaultWrites [ # defaultWrites + 1 ] = " self." .. assignment
end
if split then
e (
("function %s.%s(self%s)%s")

: format (
owner ,
initializer ,
# names > 0 and ( ", " .. table . concat ( names , ", " ) ) or "" ,
table . concat ( defaultWrites )
) ,
line
)
elseif x . structAllocator then



e (
("function %s.%s(%s) local self = %s()%s")

: format (
owner ,
constructorMember ( x . constructorIndex ) ,
table . concat ( names , ", " ) ,
x . structAllocator ,
table . concat ( defaultWrites )
) ,
line
)
else
e (
("function %s.%s(%s) local self = _G.setmetatable({%s}, %s)")

: format (
owner ,
constructorMember ( x . constructorIndex ) ,
table . concat ( names , ", " ) ,
table . concat ( seeded , ", " ) ,
owner
) ,
line
)
end
if body . varargParam then
e ( ("local %s = { n = _G.select(\"#\", ...), ... }") : format ( body . varargParam . name . text ) )
end
local priorConstructorReturnName = emitDepth . constructorReturnName
local instanceName = nextTemp ( )
emitDepth . constructorReturnName = instanceName
e ( (" local %s=self;") : format ( instanceName ) )
emitDepth . fn = emitDepth . fn + 1
emitDepth . beginActivation ( )
if body . body then
emit ( body . body )
end
emitDepth . endActivation ( )
emitDepth . fn = emitDepth . fn - 1
emitDepth . constructorReturnName = priorConstructorReturnName
local endTok = pluck . endToken ( body )
if split then
local allocation = x . structAllocator and ( x . structAllocator .. "()" )
or ( "_G.setmetatable({}, " .. owner .. ")" )
e (
("return %s end function %s.%s(%s) return %s.%s(%s%s) end")

: format (
instanceName ,
owner ,
constructorMember ( x . constructorIndex ) ,
table . concat ( names , ", " ) ,
owner ,
initializer ,
allocation ,
# names > 0 and ( ", " .. table . concat ( names , ", " ) ) or ""
) ,
endTok and endTok . line or nil
)
else
e ( "return " .. instanceName .. " end" , endTok and endTok . line or nil )
end
return

elseif kind == "inlineMethod" and x . inlineRuntimeOwner then
local declarationName = x . inlineRuntimeOwner .. "." .. ( x . overloadMember or x . name . text )
local dispatch = pluck . hotDispatch
local planned = dispatch and dispatch . byNode [ x ] or nil
if dispatch and planned then
dispatch . emit ( planned )
pluck . emitRegistrations ( x . name and x . name . cleanupRegistrations , sourceLine ( x ) , nil , declarationName )
return
end
local body = x . body
local line = sourceLine ( x )
local names = pluck . paramNames ( body . params , false )
if x . inlineDotted then



e (
("function %s.%s(%s)")

: format ( x . inlineRuntimeOwner , x . overloadMember or x . name . text , table . concat ( names , ", " ) ) ,
line
)
else






if names [ 1 ] == "self" then
table . remove ( names , 1 )
end
e (
("function %s:%s(%s)")

: format ( x . inlineRuntimeOwner , x . overloadMember or x . name . text , table . concat ( names , ", " ) ) ,
line
)
end
if body . varargParam then
e ( ("local %s = { n = _G.select(\"#\", ...), ... }") : format ( body . varargParam . name . text ) )
end
emitDepth . fn = emitDepth . fn + 1
emitDepth . beginActivation ( )
if body . body then
emit ( body . body )
end
emitDepth . endActivation ( )
emitDepth . fn = emitDepth . fn - 1
local endTok = pluck . endToken ( body )
e ( "end" , endTok and endTok . line or nil )
pluck . emitRegistrations ( x . name and x . name . cleanupRegistrations , sourceLine ( x ) , nil , declarationName )
return

elseif kind == "funcStmt" and x . structOwner and x . memberName then
local dispatch = pluck . hotDispatch
local planned = dispatch and dispatch . byNode [ x ] or nil
if dispatch and planned then
dispatch . emit ( planned )
return
end
needsFfi = true
local line = sourceLine ( x )
local names = pluck . paramNames ( x . body . params , false )
if x . name . method then
table . insert ( names , 1 , "self" )
end


local structName = x . structOwner : match ( "[^.]+$" ) or x . structOwner
e (
("__nuppMt_%s.__index.%s = function(%s)") : format ( structName , x . memberName , table . concat ( names , ", " ) ) ,
line
)
if x . body . varargParam then
e ( ("local %s = { n = _G.select(\"#\", ...), ... }") : format ( x . body . varargParam . name . text ) )
end
emitDepth . fn = emitDepth . fn + 1
emitDepth . beginActivation ( )
if x . body . body then
emit ( x . body . body )
end
emitDepth . endActivation ( )
emitDepth . fn = emitDepth . fn - 1

local endTok = pluck . endToken ( x . body )
e ( "end" , endTok and endTok . line or nil )
return

elseif kind == "cleanupRegion" or kind == "withStmt" then




local first = x . bindings and x . bindings [ 1 ] or nil
if first and first . expr and # x . bindings == 1 and emitDepth . switchContains ( first . expr ) then
emitDepth . lowerSwitches ( first . expr )
end
if kind == "withStmt" then
x . enclosingCaptures = automaticCaptures ( x . body , x . bindings )
x . capturesEnclosing = # x . enclosingCaptures > 0
end
local virtualBinding = kind == "withStmt"
and x . bindings
and x . bindings [ 1 ]
and x . bindings [ 1 ] . virtualIndexedView
or nil
if virtualBinding then
local binding = x . bindings [ 1 ]
virtualBinding . anchorName = virtualBinding . anchorName or nextTemp ( )
e ( "do local " .. virtualBinding . anchorName .. "=" , x . withTok and x . withTok . line or sourceLine ( x ) )
emit ( virtualBinding . source )
e ( "; local " .. binding . name . text .. "=" , sourceLine ( binding . expr ) )
emit ( binding . expr )
e ( "; do" )
if x . body then
emit ( x . body )
end
e ( "end end" , x . endTok and x . endTok . line or nil )
return
elseif kind == "withStmt" and x . directCleanup then
local binding = x . bindings [ 1 ]
e ( "do local " , x . withTok and x . withTok . line or sourceLine ( x ) )
e ( binding . name . text .. "=" , sourceLine ( binding . expr ) )
local move = ownershipMoveOf ( binding . expr )
local movedActive = move and activeFlag ( move ) or nil
emit ( binding . expr )
if movedActive then
e ( ("; %s=false") : format ( movedActive ) )
end
e ( "; do" )
if x . body then
emit ( x . body )
end
e ( "end;" )
for _ , cleanup in ipairs ( binding . ownerCleanups or { } ) do
local call = cleanupCall ( cleanup , binding . name . text )
if call then
e ( call .. ";" , x . endTok and x . endTok . line or nil )
end
end
e ( "end" )
return
end
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
local statementOwnerMap = { }
local captureMoves = { }

local function collectCaptureMoves ( node ) 
if not node or cst . isToken ( node ) then
return
end
if node . kind == "funcbody" or node . kind == "funcExpr" or node . kind == "shortfn" then
local body = node . kind == "funcbody" and node or node . body
for _ , capture in ipairs ( body and body . takenCaptures or { } ) do
local definition = capture . token and capture . token . definition
if definition then
captureMoves [ definition ] = true
end
if capture . outer then
captureMoves [ capture . outer ] = true
if capture . outer . definition then
captureMoves [ capture . outer . definition ] = true
end
if capture . outer . automaticOwner then
captureMoves [ capture . outer . automaticOwner ] = true
end
end
end
end
for _ , child in ipairs ( node ) do
collectCaptureMoves ( child )
end
end

local analysisBody = x . analysisBody or x . body
collectCaptureMoves ( analysisBody )
for j = 1 , # ( x . bindings or { } ) do
owners [ j ] = nextTemp ( )
local binding = x . bindings [ j ]
for ownerIndex , owner in ipairs ( binding . statementOwners or { } ) do
statementOwnerMap [ owner ] = { name = binding . name . text , index = ownerIndex , }
end
local automatic = binding . automaticOwner
if automatic
and (
automatic . conditional
or automatic . moved
or automatic . movedFields
or captureMoves [ binding . name and binding . name . definition ]
or captureMoves [ automatic ]
)
then
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
automaticMap [
automatic
] = {
whole = active [ j ] ,
fields = fieldActive [ j ] ,
slot = owners [ j ] ,
definition = binding . name and binding . name . definition ,
}
end
end
local variadic = usesVararg ( analysisBody )
local ctx = {
entryLoopDepth = emitDepth . loop ,
functionDepth = emitDepth . fn ,
labels = labelsIn ( x . body ) ,
gotos = { } ,
automaticMap = automaticMap ,
statementOwnerMap = statementOwnerMap ,
}





local captures = x . enclosingCaptures or { }
local activation = emitDepth . activations [ # emitDepth . activations ]
local stable = # captures > 0 and activation and emitDepth . activationStable ( captures ) or false
local captureWrites , nestedCaptures = emitDepth . captureUsage ( analysisBody , captures )
local framed = # captures > 0 and not stable and emitDepth . frameEligible ( captures , nestedCaptures )
local cacheName = # captures == 0 and cleanupCacheName
or stable and activation . name
or framed and cleanupCacheName
or nil
local inStateRegion = false
for _ , parent in ipairs ( cleanupStack ) do
if parent . moveFrame then
inStateRegion = true
end
end
local shared = pluck . compat ~= "lua51"
and not emitDepth . constructorReturnName
and not inStateRegion
and cacheName ~= nil
and # ( x . bindings or { } ) == 1
and not active [ 1 ]
and not x . automaticComplex






local stateAnalysis = { analysisBody }
for _ , binding in ipairs ( x . bindings or { } ) do
stateAnalysis [ # stateAnalysis + 1 ] = binding . expr
end
for _ , item in ipairs ( x . automaticSequence or { } ) do
if item . declaration then
stateAnalysis [ # stateAnalysis + 1 ] = item . declaration
end
end

local function frameBodyEligible ( node ) 
if not node or cst . isToken ( node ) then
return true
end


if node . recordConstruct
or node . structConstruct
or node . staticCallee
or node . concatBufferResult
or node . kind == "isExpr"
or node . kind == "switchExpr"
then
return false
end
for _ , child in ipairs ( node ) do
if not frameBodyEligible ( child ) then
return false
end
end

return true
end

local stateCaptures = automaticCaptures ( stateAnalysis , x . bindings )
local _ , stateNested = emitDepth . captureUsage ( stateAnalysis , stateCaptures )
local immutableCaptures = true
for _ , definition in ipairs ( stateCaptures ) do
local t = definition . type
if emitDepth . captureWrites [ definition ]
or t and ( t . tag == "typeobject" or t . tag == "metatable" or t . tag == "typeHandle" )
then
immutableCaptures = false
end
end
local stateFrame = pluck . compat ~= "lua51"
and not shared
and # ( x . bindings or { } ) > 1
and x . automaticSequence
and not x . repeatCondition
and # cleanupStack == 0
and not emitDepth . constructorReturnName
and immutableCaptures
and frameBodyEligible ( stateAnalysis )
and emitDepth . frameEligible ( stateCaptures , stateNested )
and nextTemp ( )
or nil
local hoist = stateFrame
and emitDepth . hoist
and emitDepth . hoist . body == x . automaticBlock
and emitDepth . hoist
or nil
local hoistEmission
local stateRegion
local stateSlot
if stateFrame then
captures = stateCaptures
variadic = usesVararg ( stateAnalysis )
count = stateFrame .. "[0]"
local index = 0

local function stateCell ( ) 
index = index - 1
return ("%s[%d]") : format ( stateFrame , index )
end

for j = 1 , # ( x . bindings or { } ) do
owners [ j ] = stateCell ( )
if active [ j ] then
active [ j ] = stateCell ( )
end
for _ , field in ipairs ( fieldActiveOrder [ j ] or { } ) do
fieldActive [ j ] [ field ] = stateCell ( )
end
local automatic = x . bindings [ j ] . automaticOwner
if automatic and automaticMap [ automatic ] then
automaticMap [ automatic ] . whole = active [ j ]
automaticMap [ automatic ] . slot = owners [ j ]
end
end
ctx . moveFrame = stateFrame
cleanupCacheSites = cleanupCacheSites + 1
stateSlot = cleanupCacheSites
stateRegion = nextTemp ( )
end


if pluck . compat == "lua51" and variadic then
emitDepth . diag (
cst . firstToken ( x ) ,
"NUPP3015" ,
"variadic cleanup needs the LuaJIT xpcall argument contract" ,
"bind the needed values before entering cleanup"
)
end
if shared then
if cacheName ~= cleanupCacheName then
activation . used = true
end
cleanupCacheSites = cleanupCacheSites + 1
local slot = cleanupCacheSites
local region = nextTemp ( )
local frame = framed and nextTemp ( ) or nil
local frameParam = framed and nextTemp ( ) or nil
local binding = x . bindings [ 1 ]
e ( "do const " , ( x . startTok or x . withTok ) and ( x . startTok or x . withTok ) . line or sourceLine ( x ) )
e ( ("%s=") : format ( owners [ 1 ] ) , sourceLine ( binding . expr ) )
local move = ownershipMoveOf ( binding . expr )
local movedActive = move and activeFlag ( move ) or nil
emit ( binding . expr )
if movedActive then






e ( ("; %s=false") : format ( movedActive ) )
end
if frame then
e ( ("; const %s={") : format ( frame ) )
for index , definition in ipairs ( captures ) do
if index > 1 then
e ( "," )
end
e ( definition . token . text )
end
e ( "}" )
end
if cacheName ~= cleanupCacheName then
e ( ("; %s=%s or {}") : format ( cacheName , cacheName ) )
end
e (
("; local %s=%s[%d]; if not %s then %s=function(%s%s%s)")

: format (
region ,
cacheName ,
slot ,
region ,
region ,
binding . name . text ,
frameParam and ( "," .. frameParam ) or "" ,
variadic and ",..." or ""
)
)
cleanupStack [ # cleanupStack + 1 ] = ctx
if frameParam then
emitDepth . pushCaptureFrame ( captures , frameParam )
end
e ( "do" )
if x . body then
emit ( x . body )
end
if x . repeatCondition then
e ( pluck . separator ( ) )
emitDepth . beginCondition ( x . repeatConditionHeader )
emitDepth . lowerSwitches ( x . repeatCondition )
e ( ("%s=") : format ( x . repeatConditionTemp ) , sourceLine ( x . repeatCondition ) )
emit ( x . repeatCondition )
emitDepth . endCondition ( x . repeatConditionHeader )
end
e ( ("end; return \"normal\" end; %s[%d]=%s end;") : format ( cacheName , slot , region ) )
if frame then
emitDepth . popCaptureFrame ( )
end
e (
("const %s,%s,%s=%s(%s,%s,%s%s%s);")

: format (
ok ,
tag ,
payload ,
cleanupGlobals . xpcall ,
region ,
cleanupIdName ,
owners [ 1 ] ,
frame and ( "," .. frame ) or "" ,
variadic and ",..." or ""
)
)
cleanupStack [ # cleanupStack ] = nil
if frame then
for index , definition in ipairs ( captures ) do
if captureWrites [ definition ] then
e ( ("%s=%s[%d];") : format ( definition . token . text , frame , index ) )
end
end
end
e ( ("const %s=1;") : format ( count ) )
else
if stateFrame then
e ( ("do local %s={[0]=0") : format ( stateFrame ) , sourceLine ( x ) )
for index , definition in ipairs ( captures ) do
e ( (",[%d]=%s") : format ( index , definition . token . text ) )
end
if hoist then
e ( ("}; local %s=%s[%d];") : format ( stateRegion , cleanupCacheName , stateSlot ) )
hoistEmission = pluck . beginHoistedRegion ( )
e (
("%s[%d]=function(%s%s)")

: format ( cleanupCacheName , stateSlot , stateFrame , variadic and ",..." or "" )
)
else
e (
("}; local %s=%s[%d]; if not %s then %s=function(%s%s)")

: format (
stateRegion ,
cleanupCacheName ,
stateSlot ,
stateRegion ,
stateRegion ,
stateFrame ,
variadic and ",..." or ""
)
)
end
emitDepth . pushCaptureFrame ( captures , stateFrame )
else
e (
("do local %s=0; local ") : format ( count ) ,
( x . startTok or x . withTok ) and ( x . startTok or x . withTok ) . line or sourceLine ( x )
)
e ( table . concat ( owners , "," ) )
for j = 1 , # ( x . bindings or { } ) do
if active [ j ] then
e ( ("; local %s=false") : format ( active [ j ] ) )
end
for _ , field in ipairs ( fieldActiveOrder [ j ] or { } ) do
e ( ("; local %s=false") : format ( fieldActive [ j ] [ field ] ) )
end
end
pluck . loweredFunction (
("; local %s,%s,%s=%s(function(%s)")

: format ( ok , tag , payload , cleanupGlobals . xpcall , variadic and "..." or "" ) ,
nil ,
pluck . reasons . region
)
end
cleanupStack [ # cleanupStack + 1 ] = ctx











local function emitAcquired ( binding , expr ) 
emit ( expr )
local move = ownershipMoveOf ( expr )

return move and activeFlag ( move ) or nil
end

local function activateValue ( j , binding , value ) 
e ( ("%s=") : format ( owners [ j ] ) , sourceLine ( binding . expr ) )
e ( value )
e ( ("; %s=%d;") : format ( count , j ) )
if active [ j ] then
e ( (" %s=true;") : format ( active [ j ] ) )
end
for _ , field in ipairs ( fieldActiveOrder [ j ] or { } ) do
e ( (" %s=true;") : format ( fieldActive [ j ] [ field ] ) )
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
local literal = type ( constant ) == "string" and ("%q") : format ( constant )
or constant == nil and "nil"
or tostring ( constant )
parts [ # parts + 1 ] = ("%s==%s") : format ( name , literal )
end
clauses [ # clauses + 1 ] = "(" .. table . concat ( parts , " and " ) .. ")"
end

return table . concat ( clauses , " or " )
end




local function liftSwitches ( expr ) 
if expr and not emitDepth . switchTemps [ expr ] and emitDepth . switchContains ( expr ) then
emitDepth . lowerSwitches ( expr )
end
end

local function activate ( j , binding , deferName ) 
local value = nextTemp ( )
liftSwitches ( binding . expr )
e ( ("local %s=") : format ( value ) , sourceLine ( binding . expr ) )
local cleared = emitAcquired ( binding , binding . expr )
e ( ";" )
if cleared then
e ( (" %s=false;") : format ( cleared ) )
end
activateValue ( j , binding , value )
if not deferName then
e ( (" %s %s=%s;") : format ( binding . isConst and "const" or "local" , binding . name . text , owners [ j ] ) )
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
liftSwitches ( expr )
if exprIndex == # exprs and # names > # exprs then
local packed = nextTemp ( )
e ( ("local %s=%s(") : format ( packed , cleanupPackName ) , sourceLine ( expr ) )
local cleared = emitAcquired ( bySlot [ exprIndex ] , expr )
e ( ");" )
if cleared then
e ( (" %s=false;") : format ( cleared ) )
end
for nameIndex = exprIndex , # names do
staged [ nameIndex ] = ("%s[%d]") : format ( packed , nameIndex - exprIndex + 1 )
end
else
local value = nextTemp ( )
e ( ("local %s=") : format ( value ) , sourceLine ( expr ) )
local cleared = emitAcquired ( bySlot [ exprIndex ] , expr )
e ( ";" )
if cleared then
e ( (" %s=false;") : format ( cleared ) )
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
e ( (" %s=%s;") : format ( active [ j ] , activationCondition ( binding ) or "false" ) )
end
end
end
elseif item . bindings then




for _ , binding in ipairs ( item . bindings ) do
activate ( bindingIndex [ binding ] , binding , true )
end
for _ , binding in ipairs ( item . bindings ) do
e (
(" %s %s=%s;")

: format (
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
if x . repeatCondition then
e ( pluck . separator ( ) )
emitDepth . beginCondition ( x . repeatConditionHeader )
emitDepth . lowerSwitches ( x . repeatCondition )
e ( ("%s=") : format ( x . repeatConditionTemp ) , sourceLine ( x . repeatCondition ) )
emit ( x . repeatCondition )
emitDepth . endCondition ( x . repeatConditionHeader )
end
if stateFrame then
if hoist then
e ( "end; return \"normal\" end;" )
pluck . saveHoistedRegion ( hoistEmission )
else
e (
("end; return \"normal\" end; %s[%d]=%s end;")

: format ( cleanupCacheName , stateSlot , stateRegion )
)
end
emitDepth . popCaptureFrame ( )
e (
("const %s,%s,%s=%s(%s,%s,%s%s);")

: format (
ok ,
tag ,
payload ,
cleanupGlobals . xpcall ,
stateRegion ,
cleanupIdName ,
stateFrame ,
variadic and ",..." or ""
)
)
for index , definition in ipairs ( captures ) do
if captureWrites [ definition ] then
e ( ("%s=%s[%d];") : format ( definition . token . text , stateFrame , index ) )
end
end
else
e ( ("end; return \"normal\" end,%s%s);") : format ( cleanupIdName , variadic and ",..." or "" ) )
end
cleanupStack [ # cleanupStack ] = nil
end
e ( ("local %s={}; local %s=0;") : format ( cleanupError , hasCleanupError ) , x . endTok and x . endTok . line or nil )
for j = # ( x . bindings or { } ) , 1 , -1 do
local binding = x . bindings [ j ]

local function emitProtected ( cleanup , value , fieldName ) 
local resolvedField = cleanup . kind == "field" and fieldActive [ j ] and fieldActive [ j ] [ cleanup . field ]
or fieldName
if resolvedField then
e ( ("if %s then ") : format ( resolvedField ) )
end
local call = protectedCleanupCall ( cleanup , value , cleanupGlobals . pcall )
if call then
local cok , cerr = nextTemp ( ) , nextTemp ( )
e ( ("local %s,%s=%s;") : format ( cok , cerr , call ) )
e (
(" if not %s then %s=%s+1; %s[%s]=%s end;")

: format ( cok , hasCleanupError , hasCleanupError , cleanupError , hasCleanupError , cerr )
)
end
if resolvedField then
e ( "end;" )
end
end

if binding . statementOwners then
e ( ("if %s>=%d then ") : format ( count , j ) )
for ownerIndex = # binding . statementOwners , 1 , -1 do
local owner = binding . statementOwners [ ownerIndex ]
local value = ("%s[%d]") : format ( owners [ j ] , ownerIndex )
e (
("if %s[-%d]%s then ")

: format ( owners [ j ] , ownerIndex , owner . optional and ( " and " .. value .. "~=nil" ) or "" )
)
for _ , cleanup in ipairs ( owner . cleanups or { } ) do
emitProtected ( cleanup , value )
end
e ( "end;" )
end
e ( "end;" )
else
local present = binding . automaticOwner and binding . automaticOwner . optional
if active [ j ] then
e (
("if %s>=%d and %s%s then ")

: format ( count , j , active [ j ] , present and ( " and " .. owners [ j ] .. "~=nil" ) or "" )
)
else
e ( ("if %s>=%d%s then ") : format ( count , j , present and ( " and " .. owners [ j ] .. "~=nil" ) or "" ) )
end
for _ , cleanup in ipairs ( binding . ownerCleanups or { } ) do
emitProtected ( cleanup , owners [ j ] )
end
e ( "end;" )
end
end
e (
("if not %s then if %s>0 then %s(%s(%s,%s,1),0) else %s(%s,0) end end;")

: format (
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
("if %s>0 then if %s>1 then %s(%s(%s[1],%s,2),0) else %s(%s[1],0) end end;")

: format (
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
if parent and parent . functionDepth ~= ctx . functionDepth then
parent = nil
end
e ( ("if %s==\"return\" then ") : format ( tag ) )
if parent then
e ( ("return \"return\",%s") : format ( payload ) )
else
e ( ("return %s(%s,1,%s.n)") : format ( cleanupGlobals . unpack , payload , payload ) )
end
e ( " end;" )
if ctx . breakExit then
e ( ("if %s==\"break\" then ") : format ( tag ) )
if parent and ctx . entryLoopDepth <= parent . entryLoopDepth then
parent . breakExit = true
e ( "return \"break\"" )
else
emitDepth . valueControl ( "break" )
end
e ( " end;" )
end
if ctx . continueExit then
e ( ("if %s==\"continue\" then ") : format ( tag ) )
if parent and ctx . entryLoopDepth <= parent . entryLoopDepth then
parent . continueExit = true
e ( "return \"continue\"" )
else
emitDepth . valueControl ( "continue" )
end
e ( " end;" )
end
local conditionTags = { }
for conditionTag in pairs ( ctx . conditionExits or { } ) do
conditionTags [ # conditionTags + 1 ] = conditionTag
end
table . sort ( conditionTags )
for _ , conditionTag in ipairs ( conditionTags ) do
local completion = ctx . conditionExits [ conditionTag ]
e ( ("if %s==%q then ") : format ( tag , conditionTag ) )
emitDepth . conditionControl ( completion . header , completion . kind )
e ( " end;" )
end
local valueTags = { }
for valueTag in pairs ( ctx . valueExits or { } ) do
valueTags [ # valueTags + 1 ] = valueTag
end
table . sort ( valueTags )
for _ , valueTag in ipairs ( valueTags ) do
e ( ("if %s==%q then ") : format ( tag , valueTag ) )
emitDepth . valueExit ( ctx . valueExits [ valueTag ] , nil , payload )
e ( " end;" )
end
local gotoTargets = { }
for target in pairs ( ctx . gotos ) do
gotoTargets [ # gotoTargets + 1 ] = target
end
table . sort ( gotoTargets )
for _ , target in ipairs ( gotoTargets ) do
e ( ("if %s==%q then ") : format ( tag , "goto:" .. target ) )
if parent and not parent . labels [ target ] then
parent . gotos [ target ] = true
e ( ("return %q") : format ( "goto:" .. target ) )
else
e ( "goto " .. target )
end
e ( " end;" )
end
e ( "end" )
if hoist then
pluck . finishHoistedRegion ( hoistEmission )
hoist . done = true
end

elseif kind == "returnStmt" and x . indexedViewReturnTransport then
local producer = x . indexedViewReturnTransport . producer
local root = producer . producer
local producerKind = root and root . kind
e ( "return " , sourceLine ( x ) )
emit ( producer . source )
e ( ",0," )
if producerKind == "string" then
e ( "#" )
emit ( producer . source )
elseif producerKind == "fixed-carray" then
emit ( producer . count )
elseif producerKind == "heap" or producerKind == "soa" then
emit ( producer . source )
e ( ".count" )
else
if pluck . storage . enabled then
pluck . needRuntimeEffect ( "runtime.cstorage" )
e ( pluck . storage . name .. ".boundedCount(" )
emit ( producer . source )
e ( "," )
end
e ( compilerModuleName ( "nupp.mem.indexed" ) .. "._rootCount(" )
emit ( producer . count )
local message = root . descriptor and root . descriptor . writable and "write span count cannot be negative"
or "span count cannot be negative"
e ( (",%q)") : format ( message ) )
if pluck . storage . enabled then
e ( ")" )
end
end

elseif kind == "returnStmt" and pluck . currentRegion ( ) then
emitPackedReturn ( pluck . currentRegion ( ) , x )

elseif kind == "returnStmt" and x . constructorReturn then
e ( "do return " .. assert ( emitDepth . constructorReturnName ) .. " end" , sourceLine ( x ) )

elseif kind == "returnStmt" and emitDepth . returnsConstruction ( x ) then





e ( "return (" , sourceLine ( x ) )
emit ( x . exprs [ 1 ] )
e ( ")" )

elseif ( kind == "breakStmt" or kind == "continueStmt" )
and pluck . currentRegion ( )
and emitDepth . loop <= pluck . currentRegion ( ) . entryLoopDepth
then
local completion = kind == "breakStmt" and "break" or "continue"
pluck . currentRegion ( ) [ completion .. "Exit" ] = true
e ( ("return %q") : format ( completion ) , sourceLine ( x ) )

elseif kind == "breakStmt" or kind == "continueStmt" then
local loopWrapper = emitDepth . loopWrappers [ # emitDepth . loopWrappers ]
if loopWrapper and loopWrapper . action then
pluck . loopExit ( loopWrapper , kind == "breakStmt" and "break" or "continue" , sourceLine ( x ) )
else
emitChildren ( x )
end

elseif kind == "gotoStmt" and pluck . currentRegion ( ) and not pluck . currentRegion ( ) . labels [ x . name . text ] then
local ctx = pluck . currentRegion ( )
ctx . gotos [ x . name . text ] = true
e ( ("return %q") : format ( "goto:" .. x . name . text ) , sourceLine ( x ) )

elseif kind == "forinStmt" and x . numericIpairs then
local operand = x . numericIpairs . operand
local names = x . names or { }



local index = names [ 1 ] and names [ 1 ] . text or nextTemp ( )
local line = sourceLine ( x )
e ( ("for %s=1,%d do") : format ( index , x . numericIpairs . length ) , line )
if names [ 2 ] then
e ( ("local %s=") : format ( names [ 2 ] . text ) )
emit ( operand )
e ( ("[%s];") : format ( index ) )
end
for j = 3 , # names do
e ( ("local %s=nil;") : format ( names [ j ] . text ) )
end
local loopWrapper = { }
if pluck . loopNeedsWrapper ( x ) then
loopWrapper . action = nextTemp ( )
e ( ("local %s;repeat") : format ( loopWrapper . action ) )
end
emitDepth . loopWrappers [ # emitDepth . loopWrappers + 1 ] = loopWrapper
emitDepth . loop = emitDepth . loop + 1
emitDepth . loopNodes [ # emitDepth . loopNodes + 1 ] = x
if x . body then
emit ( x . body )
end
emitDepth . loopNodes [ # emitDepth . loopNodes ] = nil
emitDepth . loop = emitDepth . loop - 1
emitDepth . loopWrappers [ # emitDepth . loopWrappers ] = nil
if loopWrapper . action then
e ( ("until true;if %s==\"break\" then break end;") : format ( loopWrapper . action ) )
emitDepth . propagateValueLoop ( )
end
local endTok = pluck . endToken ( x )
e ( "end" , endTok and endTok . line or nil )
finishConcatBuffer ( x , endTok and endTok . line or nil )
emitDepth . propagateValueLoop ( )

elseif kind == "whileStmt" or kind == "fornumStmt" or kind == "forinStmt" or kind == "repeatStmt" then
if kind == "fornumStmt" then
emitDepth . lowerValues ( { x . start , x . stop , x . step } )
elseif kind == "forinStmt" then
emitDepth . lowerValues ( x . exprs or { } )
end
emitDepth . soa . openLoop ( x )
local loopWrapper = { }
local blockWhile = kind == "whileStmt" and emitDepth . switchContains ( x . cond )
local header = nil
if ( kind == "whileStmt" or kind == "repeatStmt" ) and emitDepth . switchContains ( x . cond ) then
header = {
action = nextTemp ( ) ,
controls = { } ,
loopDepth = emitDepth . loop ,
functionDepth = emitDepth . fn ,
frames = # emitDepth . valueBlocks ,
cleanupDepth = # cleanupStack
}
x . blockCondition = header
loopWrapper . blockCondition = header
e ( "local " .. header . action .. ";" , sourceLine ( x ) )
end
if kind == "repeatStmt" then
local body = x . body
local hasAutomaticCleanup = body and body . automaticDirect ~= nil
for _ , stat in ipairs ( body and body . stats or { } ) do
hasAutomaticCleanup = hasAutomaticCleanup or stat . automaticOwners and # stat . automaticOwners > 0
end
if hasAutomaticCleanup then
x . cleanupConditionTemp = nextTemp ( )
e ( ("local %s;") : format ( x . cleanupConditionTemp ) , sourceLine ( x ) )
end
end
if pluck . loopNeedsWrapper ( x ) then
loopWrapper . action = nextTemp ( )



if kind == "repeatStmt" and x . cond and not x . cleanupConditionTemp then
loopWrapper . untilFlag = nextTemp ( )
loopWrapper . untilCond = x . cond
end
end
local lastLine = nil
for _ , child in ipairs ( x ) do
if child == x . body then
if blockWhile then
emitDepth . beginCondition ( header )
emitDepth . lowerSwitches ( x . cond )
e ( "if not (" )
emit ( x . cond )
e ( ") then break end;" )
emitDepth . endCondition ( header )
end
if loopWrapper . untilFlag then
e ( ("local %s,%s;repeat") : format ( loopWrapper . action , loopWrapper . untilFlag ) , sourceLine ( child ) )
elseif loopWrapper . action then
e ( ("local %s;repeat") : format ( loopWrapper . action ) , sourceLine ( child ) )
end
emitDepth . soa . beginIteration ( x )
emitDepth . loopWrappers [ # emitDepth . loopWrappers + 1 ] = loopWrapper
emitDepth . loop = emitDepth . loop + 1
emitDepth . loopNodes [ # emitDepth . loopNodes + 1 ] = x
emit ( child )
if kind == "repeatStmt" and not loopWrapper . untilFlag and not x . cleanupConditionTemp then
emitDepth . beginCondition ( header )
emitDepth . lowerSwitches ( x . cond )
emitDepth . endCondition ( header )
end
if loopWrapper . untilFlag then
e ( pluck . loopUntilTest ( loopWrapper ) )
end
emitDepth . loopNodes [ # emitDepth . loopNodes ] = nil
emitDepth . loop = emitDepth . loop - 1
emitDepth . loopWrappers [ # emitDepth . loopWrappers ] = nil
emitDepth . soa . endIteration ( x )
if loopWrapper . action then
e ( ("until true;if %s==\"break\" then break end;") : format ( loopWrapper . action ) )
emitDepth . propagateValueLoop ( )
if header then
e ( "if " .. header . action .. " then break end;" )
end
end
elseif child == x . cond and blockWhile then
e ( "true" , sourceLine ( child ) )
elseif child == x . cond and x . cleanupConditionTemp then
e ( x . cleanupConditionTemp , sourceLine ( child ) )
elseif child == x . cond and loopWrapper . untilFlag then
e ( loopWrapper . untilFlag , sourceLine ( child ) )
else
emit ( child )
end
if cst . isToken ( child ) then
lastLine = child . line
end
end


finishConcatBuffer ( x , lastLine )
emitDepth . soa . closeLoop ( x , lastLine )
if header then
for _ , completion in ipairs ( { "break" , "continue" } ) do
if header . controls [ completion ] then
e ( ("if %s==%q then ") : format ( header . action , completion ) )
emitDepth . valueControl ( completion )
e ( " end;" )
end
end
end
emitDepth . propagateValueLoop ( )

elseif kind == "funcbody" then
emitDepth . fn = emitDepth . fn + 1
local openedActivation = false
if x . varargParam then
for _ , child in ipairs ( x ) do
if child == x . body then
emitDepth . beginActivation ( )
openedActivation = true
if coverageOn then
coverageHit ( "function" , x )
end
e ( ("local %s = { n = _G.select(\"#\", ...), ... }") : format ( x . varargParam . name . text ) )
end
if emitDepth . hoist and emitDepth . hoist . done and child == emitDepth . hoist . endTok then
pluck . skipHoistedEnd ( child . line )
else
emit ( child )
end
end
else
for _ , child in ipairs ( x ) do
if child == x . body then
emitDepth . beginActivation ( )
openedActivation = true
if coverageOn then
coverageHit ( "function" , x )
end
end
if emitDepth . hoist and emitDepth . hoist . done and child == emitDepth . hoist . endTok then
pluck . skipHoistedEnd ( child . line )
else
emit ( child )
end
end
end
if openedActivation then
emitDepth . endActivation ( )
end
emitDepth . fn = emitDepth . fn - 1

elseif kind == "moduleStmt" then
return

elseif kind == "exportStmt" then
if x . value then
e ( ("local %s=") : format ( emitDepth . exportAssignmentValueName ) , sourceLine ( x ) )
emit ( x . value )
e ( (";%s=%s") : format ( emitDepth . exportTableName , emitDepth . exportAssignmentValueName ) )
return
end
local stat = x . stat
if stat then
emit ( stat )
end
while stat and stat . kind == "pragmaStmt" do
stat = stat . stat
end
if not stat or stat . comptimeFunction or stat . comptimeTok or stat . isAnnotationDefinition then
return
end
local names = { }
if stat . kind == "localFuncStmt" then
names [ 1 ] = stat . name and stat . name . text
elseif stat . kind == "funcStmt" then
names [ 1 ] = stat . name and stat . name . base and stat . name . base . text
elseif stat . kind == "localStmt" then
for _ , name in ipairs ( stat . names or { } ) do
names [ # names + 1 ] = name . text
end
elseif stat . kind == "recordDecl" and ( stat . declKind == "record" or stat . declKind == "struct" ) then
names [ 1 ] = stat . name and stat . name . text
end
for _ , name in ipairs ( names ) do
if name then
e ( (";%s[%q]=%s") : format ( emitDepth . exportTableName , name , name ) , sourceLine ( stat ) )
end
end

elseif kind == "localFuncStmt" and x . exported then
if x . comptimeFunction or x . comptimeTok then
return
end
e ( ( x . name and x . name . text or "__nuppMissing" ) .. "=function" , sourceLine ( x ) )
if x . body then
local previousHoist = emitDepth . hoist
emitDepth . hoist = pluck . hoistDeclaration ( x )
emit ( x . body )
emitDepth . hoist = previousHoist
end
for _ , specialization in ipairs ( x . constSpecializations or { } ) do
pluck . constSpecialize . emitSpecialization ( x , specialization )
end
pluck . constSpecialize . emitRegistrations ( x )

elseif kind == "localFuncStmt" then
if x . comptimeFunction or x . comptimeTok then
return
end
local dispatch = pluck . hotDispatch
local planned = dispatch and dispatch . byNode [ x ] or nil
if dispatch and planned then
dispatch . emit ( planned )
else
local previousHoist = emitDepth . hoist
emitDepth . hoist = pluck . hoistDeclaration ( x )
emitChildren ( x )
emitDepth . hoist = previousHoist
end
for _ , specialization in ipairs ( x . constSpecializations or { } ) do
pluck . constSpecialize . emitSpecialization ( x , specialization )
end
pluck . constSpecialize . emitRegistrations ( x )
pluck . emitRegistrations ( x . name and x . name . cleanupRegistrations , sourceLine ( x ) , nil , x . name and x . name . text )

elseif kind == "funcStmt" and x . exported and x . name and x . name . base and # x . name == 1 and not x . name . method then
e ( x . name . base . text .. "=function" , sourceLine ( x ) )
if x . body then
local previousHoist = emitDepth . hoist
emitDepth . hoist = pluck . hoistDeclaration ( x )
emit ( x . body )
emitDepth . hoist = previousHoist
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
local previousHoist = emitDepth . hoist
emitDepth . hoist = not x . name . method and pluck . hoistDeclaration ( x ) or nil
if emitDepth . hoist then


local wrapper = nextTemp ( )
e ( ("do local %s=function") : format ( wrapper ) , sourceLine ( x ) )
emit ( x . body )
emit ( x . name )
e ( ("=%s; end") : format ( wrapper ) )
else
emitChildren ( x )
end
emitDepth . hoist = previousHoist
end




for _ , name in ipairs ( x . name or { } ) do
pluck . emitRegistrations (
name . cleanupRegistrations ,
sourceLine ( x ) ,
nil ,
( cst . textOf ( x . name ) : gsub ( ":" , "." ) )
)
end

elseif kind == "annotationApply" then

return

elseif kind == "pragmaStmt" then
pluck . emitRegistrations ( x . cleanupRegistrations , sourceLine ( x ) , false )
if x . stat then
emit ( x . stat )
end
pluck . emitRegistrations ( x . cleanupRegistrations , sourceLine ( x ) , true )

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
e ( ("%s(%d,%d)") : format ( name , x . presize . narr , x . presize . nhash ) , sourceLine ( x ) )

elseif kind == "param" then

if x . indexedViewParameterTransport then
local view = x . indexedViewParameterTransport
view . anchorName = view . anchorName or nextTemp ( )
view . offsetName = view . offsetName or nextTemp ( )
view . countName = view . countName or nextTemp ( )
e ( ("%s,%s,%s") : format ( view . anchorName , view . offsetName , view . countName ) , sourceLine ( x ) )
elseif x . vararg then
e ( "..." , sourceLine ( x ) )
elseif x . name then
emit ( x . name )
else
emitChildren ( x )
end

elseif kind == "call" and x . soaLayout and x . soaOperation then
local moduleName = compilerModuleName ( "nupp.mem.soa" )
local args = x . args and x . args . exprs or { }
local line = sourceLine ( x )
if x . soaOperation == "allocate" then
local elementName , countName = nextTemp ( ) , nextTemp ( )
e (
("(function(%s,%s)return %s._allocate(%s,%s,")

: format ( elementName , countName , moduleName , elementName , countName ) ,
line
)
emitRuntimeLayout ( x . soaLayout , line , function ( ) 
e ( elementName )
end )
e ( ")end)(" )
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" )
end
e ( "," )
if args [ 2 ] then
emit ( args [ 2 ] )
else
e ( "nil" )
end
e ( ")" )
else
e ( moduleName .. "._layout(" , line )
emitRuntimeLayout ( x . soaLayout , line , function ( ) 
if args [ 1 ] then
emit ( args [ 1 ] )
else
e ( "nil" )
end
end )
e ( ")" )
end
return

elseif kind == "call" and x . virtualIndexedView and x . virtualIndexedView . kind == "root" then
local view = x . virtualIndexedView
if view . transport then
if not view . transportEmission then
error ( "transported indexed view was emitted outside its binding" )
end
emitChildren ( x )
return
end
local producerKind = view . producer and view . producer . kind
local moduleName = compilerModuleName ( "nupp.mem.indexed" )
if producerKind == "string" then
e ( "#" .. view . anchorName , sourceLine ( x ) )
elseif producerKind == "fixed-carray" then
emit ( view . count )
else
if pluck . storage . enabled then
pluck . needRuntimeEffect ( "runtime.cstorage" )
e ( pluck . storage . name .. ".boundedCount(" .. view . anchorName .. "," , sourceLine ( x ) )
end
e ( moduleName .. "._rootCount(" , sourceLine ( x ) )
emit ( view . count )
local message = view . descriptor and view . descriptor . writable and "write span count cannot be negative"
or "span count cannot be negative"
e ( (",%q)") : format ( message ) )
if pluck . storage . enabled then
e ( ")" )
end
end
return

elseif x . soaFieldProjection and not x . virtualIndexedView then
emit ( x . obj )
e ( (":fieldBySlot(%d)") : format ( x . soaFieldProjection . ordinal ) , sourceLine ( x ) )
return

elseif x . soaFieldProjection and x . virtualIndexedView then
emitDepth . view . count ( x . virtualIndexedView . source )
return

elseif kind == "methodCall" and x . virtualIndexedView then
local view = x . virtualIndexedView
if view . kind == "root" then
e ( view . anchorName .. ".count" , sourceLine ( x ) )
elseif view . kind == "slice" then
local moduleName = compilerModuleName ( "nupp.mem.indexed" )
e ( moduleName .. "._sliceFinish(" , sourceLine ( x ) )
emitDepth . view . count ( view . source )
e ( "," )
e ( view . firstName )
e ( "," )
if view . last then
emit ( view . last )
else
e ( "nil" )
end
local adapter = view . descriptor and view . descriptor . adapter or "span"
local writable = view . descriptor and view . descriptor . writable
local message = adapter == "soa" and "SoA slice out of bounds"
or writable and "write span slice out of bounds"
or "span slice out of bounds"
e ( (",%q)") : format ( message ) )
else
emitDepth . view . count ( view . source )
end
return

elseif kind == "dotIndex" and x . soaField then
local row = x . obj
local view = row and row . obj
if view and row . expr then
if emitDepth . soa . boundSlot ( view , x . soaField . ordinal , row . expr ) then
return
elseif emitDepth . view . info ( view ) then
emitDepth . view . soaSlot ( view , x . soaField . ordinal , row . expr , not emitDepth . soa . unchecked ( row ) )
elseif view . kind == "name" then





emit ( view )
e ( (".columns[%d][") : format ( x . soaField . ordinal ) , sourceLine ( x ) )
if emitDepth . soa . unchecked ( row ) then
emit ( view )
e ( ".offset+" )
emit ( row . expr )
e ( "-1]" )
else
emit ( view )
e ( ":checkedIndex(" )
emit ( row . expr )
e ( ")]" )
end
else
local viewName , indexName = nextTemp ( ) , nextTemp ( )
e (
("(function(%s,%s)return %s.columns[%d][%s:checkedIndex(%s)] end)(")

: format ( viewName , indexName , viewName , x . soaField . ordinal , viewName , indexName ) ,
sourceLine ( x )
)
emit ( view )
e ( "," )
emit ( row . expr )
e ( ")" )
end
else
emitChildren ( x )
end
return

elseif kind == "bracketIndex" and x . soaRow then
local view = emitDepth . view . info ( x . obj )
local element = x . soaRow . element
if view and x . indexedDirectAccess and element and element . tag == "nominal" then
emitDepth . view . root ( x . obj )
e ( ".element({" , sourceLine ( x ) )
for ordinal , field in ipairs ( element . fieldOrder or { } ) do
if ordinal > 1 then
e ( "," )
end
e ( field .. "=" )
emitDepth . view . soaSlot ( x . obj , ordinal , x . expr )
end
e ( "})" )
else
emit ( x . obj )
e ( ":get(" , sourceLine ( x ) )
emit ( x . expr )
e ( ")" )
end
return

elseif kind == "call" and x . layoutOf then




local line = sourceLine ( x )
emitRuntimeLayout ( x . layoutOf , line , function ( ) 
emit ( x . args and x . args . exprs and x . args . exprs [ 1 ] or x . obj )
end )
return

elseif ( kind == "dotIndex" or kind == "name" ) and x . qualifiedModule then
e ( compilerModuleName ( x . qualifiedModule ) , sourceLine ( x ) )
for _ , member in ipairs ( x . qualifiedMembers or { } ) do
e ( "." .. member )
end

elseif kind == "dotIndex" and x . compilerModule then


e ( compilerModuleName ( x . compilerModule ) , sourceLine ( x ) )

elseif kind == "localStmt"
and # ( x . names or { } ) == 1
and # ( x . exprs or { } ) == 1
and x . names [ 1 ] . definition
and x . names [ 1 ] . definition . virtualIndexedView
and x . names [ 1 ] . definition . virtualIndexedView . kind == "alias"
then
local view = x . names [ 1 ] . definition . virtualIndexedView
e ( ( x . isConst and "const " or "local " ) .. x . names [ 1 ] . text .. "=" , sourceLine ( x ) )
emitDepth . view . count ( view . source )

elseif kind == "localStmt"
and # ( x . names or { } ) == 1
and # ( x . exprs or { } ) == 1
and x . exprs [ 1 ] . virtualIndexedView
and x . exprs [ 1 ] . virtualIndexedView . kind == "root"
then
local view = x . exprs [ 1 ] . virtualIndexedView
view . anchorName = view . anchorName or nextTemp ( )
if view . transport then
view . offsetName = view . offsetName or nextTemp ( )
e ( ("const %s,%s,%s=") : format ( view . anchorName , view . offsetName , x . names [ 1 ] . text ) , sourceLine ( x ) )
view . transportEmission = true
emit ( x . exprs [ 1 ] )
view . transportEmission = nil
else
e ( "const " .. view . anchorName .. "=" , sourceLine ( x ) )
emit ( view . source )
e ( ";" )
emitChildren ( x )
end

elseif kind == "localStmt"
and # ( x . names or { } ) == 1
and # ( x . exprs or { } ) == 1
and x . exprs [ 1 ] . virtualIndexedView
and x . exprs [ 1 ] . virtualIndexedView . kind == "slice"
then
local view = x . exprs [ 1 ] . virtualIndexedView
view . firstName = view . firstName or nextTemp ( )
e ( "const " .. view . firstName .. "=" , sourceLine ( x ) )
emit ( view . first )
e ( ";" )
emitChildren ( x )

elseif kind == "emptyStmt" then




if x . separatesStatements and pluck . separator ( ) == ";" then
e ( ";" , sourceLine ( x ) )
end

elseif kind == "localStmt" and x . concatBuffer then


if not x . concatBuffer . elide then
emitChildren ( x )
end
e ( ("local %s = %s.newBuffer()") : format ( x . concatBuffer . name , concatBufferName ( ) ) , sourceLine ( x ) )

elseif kind == "assignStmt" and x . concatBuffer then







local pieces = x . concatBuffer . pieces
e ( ("%s:put(") : format ( x . concatBuffer . name ) , sourceLine ( x ) )
for j , piece in ipairs ( pieces ) do
if j > 1 then
e ( "," )
end
local single = piece . kind == "name"
or piece . kind == "string"
or piece . kind == "number"
or piece . kind == "paren"
or piece . kind == "binop"
if j == # pieces and not single then
e ( "(" )
emit ( piece )
e ( ")" )
else
emit ( piece )
end
end
e ( ")" )

else
emitChildren ( x )
end
end

planStructTags ( )


do
local function markSeparators ( node ) 
if type ( node ) ~= "table" or cst . isToken ( node ) then
return
end
local stats = node . stats
if type ( stats ) == "table" then
for index , stat in ipairs ( stats ) do
if type ( stat ) == "table" and stat . kind == "emptyStmt" then
local previous = stats [ index - 1 ]
stat . separatesStatements = previous ~= nil and previous . kind ~= "emptyStmt"
end
end
end
for _ , child in ipairs ( node ) do
markSeparators ( child )
end
end

markSeparators ( result . root )
end
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
for _ , activation in ipairs ( emitDepth . activationPlaceholders ) do
local replacement = activation . used and ("local %s;") : format ( activation . name ) or ""
code = code : gsub ( activation . marker : gsub ( "([^%w])" , "%%%1" ) , replacement , 1 )
end
if bytecodeBoundary ~= nil then



code = ("do local __nuppBytecodeBoundary=%q end;") : format ( bytecodeBoundary ) .. code
end
if declaredModuleName then
local migrationAssignment = cst . exportAssignment ( result . root ) ~= nil
local exportedFunctions = { }
local exportedFunctionTypes = { }
for _ , block in ipairs ( result . root . blocks or { } ) do
for _ , statement in ipairs ( block . stats or { } ) do
local actual = statement
while actual and ( actual . kind == "exportStmt" or actual . kind == "pragmaStmt" ) do
actual = actual . stat
end
if actual and actual . exported then
if actual . kind == "localFuncStmt" then
local fn = actual
if fn . name and not fn . comptimeTok and not fn . comptimeFunction then
local nameToken = fn . name
exportedFunctions [ # exportedFunctions + 1 ] = fn . name . text
exportedFunctionTypes [ fn . name . text ] = nameToken . definition and nameToken . definition . type
or nameToken . inferredType
end
elseif actual . kind == "funcStmt" then
local fn = actual
local fname = fn . name
if fname
and fname . kind == "funcname"
and fname . base
and not fn . comptimeTok
and not fn . comptimeFunction
then
local nameToken = fname . base
exportedFunctions [ # exportedFunctions + 1 ] = fname . base . text
exportedFunctionTypes [ fname . base . text ] = nameToken . definition and nameToken . definition . type
or nameToken . inferredType
end
end
end
end
end
table . sort ( exportedFunctions )
local exportedRecords


= { }

local function collectExportedRecords ( record , path ) 
if record . isAnnotationDefinition then
return
end
local nameToken = record . name
exportedRecords [
# exportedRecords + 1
] = {
path = path ,
type = record . hoistedType
or ( nameToken . definition and nameToken . definition . type or nameToken . inferredType ) ,
}
for _ , entry in ipairs ( record . entries or { } ) do
if entry . kind == "recordDecl" and entry . declKind == "record" then
collectExportedRecords ( entry , path .. "." .. entry . name . text )
end
end
end

for _ , block in ipairs ( result . root . blocks or { } ) do
for _ , statement in ipairs ( block . stats or { } ) do
local actual = statement
while actual and ( actual . kind == "exportStmt" or actual . kind == "pragmaStmt" ) do
actual = actual . stat
end
if actual
and actual . exported
and actual . kind == "recordDecl"
and actual . declKind == "record"
and actual . name
then
collectExportedRecords ( actual , actual . name . text )
end
end
end
table . sort ( exportedRecords , function ( left , right ) 
return left . path < right . path
end )
local exportedRecordByType = { }
for _ , record in ipairs ( exportedRecords ) do
if record . type ~= nil then
exportedRecordByType [ record . type ] = record
end
end
local instantiation = { }
for _ , name in ipairs ( exportedFunctions ) do
if emitDepth . spill then
emitDepth . spill . name ( name )
instantiation [
# instantiation + 1
] = ("%s[%q]=function(...) return %s(...) end;") : format ( emitDepth . exportTableName , name , name )
else
instantiation [
# instantiation + 1
] = ("local %s;%s[%q]=function(...) return %s(...) end;")

: format ( name , emitDepth . exportTableName , name , name )
end
end

local function primitiveWorkerTransfer ( resolved ) 
if resolved and ( resolved . tag == "number" or resolved . tag == "integer" ) then
return "number"
elseif resolved and resolved . tag == "string" then
return "string"
end

return nil
end

local function storedWorkerTransfer ( fieldType ) 
local kind = primitiveWorkerTransfer ( fieldType )
if kind == nil and fieldType . tag == "boolean" then
kind = "boolean"
end
if kind ~= nil then
return kind
end


if fieldType . tag ~= "union" or # ( fieldType . members or { } ) ~= 2 then
return nil
end
local inner = nil
for _ , member in ipairs ( fieldType . members ) do
if member . tag ~= "nil" then
if inner ~= nil then
return nil
end
inner = member
end
end
if inner == nil then
return nil
end
local innerKind = primitiveWorkerTransfer ( inner )
if innerKind == nil and inner . tag == "boolean" then
innerKind = "boolean"
end

return innerKind ~= nil and innerKind .. "?" or nil
end

local function recordWorkerTransfer ( resolved ) 
local exported = resolved and exportedRecordByType [ resolved ]
if exported == nil or resolved . tag ~= "nominal" or resolved . declKind ~= "record" then
return nil
end
local fields


= { }
for field , fieldType in pairs ( resolved . byname or { } ) do
local kind = storedWorkerTransfer ( fieldType )
if kind == nil then
return nil
end
fields [ # fields + 1 ] = { name = field , kind = kind }
end
table . sort ( fields , function ( left , right ) 
return left . name < right . name
end )
local address = declaredModuleName .. "\0" .. exported . path
local schemaParts = { address }
for _ , field in ipairs ( fields ) do
schemaParts [ # schemaParts + 1 ] = field . name
schemaParts [ # schemaParts + 1 ] = field . kind
end

return {
kind = "record" ,
address = address ,
schema = table . concat ( schemaParts , "\0" ) ,
path = exported . path ,
fields = fields ,
}
end

local function workerTransfer ( resolved ) 
return primitiveWorkerTransfer ( resolved ) or recordWorkerTransfer ( resolved )
end

local function workerTransferLiteral ( plan ) 
if type ( plan ) == "string" then
return ("%q") : format ( plan )
end
local fieldNames = { }
local fieldKinds = { }
for _ , field in ipairs ( plan . fields ) do
fieldNames [ # fieldNames + 1 ] = ("%q") : format ( field . name )
fieldKinds [ # fieldKinds + 1 ] = ("%q") : format ( field . kind )
end

return ("{kind=\"record\",schema=%q,address=%q,record=%s,fields={%s},types={%s}}")

: format ( plan . schema , plan . address , plan . path , table . concat ( fieldNames , "," ) , table . concat ( fieldKinds , "," ) )
end

local preparedFunctions



= { }
for _ , name in ipairs ( exportedFunctions ) do
local signature = exportedFunctionTypes [ name ]
local params = signature and signature . tag == "func" and signature . params or { }
local results = signature and signature . tag == "func" and signature . rets or { }
local input = signature and not signature . vararg and # params == 1 and workerTransfer ( params [ 1 ] ) or nil
local output = signature and # results == 1 and workerTransfer ( results [ 1 ] ) or nil
if input ~= nil and output ~= nil then
preparedFunctions [ # preparedFunctions + 1 ] = { name = name , input = input , output = output }
end
end
local sendableDefinitions = { }
for _ , literal in ipairs ( result . sendableLiterals or { } ) do
local savedOut , savedLine , savedLineStart = out , curLine , atLineStart
out , curLine , atLineStart = { } , 1 , true
local priorOutline = outliningSendable
outliningSendable = literal
emit ( literal )
outliningSendable = priorOutline
local body = table . concat ( out )
out , curLine , atLineStart = savedOut , savedLine , savedLineStart
local captures = { }
for _ , capture in ipairs ( literal . sendableCaptures or { } ) do
captures [ # captures + 1 ] = capture . name
end
local workersName = compilerModuleName ( "nupp.workers" )
sendableDefinitions [
# sendableDefinitions + 1
] = ("%s.__defineSendable(%q,%q,function(%s,...) return (%s)(...) end);")

: format ( workersName , declaredModuleName , literal . sendableMember , table . concat ( captures , "," ) , body )
end
local recordDefinitions = { }
if # exportedRecords > 0 then





local registry = reservedName ( "__nuppWorkerRecords" )
recordDefinitions [
1
] = ("local %s=_G.rawget(_G.nupp,\"__workerRecords\");if _G.type(%s)~=\"table\" then %s=_G.setmetatable({},{__mode=\"k\"});_G.rawset(_G.nupp,\"__workerRecords\",%s) end;")



: format ( registry , registry , registry , registry )
for _ , record in ipairs ( exportedRecords ) do
recordDefinitions [
# recordDefinitions + 1
] = ("%s[%s]=%q;") : format ( registry , record . path , declaredModuleName .. "\0" .. record . path )
end
end
local workerDefinitions = { }
if # preparedFunctions > 0 then
local registry = reservedName ( "__nuppWorkerSendables" )
workerDefinitions [
1
] = ("local %s=_G.rawget(_G.nupp,\"__workerSendables\");if _G.type(%s)~=\"table\" then %s=_G.setmetatable({},{__mode=\"k\"});_G.rawset(_G.nupp,\"__workerSendables\",%s) end;")



: format ( registry , registry , registry , registry )
for _ , prepared in ipairs ( preparedFunctions ) do
workerDefinitions [
# workerDefinitions + 1
] = ("%s[%s[%q]]={module=%q,member=%q,captures={values={},count=0},input=%s,output=%s};")

: format (
registry ,
emitDepth . exportTableName ,
prepared . name ,
declaredModuleName ,
prepared . name ,
workerTransferLiteral ( prepared . input ) ,
workerTransferLiteral ( prepared . output )
)
end
end
local loadsSpi = false
local visitedSpi = { }

local function inspectSpi ( node ) 
if type ( node ) ~= "table" or visitedSpi [ node ] or cst . isToken ( node ) then
return
end
visitedSpi [ node ] = true
loadsSpi = loadsSpi or node . spiInterface ~= nil
for _ , child in ipairs ( node ) do
inspectSpi ( child )
end
for _ , child in ipairs ( node . stats or { } ) do
inspectSpi ( child )
end
end

inspectSpi ( result . root )






local patching = hotState ~= nil and hotState . mode == "patch"
local prefix
if migrationAssignment then
prefix = ("local %s;local __nuppOk,__nuppWhy=pcall(function()") : format ( emitDepth . exportTableName )
elseif loadsSpi or patching then
prefix = ("local %s={};local __nuppOk,__nuppWhy=pcall(function()") : format ( emitDepth . exportTableName )
else
prefix = ("local %s={};package.loaded[%q]=%s;local __nuppOk,__nuppWhy=pcall(function()")

: format ( emitDepth . exportTableName , declaredModuleName , emitDepth . exportTableName )
end
local epilogue = patching
and (" end);if not __nuppOk then error(__nuppWhy,0) end;return %s") : format ( emitDepth . exportTableName )
or (" end);if not __nuppOk then package.loaded[%q]=nil;error(__nuppWhy,0) end;package.loaded[%q]=%s;return %s")


: format ( declaredModuleName , declaredModuleName , emitDepth . exportTableName , emitDepth . exportTableName )
local spill = emitDepth . spill
if spill then


local names = { }
for index , name in ipairs ( spill . order ) do
names [ index ] = ("[%q]=true") : format ( name )
end
local scope = spill . scopeName
prefix = prefix : gsub ( "pcall%(function%(%)$" , function ( ) 
return ("pcall((function(f) if _G.setfenv then _G.setfenv(f,%s) end return f end)(function(_ENV)")

: format ( scope )
end )
prefix = ("local %s;do local names={%s};%s=_G.setmetatable({},{__index=_G,__newindex=function(t,k,v) if names[k] then _G.rawset(t,k,v) else _G[k]=v end end}) end;")


: format ( scope , table . concat ( names , "," ) , scope ) .. prefix
epilogue = epilogue : gsub ( "^ end%);" , function ( ) 
return (" end),%s);") : format ( scope )
end )
end
code = prefix .. table . concat (
instantiation
) .. code .. table . concat (
recordDefinitions
) .. table . concat ( workerDefinitions ) .. table . concat ( sendableDefinitions ) .. epilogue
end








if # pluck . helpers . order > 0 then
local declarations = { }
for _ , helper in ipairs ( pluck . helpers . order ) do
declarations [
# declarations + 1
] = ("local %s = function(%s) %s end;") : format ( helper . name , helper . params , helper . body )
end
code = table . concat ( declarations ) .. code
end
if # constants . order > 0 or # constants . spilled > 0 then
local declarations = { }
for _ , constant in ipairs ( constants . order ) do
declarations [ # declarations + 1 ] = ("local %s=%s;") : format ( constant . name , constant . body )
end
if # constants . spilled > 0 then
declarations [ # declarations + 1 ] = ("local %s={};") : format ( constants . spillName )
for index , body in ipairs ( constants . spilled ) do
declarations [ # declarations + 1 ] = ("%s[%d]=%s;") : format ( constants . spillName , index , body )
end
end
code = table . concat ( declarations ) .. code
end
if needsCleanupRegistry then
local linked = {
("local %s=_G.__nuppCleanupRegistry;") : format ( cleanupRegistryName ) ,
("if %s==nil then %s={};_G.__nuppCleanupRegistry=%s end;")

: format ( cleanupRegistryName , cleanupRegistryName , cleanupRegistryName ) ,
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
] = ("local %s;%s=function(value) local cleanup=%s[%q];")

: format (
resolver . name ,
resolver . name ,
cleanupRegistryName ,
cleanup . key
) .. ("if cleanup==nil then return _G.error(%q) end;")

: format (
"Nupp cleanup provider is not loaded: " .. cleanup . key
) .. ("%s=cleanup;return cleanup(value) end;") : format ( resolver . name )
end
code = table . concat ( linked ) .. code
end


local installingManaged = ( result . declaredModuleName or result . moduleName ) == "nupp.runtime.managed"
if not installingManaged then
pluck . needRuntimeEffect ( "runtime.managed" )
end
local runtimeEffects = emittedFeatureEffects
local canSuspend = native . expand ( runtimeEffects ) [ "runtime.suspension" ] == true
local useYieldableCleanupCalls = false
local cleanupCoroutineCreate = "coroutine.create"
if needsCleanupRegions then
useYieldableCleanupCalls = yieldableXpcallName ~= nil and canSuspend
if useYieldableCleanupCalls then
cleanupCoroutineCreate = suspensionModule ( ) .. ".create"
end
end



if compilerModules [ "nupp.log#view" ] then
code = ("const %s = require(\"nupp.log\").forModule(%q); ")

: format ( compilerModules [ "nupp.log#view" ] , result . moduleName or filename or "?" ) .. code
end
local runtimeBootstrap = stdlib . bootstrap ( runtimeEffects , hotState ~= nil , installingManaged )
if pluck . storage . enabled and runtimeEffects [ "runtime.cstorage" ] then
runtimeBootstrap = runtimeBootstrap .. ("local %s=require(%q);")

: format ( pluck . storage . name , "nupp.runtime.storage" )
end
if needsCleanupRegions then





local yieldableCleanupPcall = useYieldableCleanupCalls and yieldablePcallName ~= nil

local names , values = { } , { }
for _ , name in ipairs ( { "pcall" , "xpcall" , "error" , "unpack" , "select" , "setmetatable" , "tostring" , "ipairs" } ) do
names [ # names + 1 ] = cleanupGlobals [ name ]
values [ # values + 1 ] = name == "xpcall" and yieldableXpcallName
or name == "pcall" and yieldableCleanupPcall and yieldablePcallName
or name == "unpack" and "(unpack or table.unpack)"
or name
end
code = ("local %s={}; ")

: format (
cleanupCacheName
) .. ("local function %s(...) return ")

: format (
cleanupPackName
) .. ("{n=%s(\"#\",...),...} end; ")

: format (
"select"
) .. (
useYieldableCleanupCalls
and ("local function %s(body,handler,...) local thread=%s(body);local input=%s(...);while true do local resumed=%s(coroutine.resume(thread,%s(input,1,input.n)));if not resumed[1] then return false,handler(resumed[2]) end;if coroutine.status(thread)==\"dead\" then return true,%s(resumed,2,resumed.n) end;input=%s(coroutine.yield(%s(resumed,2,resumed.n))) end end; ")





: format (
yieldableXpcallName ,
cleanupCoroutineCreate ,
cleanupPackName ,
cleanupPackName ,
"(unpack or table.unpack)" ,
"(unpack or table.unpack)" ,
cleanupPackName ,
"(unpack or table.unpack)"
)
or yieldableXpcallName
and ("local function %s(body,handler,...) local args=%s(...);return xpcall(function() return body(%s(args,1,args.n)) end,handler) end; ")


: format ( yieldableXpcallName , cleanupPackName , "(unpack or table.unpack)" )
or ""
) .. (
yieldableCleanupPcall
and ("local function %s(body,...) return %s(body,function(problem) return problem end,...) end; ")

: format ( yieldablePcallName , yieldableXpcallName )
or ""
) .. ("local %s=%s; ")

: format (
table . concat ( names , "," ) ,
table . concat ( values , "," )
) .. ("local function %s(value) return value end; ")

: format (
cleanupIdName
) .. ("local function %s(primary,errors,start) ")

: format ( cleanupFailureName ) .. "local secondary={} for i=start,#errors do " .. ("if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return %s(")





: format (
cleanupGlobals . setmetatable
) .. "{primary=primary,suppressed=secondary},{__tostring=function(v) " .. ("local text=%s(v.primary) for _,reason in %s(")

: format (
cleanupGlobals . tostring ,
cleanupGlobals . ipairs
) .. ("v.suppressed) do text=text..\"\\ncleanup: \"..%s(reason) ")

: format ( cleanupGlobals . tostring ) .. "end return text end}) end; " .. code
end



if result . implicitSideEffects and next ( result . implicitSideEffects ) then
local effects = { }
for moduleName in pairs ( result . implicitSideEffects ) do
effects [ # effects + 1 ] = moduleName
end
table . sort ( effects )
for j , moduleName in ipairs ( effects ) do
effects [ j ] = ("require(%q); ") : format ( moduleName )
end
code = table . concat ( effects ) .. code
end
if needsArrayCache then
code = "const __nuppArrayCache = {}; const function __nuppArray(ct) "
.. "local a = __nuppArrayCache[ct] if not a then "
.. "a = __nuppFfi.typeof(\"$[?]\", ct) __nuppArrayCache[ct] = a end "
.. "return a end; "
.. code
end
if needsCArrayIndex then
code = ("local function %s(i,n) if i%%1~=0 or i<0 or i>=n then ")

: format ( carrayIndexName ) .. "error('C array index out of bounds',2) end return i end; " .. code
end
if needsLibs then

















code = "const __nuppLibCache = {}; "
.. "const __nuppLibRoots = rawget(_G, '__nuppLibraryRoots') or {}; "
.. "rawset(_G, '__nuppLibraryRoots', __nuppLibRoots); "
.. "const function __nuppLib(n) "
.. "local l = __nuppLibCache[n] if not l then "
.. "local rel = n:match('^@(.+)$') "
.. "if rel then "
.. "local here = debug.getinfo(1, 'S').source:match('^@(.*)$') "
.. "local dir = here and here:match('^(.*)[/\\\\]') or '.' "
.. "local from = dir "
.. "for _ = 0, 8 do "
.. "local at = dir .. '/' .. rel "
.. "local probe = io.open(at, 'rb') "
.. "if probe then probe:close() l = __nuppFfi.load(at) break end "
.. "dir = dir .. '/..' "
.. "end "
.. "if not l then error('cannot find ' .. rel .. ' at or above ' .. from"
.. " .. '; the compiled library has to travel with the module that calls it', 0) end "
.. "else l = __nuppFfi.load(n) end "
.. "__nuppLibCache[n] = l __nuppLibRoots[l] = true end return l end; "
.. code
end
if needsCloneTab then





code = ("local function %s(t) local out = {} ")

: format (
cloneTabName
)
.. "for k, v in next, t do out[k] = v end "
.. "const mt = getmetatable(t) "
.. "if type(mt) == \"table\" then setmetatable(out, mt) end "
.. "return out end; "
.. code
end
if needsClearTab then
code = ("const %s = require(\"table.clear\"); ") : format ( clearTabName ) .. code
end
if needsNewTab then
code = ("const %s = require(\"table.new\"); ") : format ( newTabName ) .. code
end
if needsMetatypeOnce then



code = ("const %s = function(ct, mt) const ok, got = pcall(")

: format ( metatypeOnceName ) .. "__nuppFfi.metatype, ct, mt) if ok then return got end return ct end; " .. code
needsFfi = true
end
if # structTagOrder > 0 then



local forwards = { }
for _ , tag in ipairs ( structTagOrder ) do
forwards [ # forwards + 1 ] = ("pcall(__nuppFfi.cdef, \"struct %s;\"); ") : format ( tag )
end
code = table . concat ( forwards ) .. code
needsFfi = true
end
if needsLayout then




code = ("const %s = (function() const cache = setmetatable({}, {__mode = \"k\"}) return function(ct, name, spec, printed, ...) local hit = cache[ct] if hit then return hit end const nested = {...} local at = 0 const fields = {} for fname, ctype in spec:gmatch(\"([^:,]+):([^,]+)\") do local own local fieldType local shown = ctype if ctype:sub(1, 1) == \"$\" then at = at + 1 own = nested[at] shown = ctype:sub(2) const repeats = shown:match(\"%%[(%%d+)%%]$\") if repeats then fieldType = __nuppFfi.typeof(\"$ [\" .. repeats .. \"]\", own) else fieldType = __nuppFfi.typeof(own) end elseif ctype:sub(-1) == \"*\" then own = \"void *\" else own = ctype end if not fieldType then fieldType = __nuppFfi.typeof(own) end fields[#fields + 1] = {name = fname, ctype = shown, offset = __nuppFfi.offsetof(ct, fname), size = __nuppFfi.sizeof(fieldType), alignment = __nuppFfi.alignof(fieldType), pointerType = __nuppFfi.typeof(\"$ *\", fieldType)} end const size = __nuppFfi.sizeof(ct) for i = 1, #fields do const after = fields[i + 1] and fields[i + 1].offset or size fields[i].padding = after - fields[i].offset - fields[i].size end const layout = {name = name, size = size, alignment = __nuppFfi.alignof(ct), fields = fields, fingerprint = printed .. \"|\" .. size} cache[ct] = layout return layout end end)(); ")


























: format ( layoutName ) .. code
needsFfi = true
end
if needsSuspension then
code = ("const %s = require(\"nupp.suspension\"); ") : format ( suspensionName ) .. code
end
for _ , moduleName in ipairs ( compilerModuleOrder ) do


if moduleName ~= "nupp.log#view" then
code = ("const %s = require(%q); ") : format ( compilerModules [ moduleName ] , moduleName ) .. code
end
end
if runtimeBootstrap ~= "" then
code = runtimeBootstrap .. code
else
code = "_G.nupp=_G.nupp or {};" .. code
end






local inlineBitopBindings = "" local __nuppBuf_1 = __nuppBuffer.newBuffer()
for _ , name in ipairs ( INLINE_BITOPS ) do
local reserved = inlineBitopNames [ name ]
if reserved then
__nuppBuf_1:put( ( ("local %s=bit.%s;") : format ( reserved , name ) ) )
end
end inlineBitopBindings = __nuppBuf_1:tostring()
code = inlineBitopBindings .. code
if needsFfi then

code = "const __nuppFfi = require(\"ffi\"); " .. code
end
if coverageOn and coverageName then



code = ("local %s=_G.__nuppCoverage;if not %s then %s={hits={}};function %s.hit(p,i)local f=%s.hits[p]or{};%s.hits[p]=f;local k=tostring(i);f[k]=(f[k]or 0)+1 end;function %s.branch(p,i,v)local f=%s.hits[p]or{};%s.hits[p]=f;local k=tostring(i)..(v and ':true'or ':false');f[k]=(f[k]or 0)+1;return v end;_G.__nuppCoverage=%s end; ")





: format (
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
policies [ j ] = ("_G.__nuppHotReload.policy(%s,%q); ") : format ( hotState . slotsExpr , policy )
end
code = ("local %s=_G.__nuppHotReload.module(%q); ")

: format ( hotState . slotsExpr , hotState . module ) .. table . concat ( policies ) .. code
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




if not installingManaged and result . preludeRuntime and result . preludeRuntime ~= "" then




local quotedPrelude = ("%q") : format ( result . preludeRuntime ) : gsub ( "\n" , "n" )
code = ("_G.assert((_G.loadstring or _G.load)(%s,%q))();") : format ( quotedPrelude , "@nupp-prelude" ) .. code
end



















if loadstring then
local chunk , reason = loadstring ( code , "@" .. tostring ( filename or "generated" ) )
if not chunk then
local text = tostring ( reason )


local line = tonumber ( text : match ( "function at line (%d+)" ) ) or tonumber ( text : match ( "^[^:]*:(%d+):" ) ) or 0




local cap = text : match ( "more than (%d+) upvalues" )
local localCap = text : match ( "more than (%d+) local variables" )
if localCap and not spillsModuleScope and declaredModuleName and hot == nil then
spillNextModule = true
return gen . generate ( result , filename , coverage , hot , bytecodeBoundary , forcedEffects )
end





local levels = text : find ( "too many syntax levels" , 1 , true ) ~= nil
local registers = text : find ( "needs too many registers" , 1 , true ) ~= nil
local message , help
if cap then
message = ("this function captures more than %s names from around it, which is more than a Lua function can hold")


: format ( cap )
help = "pass some of them as arguments, or gather what it reads into one value and capture that"
elseif localCap then



message = ("this function declares more than %s local names, which is more than a Lua function can hold")

: format ( localCap )
help = "gather related values into a table, or split the module; at the top level every local, function and record counts, exported or not"

elseif levels then
message = "this nests expressions or blocks more than 200 levels deep, which is more than LuaJIT's parser accepts"

help = "name intermediate results with locals, or move an inner block into a function"
elseif registers then
message = "this function needs more registers than a Lua function has"
help = "split the expression or the function, or name intermediate results with locals"
else
message = "generated code does not load: " .. ( text : gsub ( "^[^:]*:%d+:%s*" , "" ) )
help = "this is a bug in the compiler rather than in this file; report it with the smallest source that reproduces it"

end


line = math . max ( line , 1 )
local offset , reached = 1 , 1
local source = result . source
while source and reached < line do
local newline = source : find ( "\n" , offset , true )
if not newline then
do break end
end
offset = newline + 1
reached = reached + 1
end
diag ( { line = line , col = 1 , offset = offset , text = "" } , "NUPP3005" , message , help )
end
end

if result . compat == "lua51" then
for _ , diagnostic in ipairs ( require ( "nupp.compiler.compat" ) . generated ( code , filename , result . tokens ) ) do
diags [ # diags + 1 ] = diagnostic
end
if needsCleanupRegions and canSuspend then
diag (
result . tokens and result . tokens [ 1 ] ,
"NUPP3015" ,
"Lua 5.1 cleanup cannot cross the effect closure: " .. require (
"nupp.compiler.compat"
) . suspensionPath ( runtimeEffects ) ,
"use a non-suspending cleanup dependency closure or remove the compatibility requirement"
)
end
end

return code , diags , metadata , emittedFeatureEffects , hotMetadata
end

local __nuppExportValue= gen ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.lua.gen"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.lua.gen"]=__nuppExports;return __nuppExports