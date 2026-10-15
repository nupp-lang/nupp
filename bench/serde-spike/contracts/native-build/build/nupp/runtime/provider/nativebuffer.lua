_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.runtime.provider.nativebuffer"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local new;__nuppExports["new"]=function(...) return new(...) end;

















local native = require ( "string.buffer" )



new=function ( size , options ) 
if options ~= nil then
return native . new ( size , options )
end
if size ~= nil then
return native . new ( size )
end

return native . new ( )
end ;__nuppExports["new"]=new
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.nativebuffer"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.nativebuffer"]=__nuppExports;return __nuppExports