_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.serde.internal.json.plan"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local resolve;__nuppExports["resolve"]=function(...) return resolve(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.json.plan\0runtime\0001") };

local core = require ( "nupp.serde.internal.value" )
local json = require ( "nupp.codec.json" )
local errors = require ( "nupp.serde.internal.errors" )
































































local Plan = {} Plan.__index = Plan







function Plan:member(name) 
return self . names [ name ]
end

function Plan:key(member) 
return self . keys [ member ]
end

function Plan:wireName(member) 
return self . wireNames [ member ]
end

function Plan:omitsName(name) 
return self . omittedNames [ name ] == true
end

function Plan:action(member) 
return self . actions [ member ]
end

function Plan:child(member) 
return self . children [ member ]
end

function Plan:slot(index) 
local child = self . description . children [ index ]
local plan = child ~= nil and self . children [ child . member ] or nil
if plan ~= nil then
return plan
end
if self . description . kind == "dynamic" then
return nil
else
error ( "missing container slot " .. tostring ( index ) , 2 )
end
end ;_G.nupp.__reflect.link(Plan,__nuppT1[1],{ _G.nupp.__reflect.reference("../../../src/nupp/serde/internal/value.nupp\0Description\0interface\0module\0001","nupp.serde.internal.value") , _G.nupp.__reflect.reference("nupp.codec.json.spi\0runtime\0002","nupp.codec.json.spi") , __nuppT1[1] }) ;__nuppExports["Plan"]=Plan


local function build (
description ,
policy ,
direction ,
seen ,
path
) 
local prior = seen [ description ]
if prior ~= nil then
return prior
end
if direction == "read" and not description . canRead then
error (
_G.setmetatable({ code =
"unsupported" ,  message =
"binding has no construction operation" ,  path =
path ,  cause =
nil ,  suppressed =  {} }, errors.Error)
,
0
)
end
if description . kind == "opaque" or description . kind == "atom" then
error (
_G.setmetatable({ code =
"unsupported" ,  message =
"JSON does not support " .. description . kind ,  path =
path ,  cause =
nil ,  suppressed =  {} }, errors.Error)
,
0
)
end
local result = _G.setmetatable({ description =
description ,  names =
{ } ,  keys =
{ } ,  wireNames =
{ } ,  omittedNames =
{ } ,  actions =
{ } ,  children =
{ } }, Plan)

seen [ description ] = result
for _ , child in ipairs ( description . children ) do
local member = child . member
local childPath = path .. "[" .. json . encode ( member . name ) .. "]"
local action = policy : select ( member , direction )
result . actions [ member ] = action
if action ~= "traverse" and direction == "read" and child . required and not child . hasDefault then
error (
_G.setmetatable({ code =
"unsupported" ,  message =
"omitted member has no default" ,  path =
childPath ,  cause =
nil ,  suppressed =  {} }, errors.Error)
,
0
)
end
if description . kind == "structure" or description . kind == "union" then
local name = policy : name ( member )
if action == "omit" then
result . omittedNames [ name ] = true
else
if result . names [ name ] ~= nil then
error (
_G.setmetatable({ code =
"contract" ,  message =
"colliding JSON member name: " .. name ,  path =
childPath ,  cause =
nil ,  suppressed =  {} }, errors.Error)
,
0
)
end
result . names [ name ] = member
result . keys [ member ] = json . encodedString ( name )
result . wireNames [ member ] = name
end
end
if action == "traverse" then
local ok , described = pcall ( child . describe , child , direction )
if not ok then
error ( errors . wrap ( described , childPath , nil ) , 0 )
end
result . children [ member ] = build ( described , policy , direction , seen , childPath )
end
end

return result
end

resolve=function (
description ,
policy ,
direction
) 
return build ( description , policy , direction , { } , "$" )
end ;__nuppExports["resolve"]=resolve
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Plan]="nupp.serde.internal.json.plan\0Plan"; end);if not __nuppOk then package.loaded["nupp.serde.internal.json.plan"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.json.plan"]=__nuppExports;return __nuppExports