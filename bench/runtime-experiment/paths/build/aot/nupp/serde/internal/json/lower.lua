_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.serde.internal.json.lower"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()
local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.json.lower\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.serde.internal.json.lower\0runtime\0002") };

local core = require ( "nupp.serde.internal.value" )
local plans = require ( "nupp.serde.internal.json.plan" )



local Recipe = {} Recipe.__index = Recipe ;_G.nupp.__reflect.link(Recipe,__nuppT1[1],{ }) ;__nuppExports["Recipe"]=Recipe








local json = require ( "nupp.codec.json" )
local errors = require ( "nupp.serde.internal.errors" )
local Budget = {} Budget.__index = Budget

function Budget:step(path) 
self . values += 1
if self . values > 1000000 then
error ( _G.setmetatable({ code =  "limit" ,  message =  "value limit exceeded" ,  path =  path ,  cause =  nil ,  suppressed =  {} }, errors.Error) , 0 )
end
end ;_G.nupp.__reflect.link(Budget,__nuppT1[2],{ }) ;__nuppExports["Budget"]=Budget
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Budget]="nupp.serde.internal.json.lower\0Budget";__nuppWorkerRecords[Recipe]="nupp.serde.internal.json.lower\0Recipe"; end);if not __nuppOk then package.loaded["nupp.serde.internal.json.lower"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.json.lower"]=__nuppExports;return __nuppExports