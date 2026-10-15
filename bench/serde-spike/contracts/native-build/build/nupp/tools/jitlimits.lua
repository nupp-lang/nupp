_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



































local jitlimits = { }





jitlimits . FLAGS = { "maxtrace=20000" , "maxside=1000" , "sizemcode=16384" , "maxmcode=16384" }












function jitlimits . apply ( ) 
if os . getenv ( "NUPP_JIT_DEFAULT" ) then
return false
end
local flags = jitlimits . FLAGS
local override = os . getenv ( "NUPP_JIT_LIMITS" )
if override then
flags = { }
for flag in override : gmatch ( "[^,]+" ) do
flags [ # flags + 1 ] = flag
end
end
if # flags == 0 then
return false
end


if not pcall ( jit . opt . start , unpack ( flags ) ) then
return false
end
jit . flush ( )

return true
end

local __nuppExportValue= jitlimits ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.jitlimits"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.jitlimits"]=__nuppExports;return __nuppExports