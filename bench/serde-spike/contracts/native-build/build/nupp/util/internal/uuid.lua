_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.util.internal.uuid"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local uuid4;__nuppExports["uuid4"]=function(...) return uuid4(...) end;local uuid7;__nuppExports["uuid7"]=function(...) return uuid7(...) end;







local provider = require ( "nupp.runtime.uuidprovider" )

local function canonical ( value , version ) 
if type ( value ) ~= "string" or # value ~= 36 then
error ( "nupp: UUID provider returned an invalid version " .. version .. " UUID" , 0 )
end
local compact = value : gsub ( "-" , "" )
if value : sub ( 9 , 9 ) ~= "-"
or value : sub ( 14 , 14 ) ~= "-"
or value : sub ( 19 , 19 ) ~= "-"
or value : sub ( 24 , 24 ) ~= "-"
or # compact ~= 32
or compact : find ( "[^0-9a-f]" ) ~= nil
or value : sub ( 15 , 15 ) ~= version
or value : sub ( 20 , 20 ) : find ( "[89ab]" ) == nil then
error ( "nupp: UUID provider returned an invalid version " .. version .. " UUID" , 0 )
end

return value
end




uuid4=function ( ) 
return canonical ( provider . uuid4 ( ) , "4" )
end ;__nuppExports["uuid4"]=uuid4




uuid7=function ( ) 
return canonical ( provider . uuid7 ( ) , "7" )
end ;__nuppExports["uuid7"]=uuid7
 end);if not __nuppOk then package.loaded["nupp.util.internal.uuid"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.util.internal.uuid"]=__nuppExports;return __nuppExports