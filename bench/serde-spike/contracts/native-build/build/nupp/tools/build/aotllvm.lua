_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT12={}; local function __nuppT9(...) return {n=select("#",...),...} end; local __nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19,__nuppT20=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT10(value) return value end; local function __nuppT11(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT18({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT19(v.primary) for _,reason in __nuppT20(v.suppressed) do text=text.."\ncleanup: "..__nuppT19(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.build.aotllvm\0runtime\0001") };







local codegen = require ( "nupp.compiler.aot.llvm.codegen" )
local facts = require ( "nupp.compiler.aot.llvm.facts" )
local fs = require ( "nupp.compiler.fs" )
local llvmDetector = require ( "nupp.compiler.aot.llvm.detector" )
local llvmProgram = require ( "nupp.compiler.aot.llvm.program" )
local llvmProfile = require ( "nupp.compiler.aot.llvm.profile" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )
local toolruns = require ( "nupp.tools.build.toolruns" )

local aotllvm = { }



aotllvm . BACKEND = "llvm"



function aotllvm . selected ( ) 
local available , why = codegen . available ( )
if not available then
return nil , tostring ( why )
end
local _ , factsErr = aotllvm . facts ( )
if factsErr ~= nil then
return nil , "NUPP_AOT_FACTS: " .. tostring ( factsErr )
end

return true , nil
end



function aotllvm . facts ( ) 
return facts . parse ( os . getenv ( "NUPP_AOT_FACTS" ) or "all" )
end


function aotllvm . factsKey ( ) 
local selected = aotllvm . facts ( )

return selected ~= nil and facts . key ( selected ) or "all"
end




function aotllvm . wasmOracle ( ) 
return os . getenv ( "NUPP_AOT_WASM_ORACLE" ) == "1"
end



function aotllvm . selection ( ) 
return "llvm " .. aotllvm . version ( ) .. " facts=" .. aotllvm . factsKey ( ) .. (
aotllvm . wasmOracle ( ) and " wasm-oracle" or ""
)
end




function aotllvm . version ( ) 
if not codegen . available ( ) then
return "unavailable"
end

return codegen . version ( )
end



function aotllvm . note ( line ) local __nuppT8;
local path = os . getenv ( "NUPP_AOT_LLVM_REPORT" )
if path == nil or path == "" then
return
end
do const  __nuppT27= io . open ( path , "a" ) ; __nuppT8=__nuppT8 or {} ; local __nuppT28=__nuppT8[1]; if not __nuppT28 then __nuppT28=function(file) do
if file ~= nil then
file : write ( line , "\n" )
file : close ( )
end end; return "normal" end; __nuppT8[1]=__nuppT28 end; const __nuppT22,__nuppT23,__nuppT24=__nuppT14(__nuppT28,__nuppT10,__nuppT27); const __nuppT21=1; local __nuppT25={}; local __nuppT26=0; if __nuppT21>=1 and __nuppT27~=nil then  local __nuppT29,__nuppT30=__nuppT13(__nuppCleanup1,__nuppT27);  if not __nuppT29 then __nuppT26=__nuppT26+1; __nuppT25[__nuppT26]=__nuppT30 end; end; if not __nuppT22 then if __nuppT26>0 then __nuppT15(__nuppT11(__nuppT23,__nuppT25,1),0) else __nuppT15(__nuppT23,0) end end; if __nuppT26>0 then if __nuppT26>1 then __nuppT15(__nuppT11(__nuppT25[1],__nuppT25,2),0) else __nuppT15(__nuppT25[1],0) end end; if __nuppT23=="return" then  return __nuppT16(__nuppT24,1,__nuppT24.n)  end; end
end







function aotllvm . emit (
programs ,
tier ,
triple ,
logical ,
sourceFile
) 
local selected , profileErr = llvmProfile . of ( triple )
if selected == nil then
return nil , profileErr
end
local cpu = { }
for _ , program in ipairs ( programs ) do
if program . executionTarget ~= "gpu" then
cpu [ # cpu + 1 ] = program
end
end


local bridges = { }
for position , program in ipairs ( programs ) do
bridges [ program . symbol ] = position
end
local ok , module = pcall (
llvmProgram . module ,
cpu ,
tier ,
selected ,
( aotllvm . facts ( ) ) ,
sourceFile ,
logical ,
bridges ,
aotllvm . wasmOracle ( )
)
if not ok then
if llvmProgram . isUnsupported ( module ) then
return nil , tostring ( module )
end
error ( module , 0 )
end

return module , nil
end



function aotllvm . detector ( triple ) 
local selected = llvmProfile . of ( triple )
if selected == nil then
return nil
end

return llvmDetector . module ( ( selected ) . functionAttributes )
end




function aotllvm . takesRuntime ( triple ) 
local selected = triple ~= nil and llvmProfile . of ( triple ) or nil

return selected == nil or ( selected ) . linkedRuntime == nil
end


function aotllvm . flags ( triple , tier ) 
local selected = llvmProfile . of ( triple )
if selected == nil then
return { "triple=" .. triple , "tier=" .. tier }
end
local options = llvmProfile . options ( selected , tier )
local keys = { }
for key in pairs ( options ) do
keys [ # keys + 1 ] = key
end
table . sort ( keys )
local flags = { }
for _ , key in ipairs ( keys ) do
flags [ # flags + 1 ] = key .. "=" .. ( options [ key ] )
end

return flags
end



function aotllvm . assembly (
programs ,
tier ,
triple ,
sourceFile
) 
local ir , why = aotllvm . emit ( programs , tier , triple , true , sourceFile )
if ir == nil then
return nil , why
end
local selected = llvmProfile . of ( triple )
local options = llvmProfile . options ( selected , tier )
options . assembly = "1"
local compiled , err = codegen . compile ( ir , "<aot>" , options )
if compiled == nil or compiled . assembly == nil then
return nil , "compiling the LLVM IR failed: " .. tostring ( err )
end

return compiled . assembly , nil
end


aotllvm.Unit = {} aotllvm.Unit.__index = aotllvm.Unit ;_G.nupp.__reflect.link(aotllvm.Unit,__nuppT1[1],{ })









function aotllvm . compileMany ( units ) 
local jobs = { }
for position , unit in ipairs ( units ) do
local selected , profileErr = llvmProfile . of ( unit . triple )
if selected == nil then
return profileErr
end
jobs [
position
] = _G.setmetatable({ ir =
unit . ir ,  object =
unit . object .. ".tmp" ,  options =
llvmProfile . options ( selected , unit . tier ) }, codegen.Job)

end
local outcomes , err = codegen . compileFiles ( jobs , toolruns . width ( # jobs ) )
if outcomes == nil then
return "compiling the LLVM units failed: " .. tostring ( err )
end
local failure = nil
for position , outcome in ipairs ( outcomes ) do
local unit = units [ position ]
if outcome . error ~= nil then
os . remove ( jobs [ position ] . object )
failure = failure or "compiling " .. unit . ir .. " with LLVM failed: " .. tostring ( outcome . error )
else
local timings = ( tostring ( outcome . report ) : match ( "^(.-)object%-bytes" ) or "" ) : gsub ( "\n" , " " )
aotllvm . note ( ("compile\9%s\9%s") : format ( unit . ir , timings ) )
local installed , installErr = fs . installStaged ( jobs [ position ] . object , unit . object )
if not installed then
failure = failure or tostring ( installErr )
end
end
end

return failure
end





local function linkedRuntime ( selected , directory ) 
local carried = selected . linkedRuntime
if carried == nil then
return nil , nil
end
local text = require ( "nupp.compiler.bundled" ) . source ( carried )
if text == nil then
return nil , "this compiler carries no runtime " .. tostring ( carried )
end
local digest = require ( "nupp.compiler.hash" ) . digest ( ( text ) .. "\0" .. aotllvm . version ( ) )
local object = directory .. "/runtime." .. digest : sub ( 1 , 16 ) .. ".o"
if fs . exists ( object ) then
return object , nil
end
local ir = directory .. "/runtime." .. digest : sub ( 1 , 16 ) .. ".ll"
local wrote , writeErr = fs . writeFile ( ir , text )
if not wrote then
return nil , tostring ( writeErr )
end
local err = aotllvm . compileMany ( {
_G.setmetatable({ ir =  ir ,  triple =  selected . public ,  tier =  "baseline" ,  object =  object }, aotllvm.Unit)
} )
os . remove ( ir )
if err ~= nil then
return nil , err
end

return object , nil
end





local function windowsGlue ( selected , directory ) 
local coff = require ( "nupp.compiler.aot.llvm.coff" )
local names = require ( "nupp.compiler.aot.llvm.lua.runtime" ) . apiNames ( )
local ir = coff . binding ( selected . llvmTriple , names )
local digest = require (
"nupp.compiler.hash"
) . digest (
ir .. "\0" .. table . concat ( coff . CRT , "," ) .. "\0" .. table . concat ( coff . UCRT , "," ) .. "\0" .. aotllvm . version ( )
)
: sub ( 1 , 16 )
local object = directory .. "/luabind." .. digest .. ".o"
local crt = directory .. "/msvcrt." .. digest .. ".a"
local kernel32 = directory .. "/kernel32." .. digest .. ".a"
local ucrt = directory .. "/ucrtmath." .. digest .. ".a"
if not fs . exists ( object ) then
local source = directory .. "/luabind." .. digest .. ".ll"
local wrote , writeErr = fs . writeFile ( source , ir )
if not wrote then
return nil , tostring ( writeErr )
end
local err = aotllvm . compileMany ( {
_G.setmetatable({ ir =  source ,  triple =  selected . public ,  tier =  "baseline" ,  object =  object }, aotllvm.Unit)
} )
os . remove ( source )
if err ~= nil then
return nil , err
end
end
for _ , library in ipairs ( {
{ "msvcrt.dll" , crt , coff . CRT } ,
{ coff . UCRT_MODULE , ucrt , coff . UCRT } ,
{ "kernel32.dll" , kernel32 , coff . KERNEL32 }
} ) do
if not fs . exists ( library [ 2 ] ) then
local entries = { }
for _ , name in ipairs ( library [ 3 ] ) do
entries [ # entries + 1 ] = { name }
end
local err = codegen . importLibrary ( library [ 1 ] , library [ 2 ] , entries )
if err ~= nil then
return nil , "cannot write the import library for " .. tostring ( library [ 1 ] ) .. ": " .. err
end
end
end

return { object , crt , ucrt , kernel32 } , nil
end





function aotllvm . link ( triple , objects , output , root ) 
local selected , profileErr = llvmProfile . of ( triple )
if selected == nil then
return profileErr
end



local staged = output .. ".tmp"
if ( selected ) . format == "coff" and objects [ 1 ] ~= nil then
staged = fs . dirname ( objects [ 1 ] ) .. "/" .. fs . basename ( output )
end
os . remove ( staged )



local linked = { }
for _ , object in ipairs ( objects ) do
linked [ # linked + 1 ] = root ~= nil and fs . absolute ( object ) or object
end
local runtimeObject , runtimeErr = linkedRuntime ( selected , fs . dirname ( objects [ 1 ] or output ) )
if runtimeErr ~= nil then
return runtimeErr
end
if runtimeObject ~= nil then
linked [ # linked + 1 ] = runtimeObject
end
local strip = root ~= nil and fs . absolute ( root ) : gsub ( "/*$" , "/" ) or nil
local argv = llvmProfile . sharedLink ( selected , staged , linked , fs . basename ( output ) , strip )
if ( selected ) . format == "coff" then
local glue , glueErr = windowsGlue ( selected , fs . dirname ( objects [ 1 ] or output ) )
if glue == nil then
return glueErr
end
for position , argument in ipairs ( argv ) do
if argument == "/noentry" then
argv [ position ] = "/entry:" .. require ( "nupp.compiler.aot.llvm.coff" ) . ENTRY
end
end
for _ , file in ipairs ( glue ) do
argv [ # argv + 1 ] = file
end
end
local _ , err = codegen . link ( argv )
if err ~= nil then
os . remove ( staged )

return "linking the LLVM objects failed: " .. tostring ( err )
end
local installed , installErr = fs . installStaged ( staged , output )
if not installed then
return tostring ( installErr )
end

return nil
end




function aotllvm . archive ( triple , objects , output ) 
local selected , profileErr = llvmProfile . of ( triple )
if selected == nil then
return profileErr
end
local staged = output .. ".tmp"
os . remove ( staged )
local format = ( selected ) . format == "macho" and "darwin" or "gnu"
local err = codegen . archive ( staged , objects , format )
if err ~= nil then
os . remove ( staged )

return "archiving the LLVM objects failed: " .. tostring ( err )
end
local installed , installErr = fs . installStaged ( staged , output )
if not installed then
return tostring ( installErr )
end

return nil
end




function aotllvm . wasmLibm ( directory ) 
local text = require ( "nupp.compiler.bundled" ) . source ( "/aot/llvm/wasm/libm.ll" )
if text == nil then
return nil , "this compiler carries no Wasm libm"
end
local digest = require ( "nupp.compiler.hash" ) . digest ( ( text ) .. "\0" .. aotllvm . version ( ) )
local object = directory .. "/libm." .. digest : sub ( 1 , 16 ) .. ".o"
if fs . exists ( object ) then
return object , nil
end
local ir = directory .. "/libm." .. digest : sub ( 1 , 16 ) .. ".ll"
local wrote , writeErr = fs . writeFile ( ir , text )
if not wrote then
return nil , tostring ( writeErr )
end
local err = aotllvm . compileMany ( {
_G.setmetatable({ ir =  ir ,  triple =  "wasm32-unknown-emscripten" ,  tier =  "scalar" ,  object =  object }, aotllvm.Unit)
} )
os . remove ( ir )
if err ~= nil then
return nil , err
end

return object , nil
end





function aotllvm . linkWasm ( object , output , exports , libm ) 


local oracle = aotllvm . wasmOracle ( )
local argv

= {
"wasm-ld" ,
"--no-entry" ,
oracle and "--initial-memory=33554432" or "--initial-memory=4194304" ,
"--max-memory=67108864" ,
"-z" ,
oracle and "stack-size=16777216" or "stack-size=65536" ,
"--export=malloc" ,
"--export=free" ,
}
for _ , name in ipairs ( exports ) do
argv [ # argv + 1 ] = "--export=" .. name
end
argv [ # argv + 1 ] = "-o"
argv [ # argv + 1 ] = output
argv [ # argv + 1 ] = object
if libm ~= nil then
argv [ # argv + 1 ] = libm
end
local _ , err = codegen . link ( argv )
if err ~= nil then
os . remove ( output )

return "linking the Wasm module failed: " .. tostring ( err )
end

return nil
end




local function linkLinux (
kit ,
manifest ,
machine ,
output ,
archives ,
flags
) 
local argv

= {
"ld.lld" ,
"-m" ,
machine ,
"-pie" ,
"--eh-frame-hdr" ,
"-z" ,
"noexecstack" ,
"--hash-style=gnu" ,
"--build-id" ,
"-dynamic-linker" ,
tostring ( manifest . interpreter ) ,
"-o" ,
output ,
}
for _ , object in ipairs ( manifest . startup ) do
argv [ # argv + 1 ] = kit .. "/" .. tostring ( object )
end
argv [ # argv + 1 ] = "--whole-archive"
argv [ # argv + 1 ] = kit .. "/" .. tostring ( manifest . runtime )
for _ , archive in ipairs ( archives ) do
argv [ # argv + 1 ] = archive
end
argv [ # argv + 1 ] = "--no-whole-archive"
for _ , library in ipairs ( manifest . libraries ) do
argv [ # argv + 1 ] = kit .. "/" .. tostring ( library )
end
for _ , flag in ipairs ( flags ) do
argv [ # argv + 1 ] = flag
end
for _ , object in ipairs ( manifest . finish ) do
argv [ # argv + 1 ] = kit .. "/" .. tostring ( object )
end

argv [ # argv + 1 ] = "--export-dynamic"
local _ , err = codegen . link ( argv )
if err ~= nil then
os . remove ( output )

return "linking the standalone program failed: " .. tostring ( err )
end

return nil
end




local function linkWindows ( kit , manifest , output , archives , flags ) 
if type ( manifest . argv ) ~= "table" then
return "the link kit at " .. kit .. " records no link"
end
local argv = { "ld.lld" }
for _ , token in ipairs ( manifest . argv ) do
if token == "{output}" then
argv [ # argv + 1 ] = output
elseif token == "{runtime}" then
argv [ # argv + 1 ] = kit .. "/" .. tostring ( manifest . runtime )
elseif token == "{archives}" then
argv [ # argv + 1 ] = "--whole-archive"
for _ , archive in ipairs ( archives ) do
argv [ # argv + 1 ] = archive
end
argv [ # argv + 1 ] = "--no-whole-archive"
for _ , flag in ipairs ( flags ) do
argv [ # argv + 1 ] = flag
end
elseif token : sub ( 1 , 6 ) == "{kit}/" then
argv [ # argv + 1 ] = kit .. token : sub ( 6 )
else
argv [ # argv + 1 ] = token
end
end
local _ , err = codegen . link ( argv )
if err ~= nil then
os . remove ( output )

return "linking the standalone program failed: " .. tostring ( err )
end

return nil
end






function aotllvm . linkStandalone ( kit , output , archives , flags ) 
local text = fs . readFile ( kit .. "/kit.json" )
if text == nil then
return "the link kit at " .. kit .. " has no kit.json"
end
local json = require ( "nupp.codec.json" )
local manifest = json . decode ( text , json . NULL )
if type ( manifest ) ~= "table" or manifest . schemaVersion ~= 1 then
return "the link kit at " .. kit .. " has an unreadable kit.json"
end

local selected = type ( manifest . target ) == "string" and llvmProfile . of ( manifest . target ) or nil
if selected == nil then
return "the link kit at " .. kit .. " names no target this nupp can link for"
end
local machine = ( selected ) . machine
if manifest . platform == "linux" then
return linkLinux ( kit , manifest , machine , output , archives , flags )
elseif manifest . platform == "windows" then
return linkWindows ( kit , manifest , output , archives , flags )
elseif manifest . platform ~= "macos" then
return "the link kit at " .. kit .. " is for " .. tostring ( manifest . platform ) .. ", which this nupp cannot link"
end
local minimum = tostring ( manifest . minimum )
local argv

= {
"ld64.lld" ,
"-arch" ,
machine ,
"-platform_version" ,
"macos" ,
minimum ,
minimum ,
"-syslibroot" ,
kit .. "/" .. tostring ( manifest . syslibroot ) ,
"-o" ,
output ,
"-force_load" ,
kit .. "/" .. tostring ( manifest . runtime ) ,
}
for _ , archive in ipairs ( archives ) do
argv [ # argv + 1 ] = "-force_load"
argv [ # argv + 1 ] = archive
end
for _ , library in ipairs ( manifest . libraries ) do
argv [ # argv + 1 ] = tostring ( library )
end
for _ , flag in ipairs ( flags ) do
argv [ # argv + 1 ] = flag
end

argv [ # argv + 1 ] = "-export_dynamic"
local _ , err = codegen . link ( argv )
if err ~= nil then
os . remove ( output )

return "linking the standalone program failed: " .. tostring ( err )
end

return nil
end

local __nuppExportValue= aotllvm ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.aotllvm"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.aotllvm"]=__nuppExports;return __nuppExports