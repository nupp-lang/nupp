_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);












if package . config : sub ( 1 , 1 ) == "\\" then
_G.pcall(__nuppFfi.cdef, "int32_t _setmode(int32_t, int32_t);") const _setmode = __nuppFfi.C._setmode

_setmode ( 0 , 32768 )
_setmode ( 1 , 32768 )
_setmode ( 2 , 32768 )
end



require ( "nupp.tools.jitlimits" ) . apply ( )





require ( "nupp.tools.bytecodecache" ) . install ( )

local code = require ( "nupp.tools.cli" ) . main ( arg )

local codegen = package . loaded [ "nupp.compiler.aot.llvm.codegen" ]
if codegen ~= nil then
codegen . endIfUnexitable ( code )
end
os . exit ( code )
