_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.digest.internal.builtin"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local hmacSha256;__nuppExports["hmacSha256"]=function(...) return hmacSha256(...) end;local lookup;__nuppExports["lookup"]=function(...) return lookup(...) end;local names;__nuppExports["names"]=function(...) return names(...) end;














const provider = require ( "nupp.digest.spi" )
const streaming = require ( "nupp.digest.internal.streaming" )
const span = require ( "nupp.mem.span" )
const storage = require ( "nupp.runtime.storage" )
const words = require ( "nupp.digest.internal.words" )

local State = {} State.__index = State


function State:update(bytes) 

local offset = 1
while offset <= bytes .count do
local last = math . min ( offset + 4095 , bytes .count )
local part = bytes : slice ( offset , last )
local pointer , count = part : ref ( )
self . value : update ( storage . string ( pointer , count ) )
offset = last + 1
end
end

function State:finish(destination) 
self . value : writeDigest ( destination )
end

function State:close() 

end


local Algorithm = {} Algorithm.__index = Algorithm



function Algorithm:create() 
if self . name == "sha256" then
return ( _G.setmetatable({ value =  streaming . sha256 ( ) }, State) )
end
return ( _G.setmetatable({ value =  words . create ( self . name ) }, State) )
end


const ALGORITHMS

= {
md5 = _G.setmetatable({ name =  "md5" ,  digestSize =  16 }, Algorithm) ,
sha1 = _G.setmetatable({ name =  "sha1" ,  digestSize =  20 }, Algorithm) ,
sha256 = _G.setmetatable({ name =  "sha256" ,  digestSize =  32 }, Algorithm) ,
sha512 = _G.setmetatable({ name =  "sha512" ,  digestSize =  64 }, Algorithm) ,
}

lookup=function ( name ) 
return ALGORITHMS [ name ]
end ;__nuppExports["lookup"]=lookup

names=function ( ) 
return { "md5" , "sha1" , "sha256" , "sha512" }
end ;__nuppExports["names"]=names

hmacSha256=function ( key ) 
return ( _G.setmetatable({ value =  streaming . hmac ( key ) }, State) )
end ;__nuppExports["hmacSha256"]=hmacSha256
 end);if not __nuppOk then package.loaded["nupp.digest.internal.builtin"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.digest.internal.builtin"]=__nuppExports;return __nuppExports