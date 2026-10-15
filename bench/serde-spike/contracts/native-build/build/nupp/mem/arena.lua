_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.mem.arena\0runtime\0001") };




































local storage = require ( "nupp.runtime.storage" )
local arena = { }



arena.Arena = {} arena.Arena.__index = arena.Arena ;_G.nupp.__reflect.link(arena.Arena,__nuppT1[1],{ })




































local function addPage ( self , index ) 
local page = storage . allocateArray ( self . element , self . pageSize )
local cached = { }
do
for offset = 0 , self . pageSize - 1 do
cached [ offset + 1 ] = page [ offset ]
end
end
self . pageList [ index ] = page
self . rows [ index ] = cached
end










function arena . Arena . acquire ( self ) 
local cursor = self . cursor
local page = self . pageIndex
if cursor >= self . pageSize then
page = page + 1
cursor = 0
if self . pageList [ page ] == nil then
addPage ( self , page )
end
self . pageIndex = page
end
cursor = cursor + 1
self . cursor = cursor
self . usedCount = self . usedCount + 1
self . liveCount = self . liveCount + 1
local row = self . rows [ page ] [ cursor ]
rawset ( self . leases , row , true )
storage . fill ( row , self . width , 0 )

return row
end











function arena . Arena . release ( self , row ) 
if rawget ( self . leases , row ) ~= true then
error ( "nupp: arena release of a row without a live lease" , 2 )
end
rawset ( self . leases , row , false )
self . liveCount = self . liveCount - 1
end










function arena . Arena . reset ( self ) 
if self . liveCount > 0 then
error ( "nupp: arena reset with " .. tostring ( self . liveCount ) .. " live leases" , 2 )
end
self . pageIndex = 0
self . cursor = self . pageSize
self . usedCount = 0
end





function arena . Arena . pages ( self ) 
return # self . pageList
end





function arena . Arena . used ( self ) 
return self . usedCount
end





function arena . Arena . live ( self ) 
return self . liveCount
end


















function arena . newArena ( witness , pageSize ) 
local rows = pageSize or 256
if rows < 1 or rows % 1 ~= 0 then
error ( "nupp: arena page size must be a positive integer" , 2 )
end




local sample = ( witness ) ( )
local element = storage . descriptor ( sample )
local created = _G.setmetatable({ element =
element ,  width =
storage . sizeOf ( element ) ,  pageSize =
rows ,  pageList =
{ } ,  rows =
{ } ,  pageIndex =
0 ,  cursor =
rows ,  usedCount =
0 ,  liveCount =
0 ,  leases =
{ } }, arena.Arena)

addPage ( created , 1 )

return created
end

local __nuppExportValue= arena ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.mem.arena"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.mem.arena"]=__nuppExports;return __nuppExports