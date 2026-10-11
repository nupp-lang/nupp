_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};local __nuppOk,__nuppWhy=pcall(function()
























const contracts = require ( "nupp.runtime.services.contracts" )

const provider = contracts . storage : assemble ( function ( ) 
return contracts . storage : require ( "nupp.browser" )
end )


const get = provider . get ;__nuppExports["get"]=get


const set = provider . set ;__nuppExports["set"]=set


const remove = provider . remove ;__nuppExports["remove"]=remove


const clear = provider . clear ;__nuppExports["clear"]=clear
 end);if not __nuppOk then package.loaded["nupp.io.storage"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.storage"]=__nuppExports;return __nuppExports