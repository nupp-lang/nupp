_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.serde.internal.json.diagnostic"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local explain;__nuppExports["explain"]=function(...) return explain(...) end;


local syntax = require ( "nupp.serde.internal.json.syntax" )
local errors = require ( "nupp.serde.internal.errors" )
local numbers = require ( "nupp.serde.internal.numbers" )



local function validate ( recipe , cursor ) 
local kind = recipe . kind
if kind == "structure" then
cursor : start ( "object" )
local seen = { }
while true do
local name = cursor : nextKey ( )
if name == nil then
do break end
end
local field = nil
for _ , candidate in ipairs ( recipe . fields ) do
if candidate . wire == name then
field = candidate
do break end
end
end
assert ( field ~= nil , "unknown member: " .. name )
seen [ name ] = true
cursor : selectMember ( field . name )
validate ( field . target , cursor )
end
for _ , field in ipairs ( recipe . fields ) do
assert ( not field . required or seen [ field . wire ] , "missing required member: " .. field . name )
end
elseif kind == "list" or kind == "tuple" then
cursor : start ( "array" )
local index = 0
while cursor : next ( "array" ) do
index += 1
local item = kind == "list" and recipe . element or recipe . items [ index ]
assert ( item ~= nil , "too many tuple elements" )
validate ( item , cursor )
end
assert ( kind ~= "tuple" or index == # recipe . items , "missing tuple elements" )
elseif kind == "map" then
cursor : start ( "object" )
while cursor : nextKey ( ) ~= nil do
validate ( recipe . value , cursor )
end
elseif kind == "string" then
cursor : readString ( )
elseif kind == "boolean" then
cursor : readBoolean ( )
else
local token = cursor : readNumber ( )
if recipe . strictInteger then
numbers . integer ( token , recipe . width , recipe . signed )
else
local value = tonumber ( token )
assert (
value ~= nil and value == value and value ~= math . huge and value ~= - math . huge ,
"expected finite number"
)
assert ( kind ~= "integer" or value % 1 == 0 , "expected integer" )
end
end
end

explain=function ( recipe , bytes , original ) 
local cursor = syntax . reader ( bytes )
local valid , problem = pcall ( validate , recipe , cursor )
if valid then
valid , problem = pcall ( cursor . finish , cursor )
end
if not valid then
return errors . wrap ( problem , cursor : path ( ) , cursor : offset ( ) )
end

return errors . wrap ( original , "$" , nil )
end ;__nuppExports["explain"]=explain
 end);if not __nuppOk then package.loaded["nupp.serde.internal.json.diagnostic"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.json.diagnostic"]=__nuppExports;return __nuppExports