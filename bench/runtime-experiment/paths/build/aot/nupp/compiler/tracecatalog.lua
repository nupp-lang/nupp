_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()




local catalog = {
CATALOG_VERSION= 1 ,
CATALOG_ID= "nupp-trace-reasons-v1" , }

local records

= {
{
id = "jit/loop-function-construction" ,
class = "blocker" ,
source = { [ "jit-loop-closure" ] = true , [ "loop-invariant-closure" ] = true , } ,
explanation = "LuaJIT has no recorder for constructing a function" ,
repair = "declare one function outside the loop and pass what varies to it" ,
contractSeverity = "error" ,
} ,
{
id = "jit/loop-upvalue-close" ,
class = "blocker" ,
explanation = "LuaJIT has no recorder for closing an upvalue" ,
repair = "move the captured lifetime outside the repeated region" ,
contractSeverity = "error" ,
} ,
{
id = "jit/ffi-vararg-policy" ,
class = "risk" ,
source = { [ "jit-boundary" ] = true , } ,
explanation = "this variadic FFI form depends on argument types and the target ABI" ,
repair = "move the call behind an explicit jit.off boundary when it is not hot" ,
contractSeverity = "error" ,
} ,
{
id = "jit/ffi-callback" ,
class = "risk" ,
source = { [ "jit-callback" ] = true , } ,
explanation = "a C call that re-enters Lua through this callback cannot remain on a trace" ,
repair = "disable the callback and its calling boundary with jit.off" ,
contractSeverity = "error" ,
} ,
{
id = "jit/disabled-callee" ,
class = "blocker" ,
explanation = "the resolved callee is explicitly disabled with jit.off" ,
repair = "remove @jit from the caller or keep the disabled call outside its hot path" ,
contractSeverity = "error" ,
} ,
{
id = "jit/dynamic-call" ,
class = "risk" ,
explanation = "the call target is dynamic, so its bytecode recordability is unknown" ,
} ,
}

local byId , bySource = { } , { }
for _ , reason in ipairs ( records ) do
byId [ reason . id ] = reason
for sourceName in pairs ( reason . source or { } ) do
bySource [ sourceName ] = reason
end
end

function catalog . reason ( id ) 
return byId [ id ]
end

function catalog . forSource ( sourceName ) 
return bySource [ sourceName ]
end

function catalog . profile ( ) 
return {
id = "static:" .. catalog . CATALOG_ID ,
luajitRevision = "static" ,
luajitVersion = 0 ,
architecture = "target" ,
operatingSystem = "target" ,
enabledRecorderFeatures = { } ,
bytecodeSchema = "static" ,
supported = true ,
}
end

local __nuppExportValue= catalog ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.tracecatalog"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.tracecatalog"]=__nuppExports;return __nuppExports