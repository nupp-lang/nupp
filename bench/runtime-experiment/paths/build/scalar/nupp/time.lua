_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.time"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()





















local contracts = require ( "nupp.time.spi" )

local target = require ( "nupp.runtime.target" )
local __nuppT1= require ( "nupp.runtime.timeprovider" ) . provider ;if __nuppT1==nil then  local __nuppT2;do local __nuppT3,__nuppT4;repeat
if target . host == "native" then
do  __nuppT2= _G . require ( "nupp.runtime.provider.nativetime" ) ;__nuppT3=true;break end
end
assert ( target . host == "browser" and rawget ( _G , "__nuppBrowser" ) ~= nil , "nupp.time: no clock provider is available" )
do  __nuppT2= _G . require ( "nupp.runtime.browser.time" ) ;__nuppT3=true;break end
 until true; end; __nuppT1= __nuppT2 ;end; const provider = __nuppT1


const now = provider . now ;__nuppExports["now"]=now


const wallTime = provider . wallTime ;__nuppExports["wallTime"]=wallTime




const sleep = provider . sleep ;__nuppExports["sleep"]=sleep






const sleepUntil = provider . sleepUntil ;__nuppExports["sleepUntil"]=sleepUntil







const wakeAt = provider . wakeAt ;__nuppExports["wakeAt"]=wakeAt
 end);if not __nuppOk then package.loaded["nupp.time"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.time"]=__nuppExports;return __nuppExports