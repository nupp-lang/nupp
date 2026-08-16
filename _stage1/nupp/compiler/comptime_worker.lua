_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local function __nuppLoadJSON()local source=require("cjson");local aliases={EMPTY_ARRAY="empty_array",ARRAY_MT="array_mt",EMPTY_ARRAY_MT="empty_array_mt",encodeEmptyTableAsObject="encode_empty_table_as_object",decodeArrayWithArrayMt="decode_array_with_array_mt",encodeSparseArray="encode_sparse_array",encodeMaxDepth="encode_max_depth",decodeMaxDepth="decode_max_depth",encodeNumberPrecision="encode_number_precision",encodeKeepBuffer="encode_keep_buffer",encodeInvalidNumbers="encode_invalid_numbers",decodeInvalidNumbers="decode_invalid_numbers",encodeEscapeForwardSlash="encode_escape_forward_slash"};local function adopt(target,json)target.encodeJSON=json.encode;target.decodeJSON=json.decode;target.NULL=json.null;for public,name in pairs(aliases)do target[public]=json[name]end;return target end;local json=adopt({},source);json.newJSON=function()return adopt({},source.new())end;return json end __nuppLazy(__nuppData,"json",__nuppLoadJSON);








local cjson = require ( "cjson" ) . new ( )
local process = require ( "nupp.compiler.build.process" )







const worker = {} worker.__index = worker







cjson . encode_empty_table_as_object ( false )
cjson . encode_invalid_numbers ( false )

local MAX_PROTOCOL_BYTES = 2 * 1024 * 1024



local WORKER_TIMEOUT_MS = 10000

local function timeoutMessage ( )
return ( "comptime evaluation exceeded the %d ms worker timeout" ) : format ( WORKER_TIMEOUT_MS )
end

local function read ( path )
local file , err = io . open ( path , "rb" )
if not file then
return nil , err
end
local text = file : read ( "*a" )
file : close ( )

return text
end

local function write ( path , text )
local file , err = io . open ( path , "wb" )
if not file then
return nil , err
end
file : write ( text )
file : close ( )

return true
end

local function serializedHelper ( node )
node = node and ( node . node or node )
local token = node and node . name
if not node or node . kind ~= "localFuncStmt" or not token then
return nil
end

return { source = require ( "nupp.compiler.cst" ) . textOf ( node ) , line = token . line , column = token . col , }
end

local function findComptime ( node )
if type ( node ) ~= "table" then
return nil
end
if node . kind == "comptimeExpr" then
return node
end
for _ , child in ipairs ( node ) do
local found = findComptime ( child )
if found then
return found
end
end

return nil
end

local function findLocalFunction ( node )
if type ( node ) ~= "table" then
return nil
end
if node . kind == "localFuncStmt" then
return node
end
for _ , child in ipairs ( node ) do
local found = findLocalFunction ( child )
if found then
return found
end
end

return nil
end

local parsedPrograms = { }

local function parseHelpers ( request )
if type ( request . program ) ~= "string" or type ( request . main ) ~= "string" or type ( request . helpers ) ~= "table" then
return nil , { code = "NUPP2412" , message = "invalid type-function worker program" }
end
local cached = parsedPrograms [ request . program ]
if cached then
return cached , nil
end
local helpers = { }
for name , descriptor in pairs ( request . helpers ) do
if type ( name ) ~= "string" or type ( descriptor ) ~= "table" or type ( descriptor . source ) ~= "string" then
return nil , { code = "NUPP2412" , message = "invalid comptime helper request" }
end
local helperParse = require ( "nupp.compiler.parser" ) . parse ( descriptor . source , "=comptime-helper-" .. name )
local helper = # ( helperParse . errors or { } ) == 0 and findLocalFunction ( helperParse . root ) or nil
if not helper or not helper . name or helper . name . text ~= name then
return nil , { code = "NUPP2412" , message = "the comptime worker could not parse checked helper " .. name , }
end
helpers [ name ] = { node = helper , line = descriptor . line , column = descriptor . column }
end
local main = helpers [ request . main ]
if not main then
return nil , { code = "NUPP2412" , message = "type-function worker program has no entry helper" }
end
cached = { main = main . node , helpers = helpers }
parsedPrograms [ request . program ] = cached

return cached , nil
end

local function handleRequest ( request )
if type ( request ) ~= "table" then
return { ok = false , code = "NUPP2412" , message = "invalid worker request" }
end
if request . kind == "type-function" then
local program , programFailure = parseHelpers ( request )
if not program then
local stopped = programFailure or {
code = "NUPP2412" ,
message = "type-function worker program could not be loaded" ,
}
return { ok = false , code = stopped . code , message = stopped . message }
end
local comptime = require (
"nupp.compiler.comptime"
)
local envelope , failure = comptime . evaluateTypeFunctionDirect (
program . main ,
request . arguments or { } ,
program . helpers
)
if failure then
return { ok = false , code = failure . code , message = failure . message , help = failure . help }
end
return { ok = true , materialized = envelope }
end
if request . kind == "derive-provider" then
local program , programFailure = parseHelpers ( request )
if not program then
local stopped = programFailure or {
code = "NUPP2810" ,
message = "derive-provider worker program could not be loaded" ,
}
return { ok = false , code = stopped . code , message = stopped . message }
end
local comptime = require (
"nupp.compiler.comptime"
)
local envelope , failure = comptime . evaluateDeriveProviderDirect (
program . main ,
request . input ,
program . helpers ,
request . runtimeHelpers ,
request . providerModule
)
if failure then
return { ok = false , code = failure . code , message = failure . message , help = failure . help }
end
return { ok = true , materialized = envelope }
end
if type ( request . source ) ~= "string" then
return { ok = false , code = "NUPP2412" , message = "invalid worker request" }
end
local parsed = require ( "nupp.compiler.parser" ) . parse ( "return " .. request . source , "=comptime-worker" )
if # ( parsed . errors or { } ) > 0 then
return { ok = false , code = "NUPP2412" , message = "the comptime worker could not parse its checked request" }
end
local node = findComptime ( parsed . root )
if not node then
return { ok = false , code = "NUPP2412" , message = "worker request has no comptime block" }
end
local helperRequest = { program = "value:" .. request . source , main = "" , helpers = request . helpers or { } }
local helpers = { }
for name , descriptor in pairs ( helperRequest . helpers ) do
local helperParse = type (
descriptor
) == "table" and type (
descriptor . source
) == "string" and require ( "nupp.compiler.parser" ) . parse ( descriptor . source , "=comptime-helper-" .. name ) or nil
local helper = helperParse and # ( helperParse . errors or { } ) == 0 and findLocalFunction ( helperParse . root ) or nil
if not helper or not helper . name or helper . name . text ~= name then
return { ok = false , code = "NUPP2412" , message = "invalid comptime helper request" }
end
helpers [ name ] = { node = helper , line = descriptor . line , column = descriptor . column }
end
local comptime = require (
"nupp.compiler.comptime"
)
local quoted , _ , failure , envelope = comptime . evaluateDirect (
node ,
node . body ,
request . reflections ,
request . layouts ,
helpers
)
if failure then
return { ok = false , code = failure . code , message = failure . message , help = failure . help }
elseif envelope then
return { ok = true , materialized = envelope }
end

return { ok = true , quoted = quoted }
end


function worker . main ( argv )
local requestPath = argv [ 1 ]
if not requestPath then
io . write ( cjson . encode ( { ok = false , code = "NUPP2412" , message = "missing worker request" } ) , "\n" )
return 0
end
local requestText , readErr = read ( requestPath )
if not requestText then
io . write ( cjson . encode ( { ok = false , code = "NUPP2412" , message = tostring ( readErr ) } ) , "\n" )
return 0
end
if # requestText > MAX_PROTOCOL_BYTES then
io . write (
cjson . encode ( {
ok = false ,
code = "NUPP2416" ,
message = "comptime worker request exceeds 2097152 bytes"
} ) ,
"\n"
)
return 0
end
local decoded , request = pcall ( cjson . decode , requestText )
if not decoded or type ( request ) ~= "table" then
io . write ( cjson . encode ( { ok = false , code = "NUPP2412" , message = "invalid worker request" } ) , "\n" )
return 0
end
io . write ( cjson . encode ( handleRequest ( request ) ) , "\n" )

return 0
end



function worker . serviceMain ( )
for requestText in io . lines ( ) do
local response
if # requestText > MAX_PROTOCOL_BYTES then
response = { ok = false , code = "NUPP2416" , message = "comptime worker request exceeds 2097152 bytes" }
else
local decoded , request = pcall ( cjson . decode , requestText )
response = decoded and handleRequest (
request
) or { ok = false , code = "NUPP2412" , message = "invalid worker request" }
end
local encoded = cjson . encode ( response )
if # encoded > MAX_PROTOCOL_BYTES then
encoded = cjson . encode ( {
ok = false ,
code = "NUPP2416" ,
message = "comptime worker response exceeds 2097152 bytes"
} )
end
io . write ( encoded , "\n" )
io . stdout : flush ( )
end

return 0
end



function worker . evaluate (
source ,
executable ,
reflections ,
layouts ,
helpers ,
host
)
local requestPath = os . tmpname ( )
local serializedHelpers = { }
for name , supplied in pairs ( helpers or { } ) do
serializedHelpers [ name ] = serializedHelper ( supplied )
end
local requestText = cjson . encode ( {
source = source ,
reflections = reflections or { } ,
layouts = layouts or { } ,
helpers = serializedHelpers ,
} )
if # requestText > MAX_PROTOCOL_BYTES then
os . remove ( requestPath )
return nil , {
code = "NUPP2416" ,
message = "comptime worker request exceeds 2097152 bytes" ,
help = "make the reflected schema or helper set smaller" ,
}
end
local wrote , writeErr = write ( requestPath , requestText )
if not wrote then
return nil , { code = "NUPP2412" , message = "cannot create comptime worker request: " .. tostring ( writeErr ) }
end
local code , output = process . captureIsolated ( { executable , "__comptime-worker" , requestPath } , {
env = { NUPP_COMPTIME_WORKER_CHILD = "1" } ,
timeoutMs = WORKER_TIMEOUT_MS ,
memoryMb = 256 ,
pump = host and host . pump or nil ,
cancelled = host and host . cancelled or nil ,
} )
os . remove ( requestPath )
if code == 124 then
return nil , {
code = "NUPP2412" ,
message = timeoutMessage ( ) ,
help = "make the computation smaller or move the unbounded work to run time" ,
}
elseif code == 125 then
return nil , { code = "NUPP2412" , message = "comptime evaluation was cancelled" }
end
if # output > MAX_PROTOCOL_BYTES then
return nil , { code = "NUPP2416" , message = "comptime worker response exceeds 2097152 bytes" , }
end
local decoded , response = pcall ( cjson . decode , output )
if not decoded or type ( response ) ~= "table" then
return nil , {
code = "NUPP2412" ,
message = "the comptime worker crashed or returned an invalid response: " .. tostring (
decoded and response or output
) ,
}
end
if not response . ok then
return nil , {
code = response . code or "NUPP2412" ,
message = response . message or "comptime evaluation failed" ,
help = response . help
}
end

if response . materialized then
return nil , nil , response . materialized
end

return response . quoted , nil , nil
end

local service = nil
local serviceExecutable = nil
local serviceBuffer = ""

local function stopService ( force )
local current = service
service , serviceExecutable , serviceBuffer = nil , nil , ""
if not current then
return
end
if force and current : isRunning ( ) then
current : kill ( true )
end
current : close ( )
end

local function startService ( executable )
if service and serviceExecutable == executable and service : isRunning ( ) then
return service , nil
end
stopService ( true )
local child , problem = process . startIsolated ( { executable , "__comptime-worker-service" } , {
env = { NUPP_COMPTIME_WORKER_CHILD = "1" } ,
memoryMb = 256
} )
if not child or not child . stdin or not child . stdout then
if child then
child : close ( )
end
return nil , { code = "NUPP2412" , message = "cannot start comptime worker service: " .. tostring ( problem ) }
end
child . stdin : setTimeout ( WORKER_TIMEOUT_MS )
child . stdout : setTimeout ( 5 )
service = child
serviceExecutable = executable

return service , nil
end

local function requestService ( request , executable , host )
local encoded = cjson . encode ( request )
if # encoded > MAX_PROTOCOL_BYTES then
return nil , { code = "NUPP2416" , message = "comptime worker request exceeds 2097152 bytes" }
end
local child , startFailure = startService ( executable )
if not child then
return nil , startFailure
end
local wrote , writeFailure = child . stdin : write ( encoded .. "\n" )
if not wrote then
stopService ( true )
return nil , {
code = "NUPP2412" ,
message = "comptime worker service stopped accepting requests: " .. tostring ( writeFailure )
}
end
local deadline = child . backend : now ( ) + WORKER_TIMEOUT_MS
while true do
local newline = serviceBuffer : find ( "\n" , 1 , true )
if newline then
local line = serviceBuffer : sub ( 1 , newline - 1 )
serviceBuffer = serviceBuffer : sub ( newline + 1 )
if # line > MAX_PROTOCOL_BYTES then
stopService ( true )
return nil , { code = "NUPP2416" , message = "comptime worker response exceeds 2097152 bytes" }
end
local decoded , response = pcall ( cjson . decode , line )
if not decoded or type ( response ) ~= "table" then
stopService ( true )
return nil , { code = "NUPP2412" , message = "comptime worker service returned an invalid response" }
end
return response , nil
end
if host and host . pump then
host . pump ( )
end
if host and host . cancelled and host . cancelled ( ) then
stopService ( true )
return nil , { code = "NUPP2412" , message = "comptime evaluation was cancelled" }
end
if child . backend : now ( ) >= deadline then
stopService ( true )
return nil , {
code = "NUPP2412" ,
message = timeoutMessage ( ) ,
help = "make the computation smaller or move the unbounded work to run time" ,
}
end
local chunk , readFailure = child . stdout : read ( 65536 )
if chunk and # chunk > 0 then
serviceBuffer = serviceBuffer .. chunk
if # serviceBuffer > MAX_PROTOCOL_BYTES then
stopService ( true )
return nil , { code = "NUPP2416" , message = "comptime worker response exceeds 2097152 bytes" }
end
elseif not child : isRunning ( ) or child . stdout : isEOF ( ) then
stopService ( true )
return nil , {
code = "NUPP2412" ,
message = "the persistent comptime worker crashed: " .. tostring ( readFailure or "unexpected EOF" ) ,
}
end
end
end


function worker . evaluateTypeFunction (
program ,
arguments ,
executable ,
host
)
local main = program . helper
local mainName = program . main or main and main . name and main . name . text or nil
if not mainName then
return nil , { code = "NUPP2412" , message = "type function has no named program entry" }
end
local helpers = program . serializedHelpers or { }
if not program . serializedHelpers then
helpers [ mainName ] = serializedHelper ( main )
for name , helper in pairs ( program . helpers or { } ) do
helpers [ name ] = serializedHelper ( helper )
end
end
local response , protocolFailure = requestService (
{
kind = "type-function" ,
program = program . identity ,
main = mainName ,
helpers = helpers ,
arguments = arguments ,
} ,
executable ,
host
)
if not response then
return nil , protocolFailure
end
if not response . ok then
return nil , {
code = response . code or "NUPP2412" ,
message = response . message or "comptime type-function evaluation failed" ,
help = response . help ,
}
end

return response . materialized , nil
end


function worker . evaluateDeriveProvider (
program ,
input ,
runtimeHelpers ,
providerModule ,
executable ,
host
)
local main = program . helper
local mainName = program . main or main and main . name and main . name . text or nil
if not mainName then
return nil , { code = "NUPP2810" , message = "derive provider has no named program entry" }
end
local helpers = program . serializedHelpers or { }
if not program . serializedHelpers then
helpers [ mainName ] = serializedHelper ( main )
for name , helper in pairs ( program . helpers or { } ) do
helpers [ name ] = serializedHelper ( helper )
end
end
local response , protocolFailure = requestService (
{
kind = "derive-provider" ,
program = program . identity ,
main = mainName ,
helpers = helpers ,
input = input ,
runtimeHelpers = runtimeHelpers ,
providerModule = providerModule ,
} ,
executable ,
host
)
if not response then
return nil , protocolFailure
end
if not response . ok then
return nil , {
code = response . code or "NUPP2810" ,
message = response . message or "comptime derive-provider evaluation failed" ,
help = response . help ,
}
end

return response . materialized , nil
end

return worker
