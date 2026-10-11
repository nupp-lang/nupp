_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.comptime.materialize.providers\0runtime\0001") };










local cst = require ( "nupp.compiler.syntax.cst" )
local hash = require ( "nupp.compiler.hash" )
local peg = require ( "nupp.compiler.comptime.materialize.peg" )






local fieldcodec = require ( "nupp.compiler.comptime.materialize.fieldcodec" )




local typeprovider = require ( "nupp.compiler.comptime.materialize.typeprovider" )







local deriveprovider = require ( "nupp.compiler.comptime.materialize.derive" )















local providers = {} providers.__index = providers ;_G.nupp.__reflect.link(providers,__nuppT1[1],{ })
















function providers . importTypeDescriptor (
state ,
descriptor ,
source ,
referencePrefix
) 



local importDescriptor = typeprovider . importDescriptor
return importDescriptor ( state , descriptor , source , referencePrefix )
end

function providers . importFunctionConst ( state , key ) 
return typeprovider . importFunctionConst ( state , key )
end

providers . ABI = 1

local function provenance ( node , operation ) 
local token = cst . firstToken ( node )

return { operation = operation , line = token and token . line or 1 , column = token and token . col or 1 , }
end

local function opaque ( state , provider , family , payload , at ) 
local handle = { }
state . opaque [ handle ] = { provider = provider , family = family , payload = payload , provenance = at , }

return handle
end

local function installTest ( state , env ) 
local library = __nuppNew(0,2)

local nodeToken = { }
state . intrinsics [ nodeToken ] = function ( at , args ) 
local value = args [ 1 ]
if type ( value ) ~= "number" or value ~= math . floor ( value ) then
return nil , { code = "NUPP2412" , message = "the materialization test node needs an integer" , }
end

return opaque ( state , "compiler-test" , "Graph" , { value = value } , provenance ( at , "node" ) )
end
library . node = nodeToken
local factoryToken = { }
state . intrinsics [ factoryToken ] = function ( at ) 
return opaque ( state , "compiler-test" , "Factory" , { } , provenance ( at , "factory" ) )
end
library . factory = factoryToken
env . nupp = env . nupp or { }
env . nupp . __materializationTest = library
end

function providers . installEvaluator ( state , env ) 
state . opaque = { }
state . reflectionViews = { }
state . intrinsics = { }
installTest ( state , env )

local function newOpaque ( provider , family , payload , at ) 
return opaque ( state , provider , family , payload , at )
end

peg . installEvaluator ( state , env , newOpaque , provenance )
fieldcodec . installEvaluator ( state , env , newOpaque , provenance )
typeprovider . installEvaluator ( state , env , newOpaque , provenance )
deriveprovider . installEvaluator ( state , env , newOpaque , provenance , function ( handle ) 
return state . opaque [ handle ]
end )
end

function providers . materializeDeriveInfo ( state , input ) 
return deriveprovider . materializeInfo (
state ,
input ,
function ( provider , family , payload , at ) 
return opaque ( state , provider , family , payload , at )
end ,
provenance
)
end

local function reflectionValue ( state , value , at ) 
if type ( value ) ~= "table" then
return value
end
local prior = state . reflectionViews [ value ]
if prior then
return prior
end
local handle = opaque ( state , "reflection" , "TypeInfoView" , value , provenance ( at , "reflect-view" ) )
state . reflectionViews [ value ] = handle

return handle
end

function providers . reflect ( state , descriptor , at ) 
local handle = opaque ( state , "reflection" , "TypeInfo" , descriptor , provenance ( at , "reflect" ) )
state . reflectionViews [ descriptor ] = handle

return handle
end

function providers . isOpaque ( state , value ) 
return type ( value ) == "table" and state . opaque [ value ] ~= nil
end

function providers . opaqueKind ( state , value ) 
local entry = state . opaque [ value ]
if entry and entry . provider == "reflection" then
return "table"
end
if entry and entry . provider == "derive" and entry . family == "View" then
return "table"
end

return typeprovider . opaqueKind ( state , value )
end

function providers . index ( state , handle , key , at ) 
local entry = state . opaque [ handle ]
if entry and entry . provider == "derive" then
return deriveprovider . index ( state , entry , key )
end
if not entry or entry . provider ~= "reflection" or type ( entry . payload ) ~= "table" then
return nil , { code = "NUPP2411" , message = "this opaque comptime value cannot be indexed" }
end
if type ( key ) ~= "string" and type ( key ) ~= "number" then
return nil , { code = "NUPP2411" , message = "reflection indices must be strings or numbers" }
end

return reflectionValue ( state , entry . payload [ key ] , at ) , nil
end

function providers . iterator ( state , handle , array ) 
local entry = state . opaque [ handle ]
if entry and entry . provider == "derive" then
return deriveprovider . iterator ( state , entry , array )
end
if not entry or entry . provider ~= "reflection" or type ( entry . payload ) ~= "table" then
return nil , { code = "NUPP2411" , message = "this opaque comptime value cannot be iterated" }
end

return deriveprovider . sortedPairs ( entry . payload , array , function ( item ) 
return reflectionValue ( state , item , nil )
end ) , nil
end

function providers . method ( state , handle , name , args , at ) 
local entry = state . opaque [ handle ]
if not entry then
return nil , { code = "NUPP2412" , message = "the comptime value is not an opaque handle" }
end
if entry . provider == "compiler-test" and entry . family == "Graph" and name == "link" then
local child = args [ 1 ]
local childEntry = state . opaque [ child ]
if not childEntry or childEntry . provider ~= entry . provider or childEntry . family ~= entry . family then
return nil , { code = "NUPP2412" , message = "link needs another materialization test node" }
end
entry . payload . next = child
entry . provenance = provenance ( at , "link" )

return handle , nil
end
if entry . provider == "peg" then
return peg . method ( state , handle , name , args , at )
end

return nil , {
code = "NUPP2411" ,
message = ("opaque %s has no comptime method %q") : format ( tostring ( entry . family ) , name ) ,
}
end

function providers . operator ( state , op , left , right , at ) 
local entry = state . opaque [ left ]
if ( op == "==" or op == "~=" ) and not entry then
local rightEntry = state . opaque [ right ]
if rightEntry and rightEntry . provider == "reflection" then
return op == "~=" , nil
end
end
if entry and entry . provider == "reflection" then
if op == "unary#" then
return # entry . payload , nil
elseif op == "==" or op == "~=" then
local other = state . opaque [ right ]
local equal = other and other . provider == "reflection" and other . payload == entry . payload or false
if op == "==" then
return equal , nil
else
return not equal , nil
end
end
end
if entry and entry . provider == "derive" then
if entry . family == "View" and op == "unary#" then
return deriveprovider . operator ( state , op , entry , right )
end
if op == "unarynot" then
return false , nil
end
if op == "==" or op == "~=" then
local equal = left == right
return op == "==" and equal or not equal , nil
end
end
if entry and entry . provider == "peg" then
return peg . operator ( state , op , left , right , at )
end
if entry and entry . provider == "types" then
return typeprovider . operator ( state , op , left , right )
end

return nil , { code = "NUPP2411" , message = "this operator is unavailable for opaque comptime values" }
end

local function finalizeTest ( state , root ) 
local indices = { }
local entries = { }
local cursor = root
while cursor do
local existing = indices [ cursor ]
if existing then
do break end
end
if # entries >= 1024 then
return nil , { code = "NUPP2416" , message = "compiler-test blueprint exceeds its 1024-node limit" , }
end
local entry = state . opaque [ cursor ]
if not entry or entry . provider ~= "compiler-test" or entry . family ~= "Graph" then
return nil , { code = "NUPP2415" , message = "compiler-test graph contains a foreign handle" }
end
indices [ cursor ] = # entries + 1
entries [ # entries + 1 ] = entry
cursor = entry . payload . next
end

local values , nexts , origins = { } , { } , { }
for index , entry in ipairs ( entries ) do
values [ index ] = entry . payload . value
nexts [ index ] = entry . payload . next and indices [ entry . payload . next ] or 0
origins [ index ] = entry . provenance
end
local canonicalParts = { }
for index = 1 , # values do
canonicalParts [ # canonicalParts + 1 ] = tostring ( values [ index ] ) .. ":" .. tostring ( nexts [ index ] )
end
local canonical = table . concat ( canonicalParts , "," )

return {
kind = "materialized" ,
provider = "compiler-test" ,
schema = 1 ,
family = "Graph" ,
payload = { values = values , nexts = nexts } ,
provenance = origins ,
fingerprint = hash . sha256 ( "compiler-test\0v1\0" .. canonical ) ,
summary = ("%d-node test graph") : format ( # values ) ,
} , nil
end

function providers . finalize ( state , value ) 
local entry = state . opaque [ value ]
if not entry then
return nil , { code = "NUPP2414" , message = "the value is not compiler-owned opaque data" }
end
if entry . provider == "compiler-test" then
if entry . family == "Factory" then
local fingerprint = hash . sha256 ( "compiler-test\0factory-v1" )
return {
kind = "materialized" ,
provider = "compiler-test" ,
schema = 1 ,
family = "Factory" ,
payload = { } ,
provenance = { entry . provenance } ,
fingerprint = fingerprint ,
summary = "test input factory" ,
} , nil
end
return finalizeTest ( state , value )
elseif entry . provider == "peg" then
return peg . finalize ( state , value )
elseif entry . provider == "fieldcodec" then
return fieldcodec . finalize ( state , value )
elseif entry . provider == "types" then
return typeprovider . finalize ( state , value )
elseif entry . provider == "derive" then
return deriveprovider . finalize ( state , value )
end

return nil , { code = "NUPP2415" , message = "no finalizer owns this opaque value" }
end

local function validateTest ( envelope ) 
if envelope . schema ~= 1 or envelope . family ~= "Graph" or type ( envelope . payload ) ~= "table" then
return nil , "compiler-test blueprint has the wrong schema"
end
local values , nexts = envelope . payload . values , envelope . payload . nexts
if type ( values ) ~= "table" or type ( nexts ) ~= "table" or # values ~= # nexts or # values > 1024 then
return nil , "compiler-test blueprint has invalid graph arrays"
end
local canonicalParts = { }
for index = 1 , # values do
local value , nextIndex = values [ index ] , nexts [ index ]
if type ( value ) ~= "number" or value ~= math . floor ( value ) then
return nil , "compiler-test blueprint has a non-integer value"
end
if type ( nextIndex ) ~= "number"
or nextIndex ~= math . floor ( nextIndex )
or nextIndex < 0
or nextIndex > # values
then
return nil , "compiler-test blueprint has an invalid edge"
end
canonicalParts [ # canonicalParts + 1 ] = tostring ( value ) .. ":" .. tostring ( nextIndex )
end
local fingerprint = hash . sha256 ( "compiler-test\0v1\0" .. table . concat ( canonicalParts , "," ) )
if envelope . fingerprint ~= fingerprint then
return nil , "compiler-test blueprint fingerprint does not match its payload"
end

return true
end

local function testFactoryTarget ( expected , env ) 
local input = env and env . globalTypes and env . globalTypes [ "nupp.__MaterializationTestInput" ]
local output = env and env . globalTypes and env . globalTypes [ "nupp.__MaterializedTest" ]

return expected
and expected . tag == "func"
and # expected . params == 1
and # expected . rets == 1
and expected . params [ 1 ] == input
and expected . rets [ 1 ] == output
end





function providers . lower ( envelope , expected , env ) 
if type ( envelope ) ~= "table"
or envelope . kind ~= "materialized"
or type ( envelope . provider ) ~= "string"
or type ( envelope . schema ) ~= "number"
or type ( envelope . fingerprint ) ~= "string"
then
return nil , { code = "NUPP2415" , message = "the comptime worker returned a malformed blueprint envelope" }
end
if envelope . provider ~= "compiler-test" then
if envelope . provider == "peg" then
return peg . lower ( envelope , expected , env )
elseif envelope . provider == "fieldcodec" then
return fieldcodec . lower ( envelope , expected , env )
elseif envelope . provider == "types" then
return nil , {
code = "NUPP2414" ,
message = "a type blueprint is valid only as the result of a type-position comptime call" ,
}
elseif envelope . provider == "derive" then
return nil , {
code = "NUPP2810" ,
message = "a derive recipe is valid only as the result of an @derive provider" ,
}
end
return nil , { code = "NUPP2415" , message = "no materializer owns provider " .. envelope . provider }
end
if not expected then
return nil , {
code = "NUPP2414" ,
message = "an opaque comptime result needs a directly declared runtime type" ,
help = "write a type annotation on the declaration initialized by this comptime block" ,
}
end
local target = env and env . globalTypes and env . globalTypes [ "nupp.__MaterializedTest" ]
if envelope . family == "Factory" then
if not testFactoryTarget ( expected , env ) then
return nil , {
code = "NUPP2415" ,
message = "compiler-test opaque Factory needs function(__MaterializationTestInput): __MaterializedTest" ,
}
end
if envelope . schema ~= 1 or envelope . fingerprint ~= hash . sha256 ( "compiler-test\0factory-v1" ) then
return nil , { code = "NUPP2415" , message = "compiler-test factory blueprint is malformed" }
end

return {
tag = "function" ,
params = { 1 } ,
body = {
{
tag = "return" ,
value = {
tag = "table" ,
fields = {
{
name = "value" ,
value = { tag = "field" , object = { tag = "local" , id = 1 } , name = "value" , }
} ,
{ name = "nodes" , value = { tag = "literal" , value = 1 } } ,
} ,
} ,
}
} ,
} , nil , { backend = "direct" , emitterAbi = 1 , helperAbi = 0 , runtimeFeatures = { } , }
elseif expected ~= target then
return nil , {
code = "NUPP2415" ,
message = ("compiler-test opaque Graph cannot materialize as %s")

: format ( tostring ( expected . name or expected . tag ) ) ,
}
end
local valid , why = validateTest ( envelope )
if not valid then
return nil , { code = "NUPP2415" , message = why }
end
local sum = 0
for _ , value in ipairs ( envelope . payload . values ) do
sum = sum + value
end

return {
tag = "table" ,
fields = {
{ name = "value" , value = { tag = "literal" , value = sum } } ,
{ name = "nodes" , value = { tag = "literal" , value = # envelope . payload . values } } ,
} ,
} , nil , { backend = "direct" , emitterAbi = 1 , helperAbi = 0 , runtimeFeatures = { } , }
end

local __nuppExportValue= providers ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.comptime.materialize.providers"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.comptime.materialize.providers"]=__nuppExports;return __nuppExports