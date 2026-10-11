_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






const native = require ( "nupp.runtime.native" )

native . ffi . cdef [[
int32_t nuppNativeXxh64Digest(const uint8_t *, size_t, uint8_t *, size_t);
]]

local ffi = native . ffi
const C = native . C
local ffiString = ffi . string
local hash = { }


function hash . digest ( input ) 
local output = __nuppFfi.new("uint8_t[32]" )
native . succeeded ( C . nuppNativeXxh64Digest ( input , # input , output , 32 ) , 2 )

return ffiString ( __nuppFfi.cast("const uint8_t *" , output ) , 32 )
end

local __nuppExportValue= hash ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.nativehash"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.nativehash"]=__nuppExports;return __nuppExports