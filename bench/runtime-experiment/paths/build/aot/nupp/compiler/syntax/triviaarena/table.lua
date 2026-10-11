_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





local provider = { }
const STRIDE = 5

local TableArena = {} TableArena.__index = TableArena





function TableArena : append ( kind , offset , length , line , col ) 
local at = self . count * 5
self . words [ at + 1 ] = kind
self . words [ at + 2 ] = offset
self . words [ at + 3 ] = length
self . words [ at + 4 ] = line
self . words [ at + 5 ] = col
self . count = self . count + 1

return self . count
end

function TableArena : record ( index ) 
if index < 1 or index > self . count then
error ( "nupp: trivia record " .. index .. " is outside 1.." .. self . count , 2 )
end
local at = ( index - 1 ) * 5

return self . words [ at + 1 ] , self . words [ at + 2 ] , self . words [ at + 3 ] , self . words [ at + 4 ] , self . words [ at + 5 ]
end

function provider . new ( source ) 
return ( _G.setmetatable({ source =  source ,  count =  0 ,  words =  { } }, TableArena) )
end

local __nuppExportValue= provider ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.syntax.triviaarena.table"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.syntax.triviaarena.table"]=__nuppExports;return __nuppExports