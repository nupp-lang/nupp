_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);const __nuppClear = require("table.clear"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.util.internal.pool\0runtime\0001") };































local pool = { }



pool.Pool = {} pool.Pool.__index = pool.Pool ;_G.nupp.__reflect.link(pool.Pool,__nuppT1[1],{ })






































function pool . Pool . acquire ( self ) 
self . liveCount = self . liveCount + 1
local count = self . freeCount
local value
if count == 0 then
value = setmetatable ( { } , self . witness )
else
value = self . freeList [ count ]
self . freeList [ count ] = nil
self . freeCount = count - 1
end
self . liveValues [ value ] = true

return value
end












function pool . Pool . release ( self , value ) 
if self . liveCount == 0 then
error ( "nupp: pool release without a live instance" , 2 )
end
if getmetatable ( value ) ~= self . witness then
error ( "nupp: pool release of a value the pool's declaration did not stamp" , 2 )
end
if not self . liveValues [ value ] then
error ( "nupp: pool release of a value not live in this pool" , 2 )
end
self . liveValues [ value ] = nil
self . liveCount = self . liveCount - 1
__nuppClear ( value )
local count = self . freeCount
if count >= self . capacity then
return
end
self . freeList [ count + 1 ] = value
self . freeCount = count + 1
end










function pool . Pool . reserve ( self , count ) 
if count < 0 then
error ( "nupp: pool reserve count cannot be negative" , 2 )
end
local free = self . freeCount
while free < count do
free = free + 1
self . freeList [ free ] = setmetatable ( { } , self . witness )
end
self . freeCount = free
end





function pool . Pool . live ( self ) 
return self . liveCount
end





function pool . Pool . free ( self ) 
return self . freeCount
end










function pool . Pool . reset ( self ) 
if self . liveCount > 0 then
error ( "nupp: pool reset with " .. tostring ( self . liveCount ) .. " live instances" , 2 )
end
self . freeList = { }
self . freeCount = 0
end


















function pool . new ( witness , capacity ) 
local retained = capacity or 32
if retained < 0 then
error ( "nupp: pool capacity cannot be negative" , 2 )
end
local created = _G.setmetatable({ witness =
witness ,  capacity =
retained ,  freeList =
{ } ,  freeCount =
0 ,  liveCount =
0 ,  liveValues =
{ } }, pool.Pool)

created : reserve ( retained )

return created
end

local __nuppExportValue= pool ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.util.internal.pool"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.util.internal.pool"]=__nuppExports;return __nuppExports