_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()












local triviaarena = { }















local selected



function triviaarena . install ( provider ) 
if selected ~= nil and selected ~= provider then
error ( "nupp: compiler trivia arena provider is already selected" , 2 )
end
selected = provider
end






local function load ( name ) 
return require ( "nupp.compiler.syntax.triviaarena." .. name )
end

local function provider ( ) 
if selected == nil then


selected = ( require ( "nupp.compiler.syntax.triviaarena." .. "ffi" ) )
end

return selected
end

function triviaarena . new ( source ) 
return provider ( ) . new ( source )
end

local __nuppExportValue= triviaarena ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.syntax.triviaarena"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.syntax.triviaarena"]=__nuppExports;return __nuppExports