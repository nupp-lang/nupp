_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()


local host = { }
function host . get ( ) 
local ok , ffi = pcall ( require , "ffi" )
if not ok then
return nil
end
local declared
local read
local pid
if package . config : sub ( 1 , 1 ) == "\\" then
declared = pcall ( ffi . cdef , "int _getpid(void);" )
read , pid = pcall ( function ( ) 
return ffi . C . _getpid ( )
end )
else
declared = pcall ( ffi . cdef , "int getpid(void);" )
read , pid = pcall ( function ( ) 
return ffi . C . getpid ( )
end )
end
if declared and read then
return tonumber ( pid )
end

return nil
end

local __nuppExportValue= host ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.hostpid"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.hostpid"]=__nuppExports;return __nuppExports