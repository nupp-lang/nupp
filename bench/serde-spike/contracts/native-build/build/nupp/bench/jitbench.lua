_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local bench = { }

local nesting = 0
local MAX = 5

local function rec ( n ) 
nesting = nesting + 1
if nesting > 5 then
error ( "deep" , 0 )
end
local r = 0
if n > 0 then
r = rec ( n - 1 ) + 1
end
nesting = nesting - 1

return r
end

function bench . run ( ) 
local ok , r = pcall ( rec , 3 )
local ok2 , r2 = pcall ( rec , 10 )
return ( ok and r or -1 ) , ( ok2 and r2 or -1 ) , nesting
end

local __nuppExportValue= bench ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.bench.jitbench"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.bench.jitbench"]=__nuppExports;return __nuppExports