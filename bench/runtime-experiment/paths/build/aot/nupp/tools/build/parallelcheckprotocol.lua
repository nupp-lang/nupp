_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()












local hasBuffer , nativeBuffer = pcall ( require , "string.buffer" )

local protocol = {


available= hasBuffer ,


MAX_FRAME= 268435456 , }

function protocol . encode ( value ) 
return nativeBuffer . encode ( { schema = 1 , value = value } )
end

function protocol . decode ( text ) 
if not hasBuffer then
return nil , "parallel-check payloads are unavailable on this host"
end
local decoded , envelope = pcall ( nativeBuffer . decode , text )
if not decoded or type ( envelope ) ~= "table" or envelope . schema ~= 1 or type ( envelope . value ) ~= "table" then
return nil , "the parallel-check payload is malformed"
end

return envelope . value , nil
end

local __nuppExportValue= protocol ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.parallelcheckprotocol"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.parallelcheckprotocol"]=__nuppExports;return __nuppExports