_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()
















local builder = require ( "nupp.compiler.aot.llvm.builder" )
local context = require ( "nupp.compiler.aot.llvm.context" )
local expressions = require ( "nupp.compiler.aot.llvm.expressions" )
local runtime = require ( "nupp.compiler.aot.llvm.lua.runtime" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )

local values = { }


function values . operand ( ctx , node , to ) 
local value , t = expressions . value ( ctx , node )

return expressions . convert ( ctx , value , t , to )
end


function values . wide ( ctx , node ) 
return "i64 " .. context . value ( ctx , ("zext i32 %s to i64") : format ( values . operand ( ctx , node , "u32" ) ) )
end


function values . flag ( ctx , node ) 
return "i64 " .. context . value ( ctx , ("zext i1 %s to i64") : format ( values . operand ( ctx , node , "bool" ) ) )
end


function values . site ( source ) 
return source ~= nil
and tostring ( ( source ) . line ) .. ":" .. tostring ( ( source ) . column )
or "1:1"
end



function values . handle ( ctx , node ) 
local uniqueName = tostring ( ( node ) . uniqueName )
local found = runtime . lua ( ctx ) . handles [ uniqueName ]
if found ~= nil then
return found
end
if uniqueName : match ( "^%d+$" ) ~= nil then
return uniqueName
end
error ( "no Lua stack slot for " .. uniqueName , 0 )
end



function values . bytes ( ctx , node ) 
local uniqueName = tostring ( ( node ) . uniqueName )
local found = runtime . lua ( ctx ) . bytes [ uniqueName ]
if found == nil then
error ( "no rooted bytes for " .. uniqueName , 0 )
end

return found
end


function values . byteOperands ( ctx , node ) 
local bytes = values . bytes ( ctx , node )

return ("ptr %s, %s %s") : format ( bytes . pointer , runtime . size ( ctx ) , bytes . length )
end



function values . block ( ctx , node ) 
local uniqueName = tostring ( ( node ) . uniqueName )
local found = runtime . lua ( ctx ) . blocks [ uniqueName ]
if found == nil then
error ( "no native block for " .. uniqueName , 0 )
end

return found
end


function values . field ( ctx , block , structType , index ) 
return context . value ( ctx , ("getelementptr inbounds %s, ptr %s, i32 0, i32 %d") : format ( structType , block , index ) )
end





local function apiInteger ( ctx , value , minimum , raising ) 
local low = context . value ( ctx , ("fcmp oge double %s, %s") : format ( value , minimum ) )
local high = context . value ( ctx , ("fcmp ole double %s, 2147483647.0") : format ( value ) )
local inRange = context . value ( ctx , ("and i1 %s, %s") : format ( low , high ) )

local clamped = context . value ( ctx , ("select i1 %s, double %s, double 0.0") : format ( inRange , value ) )
local integer = context . value ( ctx , ("fptosi double %s to i32") : format ( clamped ) )
local back = context . value ( ctx , ("sitofp i32 %s to double") : format ( integer ) )
local integral = context . value ( ctx , ("fcmp oeq double %s, %s") : format ( back , value ) )
local fine = context . value ( ctx , ("and i1 %s, %s") : format ( inRange , integral ) )
runtime . guard ( ctx , context . value ( ctx , ("xor i1 %s, true") : format ( fine ) ) , raising )

return integer
end


function values . count ( ctx , node , what ) 
local value = values . operand ( ctx , node , "f64" )

return apiInteger ( ctx , value , "0.0" , function ( ) 
runtime . call ( ctx , "raise_count" , { runtime . state ( ctx ) , "ptr " .. runtime . cString ( ctx , what ) } )
end )
end


function values . index ( ctx , node , source ) 
local value = values . operand ( ctx , node , "f64" )

return apiInteger ( ctx , value , "1.0" , function ( ) 
runtime . call ( ctx , "raise_index" , { runtime . state ( ctx ) , "ptr " .. runtime . cString ( ctx , values . site ( source ) ) } )
end )
end


function values . pushLiteral ( ctx , value ) 
runtime . api ( ctx , "lua_pushlstring" , {
runtime . state ( ctx ) ,
"ptr " .. builder . bytes ( ctx . module , value ) ,
runtime . size ( ctx ) .. " " .. tostring ( # value )
} )
end


function values . substringOperands ( ctx , sliced ) 
local bytes = values . bytes ( ctx , sliced . bytes )
local first = values . operand ( ctx , sliced . first , "f64" )
local last = sliced . last ~= nil and values . operand ( ctx , sliced . last , "f64" )
or context . value ( ctx , ("uitofp %s %s to double") : format ( runtime . size ( ctx ) , bytes . length ) )

return ("ptr %s, %s %s, double %s, double %s") : format ( bytes . pointer , runtime . size ( ctx ) , bytes . length , first , last )
end



function values . push ( ctx , value ) 
local state = runtime . state ( ctx )
local valueType = tostring ( value . type )
if valueType == "lua_table" then
if value . op == "lua_new_table" then
local created = value
runtime . reserve ( ctx , 3 )
local site = values . site ( created . source )
local array = values . count ( ctx , created . arrayCapacity , "array capacity at " .. site )
local hash = values . count ( ctx , created . hashCapacity , "hash capacity at " .. site )
runtime . api ( ctx , "lua_createtable" , { state , "i32 " .. array , "i32 " .. hash } )
local fields = created . fields or { }
if # fields == 0 then
return
end
local table = runtime . api ( ctx , "lua_gettop" , { state } )
for _ , field in ipairs ( fields ) do
if field . indexed then
values . push ( ctx , field . value )
local key = values . index ( ctx , field . key , field . source )
runtime . api ( ctx , "lua_rawseti" , { state , "i32 " .. table , "i32 " .. key } )
else
values . push ( ctx , field . key )
values . push ( ctx , field . value )
runtime . api ( ctx , "lua_rawset" , { state , "i32 " .. table } )
end
end
return
end
elseif valueType == "lua_nil" then
runtime . api ( ctx , "lua_pushnil" , { state } )
return
elseif valueType == "lua_string" then
if value . op == "lua_string" then
values . pushLiteral ( ctx , ( value ) . value )
return
elseif value . op == "lua_string_buffer_finish" then
local buffer = values . block ( ctx , ( value ) . buffer )
runtime . call ( ctx , "string_buffer_finish" , { state , "ptr " .. buffer } )
return
elseif value . op == "lua_concat" then
local joined = value
values . push ( ctx , joined . left )
values . push ( ctx , joined . right )
runtime . api ( ctx , "lua_concat" , { state , "i32 2" } )
return
elseif value . op == "lua_substring" then
runtime . call ( ctx , "substring" , { state , values . substringOperands ( ctx , value ) } )
return
end
elseif valueType == "lua_value" then
if value . op == "lua_builder_finish" then
local stream = values . block ( ctx , ( value ) . builder )
runtime . call ( ctx , "builder_finish" , { state , "ptr " .. stream } )
return
end
elseif valueType == "bool" then
local truth = values . operand ( ctx , value , "bool" )
runtime . api ( ctx , "lua_pushboolean" , { state , "i32 " .. context . value ( ctx , ("zext i1 %s to i32") : format ( truth ) ) } )
return
else
runtime . api ( ctx , "lua_pushnumber" , { state , "double " .. values . operand ( ctx , value , "f64" ) } )
return
end

runtime . api ( ctx , "lua_pushvalue" , { state , "i32 " .. values . handle ( ctx , value ) } )
end


local function narrow ( ctx , value ) 
return context . value ( ctx , ("trunc i64 %s to i32") : format ( value ) ) , "u32"
end

local function stringMatch ( ctx , node ) 
local matched = node
local index = context . value ( ctx , ("sext i32 %s to i64") : format ( values . handle ( ctx , matched . bytes ) ) )
local answer = runtime . call ( ctx , "string_match" , {
runtime . state ( ctx ) ,
"i64 " .. index ,
"ptr " .. builder . bytes ( ctx . module , matched . value ) ,
runtime . size ( ctx ) .. " " .. tostring ( # matched . value )
} )

return context . value ( ctx , ("icmp ne i64 %s, 0") : format ( answer ) ) , "bool"
end

local function stringLength ( ctx , node ) 
local bytes = values . bytes ( ctx , ( node ) . bytes )
local size = runtime . size ( ctx )
if size == "i32" then
return bytes . length , "u32"
end
runtime . check ( ctx , context . value ( ctx , ("icmp ugt %s %s, 4294967295") : format ( size , bytes . length ) ) , "stringLength" )

return context . value ( ctx , ("trunc %s %s to i32") : format ( size , bytes . length ) ) , "u32"
end


local function byteAddress ( ctx , bytes , offset ) 
return context . value (
ctx ,
("getelementptr inbounds i8, ptr %s, %s %s") : format ( bytes . pointer , runtime . size ( ctx ) , offset )
)
end


local function sizeOf ( ctx , value ) 
local size = runtime . size ( ctx )
if size == "i32" then
return value
end

return context . value ( ctx , ("zext i32 %s to %s") : format ( value , size ) )
end

local function stringByte ( ctx , node ) 
local loaded = node
local bytes = values . bytes ( ctx , loaded . bytes )
local size = runtime . size ( ctx )
local offset = sizeOf ( ctx , values . operand ( ctx , loaded . index , "u32" ) )
runtime . check ( ctx , context . value ( ctx , ("icmp uge %s %s, %s") : format ( size , offset , bytes . length ) ) , "byte" )
local byte = context . value ( ctx , ("load i8, ptr %s") : format ( ( context . value ( ctx , ("getelementptr inbounds i8, ptr %s, %s %s") : format ( bytes . pointer , runtime . size ( ctx ) , offset ) ) ) ) )

return context . value ( ctx , ("zext i8 %s to i32") : format ( byte ) ) , "u32"
end

local function stringByteAt ( ctx , node ) 
local loaded = node
local bytes = values . bytes ( ctx , loaded . bytes )
local slot = ctx . locals [ tostring ( loaded . cursorUniqueName ) ]
if slot == nil then
error ( "no cursor " .. tostring ( loaded . cursorUniqueName ) , 0 )
end
local cursor = expressions . convert (
ctx ,
context . loadSlot ( ctx , slot ) ,
( slot ) . type ,
"u32"
)
local byte = context . value ( ctx , ("load i8, ptr %s") : format ( byteAddress ( ctx , bytes , sizeOf ( ctx , cursor ) ) ) )

return context . value ( ctx , ("zext i8 %s to i32") : format ( byte ) ) , "u32"
end

local function stringWord ( ctx , node ) 
local loaded = node
local bytes = values . bytes ( ctx , loaded . bytes )
local size = runtime . size ( ctx )
local index = values . operand ( ctx , loaded . index , "u32" )
if size == "i32" then
runtime . check ( ctx , context . value ( ctx , ("icmp ugt i32 %s, 1073741823") : format ( index ) ) , "wordIndex" )
end
local offset = context . value ( ctx , ("shl nuw %s %s, 2") : format ( size , sizeOf ( ctx , index ) ) )
local past = context . value ( ctx , ("icmp ugt %s %s, %s") : format ( size , offset , bytes . length ) )
local left = context . value ( ctx , ("sub %s %s, %s") : format ( size , bytes . length , offset ) )
local short = context . value ( ctx , ("icmp ult %s %s, 4") : format ( size , left ) )
runtime . check ( ctx , context . value ( ctx , ("or i1 %s, %s") : format ( past , short ) ) , "word" )

return context . value ( ctx , ("load i32, ptr %s, align 1") : format ( ( context . value ( ctx , ("getelementptr inbounds i8, ptr %s, %s %s") : format ( bytes . pointer , runtime . size ( ctx ) , offset ) ) ) ) ) , "u32"
end

local function stringByteLua ( ctx , node ) 
local loaded = node
local answer = runtime . call ( ctx , "string_byte_lua" , {
runtime . state ( ctx ) ,
values . byteOperands ( ctx , loaded . bytes ) ,
"double " .. values . operand ( ctx , loaded . index , "f64" )
} )

return answer , "f64"
end

local function tableNumber ( ctx , node ) 
local loaded = node
local table = context . value ( ctx , ("sext i32 %s to i64") : format ( values . handle ( ctx , loaded . table ) ) )
local answer = runtime . call ( ctx , "table_number" , {
runtime . state ( ctx ) ,
"i64 " .. table ,
"double " .. values . operand ( ctx , loaded . key , "f64" ) ,
"ptr " .. runtime . cString ( ctx , values . site ( loaded . source ) )
} )

return answer , "f64"
end





local function builderQuery ( ctx , node ) 
local query = node
local operation = tostring ( query . op )
local stream = values . block ( ctx , query . builder )
local depthAddress = values . field ( ctx , stream , runtime . BUILDER , 1 )
local depth = context . value ( ctx , ("load i32, ptr %s") : format ( depthAddress ) )
if operation == "lua_builder_depth" then
return depth , "u32"
end
local f = ctx . f
local empty = context . value ( ctx , ("icmp eq i32 %s, 0") : format ( depth ) )
local answer = builder . alloca ( f , "i32" , 4 )
if operation == "lua_builder_state" then

builder . emit ( f , ("store i32 0, ptr %s") : format ( answer ) )
local some = builder . label ( f , "lua.frame" )
local done = builder . label ( f , "lua.state" )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( empty , done , some ) )
builder . start ( f , some )
local frame = values . currentFrame ( ctx , stream , depth )
local kind = context . value ( ctx , ("load i32, ptr %s") : format ( values . field ( ctx , frame , runtime . FRAME , 2 ) ) )
local count = context . value ( ctx , ("load i32, ptr %s") : format ( values . field ( ctx , frame , runtime . FRAME , 4 ) ) )
local started = context . value ( ctx , ("icmp ne i32 %s, 0") : format ( count ) )
local flag = context . value ( ctx , ("select i1 %s, i32 256, i32 0") : format ( started ) )
builder . emit (
f ,
("store i32 %s, ptr %s") : format ( context . value ( ctx , ("or i32 %s, %s") : format ( kind , flag ) ) , answer )
)
builder . jump ( f , done )
builder . start ( f , done )

return context . value ( ctx , ("load i32, ptr %s") : format ( answer ) ) , "u32"
end
runtime . check ( ctx , empty , "noContainer" )
local frame = values . currentFrame ( ctx , stream , depth )
local field = operation == "lua_builder_kind" and 2 or 4

return context . value ( ctx , ("load i32, ptr %s") : format ( values . field ( ctx , frame , runtime . FRAME , field ) ) ) , "u32"
end



function values . currentFrame ( ctx , stream , depth ) 
local spilled = context . value ( ctx , ("load ptr, ptr %s") : format ( values . field ( ctx , stream , runtime . BUILDER , 7 ) ) )
local inline = values . field ( ctx , stream , runtime . BUILDER , 8 )
local none = context . value ( ctx , ("icmp eq ptr %s, null") : format ( spilled ) )
local frames = context . value ( ctx , ("select i1 %s, ptr %s, ptr %s") : format ( none , inline , spilled ) )
local last = context . value ( ctx , ("zext i32 %s to i64") : format ( context . value ( ctx , ("sub i32 %s, 1") : format ( depth ) ) ) )

return context . value ( ctx , ("getelementptr inbounds %s, ptr %s, i64 %s") : format ( runtime . FRAME , frames , last ) )
end


function values . eager ( ctx ) 
return runtime . lua ( ctx ) . eager and "i64 1" or "i64 0"
end

local function numberToken ( ctx , node ) 
local number = node

return narrow (
ctx ,
runtime . call ( ctx , "builder_number_token" , {
runtime . state ( ctx ) ,
"ptr " .. values . block ( ctx , number . builder ) ,
values . byteOperands ( ctx , number . sourceBytes ) ,
values . wide ( ctx , number . start ) ,
values . wide ( ctx , number . limit ) ,
values . eager ( ctx )
} )
)
end


local function word ( ctx , block , index ) 
local storage = context . value ( ctx , ("load ptr, ptr %s") : format ( values . field ( ctx , block , runtime . SCRATCH_U32 , 0 ) ) )
local wide = context . value ( ctx , ("zext i32 %s to i64") : format ( index ) )
local address = context . value ( ctx , ("getelementptr inbounds i32, ptr %s, i64 %s") : format ( storage , wide ) )

return context . value ( ctx , ("load i32, ptr %s") : format ( address ) )
end


function values . u32Field ( ctx , block , structType , index ) 
return context . value ( ctx , ("load i32, ptr %s") : format ( values . field ( ctx , block , structType , index ) ) )
end



local function cursorValue ( ctx , uniqueName ) 
local slot = ctx . locals [ uniqueName ]
if slot == nil then
error ( "no cursor " .. uniqueName , 0 )
end

return expressions . convert ( ctx , context . loadSlot ( ctx , slot ) , ( slot ) . type , "u32" )
end

local function scratchWordGet ( ctx , node ) 
local loaded = node
local block = values . block ( ctx , loaded . scratch )
local escape = loaded . op == "lua_scratch_u32_escape_get"
if loaded . cursor ~= nil then
local cursor = cursorValue ( ctx , tostring ( loaded . cursorUniqueName ) )
if escape then
local capacity = values . u32Field ( ctx , block , runtime . SCRATCH_U32 , 1 )
local last = context . value ( ctx , ("sub i32 %s, 1") : format ( capacity ) )
cursor = context . value ( ctx , ("sub i32 %s, %s") : format ( last , cursor ) )
end
return word ( ctx , block , cursor ) , "u32"
end
local index = values . operand ( ctx , loaded . index , "u32" )
local bound = loaded . fixedBound ~= nil and not escape and tostring ( loaded . fixedBound )
or values . u32Field ( ctx , block , runtime . SCRATCH_U32 , escape and 3 or 2 )
runtime . check (
ctx ,
context . value ( ctx , ("icmp uge i32 %s, %s") : format ( index , bound ) ) ,
escape and "escapeRead" or "scratchRead"
)
if escape then
local capacity = values . u32Field ( ctx , block , runtime . SCRATCH_U32 , 1 )
local last = context . value ( ctx , ("sub i32 %s, 1") : format ( capacity ) )
index = context . value ( ctx , ("sub i32 %s, %s") : format ( last , index ) )
end

return word ( ctx , block , index ) , "u32"
end

local function scratchWordLength ( ctx , node ) 
local read = node
local block = values . block ( ctx , read . scratch )
local field = read . op == "lua_scratch_u32_escape_length" and 3 or 2

return values . u32Field ( ctx , block , runtime . SCRATCH_U32 , field ) , "u32"
end


function values . scratchByte ( ctx , block , index ) 
local storage = context . value ( ctx , ("load ptr, ptr %s") : format ( values . field ( ctx , block , runtime . SCRATCH_U8 , 0 ) ) )
local wide = context . value ( ctx , ("zext i32 %s to i64") : format ( index ) )

return context . value ( ctx , ("getelementptr inbounds i8, ptr %s, i64 %s") : format ( storage , wide ) )
end

local function scratchByteGet ( ctx , node ) 
local loaded = node
local block = values . block ( ctx , loaded . scratch )
local index = values . operand ( ctx , loaded . index , "u32" )
local bound = loaded . fixedBound ~= nil and tostring ( loaded . fixedBound )
or values . u32Field ( ctx , block , runtime . SCRATCH_U8 , 2 )
runtime . check ( ctx , context . value ( ctx , ("icmp uge i32 %s, %s") : format ( index , bound ) ) , "byteRead" )
local byte = context . value ( ctx , ("load i8, ptr %s") : format ( values . scratchByte ( ctx , block , index ) ) )

return context . value ( ctx , ("zext i8 %s to i32") : format ( byte ) ) , "u32"
end


values . EXPRESSIONS = {
lua_string_match = stringMatch ,
lua_string_length = stringLength ,
lua_string_byte = stringByte ,
lua_string_byte_at = stringByteAt ,
lua_string_u32 = stringWord ,
lua_string_byte_lua = stringByteLua ,
lua_table_get_index = tableNumber ,
lua_builder_depth = builderQuery ,
lua_builder_kind = builderQuery ,
lua_builder_count = builderQuery ,
lua_builder_state = builderQuery ,
lua_builder_number_token = numberToken ,
lua_scratch_u32_get = scratchWordGet ,
lua_scratch_u32_escape_get = scratchWordGet ,
lua_scratch_u32_length = scratchWordLength ,
lua_scratch_u32_escape_length = scratchWordLength ,
lua_scratch_u8_get = scratchByteGet ,
}

local __nuppExportValue= values ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.lua.values"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.lua.values"]=__nuppExports;return __nuppExports