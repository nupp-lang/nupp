_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()




local host = { }

function host . isTerminal ( fd ) 
local loaded , ffi = pcall ( require , "ffi" )
if not loaded then
return false
end
pcall ( ffi . cdef , "int isatty(int);" )
local ok , result = pcall ( function ( ) 
local C = ffi . C
return C . isatty ( fd )
end )
if ok then
return result ~= 0
end
pcall ( ffi . cdef , "int _isatty(int);" )
local retried , retriedResult = pcall ( function ( ) 
local C = ffi . C
return C . _isatty ( fd )
end )

return retried and retriedResult ~= 0
end


local WINDOW_SIZE = { OSX = 1074295912 , BSD = 1074295912 , Linux = 21523 }

function host . columns ( fd ) 
local loaded , ffi = pcall ( require , "ffi" )
if not loaded then
return nil
end
local library = ffi
local request = WINDOW_SIZE [ library . os or "" ]
if request == nil then
return nil
end
pcall ( ffi . cdef , "struct nupp_winsize { unsigned short ws_row, ws_col, ws_x, ws_y; };" )
pcall ( ffi . cdef , "int ioctl(int, unsigned long, ...);" )
local ok , answer = pcall ( function ( ) 
local C = library . C
local size = library . new ( "struct nupp_winsize" )
if C . ioctl ( fd , request , size ) ~= 0 then
return nil
end

return tonumber ( size . ws_col )
end )
if not ok or answer == nil or ( answer ) <= 0 then
return nil
end

return math . floor ( answer )
end

local __nuppExportValue= host ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.cli.internal.terminalhost"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.cli.internal.terminalhost"]=__nuppExports;return __nuppExports