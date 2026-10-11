_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.util.internal.store"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local newKey;__nuppExports["newKey"]=function(...) return newKey(...) end;local newStore;__nuppExports["newStore"]=function(...) return newStore(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.util.internal.store\0runtime\0001") };













local nextId = 1
local named = { }
local names = { }

local function nextRegistered ( _ , after ) 
local id = after + 1
local last = nextId - 1
while id <= last do
local name = names [ id ]
if name ~= nil then
return id , name
end
id = id + 1
end

return nil , nil
end








local Key = {} Key.__index = Key

















function Key.find(name) 
return named [ name ]
end










function Key.registered() 
return nextRegistered , nil , 0
end ;_G.nupp.__reflect.link(Key,__nuppT1[1],{ }) ;__nuppExports["Key"]=Key











newKey=function ( name ) 
if name ~= nil then
if name == "" then
error ( "nupp: a key name must not be empty" , 2 )
elseif named [ name ] ~= nil then
error ( "nupp: key " .. name .. " is already registered" , 2 )
end
end
local key = _G.setmetatable({ id =  nextId ,  name =  name ,  _valueType =  nil ,  _inferredType =  nil }, Key)
nextId = nextId + 1
if name ~= nil then
named [ name ] = key
names [ key . id ] = name
end

return key
end ;__nuppExports["newKey"]=newKey






























local Bag = {} Bag.__index = Bag






newStore=function ( ) 
return ( _G.setmetatable({ values =  { } }, Bag) )
end ;__nuppExports["newStore"]=newStore

function Bag . get ( self , key ) 
return self . values [ key . id ]
end

function Bag . set ( self , key , value ) 
if value == nil then
error ( "nupp: Store:set value must not be nil; use Store:remove" , 2 )
end
self . values [ key . id ] = value
end

function Bag . remove ( self , key ) 
self . values [ key . id ] = nil
end

function Bag . clear ( self ) 
self . values = { }
end








local function step ( store , after ) 
local id = after + 1
local last = nextId - 1
while id <= last do
local value = store . values [ id ]
if value ~= nil then
return id , names [ id ] , type ( value )
end
id = id + 1
end

return nil , nil , nil
end












function Bag . entries ( self ) 
return step , self , 0
end
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Key]="nupp.util.internal.store\0Key"; end);if not __nuppOk then package.loaded["nupp.util.internal.store"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.util.internal.store"]=__nuppExports;return __nuppExports