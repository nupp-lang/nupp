_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.loops\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.loops\0runtime\0002") };






local effects = require ( "nupp.compiler.aot.effects" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )

local loops = { }

loops.Report = {} loops.Report.__index = loops.Report ;_G.nupp.__reflect.link(loops.Report,__nuppT1[1],{ })















loops.Counts = {} loops.Counts.__index = loops.Counts ;_G.nupp.__reflect.link(loops.Counts,__nuppT1[2],{ })








local STATEMENTS

= {
let = true ,
multi_let = true ,
assign = true ,
store = true ,
shared_store = true ,
phase = true ,
lua_set_index = true ,
lua_set_key = true ,
lua_string_buffer_append = true ,
lua_scratch_u32_set = true ,
lua_scratch_u8_set = true ,
lua_scratch_u8_set4 = true ,
lua_scratch_u8_reset = true ,
lua_builder_open_array = true ,
lua_builder_open_object = true ,
lua_builder_key = true ,
lua_builder_string = true ,
lua_builder_number = true ,
lua_builder_number_slice = true ,
lua_builder_integer_slice = true ,
lua_builder_integer64 = true ,
lua_builder_decimal64 = true ,
lua_builder_boolean = true ,
lua_builder_null = true ,
lua_builder_close = true ,
simd_store = true ,
lua_builder_key_scratch = true ,
lua_builder_string_scratch = true ,
lua_builder_key_escapes = true ,
lua_builder_string_escapes = true ,
[ "if" ] = true ,
[ "while" ] = true ,
[ "repeat" ] = true ,
fornum = true ,
block = true ,
reducer_region = true ,
[ "break" ] = true ,
[ "continue" ] = true ,
[ "return" ] = true ,
}

local function count ( value , counts ) 
if type ( value ) ~= "table" then
return
end
if value . op ~= nil then
local op = tostring ( value . op )
local facts = STATEMENTS [ op ] and effects . statement ( op ) or effects . expression ( op )
counts . nodes = counts . nodes + 1
if op : match ( "^simd_" ) ~= nil then
counts . simdOperations = counts . simdOperations + 1
end
if facts . usesLua then
counts . luaOperations = counts . luaOperations + 1
end
if facts . readsNative then
counts . nativeReads = counts . nativeReads + 1
end
if facts . writesNative then
counts . nativeWrites = counts . nativeWrites + 1
end
counts . mayRaise = counts . mayRaise or facts . mayRaise
end
for key , child in pairs ( value ) do
if key ~= "source" and key ~= "cursorBounds" then
count ( child , counts )
end
end
end

local function measurements ( value ) 
local answer = _G.setmetatable({ nodes =
0 ,  simdOperations =
0 ,  luaOperations =
0 ,  nativeReads =
0 ,  nativeWrites =
0 ,  mayRaise =
false }, loops.Counts)

count ( value , answer )

return answer
end

local function lastSourceLine ( value , latest ) 
if type ( value ) ~= "table" then
return latest
end
if value . source ~= nil then
latest = math . max ( latest , value . source . line or latest )
end
for key , child in pairs ( value ) do
if key ~= "source" then
latest = lastSourceLine ( child , latest )
end
end

return latest
end

local function append (
reports ,
kind ,
source ,
value ,
outcome ,
reason
) 
local counts = measurements ( value )
reports [
# reports + 1
] = _G.setmetatable({ id =
# reports + 1 ,  kind =
kind ,  line =
source ~= nil and ( source ) . line or 1 ,  lastLine =
lastSourceLine ( value , source ~= nil and ( source ) . line or 1 ) ,  column =
source ~= nil and ( source ) . column or 1 ,  nodes =
counts . nodes ,  simdOperations =
counts . simdOperations ,  luaOperations =
counts . luaOperations ,  nativeReads =
counts . nativeReads ,  nativeWrites =
counts . nativeWrites ,  mayRaise =
counts . mayRaise ,  outcome =
outcome ,  reason =
reason }, loops.Report)

end

local function structured ( statements , reports ) 
for _ , statement in ipairs ( statements ) do
if statement . op == "while" or statement . op == "repeat" or statement . op == "fornum" then
local counts = measurements ( statement )
local explicit = counts . simdOperations > 0
local reason = nil
if not explicit then
reason = "loop has no explicit SIMD operations in Nupp IR"
end
append ( reports , statement . op , statement . source , statement , explicit and "explicit-simd" or "scalar" , reason )
structured ( ( statement ) . conditionBody or { } , reports )
structured ( statement . body , reports )
elseif statement . op == "if" then
for _ , clause in ipairs ( statement . clauses ) do
structured ( clause . body , reports )
end
if statement . elseBody ~= nil then
structured ( statement . elseBody , reports )
end
elseif statement . op == "block" then
structured ( statement . body , reports )
end
end
end


function loops . program ( program ) 
local reports = { }
if program . loop ~= nil then
local statements = ( program . loop ) . statements
local explicit = measurements ( statements ) . simdOperations > 0
local reason = nil
if not explicit then
reason = "loop has no explicit SIMD operations in Nupp IR"
end
append (
reports ,
"map" ,
( program . loop ) . source ,
statements ,
explicit and "explicit-simd" or "scalar" ,
reason
)
elseif program . workgroup ~= nil then
local workgroup = program . workgroup
structured ( workgroup . prelude , reports )
structured ( workgroup . statements , reports )
else
structured ( program . body or { } , reports )
end

return reports
end

local __nuppExportValue= loops ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.loops"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.loops"]=__nuppExports;return __nuppExports