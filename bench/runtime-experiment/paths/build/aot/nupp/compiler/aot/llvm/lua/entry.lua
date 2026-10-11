_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.lua.entry\0runtime\0001") };

















local builder = require ( "nupp.compiler.aot.llvm.builder" )
local context = require ( "nupp.compiler.aot.llvm.context" )
local runtime = require ( "nupp.compiler.aot.llvm.lua.runtime" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )
local statements = require ( "nupp.compiler.aot.llvm.statements" )
local verify = require ( "nupp.compiler.aot.verify" )
local visit = require ( "nupp.compiler.aot.visit" )

local entry = { }


const GLOBALS = -10002


entry . TABLE = "@ks.rt"


function entry . declareTable ( module ) 
builder . once ( module , "global " .. entry . TABLE , entry . TABLE .. " = internal global ptr null" )
end


local function saturate ( ctx , value , to ) 
local width = ( to == "i64" or to == "u64" ) and "i64" or "i32"
local signed = to == "i32" or to == "i64"
local intrinsic = ("llvm.%s.sat.%s.f64") : format ( signed and "fptosi" or "fptoui" , width )
builder . declare ( ctx . module , "@" .. intrinsic , ("declare %s @%s(double)") : format ( width , intrinsic ) )

return context . value ( ctx , ("call %s @%s(double %s)") : format ( width , intrinsic , value ) )
end


function entry . rootedSpan ( uniqueName ) 
return "ks_bytes_" .. uniqueName
end


local function root (
ctx ,
uniqueName ,
pointer ,
length ,
param
) 
local lua = runtime . lua ( ctx )
lua . bytes [ uniqueName ] = _G.setmetatable({ pointer =  pointer ,  length =  length }, context.Bytes)
local span = _G.setmetatable({ pointer =  pointer ,  param =  param }, context.Span)
local count = lua . size == "i64" and length or context . value ( ctx , ("zext %s %s to i64") : format ( lua . size , length ) )


for _ , name in ipairs ( { entry . rootedSpan ( uniqueName ) , param . name } ) do
ctx . spans [ name ] = span
ctx . counts [ name ] = count
end
end



local function arguments ( ctx , program ) 
local lua = runtime . lua ( ctx )
local state = runtime . state ( ctx )
for position , param in ipairs ( program . params ) do
local index = "i32 " .. tostring ( position )
local typeName = tostring ( param . type )
if param . kind == "uniform" then
local value
if typeName == "bool" then
local truth = runtime . api ( ctx , "lua_toboolean" , { state , index } )
value = context . value ( ctx , ("icmp ne i32 %s, 0") : format ( truth ) )
else
local number = runtime . api ( ctx , "luaL_checknumber" , { state , index } )
if typeName == "f64" then
value = number
elseif typeName == "f32" then
value = context . value ( ctx , ("fptrunc double %s to float") : format ( number ) )
else
value = saturate ( ctx , number , typeName )
end
end
ctx . uniforms [ param . name ] = value
local slot = statements . slot ( ctx , "p_" .. param . name , typeName )
context . emit ( ctx , ("store %s %s, ptr %s") : format ( context . llvmType ( ctx , typeName ) , value , slot . pointer ) )
elseif param . kind == "scalar" and ( typeName == "lua_string" or typeName == "lua_bytes" ) then
local length = builder . alloca ( ctx . f , lua . size , lua . size == "i64" and 8 or 4 )
local pointer
if typeName == "lua_bytes" then


local f = ctx . f
local kept = builder . alloca ( f , "ptr" , 8 )
local kind = runtime . api ( ctx , "lua_type" , { state , index } )
local isString = context . value ( ctx , ("icmp eq i32 %s, 4") : format ( kind ) )
local direct = builder . label ( f , "lua.string" )
local buffer = builder . label ( f , "lua.buffer" )
local joined = builder . label ( f , "lua.bytes" )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( isString , direct , buffer ) )
builder . start ( f , direct )
local bytes = runtime . api ( ctx , "luaL_checklstring" , { state , index , "ptr " .. length } )
builder . emit ( f , ("store ptr %s, ptr %s") : format ( bytes , kept ) )
builder . jump ( f , joined )
builder . start ( f , buffer )
local converted = runtime . call ( ctx , "bytes" , {
state ,
"i64 " .. tostring ( position ) ,
"ptr " .. length
} )
builder . emit ( f , ("store ptr %s, ptr %s") : format ( converted , kept ) )
builder . jump ( f , joined )
builder . start ( f , joined )
pointer = context . value ( ctx , ("load ptr, ptr %s") : format ( kept ) )
else
pointer = runtime . api ( ctx , "luaL_checklstring" , { state , index , "ptr " .. length } )
end
local loaded = context . value ( ctx , ("load %s, ptr %s") : format ( lua . size , length ) )
root ( ctx , tostring ( param . uniqueName or tostring ( position ) ) , pointer , loaded , param )
elseif param . kind == "scalar" and typeName == "lua_value" then

else
error ( "Lua builders currently take scalar parameters" , 0 )
end
end
end



local function roots ( ctx , program ) 
local lua = runtime . lua ( ctx )
local slots = { }
local seen = { }
visit . program (
program ,
_G.setmetatable({ scalarStatement =  function ( statement ) 
if statement . op == "let" then
local typeName = tostring ( statement . type )
if typeName == "lua_string"
or typeName == "lua_nil"
or typeName == "lua_table"
or typeName == "lua_value"
then
local name = ( statement ) . uniqueName
if not seen [ name ] then
seen [ name ] = true
slots [ # slots + 1 ] = name
end
end
end
end }, visit.Visitor)
)
if # slots == 0 then
return
end
local state = runtime . state ( ctx )
local base = runtime . api ( ctx , "lua_gettop" , { state } )
runtime . api ( ctx , "lua_settop" , { state , "i32 " .. context . value ( ctx , ("add i32 %s, %d") : format ( base , # slots ) ) } )
for position , name in ipairs ( slots ) do
lua . handles [ name ] = context . value ( ctx , ("add i32 %s, %d") : format ( base , position ) )
end
end


local function constants ( ctx , program ) 
for _ , constant in ipairs ( program . constants or { } ) do


local global = builder . bytes ( ctx . module , constant . value .. "\0" , 4 )
local param = _G.setmetatable({ kind =  "scalar" ,  name =  constant . uniqueName ,  type =  "lua_string" }, scalarIR.Param)
root ( ctx , constant . uniqueName , global , tostring ( # constant . value ) , param )
end
end



function entry . body ( ctx , program ) 
local lua = runtime . lua ( ctx )
entry . declareTable ( ctx . module )
lua . runtime = context . value ( ctx , ("load ptr, ptr %s") : format ( entry . TABLE ) )
local byteRoots = 0
for _ , param in ipairs ( program . params ) do
if param . type == "lua_bytes" then
byteRoots = byteRoots + 1
end
end
runtime . reserve ( ctx , verify . builderStack ( program ) + byteRoots + ( byteRoots > 0 and 2 or 0 ) )
arguments ( ctx , program )
constants ( ctx , program )
roots ( ctx , program )
statements . block ( ctx , program . body or { } )
builder . finish ( ctx . f , "ret i32 0" )
end



local function refuse ( ctx , failed , message ) 
runtime . guard ( ctx , failed , function ( ) 
runtime . api ( ctx , "luaL_error" , {
runtime . state ( ctx ) ,
"ptr " .. runtime . cString ( ctx , "%s" ) ,
"ptr " .. runtime . cString ( ctx , message )
} )
end )
end


entry.Registered = {} entry.Registered.__index = entry.Registered ;_G.nupp.__reflect.link(entry.Registered,__nuppT1[1],{ })





function entry . registrar (
module ,
name ,
attrs ,
size ,
registered ,
program ,
linked
) 
entry . declareTable ( module )
local f = builder . func ( module , ("define i32 @%s(ptr %%L) %s {") : format ( name , attrs ) )
local ctx = context . new ( module , f , program )
ctx . lua = _G.setmetatable({ state =
"%L" ,  runtime =
"null" ,  size =
size ,  eager =
false ,  handles =
{ } ,  bytes =
{ } ,  blocks =
{ } ,  reusableScratch =
nil }, context.Lua)

local state = runtime . state ( ctx )
local ok = runtime . api ( ctx , "lua_checkstack" , { state , "i32 4" } )
refuse ( ctx , context . value ( ctx , ("icmp eq i32 %s, 0") : format ( ok ) ) , "AOT builder Lua stack exhausted" )


local table
if linked == true then

builder . once ( module , "global @ks_rt_table" , "@ks_rt_table = external hidden constant [1 x ptr]" )
table = "@ks_rt_table"
else




local given = runtime . api ( ctx , "lua_type" , { state , "i32 1" } )
local isString = context . value ( ctx , ("icmp eq i32 %s, 4") : format ( given ) )
local fromArgument = builder . label ( f , "runtime.argument" )
local fromLookup = builder . label ( f , "runtime.lookup" )
local found = builder . label ( f , "runtime.found" )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( isString , fromArgument , fromLookup ) )
builder . start ( f , fromArgument )
runtime . api ( ctx , "lua_pushnil" , { state } )
runtime . api ( ctx , "lua_pushvalue" , { state , "i32 1" } )
builder . jump ( f , found )
builder . start ( f , fromLookup )
runtime . api ( ctx , "lua_getfield" , {
state ,
"i32 " .. tostring ( -10002 ) ,
"ptr " .. runtime . cString ( ctx , "require" )
} )

runtime . api ( ctx , "lua_pushlstring" , {
state ,
"ptr " .. builder . bytes ( module , "nupp.runtime.native" ) ,
size .. " " .. tostring ( 19 )
} )
runtime . api ( ctx , "lua_call" , { state , "i32 1" , "i32 1" } )
runtime . api ( ctx , "lua_getfield" , { state , "i32 -1" , "ptr " .. runtime . cString ( ctx , "aotRuntime" ) } )
runtime . api ( ctx , "lua_call" , { state , "i32 0" , "i32 1" } )
builder . jump ( f , found )
builder . start ( f , found )
local length = builder . alloca ( f , size , size == "i64" and 8 or 4 )
builder . emit ( f , ("store %s 0, ptr %s") : format ( size , length ) )
local bytes = runtime . api ( ctx , "lua_tolstring" , { state , "i32 -1" , "ptr " .. length } )
local got = context . value ( ctx , ("load %s, ptr %s") : format ( size , length ) )
local width = size == "i64" and 8 or 4
local missing = context . value ( ctx , ("icmp eq ptr %s, null") : format ( bytes ) )
local wrongLength = context . value ( ctx , ("icmp ne %s %s, %d") : format ( size , got , width ) )
refuse ( ctx , context . value ( ctx , ("or i1 %s, %s") : format ( missing , wrongLength ) ) , "AOT runtime is not the one this module was compiled for" )
table = context . value ( ctx , ("load ptr, ptr %s, align 1") : format ( bytes ) )
end

local function word ( index ) 
local address = context . value ( ctx , ("getelementptr inbounds ptr, ptr %s, i64 %d") : format ( table , index ) )
local loaded = context . value ( ctx , ("load ptr, ptr %s") : format ( address ) )

return context . value ( ctx , ("ptrtoint ptr %s to i64") : format ( loaded ) )
end

local function sizeOf ( type ) 
return ("ptrtoint (ptr getelementptr (%s, ptr null, i32 1) to i64)") : format ( type )
end

local function offsetOf ( type , field ) 
return ("ptrtoint (ptr getelementptr (%s, ptr null, i32 0, i32 %d) to i64)") : format ( type , field )
end

local checks = {
context . value ( ctx , ("icmp ne i64 %s, %d") : format ( word ( 0 ) , runtime . VERSION ) ) ,
context . value ( ctx , ("icmp ugt i64 %s, %d") : format ( word ( 1 ) , runtime . BUILDER_BYTES ) ) ,
context . value ( ctx , ("icmp ugt i64 %s, %d") : format ( word ( 2 ) , runtime . STRING_BUFFER_BYTES ) ) ,
context . value ( ctx , ("icmp ne i64 %s, %s") : format ( word ( 3 ) , sizeOf ( runtime . SCRATCH_U32 ) ) ) ,
context . value ( ctx , ("icmp ne i64 %s, %s") : format ( word ( 4 ) , sizeOf ( runtime . SCRATCH_U8 ) ) ) ,
context . value ( ctx , ("icmp ne i64 %s, %s") : format ( word ( 5 ) , offsetOf ( runtime . BUILDER , 1 ) ) ) ,
context . value ( ctx , ("icmp ne i64 %s, %s") : format ( word ( 6 ) , offsetOf ( runtime . BUILDER , 7 ) ) ) ,
context . value ( ctx , ("icmp ne i64 %s, %s") : format ( word ( 7 ) , offsetOf ( runtime . BUILDER , 8 ) ) ) ,
context . value ( ctx , ("icmp ne i64 %s, %s") : format ( word ( 8 ) , sizeOf ( runtime . FRAME ) ) ) ,
context . value ( ctx , ("icmp ne i64 %s, %s") : format ( word ( 9 ) , offsetOf ( runtime . FRAME , 2 ) ) ) ,
context . value ( ctx , ("icmp ne i64 %s, %s") : format ( word ( 10 ) , offsetOf ( runtime . FRAME , 4 ) ) ) ,
}
local wrong = checks [ 1 ]
for position = 2 , # checks do
wrong = context . value ( ctx , ("or i1 %s, %s") : format ( wrong , checks [ position ] ) )
end
refuse ( ctx , wrong , "AOT runtime is not the one this module was compiled for" )
builder . emit ( f , ("store ptr %s, ptr %s") : format ( table , entry . TABLE ) )
if linked ~= true then
runtime . api ( ctx , "lua_settop" , { state , "i32 -3" } )
end

runtime . api ( ctx , "lua_createtable" , { state , "i32 0" , "i32 " .. tostring ( # registered ) } )
for _ , one in ipairs ( registered ) do
runtime . api ( ctx , "lua_pushlstring" , {
state ,
"ptr " .. builder . bytes ( module , one . name ) ,
size .. " " .. tostring ( # one . name )
} )
runtime . api ( ctx , "lua_pushcclosure" , { state , "ptr " .. one . fn , "i32 0" } )
runtime . api ( ctx , "lua_rawset" , { state , "i32 -3" } )
end
builder . finish ( f , "ret i32 1" )
end

local __nuppExportValue= entry ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.lua.entry"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.lua.entry"]=__nuppExports;return __nuppExports