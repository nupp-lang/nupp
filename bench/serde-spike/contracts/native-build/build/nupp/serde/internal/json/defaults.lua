_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.serde.internal.json.defaults"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()

local core = require ( "nupp.serde.internal.value" )
local plans = require ( "nupp.serde.internal.json.plan" )
local declarations = require ( "nupp.serde.internal.declaration" )
local documents = require ( "nupp.serde.internal.document" )
local declarationPolicy = declarations . policy ( )
local Factory = {} Factory.__index = Factory
function Factory:policy(member) 
local documentPolicy = documents . policy ( member , false )
if documentPolicy ~= nil then
return documentPolicy
end

return declarationPolicy : policy ( member )
end

const factory = _G.setmetatable({ }, Factory) ;__nuppExports["factory"]=factory
 end);if not __nuppOk then package.loaded["nupp.serde.internal.json.defaults"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.json.defaults"]=__nuppExports;return __nuppExports