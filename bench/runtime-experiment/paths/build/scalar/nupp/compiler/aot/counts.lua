_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()









local scalarIR = require ( "nupp.compiler.aot.scalar" )

local counts = { }




function counts . equal ( program , roots ) 
local order = { }
for position , param in ipairs ( program . params ) do
if ( param . kind == "write_span" or param . kind == "read_span" ) and roots [ param . name ] == nil then
order [ param . name ] = position
end
end
local atMost = { }
for _ , relation in ipairs ( program . relations or { } ) do
local left , right = relation . left , relation . right
if relation . offset == 0 and left . kind == "count" and right . kind == "count" then
atMost [ tostring ( left . name ) .. " " .. tostring ( right . name ) ] = true
end
end
local parent = { }

local function find ( name ) 
local next = parent [ name ]
while next ~= nil and next ~= name do
name = next
next = parent [ name ]
end

return name
end

for key in pairs ( atMost ) do
local left , right = key : match ( "^(%S+) (%S+)$" )
if left ~= nil
and right ~= nil
and order [ left ] ~= nil
and order [ right ] ~= nil
and atMost [ tostring ( right ) .. " " .. tostring ( left ) ]
then
local a , b = find ( left ) , find ( right )
if a ~= b then
if order [ a ] < order [ b ] then
parent [ b ] = a
else
parent [ a ] = b
end
end
end
end
local aliases = { }
for name in pairs ( order ) do
local root = find ( name )
if root ~= name then
aliases [ name ] = root
end
end

return aliases
end


function counts . roots ( program ) 
local roots = { }
for _ , param in ipairs ( program . params ) do
if param . soa ~= nil then
roots [ param . name ] = param . soa . view
end
end

return roots
end

local __nuppExportValue= counts ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.counts"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.counts"]=__nuppExports;return __nuppExports