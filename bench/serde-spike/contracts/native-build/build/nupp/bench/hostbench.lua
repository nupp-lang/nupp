_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local host = require ( "nupp.bench.host" )

local bench = { }


function bench . readOne ( path ) 
local text = host . readFile ( path )
if text == nil then
return -1
end

return # text
end


function bench . readMany ( paths ) 
local total = 0
for _ , p in ipairs ( paths ) do
local text = host . readFile ( p )
if text ~= nil then
total = total + # text
end
end

return total
end



function bench . pingMany ( n ) 
local i = 0
while i < n do
host . sleep ( 0 )
i = i + 1
end

return i
end


function bench . sleepThen ( ms , v ) 
host . sleep ( ms )
return v
end


function bench . probe ( ) 
local t = host . now ( )
local home = host . getenv ( "HOME" )
return t , home
end

local __nuppExportValue= bench ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.bench.hostbench"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.bench.hostbench"]=__nuppExports;return __nuppExports