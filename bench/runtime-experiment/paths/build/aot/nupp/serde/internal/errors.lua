_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.serde.internal.errors"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local prefix;__nuppExports["prefix"]=function(...) return prefix(...) end;local wrap;__nuppExports["wrap"]=function(...) return wrap(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.errors\0runtime\0001") };









local Error = {} Error.__index = Error ;_G.nupp.__reflect.link(Error,__nuppT1[1],{ }) ;__nuppExports["Error"]=Error
























Error . __tostring = function ( self ) 
local position = self . byte ~= nil and " at byte " .. tostring ( self . byte ) or ""
return self . code .. " " .. self . path .. position .. ": " .. self . message
end











wrap=function ( problem , path , byte ) 
if getmetatable ( problem ) == Error then
return problem
end
local ok , message = pcall ( tostring , problem )

return ( _G.setmetatable({ code =
"model" ,  message =
ok and type ( message ) == "string" and message or "model operation failed" ,  path =
path ,  byte =
byte ,  cause =
problem ,  suppressed =
not ok and { message } or { } }, Error) )

end ;__nuppExports["wrap"]=wrap










prefix=function ( problem , parent ) 
local inner = wrap ( problem , "$" , nil )
if parent == "$" then
return inner
end

return ( _G.setmetatable({ code =
inner . code ,  message =
inner . message ,  path =
parent .. inner . path : sub ( 2 ) ,  byte =
inner . byte ,  cause =
inner . cause ,  suppressed =
inner . suppressed }, Error) )

end ;__nuppExports["prefix"]=prefix
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Error]="nupp.serde.internal.errors\0Error"; end);if not __nuppOk then package.loaded["nupp.serde.internal.errors"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.errors"]=__nuppExports;return __nuppExports