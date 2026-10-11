_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()
































local ffi = require ( "ffi" )
local bit = require ( "bit" )

local band = bit . band
local rshift = bit . rshift

local wire = {

CALL= 1 ,
POST= 2 ,
SEND= 3 ,
CANCEL= 4 ,
ABANDON= 5 ,
ABORT= 6 ,
ROUTES= 7 ,

ANSWER= 1 ,
MESSAGE= 2 ,
DROPPED= 3 ,

NIL= 0 ,
FALSE= 1 ,
TRUE= 2 ,
NUMBER= 3 ,
STRING= 4 ,
BYTES= 5 ,
UPLOAD= 6 ,
FETCH= 7 , }



local scratch = ffi . new ( "double[1]" )
local scratchBytes = ffi . cast ( "uint8_t *" , scratch )


function wire . writer ( capacity ) 
return { buffer = ffi . new ( "uint8_t[?]" , capacity ) , capacity = capacity , length = 0 }
end


function wire . reset ( writer ) 
writer . length = 0
end

local function reserve ( writer , count ) 
local needed = writer . length + count
if needed > writer . capacity then
local capacity = writer . capacity * 2
while capacity < needed do
capacity = capacity * 2
end
local grown = ffi . new ( "uint8_t[?]" , capacity )
ffi . copy ( grown , writer . buffer , writer . length )
writer . buffer = grown
writer . capacity = capacity
end
local at = writer . length
writer . length = needed

return at
end

function wire . u8 ( writer , value ) 
local at = reserve ( writer , 1 )
writer . buffer [ at ] = value
end

function wire . u16 ( writer , value ) 
local at = reserve ( writer , 2 )
local buffer = writer . buffer
buffer [ at ] = band ( value , 255 )
buffer [ at + 1 ] = band ( rshift ( value , 8 ) , 255 )
end

function wire . u32 ( writer , value ) 
local at = reserve ( writer , 4 )
local buffer = writer . buffer
buffer [ at ] = band ( value , 255 )
buffer [ at + 1 ] = band ( rshift ( value , 8 ) , 255 )
buffer [ at + 2 ] = band ( rshift ( value , 16 ) , 255 )
buffer [ at + 3 ] = band ( rshift ( value , 24 ) , 255 )
end

function wire . f64 ( writer , value ) 
local at = reserve ( writer , 8 )
local buffer = writer . buffer
scratch [ 0 ] = value
for index = 0 , 7 do
buffer [ at + index ] = scratchBytes [ index ]
end
end


function wire . raw ( writer , pointer , count ) 
local at = reserve ( writer , count )
if count > 0 then
ffi . copy ( writer . buffer + at , pointer , count )
end
end


function wire . sized ( writer , pointer , count ) 
wire . u32 ( writer , count )
wire . raw ( writer , pointer , count )
end


function wire . reader ( pointer , count ) 
return { buffer = ffi . cast ( "const uint8_t *" , pointer ) , length = count , at = 0 }
end

local function take ( reader , count ) 
local at = reader . at
if at + count > reader . length then
error ( "nupp: a host frame's inbox ended inside a record" , 0 )
end
reader . at = at + count

return at
end

function wire . readU8 ( reader ) 
return reader . buffer [ take ( reader , 1 ) ]
end

function wire . readU16 ( reader ) 
local at = take ( reader , 2 )
local buffer = reader . buffer

return ( buffer [ at ] + buffer [ at + 1 ] * 256 )
end

function wire . readU32 ( reader ) 
local at = take ( reader , 4 )
local buffer = reader . buffer

return ( buffer [ at ] + buffer [ at + 1 ] * 256 + buffer [ at + 2 ] * 65536 + buffer [ at + 3 ] * 16777216 )
end

function wire . readF64 ( reader ) 
local at = take ( reader , 8 )
local buffer = reader . buffer
for index = 0 , 7 do
scratchBytes [ index ] = buffer [ at + index ]
end

return scratch [ 0 ]
end


function wire . readString ( reader , count ) 
local at = take ( reader , count )

return ffi . string ( reader . buffer + at , count )
end

function wire . remaining ( reader ) 
return ( reader . length - reader . at )
end

local __nuppExportValue= wire ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.browser.hostwire"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.browser.hostwire"]=__nuppExports;return __nuppExports