_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;







local dynamic = { }

local STORE_REGISTRY_KEY = "__nuppDynamicStores"
local stores = _G [ STORE_REGISTRY_KEY ]
if not stores then
stores = setmetatable ( { } , { __mode = "k" } )
_G [ STORE_REGISTRY_KEY ] = stores
end


dynamic.Error = {} dynamic.Error.__index = dynamic.Error




const Entry = {} Entry.__index = Entry








dynamic.Handle = {} dynamic.Handle.__index = dynamic.Handle







dynamic.ErasedHandle = {} dynamic.ErasedHandle.__index = dynamic.ErasedHandle







dynamic.StoreState = {} dynamic.StoreState.__index = dynamic.StoreState








function dynamic.StoreState:_put(value, cleanup, policy)
assert ( not self . destroyed , "dynamic store is destroyed" )
local slot = self . nextSlot
self . nextSlot = slot + 1
local generation = self . generations [ slot ] or 1
self . entries [
slot
] = setmetatable({ value =  value ,  cleanup =  cleanup ,  policy =  policy ,  generation =  generation }, Entry)

return setmetatable({ store =
self ,  slot =
slot ,  generation =
generation ,  policy =
policy }, dynamic.Handle)

end






function dynamic.StoreState:put(value)
local _raw = value
error ( "dynamic.Store.put must be lowered by the compiler" , 2 )
end

function dynamic.StoreState:with(handle, callback)




local entry , problem = self : _entry ( handle )
if not entry then
return nil , problem
end

return callback ( entry . value ) , nil
end

function dynamic.StoreState:withExclusive(handle, callback)




local entry , problem = self : _entry ( handle )
if not entry then
return nil , problem
end

return callback ( entry . value ) , nil
end

function dynamic.StoreState:take(handle)
local entry , problem = self : _entry ( handle )
if not entry then
return nil , problem
end
self . entries [ handle . slot ] = nil
self . generations [ handle . slot ] = entry . generation + 1

return entry . value , nil
end

function dynamic.StoreState:remove(handle)
local entry , problem = self : _entry ( handle )
if not entry then
return problem
end
self . entries [ handle . slot ] = nil
self . generations [ handle . slot ] = entry . generation + 1
entry . cleanup ( entry . value )

return nil
end

function dynamic.StoreState:_entry(handle)
if self . destroyed or handle . store ~= self then
return nil , setmetatable({ code =
"NUPP2614" ,  message =
"dynamic handle names a destroyed or different store" }, dynamic.Error)

end
local entry = self . entries [ handle . slot ]
if not entry or entry . generation ~= handle . generation then
return nil , setmetatable({ code =  "NUPP2614" ,  message =  "dynamic handle is stale" }, dynamic.Error)
end
if entry . policy ~= handle . policy then
return nil , setmetatable({ code =  "NUPP2613" ,  message =  "dynamic handle has the wrong type policy" }, dynamic.Error)
end

return entry , nil
end


function dynamic . StoreState . drop ( self )
if self . destroyed then
return
end
self . destroyed = true
stores [ self ] = nil
local first = nil
local suppressed = 0
for slot , entry in pairs ( self . entries ) do
self . entries [ slot ] = nil
self . generations [ slot ] = entry . generation + 1
local ok , reason = pcall ( entry . cleanup , entry . value )
if not ok then
if first == nil then
first = reason
else
suppressed = suppressed + 1
end
end
end
local _raw = self
if first ~= nil then
if suppressed > 0 then
error ( tostring ( first ) .. " (suppressed " .. tostring ( suppressed ) .. " cleanup failure(s))" , 0 )
end
error ( first , 0 )
end
end

local function destroyStore ( self )
self : drop ( )
end ;__nuppCleanups["nupp.dynamic#destroyStore"]=destroyStore

__nuppCleanups["nupp.dynamic#destroyStore"]=destroyStore;

function dynamic . newStore ( )
local store = setmetatable({ entries =  { } ,  generations =  { } ,  nextSlot =  1 ,  destroyed =  false }, dynamic.StoreState)
stores [ store ] = true

return store
end

function dynamic . erase ( handle )
return setmetatable({ store =
handle . store ,  slot =
handle . slot ,  generation =
handle . generation ,  policy =
handle . policy }, dynamic.ErasedHandle)

end




function dynamic . _recover ( handle , policy )
if handle . policy ~= policy then
return nil , setmetatable({ code =  "NUPP2613" ,  message =  "dynamic handle has the wrong type policy" }, dynamic.Error)
end
return ( setmetatable({ store =

handle . store ,  slot =
handle . slot ,  generation =
handle . generation ,  policy =
handle . policy }, dynamic.Handle)

) , nil
end






function dynamic . recover ( handle , expected )
error ( "dynamic.recover must be lowered by the compiler" , 2 )
end



_G . __nuppDynamicPolicyCount = function ( policy )
local count = 0
for store in pairs ( stores ) do
if not store . destroyed then
for _ , entry in pairs ( store . entries ) do
if entry . policy == policy then
count = count + 1
end
end
end
end

return count
end

return dynamic
