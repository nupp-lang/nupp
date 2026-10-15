_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["example.registry"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local project;__nuppExports["project"]=function(...) return project(...) end;local registry;__nuppExports["registry"]=function(...) return registry(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("example.registry\0runtime\0003") };

local __serdeJson = require ( "nupp.serde.json" )

local core = require ( "nupp.serde" )
local documents = require ( "nupp.serde.document" )
local bridge = require ( "nupp.serde.document" )








local Selected = {} Selected.__index = Selected



function Selected:identity() 
return self . id
end

function Selected:accept(consumer) 
return consumer : apply ( self . id , self . binding , self . value )
end




local Bound = {} Bound.__index = Bound


function Bound:read(value) 
return ( _G.setmetatable({ id =  self . id ,  binding =  self . binding ,  value =  bridge . into ( self . binding , value ) }, Selected) )
end




local Registry = {} Registry.__index = Registry

function Registry:register(identity, binding) 
assert ( identity ~= "" and self . entries [ identity ] == nil , "duplicate or empty type identity" )
self . entries [ identity ] = _G.setmetatable({ id =  identity ,  binding =  binding }, Bound)
end

function Registry:contains(identity) 
return self . entries [ identity ] ~= nil
end

function Registry:reconstruct(identity, value) 
return assert ( self . entries [ identity ] , "unknown type discriminator: " .. identity ) : read ( value )
end ;_G.nupp.__reflect.link(Registry,__nuppT1[1],{ _G.nupp.__reflect.reference("../src/example/registry.nupp\000826\0interface","example.registry") }) ;__nuppExports["Registry"]=Registry


local Project = {} Project.__index = Project
function Project:apply(identity, binding, value) 





return bridge . from ( binding , value )
end

project=function ( value ) 
return value : accept ( _G.setmetatable({ }, Project) )
end ;__nuppExports["project"]=project

registry=function ( ) 
return ( _G.setmetatable({ entries =  {} }, Registry) )
end ;__nuppExports["registry"]=registry
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Registry]="example.registry\0Registry"; end);if not __nuppOk then package.loaded["example.registry"]=nil;error(__nuppWhy,0) end;package.loaded["example.registry"]=__nuppExports;return __nuppExports