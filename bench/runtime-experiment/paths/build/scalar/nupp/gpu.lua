_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};local __nuppOk,__nuppWhy=pcall(function()











































local spi = require ( "nupp.spi" )
local target = require ( "nupp.runtime.target" )

local api = require ( "nupp.gpu.api" )
local implementation = require ( "nupp.gpu.types" )
local contract = require ( "nupp.gpu.spi" )
local __nuppT1;do local __nuppT2,__nuppT3;repeat
const chosen = spi . select ( spi . load ("nupp.gpu.spi.Provider") )
if chosen ~= nil then
do  __nuppT1= chosen ;__nuppT2=true;break end
end
if target . host == "native" then
do  __nuppT1= _G . require ( "nupp.runtime.provider.nativegpu" ) ;__nuppT2=true;break end
end
do  __nuppT1= _G . require ( "nupp.runtime.browser.webgpu.internal" ) ;__nuppT2=true;break end
 until true; end; local provider = __nuppT1
local operations = require ( "nupp.gpu.operations" )
local tensorlayout = require ( "nupp.gpu.layout" )


const Layout = tensorlayout . Layout ;__nuppExports["Layout"]=Layout




const PORTABLE_WORKGROUP_THREADS = implementation . PORTABLE_WORKGROUP_THREADS ;__nuppExports["PORTABLE_WORKGROUP_THREADS"]=PORTABLE_WORKGROUP_THREADS
const PORTABLE_SCRATCH_BYTES = implementation . PORTABLE_SCRATCH_BYTES ;__nuppExports["PORTABLE_SCRATCH_BYTES"]=PORTABLE_SCRATCH_BYTES
const workgroups



= operations . workgroups ;__nuppExports["workgroups"]=workgroups






const available = provider . available ;__nuppExports["available"]=available


const open = provider . open ;__nuppExports["open"]=open
 end);if not __nuppOk then package.loaded["nupp.gpu"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.gpu"]=__nuppExports;return __nuppExports