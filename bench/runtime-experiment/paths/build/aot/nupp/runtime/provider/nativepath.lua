_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

















const native = require ( "nupp.runtime.native" )

_G.pcall(__nuppFfi.cdef, "struct NuppNativeFilesystemSlice { const char * data; uint64_t length; };") const NuppNativeFilesystemSlice = __nuppFfi.typeof("struct NuppNativeFilesystemSlice")




native . ffi . cdef [[
int32_t nuppNativeFilesCurrentDirectory(uint64_t *);
int32_t nuppNativeFilesCanonicalize(
    struct NuppNativeFilesystemSlice, uint64_t *);
]]

local provider = { }
local ffi = native . ffi
local C = native . C

native . requireFeature ( 64 , "filesystem" )

local function slice ( text ) 
local value = __nuppFfi.new(NuppNativeFilesystemSlice )



do
value . data = text
end
value . length = # text

return value
end

local function answered ( status , output ) 
if status ~= 0 then
return nil , ffi . string ( C . nuppNativeLastError ( ) )
end

return native . bytes ( output [ 0 ] ) , nil
end

function provider . separator ( ) 
return package . config : sub ( 1 , 1 )
end

function provider . currentDirectory ( ) 
local output = ffi . new ( "uint64_t[1]" )

return answered ( C . nuppNativeFilesCurrentDirectory ( output ) , output )
end

function provider . canonicalize ( path ) 
local output = ffi . new ( "uint64_t[1]" )

return answered ( C . nuppNativeFilesCanonicalize ( slice ( path ) , output ) , output )
end

local __nuppExportValue= provider ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.nativepath"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.nativepath"]=__nuppExports;return __nuppExports