_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.serde.internal.json.extensions"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local scope;__nuppExports["scope"]=function(...) return scope(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.json.extensions\0runtime\0001") };

local core = require ( "nupp.serde.internal.value" )
local plans = require ( "nupp.serde.internal.json.plan" )
local errors = require ( "nupp.serde.internal.errors" )
local encoding = require ( "nupp.serde.internal.json.encoder" )
local lowering = require ( "nupp.serde.internal.json.lower" )
local compiled = require ( "nupp.serde.internal.json.compiled" )
local memos = require ( "nupp.serde.internal.memo" )

local Operation = {} Operation.__index = Operation ;_G.nupp.__reflect.link(Operation,__nuppT1[1],{ _G.nupp.__reflect.reference("../../../src/nupp/serde/internal/json/plan.nupp\0Policy\0interface\0module\0001","nupp.serde.internal.json.plan") , _G.nupp.__reflect.reference("nupp.serde.internal.json.plan\0runtime\0001","nupp.serde.internal.json.plan") , _G.nupp.__reflect.reference("../../../src/nupp/serde/internal/json/compiled.nupp\0Decoder\0interface\0module\0001","nupp.serde.internal.json.compiled") , _G.nupp.__reflect.reference("../../../src/nupp/serde/internal/json/lower.nupp\0Encoding\0interface\0module\0001","nupp.serde.internal.json.lower") }) ;__nuppExports["Operation"]=Operation

















local function initialize (
adapter ,
factory ,
direction
) 
local description = adapter : describe ( direction )
local policy = factory : policy ( description . member )
local plan = plans . resolve ( description , policy , direction )
return ( _G.setmetatable({ policy =
policy ,  plan =
plan ,  native =
direction == "read" and compiled . select ( adapter , plan ) or nil ,  encoding =
direction == "write" and encoding . select ( adapter , plan ) or nil }, Operation) )

end

local Cache = {} Cache.__index = Cache



function Cache:profile() 
return self . factory
end

function Cache:size() 
return self . memo : size ( )
end

function Cache:clear() 
self . memo : clear ( )
end

function Cache:resolve(adapter, direction) 
local found , cached = self . memo : find ( adapter , direction )
if found then



return cached
end
local slot = self . memo : start ( adapter , direction )
local ok , result = pcall ( initialize , adapter , self . factory , direction )
if not ok then
result = errors . wrap ( result , "$" , nil )
end

return self . memo : finish ( slot , ok , result )
end


scope=function ( factory , capacity ) 
return ( _G.setmetatable({ factory =  factory ,  memo =  memos . new ( "JSON extension" , capacity ) }, Cache) )
end ;__nuppExports["scope"]=scope
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Operation]="nupp.serde.internal.json.extensions\0Operation"; end);if not __nuppOk then package.loaded["nupp.serde.internal.json.extensions"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.json.extensions"]=__nuppExports;return __nuppExports