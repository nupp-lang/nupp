_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()









local platform = { }

local ORDERED = { "x86_64-unknown-linux-gnu" , "aarch64-apple-darwin" , "x86_64-pc-windows-msvc" , }

local RECORDS = {
[ "x86_64-unknown-linux-gnu" ] = { executableSuffix = "" , posix = true } ,
[ "aarch64-apple-darwin" ] = { executableSuffix = "" , posix = true } ,
[ "x86_64-pc-windows-msvc" ] = { executableSuffix = ".exe" , posix = false } ,
}

function platform . keys ( ) 
local keys = { }
for index , key in ipairs ( ORDERED ) do
keys [ index ] = key
end

return keys
end

function platform . has ( key ) 
return key ~= nil and RECORDS [ key ] ~= nil
end

function platform . executableSuffix ( key ) 
return assert ( RECORDS [ key ] , "unsupported binary platform" ) . executableSuffix
end

function platform . isPosix ( key ) 
return assert ( RECORDS [ key ] , "unsupported binary platform" ) . posix
end

function platform . hostKey ( ) 
local key = require ( "nupp.compiler.targetlayout" ) . hostKey ( )
return platform . has ( key ) and key or nil
end

local __nuppExportValue= platform ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.platform"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.platform"]=__nuppExports;return __nuppExports