_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.mem.indexed\0runtime\0001") };


























local indexed = { }



indexed.Range = {} indexed.Range.__index = indexed.Range ;_G.nupp.__reflect.link(indexed.Range,__nuppT1[1],{ })

























function indexed . range ( first , last , ... ) 
local count = select ( "#" , ... )
if count < 1 or first % 1 ~= 0 or last % 1 ~= 0 or first < 1 or last < first - 1 then
error ( "nupp: indexed range out of bounds" , 2 )
end
for index = 1 , count do
local candidate = select ( index , ... )
if not ( last <= candidate . count ) then
error ( "nupp: indexed range out of bounds" , 2 )
end
end

return ( _G.setmetatable({ first =  first ,  last =  last }, indexed.Range) )
end





function indexed . _rangeCounts ( first , last , ... ) 
local count = select ( "#" , ... )
if count < 1 or first % 1 ~= 0 or last % 1 ~= 0 or first < 1 or last < first - 1 then
error ( "nupp: indexed range out of bounds" , 2 )
end
for index = 1 , count do
if not ( last <= select ( index , ... ) ) then
error ( "nupp: indexed range out of bounds" , 2 )
end
end

return ( _G.setmetatable({ first =  first ,  last =  last }, indexed.Range) )
end




function indexed . _sliceFinish ( count , first , last , message ) 
local finish = last or count
if first % 1 ~= 0 or finish % 1 ~= 0 or first < 1 or finish < first - 1 or not ( finish <= count ) then
error ( message , 2 )
end

return finish
end






function indexed . _rootCount ( count , message ) 
if count % 1 ~= 0 or count < 0 then
error ( message , 2 )
end

return count
end





function indexed . _checkedIndex ( count , index , message ) 
if index % 1 ~= 0 or index < 1 or not ( index <= count ) then
error ( message , 2 )
end

return index
end

local __nuppExportValue= indexed ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.mem.indexed"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.mem.indexed"]=__nuppExports;return __nuppExports