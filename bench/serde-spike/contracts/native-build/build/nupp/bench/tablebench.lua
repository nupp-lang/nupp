_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local bench = { }

function bench . run ( ) 
local byObj = setmetatable ( { } , { __mode = "k" } )
local objs = { }
for i = 1 , 500 do
local o = { id = i }
objs [ i ] = o
byObj [ o ] = i * 3
end
local sum = 0
for i = 1 , 500 do
sum = sum + ( byObj [ objs [ i ] ] )
end
for i = 1 , 500 , 2 do
byObj [ objs [ i ] ] = nil
end
local count = 0
for _ , v in pairs ( byObj ) do
count = count + ( v )
end
local t = { }
for i = 1 , 300 do
t [ "k" .. i ] = i
end
for i = 1 , 300 , 3 do
t [ "k" .. i ] = nil
end
local n , seen = 0 , 0
local k = next ( t )
while k ~= nil do
n = n + 1
seen = seen + ( t [ k ] )
t [ k ] = ( t [ k ] ) + 1
k = next ( t , k )
end
local dup = 0
for i = 1 , 300 do
if t [ "k" .. i ] ~= nil then
dup = dup + ( t [ "k" .. i ] )
end
end

return sum , count , n , seen + dup
end

local __nuppExportValue= bench ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.bench.tablebench"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.bench.tablebench"]=__nuppExports;return __nuppExports