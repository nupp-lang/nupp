_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

local _fused = require ( "nupp.codec.json.internal.decoder.fused" )

local fused = __nuppNew(0,7)

fused . OK = 0
fused . SYNTAX = 1
fused . INVALID_UTF8 = 2
fused . INVALID_CONTROL = 3
fused . INVALID_BACKSLASH = 4
fused . TAPE = 5







fused . decode = _fused . decodePull









local __nuppExportValue= fused ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.codec.json.internal.decode"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.codec.json.internal.decode"]=__nuppExports;return __nuppExports