_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.tools.browserluajit"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local new;__nuppExports["new"]=function(...) return new(...) end;

local Browser = require ( "nupp.tools.browser" )
local cheader = require ( "nupp.compiler.cinterop.cheader" )

local function unavailable ( ) 
return nil , "the browser compiler cannot read C headers or invoke a preprocessor; declare C types inline"
end

new=function ( ) 
return Browser . new ( {
layoutTarget = "i686-unknown-linux-gnu" ,
compilerServices = {
cheader = {
declare = cheader . declare ,
typeFromString = cheader . typeFromString ,
declaredFunctions = cheader . declaredFunctions ,
provenance = unavailable ,
load = unavailable ,
}
} ,
} )
end ;__nuppExports["new"]=new
 end);if not __nuppOk then package.loaded["nupp.tools.browserluajit"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.browserluajit"]=__nuppExports;return __nuppExports