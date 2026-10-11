_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()
















local builder = require ( "nupp.compiler.aot.llvm.builder" )
local context = require ( "nupp.compiler.aot.llvm.context" )
local dwarf = require ( "nupp.compiler.aot.llvm.dwarf" )
local expressions = require ( "nupp.compiler.aot.llvm.expressions" )
local prelude = require ( "nupp.compiler.aot.llvm.prelude" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )
local visit = require ( "nupp.compiler.aot.visit" )
local types = require ( "nupp.compiler.aot.llvm.types" )

local statements = { }




function statements . slot ( ctx , uniqueName , typeName , carried ) 
local existing = ctx . locals [ uniqueName ]
if existing ~= nil then
return existing
end
local llvmType = context . slotType ( ctx , typeName , carried == true )
local scalar = types . value ( typeName ) ~= nil
local slot = _G.setmetatable({ pointer =
builder . alloca ( ctx . f , llvmType , not scalar and 16 or types . bits ( typeName ) >= 64 and 8 or 4 ) ,  type =
typeName ,  carried =
carried == true }, context.Slot)

ctx . locals [ uniqueName ] = slot

return slot
end


local function assignLocal ( ctx , slot , value , valueType ) 
local converted = expressions . convert ( ctx , value , valueType , slot . type )
context . storeSlot ( ctx , slot , converted )
end


local function condition ( ctx , node ) 
local value , t = expressions . value ( ctx , node )

return expressions . convert ( ctx , value , t , "bool" )
end

local function loop ( ctx , breakLabel , continueLabel , body ) 
ctx . loops [ # ctx . loops + 1 ] = _G.setmetatable({ breakLabel =  breakLabel ,  continueLabel =  continueLabel }, context.Loop)
body ( )
ctx . loops [ # ctx . loops ] = nil
end





local function spanFor ( ctx , statement ) 
local f = ctx . f
local count = context . count ( ctx , statement . boundSpan )
local start = math . floor ( tonumber ( ( statement . from ) . value ) or 1 )
local counter = builder . alloca ( f , "i64" , 8 )
builder . emit ( f , ("store i64 %d, ptr %s") : format ( start , counter ) )
local head = builder . label ( f , "for.head" )
local bodyLabel = builder . label ( f , "for.body" )
local latch = builder . label ( f , "for.next" )
local exit = builder . label ( f , "for.end" )
builder . start ( f , head )
local current = builder . value ( f , ("load i64, ptr %s") : format ( counter ) )
local continues = builder . value ( f , ("icmp ule i64 %s, %s") : format ( current , count ) )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( continues , bodyLabel , exit ) )
builder . start ( f , bodyLabel )
local bindingType = statement . binding . type == "i32" and "i32" or "f64"
local slot = statements . slot ( ctx , statement . binding . uniqueName , bindingType )
assignLocal ( ctx , slot , current , "u64" )
local saved = ctx . spanCounters [ statement . binding . uniqueName ]
if statement . binding . assigned ~= true then
ctx . spanCounters [ statement . binding . uniqueName ] = counter
end
loop ( ctx , exit , latch , function ( ) 
statements . block ( ctx , statement . body )
end )

local counters = ctx . spanCounters
counters [ statement . binding . uniqueName ] = saved
builder . start ( f , latch )
local again = builder . value ( f , ("load i64, ptr %s") : format ( counter ) )
local stepped = builder . value ( f , ("add nuw i64 %s, 1") : format ( again ) )
builder . emit ( f , ("store i64 %s, ptr %s") : format ( stepped , counter ) )
builder . jump ( f , head )
builder . start ( f , exit )
end

local function fornum ( ctx , statement ) 
if statement . boundSpan ~= nil
and statement . from . op == "constant_i32"
and ctx . counts [ statement . boundSpan ] ~= nil
then
spanFor ( ctx , statement )
return
end
local f = ctx . f
local integral = statement . from . type == "i32" and statement . to . type == "i32"
local control = integral and "i64" or "f64"
local from , fromType = expressions . value ( ctx , statement . from )
from = expressions . convert ( ctx , from , fromType , control )
local to , toType = expressions . value ( ctx , statement . to )
to = expressions . convert ( ctx , to , toType , control )
local llvmControl = types . require ( control )
local counter = builder . alloca ( f , llvmControl , 8 )
builder . emit ( f , ("store %s %s, ptr %s") : format ( llvmControl , from , counter ) )
local runtime = ctx . program . numericForRuntime
if runtime == "luajit-dual" and not integral and statement . from . type == "f64" then


local wrap = prelude . use ( ctx . module , "nupp.wrap.u32" )
local wrapped = builder . value ( f , ("call i32 %s(double %s)") : format ( wrap , to ) )
local back = builder . value ( f , ("sitofp i32 %s to double") : format ( wrapped ) )
local lastInt = builder . value ( f , ("fcmp oeq double %s, %s") : format ( to , back ) )
local zero = builder . value ( f , ("fcmp oeq double %s, 0.0") : format ( from ) )
local both = builder . value ( f , ("and i1 %s, %s") : format ( zero , lastInt ) )
local normalized = builder . value ( f , ("select i1 %s, double 0.0, double %s") : format ( both , from ) )
builder . emit ( f , ("store double %s, ptr %s") : format ( normalized , counter ) )
end
local head = builder . label ( f , "for.head" )
local bodyLabel = builder . label ( f , "for.body" )
local latch = builder . label ( f , "for.next" )
local exit = builder . label ( f , "for.end" )
builder . start ( f , head )
local current = builder . value ( f , ("load %s, ptr %s") : format ( llvmControl , counter ) )
local continues = integral and builder . value ( f , ("icmp sle i64 %s, %s") : format ( current , to ) )
or builder . value ( f , ("fcmp ole double %s, %s") : format ( current , to ) )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( continues , bodyLabel , exit ) )
builder . start ( f , bodyLabel )
local bindingType = statement . binding . type == "i32" and "i32" or "f64"
local slot = statements . slot ( ctx , statement . binding . uniqueName , bindingType )
assignLocal ( ctx , slot , current , control )
loop ( ctx , exit , latch , function ( ) 
statements . block ( ctx , statement . body )
end )
builder . start ( f , latch )
local again = builder . value ( f , ("load %s, ptr %s") : format ( llvmControl , counter ) )
local stepped = integral and builder . value ( f , ("add nsw i64 %s, 1") : format ( again ) )
or builder . value ( f , ("fadd double %s, 1.0") : format ( again ) )
builder . emit ( f , ("store %s %s, ptr %s") : format ( llvmControl , stepped , counter ) )
builder . jump ( f , head )
builder . start ( f , exit )
end


local function provedSpans ( statement ) 
local seen = { }
local spans = { }

local function note ( node ) 
if tostring ( node . op ) : match ( "^simd_" ) ~= nil
and node . cursor ~= nil
and node . span ~= nil
and not seen [ node . span ] then
seen [ node . span ] = true
spans [ # spans + 1 ] = node . span
end
end

visit . block (
{ statement } ,
_G.setmetatable({ scalarExpression =
function ( node ) 
note ( node )
end ,  scalarStatement =
function ( node ) 
note ( node )
end }, visit.Visitor)

)
table . sort ( spans )

return spans
end




local function unrollFactor ( ctx , statement ) 
local widest = 0
local plain = true

local function note ( node ) 
local op = tostring ( node . op )
if op == "while" or op == "repeat" or op == "fornum" or op == "break" or op == "continue" then
plain = false
elseif op : match ( "^simd_" ) ~= nil and node . cursor ~= nil then
local typeName = node . type
if op == "simd_store" or op == "simd_field_store" then
typeName = node . args [ 3 ] . type
end
local found = context . species ( ctx , tostring ( typeName ) )
if found ~= nil then
local bytes = math . floor ( ( found ) . lanes * ( found ) . bits / 8 )
widest = math . max ( widest , bytes )
end
end
end

visit . block (
statement . body ,
_G.setmetatable({ scalarExpression =
function ( node ) 
note ( node )
end ,  scalarStatement =
function ( node ) 
note ( node )
end }, visit.Visitor)

)
if not plain or widest == 0 then
return 1
end

return widest <= 16 and 4 or widest <= 32 and 2 or 1
end


local function uncast ( node ) 
while node . op == "numeric_cast" do
node = ( node ) . value
end

return node
end



local function constantOf ( node ) 
node = uncast ( node )
if node . op == "constant_i32" or node . op == "constant_i64" or node . op == "constant" then
return tonumber ( tostring ( ( node ) . value ) )
end

return nil
end



local function sameTree ( a , b ) 
if type ( a ) ~= "table" or type ( b ) ~= "table" then
return a == b
end
for key , value in pairs ( a ) do
if key ~= "source" and not sameTree ( value , ( b ) [ key ] ) then
return false
end
end
for key in pairs ( b ) do
if key ~= "source" and ( a ) [ key ] == nil then
return false
end
end

return true
end



local function withinRoom ( by , width ) 
local step , room = constantOf ( by ) , constantOf ( width )
if step ~= nil and room ~= nil then
return ( step ) >= 0 and ( step ) <= ( room )
end

return sameTree ( uncast ( by ) , uncast ( width ) )
end








local function cursorStep ( ctx , statement , fits ) 
if statement . conditionBody ~= nil then
return nil
end
local cursor = nil
local widths = { }
local pending = { statement . condition }
while # pending > 0 do
local guard = table . remove ( pending )
if guard . op == "and" then
pending [ # pending + 1 ] = ( guard ) . left
pending [ # pending + 1 ] = ( guard ) . right
elseif ( guard . op == "le" or guard . op == "lt" ) and ( guard ) . right . op == "span_count" then
local counted = ( guard ) . right
if not fits [ context . count ( ctx , counted . span ) ] then
return nil
end
local left = ( guard ) . left
if guard . op == "le" then
if left . op ~= "u64_add" then
return nil
end
widths [ # widths + 1 ] = ( left ) . right
left = ( left ) . left
elseif left . op == "u64_add" then


local step = constantOf ( ( left ) . right )
if step == nil then
return nil
end
widths [
# widths + 1
] = _G.setmetatable({ op =  "constant_i32" ,  value =  tostring ( ( step ) + 1 ) ,  type =  "u32" }, scalarIR.IntConstant)
left = ( left ) . left
else
widths [ # widths + 1 ] = _G.setmetatable({ op =  "constant_i32" ,  value =  "1" ,  type =  "u32" }, scalarIR.IntConstant)
end
left = uncast ( left )
if left . op ~= "local" or left . type ~= "u32" then
return nil
end
local named = ( left ) . uniqueName
if cursor ~= nil and named ~= cursor then
return nil
end
cursor = named
else
return nil
end
end
if cursor == nil then
return nil
end
local writes = 0
visit . block (
statement . body ,
_G.setmetatable({ scalarStatement =  function ( node ) 
if node . op == "assign" then
for _ , target in ipairs ( ( node ) . values ) do
if target . target . uniqueName == cursor then
writes = writes + 1
end
end
end
end }, visit.Visitor)
)
if writes ~= 1 then
return nil
end
for _ , child in ipairs ( statement . body ) do
if child . op == "assign" and # ( child ) . values == 1 then
local only = ( child ) . values [ 1 ]
local step = only . value
if only . target . uniqueName == cursor
and step . op == "u32_add"
and ( step ) . left . op == "local"
and ( ( step ) . left ) . uniqueName == cursor
then
for _ , width in ipairs ( widths ) do
if not withinRoom ( ( step ) . right , width ) then
return nil
end
end
return step
end
end
end

return nil
end

local whileLoop




local function versionedLoop ( ctx , statement , spans ) 
local f = ctx . f
local fits = "true"
local counts = { }
for _ , span in ipairs ( spans ) do
counts [ context . count ( ctx , span ) ] = true
local small = builder . value ( f , ("icmp ule i64 %s, 4294967295") : format ( context . count ( ctx , span ) ) )
fits = fits == "true" and small or builder . value ( f , ("and i1 %s, %s") : format ( fits , small ) )
end
local wide = builder . label ( f , "cursors.wide" )
local narrow = builder . label ( f , "cursors.narrow" )
local done = builder . label ( f , "cursors.done" )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( fits , wide , narrow ) )
builder . start ( f , wide )
ctx . wideCursors = true


local step = cursorStep ( ctx , statement , counts )
if step ~= nil then
ctx . noWrap [ step ] = true
end
whileLoop ( ctx , statement )
if step ~= nil then
ctx . noWrap [ step ] = nil
end
ctx . wideCursors = false
builder . jump ( f , done )
builder . start ( f , narrow )
whileLoop ( ctx , statement , true )
builder . start ( f , done )
end

whileLoop = function ( ctx , statement , checked ) 
if not ctx . wideCursors and not ctx . oracle and checked ~= true then
local spans = provedSpans ( statement )
if # spans > 0 then
versionedLoop ( ctx , statement , spans )
return
end
end
local f = ctx . f
local head = builder . label ( f , "while.head" )
local bodyLabel = builder . label ( f , "while.body" )
local exit = builder . label ( f , "while.end" )
builder . start ( f , head )


if statement . conditionBody ~= nil then
statements . block ( ctx , statement . conditionBody )
end
local test = condition ( ctx , statement . condition )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( test , bodyLabel , exit ) )
builder . start ( f , bodyLabel )
loop ( ctx , exit , head , function ( ) 
statements . block ( ctx , statement . body )
end )
local unroll = ctx . wideCursors and unrollFactor ( ctx , statement ) or 1
if unroll > 1 and not f . terminated then
local metadata = builder . loopMetadata ( ctx . module , { ("!{!\"llvm.loop.unroll.count\", i32 %d}") : format ( unroll ) } )
builder . terminate ( f , ("br label %%%s, !llvm.loop %s") : format ( head , metadata ) )
else
builder . jump ( f , head )
end
builder . start ( f , exit )
end

local function repeatLoop ( ctx , statement ) 
local f = ctx . f
local bodyLabel = builder . label ( f , "repeat.body" )
local test = builder . label ( f , "repeat.test" )
local exit = builder . label ( f , "repeat.end" )
builder . start ( f , bodyLabel )
loop ( ctx , exit , test , function ( ) 
statements . block ( ctx , statement . body )
end )
builder . start ( f , test )

if statement . conditionBody ~= nil then
statements . block ( ctx , statement . conditionBody )
end
local done = condition ( ctx , statement . condition )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( done , exit , bodyLabel ) )
builder . start ( f , exit )
end

local function ifStatement ( ctx , statement ) 
local f = ctx . f
local done = builder . label ( f , "if.end" )
for _ , clause in ipairs ( statement . clauses ) do
local test = condition ( ctx , clause . condition )
local thenLabel = builder . label ( f , "if.then" )
local elseLabel = builder . label ( f , "if.else" )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( test , thenLabel , elseLabel ) )
builder . start ( f , thenLabel )
statements . block ( ctx , clause . body )
builder . jump ( f , done )
builder . start ( f , elseLabel )
end
if statement . elseBody ~= nil then
statements . block ( ctx , statement . elseBody )
end
builder . start ( f , done )
end



local function spanStore ( ctx , statement ) 
local span = ctx . spans [ statement . span ]
if span == nil then
error ( "no span " .. statement . span , 0 )
end
local param = span . param
local value , t = expressions . value ( ctx , statement . value )
local elementType = tostring ( param . type )
if elementType : match ( "^struct:" ) ~= nil then
expressions . unsupported ( "whole-struct span stores" )
end
local storage = types . storage ( elementType , param . sourceType )
local converted = expressions . convert ( ctx , value , t , elementType )
local stored = expressions . narrow ( ctx , converted , elementType , storage )
local index = expressions . index ( ctx , statement . indexUniqueName , statement . cursorUniqueName , statement . cursorOffset )
local address = expressions . element ( ctx , statement . span , index , storage )
context . emit (
ctx ,
("store %s %s, ptr %s, align %d")

: format ( storage , stored , address , types . storageBytes ( elementType , param . sourceType ) )
)
end



local function assign ( ctx , statement ) 
local computed = { }
local wide = { }
for position , entry in ipairs ( statement . values ) do
local slot = entry . target . kind == "local" and ctx . locals [ tostring ( entry . target . uniqueName ) ] or nil
local lanes = slot ~= nil
and statements . wideMask ~= nil
and (
statements . wideMask
) ( ctx , entry . value , slot )
or nil
if lanes ~= nil then
computed [ position ] = { lanes , "" }
wide [ position ] = true
else
local value , t = expressions . value ( ctx , entry . value )
computed [ position ] = { value , t }
end
end
for position , entry in ipairs ( statement . values ) do
local value , t = computed [ position ] [ 1 ] , computed [ position ] [ 2 ]
local target = entry . target
if wide [ position ] then
local slot = ctx . locals [ tostring ( target . uniqueName ) ]
context . storeWide ( ctx , slot , value )
elseif target . kind == "local" then
local slot = ctx . locals [ tostring ( target . uniqueName ) ]
if slot == nil then
error ( "assignment to unbound local " .. tostring ( target . uniqueName ) , 0 )
end
assignLocal ( ctx , slot , value , t )
else
local object = expressions . value ( ctx , target . object )
local address , declared , alignment = expressions . fieldAddress (
ctx ,
object ,
tostring ( target . layout ) ,
tostring ( target . field )
)
local fieldType = tostring ( declared . type )
if expressions . vectorField ( declared ) then


if t ~= fieldType then
error ( "a stored vector field takes a vector of its own species" , 0 )
end
context . emit (
ctx ,
("store %s %s, ptr %s, align %d")

: format ( context . llvmType ( ctx , fieldType ) , value , address , alignment )
)
return
end
local storage = types . storage ( fieldType , declared . sourceType )
local stored = expressions . narrow ( ctx , expressions . convert ( ctx , value , t , fieldType ) , fieldType , storage )
context . emit ( ctx , ("store %s %s, ptr %s") : format ( storage , stored , address ) )
end
end
end



local function returnStatement ( ctx , statement ) 
local results = ctx . program . resultTypes or { }
if # results > 1 then

for position , valueNode in ipairs ( statement . values ) do
local value , t = expressions . value ( ctx , valueNode )
local resultType = tostring ( results [ position ] )
local converted = expressions . convert ( ctx , value , t , resultType )
local field = types . field ( resultType )
if field ~= types . require ( resultType ) then
converted = context . value ( ctx , ("zext i1 %s to i8") : format ( converted ) )
end
local address = context . value (
ctx ,
(
"getelementptr " .. expressions . inbounds ( ctx ) .. "%s, ptr %s, i32 0, i32 %d"
) : format ( tostring ( ctx . resultStruct ) , tostring ( ctx . resultBlock ) , position - 1 )
)
context . emit ( ctx , ("store %s %s, ptr %s") : format ( field , converted , address ) )
end
builder . terminate ( ctx . f , "ret void" )
return
end
if # statement . values == 0 or # results == 0 then
builder . terminate ( ctx . f , "ret void" )
return
end
local value , t = expressions . value ( ctx , statement . values [ 1 ] )
local resultType = tostring ( results [ 1 ] )
local converted = expressions . convert ( ctx , value , t , resultType )
builder . terminate ( ctx . f , ("ret %s %s") : format ( context . llvmType ( ctx , resultType ) , converted ) )
end





statements . handlers = { }



statements . binders = { }




statements . wideMask = nil




statements . builderHandlers = { }

function statements . statement ( ctx , node ) 
dwarf . at ( ctx . f , ctx . scope , ( node ) . source )
local operation = node . op
if ctx . lua ~= nil then
local special = statements . builderHandlers [ operation ]
if special ~= nil and special ( ctx , node ) then
return
end
end
local handler = statements . handlers [ operation ]
if handler ~= nil then
handler ( ctx , node )
return
end
if operation == "let" then
local statement = node
local named = context . species ( ctx , tostring ( statement . type ) )
if named ~= nil and ( named ) . family == "species" then

return
end
if statement . value . op == "simd_tail" and statement . assigned ~= true and not ctx . oracle then


local found = context . species ( ctx , tostring ( statement . type ) )
local count , countType = expressions . value ( ctx , ( statement . value ) . args [ 1 ] )
local lanes = expressions . convert ( ctx , count , countType , "u32" )
local indices = { }
for index = 0 , found . lanes - 1 do
indices [ # indices + 1 ] = "i32 " .. tostring ( index )
end
local splatOne = context . value (
ctx ,
("insertelement <%d x i32> poison, i32 %s, i64 0") : format ( found . lanes , lanes )
)
local bound = context . value (
ctx ,
("shufflevector <%d x i32> %s, <%d x i32> poison, <%d x i32> zeroinitializer")

: format ( found . lanes , splatOne , found . lanes , found . lanes )
)
local mask = context . value (
ctx ,
("icmp ult <%d x i32> <%s>, %s") : format ( found . lanes , table . concat ( indices , ", " ) , bound )
)
local slot = statements . slot ( ctx , statement . uniqueName , tostring ( statement . type ) )
context . storeSlot ( ctx , slot , mask )
ctx . tailCounts [ statement . uniqueName ] = lanes
return
end
local binder = statements . binders [ statement . value . op ]
if binder ~= nil then
binder ( ctx , statements . slot ( ctx , statement . uniqueName , tostring ( statement . type ) ) , statement . value )
return
end
local value , t = expressions . value ( ctx , statement . value )

local slot = statements . slot (
ctx ,
statement . uniqueName ,
t == "ptr" and "ptr" or tostring ( statement . type ) ,
statement . assigned == true
)
assignLocal ( ctx , slot , value , t )
elseif operation == "assign" then
assign ( ctx , node )
elseif operation == "store" then
spanStore ( ctx , node )
elseif operation == "if" then
ifStatement ( ctx , node )
elseif operation == "while" then
whileLoop ( ctx , node )
elseif operation == "repeat" then
repeatLoop ( ctx , node )
elseif operation == "fornum" then
fornum ( ctx , node )
elseif operation == "block" then
statements . block ( ctx , ( node ) . body )
elseif operation == "break" then
builder . jump ( ctx . f , context . loop ( ctx ) . breakLabel )
elseif operation == "continue" then
builder . jump ( ctx . f , context . loop ( ctx ) . continueLabel )
elseif operation == "return" then
returnStatement ( ctx , node )
elseif operation == "multi_let" then
local statement = node
local aggregate = expressions . helperCall ( ctx , statement . call )
local resultType = expressions . helperResult ( ctx , statement . call . resultTypes )
for position , bound in ipairs ( statement . bindings ) do
local value = context . value ( ctx , ("extractvalue %s %s, %d") : format ( resultType , aggregate , position - 1 ) )
assignLocal (
ctx ,
statements . slot ( ctx , bound . uniqueName , bound . type , bound . assigned == true ) ,
value ,
bound . type
)
end
else
expressions . unsupported ( "statement " .. tostring ( operation ) )
end
end

function statements . block ( ctx , body ) 
for _ , statement in ipairs ( body ) do
statements . statement ( ctx , statement )
end
end

local __nuppExportValue= statements ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.statements"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.statements"]=__nuppExports;return __nuppExports