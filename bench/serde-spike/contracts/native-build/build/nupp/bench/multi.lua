_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()


local m = { }

function m . pair ( src ) 
local tokens = { }
local errors = { }

local function add ( e ) 
errors [ # errors + 1 ] = e
end

tokens [ 1 ] = src
add ( "x" )

return tokens , errors
end

function m . plain ( src ) 
local a = { src }
local b = { "y" , "z" }
return a , b
end

function m . lex ( src ) 
local t , e = m . pair ( src )
local a , b = m . plain ( src )
return # t + # a , # e + # b , 0
end

local __nuppExportValue= m ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.bench.multi"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.bench.multi"]=__nuppExports;return __nuppExports