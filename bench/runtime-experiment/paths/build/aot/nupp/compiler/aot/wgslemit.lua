_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()










local scalarIR = require ( "nupp.compiler.aot.scalar" )

local wgslemit = { }




local INTERNAL = "nupp_tmp_"

const WGSL_TYPE = { i32 = "i32" , u32 = "u32" , bool = "bool" }

const BINARY

= {
add = "+" ,
sub = "-" ,
mul = "*" ,
div = "/" ,
mod = "%" ,
lt = "<" ,
le = "<=" ,
gt = ">" ,
ge = ">=" ,
eq = "==" ,
ne = "!=" ,
[ "and" ] = "&&" ,
[ "or" ] = "||" ,
band = "&" ,
bor = "|" ,
bxor = "^" ,
lshift = "<<" ,
rshift = ">>" ,
arshift = ">>" ,
i32_add = "+" ,
i32_sub = "-" ,
i32_mul = "*" ,
u32_add = "+" ,
u32_sub = "-" ,
u32_mul = "*" ,
u32_and = "&" ,
u32_or = "|" ,
u32_xor = "^" ,
u32_shl = "<<" ,
u32_shr = ">>" ,
}

local function identifier ( value ) 
local name = ( value : gsub ( "[^%w_]" , "_" ) )

return "nupp_tmp_" .. "name_" .. name
end

local function entrypoint ( value ) 
return ( value : gsub ( "[^%w_]" , "_" ) )
end


const OUTSIDE = { }

local outsideReason = nil







local function refuse ( reason ) 
outsideReason = reason
error ( OUTSIDE , 0 )
end

local function typeName ( value ) 
local named = WGSL_TYPE [ value ]
if named == nil then
refuse ( "webgpu-int32 only admits int32 and uint32 values, got " .. value )
end

return named
end

local function literal ( value , type_ ) 
local text = tostring ( value )
if type_ == "u32" then
return text : match ( "u$" ) and text or text .. "u"
end
local number = tonumber ( text )
if number == math . huge or number == - math . huge then


error ( "an infinite constant is not available in a GPU kernel" , 0 )
end

return text
end


local function emitProgram (
program ,
readonly ,
writable ,
uniforms ,
threads
) 
if program . executionTarget ~= "gpu" then
refuse ( "WGSL emission requires @aot(target = \"gpu\")" )
end
local loop = program . loop
if program . workgroup ~= nil or loop == nil then
refuse ( "webgpu-int32 currently admits complete-span map kernels" )
end
if # ( program . layouts or { } ) > 0 then
refuse ( "webgpu-int32 does not yet admit struct storage" )
end
if threads < 1 or threads > 256 then
refuse ( "webgpu-int32 workgroup size must be between 1 and 256" )
end

local spans = { }
for _ , param in ipairs ( readonly ) do
spans [ # spans + 1 ] = param
end
for _ , param in ipairs ( writable ) do
spans [ # spans + 1 ] = param
end
for _ , param in ipairs ( spans ) do
if param . type ~= "i32" and param . type ~= "u32" then
refuse ( "webgpu-int32 storage must be int32 or uint32" )
end
end
if # spans > 8 then
refuse ( "webgpu-int32 admits at most eight storage buffers" )
end
for _ , param in ipairs ( uniforms ) do
if param . type ~= "i32" and param . type ~= "u32" then
refuse ( "webgpu-int32 uniforms must be int32 or uint32" )
end
end

local function spanIndex ( value ) 
if value . cursor ~= nil then
refuse ( "webgpu-int32 does not yet admit cursor-indexed spans" )
end
if value . index ~= ( loop ) . index then
refuse ( "webgpu-int32 spans must use the dispatch index" )
end

return "[" .. "nupp_tmp_" .. "uniforms." .. "nupp_tmp_" .. identifier (
value . span
) .. "_offset + nupp_tmp_dispatch_index]"
end

local expression
expression = function ( value ) 
local op = value . op
if op == "local" or op == "helper_param" then
return identifier ( value . uniqueName or value . name )
elseif op == "uniform" then
return "nupp_tmp_" .. "uniforms." .. identifier ( value . name )
elseif op == "loop_index" then
return "(nupp_tmp_dispatch_index + 1u)"
elseif op == "load" then
return "nupp_tmp_" .. "buffer_" .. identifier ( value . span ) .. spanIndex ( value )
elseif op == "span_count" then
return "nupp_tmp_" .. "uniforms." .. "nupp_tmp_" .. identifier ( value . span ) .. "_count"
elseif op == "constant" or op == "constant_i32" then
return literal ( value . value , value . type )
elseif op == "bool" then
return value . value and "true" or "false"
elseif op == "numeric_cast" or op == "store_cast" then
return typeName ( value . type ) .. "(" .. expression ( value . value ) .. ")"
elseif BINARY [ op ] ~= nil then
return "(" .. expression ( value . left ) .. " " .. tostring ( BINARY [ op ] ) .. " " .. expression ( value . right ) .. ")"
elseif op == "neg" then
return "(-" .. expression ( value . value ) .. ")"
elseif op == "not" then
return "(!" .. expression ( value . value ) .. ")"
elseif op == "bnot" or op == "u32_not" then
return "(~" .. expression ( value . value ) .. ")"
end
refuse ( "webgpu-int32 does not emit expression " .. tostring ( op ) )

return ""
end

local lines = { }

local function line ( depth , value ) 
lines [ # lines + 1 ] = string . rep ( "    " , depth ) .. value
end

local mutable = { }

local function findAssignments ( values ) 
for _ , statement in ipairs ( values ) do
if statement . op == "assign" then
for _ , assignment in ipairs ( statement . values ) do
if assignment . target . kind == "local" then
mutable [ identifier ( assignment . target . uniqueName or assignment . target . name ) ] = true
end
end
elseif statement . op == "if" then
for _ , clause in ipairs ( statement . clauses ) do
findAssignments ( clause . body )
end
if statement . elseBody ~= nil then
findAssignments ( statement . elseBody )
end
elseif statement . op == "while"
or statement . op == "repeat"
or statement . op == "fornum"
or statement . op == "block"
then
findAssignments ( statement . body )
end
end
end

findAssignments ( ( loop ) . statements )

local forSerial = 0
local statements
statements = function ( values , depth ) 
for _ , statement in ipairs ( values ) do
local op = statement . op
if op == "let" then
if statement . type : match ( "^ref:" ) then
refuse ( "webgpu-int32 does not yet admit element references" )
end
line (
depth ,
(
mutable [ identifier ( statement . uniqueName ) ] == true and "var " or "let "
) .. identifier (
statement . uniqueName
) .. ": " .. typeName ( statement . type ) .. " = " .. expression ( statement . value ) .. ";"
)
elseif op == "assign" then
if # statement . values ~= 1 or statement . values [ 1 ] . target . kind ~= "local" then
refuse ( "webgpu-int32 only assigns locals" )
end
local assignment = statement . values [ 1 ]
line (
depth ,
identifier (
assignment . target . uniqueName or assignment . target . name
) .. " = " .. expression ( assignment . value ) .. ";"
)
elseif op == "store" then
line (
depth ,
"nupp_tmp_" .. "buffer_" .. identifier (
statement . span
) .. spanIndex ( statement ) .. " = " .. expression ( statement . value ) .. ";"
)
elseif op == "if" then
for index , clause in ipairs ( statement . clauses ) do
line ( depth , ( index == 1 and "if (" or "else if (" ) .. expression ( clause . condition ) .. ") {" )
statements ( clause . body , depth + 1 )
line ( depth , "}" )
end
if statement . elseBody ~= nil then
line ( depth , "else {" )
statements ( statement . elseBody , depth + 1 )
line ( depth , "}" )
end
elseif op == "fornum" then
if statement . from . type ~= "i32" or statement . to . type ~= "i32" then
refuse ( "GPU counted loop bounds must be int32" )
end
forSerial = forSerial + 1
local counter = "nupp_tmp_" .. "for_counter_" .. tostring ( forSerial )
local last = "nupp_tmp_" .. "for_last_" .. tostring ( forSerial )
local done = "nupp_tmp_" .. "for_done_" .. tostring ( forSerial )
line ( depth , "{" )
line ( depth + 1 , "var " .. counter .. ": i32 = " .. expression ( statement . from ) .. ";" )
line ( depth + 1 , "let " .. last .. ": i32 = " .. expression ( statement . to ) .. ";" )
line ( depth + 1 , "var " .. done .. ": bool = false;" )
line ( depth + 1 , "loop {" )
line ( depth + 2 , "if (" .. counter .. " > " .. last .. ") { break; }" )
line ( depth + 2 , "var " .. identifier ( statement . binding . uniqueName ) .. ": i32 = " .. counter .. ";" )
statements ( statement . body , depth + 2 )
line ( depth + 2 , "continuing {" )


line ( depth + 3 , done .. " = " .. counter .. " == " .. last .. ";" )
line ( depth + 3 , "if (!" .. done .. ") { " .. counter .. " = " .. counter .. " + 1; }" )
line ( depth + 3 , "break if " .. done .. ";" )
line ( depth + 2 , "}" )
line ( depth + 1 , "}" )
line ( depth , "}" )
elseif op == "while" then
if statement . conditionBody ~= nil then
refuse ( "statementful loop conditions are not admitted by this GPU profile" )
end
line ( depth , "while (" .. expression ( statement . condition ) .. ") {" )
statements ( statement . body , depth + 1 )
line ( depth , "}" )
elseif op == "repeat" then
if statement . conditionBody ~= nil then
refuse ( "statementful loop conditions are not admitted by this GPU profile" )
end
line ( depth , "loop {" )
statements ( statement . body , depth + 1 )
line ( depth + 1 , "continuing {" )
line ( depth + 2 , "break if " .. expression ( statement . condition ) .. ";" )
line ( depth + 1 , "}" )
line ( depth , "}" )
elseif op == "break" or op == "continue" then
line ( depth , op .. ";" )
elseif op == "block" then
line ( depth , "{" )
statements ( statement . body , depth + 1 )
line ( depth , "}" )
else
refuse ( "webgpu-int32 does not emit statement " .. tostring ( op ) )
end
end
end

line ( 0 , "struct nupp_tmp_Uniforms {" )
line ( 1 , "nupp_tmp_count: u32," )
for _ , param in ipairs ( spans ) do
line ( 1 , "nupp_tmp_" .. identifier ( param . name ) .. "_count: u32," )
end
for _ , param in ipairs ( spans ) do
line ( 1 , "nupp_tmp_" .. identifier ( param . name ) .. "_offset: u32," )
end
for _ , param in ipairs ( uniforms ) do
line ( 1 , identifier ( param . name ) .. ": " .. typeName ( param . type ) .. "," )
end
line ( 0 , "}" )
line ( 0 , "" )
local binding = 0
for _ , param in ipairs ( readonly ) do
line (
0 ,
"@group(0) @binding(" .. tostring (
binding
) .. ") var<storage, read> " .. "nupp_tmp_" .. "buffer_" .. identifier (
param . name
) .. ": array<" .. typeName ( param . type ) .. ">;"
)
binding = binding + 1
end
for _ , param in ipairs ( writable ) do
line (
0 ,
"@group(0) @binding(" .. tostring (
binding
) .. ") var<storage, read_write> " .. "nupp_tmp_" .. "buffer_" .. identifier (
param . name
) .. ": array<" .. typeName ( param . type ) .. ">;"
)
binding = binding + 1
end
line (
0 ,
"@group(0) @binding(" .. tostring (
binding
) .. ") var<uniform> nupp_tmp_uniforms: nupp_tmp_Uniforms;"
)
line ( 0 , "" )
line ( 0 , "@compute @workgroup_size(" .. tostring ( threads ) .. ")" )
line ( 0 , "fn " .. entrypoint ( program . symbol ) .. "_gpu(" )
line ( 1 , "@builtin(global_invocation_id) nupp_tmp_global_id: vec3<u32>," )
line ( 1 , "@builtin(num_workgroups) nupp_tmp_workgroups: vec3<u32>," )
line ( 0 , ") {" )



for _ , text in ipairs ( {
"let $row_width = $workgroups.x * " .. tostring ( threads ) .. "u;" ,
"let $dispatch_index = $global_id.y * $row_width + $global_id.x;" ,
"let $count_row = $uniforms.$count / $row_width;" ,
"let $count_column = $uniforms.$count % $row_width;" ,
"if ($global_id.y > $count_row || ($global_id.y == $count_row && $global_id.x >= $count_column)) {" ,
} ) do
line ( 1 , ( text : gsub ( "%$" , "nupp_tmp_" ) ) )
end
line ( 2 , "return;" )
line ( 1 , "}" )
statements ( ( loop ) . statements , 1 )
line ( 0 , "}" )

return table . concat ( lines , "\n" )
end










function wgslemit . program (
program ,
readonly ,
writable ,
uniforms ,
threads
) 
outsideReason = nil
local ok , source = pcall ( emitProgram , program , readonly , writable , uniforms , threads )
if ok then
return source , nil
end
if source ~= OUTSIDE then
error ( source , 0 )
end

return nil , outsideReason
end

local __nuppExportValue= wgslemit ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.wgslemit"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.wgslemit"]=__nuppExports;return __nuppExports