_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};local __nuppOk,__nuppWhy=pcall(function()





















local spi = require ( "nupp.spi" )
local target = require ( "nupp.runtime.target" )

local contract = require ( "nupp.system.spi" )
local __nuppT1;do local __nuppT2,__nuppT3;repeat
const chosen = spi . select ( spi . load ("nupp.system.spi.Provider") )
if chosen ~= nil then
do  __nuppT1= chosen ;__nuppT2=true;break end
end
if target . host == "native" then
do  __nuppT1= _G . require ( "nupp.runtime.provider.nativesystem" ) ;__nuppT2=true;break end
end
do  __nuppT1= _G . require ( "nupp.runtime.browser.system" ) ;__nuppT2=true;break end
 until true; end; local provider = __nuppT1
if provider . platform == "" or provider . architecture == "" then
error ( "system provider must name its platform and architecture" , 2 )
end
if provider . endianness ~= "little" and provider . endianness ~= "big" then
error ( "system provider endianness must be little or big" , 2 )
end
if provider . pointerBits ~= 32 and provider . pointerBits ~= 64 then
error ( "system provider pointerBits must be 32 or 64" , 2 )
end






const platform = provider . platform ;__nuppExports["platform"]=platform





const architecture = provider . architecture ;__nuppExports["architecture"]=architecture


const endianness = provider . endianness ;__nuppExports["endianness"]=endianness





const pointerBits = provider . pointerBits ;__nuppExports["pointerBits"]=pointerBits
















const availableParallelism = provider . availableParallelism ;__nuppExports["availableParallelism"]=availableParallelism
 end);if not __nuppOk then package.loaded["nupp.system"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.system"]=__nuppExports;return __nuppExports