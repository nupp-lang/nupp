_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.tools.build.clockhost"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local now;__nuppExports["now"]=function(...) return now(...) end;





local function makeClock ( ) 
local coarse = function ( ) 
return os . clock ( ) * 1000
end
local loaded , ffi = pcall ( require , "ffi" )
if not loaded then
return coarse
end

pcall ( ffi . cdef , "int gettimeofday(void *, void *);" )
local holder = ffi . new ( "int64_t[2]" )
local buffer = ffi . cast ( "void *" , holder )

local function read ( ) 
do
ffi . C . gettimeofday ( buffer , nil )
end

return ( tonumber ( holder [ 0 ] ) or 0 ) * 1000 + ( tonumber ( holder [ 1 ] ) or 0 ) / 1000
end


local sampled , sample = pcall ( read )
if not sampled or type ( sample ) ~= "number" or sample < 1400000000000 or sample > 4000000000000 then
return coarse
end

return read
end

local clock = makeClock ( )

now=function ( ) 
return clock ( )
end ;__nuppExports["now"]=now
 end);if not __nuppOk then package.loaded["nupp.tools.build.clockhost"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.clockhost"]=__nuppExports;return __nuppExports