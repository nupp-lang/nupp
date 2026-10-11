_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.text\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.text\0runtime\0002") };












local relations = require ( "nupp.compiler.aot.relations" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )

local text = { }






text.Operands = {} text.Operands.__index = text.Operands ;_G.nupp.__reflect.link(text.Operands,__nuppT1[1],{ })













text.Pair = {} text.Pair.__index = text.Pair ;_G.nupp.__reflect.link(text.Pair,__nuppT1[2],{ })










text . LIST_OPERANDS = { [ "f32_fma" ] = true , }


text . ONE_OPERAND = {
[ "widen_f32_f64" ] = true ,
[ "narrow_f64_f32" ] = true ,
[ "int_to_f64" ] = true ,
[ "numeric_cast" ] = true ,
[ "store_cast" ] = true ,
[ "f32_from_bits" ] = true ,
[ "f32_to_bits" ] = true ,
[ "f16_to_f32" ] = true ,
[ "f32_to_f16" ] = true ,
[ "bf16_to_f32" ] = true ,
[ "f32_to_bf16" ] = true ,
[ "neg" ] = true ,
[ "not" ] = true ,
[ "bnot" ] = true ,
[ "f32_sqrt" ] = true ,
[ "f32_exp" ] = true ,
[ "u32_not" ] = true ,
[ "u32_popcount" ] = true ,
[ "u32_ctz" ] = true ,
[ "u32_clz" ] = true ,
[ "i64_not" ] = true ,
[ "u64_not" ] = true ,
[ "u64_popcount" ] = true ,
[ "u64_ctz" ] = true ,
[ "u64_clz" ] = true ,
[ "u64_prefix_xor" ] = true ,
}





local function at ( source ) 
local site = source or _G.setmetatable({ line =  1 ,  column =  1 }, scalarIR.Source)

return ("@%d:%d") : format ( site . line , site . column )
end


function text . displayOp ( node ) 
return node . op
end


function text . expression ( node ) 
local op = node . op
if op == "load" then
local index = node . cursor ~= nil and node . cursor .. "+" .. tostring ( ( node . cursorOffset or 0 ) + 1 ) or node . index
return "load:" .. node . type .. " " .. node . span .. "[" .. index .. "]"
elseif op == "span_count" then
return "count " .. node . span
elseif op == "loop_index" then
return "loop_index:f64"
elseif op == "workgroup_index" or op == "local_index" then
return op .. ":u32"
elseif op == "shared_load" then
local load = node
return "shared_load:" .. load . type .. " " .. load . shared .. "[" .. text . expression ( load . index ) .. "]"
elseif op == "element_ref" then
local index = node . cursor ~= nil and node . cursor .. "+" .. tostring ( ( node . cursorOffset or 0 ) + 1 ) or node . index
return "element_ref:" .. node . layout .. " " .. node . span .. "[" .. index .. "]"
elseif op == "field_load" then
return "field:" .. node . type .. " " .. text . expression ( node . object ) .. "." .. node . field
elseif op == "aggregate_new" then
local parts = { }
for position , value in ipairs ( ( node ) . values ) do
parts [ position ] = text . expression ( value )
end
return "aggregate:" .. node . layout .. "(" .. table . concat ( parts , ", " ) .. ")"
elseif op == "aggregate_field" then
return "field:" .. node . type .. " " .. text . expression ( node . object ) .. "." .. node . field
elseif op == "uniform" or op == "local" or op == "helper_param" then
return op .. ":" .. node . type .. " " .. ( node ) . name
elseif op == "constant_i32" or op == "constant_i64" then
return "constant:" .. node . type .. " " .. node . value
elseif op == "constant" then
return "constant:f64 " .. node . value
elseif op == "bool" then
return "bool " .. tostring ( node . value )
elseif op == "lua_nil" then
return "lua.nil"
elseif op == "lua_string" then
return "lua.string " .. string . format ( "%q" , node . value )
elseif op == "lua_string_match" then
local matched = node
return "lua.string_match(" .. text . expression (
matched . bytes
) .. ", " .. string . format ( "%q" , matched . value ) .. ")"
elseif op == "lua_concat" then
return "lua.concat(" .. text . expression ( node . left ) .. ", " .. text . expression ( node . right ) .. ")"
elseif op == "lua_substring" then
return "lua.substring(" .. text . expression (
node . bytes
) .. ", " .. text . expression (
node . first
) .. ( node . last ~= nil and ", " .. text . expression ( node . last ) or "" ) .. ")"
elseif op == "lua_string_byte_lua" then
return "lua.byte(" .. text . expression ( node . bytes ) .. ", " .. text . expression ( node . index ) .. ")"
elseif op == "lua_table_get_index" then
return "lua.get_index(" .. text . expression ( node . table ) .. ", " .. text . expression ( node . key ) .. ")"
elseif op == "lua_string_buffer" then
return "lua.string_buffer(" .. text . expression ( node . initial ) .. ")"
elseif op == "lua_string_buffer_finish" then
return "lua.string_buffer_finish(" .. text . expression ( node . buffer ) .. ")"
elseif op == "lua_new_table" then
local created = node
local fields = { }
for position , field in ipairs ( created . fields or { } ) do
fields [
position
] = (
field . indexed and "index " or "key "
) .. text . expression ( field . key ) .. " = " .. text . expression ( field . value )
end
return "lua.new_table(" .. text . expression (
created . arrayCapacity
) .. ", " .. text . expression ( created . hashCapacity ) .. "){" .. table . concat ( fields , "; " ) .. "}"
elseif op == "lua_builder" then
local builder = node
local values = { builder . mode , text . expression ( builder . nullValue ) }
if builder . maxDepth ~= nil then
values [ # values + 1 ] = text . expression ( builder . maxDepth )
values [ # values + 1 ] = text . expression ( builder . stringCapacity )
if builder . arrayMarker ~= nil then
values [ # values + 1 ] = text . expression ( builder . arrayMarker )
values [ # values + 1 ] = text . expression ( builder . objectMarker )
if builder . selectionShape ~= nil then
values [ # values + 1 ] = text . expression ( builder . selectionShape )
values [ # values + 1 ] = text . expression ( builder . arrayShapeMarker )
values [ # values + 1 ] = text . expression ( builder . serdeMarkers )
end
end
end
return "lua.builder(" .. table . concat ( values , ", " ) .. ")"
elseif op == "lua_scratch_u32" then
return "lua.scratch_u32(" .. text . expression ( ( node ) . capacity ) .. ")"
elseif op == "lua_scratch_u32_get" or op == "lua_scratch_u32_escape_get" then
local loaded = node
return (
op == "lua_scratch_u32_escape_get" and "lua.scratch_u32_escape_get(" or "lua.scratch_u32_get("
) .. text . expression ( loaded . scratch ) .. ", " .. text . expression ( loaded . index ) .. ")"
elseif op == "lua_scratch_u32_length" or op == "lua_scratch_u32_escape_length" then
return (
op == "lua_scratch_u32_escape_length" and "lua.scratch_u32_escape_length(" or "lua.scratch_u32_length("
) .. text . expression ( ( node ) . scratch ) .. ")"
elseif op == "lua_scratch_u8" then
return "lua.scratch_u8(" .. text . expression ( ( node ) . capacity ) .. ")"
elseif op == "lua_scratch_u8_get" then
local loaded = node
return "lua.scratch_u8_get(" .. text . expression ( loaded . scratch ) .. ", " .. text . expression ( loaded . index ) .. ")"
elseif op == "lua_string_length" then
return "lua.length(" .. text . expression ( ( node ) . bytes ) .. ")"
elseif op == "lua_string_byte" or op == "lua_string_byte_at" or op == "lua_string_u32" then
local bytes = node
return op .. "(" .. text . expression ( bytes . bytes ) .. ", " .. text . expression ( bytes . index ) .. ")"
elseif op == "lua_builder_finish" then
return "lua.builder_finish(" .. text . expression ( ( node ) . builder ) .. ")"
elseif op == "lua_builder_depth"
or op == "lua_builder_kind"
or op == "lua_builder_count"
or op == "lua_builder_state"
then
return op .. "(" .. text . expression ( ( node ) . builder ) .. ")"
elseif op == "lua_builder_number_token" then
local number = node
return op .. ":u32(" .. table . concat (
{
text . expression ( number . builder ) ,
text . expression ( number . sourceBytes ) ,
text . expression ( number . start ) ,
text . expression ( number . limit ) ,
} ,
", "
) .. ")"
elseif op == "reducer_init" then
local reducer = node
return "reducer." .. reducer . order .. "." .. reducer . operation .. "(" .. text . expression ( reducer . initial ) .. ")"
elseif op == "reducer_add" then
local reducer = node
return "reducer.add " .. text . expression (
reducer . reducer
) .. " <- " .. text . expression (
reducer . value
) .. ( reducer . right ~= nil and ", " .. text . expression ( reducer . right ) or "" )
elseif op == "reducer_value" then
local reducer = node
return "reducer.value " .. text . expression ( reducer . reducer )
elseif op == "simd_reducer_add" then
local reducer = node
return "simd.reducer." .. reducer . order .. "." .. reducer . operation .. " " .. text . expression (
reducer . reducer
) .. " <- " .. text . expression (
reducer . value
) .. (
reducer . right ~= nil and ", " .. text . expression ( reducer . right ) or ""
) .. " if " .. text . expression ( reducer . mask )
elseif tostring ( op ) : match ( "^simd_" ) ~= nil then
local simd = node
local values = { }
for position , argument in ipairs ( simd . args ) do
values [ position ] = text . expression ( argument )
end
if simd . span ~= nil then
values [ # values + 1 ] = "span:" .. ( simd . span )
end
if simd . field ~= nil then
values [ # values + 1 ] = "field:" .. tostring ( simd . layout ) .. "." .. ( simd . field )
end
if simd . helper ~= nil then
values [ # values + 1 ] = "helper:" .. ( simd . helper )
end
if simd . part ~= nil then
values [ # values + 1 ] = "part:" .. tostring ( simd . part )
end
local name = tostring ( op ) .. ( simd . intrinsic ~= nil and "." .. ( simd . intrinsic ) or "" )
return name .. ":" .. simd . type .. "(" .. table . concat ( values , ", " ) .. ")"
elseif text . ONE_OPERAND [ tostring ( op ) ] == true then
return op .. "(" .. text . expression ( ( node ) . value ) .. ")"
end


local function operands ( args ) 
local rendered = { }
for position , argument in ipairs ( args ) do
rendered [ position ] = text . expression ( argument )
end

return table . concat ( rendered , ", " )
end

if op == "math" then
return "math." .. node . intrinsic .. "(" .. operands ( node . args ) .. ")"
elseif op == "helper_call" then
return "call " .. node . helper .. "(" .. operands ( node . args ) .. ")"
elseif text . LIST_OPERANDS [ tostring ( op ) ] == true then
local listed = node

return text . displayOp ( listed ) .. ":" .. tostring ( listed . type ) .. "(" .. operands ( listed . args ) .. ")"
end

local pair = node

return op .. "(" .. text . expression ( pair . left ) .. ", " .. text . expression ( pair . right ) .. ")"
end


local function target ( assignment ) 
if assignment . target . kind == "local" then
return assignment . target . name
end

return text . expression ( assignment . target . object ) .. "." .. assignment . target . field
end


local function scratchWrite ( label , statement ) 
return label .. " " .. text . expression (
statement . scratch
) .. "[" .. text . expression (
statement . index
) .. "] = " .. text . expression ( statement . value )
end



local function carrying ( carried ) 
if carried == nil or # ( carried ) == 0 then
return ""
end
local names = { }
for position , entry in ipairs ( carried ) do
names [ position ] = entry . name .. ":" .. entry . type
end

return " carrying " .. table . concat ( names , ", " )
end


function text . block ( statements , depth ) 
local lines = { }
local prefix = string . rep ( "  " , depth )


local function nested ( body ) 
for _ , line in ipairs ( text . block ( body , depth + 1 ) ) do
lines [ # lines + 1 ] = line
end
end

for _ , statement in ipairs ( statements ) do
local op = statement . op
if op == "let" then
lines [
# lines + 1
] = prefix .. (
statement . assigned == true and "var " or "let "
) .. statement . name .. ":" .. statement . type .. " = " .. text . expression ( statement . value )
elseif op == "multi_let" then
local names = { }
for position , bound in ipairs ( statement . bindings ) do
names [ position ] = ( bound . assigned == true and "var " or "" ) .. bound . name .. ":" .. bound . type
end
lines [ # lines + 1 ] = prefix .. "let " .. table . concat ( names , "," ) .. " = " .. text . expression ( statement . call )
elseif op == "store" then
local index = statement . cursor ~= nil
and statement . cursor .. "+" .. tostring ( ( statement . cursorOffset or 0 ) + 1 )
or statement . index
lines [
# lines + 1
] = prefix .. "store " .. statement . span .. "[" .. index .. "] = " .. text . expression ( statement . value )
elseif op == "shared_store" then
local store = statement
lines [
# lines + 1
] = prefix .. "shared_store " .. store . shared .. "[" .. text . expression (
store . index
) .. "] = " .. text . expression ( store . value )
elseif op == "phase" then
lines [ # lines + 1 ] = prefix .. "phase"
nested ( ( statement ) . body )
lines [ # lines + 1 ] = prefix .. "barrier"
elseif op == "lua_set_index" or op == "lua_set_key" then
lines [
# lines + 1
] = prefix .. op .. " " .. text . expression (
statement . table
) .. "[" .. text . expression ( statement . key ) .. "] = " .. text . expression ( statement . value )
elseif op == "lua_string_buffer_append" then
lines [
# lines + 1
] = prefix .. "lua.string_buffer_append(" .. text . expression (
statement . buffer
) .. ", " .. text . expression ( statement . value ) .. ")"
elseif op == "lua_scratch_u32_set" then
lines [ # lines + 1 ] = prefix .. scratchWrite ( "lua.scratch_u32_set" , statement )
elseif op == "lua_scratch_u8_set" then
lines [ # lines + 1 ] = prefix .. scratchWrite ( "lua.scratch_u8_set" , statement )
elseif op == "lua_scratch_u8_set4" then
lines [ # lines + 1 ] = prefix .. scratchWrite ( "lua.scratch_u8_set4" , statement )
elseif op == "lua_scratch_u8_reset" then
lines [
# lines + 1
] = prefix .. "lua.scratch_u8_reset " .. text . expression ( ( statement ) . scratch )
elseif tostring ( op ) : match ( "^lua_builder_" ) ~= nil then
local event = statement
local values = { text . expression ( event . builder ) }


local function append ( value ) 
if value ~= nil then
values [ # values + 1 ] = text . expression ( value )
end
end

append ( event . capacity )
append ( event . sourceBytes )
append ( event . start )
append ( event . length )
append ( event . escaped )
append ( event . value )
append ( event . exponent )
append ( event . negative )
append ( event . exact )
append ( event . scratch )
append ( event . escapeScratch )
append ( event . escapeIndex )
append ( event . escapeCount )
lines [ # lines + 1 ] = prefix .. op .. "(" .. table . concat ( values , ", " ) .. ")"
elseif op == "assign" then
for _ , assignment in ipairs ( statement . values ) do
lines [ # lines + 1 ] = prefix .. "set " .. target ( assignment ) .. " = " .. text . expression ( assignment . value )
end
elseif op == "reducer_add" then
lines [ # lines + 1 ] = prefix .. text . expression ( statement )
elseif op == "simd_store" or op == "simd_field_store" then
lines [ # lines + 1 ] = prefix .. text . expression ( statement )
elseif op == "simd_reducer_add" then
lines [ # lines + 1 ] = prefix .. text . expression ( statement )
elseif op == "reducer_region" then
local region = statement
local names = { }
for position , reducer in ipairs ( region . reducers ) do
names [ position ] = reducer . name
end
lines [ # lines + 1 ] = prefix .. "simd.region " .. table . concat ( names , ", " )
nested ( region . body )
lines [ # lines + 1 ] = prefix .. "end"
elseif op == "if" then
for position , clause in ipairs ( statement . clauses ) do
lines [
# lines + 1
] = prefix .. ( position == 1 and "if " or "elseif " ) .. text . expression ( clause . condition )
nested ( clause . body )
end
if statement . elseBody ~= nil then
lines [ # lines + 1 ] = prefix .. "else"
nested ( statement . elseBody )
end
lines [ # lines + 1 ] = prefix .. "end"
elseif op == "fornum" then
local region = statement
lines [
# lines + 1
] = prefix .. "for " .. (
statement . binding . assigned == true and "var " or ""
) .. statement . binding . name .. " = " .. text . expression (
statement . from
) .. " .. " .. text . expression ( statement . to ) .. carrying ( region . carried )
nested ( statement . body )
lines [ # lines + 1 ] = prefix .. "end"
elseif op == "while" then
if statement . conditionBody ~= nil then
lines [ # lines + 1 ] = prefix .. "condition setup"
nested ( statement . conditionBody )
end
lines [
# lines + 1
] = prefix .. "while " .. text . expression ( statement . condition ) .. carrying ( statement . carried )
nested ( statement . body )
lines [ # lines + 1 ] = prefix .. "end"
elseif op == "repeat" then
lines [ # lines + 1 ] = prefix .. "repeat" .. carrying ( statement . carried )
nested ( statement . body )
if statement . conditionBody ~= nil then
lines [ # lines + 1 ] = prefix .. "condition setup"
nested ( statement . conditionBody )
end
lines [ # lines + 1 ] = prefix .. "until " .. text . expression ( statement . condition )
elseif op == "block" then
lines [ # lines + 1 ] = prefix .. "block"
nested ( statement . body )
lines [ # lines + 1 ] = prefix .. "end"
elseif op == "return" then
local values = { }
for position , value in ipairs ( statement . values ) do
values [ position ] = text . expression ( value )
end
lines [ # lines + 1 ] = prefix .. "return " .. table . concat ( values , ", " )
else
lines [ # lines + 1 ] = prefix .. op
end
end

return lines
end


local function preamble ( program ) 
local lines

= { "native-ir " .. tostring ( scalarIR . VERSION ) , "function " .. program . name , "symbol " .. program . symbol , }
lines [ # lines + 1 ] = "entry " .. program . entryMode
if program . executionTarget == "gpu" then
lines [ # lines + 1 ] = "target gpu"
end


if program . reusableScratch ~= nil then
lines [ # lines + 1 ] = "reuses scratch " .. tostring ( program . reusableScratch )
end
if program . runtimeAbi ~= nil then
lines [
# lines + 1
] = "runtime " .. tostring ( program . runtimeAbi ) .. " registrar(" .. tostring ( program . registrar ) .. ")"
end




if program . fpContract == true then
lines [ # lines + 1 ] = "contract fp-contract(fused)"
end
if program . fpTranscendentals == true then
lines [ # lines + 1 ] = "contract fp-transcendentals(native)"
end
if program . simdWidth ~= nil then
lines [ # lines + 1 ] = "simd species(uint8," .. tostring ( program . simdWidth ) .. ")"
end

lines [ # lines + 1 ] = "layouts"
for _ , layout in ipairs ( program . layouts or { } ) do
local fields = { }
for position , field in ipairs ( layout . fields ) do
fields [ position ] = field . name .. ":" .. field . type .. " source(" .. tostring ( field . sourceType ) .. ")"
end
if layout . nativeOnly == true then
fields [ # fields + 1 ] = "native-only"
end
lines [ # lines + 1 ] = "  " .. layout . name .. "{" .. table . concat ( fields , "," ) .. "}"
end

lines [ # lines + 1 ] = "params"
for _ , param in ipairs ( program . params ) do
if param . region ~= nil then
lines [
# lines + 1
] = ("  %s %s:%s source(%s) span(%s) region(%s) %s %s")

: format (
param . kind ,
param . name ,
param . type ,
tostring ( param . sourceType ) ,
tostring ( param . spanModule ) ,
tostring ( param . region ) ,
tostring ( param . access ) ,
at ( param . source )
)
if param . soa ~= nil then
local column = param . soa
lines [
# lines + 1
] = ("    soa %s:%s layout(%s) field(%d,%s)")

: format ( column . view , column . sourceType , column . layout , column . ordinal , column . field )
end
else
lines [
# lines + 1
] = ("  %s %s:%s source(%s) %s")

: format ( param . kind , param . name , param . type , tostring ( param . sourceType ) , at ( param . source ) )
end
end

lines [ # lines + 1 ] = "aliasing"
for _ , fact in ipairs ( program . aliasFacts ) do
lines [ # lines + 1 ] = ("  %s %s %s proof(%s)") : format ( fact . relation , fact . left , fact . right , fact . proof )
end

lines [ # lines + 1 ] = "helpers"
for _ , helper in ipairs ( program . helpers or { } ) do
lines [
# lines + 1
] = ("  %s -> %s %s") : format ( helper . name , table . concat ( helper . resultTypes , "," ) , at ( helper . source ) )
end

lines [ # lines + 1 ] = "relations"
for _ , relation in ipairs ( program . relations or { } ) do
lines [ # lines + 1 ] = ("  %s %s") : format ( relations . text ( relation ) , at ( relation . source ) )
end

lines [ # lines + 1 ] = "guards"
for _ , guard in ipairs ( program . guards ) do
lines [ # lines + 1 ] = ("  equal_count %s %s %s") : format ( guard . left , guard . right , at ( guard . source ) )
end

local rangeGuard = program . rangeGuard
if rangeGuard ~= nil then
local guard = rangeGuard
lines [
# lines + 1
] = ("  range %s %s count(%s) %s") : format ( guard . first , guard . last , guard . count , at ( guard . source ) )
end

local resultTypes = program . resultTypes or { }
lines [ # lines + 1 ] = "results " .. ( # resultTypes == 0 and "nil" or table . concat ( resultTypes , "," ) )

local loop = program . loop
local workgroup = program . workgroup
if loop ~= nil then
local scalarLoop = loop
lines [
# lines + 1
] = ("loop %s = %s .. %s count(%s) %s")

: format (
scalarLoop . index ,
tostring ( scalarLoop . first ) ,
tostring ( scalarLoop . last ) ,
scalarLoop . count ,
at ( scalarLoop . source )
)
elseif workgroup ~= nil then
local phased = workgroup
lines [
# lines + 1
] = ("workgroups count(%s) size(%d) dispatch(%s) %s")

: format ( text . expression ( phased . groups ) , phased . size , phased . dispatchSpan , at ( phased . source ) )
for _ , scratch in ipairs ( phased . shared ) do
lines [
# lines + 1
] = ("  shared %s:%s[%d] = %s %s")

: format ( scratch . name , scratch . element , scratch . count , text . expression ( scratch . initial ) , at ( scratch . source ) )
end
else
lines [ # lines + 1 ] = "block"
end

return lines
end




function text . program ( program ) 
local lines = preamble ( program )
local loop = program . loop
local workgroup = program . workgroup
local statements = loop ~= nil and ( loop ) . statements
or workgroup ~= nil and ( workgroup ) . statements
or program . body
or { }
if workgroup ~= nil then
for _ , line in ipairs ( text . block ( ( workgroup ) . prelude , 1 ) ) do
lines [ # lines + 1 ] = line
end
end
for _ , line in ipairs ( text . block ( statements , 1 ) ) do
lines [ # lines + 1 ] = line
end

return table . concat ( lines , "\n" ) .. "\n"
end





function text . programs ( programs ) 
local parts = { }
for position , program in ipairs ( programs ) do
parts [ position ] = text . program ( program )
end

return table . concat ( parts , "\n" )
end

local __nuppExportValue= text ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.text"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.text"]=__nuppExports;return __nuppExports