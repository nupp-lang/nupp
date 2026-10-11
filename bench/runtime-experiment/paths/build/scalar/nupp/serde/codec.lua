_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.serde.codec"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()




















local numbers = require ( "nupp.serde.internal.numbers" )
local timestamps = require ( "nupp.serde.internal.timestamps" )
local errors = require ( "nupp.serde.internal.errors" )
local publication = require ( "nupp.serde.internal.publication" )
local contexts = require ( "nupp.serde.internal.context" )








const integer = numbers . integer ;__nuppExports["integer"]=integer








const float = numbers . floating ;__nuppExports["float"]=float






const parseDateTime = timestamps . parseDateTime ;__nuppExports["parseDateTime"]=parseDateTime





const formatDateTime = timestamps . dateTime ;__nuppExports["formatDateTime"]=formatDateTime






const parseEpoch = timestamps . parseEpoch ;__nuppExports["parseEpoch"]=parseEpoch





const formatEpoch = timestamps . epoch ;__nuppExports["formatEpoch"]=formatEpoch










const wrapError = errors . wrap ;__nuppExports["wrapError"]=wrapError






const prefixError = errors . prefix ;__nuppExports["prefixError"]=prefixError











const discardFailed = publication . failure ;__nuppExports["discardFailed"]=discardFailed




const ContextBuilder = contexts . Builder ;__nuppExports["ContextBuilder"]=ContextBuilder



















const contextBuilder = contexts . builder ;__nuppExports["contextBuilder"]=contextBuilder
 end);if not __nuppOk then package.loaded["nupp.serde.codec"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.codec"]=__nuppExports;return __nuppExports