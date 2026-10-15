_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};local __nuppOk,__nuppWhy=pcall(function()


const _DYNAMIC_REQUIRES = "@requires-dynamically nupp.runtime.provider.workers @requires-dynamically nupp.runtime.browser.workers"

local spi = require ( "nupp.spi" )
local target = require ( "nupp.runtime.target" )
local contracts = require ( "nupp.workers.spi" )




local function available ( name ) 
local wasPresent = package . loaded [ name ] ~= nil or package . preload [ name ] ~= nil
local ok , value = pcall ( require , name )
if ok then
return value
end
local wasMissing = tostring ( value ) : find ( "module '" .. name .. "' not found:" , 1 , true ) == 1
if wasPresent or not wasMissing then
error ( value , 0 )
end

return nil
end

local __nuppT2;do local __nuppT3,__nuppT4;repeat
const chosen = spi . select ( spi . load ("nupp.workers.spi.Provider") )
if chosen ~= nil then
do  __nuppT2= chosen ;__nuppT3=true;break end
end
if target . host == "native"
and ( package . preload [ "nupp.workers.native" ] ~= nil or package . loaded [ "nupp.workers.native" ] ~= nil )
then
do  __nuppT2= available ( "nupp.runtime.provider.workers" ) ;__nuppT3=true;break end
end
if target . host == "browser" and rawget ( _G , "__nuppBrowser" ) ~= nil then
do  __nuppT2= available ( "nupp.runtime.browser.workers" ) ;__nuppT3=true;break end
end
do  __nuppT2= nil ;__nuppT3=true;break end
 until true; end; const provider = __nuppT2 ;__nuppExports["provider"]=provider
 end);if not __nuppOk then package.loaded["nupp.runtime.workersprovider"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.workersprovider"]=__nuppExports;return __nuppExports