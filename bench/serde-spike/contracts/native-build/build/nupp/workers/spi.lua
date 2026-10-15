_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.workers.spi"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.workers.spi\0runtime\0001") };























































































































































Submitted=function ( F ) 
if nupp . types . kind ( F ) ~= "function" then
return nupp . types . error ( "a worker job must name a function type" )
end
local packs = { { of = nupp . types . parameters ( F ) , what = "argument" } , { of = nupp . types . results ( F ) , what = "result" } , }
for _ , one in ipairs ( packs ) do
local described = nupp . types . describe ( one . of )



local headTypes = described . head or { }
for position , mode in ipairs ( described . modes or { } ) do



local moved = mode == "takes" and one . what == "argument" and movableOwner ( headTypes [ position ] )
if mode ~= "plain" and not moved then
return nupp . types . error (
one . what .. " " .. tostring (
position
) .. " is an owner or a borrow, which cannot cross into another Lua state"
)
end
end
for position , member in ipairs ( described . head or { } ) do
local why = unsendable ( member , one . what .. " " .. tostring ( position ) )
if why ~= nil then
return nupp . types . error ( why .. ", which cannot cross into another Lua state" )
end
end
if described . tail ~= nil then
local why = unsendable ( described . tail , "every extra " .. one . what )
if why ~= nil then
return nupp . types . error ( why .. ", which cannot cross into another Lua state" )
end
end
end

return nupp . types . parameters ( F )
end







































































local Scope = {} Scope.__index = Scope ;_G.nupp.__reflect.link(Scope,__nuppT1[1],{ }) ;__nuppExports["Scope"]=Scope
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Scope]="nupp.workers.spi\0Scope"; end);if not __nuppOk then package.loaded["nupp.workers.spi"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.workers.spi"]=__nuppExports;return __nuppExports