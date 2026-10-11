_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()













local store = require ( "nupp.util.internal.store" )

local extensions = { }
local states = setmetatable ( { } , { __mode = "k" } )




local providers = { }



function extensions . key ( build ) 
local key = store . newKey ( nil )
providers [ key . id ] = build

return key
end



function extensions . host ( value ) 
if states [ value ] == nil then
states [ value ] = { values = { } }
end
return value
end








function extensions . resolve ( host , key ) 
local state = states [ host ]
if state == nil then
error ( "nupp: value is not an extension host" , 2 )
end
local token = key
local slot = token . id
if slot == nil or providers [ slot ] == nil then
error ( "nupp: value is not an extension key" , 2 )
end
local index = slot
local build = providers [ index ]
local cached = state . values [ index ]
if cached ~= nil then
if cached . state == "ready" then
return cached . value
elseif cached . state == "failed" then
error ( cached . error , 2 )
end
error ( "nupp: recursive extension initialization" , 2 )
end
local initializing = { state = "initializing" }
state . values [ index ] = initializing
local ok , value = pcall ( build , host )
if not ok then
initializing . state = "failed"
initializing . error = tostring ( value )
error ( initializing . error , 2 )
end
initializing . state = "ready"
initializing . value = value

return value
end

local __nuppExportValue= extensions ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.runtime.extensions"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.runtime.extensions"]=__nuppExports;return __nuppExports