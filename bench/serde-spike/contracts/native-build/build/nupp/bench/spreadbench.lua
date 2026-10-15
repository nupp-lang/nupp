_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local bench = { }

local function two ( ) 
return 1 , 2
end

local function one ( ) 
return 7
end

local function pack ( ... ) 
local t = { ... }
return # t
end

local function sum3 ( a , b , c ) 
return ( a or 0 ) * 100 + ( b or 0 ) * 10 + ( c or 0 )
end

local function fails ( _ , _ ) 
error ( "boom" )
end

function bench . run ( ) 
local a = sum3 ( 5 , two ( ) )
local b = sum3 ( 5 , 7 )
local c = pack ( 9 , two ( ) )
local d = pack ( 7 )
local ok , v = pcall ( sum3 , 5 , two ( ) )
local ok2 = pcall ( fails , two ( ) )

return a , b , c , d , ( ok and v or -1 ) , ok2
end

local __nuppExportValue= bench ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.bench.spreadbench"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.bench.spreadbench"]=__nuppExports;return __nuppExports