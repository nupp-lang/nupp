_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.context\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.context\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.context\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.context\0runtime\0004") , _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.context\0runtime\0005") , _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.context\0runtime\0006") , _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.context\0runtime\0007") };











local builder = require ( "nupp.compiler.aot.llvm.builder" )
local facts = require ( "nupp.compiler.aot.llvm.facts" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )
local species = require ( "nupp.compiler.aot.llvm.simd.species" )
local states = require ( "nupp.compiler.aot.llvm.simd.states" )
local types = require ( "nupp.compiler.aot.llvm.types" )

local context = { }


context.Slot = {} context.Slot.__index = context.Slot ;_G.nupp.__reflect.link(context.Slot,__nuppT1[1],{ })









context.Span = {} context.Span.__index = context.Span ;_G.nupp.__reflect.link(context.Span,__nuppT1[2],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00084","nupp.compiler.aot.scalar") })






context.Accumulator = {} context.Accumulator.__index = context.Accumulator ;_G.nupp.__reflect.link(context.Accumulator,__nuppT1[3],{ })








context.Loop = {} context.Loop.__index = context.Loop ;_G.nupp.__reflect.link(context.Loop,__nuppT1[4],{ })





context.Bytes = {} context.Bytes.__index = context.Bytes ;_G.nupp.__reflect.link(context.Bytes,__nuppT1[5],{ })







context.Lua = {} context.Lua.__index = context.Lua ;_G.nupp.__reflect.link(context.Lua,__nuppT1[6],{ __nuppT1[5] })



























context.Context = {} context.Context.__index = context.Context ;_G.nupp.__reflect.link(context.Context,__nuppT1[7],{ _G.nupp.__reflect.reference("nupp.compiler.aot.llvm.builder\0runtime\0002","nupp.compiler.aot.llvm.builder") , _G.nupp.__reflect.reference("nupp.compiler.aot.llvm.builder\0runtime\0001","nupp.compiler.aot.llvm.builder") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00092","nupp.compiler.aot.scalar") , __nuppT1[1] , __nuppT1[2] , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00079","nupp.compiler.aot.scalar") , __nuppT1[4] , _G.nupp.__reflect.reference("nupp.compiler.aot.llvm.facts\0runtime\0001","nupp.compiler.aot.llvm.facts") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00044","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00043","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00036","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0005","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0002","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00042","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00041","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00034","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00035","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00039","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00040","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00045","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0004","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0003","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00033","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00030","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00063","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00018","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00025","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00027","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00026","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00024","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00010","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00017","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0006","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00019","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00020","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00021","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00064","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00022","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00023","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00065","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0008","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00014","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00015","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00012","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0009","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00011","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00013","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00038","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00028","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00048","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00047","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00052","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00032","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00046","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00029","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00037","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00049","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00031","nupp.compiler.aot.scalar") , __nuppT1[3] , __nuppT1[6] })























































































function context . new (
module ,
f ,
program ,
stated
) 
local layouts = { }
for _ , layout in ipairs ( program . layouts or { } ) do
layouts [ layout . name ] = layout
end

return ( _G.setmetatable({ f =
f ,  module =
module ,  program =
program ,  locals =
{ } ,  uniforms =
{ } ,  spans =
{ } ,  counts =
{ } ,  mapIndex =
nil ,  helpers =
{ } ,  helperParams =
{ } ,  layouts =
layouts ,  loops =
{ } ,  contract =
program . fpContract == true ,  facts =
stated or facts . all ( ) ,  scope =
nil ,  maskedMemory =
false ,  tier =
"" ,  vectorRegister =
"" ,  oracle =
false ,  wideCursors =
false ,  noWrap =
{ } ,  tailCounts =
{ } ,  spanCounters =
{ } ,  accumulators =
{ } ,  lua =
nil ,  triple =
nil ,  layoutModels =
{ } }, context.Context) )

end



function context . value ( ctx , instruction ) 
return builder . value ( ctx . f , instruction )
end


function context . emit ( ctx , instruction ) 
builder . emit ( ctx . f , instruction )
end



function context . count ( ctx , span ) 
local found = ctx . counts [ span ]
if found == nil then
error ( "no count for span " .. span , 0 )
end

return found
end


function context . width ( ctx ) 
return ctx . program . simdWidth or 16
end


function context . species ( ctx , typeName ) 
return species . of ( context . width ( ctx ) , typeName )
end






function context . aggregateTypeIn (
module ,
layouts ,
width ,
layoutName
) 
local layout = layouts [ layoutName ]
if layout == nil or layout . nativeOnly ~= true then
error ( "no native-only aggregate " .. layoutName , 0 )
end
local name = "%aggregate." .. layout . uniqueName
local fields = { }
for position , field in ipairs ( layout . fields ) do
fields [ position ] = context . valueTypeIn ( module , layouts , width , tostring ( field . type ) )
end
builder . once ( module , "type " .. name , name .. " = type { " .. table . concat ( fields , ", " ) .. " }" )

return name
end




function context . valueTypeIn (
module ,
layouts ,
width ,
typeName
) 
local scalar = types . value ( typeName )
if scalar ~= nil then
return scalar
end
local aggregate = scalarIR . aggregateLayout ( typeName )
if aggregate ~= nil then
return context . aggregateTypeIn ( module , layouts , width , aggregate )
end
local found = species . of ( width , typeName )
if found ~= nil then
return species . carrier ( found ) or "i32"
end
error ( "no LLVM type for " .. typeName , 0 )
end





function context . llvmType ( ctx , typeName ) 
local scalar = types . value ( typeName )
if scalar ~= nil then
return scalar
end
local aggregate = scalarIR . aggregateLayout ( typeName )
if aggregate ~= nil then
return context . aggregateTypeIn ( ctx . module , ctx . layouts , context . width ( ctx ) , aggregate )
end
local found = context . species ( ctx , typeName )
if found ~= nil then
return species . carrier ( found ) or "i32"
end
local state = states . type ( typeName )
if state ~= nil then
return state
end
error ( "no LLVM type for " .. typeName , 0 )
end






function context . slotType ( ctx , typeName , carried ) 
local found = context . species ( ctx , typeName )
if carried and found ~= nil and ( found ) . family == "mask" and ctx . tier ~= "avx512f" then
local mask = found
return "<" .. tostring ( mask . lanes ) .. " x i" .. tostring ( mask . bits ) .. ">"
end

return context . llvmType ( ctx , typeName )
end





function context . opaque ( ctx , value , vector ) 
local register = ctx . vectorRegister
if register == "" then
return value
end
local lanes , element = vector : match ( "^<(%d+) x i(%d+)>$" )
if lanes == nil then
return value
end
local count = tonumber ( lanes )
local bits = tonumber ( element )
local perRegister = math . floor ( context . width ( ctx ) * 8 / bits )
if perRegister < 1 or count % perRegister ~= 0 then
return value
end
local chunk = "<" .. tostring ( perRegister ) .. " x i" .. tostring ( bits ) .. ">"
local pieces = { }
for start = 0 , count - perRegister , perRegister do
local picks = { }
for lane = start , start + perRegister - 1 do
picks [ # picks + 1 ] = "i32 " .. tostring ( lane )
end
local piece = count == perRegister and value
or context . value (
ctx ,
("shufflevector %s %s, %s poison, %s <%s>")

: format ( vector , value , vector , "<" .. tostring ( perRegister ) .. " x i32>" , table . concat ( picks , ", " ) )
)
pieces [
# pieces + 1
] = context . value ( ctx , ("call %s asm \"\", \"=%s,0\"(%s %s)") : format ( chunk , register , chunk , piece ) )
end

local width = perRegister
while # pieces > 1 do
local joined = { }
local type = "<" .. tostring ( width ) .. " x i" .. tostring ( bits ) .. ">"
for index = 1 , # pieces , 2 do
local picks = { }
for lane = 0 , 2 * width - 1 do
picks [ # picks + 1 ] = "i32 " .. tostring ( lane )
end
joined [
# joined + 1
] = context . value (
ctx ,
("shufflevector %s %s, %s %s, <%d x i32> <%s>")

: format ( type , pieces [ index ] , type , pieces [ index + 1 ] or "poison" , 2 * width , table . concat ( picks , ", " ) )
)
end
pieces = joined
width = width * 2
end

return pieces [ 1 ]
end


function context . loadSlot ( ctx , slot ) 
local kept = context . slotType ( ctx , slot . type , slot . carried )
local loaded = context . value ( ctx , ("load %s, ptr %s") : format ( kept , slot . pointer ) )
if kept == context . llvmType ( ctx , slot . type ) then
return loaded
end





return context . value ( ctx , ("icmp slt %s %s, zeroinitializer") : format ( kept , loaded ) )
end


function context . storeSlot ( ctx , slot , value ) 
local kept = context . slotType ( ctx , slot . type , slot . carried )
local carried = context . llvmType ( ctx , slot . type )
local stored = value
if kept ~= carried then
stored = context . value ( ctx , ("sext %s %s to %s") : format ( carried , value , kept ) )
stored = context . opaque ( ctx , stored , kept )
end
context . emit ( ctx , ("store %s %s, ptr %s") : format ( kept , stored , slot . pointer ) )
end



function context . storeWide ( ctx , slot , value ) 
local kept = context . slotType ( ctx , slot . type , slot . carried )
local stored = context . opaque ( ctx , value , kept )
context . emit ( ctx , ("store %s %s, ptr %s") : format ( kept , stored , slot . pointer ) )
end



function context . loop ( ctx ) 
local found = ctx . loops [ # ctx . loops ]
if found == nil then
error ( "break or continue outside a loop" , 0 )
end

return found
end

local __nuppExportValue= context ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.context"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.context"]=__nuppExports;return __nuppExports