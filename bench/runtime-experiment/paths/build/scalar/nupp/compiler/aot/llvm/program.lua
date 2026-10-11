_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.program\0runtime\0001") };















local builder = require ( "nupp.compiler.aot.llvm.builder" )
local context = require ( "nupp.compiler.aot.llvm.context" )
local countRules = require ( "nupp.compiler.aot.counts" )
local dwarf = require ( "nupp.compiler.aot.llvm.dwarf" )
local expressions = require ( "nupp.compiler.aot.llvm.expressions" )
local memory = require ( "nupp.compiler.aot.llvm.simd.memory" )
local rearrange = require ( "nupp.compiler.aot.llvm.simd.rearrange" )
local reduce = require ( "nupp.compiler.aot.llvm.simd.reduce" )
local simdReducers = require ( "nupp.compiler.aot.llvm.simd.reducers" )
local vectors = require ( "nupp.compiler.aot.llvm.simd.vectors" )
local facts = require ( "nupp.compiler.aot.llvm.facts" )
local luaEntry = require ( "nupp.compiler.aot.llvm.lua.entry" )
local luaStatements = require ( "nupp.compiler.aot.llvm.lua.statements" )
local luaValues = require ( "nupp.compiler.aot.llvm.lua.values" )
local profile = require ( "nupp.compiler.aot.llvm.profile" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )
local statements = require ( "nupp.compiler.aot.llvm.statements" )
local target = require ( "nupp.compiler.aot.target" )
local types = require ( "nupp.compiler.aot.llvm.types" )
local wasmBridge = require ( "nupp.compiler.aot.llvm.wasm.bridge" )
local wasmRuntime = require ( "nupp.compiler.aot.llvm.wasm.runtime" )

local llvmProgram = { }



for _ , lowering in ipairs ( {
vectors . EXPRESSIONS ,
rearrange . EXPRESSIONS ,
reduce . EXPRESSIONS ,
memory . EXPRESSIONS ,
simdReducers . EXPRESSIONS ,
luaValues . EXPRESSIONS
} ) do
for operation , lower in pairs ( lowering ) do
expressions . handlers [ operation ] = lower
end
end
for _ , lowering in ipairs ( { memory . STATEMENTS , simdReducers . STATEMENTS } ) do
for operation , lower in pairs ( lowering ) do
statements . handlers [ operation ] = lower
end
end
statements . wideMask = vectors . wideMask
for operation , bind in pairs ( simdReducers . BINDERS ) do
statements . binders [ operation ] = bind
end
for operation , lower in pairs ( luaStatements . STATEMENTS ) do
statements . builderHandlers [ operation ] = lower
end


llvmProgram.Unit = {} llvmProgram.Unit.__index = llvmProgram.Unit ;_G.nupp.__reflect.link(llvmProgram.Unit,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.compiler.aot.llvm.builder\0runtime\0001","nupp.compiler.aot.llvm.builder") , _G.nupp.__reflect.reference("nupp.compiler.aot.llvm.profile\0runtime\0001","nupp.compiler.aot.llvm.profile") , _G.nupp.__reflect.reference("nupp.compiler.aot.llvm.facts\0runtime\0001","nupp.compiler.aot.llvm.facts") , _G.nupp.__reflect.reference("nupp.compiler.aot.llvm.dwarf\0runtime\0001","nupp.compiler.aot.llvm.dwarf") })






















local function physical ( symbol , tier ) 
return tier ~= nil and target . symbol ( symbol , tier ) or symbol
end




local function disjointFromWrites ( program , param ) 
local regionOf = { }
for _ , other in ipairs ( program . params ) do
if other . region ~= nil then
regionOf [ other . region ] = other
end
end
local disjoint = { }
for _ , fact in ipairs ( program . aliasFacts ) do
if fact . relation == "disjoint" then
disjoint [ fact . left .. " " .. fact . right ] = true
disjoint [ fact . right .. " " .. fact . left ] = true
end
end
for _ , other in ipairs ( program . params ) do
if other ~= param and scalarIR . isSpan ( other ) and other . kind == "write_span" then
if param . region == nil or other . region == nil then
return false
end
if not disjoint [ tostring ( param . region ) .. " " .. tostring ( other . region ) ] then
return false
end
end
end
if param . kind == "write_span" then

for _ , other in ipairs ( program . params ) do
if other ~= param and scalarIR . isSpan ( other ) then
if param . region == nil or other . region == nil then
return false
end
if not disjoint [ tostring ( param . region ) .. " " .. tostring ( other . region ) ] then
return false
end
end
end
end

return true
end


local function spanParameter ( unit , program , param ) 
local attributes = { "ptr" }
if unit . facts . alias and disjointFromWrites ( program , param ) then
attributes [ # attributes + 1 ] = "noalias"
end
if unit . facts . access then
attributes [ # attributes + 1 ] = "captures(none)"
if param . kind == "read_span" then
attributes [ # attributes + 1 ] = "readonly"
end
end
attributes [ # attributes + 1 ] = "%p_" .. param . name

return table . concat ( attributes , " " )
end


local function functionAttributes ( selected , program , extra ) 
local parts = { "nounwind" , "uwtable" }
if selected . functionAttributes ~= "" then
parts [ # parts + 1 ] = selected . functionAttributes
end
if program . fpContract == true then
parts [ # parts + 1 ] = "\"nupp-fp-contract\""
end
if extra ~= nil then
parts [ # parts + 1 ] = extra
end

return table . concat ( parts , " " )
end



local function helpers ( unit , ctx , program ) 
local module = unit . module
for _ , helper in ipairs ( program . helpers or { } ) do



local name = "@" .. ( helper . native == true and physical ( helper . uniqueName , unit . tier ) or helper . uniqueName )
local params = { }
local paramTypes = { }
for _ , param in ipairs ( helper . params ) do
local named = context . species ( ctx , tostring ( param . type ) )

if named == nil or ( named ) . family ~= "species" then
local t = context . llvmType ( ctx , tostring ( param . type ) )
paramTypes [ # paramTypes + 1 ] = t
params [ # params + 1 ] = t .. " %h_" .. tostring ( param . uniqueName )
end
end
local result = expressions . helperResult ( ctx , helper . resultTypes )
ctx . helpers [ helper . name ] = name
if unit . defined [ name ] then

elseif helper . native == true then
unit . defined [ name ] = true
builder . declare ( module , name , ("declare %s %s(%s)") : format ( result , name , table . concat ( paramTypes , ", " ) ) )
else
unit . defined [ name ] = true
local attrs = builder . attributes ( module , "alwaysinline " .. functionAttributes ( unit . target , program ) )
local f = builder . func (
module ,
("define internal %s %s(%s) %s {") : format ( result , name , table . concat ( params , ", " ) , attrs )
)
local inner = context . new ( module , f , program , unit . facts )
inner . helpers = ctx . helpers
inner . triple = ctx . triple
for _ , param in ipairs ( helper . params ) do
inner . helperParams [ tostring ( param . uniqueName ) ] = "%h_" .. tostring ( param . uniqueName )
end
local returned = "undef"
for position , resultType in ipairs ( helper . resultTypes ) do
local value , t = expressions . value ( inner , helper . values [ position ] )
local converted = expressions . convert ( inner , value , t , tostring ( resultType ) )
returned = # helper . resultTypes == 1 and converted
or builder . value (
f ,
("insertvalue %s %s, %s %s, %d")

: format (
result ,
returned ,
context . llvmType ( inner , tostring ( resultType ) ) ,
converted ,
position - 1
)
)
end
builder . finish ( f , ("ret %s %s") : format ( result , returned ) )
end
end
end





local function layoutReporters ( unit , program , layout ) 
local module = unit . module
local symbol = physical ( program . symbol , unit . tier )
local attrs = builder . attributes ( module , functionAttributes ( unit . target , program ) )
local size = unit . target . sizeType
local ctx = context . new ( module , builder . func ( module , "" ) , program , unit . facts )
ctx . triple = unit . target . public
local structType = expressions . layoutType ( ctx , layout . name )
local model = expressions . layoutModel ( ctx , layout . name )

local function reporter ( name , address ) 
local f = builder . func ( module , ("define %s @%s() %s {") : format ( size , name , attrs ) )
builder . finish ( f , ("ret %s ptrtoint (ptr %s to %s)") : format ( size , address , size ) )
end








local function constant ( name , value ) 
local f = builder . func ( module , ("define %s @%s() %s {") : format ( size , name , attrs ) )
builder . finish ( f , ("ret %s %d") : format ( size , value ) )
end

local prefix = symbol .. "_layout_" .. layout . name
local aligned = scalarIR . holdsStoredVector ( layout )
reporter ( prefix .. "_size" , ("getelementptr (%s, ptr null, i32 1)") : format ( structType ) )
if aligned then
constant ( prefix .. "_align" , model . alignment )
end
for _ , field in ipairs ( layout . fields ) do
reporter (
prefix .. "_offset_" .. field . name ,
("getelementptr (%s, ptr null, i32 0, i32 %d)") : format ( structType , model . index [ field . name ] )
)
reporter (
prefix .. "_size_" .. field . name ,
("getelementptr (%s, ptr null, i32 1)") : format ( model . storage [ field . name ] )
)
if aligned then
constant ( prefix .. "_align_" .. field . name , model . fieldAlignment [ field . name ] )
end
end
end


local function firstLine ( program ) 
local loop = program . loop
if loop ~= nil and loop . source ~= nil then
return ( loop . source ) . line
end
for _ , statement in ipairs ( program . body or { } ) do
local source = ( statement ) . source
if source ~= nil then
return ( source ) . line
end
end

return 1
end






local function entryValueType (
module ,
program ,
typeName ,
scalar
) 
if types . value ( typeName ) ~= nil then
return scalar ( typeName )
end
local layouts = { }
for _ , layout in ipairs ( program . layouts or { } ) do
layouts [ layout . name ] = layout
end
local ok , carrier = pcall ( context . valueTypeIn , module , layouts , program . simdWidth or 16 , typeName )
if not ok then
expressions . unsupported ( "entry value type " .. typeName )
end

return carrier
end

local function prepared ( unit , f , program ) 
local ctx = context . new ( unit . module , f , program , unit . facts )
ctx . triple = unit . target . public
ctx . maskedMemory = unit . maskedMemory
ctx . tier = unit . codegenTier
local architecture = unit . target . llvmTriple : match ( "^([^-]+)" )
ctx . vectorRegister = ( architecture == "arm64" or architecture == "aarch64" ) and "w"
or ( architecture == "x86_64" or architecture == "i686" ) and "x"
or ""

return ctx
end






local function luaAttributes ( selected ) 
local parts = { "uwtable" }
if selected . format ~= "coff" then
parts [ # parts + 1 ] = "\"probe-stack\"=\"inline-asm\""
end
if selected . functionAttributes ~= "" then
parts [ # parts + 1 ] = selected . functionAttributes
end

return table . concat ( parts , " " )
end


local function builderEntry ( unit , program ) 
local name = "@" .. physical ( program . symbol , unit . tier ) .. "_lua"
local attrs = builder . attributes ( unit . module , luaAttributes ( unit . target ) )
local scope = nil
if unit . lines ~= nil then
scope = dwarf . subprogram ( unit . module , unit . lines , program . name , firstLine ( program ) )
attrs = attrs .. " !dbg " .. tostring ( scope )
end
local f = builder . func ( unit . module , ("define internal i32 %s(ptr %%L) %s {") : format ( name , attrs ) )


dwarf . at ( f , scope , _G.setmetatable({ line =  firstLine ( program ) ,  column =  1 }, scalarIR.Source) )
local ctx = prepared ( unit , f , program )
ctx . scope = scope
ctx . lua = _G.setmetatable({ state =
"%L" ,  runtime =
"null" ,  size =
unit . target . sizeType ,  eager =
program . builderMode == "eager" ,  handles =
{ } ,  bytes =
{ } ,  blocks =
{ } ,  reusableScratch =
program . reusableScratch }, context.Lua)

helpers ( unit , ctx , program )
luaEntry . body ( ctx , program )

return ( _G.setmetatable({ name =  program . name ,  fn =  name }, luaEntry.Registered) )
end



local function termValue ( ctx , term ) 
local kind = tostring ( term . kind )
if kind == "zero" then
return "0"
elseif kind == "count" then
return ctx . counts [ tostring ( term . name ) ]
end
local value = ctx . uniforms [ tostring ( term . name ) ]
local param = nil
for _ , one in ipairs ( ctx . program . params ) do
if one . name == term . name then
param = one
end
end
if value == nil or param == nil then
return nil
end
local typeName = tostring ( ( param ) . type )
if typeName == "i64" or typeName == "u64" then
return value
elseif typeName == "i32" then
return context . value ( ctx , ("sext i32 %s to i64") : format ( value ) )
elseif typeName == "u32" then
return context . value ( ctx , ("zext i32 %s to i64") : format ( value ) )
end

return nil
end







local function assumeRelations ( ctx , program ) 
for _ , relation in ipairs ( program . relations or { } ) do
local wide = false
for _ , term in ipairs ( { relation . left , relation . right } ) do
if term . factor ~= nil then
wide = true
end
if term . kind == "uniform" then
for _ , param in ipairs ( program . params ) do
if param . name == term . name and ( param . type == "i64" or param . type == "u64" ) then
wide = true
end
end
end
end
local left = not wide and termValue ( ctx , relation . left ) or nil
local right = not wide and termValue ( ctx , relation . right ) or nil
if left ~= nil and right ~= nil then
local shifted = context . value ( ctx , ("add nsw i64 %s, %d") : format ( right , relation . offset ) )
local holds = context . value ( ctx , ("icmp sle i64 %s, %s") : format ( left , shifted ) )
builder . declare ( ctx . module , "@llvm.assume" , "declare void @llvm.assume(i1)" )
context . emit ( ctx , ("call void @llvm.assume(i1 %s)") : format ( holds ) )
end
end
end




local function assumeExtents ( ctx , program ) 
for _ , param in ipairs ( program . params ) do
local span = ctx . spans [ param . name ]
local count = ctx . counts [ param . name ]
if span ~= nil and count ~= nil then
local elementType = tostring ( param . type )
local layout = elementType : match ( "^struct:(.+)$" )
local storage = layout ~= nil and expressions . layoutType ( ctx , layout )
or types . storage ( elementType , param . sourceType )
local width = ("ptrtoint (ptr getelementptr (%s, ptr null, i32 1) to i64)") : format ( storage )
local bytes = context . value ( ctx , ("mul nuw i64 %s, %s") : format ( count , width ) )
local bundles = ("\"dereferenceable\"(ptr %s, i64 %s)") : format ( ( span ) . pointer , bytes )
if layout == nil then
bundles = bundles .. (", \"align\"(ptr %s, i64 %d)")

: format ( ( span ) . pointer , types . storageBytes ( elementType , param . sourceType ) )
end
builder . declare ( ctx . module , "@llvm.assume" , "declare void @llvm.assume(i1)" )
context . emit ( ctx , ("call void @llvm.assume(i1 true) [ %s ]") : format ( bundles ) )
end
end
end


local function kernel ( unit , program , oracle ) 
local module = unit . module
local selected = unit . target
local results = program . resultTypes or { }
if program . workgroup ~= nil then
expressions . unsupported ( "workgroup entries" )
end
local independent = scalarIR . independentCounts ( program )
local roots = countRules . roots ( program )
local aliases = countRules . equal ( program , roots )
local parameters = { }
local narrowCounts = selected . sizeType ~= "i64"
local countSuffix = narrowCounts and ".arg" or ""


local countType = selected . sizeType
if unit . facts . relations and not narrowCounts then
countType = "i64 range(i64 0, 9007199254740993)"
end
for _ , param in ipairs ( program . params ) do
if scalarIR . isSpan ( param ) then
parameters [ # parameters + 1 ] = spanParameter ( unit , program , param )
elseif param . kind == "uniform" then
parameters [
# parameters + 1
] = entryValueType ( module , program , tostring ( param . type ) , types . parameter ) .. " %p_" .. param . name
else
expressions . unsupported ( "scalar parameters of kind " .. param . kind )
end
end
if independent then
for _ , param in ipairs ( program . params ) do
if scalarIR . isSpan ( param ) and ( param . soa == nil or param . soa . ordinal == 1 ) then
parameters [ # parameters + 1 ] = countType .. " %count_" .. param . name .. countSuffix
end
end
else
parameters [ # parameters + 1 ] = countType .. " %count" .. countSuffix
end
local resultStruct = nil
if # results > 1 then
resultStruct = types . resultStruct ( results )
parameters [ # parameters + 1 ] = unit . facts . access and "ptr noalias captures(none) writeonly %ks_result"
or "ptr %ks_result"
end
local result = # results ~= 1 and "void" or entryValueType ( module , program , tostring ( results [ 1 ] ) , types . result )
local symbol = physical ( program . symbol .. ( oracle and "_forced_scalar" or "" ) , unit . tier )



local effects = unit . facts . effects and "nofree nosync " or ""
local inlining = oracle and "noinline optnone " or "noinline "

inlining = inlining .. "\"no-builtin-memcpy\" \"no-builtin-memset\" "
local attrs = builder . attributes ( module , inlining .. effects .. functionAttributes ( selected , program ) )
local scope = nil
if unit . lines ~= nil then
scope = dwarf . subprogram ( module , unit . lines , program . name , firstLine ( program ) )
attrs = attrs .. " !dbg " .. tostring ( scope )
end
local f = builder . func (
module ,
("define %s @%s(%s) %s {") : format ( result , symbol , table . concat ( parameters , ", " ) , attrs )
)


local function count ( name ) 
if narrowCounts then
builder . emit ( f , ("%s = zext %s %s.arg to i64") : format ( name , selected . sizeType , name ) )
end
end

if independent then
for _ , param in ipairs ( program . params ) do
if scalarIR . isSpan ( param ) and ( param . soa == nil or param . soa . ordinal == 1 ) then
count ( "%count_" .. param . name )
end
end
else
count ( "%count" )
end
local ctx = prepared ( unit , f , program )
ctx . scope = scope
ctx . oracle = oracle
if resultStruct ~= nil then
ctx . resultBlock = "%ks_result"
ctx . resultStruct = resultStruct
end
for _ , param in ipairs ( program . params ) do
if scalarIR . isSpan ( param ) then
ctx . spans [ param . name ] = _G.setmetatable({ pointer =  "%p_" .. param . name ,  param =  param }, context.Span)
ctx . counts [ param . name ] = independent
and "%count_" .. ( roots [ param . name ] or aliases [ param . name ] or param . name )
or "%count"
elseif param . kind == "uniform" then
ctx . uniforms [ param . name ] = "%p_" .. param . name


local slot = statements . slot ( ctx , "p_" .. param . name , tostring ( param . type ) )
builder . emit (
f ,
("store %s %%p_%s, ptr %s")

: format ( context . llvmType ( ctx , tostring ( param . type ) ) , param . name , slot . pointer )
)
end
end
helpers ( unit , ctx , program )
if unit . facts . relations then
assumeRelations ( ctx , program )
end
if unit . facts . extents then
assumeExtents ( ctx , program )
end

if program . body ~= nil then
statements . block ( ctx , program . body )
builder . finish ( f , # results == 1 and "unreachable" or "ret void" )
return
end


local loopShape = program . loop
dwarf . at ( f , scope , loopShape . source )
local first = "0"
local last = "%count"
local guard = program . rangeGuard
if guard ~= nil then
local from = builder . value ( f , ("fsub double %%p_%s, 1.0") : format ( ( guard ) . first ) )
first = expressions . convert ( ctx , from , "f64" , "u64" )
last = expressions . convert ( ctx , "%p_" .. ( guard ) . last , "f64" , "u64" )
elseif independent then
last = independent and "%count_" .. ( roots [ loopShape . count ] or aliases [ loopShape . count ] or loopShape . count )
or "%count"
end
local index = builder . alloca ( f , "i64" , 8 )
builder . emit ( f , ("store i64 %s, ptr %s") : format ( first , index ) )
local head = builder . label ( f , "map.head" )
local body = builder . label ( f , "map.body" )
local latch = builder . label ( f , "map.next" )
local exit = builder . label ( f , "map.end" )
builder . start ( f , head )
local current = builder . value ( f , ("load i64, ptr %s") : format ( index ) )
local more = builder . value ( f , ("icmp ult i64 %s, %s") : format ( current , last ) )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( more , body , exit ) )
builder . start ( f , body )
ctx . mapIndex = current
ctx . loops [ # ctx . loops + 1 ] = _G.setmetatable({ breakLabel =  exit ,  continueLabel =  latch }, context.Loop)
statements . block ( ctx , loopShape . statements )
ctx . loops [ # ctx . loops ] = nil
ctx . mapIndex = nil
builder . start ( f , latch )
local stepped = builder . value ( f , ("add nuw i64 %s, 1") : format ( current ) )
builder . emit ( f , ("store i64 %s, ptr %s") : format ( stepped , index ) )
builder . jump ( f , head )
builder . start ( f , exit )
builder . finish ( f , "ret void" )
end



const WASM_LIBM

= {
sin = true ,
cos = true ,
tan = true ,
asin = true ,
acos = true ,
atan = true ,
atan2 = true ,
sinh = true ,
cosh = true ,
tanh = true ,
exp = true ,
log = true ,
log2 = true ,
pow = true ,
fmod = true ,
expf = true ,
fma = true ,
fmaf = true ,
}


local function wasmUnresolved ( module ) 
local needs = { }
for _ , key in ipairs ( module . order ) do
local name = ( module . pieces [ key ] ) : match ( "^declare [^@]*@([%w_.]+)" )
if name ~= nil and name : match ( "^llvm%." ) == nil and not WASM_LIBM [ name ] then
needs [ # needs + 1 ] = name
end
end

return needs
end








function llvmProgram . module (
programs ,
tier ,
selected ,
stated ,
sourceFile ,
logical ,
bridges ,
oracleBridges
) 
local module = builder . module ( )
local unit = _G.setmetatable({ module =
module ,  tier =
logical ~= true and tier or nil ,  maskedMemory =
tier == "avx2" or tier == "avx512f" ,  codegenTier =
tier ,  target =
selected ,  facts =
stated or facts . all ( ) ,  lines =
sourceFile ~= nil and dwarf . unit ( module , sourceFile , selected . format == "macho" and 4 or 5 )
or nil ,  defined =
{ } }, llvmProgram.Unit)

local kernels = { }
local registered = { }
local registrar = nil
local registrarProgram = nil
for _ , program in ipairs ( programs ) do
if program . executionTarget == "gpu" then

elseif program . entryMode == "lua-builder" and selected . format == "wasm" then
expressions . unsupported ( "Lua-builder entries in an independent Wasm module" )
elseif program . entryMode == "lua-builder" then
registrar = registrar or program . registrar
if registrar ~= program . registrar then
error ( "one translation unit carried multiple Lua registrars" , 0 )
end
registrarProgram = registrarProgram or program
registered [ # registered + 1 ] = builderEntry ( unit , program )
else


if program . usesSimd == true then
kernel ( unit , program , true )
kernels [ # module . functions ] = true
end
kernel ( unit , program , false )
kernels [ # module . functions ] = true


for _ , layout in ipairs ( program . layouts or { } ) do
if layout . nativeOnly ~= true then
layoutReporters ( unit , program , layout )
end
end
end
end

if selected . format == "wasm" then
local attrs = builder . attributes ( module , "nounwind" )
for _ , program in ipairs ( programs ) do
if program . executionTarget ~= "gpu" then
local index = bridges ~= nil and ( bridges ) [ program . symbol ] or nil
if index == nil then
error ( "no Wasm bridge index for " .. program . symbol , 0 )
end

local callee = oracleBridges == true and program . usesSimd == true and program . symbol .. "_forced_scalar"
or program . symbol
wasmBridge . define ( module , program , index , physical ( callee , unit . tier ) , attrs )
end
end
wasmRuntime . install ( module )
local needs = wasmUnresolved ( module )
if # needs > 0 then
expressions . unsupported ( "an independent Wasm module has no " .. table . concat ( needs , ", " ) .. " to link" )
end
end
if registrar ~= nil then
luaEntry . registrar (
module ,
physical ( registrar , unit . tier ) ,
builder . attributes ( module , luaAttributes ( selected ) ) ,
selected . sizeType ,
registered ,
registrarProgram ,
selected . linkedRuntime ~= nil
)
end





local opaque = false
local globals = false
for _ , key in ipairs ( module . order ) do
local piece = module . pieces [ key ]

local name = piece : match ( "^declare [^@]*@([%w_.]+)" )
if name ~= nil and name : match ( "^llvm%." ) == nil and name : match ( "^luaL?_" ) == nil then
opaque = true
elseif piece : match ( "^@" ) ~= nil then
globals = true
end
end
if unit . facts . effects and not opaque then
local reach = globals and "memory(read, argmem: readwrite)" or "memory(argmem: readwrite)"
for index in pairs ( kernels ) do
module . functions [ index ] = ( module . functions [ index ] : gsub ( "^(define [^\n]-%)) #" , "%1 " .. reach .. " #" , 1 ) )
end
end

return builder . render ( module )
end


function llvmProgram . isUnsupported ( err ) 
return type ( err ) == "string" and ( err ) : sub ( 1 , # expressions . UNSUPPORTED ) == expressions . UNSUPPORTED
end

local __nuppExportValue= llvmProgram ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.program"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.program"]=__nuppExports;return __nuppExports