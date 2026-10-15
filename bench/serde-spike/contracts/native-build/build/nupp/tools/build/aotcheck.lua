_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()
































local envMod = require ( "nupp.compiler.project.env" )
local fingerprint = require ( "nupp.compiler.project.fingerprint" )
local fs = require ( "nupp.compiler.fs" )

local aotcheck = { }










const _DYNAMIC_REQUIRES = "@requires-dynamically nothing"





local loadBackend = require





function aotcheck . backendKey ( cacheDir , digest ) 
return fingerprint . subsystemFingerprint ( { "nupp.compiler.aot.compile" } , cacheDir , digest )
end

















function aotcheck . applies ( policy ) 
return policy == "require" or policy == "emit-wasm" or policy == "require-wasm"
end




function aotcheck . mentionsGpuTarget ( text ) 
return text : find ( "@aot" , 1 , true ) ~= nil and text : match ( "target%s*=%s*[\"']gpu[\"']" ) ~= nil
end










function aotcheck . projectSource ( root , include , outDir , path ) 



local file = fs . canonical ( path )
local built = fs . canonical ( fs . join ( root , outDir ) ) .. "/"
if file : sub ( 1 , # built ) == built then
return false
end
local roots = { }
for _ , directory in ipairs ( include or { } ) do
roots [ # roots + 1 ] = fs . canonical ( fs . join ( root , directory ) )
end
if # roots == 0 then
roots [ 1 ] = fs . canonical ( root )
end

return envMod . moduleNameInRoots ( roots , file ) ~= nil
end





function aotcheck . selection ( policy , triple , features ) 
if policy == "emit-wasm" or policy == "require-wasm" then
return "wasm32-unknown-emscripten" , features or "scalar"
end

return triple , features
end

local function offsetOf ( source , line , column ) 
local offset = 1
for _ = 2 , line do
offset = ( source : find ( "\n" , offset , true ) or # source ) + 1
end

return offset + column - 1
end


local function widthAt ( source , offset ) 
local word = source : match ( "^[%a_][%w_]*" , offset ) or source : match ( "^%d[%w%.]*" , offset )

return word ~= nil and # ( word ) or 1
end





















function aotcheck . refusals (
source ,
filename ,
checked ,
target ,
constPlans
) 
local policy = target . aot
if not aotcheck . applies ( policy ) or source : find ( "@aot" , 1 , true ) == nil then
return { }
end
local triple , features = aotcheck . selection ( policy , target . aotTarget , target . aotFeatures )


local compile = loadBackend ( "nupp.compiler.aot.compile" )
local tiers = loadBackend ( "nupp.compiler.aot.target" ) . buildTiers ( triple , features )
if tiers == nil then
return { }
end
for _ , tier in ipairs ( tiers ) do
local artifacts , problems = compile . artifacts (
source ,
filename ,
checked ,
"<object>" ,
tier ,
tier . tier ,
constPlans
)
if artifacts == nil then
local first = problems [ 1 ]
if first == nil or first . code == compile . NO_AOT_FUNCTION then
return { }
end
local help = ("target %s compiles `@aot` functions for the %s tier (aot = %q); rewrite this, or remove `@aot` to run the function as ordinary Nupp")


: format ( target . name or "default" , tier . tier , policy )
local out = { }
for _ , problem in ipairs ( problems ) do
local offset = offsetOf ( source , problem . line , problem . column )
out [
# out + 1
] = {
filename = filename ,
line = problem . line ,
col = problem . column ,
offset = offset ,
length = widthAt ( source , offset ) ,
severity = "error" ,
code = problem . code ,
msg = problem . message ,
help = help ,
}
end

return out
end


local cpu = false
for _ , program in ipairs ( ( artifacts ) . programs ) do
cpu = cpu or program . executionTarget ~= "gpu"
end
if not cpu then
return { }
end
end

return { }
end

local __nuppExportValue= aotcheck ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.aotcheck"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.aotcheck"]=__nuppExports;return __nuppExports