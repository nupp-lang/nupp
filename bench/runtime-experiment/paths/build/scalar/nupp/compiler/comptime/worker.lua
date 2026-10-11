_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT16={}; local function __nuppT13(...) return {n=select("#",...),...} end; local __nuppT17,__nuppT18,__nuppT19,__nuppT20,__nuppT21,__nuppT22,__nuppT23,__nuppT24=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT14(value) return value end; local function __nuppT15(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT22({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT23(v.primary) for _,reason in __nuppT24(v.suppressed) do text=text.."\ncleanup: "..__nuppT23(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppT70 = function(__nuppV) return __nuppV:close() end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.comptime.worker\0runtime\0001") };










local json = require ( "nupp.codec.json" )
local process = require ( "nupp.compiler.process" )
local clock = require ( "nupp.time" )
local workerchannel = require ( "nupp.compiler.workerchannel" )







local worker = {} worker.__index = worker ;_G.nupp.__reflect.link(worker,__nuppT1[1],{ })














local MAX_PROTOCOL_BYTES = 2097152



local MAX_SAID_BYTES = 8192



local WORKER_TIMEOUT_MS = 10000

local function timeoutMessage ( ) 
return ("comptime evaluation exceeded the %d ms worker timeout") : format ( 10000 )
end







local function escapeBytes ( text ) 
if not text : find ( "[€-ÿ\\]" ) then
return text
end

return ( text : gsub ( "[€-ÿ\\]" , function ( byte ) 
return ("\\x%02X") : format ( byte : byte ( ) )
end ) )
end

local function restoreBytes ( text ) 
if not text : find ( "\\" , 1 , true ) then
return text
end

return ( text : gsub ( "\\x(%x%x)" , function ( digits ) 
return string . char ( tonumber ( digits , 16 ) )
end ) )
end

local function protocolValue ( value , seen ) 
if type ( value ) == "string" then
return escapeBytes ( value )
end
if value == json . NULL or value == json . EMPTY_ARRAY or value == json . EMPTY_OBJECT or type ( value ) ~= "table" then
return value
end
seen = seen or { }
if seen [ value ] then
return seen [ value ]
end
local copied = { }
seen [ value ] = copied
local otherKeys , maximum = false , 0
for key , item in pairs ( value ) do
if type ( key ) == "number" and key >= 1 and key % 1 == 0 then
maximum = math . max ( maximum , key )
else
otherKeys = true
end
copied [ type ( key ) == "string" and escapeBytes ( key ) or key ] = protocolValue ( item , seen )
end
if not otherKeys then
for index = 1 , maximum do
if copied [ index ] == nil then
copied [ index ] = json . NULL
end
end
return json . asArray ( copied )
end

return copied
end

local function encodeProtocol ( value ) 
return json . encode ( protocolValue ( value ) )
end





local function protocolDecoded ( value , seen ) 
if type ( value ) == "string" then
return restoreBytes ( value )
end
if value == json . NULL or value == json . EMPTY_ARRAY or value == json . EMPTY_OBJECT or type ( value ) ~= "table" then
return value
end
seen = seen or { }
if seen [ value ] then
return value
end
seen [ value ] = true
local renamed = nil
for key , item in pairs ( value ) do
value [ key ] = protocolDecoded ( item , seen )
if type ( key ) == "string" then
local restored = restoreBytes ( key )
if restored ~= key then
local list = renamed or { }
list [ # list + 1 ] = { key , restored }
renamed = list
end
end
end
for _ , pair in ipairs ( renamed or { } ) do
value [ pair [ 2 ] ] = value [ pair [ 1 ] ]
value [ pair [ 1 ] ] = nil
end

return value
end

local function decodeProtocol ( text ) 
local value , invalid = json . decode ( text , json . NULL )
if type ( value ) ~= "table" then
return false , invalid or value
end

return true , protocolDecoded ( value )
end

local function encodeResponse ( response ) 
local ok , encoded = pcall ( encodeProtocol , response )
if ok then
return encoded
end

return encodeProtocol ( {
ok = false ,
code = "NUPP2412" ,
message = "comptime worker could not encode its response: " .. tostring ( encoded ) ,
} )
end

local function read ( path ) 
do local __nuppT25=0; local  __nuppT31 ; local __nuppT26,__nuppT27,__nuppT28=__nuppT18(function() do local __nuppT32=__nuppT13( io . open ( path , "rb" ) ); __nuppT31= __nuppT32[1] ; __nuppT25=1;  local  file , err = __nuppT32[1] , __nuppT32[2] ;
if not file then
return "return",__nuppT13( nil , err )
end
local text = file : read ( "*a" )
file : close ( )

return "return",__nuppT13( text ) end; return "normal" end,__nuppT14); local __nuppT29={}; local __nuppT30=0; if __nuppT25>=1 and __nuppT31~=nil then  local __nuppT33,__nuppT34=__nuppT17(__nuppCleanup1,__nuppT31);  if not __nuppT33 then __nuppT30=__nuppT30+1; __nuppT29[__nuppT30]=__nuppT34 end; end; if not __nuppT26 then if __nuppT30>0 then __nuppT19(__nuppT15(__nuppT27,__nuppT29,1),0) else __nuppT19(__nuppT27,0) end end; if __nuppT30>0 then if __nuppT30>1 then __nuppT19(__nuppT15(__nuppT29[1],__nuppT29,2),0) else __nuppT19(__nuppT29[1],0) end end; if __nuppT27=="return" then  return __nuppT20(__nuppT28,1,__nuppT28.n)  end; end
end

local function write ( path , text ) 
do local __nuppT36=0; local  __nuppT42 ; local __nuppT37,__nuppT38,__nuppT39=__nuppT18(function() do local __nuppT43=__nuppT13( io . open ( path , "wb" ) ); __nuppT42= __nuppT43[1] ; __nuppT36=1;  local  file , err = __nuppT43[1] , __nuppT43[2] ;
if not file then
return "return",__nuppT13( nil , err )
end
file : write ( text )
file : close ( )

return "return",__nuppT13( true ) end; return "normal" end,__nuppT14); local __nuppT40={}; local __nuppT41=0; if __nuppT36>=1 and __nuppT42~=nil then  local __nuppT44,__nuppT45=__nuppT17(__nuppCleanup1,__nuppT42);  if not __nuppT44 then __nuppT41=__nuppT41+1; __nuppT40[__nuppT41]=__nuppT45 end; end; if not __nuppT37 then if __nuppT41>0 then __nuppT19(__nuppT15(__nuppT38,__nuppT40,1),0) else __nuppT19(__nuppT38,0) end end; if __nuppT41>0 then if __nuppT41>1 then __nuppT19(__nuppT15(__nuppT40[1],__nuppT40,2),0) else __nuppT19(__nuppT40[1],0) end end; if __nuppT38=="return" then  return __nuppT20(__nuppT39,1,__nuppT39.n)  end; end
end

local function serializedHelper ( node ) 
node = node and ( node . node or node )
local token = node and node . name
if not node or node . kind ~= "localFuncStmt" or not token then
return nil
end

return { source = require ( "nupp.compiler.syntax.cst" ) . textOf ( node ) , line = token . line , column = token . col , }
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
local helperParse = require ( "nupp.compiler.syntax.parser" ) . parse ( descriptor . source , "=comptime-helper-" .. name )
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
local stopped = programFailure
or { code = "NUPP2412" , message = "type-function worker program could not be loaded" , }
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
local stopped = programFailure
or { code = "NUPP2810" , message = "derive-provider worker program could not be loaded" , }
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
local parsed = require ( "nupp.compiler.syntax.parser" ) . parse ( "return " .. request . source , "=comptime-worker" )
if # ( parsed . errors or { } ) > 0 then
return { ok = false , code = "NUPP2412" , message = "the comptime worker could not parse its checked request" }
end
local node = findComptime ( parsed . root )
if not node then
return { ok = false , code = "NUPP2412" , message = "worker request has no comptime block" }
end
local helpers = { }
for name , descriptor in pairs ( request . helpers or { } ) do
local helperParse = type ( descriptor ) == "table"
and type ( descriptor . source ) == "string"
and require ( "nupp.compiler.syntax.parser" ) . parse ( descriptor . source , "=comptime-helper-" .. name )
or nil
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
io . write ( encodeProtocol ( { ok = false , code = "NUPP2412" , message = "missing worker request" } ) , "\n" )
return 0
end
local requestText , readErr = read ( requestPath )
if not requestText then
io . write ( encodeProtocol ( { ok = false , code = "NUPP2412" , message = tostring ( readErr ) } ) , "\n" )
return 0
end
if # requestText > 2097152 then
io . write (
encodeProtocol ( {
ok = false ,
code = "NUPP2416" ,
message = "comptime worker request exceeds 2097152 bytes"
} ) ,
"\n"
)
return 0
end
local decoded , request = decodeProtocol ( requestText )
if not decoded then
io . write ( encodeProtocol ( { ok = false , code = "NUPP2412" , message = "invalid worker request" } ) , "\n" )
return 0
end
io . write ( encodeResponse ( handleRequest ( request ) ) , "\n" )

return 0
end



function worker . serviceMain ( ) 
local function respond ( response ) 
local encoded = encodeResponse ( response )
if # encoded > 2097152 then
encoded = encodeResponse ( {
ok = false ,
code = "NUPP2416" ,
message = "comptime worker response exceeds 2097152 bytes"
} )
end

return encoded
end

local function answer ( requestText ) 
local decoded , request = decodeProtocol ( requestText )

return respond (
decoded and handleRequest ( request ) or { ok = false , code = "NUPP2412" , message = "invalid worker request" }
)
end

workerchannel . serve (
answer ,
2097152 ,
function ( ) 
return respond ( { ok = false , code = "NUPP2416" , message = "comptime worker request exceeds 2097152 bytes" } )
end ,



function ( line ) 
if # line > 2097152 then
return respond ( {
ok = false ,
code = "NUPP2416" ,
message = "comptime worker request exceeds 2097152 bytes"
} )
end

return answer ( line )
end
)

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
local requestText = encodeProtocol ( {
source = source ,
reflections = reflections or { } ,
layouts = layouts or { } ,
helpers = serializedHelpers ,
} )
if # requestText > 2097152 then
os . remove ( requestPath )
return nil , {
code = "NUPP2416" ,
message = "comptime worker request exceeds 2097152 bytes" ,
help = "make the reflected schema or helper set smaller" ,
}
end
local wrote , writeErr = write ( requestPath , requestText )
if not wrote then

os . remove ( requestPath )
return nil , { code = "NUPP2412" , message = "cannot create comptime worker request: " .. tostring ( writeErr ) }
end
local code , output = process . captureIsolated ( { executable , "__comptime-worker" , requestPath } , {
env = { NUPP_COMPTIME_WORKER_CHILD = "1" } ,
timeoutMs = 10000 ,
memoryMb = 256 ,
pump = host and host . pump or nil ,
cancelled = host and host . cancelled or nil ,
} )
os . remove ( requestPath )
if code == 124 then
return nil , {
code = "NUPP2412" ,
message = ( ("comptime evaluation exceeded the %d ms worker timeout") : format ( 10000 ) ) ,
help = "make the computation smaller or move the unbounded work to run time" ,
}
elseif code == 125 then
return nil , { code = "NUPP2412" , message = "comptime evaluation was canceled" }
end
if # output > 2097152 then
return nil , { code = "NUPP2416" , message = "comptime worker response exceeds 2097152 bytes" , }
end
local decoded , response = decodeProtocol ( output )
if not decoded then
return nil , {
code = "NUPP2412" ,
message = "the comptime worker crashed or returned an invalid response: " .. tostring ( response or output ) ,
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

local function stopService ( force ) 
local current = service
service , serviceExecutable = nil , nil
workerchannel . close ( current , force )
end

local function startService ( executable , host ) 
if service and serviceExecutable == executable and service . child : isRunning ( ) then
service . pump = host and host . pump or nil
service . cancelled = host and host . cancelled or nil
return service , nil
end
stopService ( true )
do local __nuppT60=0; local  __nuppT66 ; local __nuppT67=false ; local __nuppT61,__nuppT62,__nuppT63=__nuppT18(function() do local __nuppT68=__nuppT13( process . startIsolated ( { executable , "__comptime-worker-service" } , {
env = { NUPP_COMPTIME_WORKER_CHILD = "1" } ,
memoryMb = 256
} ) ); __nuppT66= __nuppT68[1] ; __nuppT60=1;  __nuppT67=true;  local  child , problem = __nuppT68[1] , __nuppT68[2] ;
if not child or not child . stdin or not child . stdout then
if child then
do (function(__nuppT69,...)  __nuppT67=false; return __nuppT69:close(...)  end)( child ) end
end
return "return",__nuppT13( nil , { code = "NUPP2412" , message = "cannot start comptime worker service: " .. tostring ( problem ) } )
end
service = workerchannel . open ( (function() __nuppT67=false; return  child  end)() , {
maxFrame = 2097152 ,
maxSaid = 8192 ,
waitMs = 5 ,
pump = host and host . pump or nil ,
cancelled = host and host . cancelled or nil ,
} )
serviceExecutable = executable

return "return",__nuppT13( service , nil ) end; return "normal" end,__nuppT14); local __nuppT64={}; local __nuppT65=0; if __nuppT60>=1 and __nuppT67 and __nuppT66~=nil then  local __nuppT71,__nuppT72=__nuppT17(__nuppT70,__nuppT66);  if not __nuppT71 then __nuppT65=__nuppT65+1; __nuppT64[__nuppT65]=__nuppT72 end; end; if not __nuppT61 then if __nuppT65>0 then __nuppT19(__nuppT15(__nuppT62,__nuppT64,1),0) else __nuppT19(__nuppT62,0) end end; if __nuppT65>0 then if __nuppT65>1 then __nuppT19(__nuppT15(__nuppT64[1],__nuppT64,2),0) else __nuppT19(__nuppT64[1],0) end end; if __nuppT62=="return" then  return __nuppT20(__nuppT63,1,__nuppT63.n)  end; end
end



local function describe ( line , said ) 
local shown = # line > 8192 and ( line : sub ( 1 , 8192 ) .. "..." ) or line
if said == "" then
return ("%q") : format ( shown )
end

return ("%q (it also said: %s)") : format ( shown , said )
end

local function requestService ( request , executable , host ) 
local encoded = ( json . encode ( protocolValue ( request ) ) )
if # encoded > 2097152 then
return nil , { code = "NUPP2416" , message = "comptime worker request exceeds 2097152 bytes" }
end
local channel , startFailure = startService ( executable , host )
if not channel then
return nil , startFailure
end
local text , stopped = workerchannel . request ( channel , encoded , clock . now ( ) + 10000 )
if text == nil then
stopService ( true )
local kind = stopped and stopped . kind or "ended"
local said = stopped and stopped . said or ""
if kind == "stopped" then
return nil , { code = "NUPP2412" , message = "comptime worker service stopped accepting requests" }
elseif kind == "cancelled" then
return nil , { code = "NUPP2412" , message = "comptime evaluation was canceled" }
elseif kind == "timeout" then
return nil , {
code = "NUPP2412" ,
message = ( ("comptime evaluation exceeded the %d ms worker timeout") : format ( 10000 ) ) ,
help = "make the computation smaller or move the unbounded work to run time" ,
}
elseif kind == "oversize" then
return nil , { code = "NUPP2416" , message = "comptime worker response exceeds 2097152 bytes" }
elseif kind == "invalid" then
return nil , {
code = "NUPP2412" ,
message = "comptime worker service returned an invalid response: " .. describe ( channel . head , said ) ,
}
end

return nil , {
code = "NUPP2412" ,
message = "the persistent comptime worker crashed: unexpected EOF" .. (
said ~= "" and ( " (it also said: " .. said .. ")" ) or ""
) ,
}
end
local decoded , response = decodeProtocol ( text )
if not decoded then
local said = channel . said
stopService ( true )
return nil , {
code = "NUPP2412" ,
message = "comptime worker service returned an invalid response: " .. describe ( text , said ) ,
}
end

return response , nil
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

local __nuppExportValue= worker ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.comptime.worker"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.comptime.worker"]=__nuppExports;return __nuppExports