_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.checksum.internal.builtin"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local lookup;__nuppExports["lookup"]=function(...) return lookup(...) end;local names;__nuppExports["names"]=function(...) return names(...) end;








const provider = require ( "nupp.checksum.spi" )
const span = require ( "nupp.mem.span" )
const target = require ( "nupp.runtime.target" )
const ffi = require ( "ffi" )

ffi . cdef [[
int32_t nuppCrcUpdate(uint32_t, int32_t, uint64_t *, const uint8_t *, size_t);
const char *nuppCrcLastError(void);
]]

local __nuppT1;do local __nuppT2,__nuppT3;repeat
if target . host == "native" then
do  __nuppT1= _G . require ( "nupp.runtime.provider.nativecrc" ) ;__nuppT2=true;break end
end
do  __nuppT1= _G . require ( "nupp.runtime.browser.crc" ) ;__nuppT2=true;break end
 until true; end; local C = __nuppT1

local function crcUpdate ( id , reset , words , bytes , count ) 
local update = C . nuppCrcUpdate
if update ( id , reset , words , bytes , count ) ~= 0 then
error ( "nupp: " .. ffi . string ( C . nuppCrcLastError ( ) ) , 2 )
end
end

local AdlerState = {} AdlerState.__index = AdlerState



function AdlerState:update(bytes) 
for index = 1 , bytes .count do
self . low = ( self . low + bytes .pointer[ bytes .offset+ index -1] ) % 65521
self . high = ( self . high + self . low ) % 65521
end
end

function AdlerState:value() 
return 0ULL + self . high * 65536 + self . low
end

function AdlerState:close() 
end


local CrcState = {} CrcState.__index = CrcState



function CrcState:update(bytes) 
crcUpdate ( self . id , 0 , self . words , bytes : ref ( ) , bytes .count )
end

function CrcState:value() 
return self . words [ 1 ]
end

function CrcState:close() 
end


local Algorithm = {} Algorithm.__index = Algorithm




function Algorithm:create() 
if self . id == 0 then
return ( _G.setmetatable({ high =  0 ,  low =  1 }, AdlerState) )
end
local words = ffi . new ( "uint64_t[2]" )
const empty = ""
local bytes = span . fromString ( empty )
crcUpdate ( self . id , 1 , words , bytes : ref ( ) , 0 )

return ( _G.setmetatable({ id =  self . id ,  words =  words }, CrcState) )
end


const ALGORITHMS

= {
adler32 = _G.setmetatable({ name =  "adler32" ,  width =  32 ,  id =  0 }, Algorithm) ,
crc32 = _G.setmetatable({ name =  "crc32" ,  width =  32 ,  id =  1 }, Algorithm) ,
crc32c = _G.setmetatable({ name =  "crc32c" ,  width =  32 ,  id =  2 }, Algorithm) ,
[ "crc64-ecma" ] = _G.setmetatable({ name =  "crc64-ecma" ,  width =  64 ,  id =  3 }, Algorithm) ,
crc64nvme = _G.setmetatable({ name =  "crc64nvme" ,  width =  64 ,  id =  4 }, Algorithm) ,
}

lookup=function ( name ) 
return ALGORITHMS [ name ]
end ;__nuppExports["lookup"]=lookup

names=function ( ) 
return { "adler32" , "crc32" , "crc32c" , "crc64-ecma" , "crc64nvme" }
end ;__nuppExports["names"]=names
 end);if not __nuppOk then package.loaded["nupp.checksum.internal.builtin"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.checksum.internal.builtin"]=__nuppExports;return __nuppExports