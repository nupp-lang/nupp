_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()














































local contracts = require ( "nupp.workers.spi" )
local target = require ( "nupp.runtime.target" )
local __nuppT1= require ( "nupp.runtime.workersprovider" ) . provider ;if __nuppT1==nil then  local __nuppT2;do local __nuppT3,__nuppT4;repeat
if target . host == "native" then
assert (
package . preload [ "nupp.workers.native" ] ~= nil or package . loaded [ "nupp.workers.native" ] ~= nil ,
"nupp.workers: no worker provider is available"
)
do  __nuppT2= _G . require ( "nupp.runtime.provider.workers" ) ;__nuppT3=true;break end
end
assert (
target . host == "browser" and rawget ( _G , "__nuppBrowser" ) ~= nil ,
"nupp.workers: no worker provider is available"
)
do  __nuppT2= _G . require ( "nupp.runtime.browser.workers" ) ;__nuppT3=true;break end
 until true; end; __nuppT1= __nuppT2 ;end; local provider = __nuppT1
local workers = { }



rawset ( workers , "__scope" , provider . openScope )
rawset ( workers , "__settle" , provider . settle )
rawset ( workers , "__runScheduler" , provider . runScheduler )
rawset ( workers , "__defineSendable" , provider . defineSendable )
rawset ( workers , "__sendable" , provider . describeSendable )

local __nuppExportValue= workers ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.workers"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.workers"]=__nuppExports;return __nuppExports