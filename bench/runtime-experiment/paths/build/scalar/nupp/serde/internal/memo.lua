_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.serde.internal.memo"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local new;__nuppExports["new"]=function(...) return new(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.memo\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.serde.internal.memo\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.serde.internal.memo\0runtime\0003") };













local core = require ( "nupp.serde.internal.value" )


local Slot = {} Slot.__index = Slot ;_G.nupp.__reflect.link(Slot,__nuppT1[1],{ }) ;__nuppExports["Slot"]=Slot




local Entry = {} Entry.__index = Entry ;_G.nupp.__reflect.link(Entry,__nuppT1[2],{ __nuppT1[1] })






local Memo = {} Memo.__index = Memo



















function Memo:find(key, direction) 
local entry = self . lastKey == key and self . lastEntry or nil
if entry == nil then
entry = self . entries [ key ]
if entry == nil then
return false , nil
end
self . clock += 1
entry . used = self . clock
self . lastKey , self . lastEntry = key , entry
end
local slot = nil
if direction == "write" then
slot = entry . write
else
slot = entry . read
end
if slot == nil then
return false , nil
elseif slot . state == "ready" then
return true , slot . value
elseif slot . state == "failed" then
error ( slot . value , 0 )
end

error ( "recursive " .. self . label .. " initialization" , 0 )
end







function Memo:start(key, direction) 
local entry = self . entries [ key ]
if entry == nil then
if self . count >= self . capacity then
self : evict ( )
end
entry = _G.setmetatable({ used =  self . clock }, Entry)
self . entries [ key ] = entry
self . count += 1
end
self . clock += 1
entry . used = self . clock
self . lastKey , self . lastEntry = key , entry
local slot = _G.setmetatable({ state =  "initializing" }, Slot)
if direction == "write" then
entry . write = slot
else
entry . read = slot
end
self . active += 1

return slot
end











function Memo:finish(slot, ok, value) 
self . active -= 1
slot . state , slot . value = ok and "ready" or "failed" , value
if not ok then
error ( value , 0 )
end

return value
end



function Memo:clear() 
if self . active ~= 0 then
error ( "cannot clear the " .. self . label .. " cache while it is initializing" , 2 )
end
self . entries , self . count , self . clock = { } , 0 , 0
self . lastKey , self . lastEntry = nil , nil
end


function Memo:size() 
return self . count
end



function Memo:evict() 
local oldest = nil
local age = self . clock + 1
for key , entry in pairs ( self . entries ) do
local busy = entry . write ~= nil and entry . write . state == "initializing"
or entry . read ~= nil and entry . read . state == "initializing"
if not busy and entry . used < age then
oldest , age = key , entry . used
end
end
if oldest == nil then
error ( self . label .. " capacity exhausted by active initialization" , 3 )
end
self . entries [ oldest ] = nil
if self . lastKey == oldest then
self . lastKey , self . lastEntry = nil , nil
end
self . count -= 1
end ;_G.nupp.__reflect.link(Memo,__nuppT1[3],{ __nuppT1[2] }) ;__nuppExports["Memo"]=Memo








new=function ( label , capacity ) 
local limit = capacity or 256
if limit < 1 or limit % 1 ~= 0 then
error ( label .. " capacity must be a positive integer" , 2 )
end

return ( _G.setmetatable({ label =  label ,  capacity =  limit ,  entries =  {} ,  count =  0 ,  clock =  0 ,  active =  0 ,  lastKey =  nil ,  lastEntry =  nil }, Memo) )
end ;__nuppExports["new"]=new
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Memo]="nupp.serde.internal.memo\0Memo";__nuppWorkerRecords[Slot]="nupp.serde.internal.memo\0Slot"; end);if not __nuppOk then package.loaded["nupp.serde.internal.memo"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.memo"]=__nuppExports;return __nuppExports