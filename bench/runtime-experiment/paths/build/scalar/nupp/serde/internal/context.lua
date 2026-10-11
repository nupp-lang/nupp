_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.serde.internal.context"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local builder;__nuppExports["builder"]=function(...) return builder(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.context\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.serde.internal.context\0runtime\0003") };

local core = require ( "nupp.serde.internal.value" )
local store = require ( "nupp.util.internal.store" )

local Entry = {} Entry.__index = Entry ;_G.nupp.__reflect.link(Entry,__nuppT1[1],{ })



local Context = {} Context.__index = Context




function Context:get(key) 
local value = self . values [ key ]
if value ~= nil then
return value . value
end
if self . parent ~= nil then
return self . parent : get ( key )
end

return nil
end


local Builder = {} Builder.__index = Builder











function Builder:set(key, value) 
if self . frozen then
error ( "context builder is frozen" , 2 )
end
self . values [ key ] = _G.setmetatable({ value =  value }, Entry)
end









function Builder:freeze() 
if self . frozen then
error ( "context builder is frozen" , 2 )
end
self . frozen = true

return ( _G.setmetatable({ codec =  self . codec ,  profile =  self . profile ,  parent =  self . parent ,  values =  self . values }, Context) )
end ;_G.nupp.__reflect.link(Builder,__nuppT1[2],{ _G.nupp.__reflect.reference("../../../src/nupp/serde/internal/value.nupp\0Context\0interface\0module\0001","nupp.serde.internal.value") , __nuppT1[1] }) ;__nuppExports["Builder"]=Builder


builder=function ( codec , profile , parent ) 
return ( _G.setmetatable({ codec =  codec ,  profile =  profile ,  parent =  parent ,  values =  { } ,  frozen =  false }, Builder) )
end ;__nuppExports["builder"]=builder
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Builder]="nupp.serde.internal.context\0Builder"; end);if not __nuppOk then package.loaded["nupp.serde.internal.context"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.context"]=__nuppExports;return __nuppExports