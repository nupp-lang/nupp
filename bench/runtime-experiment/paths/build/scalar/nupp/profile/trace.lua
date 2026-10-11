_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()























local vmdef = require ( "jit.vmdef" )

local trace = { }


































trace . CATALOG_VERSION = 1
trace . CATALOG_ID = "nupp-trace-reasons-v1"
trace . PINNED_LUAJIT_REVISION = "1edc3e52b67eaf6ce5f809be8e17d6862594b8bc"
trace . PINNED_LUAJIT_VERSION = 1785763465

local records

= {
{
id = "jit/tailcall-constructor" ,
class = "risk" ,
explanation = "a constructor in tail position can leave the root trace before its caller loop closes" ,
repair = "bind the constructed result before returning it and inspect run --jit-aborts" ,
} ,
{
id = "jit/loop-function-construction" ,
class = "blocker" ,
opcodes = { FNEW = true } ,
source = { [ "jit-loop-closure" ] = true , [ "loop-invariant-closure" ] = true } ,
explanation = "LuaJIT has no recorder for constructing a function" ,
repair = "declare one function outside the loop and pass what varies to it" ,
lint = "NUPP2515" ,
contractSeverity = "error" ,
} ,
{
id = "jit/loop-upvalue-close" ,
class = "blocker" ,
opcodes = { UCLO = true } ,
explanation = "LuaJIT has no recorder for closing an upvalue" ,
repair = "move the captured lifetime outside the repeated region" ,
contractSeverity = "error" ,
} ,
{
id = "jit/ffi-vararg-policy" ,
class = "risk" ,
source = { [ "jit-boundary" ] = true } ,
explanation = "this variadic FFI form depends on argument types and the target ABI" ,
repair = "move the call behind an explicit jit.off boundary when it is not a hot operation" ,
lint = "NUPP2514" ,
contractSeverity = "error" ,
} ,
{
id = "jit/ffi-callback" ,
class = "risk" ,
source = { [ "jit-callback" ] = true } ,
explanation = "a C call that re-enters Lua through this callback cannot remain on a trace" ,
repair = "disable the callback and its calling boundary with jit.off" ,
lint = "NUPP2502" ,
contractSeverity = "error" ,
} ,
{
id = "jit/disabled-callee" ,
class = "blocker" ,
explanation = "the resolved callee is explicitly disabled with jit.off" ,
repair = "remove @jit from the caller or keep the disabled call outside its checked hot path" ,
contractSeverity = "error" ,
} ,
{
id = "jit/dynamic-call" ,
class = "risk" ,
explanation = "the call target is dynamic, so its bytecode recordability is unknown" ,
} ,
{ id = "jit/expected-loop-leave" , class = "stop" , runtime = { "leaving loop in root trace" } } ,
{ id = "jit/expected-inner-loop" , class = "stop" , runtime = { "inner loop in root trace" } } ,
{ id = "jit/expected-down-recursion" , class = "stop" , runtime = { "down-recursion, restarting" } } ,
{ id = "jit/expected-up-recursion" , class = "stop" , runtime = { "up-recursion" } } ,
{ id = "jit/retry-recording" , class = "stop" , runtime = { "retry recording" } } ,
{ id = "jit/runtime-blacklisted" , class = "risk" , runtime = { "blacklisted" } } ,
{ id = "jit/runtime-trace-too-short" , class = "stop" , runtime = { "trace too short" } } ,
{ id = "jit/runtime-trace-too-long" , class = "risk" , runtime = { "trace too long" } } ,
{ id = "jit/runtime-trace-too-deep" , class = "risk" , runtime = { "trace too deep" } } ,
{ id = "jit/runtime-too-many-snapshots" , class = "risk" , runtime = { "too many snapshots" } } ,
{ id = "jit/runtime-loop-unroll-limit" , class = "risk" , runtime = { "loop unroll limit reached" } } ,
{ id = "jit/runtime-call-unroll-limit" , class = "risk" , runtime = { "call unroll limit reached" } } ,
{ id = "jit/runtime-disabled-callee" , class = "blocker" , runtime = { "JIT compilation disabled for function" } } ,
{ id = "jit/runtime-ffi-call" , class = "risk" , runtime = { "NYI: unsupported C function type" } } ,
{ id = "jit/runtime-ffi-conversion" , class = "risk" , runtime = { "NYI: unsupported C type conversion" } } ,
{ id = "jit/runtime-type-instability" , class = "risk" , runtime = { "persistent type instability" } } ,
{
id = "jit/runtime-machine-code-limit" ,
class = "risk" ,
runtime = { "machine code too long" , "hit mcode limit (retrying)" , "failed to allocate mcode memory" , }
} ,
{ id = "jit/runtime-recorder-error" , class = "risk" , runtime = { "error thrown or hook called during recording" } } ,
{ id = "jit/runtime-unknown" , class = "risk" } ,
}

local byId , byOpcode , bySource , byRuntime = { } , { } , { } , { }
for _ , record in ipairs ( records ) do
byId [ record . id ] = record
for opcode in pairs ( record . opcodes or { } ) do
byOpcode [ opcode ] = record
end
for source in pairs ( record . source or { } ) do
bySource [ source ] = record
end
for _ , format in ipairs ( record . runtime or { } ) do
byRuntime [ format ] = record
end
end





local function smallDigest ( value ) 
local digest = bit . tobit ( 2166136261 )
for index = 1 , # value do
local mixed = bit . bxor ( digest , value : byte ( index ) )
digest = bit . tobit ( bit . lshift ( mixed , 24 ) + bit . lshift ( mixed , 8 ) + mixed * 147 )
end

return bit . tohex ( digest )
end




function trace . profile ( ) 
local status = { jit . status ( ) }
local flags = { }
for index = 2 , # status do
flags [ # flags + 1 ] = tostring ( status [ index ] )
end
table . sort ( flags )



local version = math . floor ( tonumber ( jit . version : match ( "LuaJIT 2%.1%.(%d+)" ) ) or jit . version_num )
local revision = version == trace . PINNED_LUAJIT_VERSION and trace . PINNED_LUAJIT_REVISION
or "external:" .. tostring ( version )
local bytecodeSchema = smallDigest ( vmdef . bcnames )
local id = table . concat ( { revision , jit . arch , jit . os , table . concat ( flags , "," ) , bytecodeSchema } , "|" )

return {
id = id ,
luajitRevision = revision ,
luajitVersion = version ,
architecture = jit . arch ,
operatingSystem = jit . os ,
enabledRecorderFeatures = flags ,
bytecodeSchema = bytecodeSchema ,
supported = revision == trace . PINNED_LUAJIT_REVISION ,
}
end





function trace . reason ( id ) 
return byId [ id ]
end





function trace . forOpcode ( opcode ) 
return byOpcode [ opcode ]
end








function trace . forSource ( source ) 
return bySource [ source ]
end





function trace . opcodeName ( opcode ) 
local start = opcode * 6 + 1
return ( vmdef . bcnames : sub ( start , start + 5 ) : gsub ( "%s+$" , "" ) )
end












function trace . runtime ( errorCode , errorArg ) 
if not errorCode then
return byId [ "jit/runtime-unknown" ] , "abort"
end
local format = vmdef . traceerr [ errorCode ]
if not format then
return byId [ "jit/runtime-unknown" ] , "error " .. tostring ( errorCode )
end
if format : find ( "NYI: bytecode" , 1 , true ) and type ( errorArg ) == "number" then
local opcode = trace . opcodeName ( errorArg )
return byOpcode [ opcode ] or byId [ "jit/runtime-unknown" ] , "NYI: bytecode " .. opcode
end
local record = byRuntime [ format ] or byId [ "jit/runtime-unknown" ]
if errorArg == nil then
return record , format
end
local ok , detail = pcall ( string . format , format , errorArg )

return record , ok and detail or format
end







function trace . records ( ) 
local copy = { }
for index , record in ipairs ( records ) do
copy [ index ] = record
end

return copy
end

local __nuppExportValue= trace ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.profile.trace"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.profile.trace"]=__nuppExports;return __nuppExports