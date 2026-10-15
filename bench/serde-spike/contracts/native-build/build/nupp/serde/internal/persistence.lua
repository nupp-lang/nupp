_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.serde.internal.persistence"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local binding;__nuppExports["binding"]=function(...) return binding(...) end;local registry;__nuppExports["registry"]=function(...) return registry(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.persistence\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.serde.internal.persistence\0runtime\0002") };

local core = require ( "nupp.serde.internal.value" )
local util = require ( "nupp.util.internal.store" )
local documents = require ( "nupp.serde.internal.document" )
local bridge = require ( "nupp.serde.internal.documentcodec" )












local Entry = {} Entry.__index = Entry ;_G.nupp.__reflect.link(Entry,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0005","nupp.serde.internal.document") }) ;__nuppExports["Entry"]=Entry









local Snapshot = {} Snapshot.__index = Snapshot ;_G.nupp.__reflect.link(Snapshot,__nuppT1[2],{ __nuppT1[1] }) ;__nuppExports["Snapshot"]=Snapshot











local Selected = {} Selected.__index = Selected





function Selected:save(store) 
local value = store : get ( self . key )
if value == nil then
return nil
end

return ( _G.setmetatable({ name =  self . name ,  version =  self . version ,  value =  bridge . fromBinding ( self . binding , value ) }, Entry) )
end

function Selected:restore(store, entry) 
local value = entry . value
assert ( entry . version >= 1 and entry . version % 1 == 0 , "invalid persisted key version" )
if entry . version ~= self . version then
assert (
entry . version < self . version and self . migration ~= nil ,
"unsupported persisted key version: " .. self . name
)
value = ( self . migration ) : apply ( entry . version , value )
end
local restored = bridge . into ( self . binding , value )
assert ( restored ~= nil , "persisted key value cannot be nil" )
store : set ( self . key , restored )
end


















































local Owned = {} Owned.__index = Owned



function Owned:register(name, key, binding, version, migration) 







assert ( name ~= "" and self . names [ name ] == nil , "duplicate or empty persistent name" )
assert ( not self . keys [ key . id ] , "store key already has a persistence binding" )
assert ( version >= 1 and version % 1 == 0 , "invalid persistence version" )
local entry = _G.setmetatable({ name =
name ,  key =
key ,  binding =
binding ,  version =
version ,  migration =
migration }, Selected)

self . names [ name ] = entry
self . keys [ key . id ] = true
self . ordered [ # self . ordered + 1 ] = entry
end

function Owned:save(store) 
local entries = { }
for _ , selected in ipairs ( self . ordered ) do
local entry = selected : save ( store )
if entry ~= nil then
entries [ # entries + 1 ] = entry
end
end

return ( _G.setmetatable({ entries =  entries ,  format =  1 }, Snapshot) )
end

function Owned:load(snapshot, unknown) 
assert ( snapshot . format == 1 , "unsupported persistence snapshot version" )
local result = util . newStore ( )
local seen = { }
for _ , entry in ipairs ( snapshot . entries ) do
assert ( not seen [ entry . name ] , "duplicate persisted key: " .. entry . name )
seen [ entry . name ] = true
local selected = self . names [ entry . name ]
if selected ~= nil then
selected : restore ( result , entry )
else
assert ( unknown == "skip" , "unknown persisted key: " .. entry . name )
end
end

return result
end

registry=function ( ) 
return ( _G.setmetatable({ names =  {} ,  keys =  {} ,  ordered =  {} }, Owned) )
end ;__nuppExports["registry"]=registry

local scalar = require ( "nupp.serde.internal.scalar" )
local Mapping = {} Mapping.__index = Mapping
function Mapping:project(value) 
local entries = { }
for _ , entry in ipairs ( value . entries ) do
entries [ # entries + 1 ] = documents . object ( {
_G.setmetatable({ name =  "name" ,  value =  documents . string ( entry . name ) }, documents.Entry) ,
_G.setmetatable({ name =  "version" ,  value =  documents . numberToken ( tostring ( entry . version ) ) }, documents.Entry) ,
_G.setmetatable({ name =  "value" ,  value =  documents . document ( entry . value ) }, documents.Entry)
} )
end

return documents . object ( {
_G.setmetatable({ name =  "format" ,  value =  documents . numberToken ( tostring ( value . format ) ) }, documents.Entry) ,
_G.setmetatable({ name =  "entries" ,  value =  documents . list ( entries ) }, documents.Entry)
} )
end

function Mapping:restore(value) 
assert ( value . kind == "structure" and value : size ( ) == 2 , "invalid persistence snapshot" )
assert ( assert ( value : get ( "format" ) ) : numberToken ( ) == "1" , "unsupported persistence snapshot version" )
local entries = assert ( value : get ( "entries" ) )
assert ( entries . kind == "list" , "invalid persisted entries" )
local result = { }
for index = 1 , entries : size ( ) do
local entry = entries : at ( index )
assert ( entry . kind == "structure" and entry : size ( ) == 3 , "invalid persisted entry" )
local version = tonumber ( assert ( entry : get ( "version" ) ) : numberToken ( ) )
assert (
version ~= nil and version >= 1 and version <= 9007199254740991 and version % 1 == 0 ,
"invalid persisted key version"
)
local contents = assert ( entry : get ( "value" ) )


if contents . kind == "document" then
contents = contents : document ( )
end
result [
# result + 1
] = _G.setmetatable({ name =  assert ( entry : get ( "name" ) ) : string ( ) ,  version =  version ,  value =  contents }, Entry)
end

return ( _G.setmetatable({ entries =  result ,  format =  1 }, Snapshot) )
end


local member = _G.setmetatable({ name =  "$store" }, documents.Member)
local selected = _G.setmetatable({ adapter =
scalar . convert ( scalar . document ( member , documents . documentAdapter ( ) ) , _G.setmetatable({ }, Mapping) ) }, core.Bound)

binding=function ( ) 
return selected
end ;__nuppExports["binding"]=binding
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Entry]="nupp.serde.internal.persistence\0Entry";__nuppWorkerRecords[Snapshot]="nupp.serde.internal.persistence\0Snapshot"; end);if not __nuppOk then package.loaded["nupp.serde.internal.persistence"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.persistence"]=__nuppExports;return __nuppExports