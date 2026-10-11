_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()













local builder = require ( "nupp.compiler.aot.llvm.builder" )
local context = require ( "nupp.compiler.aot.llvm.context" )
local runtime = require ( "nupp.compiler.aot.llvm.lua.runtime" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )
local values = require ( "nupp.compiler.aot.llvm.lua.values" )

local luaStatements = { }


const STACK_SCRATCH_WORDS = 1024


const STACK_SCRATCH_BYTES = 4096


local function block ( ctx , uniqueName , type , align ) 
local lua = runtime . lua ( ctx )
local existing = lua . blocks [ uniqueName ]
if existing ~= nil then
return existing
end
local pointer = builder . alloca ( ctx . f , type , align )
lua . blocks [ uniqueName ] = pointer

return pointer
end


local function zero ( ctx , pointer , bytes , align ) 
builder . declare ( ctx . module , "@llvm.memset.p0.i64" , "declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)" )
context . emit (
ctx ,
("call void @llvm.memset.p0.i64(ptr align %d %s, i8 0, i64 %d, i1 false)") : format ( align or 16 , pointer , bytes )
)
end


local function header ( ctx , scratch , structType , fields ) 
for position , value in ipairs ( fields ) do
context . emit ( ctx , ("store i32 %s, ptr %s") : format ( value , values . field ( ctx , scratch , structType , position ) ) )
end
end


local function siteKey ( ctx , uniqueName ) 
local name = ("@ks.key.%s.%s") : format ( ctx . program . symbol , uniqueName )
builder . once ( ctx . module , "key " .. name , name .. " = internal global i8 0" )

return name
end

local function stringBufferAppend ( ctx , buffer , value ) 
local state = runtime . state ( ctx )
if value . op == "lua_string" then
local literal = ( value ) . value
runtime . call ( ctx , "string_buffer_append" , {
state ,
"ptr " .. buffer ,
"ptr " .. builder . bytes ( ctx . module , literal ) ,
runtime . size ( ctx ) .. " " .. tostring ( # literal )
} )
return
elseif value . op == "lua_substring" then
runtime . call ( ctx , "string_buffer_append_slice" , {
state ,
"ptr " .. buffer ,
values . substringOperands ( ctx , value )
} )
return
elseif value . op == "local" and runtime . lua ( ctx ) . bytes [ tostring ( ( value ) . uniqueName ) ] ~= nil then
runtime . call ( ctx , "string_buffer_append" , { state , "ptr " .. buffer , values . byteOperands ( ctx , value ) } )
return
end


values . push ( ctx , value )
runtime . call ( ctx , "string_buffer_append_top" , { state , "ptr " .. buffer } )
end


local function indexOrZero ( ctx , node ) 
if node == nil then
return "i64 0"
end

return "i64 " .. context . value ( ctx , ("sext i32 %s to i64") : format ( values . handle ( ctx , node ) ) )
end

local function bindStream ( ctx , statement ) 
local started = statement . value
local stream = block ( ctx , statement . uniqueName , ("[%d x i8]") : format ( runtime . BUILDER_BYTES ) , 16 )
local maxDepth = started . maxDepth ~= nil and values . wide ( ctx , started . maxDepth ) or "i64 1024"
local capacity = started . stringCapacity ~= nil and values . wide ( ctx , started . stringCapacity )
or "i64 0"
runtime . call ( ctx , "builder_init" , {
runtime . state ( ctx ) ,
"ptr " .. stream ,
indexOrZero ( ctx , started . nullValue ) ,
indexOrZero ( ctx , started . arrayMarker ) ,
indexOrZero ( ctx , started . objectMarker ) ,
maxDepth ,
capacity ,
indexOrZero ( ctx , started . selectionShape ) ,
indexOrZero ( ctx , started . arrayShapeMarker ) ,
indexOrZero ( ctx , started . serdeMarkers ) ,
started . mode == "eager" and "i64 1" or "i64 0"
} )
end

local function bindWordScratch ( ctx , statement ) 
local started = statement . value
local scratch = block ( ctx , statement . uniqueName , runtime . SCRATCH_U32 , 8 )
local capacity = values . operand ( ctx , started . capacity , "u32" )
local fixed = started . fixed
if fixed ~= nil and ( fixed ) <= 1024 then

local storage = block ( ctx , statement . uniqueName .. ".storage" , ("[%d x i32]") : format ( fixed ) , 16 )
zero ( ctx , storage , ( fixed ) * 4 )
context . emit ( ctx , ("store ptr %s, ptr %s") : format ( storage , values . field ( ctx , scratch , runtime . SCRATCH_U32 , 0 ) ) )
header ( ctx , scratch , runtime . SCRATCH_U32 , { capacity , capacity , "0" , "0" } )
return
end
runtime . call ( ctx , fixed ~= nil and "scratch_u32_fixed" or "scratch_u32" , {
runtime . state ( ctx ) ,
"ptr " .. scratch ,
"i64 " .. context . value ( ctx , ("zext i32 %s to i64") : format ( capacity ) ) ,
"ptr " .. siteKey ( ctx , statement . uniqueName )
} )
end

local function bindByteScratch ( ctx , statement ) 
local started = statement . value
local scratch = block ( ctx , statement . uniqueName , runtime . SCRATCH_U8 , 8 )
local capacity = values . operand ( ctx , started . capacity , "u32" )
local fixed = started . fixed
if fixed ~= nil and ( fixed ) <= 4096 then
local storage = block ( ctx , statement . uniqueName .. ".storage" , ("[%d x i8]") : format ( fixed ) , 16 )
zero ( ctx , storage , fixed )
context . emit ( ctx , ("store ptr %s, ptr %s") : format ( storage , values . field ( ctx , scratch , runtime . SCRATCH_U8 , 0 ) ) )
header ( ctx , scratch , runtime . SCRATCH_U8 , { capacity , capacity , "0" , "0" } )
return
end
local cached = runtime . lua ( ctx ) . reusableScratch == statement . uniqueName
runtime . call ( ctx , cached and "scratch_u8_cached" or "scratch_u8" , {
runtime . state ( ctx ) ,
"ptr " .. scratch ,
"i64 " .. context . value ( ctx , ("zext i32 %s to i64") : format ( capacity ) )
} )
if fixed ~= nil then



local storage = context . value (
ctx ,
("load ptr, ptr %s") : format ( values . field ( ctx , scratch , runtime . SCRATCH_U8 , 0 ) )
)
zero ( ctx , storage , fixed , 8 )
context . emit ( ctx , ("store i32 %s, ptr %s") : format ( capacity , values . field ( ctx , scratch , runtime . SCRATCH_U8 , 2 ) ) )
end
end

local function letStatement ( ctx , node ) 
local statement = node
local typeName = tostring ( statement . type )
if typeName == "lua_string_buffer" then
local buffer = block ( ctx , statement . uniqueName , ("[%d x i8]") : format ( runtime . STRING_BUFFER_BYTES ) , 16 )
runtime . call ( ctx , "string_buffer_init" , { runtime . state ( ctx ) , "ptr " .. buffer } )
stringBufferAppend ( ctx , buffer , ( statement . value ) . initial )
elseif typeName == "lua_builder" then
bindStream ( ctx , statement )
elseif typeName == "lua_scratch_u32" then
bindWordScratch ( ctx , statement )
elseif typeName == "lua_scratch_u8" then
bindByteScratch ( ctx , statement )
elseif typeName == "lua_table" or typeName == "lua_string" or typeName == "lua_nil" or typeName == "lua_value" then
values . push ( ctx , statement . value )
local handle = runtime . lua ( ctx ) . handles [ statement . uniqueName ]
if handle == nil then
error ( "no root slot for " .. statement . uniqueName , 0 )
end
runtime . api ( ctx , "lua_replace" , { runtime . state ( ctx ) , "i32 " .. tostring ( handle ) } )
else
return false
end

return true
end

local function setStatement ( ctx , node ) 
local write = node
local state = runtime . state ( ctx )
local table = values . handle ( ctx , write . table )
if write . op == "lua_set_index" then
values . push ( ctx , write . value )
local key = values . index ( ctx , write . key , write . source )
runtime . api ( ctx , "lua_rawseti" , { state , "i32 " .. table , "i32 " .. key } )
else
values . push ( ctx , write . key )
values . push ( ctx , write . value )
runtime . api ( ctx , "lua_rawset" , { state , "i32 " .. table } )
end

return true
end

local function appendStatement ( ctx , node ) 
local appended = node
stringBufferAppend ( ctx , values . block ( ctx , appended . buffer ) , appended . value )

return true
end

local function wordSet ( ctx , node ) 
local write = node
local scratch = values . block ( ctx , write . scratch )
local index = values . operand ( ctx , write . index , "u32" )
local value = values . operand ( ctx , write . value , "u32" )
local lengthField = values . field ( ctx , scratch , runtime . SCRATCH_U32 , 2 )
if write . fixedBound ~= nil then
runtime . check (
ctx ,
context . value ( ctx , ("icmp uge i32 %s, %d") : format ( index , write . fixedBound ) ) ,
"scratchWrite"
)
else
local length = context . value ( ctx , ("load i32, ptr %s") : format ( lengthField ) )
local capacity = values . u32Field ( ctx , scratch , runtime . SCRATCH_U32 , 1 )
local past = context . value ( ctx , ("icmp ugt i32 %s, %s") : format ( index , length ) )
local full = context . value ( ctx , ("icmp uge i32 %s, %s") : format ( index , capacity ) )
runtime . check ( ctx , context . value ( ctx , ("or i1 %s, %s") : format ( past , full ) ) , "scratchWrite" )
local grows = context . value ( ctx , ("icmp eq i32 %s, %s") : format ( index , length ) )
local grown = context . value ( ctx , ("add i32 %s, 1") : format ( length ) )
context . emit (
ctx ,
("store i32 %s, ptr %s")

: format ( context . value ( ctx , ("select i1 %s, i32 %s, i32 %s") : format ( grows , grown , length ) ) , lengthField )
)
end
local storage = context . value ( ctx , ("load ptr, ptr %s") : format ( values . field ( ctx , scratch , runtime . SCRATCH_U32 , 0 ) ) )
local wide = context . value ( ctx , ("zext i32 %s to i64") : format ( index ) )
local address = context . value ( ctx , ("getelementptr inbounds i32, ptr %s, i64 %s") : format ( storage , wide ) )
context . emit ( ctx , ("store i32 %s, ptr %s") : format ( value , address ) )

return true
end

local function byteSet ( ctx , node ) 
local write = node
local scratch = values . block ( ctx , write . scratch )
local lengthField = values . field ( ctx , scratch , runtime . SCRATCH_U8 , 2 )
local operation = tostring ( write . op )
if operation == "lua_scratch_u8_reset" then
context . emit ( ctx , ("store i32 0, ptr %s") : format ( lengthField ) )
return true
end
local index = values . operand ( ctx , write . index , "u32" )
local value = values . operand ( ctx , write . value , "u32" )
local four = operation == "lua_scratch_u8_set4"
local width = four and 4 or 1
local bad
local length = nil
if write . fixedBound ~= nil then
local bound = tostring ( write . fixedBound )
if four then
local past = context . value ( ctx , ("icmp ugt i32 %s, %s") : format ( index , bound ) )
local left = context . value ( ctx , ("sub i32 %s, %s") : format ( bound , index ) )
local short = context . value ( ctx , ("icmp ult i32 %s, 4") : format ( left ) )
bad = context . value ( ctx , ("or i1 %s, %s") : format ( past , short ) )
else
bad = context . value ( ctx , ("icmp uge i32 %s, %s") : format ( index , bound ) )
end
else
local current = context . value ( ctx , ("load i32, ptr %s") : format ( lengthField ) )
length = current
local capacity = values . u32Field ( ctx , scratch , runtime . SCRATCH_U8 , 1 )
local past = context . value ( ctx , ("icmp ugt i32 %s, %s") : format ( index , current ) )
if four then
local over = context . value ( ctx , ("icmp ugt i32 %s, %s") : format ( index , capacity ) )
local room = context . value ( ctx , ("sub i32 %s, %s") : format ( capacity , index ) )
local short = context . value ( ctx , ("icmp ult i32 %s, 4") : format ( room ) )
bad = context . value (
ctx ,
("or i1 %s, %s") : format ( context . value ( ctx , ("or i1 %s, %s") : format ( past , over ) ) , short )
)
else
local full = context . value ( ctx , ("icmp uge i32 %s, %s") : format ( index , capacity ) )
bad = context . value ( ctx , ("or i1 %s, %s") : format ( past , full ) )
end
end
if not four then
bad = context . value (
ctx ,
("or i1 %s, %s") : format ( bad , context . value ( ctx , ("icmp ugt i32 %s, 255") : format ( value ) ) )
)
end
runtime . check ( ctx , bad , "byteWrite" )
if length ~= nil then
local current = length
if four then
local inside = context . value ( ctx , ("icmp ult i32 %s, %s") : format ( index , current ) )
local tail = context . value ( ctx , ("sub i32 %s, %s") : format ( current , index ) )
local short = context . value ( ctx , ("icmp ult i32 %s, 4") : format ( tail ) )
runtime . check ( ctx , context . value ( ctx , ("and i1 %s, %s") : format ( inside , short ) ) , "byteStraddle" )
end
local grows = context . value ( ctx , ("icmp eq i32 %s, %s") : format ( index , current ) )
local grown = context . value ( ctx , ("add i32 %s, %d") : format ( current , width ) )
context . emit (
ctx ,
("store i32 %s, ptr %s")

: format ( context . value ( ctx , ("select i1 %s, i32 %s, i32 %s") : format ( grows , grown , current ) ) , lengthField )
)
end
local address = values . scratchByte ( ctx , scratch , index )
if four then
context . emit ( ctx , ("store i32 %s, ptr %s, align 1") : format ( value , address ) )
else
context . emit (
ctx ,
("store i8 %s, ptr %s") : format ( context . value ( ctx , ("trunc i32 %s to i8") : format ( value ) ) , address )
)
end

return true
end


local function range ( ctx , event ) 
return { values . wide ( ctx , event . start ) , values . wide ( ctx , event . length ) }
end

local function streamEvent ( ctx , node ) 
local event = node
local operation = event . op
local args = { runtime . state ( ctx ) , "ptr " .. values . block ( ctx , event . builder ) }

local function add ( more ) 
for _ , arg in ipairs ( more ) do
args [ # args + 1 ] = arg
end
end

local eager = values . eager ( ctx )
local slot
if operation == "lua_builder_open_array" or operation == "lua_builder_open_object" then
slot = "builder_open"
add ( {
operation == "lua_builder_open_array" and "i64 5" or "i64 6" ,
values . wide ( ctx , event . capacity ) ,
eager
} )
elseif operation == "lua_builder_key" or operation == "lua_builder_string" then
slot = "builder_string"
add ( { values . byteOperands ( ctx , event . sourceBytes ) } )
add ( range ( ctx , event ) )
add ( {
values . flag ( ctx , event . escaped ) ,
operation == "lua_builder_key" and "i64 1" or "i64 0" ,
eager
} )
elseif operation == "lua_builder_number_slice" or operation == "lua_builder_integer_slice" then
slot = operation == "lua_builder_integer_slice" and "builder_integer_slice" or "builder_number_slice"
add ( { values . byteOperands ( ctx , event . sourceBytes ) } )
add ( range ( ctx , event ) )
add ( { eager } )
elseif operation == "lua_builder_key_scratch" then
slot = "builder_key_scratch"
add ( { "ptr " .. values . block ( ctx , event . scratch ) } )
add ( range ( ctx , event ) )
elseif operation == "lua_builder_string_scratch" then
slot = "builder_string_scratch"
add ( { "ptr " .. values . block ( ctx , event . scratch ) } )
add ( range ( ctx , event ) )
add ( { eager } )
elseif operation == "lua_builder_key_escapes" or operation == "lua_builder_string_escapes" then
slot = "builder_string_escapes"
add ( { values . byteOperands ( ctx , event . sourceBytes ) } )
add ( range ( ctx , event ) )
add ( {
"ptr " .. values . block ( ctx , event . escapeScratch ) ,
values . wide ( ctx , event . escapeIndex ) ,
values . wide ( ctx , event . escapeCount ) ,
operation == "lua_builder_key_escapes" and "i64 1" or "i64 0" ,
eager
} )
elseif operation == "lua_builder_number" then
slot = "builder_number"
add ( { "double " .. values . operand ( ctx , event . value , "f64" ) , eager } )
elseif operation == "lua_builder_integer64" then
slot = "builder_integer64"
add ( {
"i64 " .. values . operand ( ctx , event . value , "u64" ) ,
values . flag ( ctx , event . negative ) ,
eager
} )
elseif operation == "lua_builder_decimal64" then
slot = "builder_decimal64"
add ( { values . byteOperands ( ctx , event . sourceBytes ) } )
add ( range ( ctx , event ) )
local exponent = values . operand ( ctx , event . exponent , "i32" )
add ( {
"i64 " .. values . operand ( ctx , event . value , "u64" ) ,
"i64 " .. context . value ( ctx , ("sext i32 %s to i64") : format ( exponent ) ) ,
values . flag ( ctx , event . negative ) ,
values . flag ( ctx , event . exact ) ,
eager
} )
elseif operation == "lua_builder_boolean" then
slot = "builder_boolean"
add ( { values . flag ( ctx , event . value ) , eager } )
elseif operation == "lua_builder_null" then
slot = "builder_null"
add ( { eager } )
else
slot = "builder_close"
add ( { eager } )
end
runtime . call ( ctx , slot , args )

return true
end

local function assignStatement ( ctx , node ) 
local assignment = node
local lua = false
for _ , entry in ipairs ( assignment . values ) do
local targetType = tostring ( entry . target . type )
lua = lua or targetType == "lua_string" or targetType == "lua_nil"
end
if not lua then
return false
end
local only = assignment . values [ 1 ]
local onlyType = tostring ( only . target . type )
if # assignment . values ~= 1 or ( onlyType ~= "lua_string" and onlyType ~= "lua_nil" ) then
error ( "mixed or multiple Lua string assignment reached emission" , 0 )
end
values . push ( ctx , only . value )
local handle = runtime . lua ( ctx ) . handles [ tostring ( only . target . uniqueName ) ]
if handle == nil then
error ( "no root slot for " .. tostring ( only . target . uniqueName ) , 0 )
end
runtime . api ( ctx , "lua_replace" , { runtime . state ( ctx ) , "i32 " .. tostring ( handle ) } )

return true
end

local function returnStatement ( ctx , node ) 
local returned = node
for _ , value in ipairs ( returned . values ) do
values . push ( ctx , value )
end
builder . terminate ( ctx . f , ("ret i32 %d") : format ( # returned . values ) )

return true
end


luaStatements . STATEMENTS = {
let = letStatement ,
assign = assignStatement ,
[ "return" ] = returnStatement ,
lua_set_index = setStatement ,
lua_set_key = setStatement ,
lua_string_buffer_append = appendStatement ,
lua_scratch_u32_set = wordSet ,
lua_scratch_u8_set = byteSet ,
lua_scratch_u8_set4 = byteSet ,
lua_scratch_u8_reset = byteSet ,
lua_builder_open_array = streamEvent ,
lua_builder_open_object = streamEvent ,
lua_builder_key = streamEvent ,
lua_builder_string = streamEvent ,
lua_builder_number = streamEvent ,
lua_builder_number_slice = streamEvent ,
lua_builder_integer_slice = streamEvent ,
lua_builder_integer64 = streamEvent ,
lua_builder_decimal64 = streamEvent ,
lua_builder_boolean = streamEvent ,
lua_builder_null = streamEvent ,
lua_builder_close = streamEvent ,
lua_builder_key_scratch = streamEvent ,
lua_builder_string_scratch = streamEvent ,
lua_builder_key_escapes = streamEvent ,
lua_builder_string_escapes = streamEvent ,
}

local __nuppExportValue= luaStatements ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.lua.statements"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.lua.statements"]=__nuppExports;return __nuppExports