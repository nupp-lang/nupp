_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()




















local base64 = require ( "nupp.codec.base64" )
local contracts = require ( "nupp.util.spi" )
local response = require ( "nupp.runtime.browser.response" )
local crypto = { }

local function invalid ( kind ) 
error ( "nupp: browser crypto returned invalid " .. kind , 3 )
end

local function decoded ( value , field , count ) 
if type ( value ) ~= "table" or type ( value [ field ] ) ~= "string" then
invalid ( field )
end
local bytes = base64 . decode ( value [ field ] )
if bytes == nil or # bytes ~= count then
invalid ( field )
end

return bytes
end

local function random ( count , wallTime ) 
if count < 0 or count ~= math . floor ( count ) then
error ( "nupp: random byte count must be a non-negative integer" , 3 )
elseif count > 1048576 then
error ( "nupp: one random request cannot exceed 1048576 bytes" , 3 )
end

local value = response . await ( "random" , { count = count , wallTime = wallTime == true , } )
local bytes = decoded ( value , "bytesBase64" , count )
local timestamp = nil
if wallTime then
local given = value . wallTimeMs
if type ( given ) ~= "number" or given ~= math . floor ( given ) or given < 0 or given > 281474976710655 then
invalid ( "wall time" )
end
timestamp = given
end

return { bytes = bytes , wallTimeMs = timestamp , }
end

function crypto . randomBytes ( count ) 
return random ( count ) . bytes
end

function crypto . sha256 ( value ) 
local digest = response . await ( "sha256" , { bytesBase64 = base64 . encode ( value ) , } )
if type ( digest ) ~= "string" or # digest ~= 64 or digest : find ( "[^0-9a-f]" ) ~= nil then
invalid ( "SHA-256 digest" )
end

return digest
end

function crypto . digest ( key , message ) 
local value = response . await ( "hmac-sha256" , {
keyBase64 = base64 . encode ( key ) ,
messageBase64 = base64 . encode ( message ) ,
} )

return decoded ( value , "digestBase64" , 32 )
end

function crypto . hex ( key , message ) 
local digest = crypto . digest ( key , message )
return ( digest : gsub ( "." , function ( byte ) 
return ("%02x") : format ( byte : byte ( ) )
end ) )
end

local function canonical ( bytes ) 
local hex = { }
for index = 1 , 16 do
hex [ index ] = ("%02x") : format ( bytes [ index ] )
end

return table . concat (
hex ,
"" ,
1 ,
4
) .. "-" .. table . concat (
hex ,
"" ,
5 ,
6
) .. "-" .. table . concat (
hex ,
"" ,
7 ,
8
) .. "-" .. table . concat ( hex , "" , 9 , 10 ) .. "-" .. table . concat ( hex , "" , 11 , 16 )
end

local function byteTable ( raw ) 
local bytes = { }
for index = 1 , # raw do
bytes [ index ] = raw : byte ( index )
end

return bytes
end

function crypto . uuid4 ( ) 
local bytes = byteTable ( crypto . randomBytes ( 16 ) )
bytes [ 7 ] = bytes [ 7 ] % 16 + 64
bytes [ 9 ] = bytes [ 9 ] % 64 + 128
return canonical ( bytes )
end

function crypto . uuid7 ( ) 
local generated = random ( 10 , true )
local timestamp = generated . wallTimeMs
local bytes = { }
for index = 6 , 1 , -1 do
bytes [ index ] = timestamp % 256
timestamp = math . floor ( timestamp / 256 )
end
local tail = generated . bytes
for index = 1 , 10 do
bytes [ index + 6 ] = tail : byte ( index )
end
bytes [ 7 ] = bytes [ 7 ] % 16 + 112
bytes [ 9 ] = bytes [ 9 ] % 64 + 128

return canonical ( bytes )
end


const ANSWERS_UUID = { uuid4 = crypto . uuid4 , uuid7 = crypto . uuid7 , }
local __nuppExportValue= crypto ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.browser.crypto"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.browser.crypto"]=__nuppExports;return __nuppExports