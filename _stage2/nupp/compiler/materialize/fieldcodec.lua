_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);

local hash = require ( "nupp.compiler.build.hash" )







const fieldcodec = {} fieldcodec.__index = fieldcodec





local function failure ( code , message , help )
return { code = code , message = message , help = help }
end

function fieldcodec . installEvaluator ( state , env , newOpaque , provenance )
local library = { }
local token = function ( )
end
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
if type (
descriptor
) ~= "table" or descriptor . kind ~= "record" or type (
descriptor . fingerprint
) ~= "string" or type ( descriptor . fields ) ~= "table" then
return nil , failure ( "NUPP2418" , "keyed field codecs require a reflected record type" )
end
local fields , seen = { } , { }
for _ , field in ipairs ( descriptor . fields ) do
local name = field and field . name
if type ( name ) ~= "string" or not name : find ( "^[%a_][%w_]*$" ) or seen [ name ] then
return nil , failure ( "NUPP2418" , "reflected codec fields must be unique identifiers" )
end
seen [ name ] , fields [ # fields + 1 ] = true , name
end
local payload = { fields = fields , typeFingerprint = descriptor . fingerprint , typeName = descriptor . name , }
local canonical = table . concat ( fields , "\0" ) .. "\0" .. descriptor . fingerprint .. "\0" .. tostring ( descriptor . name )

return {
kind = "materialized" ,
provider = "fieldcodec" ,
schema = 1 ,
family = "KeyedCodecBlueprint" ,
payload = payload ,
provenance = { entry . provenance } ,
fingerprint = hash . sha256 ( "nupp.fieldcodec\0v1\0" .. canonical ) ,
summary = ( "%d-field keyed codec for %s" ) : format ( # fields , descriptor . name or "record" ) ,
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
if envelope . schema ~= 1 or envelope . family ~= "KeyedCodecBlueprint" or type (
envelope . payload
) ~= "table" or type (
envelope . payload . fields
) ~= "table" or type (
envelope . payload . typeFingerprint
) ~= "string" or type ( envelope . payload . typeName ) ~= "string" then
return nil , failure ( "NUPP2415" , "field-codec blueprint has the wrong schema" )
end
local fields , seen = { } , { }
for _ , name in ipairs ( envelope . payload . fields ) do
if type ( name ) ~= "string" or not name : find ( "^[%a_][%w_]*$" ) or seen [ name ] then
return nil , failure ( "NUPP2415" , "field-codec blueprint has malformed fields" )
end
seen [ name ] , fields [ # fields + 1 ] = true , name
end
local canonical = table . concat (
fields ,
"\0"
) .. "\0" .. envelope . payload . typeFingerprint .. "\0" .. envelope . payload . typeName
if envelope . fingerprint ~= hash . sha256 ( "nupp.fieldcodec\0v1\0" .. canonical ) then
return nil , failure ( "NUPP2415" , "field-codec blueprint fingerprint does not match" )
end
local namespace = env and env . globalTypes and env . globalTypes [ "nupp.reflect" ]
local codec = namespace and namespace . nestedTypes and namespace . nestedTypes . FieldCodec
local target = expected and expected . typeArgs and expected . typeArgs [ 1 ]
if not codec or not expected or (
expected . origin or expected
) ~= codec
or not target
or target . tag ~= "nominal"
or target . declKind ~= "record"
or target . name ~= envelope . payload . typeName then
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
args = { dataArray ( fields ) , { tag = "literal" , value = fingerprint } } ,
} , nil , { backend = "keyed" , emitterAbi = 1 , helperAbi = 1 , runtimeFeatures = { "stdlib.fieldcodec" } , }
end

return fieldcodec
