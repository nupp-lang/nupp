_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.lua.runtime\0runtime\0001") };

















local builder = require ( "nupp.compiler.aot.llvm.builder" )
local context = require ( "nupp.compiler.aot.llvm.context" )

local runtime = __nuppNew(0,8)


runtime . VERSION = 1



runtime . BUILDER_BYTES = 4096



runtime . STRING_BUFFER_BYTES = 8256



runtime . SCRATCH_U32 = "{ ptr, i32, i32, i32, i32, [32 x i32] }"


runtime . SCRATCH_U8 = "{ ptr, i32, i32, i32, i32 }"



runtime . FRAME = "{ i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }"




runtime . BUILDER = "{ [10 x i32], i32, i32, i32, i32, i32, i32, ptr, [16 x { i32, i32, i32, i32, i32, i32, i32, i32, i64, i32, i32, i32, i32 }] }"


const MESSAGE

= {
stack = 1 ,
stringLength = 2 ,
byte = 3 ,
wordIndex = 4 ,
word = 5 ,
stringByte = 6 ,
scratchRead = 7 ,
scratchWrite = 8 ,
escapeRead = 9 ,
byteRead = 10 ,
byteWrite = 11 ,
byteStraddle = 12 ,
tableEntry = 13 ,
substring = 14 ,
noContainer = 16 ,
}

runtime . MESSAGE = MESSAGE



runtime.Slot = {} runtime.Slot.__index = runtime.Slot ;_G.nupp.__reflect.link(runtime.Slot,__nuppT1[1],{ })





local function slot ( name , result , params ) 
return ( _G.setmetatable({ name =  name ,  result =  result ,  params =  params }, runtime.Slot) )
end


const SLOTS

= {
( _G.setmetatable({ name =  "raise" ,  result =  "void" ,  params =  "ptr, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "raise_count" ,  result =  "void" ,  params =  "ptr, ptr" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "raise_index" ,  result =  "void" ,  params =  "ptr, ptr" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "bytes" ,  result =  "ptr" ,  params =  "ptr, i64, ptr" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "count" ,  result =  "i64" ,  params =  "ptr, double, ptr" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "index" ,  result =  "i64" ,  params =  "ptr, double, ptr" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "string_match" ,  result =  "i64" ,  params =  "ptr, i64, ptr, SIZE" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "string_length" ,  result =  "i64" ,  params =  "ptr, SIZE" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "string_byte" ,  result =  "i64" ,  params =  "ptr, ptr, SIZE, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "string_byte_lua" ,  result =  "double" ,  params =  "ptr, ptr, SIZE, double" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "string_u32" ,  result =  "i64" ,  params =  "ptr, ptr, SIZE, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "substring" ,  result =  "void" ,  params =  "ptr, ptr, SIZE, double, double" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "table_number" ,  result =  "double" ,  params =  "ptr, i64, double, ptr" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "string_buffer_init" ,  result =  "void" ,  params =  "ptr, ptr" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "string_buffer_append" ,  result =  "void" ,  params =  "ptr, ptr, ptr, SIZE" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "string_buffer_append_slice" ,  result =  "void" ,  params =  "ptr, ptr, ptr, SIZE, double, double" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "string_buffer_append_top" ,  result =  "void" ,  params =  "ptr, ptr" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "string_buffer_finish" ,  result =  "void" ,  params =  "ptr, ptr" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u32" ,  result =  "void" ,  params =  "ptr, ptr, i64, ptr" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u32_fixed" ,  result =  "void" ,  params =  "ptr, ptr, i64, ptr" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u32_stack" ,  result =  "void" ,  params =  "ptr, ptr, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u32_get" ,  result =  "i64" ,  params =  "ptr, ptr, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u32_get_fixed" ,  result =  "i64" ,  params =  "ptr, ptr, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u32_escape_get" ,  result =  "i64" ,  params =  "ptr, ptr, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u32_set" ,  result =  "void" ,  params =  "ptr, ptr, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u32_set_fixed" ,  result =  "void" ,  params =  "ptr, ptr, i64, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u8" ,  result =  "void" ,  params =  "ptr, ptr, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u8_cached" ,  result =  "void" ,  params =  "ptr, ptr, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u8_stack" ,  result =  "void" ,  params =  "ptr, ptr, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u8_get" ,  result =  "i64" ,  params =  "ptr, ptr, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u8_get_fixed" ,  result =  "i64" ,  params =  "ptr, ptr, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u8_set" ,  result =  "void" ,  params =  "ptr, ptr, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u8_set_fixed" ,  result =  "void" ,  params =  "ptr, ptr, i64, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u8_set4" ,  result =  "void" ,  params =  "ptr, ptr, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u8_set4_fixed" ,  result =  "void" ,  params =  "ptr, ptr, i64, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "scratch_u8_push" ,  result =  "void" ,  params =  "ptr, ptr, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_init" ,  result =  "void" ,  params =  "ptr, ptr, i64, i64, i64, i64, i64, i64, i64, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_open" ,  result =  "void" ,  params =  "ptr, ptr, i64, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_string" ,  result =  "void" ,  params =  "ptr, ptr, ptr, SIZE, i64, i64, i64, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_string_escapes" ,  result =  "void" ,  params =  "ptr, ptr, ptr, SIZE, i64, i64, ptr, i64, i64, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_number_slice" ,  result =  "void" ,  params =  "ptr, ptr, ptr, SIZE, i64, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_integer_slice" ,  result =  "void" ,  params =  "ptr, ptr, ptr, SIZE, i64, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_number" ,  result =  "void" ,  params =  "ptr, ptr, double, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_integer64" ,  result =  "void" ,  params =  "ptr, ptr, i64, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_decimal64" ,  result =  "void" ,  params =  "ptr, ptr, ptr, SIZE, i64, i64, i64, i64, i64, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_boolean" ,  result =  "void" ,  params =  "ptr, ptr, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_null" ,  result =  "void" ,  params =  "ptr, ptr, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_close" ,  result =  "void" ,  params =  "ptr, ptr, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_key_scratch" ,  result =  "void" ,  params =  "ptr, ptr, ptr, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_string_scratch" ,  result =  "void" ,  params =  "ptr, ptr, ptr, i64, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_pushed_scalar" ,  result =  "void" ,  params =  "ptr, ptr, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_key" ,  result =  "void" ,  params =  "ptr, ptr" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_query" ,  result =  "i64" ,  params =  "ptr, ptr, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_number_token" ,  result =  "i64" ,  params =  "ptr, ptr, ptr, SIZE, i64, i64, i64" }, runtime.Slot) ) ,
( _G.setmetatable({ name =  "builder_finish" ,  result =  "void" ,  params =  "ptr, ptr" }, runtime.Slot) ) ,
}

runtime . SLOTS = SLOTS



runtime . HEADER = 11

local indexOf = { }
local slotOf = { }
for position , entry in ipairs ( runtime . SLOTS ) do
indexOf [ entry . name ] = runtime . HEADER + position - 1
slotOf [ entry . name ] = entry
end



const API

= {
lua_checkstack = { "i32" , "ptr, i32" } ,
lua_gettop = { "i32" , "ptr" } ,
lua_settop = { "void" , "ptr, i32" } ,
lua_replace = { "void" , "ptr, i32" } ,
lua_pushvalue = { "void" , "ptr, i32" } ,
lua_pushnil = { "void" , "ptr" } ,
lua_pushboolean = { "void" , "ptr, i32" } ,
lua_pushnumber = { "void" , "ptr, double" } ,
lua_pushlstring = { "void" , "ptr, ptr, SIZE" } ,
lua_createtable = { "void" , "ptr, i32, i32" } ,
lua_rawseti = { "void" , "ptr, i32, i32" } ,
lua_rawset = { "void" , "ptr, i32" } ,
lua_concat = { "void" , "ptr, i32" } ,
lua_toboolean = { "i32" , "ptr, i32" } ,
lua_type = { "i32" , "ptr, i32" } ,
lua_tolstring = { "ptr" , "ptr, i32, ptr" } ,
lua_getfield = { "void" , "ptr, i32, ptr" } ,
lua_call = { "void" , "ptr, i32, i32" } ,
lua_pushcclosure = { "void" , "ptr, ptr, i32" } ,
luaL_checknumber = { "double" , "ptr, i32" } ,
luaL_checklstring = { "ptr" , "ptr, i32, ptr" } ,
luaL_error = { "i32" , "ptr, ptr, ..." } ,
}


function runtime . apiNames ( ) 
local names = { }
for name in pairs ( API ) do
names [ # names + 1 ] = name
end
table . sort ( names )

return names
end

local function sized ( params , size ) 
return ( params : gsub ( "SIZE" , size ) )
end


function runtime . size ( ctx ) 
return ctx . lua ~= nil and ( ctx . lua ) . size or "i64"
end



function runtime . lua ( ctx ) 
local found = ctx . lua
if found == nil then
error ( "a Lua construction outside a builder entry" , 0 )
end

return found
end




function runtime . api ( ctx , name , args ) 
local signature = API [ name ]
if signature == nil then
error ( "no Lua API declaration for " .. name , 0 )
end
local result = ( signature ) [ 1 ]
local params = sized ( ( signature ) [ 2 ] , runtime . size ( ctx ) )
builder . declare ( ctx . module , "@" .. name , ("declare %s @%s(%s)") : format ( result , name , params ) )
local callee = params : find ( "..." , 1 , true ) ~= nil and ("%s (%s) @%s") : format ( result , params , name )
or result .. " @" .. name
local call = ("call %s(%s)") : format ( callee , table . concat ( args , ", " ) )
if name == "luaL_error" then
call = call .. " nomerge"
end
if result == "void" then
context . emit ( ctx , call )
return nil
end

return context . value ( ctx , call )
end


local function pointer ( ctx , name ) 
local lua = runtime . lua ( ctx )
local address = context . value (
ctx ,
("getelementptr inbounds ptr, ptr %s, i64 %d") : format ( lua . runtime , indexOf [ name ] )
)
local invariant = builder . metadata ( ctx . module , "!{}" )

local f = ctx . f
f . serial = f . serial + 1
local loaded = ("%%rt.%s.%d") : format ( name , f . serial )
builder . emit ( f , ("%s = load ptr, ptr %s, !invariant.load %s") : format ( loaded , address , invariant ) )

return loaded
end



function runtime . call ( ctx , name , args ) 
local entry = slotOf [ name ]
if entry == nil then
error ( "no AOT runtime slot " .. name , 0 )
end
local found = entry
local callee = pointer ( ctx , name )
local call = ("call %s %s(%s)") : format ( found . result , callee , table . concat ( args , ", " ) )
if name : match ( "^raise" ) ~= nil then



call = call .. " nomerge"
end
if found . result == "void" then
context . emit ( ctx , call )
return nil
end

return context . value ( ctx , call )
end


function runtime . state ( ctx ) 
return "ptr " .. runtime . lua ( ctx ) . state
end



function runtime . guard ( ctx , failed , raising ) 
local f = ctx . f
local cold = builder . label ( f , "lua.raise" )
local fine = builder . label ( f , "lua.ok" )
local weights = builder . metadata ( ctx . module , "!{!\"branch_weights\", i32 1, i32 1048575}" )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s, !prof %s") : format ( failed , cold , fine , weights ) )
builder . start ( f , cold )
raising ( )
builder . terminate ( f , "unreachable" )
builder . start ( f , fine )
end


function runtime . check ( ctx , failed , message ) 
runtime . guard ( ctx , failed , function ( ) 
runtime . call ( ctx , "raise" , { runtime . state ( ctx ) , "i64 " .. tostring ( runtime . MESSAGE [ message ] ) } )
end )
end


function runtime . cString ( ctx , value ) 
return builder . bytes ( ctx . module , value .. "\0" )
end


function runtime . reserve ( ctx , extra ) 
local ok = runtime . api ( ctx , "lua_checkstack" , { runtime . state ( ctx ) , "i32 " .. tostring ( extra ) } )
runtime . check ( ctx , context . value ( ctx , ("icmp eq i32 %s, 0") : format ( ok ) ) , "stack" )
end

local __nuppExportValue= runtime ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.lua.runtime"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.lua.runtime"]=__nuppExports;return __nuppExports