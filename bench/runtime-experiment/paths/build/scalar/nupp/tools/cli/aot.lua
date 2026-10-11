_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.aot\0runtime\0001") };

























local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "aot" )
local report = require ( "nupp.tools.cli.report" )
local cliModule = require ( "nupp.cli" )

local REPORT_SCHEMA = {
type = "object" ,
description = "What every @aot function in one file lowered to." ,
properties = {
ok = report . OK ,
diagnostics = report . DIAGNOSTICS ,
file = { type = "string" } ,
target = {
type = "object" ,
description = "What the species were chosen for." ,
properties = { triple = { type = "string" } , architecture = { type = "string" } , tier = { type = "string" } , } ,
} ,
functions = {
type = "array" ,
description = "One entry per @aot function, in source order." ,
items = {
type = "object" ,
properties = {
name = { type = "string" } ,
symbol = { type = "string" } ,
entryMode = { type = "string" , enum = { "kernel" , "lua-builder" } } ,
builderMode = { type = "string" , enum = { "eager" , "pull" , "serde" } } ,
runtimeAbi = { type = "string" } ,
registrar = { type = "string" } ,
gpu = {
type = "object" ,
description = "Shader identity shared with runtime GPU cost records." ,
properties = {
artifactId = { type = "string" } ,
file = { type = "string" , description = "The authored file, as an absolute path." } ,
range = report . RANGE ,
entrypoint = { type = "string" } ,
threads = { type = "integer" } ,
} ,
} ,
loops = {
type = "array" ,
description = "One measured decision per loop, in source order." ,
items = {
type = "object" ,
properties = {
id = { type = "integer" } ,
kind = { type = "string" , enum = { "map" , "fornum" , "while" , "repeat" } } ,
range = {
type = "object" ,
description = "From the loop's first authored position to the end of the last line the loop IR retains."
,
properties = report . RANGE . properties ,
required = report . RANGE . required ,
} ,
nodes = { type = "integer" } ,
simdOperations = { type = "integer" } ,
luaOperations = { type = "integer" } ,
nativeReads = { type = "integer" } ,
nativeWrites = { type = "integer" } ,
mayRaise = { type = "boolean" } ,
outcome = { type = "string" , enum = { "explicit-simd" , "scalar" } , } ,
reason = { type = "string" } ,
} ,
} ,
} ,
} ,
} ,
} ,
ir = { type = "string" } ,
llvm = { type = "string" , description = "The LLVM IR the unit is compiled from." } ,
spirv = { type = "string" , description = "Canonical SPIR-V bytes as lowercase hexadecimal." } ,
binding = { type = "string" } ,
asm = {
type = "object" ,
description = "The instructions the unit compiled to. Present only for --emit asm, because producing it runs the code generator."
,
properties = {
toolchain = {
type = "object" ,
description = "The code generator that produced them, which is part of the answer: two runs are comparable only when this is the same."
,
properties = { command = { type = "string" } , version = { type = "string" } , } ,
} ,
flags = {
type = "array" ,
description = "Every flag it was given, in order. The same flags a build compiles this tier's unit with."
,
items = { type = "string" } ,
} ,
functions = {
type = "array" ,
description = "One entry per emitted symbol that has instructions, ordered by role and then by where the compiler wrote it."
,
items = {
type = "object" ,
properties = {
symbol = { type = "string" } ,
name = { type = "string" } ,
role = {
type = "string" ,
description = "Which body this symbol is. Listings are reported in this order." ,
enum = { "kernel" , "oracle" , "wrapper" , "registrar" , "reporter" , "helper" } ,
} ,
counts = {
type = "object" ,
description = "`total` is every instruction. The rest are the architecture's rules over the mnemonic and the operand shape."
,
properties = {
total = { type = "integer" } ,
vector = { type = "integer" } ,
loads = { type = "integer" } ,
stores = { type = "integer" } ,
branches = { type = "integer" } ,
calls = { type = "integer" } ,
stack = { type = "integer" } ,
} ,
required = { "total" } ,
} ,
instructions = {
type = "array" ,
items = {
type = "object" ,
properties = {
label = {
type = "string" ,
description = "The label this is the first instruction under. Absent when none precedes it."
,
} ,
loopIds = {
type = "array" ,
items = { type = "integer" } ,
description = "Loops whose authored ranges contain this location; nested loops can share an instruction."
} ,
sourceFile = { type = "string" } ,
sourceLine = { type = "integer" } ,
generatedColumn = {
type = "integer" ,
description = "Column in the generated IR; authored lines come from its line table."
} ,
text = { type = "string" } ,
mnemonic = { type = "string" } ,
operands = { type = "string" } ,
kinds = { type = "array" , items = { type = "string" } } ,
} ,
required = { "text" , "mnemonic" , "kinds" } ,
} ,
} ,
} ,
required = { "symbol" , "role" , "counts" , "instructions" } ,
} ,
} ,
} ,
} ,
} ,
required = { "ok" , "file" , "diagnostics" } ,
}



local function lineStarts ( source ) 
local starts = { 1 }
for at in source : gmatch ( "\n()" ) do
starts [ # starts + 1 ] = at
end

return starts
end

local function positionAt ( starts , line , column ) 
local first = starts [ line ] or 1

return { line = line , column = column , offset = first + column - 1 }
end



local function loopRange ( starts , loop ) 
local last = loop . lastLine or loop . line
local nextLine = starts [ last + 1 ]
local width = nextLine and nextLine - ( starts [ last ] or 1 ) or 1

return { start = positionAt ( starts , loop . line , loop . column or 1 ) , [ "end" ] = positionAt ( starts , last , width ) }
end



local function aotDiagnostic ( problem ) 
return {
filename = problem . file ,
line = problem . line ,
col = problem . column ,
code = problem . code ,
msg = problem . message
}
end


local function summarise ( path , program , artifacts ) 
local gpu = artifacts and artifacts . gpu and artifacts . gpu [ program . symbol ] ~= nil
local what
if gpu then
what = "gpu, one iteration per GPU invocation"
elseif program . nativeOnly == true then
what = "explicit simd, native-only"
elseif program . usesSimd == true then
what = "explicit simd"
elseif program . entryMode == "lua-builder" then
what = "scalar, lanes do not apply to a lua-builder entry"
else
what = "scalar"
end

return ("%s: %s, %s, %s") : format ( path , program . name , program . entryMode , what )
end









local function assembly ( artifacts , selected , wanted , sourceFile ) 
local instructionsMod = require ( "nupp.compiler.aot.instructions" )
local targets = require ( "nupp.compiler.aot.target" )
if not instructionsMod . reads ( selected . architecture ) then
return nil , ("there are no instruction rules for %s; --emit asm reads %s")

: format ( selected . architecture , table . concat ( instructionsMod . ARCHITECTURES , " and " ) )
end

local aotllvm = require ( "nupp.tools.build.aotllvm" )
local available , backendErr = aotllvm . selected ( )
if available ~= true then
return nil , tostring ( backendErr )
end
local text = aotllvm . assembly ( artifacts . programs , selected . tier , selected . triple , sourceFile )
if text == nil then
return nil , "the LLVM backend has no profile for " .. selected . triple
end

local listings = instructionsMod . parse ( text , selected . architecture , targets . system ( selected . triple ) )




local claims = { }
for _ , program in ipairs ( artifacts . programs ) do
claims [ program . symbol ] = _G.setmetatable({ name =  program . name ,  role =  "kernel" }, instructionsMod.Claim)
claims [ program . symbol .. "_forced_scalar" ] = _G.setmetatable({ name =  program . name ,  role =  "oracle" }, instructionsMod.Claim)
claims [ program . symbol .. "_lua" ] = _G.setmetatable({ name =  program . name ,  role =  "wrapper" }, instructionsMod.Claim)
if program . registrar ~= nil then
claims [ tostring ( program . registrar ) ] = _G.setmetatable({ name =  program . name ,  role =  "registrar" }, instructionsMod.Claim)
end
end
instructionsMod . claim ( listings , claims )

for _ , listing in ipairs ( listings ) do
for index , program in ipairs ( artifacts . programs ) do
if listing . name == program . name then
for _ , instruction in ipairs ( listing . instructions ) do
local file = instruction . sourceFile
local line = instruction . sourceLine
if file ~= nil and line ~= nil and file : sub ( - # sourceFile ) == sourceFile then
local ids = { }
for _ , loop in ipairs ( artifacts . loops [ index ] or { } ) do
if line >= loop . line and line <= loop . lastLine then
ids [ # ids + 1 ] = loop . id
end
end
instruction . loopIds = ids
end
end
end
end
end
local shown = instructionsMod . order ( listings )
if wanted ~= nil then



shown = instructionsMod . select ( shown , wanted )
if # shown == 0 then
return nil , ("no function named %s was compiled here; this file has %s")

: format ( wanted , table . concat ( instructionsMod . names ( listings ) , ", " ) )
end
end

return {
toolchain = { command = "<llvm>" , version = aotllvm . version ( ) , } ,
flags = aotllvm . flags ( selected . triple , selected . tier ) ,
functions = shown ,
} , nil
end


local function writeListing ( listing ) 
local counts = listing . counts
io . write (
("-- %s%s, %s: %d instructions, %d vector, %d loads, %d stores, %d branches, %d calls, %d stack\n")

: format (
listing . symbol ,
listing . name ~= nil and ( " (" .. tostring ( listing . name ) .. ")" ) or "" ,
listing . role ,
counts . total ,
counts . vector ,
counts . loads ,
counts . stores ,
counts . branches ,
counts . calls ,
counts . stack
)
)
for _ , one in ipairs ( listing . instructions ) do
if one . label ~= nil then
io . write ( tostring ( one . label ) .. ":\n" )
end


io . write (
one . operands ~= "" and ("      %-7s %s\n") : format ( one . mnemonic , one . operands )
or ( "      " .. one . mnemonic .. "\n" )
)
end
io . write ( "\n" )
end

local function run ( options ) 
local positional = { options . file }
local aot = require ( "nupp.compiler.aot.compile" )
local targets = require ( "nupp.compiler.aot.target" )
local paths = positional
if # paths ~= 1 then
return usageError ( "exactly one source file is required" )
end

local path = paths [ 1 ]
local asJson = options . format == "json"



local function refuse ( code , message ) 
if asJson then
return report . failure ( REPORT_SCHEMA , { report . runDiagnostic ( code , message , nil , path ) } , { file = path } )
end
io . stderr : write ( require ( "nupp.tools.cli.error" ) . message ( message ) .. "\n" )

return 1
end




local selected , targetErr = targets . select ( options . triple , options . features )
if selected == nil then
return refuse ( report . UNKNOWN_NAME , tostring ( targetErr ) )
end




local envMod = require ( "nupp.compiler.project.env" )
local fs = require ( "nupp.compiler.fs" )
local root = fs . dirname ( fs . absolute ( path ) )
while not fs . exists ( fs . join ( root , "nupp.lua" ) ) do
local parent = fs . dirname ( root )
if parent == root then
root = "."
do break end
end
root = parent
end
local environment = envMod . new ( root )



environment . config . _target = environment . config . _target or { }





environment . config . _target . aot = "inspect"
if ( environment . config ) . build ~= nil then
local configured = require ( "nupp.compiler.project.projectconfig" ) . targetConfig ( environment . config , nil )
local policy = configured ~= nil and ( configured ) . aot or nil
environment . config . _target . gpuBindings = policy == "require" or policy == "require-wasm"
end
local checked = asJson and { } or nil
local tree , source = require ( "nupp.tools.cli.compile" ) . check ( path , environment , { } , checked )
if tree == nil then
return checked and report . failure ( REPORT_SCHEMA , checked , { file = path } ) or 1
end

local library = options . library or "<object>"
local artifacts , diagnostics = aot . artifacts ( source , path , tree , library , selected )
if artifacts == nil then
if asJson then
local refusals = { }
for _ , problem in ipairs ( diagnostics ) do
refusals [ # refusals + 1 ] = ( { filename = problem . file , line = problem . line , col = problem . column , code = problem . code , msg = problem . message } )
end

return report . failure ( REPORT_SCHEMA , refusals , { file = path } )
end
for _ , problem in ipairs ( diagnostics ) do
io . stderr : write ( aot . renderDiagnostic ( problem ) .. "\n" )
end

return 1
end

local emit = options . emit
local spirvParts = { }
local wgslParts = { }
for _ , program in ipairs ( artifacts . programs ) do
local artifact = artifacts . gpu [ program . symbol ]
local selectedFunction = options . functionName
if artifact ~= nil
and ( selectedFunction == nil or selectedFunction == program . name or selectedFunction == program . symbol )
then
spirvParts [ # spirvParts + 1 ] = artifact . spirv
if artifact . wgsl ~= nil then
wgslParts [ # wgslParts + 1 ] = artifact . wgsl
end
end
end
local wgsl = table . concat ( wgslParts , "\n" )
local spirvHex = nil
if emit == "spirv" and # spirvParts == 1 and options . format == "json" then
local bytes = { }
for index = 1 , # spirvParts [ 1 ] do
bytes [ index ] = ("%02x") : format ( spirvParts [ 1 ] : byte ( index ) )
end
spirvHex = table . concat ( bytes )
end
if emit == "wgsl" and # wgslParts == 0 then
return refuse ( report . UNKNOWN_NAME , "no GPU function matched --emit wgsl with the webgpu-int32 profile" )
end
if emit == "spirv" and # spirvParts ~= 1 then
return refuse (
report . UNKNOWN_NAME ,
# spirvParts == 0 and "no GPU function matched --emit spirv"
or "--emit spirv needs one GPU function; select it with --function"
)
end



local instructionReport = nil
if emit == "asm" then
local built , instructionErr = assembly ( artifacts , selected , options . functionName , path )
if built == nil then
return refuse ( report . TOOL_FAILED , tostring ( instructionErr ) )
end
instructionReport = built
end
local llvmText = nil
if emit == nil and options . format == "json" then


local aotllvm = require ( "nupp.tools.build.aotllvm" )
local target = selected
local ok , module = pcall ( aotllvm . emit , artifacts . programs , target . tier , target . triple )
llvmText = ok and module or nil
elseif emit == "llvm" then
local aotllvm = require ( "nupp.tools.build.aotllvm" )
local target = selected
local _ , factsErr = aotllvm . facts ( )
if factsErr ~= nil then
return refuse ( report . TOOL_FAILED , "NUPP_AOT_FACTS: " .. tostring ( factsErr ) )
end
local ok , module , why = pcall ( aotllvm . emit , artifacts . programs , target . tier , target . triple )
if not ok or module == nil then
return refuse ( report . TOOL_FAILED , tostring ( ok and why or module ) )
end
llvmText = module
end
if asJson then
local starts = lineStarts ( source )
local functions = { }
for position , program in ipairs ( artifacts . programs ) do
local shader = artifacts . gpu [ program . symbol ]
local gpu = nil
if shader ~= nil then
local at = positionAt ( starts , shader . sourceLine or 1 , shader . sourceColumn or 1 )
gpu = {
artifactId = shader . artifactId ,
file = shader . sourceFile ,
range = { start = at , [ "end" ] = at } ,
entrypoint = shader . entrypoint ,
threads = shader . threads ,
}
end
local loops = { }
for index , loop in ipairs ( artifacts . loops [ position ] or { } ) do
loops [
index
] = {
id = loop . id ,
kind = loop . kind ,
range = loopRange ( starts , loop ) ,
nodes = loop . nodes ,
simdOperations = loop . simdOperations ,
luaOperations = loop . luaOperations ,
nativeReads = loop . nativeReads ,
nativeWrites = loop . nativeWrites ,
mayRaise = loop . mayRaise ,
outcome = loop . outcome ,
reason = loop . reason ,
}
end
functions [
position
] = {
name = program . name ,
gpu = gpu ,
symbol = program . symbol ,
entryMode = program . entryMode ,
builderMode = program . builderMode ,
runtimeAbi = program . runtimeAbi ,
registrar = program . registrar ,
loops = loops ,
}
end
io . write (
report . encode ( {
ok = true ,
diagnostics = report . diagnosticValues ( checked or { } ) ,
file = path ,
target = {
triple = ( selected ) . triple ,
architecture = ( selected ) . architecture ,
tier = ( selected ) . tier ,
} ,
functions = functions ,
ir = ( emit == nil or emit == "ir" ) and artifacts . irText or nil ,
llvm = llvmText ,
spirv = spirvHex ,
wgsl = emit == "wgsl" and wgsl or nil ,
binding = ( emit == nil or emit == "binding" ) and artifacts . binding or nil ,
asm = instructionReport ,
} ) .. "\n"
)
elseif emit == "ir" then
io . write ( artifacts . irText )
elseif emit == "llvm" then
io . write ( llvmText )
elseif emit == "spirv" then
io . write ( spirvParts [ 1 ] )
elseif emit == "wgsl" then
io . write ( wgsl )
elseif emit == "asm" then
io . write (
("-- %s, %s, %s, %s\n")

: format (
path ,
( selected ) . triple ,
( selected ) . tier ,
instructionReport . toolchain . version
)
)
for _ , listing in ipairs ( instructionReport . functions ) do
writeListing ( listing )
end
elseif emit == "binding" then
io . write ( artifacts . binding )
else
for _ , program in ipairs ( artifacts . programs ) do
io . write ( summarise ( path , program , artifacts ) .. "\n" )
end
end

return 0
end

















local Aot = {} Aot.__index = Aot































function Aot:run() 
return run ( self )
end ;Aot.__nuppInit1=function(__nuppT12, a1, a2, a3, a4, a5, a6, a7, a8) __nuppT12.emit = a1 __nuppT12.functionName = a2 __nuppT12.triple = a3 __nuppT12.features = a4 __nuppT12.library = a5 if a6 == nil then __nuppT12.format = "text" else __nuppT12.format = a6 end if a7 == nil then __nuppT12.schema = false else __nuppT12.schema = a7 end __nuppT12.file = a8 return __nuppT12 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Show what the @aot functions in a file compile to.\n\nWith no artifact, reports whether each function uses scalar, explicit SIMD, or GPU\nexecution. Select verified IR, LLVM IR, native GPU SPIR-V, browser GPU WGSL,\nnative assembly, or the generated Nupp binding with `--emit`.\n\nExamples:\n\n    nupp aot bench/kernel-subset-spike/mandelbrot.nupp\n    nupp aot --emit ir src/kernel.nupp\n    nupp aot --emit llvm src/kernel.nupp\n    nupp aot --emit asm --function scale src/kernel.nupp\n    nupp aot --emit wgsl --function transform src/gpu.nupp\n    nupp aot --format json src/kernel.nupp",["group"]=false,["hidden"]=false,["name"]="aot",["summary"]="Show what the @aot functions in a file compile to."},["fieldCount"]=8,["fields"]={{["arity"]="required",["choices"]={"ir","llvm","spirv","wgsl","asm","binding"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="--emit",["documentation"]="Artifact to print: ir, llvm, spirv, wgsl, asm, or binding.",["field"]="emit",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"emit"},["optional"]=true,["required"]=false,["role"]="option",["value"]="ARTIFACT"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--function",["documentation"]="Show only this function.",["field"]="functionName",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"function"},["optional"]=true,["required"]=false,["role"]="option",["value"]="NAME"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--triple",["documentation"]="Target triple to compile for.",["field"]="triple",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"triple"},["optional"]=true,["required"]=false,["role"]="option",["value"]="TRIPLE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--features",["documentation"]="CPU feature tier to promise.",["field"]="features",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"features"},["optional"]=true,["required"]=false,["role"]="option",["value"]="TIER"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--library",["documentation"]="Compiled object path used by a generated binding.",["field"]="library",["hidden"]=false,["index"]=5,["long"]=true,["names"]={"library"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PATH"},{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=6,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=7,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file to inspect.",["field"]="file",["hidden"]=false,["index"]=8,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file to inspect.",["field"]="file",["hidden"]=false,["index"]=8,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="57cde58344e8456227cdb536b52b39090470817698beff2aacf47041f0e3f4e9",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.aot:Aot:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="aot"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Show what the @aot functions in a file compile to."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Aot?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Aot",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.aot:Aot:1",Aot,__nuppDerived) ;Aot["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Aot["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("aot")end ;Aot["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Show what the @aot functions in a file compile to.")end ;Aot["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Aot,__nuppT1[1],{ })


function Aot . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Aot } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.aot"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.aot"]=__nuppExports;return __nuppExports