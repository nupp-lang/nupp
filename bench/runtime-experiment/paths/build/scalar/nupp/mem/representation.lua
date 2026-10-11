_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};local __nuppOk,__nuppWhy=pcall(function()

local spi = require ( "nupp.spi" )
local contracts = require ( "nupp.mem.representation.spi" )

local __nuppT1;do local __nuppT2,__nuppT3;repeat
const chosen = spi . select ( spi . load ("nupp.mem.representation.spi.CstorageProvider") )
if chosen ~= nil then
do  __nuppT1= chosen ;__nuppT2=true;break end
end
do  __nuppT1= _G . require ( "nupp.runtime.provider.nativestorage" ) ;__nuppT2=true;break end
 until true; end; const storage = __nuppT1 ;__nuppExports["storage"]=storage
if storage ~= nil then
assert ( storage . representation == "native" , "nupp.runtime.storage: target requires native pointer storage" )
end
local tableStructs = require ( "nupp.runtime.provider.tablestruct" )
const structs = storage and storage . structs or tableStructs ;__nuppExports["structs"]=structs
 end);if not __nuppOk then package.loaded["nupp.mem.representation"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.mem.representation"]=__nuppExports;return __nuppExports