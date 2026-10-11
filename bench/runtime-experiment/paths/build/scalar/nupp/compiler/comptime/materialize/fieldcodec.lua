_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.comptime.materialize.fieldcodec\0runtime\0001") };



local hash = require ( "nupp.compiler.hash" )
local reflection = require ( "nupp.compiler.reflection" )







local fieldcodec = {} fieldcodec.__index = fieldcodec ;_G.nupp.__reflect.link(fieldcodec,__nuppT1[1],{ })





local function failure ( code , message , help ) 
return { code = code , message = message , help = help }
end

function fieldcodec . installEvaluator ( state , env , newOpaque , provenance ) 
local library = { }

local token = { }
state . intrinsics [ token ] = function ( at , args ) 
local reflected = state . opaque [ args [ 1 ] ]
if args . n ~= 1 or not reflected or reflected . provider ~= "reflection" or reflected . family ~= "TypeInfo" then
return nil , failure ( "NUPP2418" , "nupp.reflect.fieldCodec needs one reflected type" )
end

return newOpaque (
"fieldcodec" ,
"Blueprint" ,
{ descriptor = reflected . payload } ,
provenance ( at , "nupp.reflect.fieldCodec" )
)
end
library . fieldCodec = token
env . nupp = env . nupp or { }
env . nupp . reflect = library
end

function fieldcodec . finalize ( state , value ) 
local entry = state . opaque [ value ]
if not entry or entry . provider ~= "fieldcodec" or entry . family ~= "Blueprint" then
return nil , failure ( "NUPP2415" , "the value is not a field-codec blueprint" )
end
local descriptor = entry . payload . descriptor
if type ( descriptor ) ~= "table"
or descriptor . kind ~= "record"
or type ( descriptor . fingerprint ) ~= "string"
or type ( descriptor . fields ) ~= "table"
then
return nil , failure ( "NUPP2418" , "keyed field codecs require a reflected record type" )
end
local fields = { }
local seen = { }
for _ , field in ipairs ( descriptor . fields ) do
local name = field and field . name
if type ( name ) ~= "string" or not name : find ( "^[%a_][%w_]*$" ) or seen [ name ] then
return nil , failure ( "NUPP2418" , "reflected codec fields must be unique identifiers" )
end
seen [ name ] , fields [ # fields + 1 ] = true , name
end
if type ( descriptor . name ) ~= "string" or type ( descriptor . qualifiedName ) ~= "string" then
return nil , failure ( "NUPP2418" , "keyed field codecs require a named reflected record type" )
end
local payload = {
fields = fields ,
typeFingerprint = descriptor . fingerprint ,
typeName = descriptor . name ,
qualifiedName = descriptor . qualifiedName ,
}
local canonical = table . concat (
fields ,
"\0"
) .. "\0" .. descriptor . fingerprint .. "\0" .. descriptor . name .. "\0" .. descriptor . qualifiedName

return {
kind = "materialized" ,
provider = "fieldcodec" ,
schema = 2 ,
family = "KeyedCodecBlueprint" ,
payload = payload ,
provenance = { entry . provenance } ,
fingerprint = hash . sha256 ( "nupp.fieldcodec\0v2\0" .. canonical ) ,
summary = ("%d-field keyed codec for %s") : format ( # fields , descriptor . name or "record" ) ,
} , nil
end

local function dataArray ( values ) 
local out = { }
for index , value in ipairs ( values ) do
out [ index ] = { tag = "literal" , value = value }
end

return { tag = "table" , array = out }
end

function fieldcodec . lower ( envelope , expected , env ) 
if not expected then
return nil , failure (
"NUPP2414" ,
"a field-codec blueprint needs a directly declared runtime type" ,
"write nupp.reflect.FieldCodec<Record> on the declaration initialized by this comptime block"
)
end
if envelope . schema ~= 2
or envelope . family ~= "KeyedCodecBlueprint"
or type ( envelope . payload ) ~= "table"
or type ( envelope . payload . fields ) ~= "table"
or type ( envelope . payload . typeFingerprint ) ~= "string"
or type ( envelope . payload . typeName ) ~= "string"
or type ( envelope . payload . qualifiedName ) ~= "string"
then
return nil , failure ( "NUPP2415" , "field-codec blueprint has the wrong schema" )
end
local fields = { }
local seen = { }
for _ , name in ipairs ( envelope . payload . fields ) do
if type ( name ) ~= "string" or not name : find ( "^[%a_][%w_]*$" ) or seen [ name ] then
return nil , failure ( "NUPP2415" , "field-codec blueprint has malformed fields" )
end
seen [ name ] , fields [ # fields + 1 ] = true , name
end
local canonical = table . concat (
fields ,
"\0"
)
.. "\0"
.. envelope . payload . typeFingerprint
.. "\0"
.. envelope . payload . typeName
.. "\0"
.. envelope . payload . qualifiedName
if envelope . fingerprint ~= hash . sha256 ( "nupp.fieldcodec\0v2\0" .. canonical ) then
return nil , failure ( "NUPP2415" , "field-codec blueprint fingerprint does not match" )
end
local namespace = env and env . globalTypes and env . globalTypes [ "nupp.reflect" ]
local codec = namespace and namespace . nestedTypes and namespace . nestedTypes . FieldCodec
local target = expected and expected . typeArgs and expected . typeArgs [ 1 ]
if not codec
or not expected
or ( expected . origin or expected ) ~= codec
or not target
or target . tag ~= "nominal"
or target . declKind ~= "record"
or target . name ~= envelope . payload . typeName
or ( target . runtimePath or target . name ) ~= envelope . payload . qualifiedName
or reflection . describe (
target ,
target . runtimePath or target . name
) . fingerprint ~= envelope . payload . typeFingerprint
then
return nil , failure ( "NUPP2415" , "field-codec blueprint needs nupp.reflect.FieldCodec<Record>" )
end
local order = target . fieldOrder or { }
if # order ~= # fields then
return nil , failure ( "NUPP2415" , "reflected fields do not match the declared codec record" )
end
for index , name in ipairs ( fields ) do
if order [ index ] ~= name then
return nil , failure ( "NUPP2415" , "reflected fields do not match the declared codec record" )
end
end
local fingerprint = "t:" .. table . concat ( fields , "," )

return {
tag = "call" ,
callee = { tag = "helper" , name = "nupp.fieldcodec.keyed" } ,
args = {
dataArray ( fields ) ,
{ tag = "literal" , value = fingerprint } ,
{ tag = "typeobject" , path = target . runtimePath or envelope . payload . qualifiedName } ,
} ,
} , nil , { backend = "keyed" , emitterAbi = 2 , helperAbi = 2 , runtimeFeatures = { "stdlib.fieldcodec" } , }
end

local __nuppExportValue= fieldcodec ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.comptime.materialize.fieldcodec"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.comptime.materialize.fieldcodec"]=__nuppExports;return __nuppExports