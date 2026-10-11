_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.util.internal.hash"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local fnv1a64;__nuppExports["fnv1a64"]=function(...) return fnv1a64(...) end;




const bit = require ( "bit" )

local function hashString ( bytes ) 
local hi = 3421674724
local lo = 2216829733
for index = 1 , # bytes do
lo = lo ~ bytes : byte ( index )
local low = lo < 0 and lo + 4294967296 or lo
local high = hi < 0 and hi + 4294967296 or hi
local product = low * 435
local carry = math . floor ( product / 4294967296 )
lo = bit . tobit ( product )
hi = bit . tobit ( high * 435 + low * 256 + carry )
end
local high = hi < 0 and hi + 4294967296 or hi
local low = lo < 0 and lo + 4294967296 or lo

return string . format ( "%08x%08x" , high , low )
end






fnv1a64=function ( value ) 
if type ( value ) == "string" then
return hashString ( value )
end

return hashString ( ( value ) : getString ( ) )
end ;__nuppExports["fnv1a64"]=fnv1a64
 end);if not __nuppOk then package.loaded["nupp.util.internal.hash"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.util.internal.hash"]=__nuppExports;return __nuppExports