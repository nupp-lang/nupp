_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()




local bundled = require ( "nupp.compiler.bundled" )
local files = require ( "nupp.io.files" )
local resource = { source = bundled . source , }

function resource . list ( prefix ) 
local embedded = package . preload [ "nupp.embedded" ]
if embedded then
local found = bundled . embeddedUnder ( embedded ( ) , prefix )






if # found > 0 then
table . sort ( found )
return found
end
end
local found , pending = { } , { prefix }
while # pending > 0 do
local relative = table . remove ( pending )
for _ , entry in ipairs ( files . list ( bundled . moduleDir ( ) .. relative ) or { } ) do
local child = relative .. "/" .. entry . name
if entry . kind == "directory" then
pending [ # pending + 1 ] = child
elseif entry . kind == "file" then
found [ # found + 1 ] = child
end
end
end
table . sort ( found )

return found
end

local __nuppExportValue= resource ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.bundledlist"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.bundledlist"]=__nuppExports;return __nuppExports