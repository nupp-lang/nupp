_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()




local guest = rawget ( _G , "__nuppBrowser" )
local memory = assert ( guest and guest . memory , "nupp: browser guest memory transport is unavailable" )




if rawget ( memory , "leaseBytes" ) == nil then
local extents = { }
local lease = memory . lease
local releaseLease = memory . releaseLease
memory . lease = function ( pointer , count , writable ) 
local id = lease ( pointer , count , writable )
extents [ id ] = count
return id
end
memory . releaseLease = function ( id ) 
extents [ id ] = nil
releaseLease ( id )
end
memory . leaseBytes = function ( id ) 
return extents [ id ] or 0
end
end

local __nuppExportValue= memory ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.browser.memory"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.browser.memory"]=__nuppExports;return __nuppExports