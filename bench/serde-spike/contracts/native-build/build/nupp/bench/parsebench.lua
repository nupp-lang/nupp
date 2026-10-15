_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()




local parser = require ( "nupp.compiler.syntax.parser" )

local triviaarena = require ( "nupp.compiler.syntax.triviaarena" )
local tableProvider = require ( "nupp.compiler.syntax.triviaarena.table" )

local bench = { }

function bench . setup ( ) 
triviaarena . install ( tableProvider )
return true
end



local function walk ( node , sum , count ) 
local kind = node . kind
if kind == nil then
return sum , count
end
for i = 1 , # kind do
sum = ( sum * 31 + string . byte ( kind , i ) ) % 1000000007
end
count = count + 1
if node . text ~= nil and node . line ~= nil then
sum = ( sum * 31 + # node . text + node . line * 7 + node . col ) % 1000000007
return sum , count
end
for _ , child in ipairs ( node ) do
sum , count = walk ( child , sum , count )
end

return sum , count
end



function bench . parse ( source ) 
local result = parser . parse ( source , "bench.nupp" )
local sum , count = walk ( result . root , 0 , 0 )
return count , # result . errors , sum
end


local function dumpInto ( node , out , depth ) 
local kind = node . kind
if kind == nil then
return
end
if node . text ~= nil and node . line ~= nil then
out [ # out + 1 ] = string . rep ( " " , depth ) .. kind .. " " .. node . text .. " " .. node . line .. ":" .. node . col
return
end
out [ # out + 1 ] = string . rep ( " " , depth ) .. kind
for _ , child in ipairs ( node ) do
dumpInto ( child , out , depth + 1 )
end
end

function bench . dump ( source ) 
local result = parser . parse ( source , "bench.nupp" )
local out = { }
dumpInto ( result . root , out , 0 )
return table . concat ( out , "\n" )
end

local __nuppExportValue= bench ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.bench.parsebench"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.bench.parsebench"]=__nuppExports;return __nuppExports