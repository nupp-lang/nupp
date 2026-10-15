_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local function stable ( value , seen ) 
local kind = type ( value )

if kind == "nil" then
return "nil"
end
if kind == "boolean" or kind == "number" then
return tostring ( value )
end

if kind == "string" then
return ("%q") : format ( value )
end

if kind ~= "table" then
return "<" .. kind .. ">"
end
local entries = value
seen = seen or { }
if seen [ value ] then
return "<cycle>"
end
seen [ value ] = true
local parts = { }
for key in pairs ( entries ) do
parts [ # parts + 1 ] = stable ( key , seen ) .. "=" .. stable ( entries [ key ] , seen )
end
table . sort ( parts )
seen [ value ] = nil

return "{" .. table . concat ( parts , "," ) .. "}"
end

local __nuppExportValue= stable ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.stable"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.stable"]=__nuppExports;return __nuppExports