_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.simd.states\0runtime\0001") };






















local builder = require ( "nupp.compiler.aot.llvm.builder" )
local reducers = require ( "nupp.compiler.aot.reducers" )

local states = { }


local function pairwiseType ( scalar ) 
return "{ [64 x " .. scalar .. "], i64 }"
end


local function compensatedType ( scalar ) 
return "{ " .. scalar .. ", " .. scalar .. " }"
end


local function floatingType ( element ) 
return element == "f32" and "float" or "double"
end


const NAN = "0x7FF8000000000000"

const ELEMENT_TYPES

= {
[ "i32" ] = "i32" ,
[ "u32" ] = "i32" ,
[ "i64" ] = "i64" ,
[ "u64" ] = "i64" ,
[ "f64" ] = "double" ,
[ "f32" ] = "float" ,
[ "bool" ] = "i1" ,
}


local function floatingState ( order , scalar ) 
if order == "ordered" or order == "algebraic" then
return scalar
elseif order == "pairwise" then
return ( "{ [64 x " .. scalar .. "], i64 }" )
elseif order == "compensated" then
return ( "{ " .. scalar .. ", " .. scalar .. " }" )
end

return nil
end


function states . type ( typeName ) 
local order , operation = typeName : match ( "^simd_reducer_(%a+)_(%a+)$" )
if order ~= nil then
return floatingState ( order , "double" )
end
if operation ~= nil then
return nil
end
local parsedOrder , _ , element = reducers . parse ( typeName )
if element == nil then
return nil
end
local total = ELEMENT_TYPES [ element ]
if total == nil then
return nil
end
local floating = floatingState ( parsedOrder , total )
if floating ~= nil then
return floating
end

return "{ " .. ( total ) .. ", i64, i64 }"
end


function states . bare ( order ) 
return order == "ordered" or order == "algebraic"
end



function states . floating ( element ) 
return ( element == "f32" and "float" or "double" )
end

local function attrs ( module ) 
return builder . attributes ( module , "alwaysinline nounwind" )
end


local function define ( module , name , lines ) 
builder . once ( module , "define " .. name , table . concat ( lines , "\n" ) )

return "@" .. name
end



local function pairwise (
module ,
operator ,
empty ,
scalar
) 
local stem = "nupp.pairwise." .. ( operator == "fadd" and "sum" or "product" ) .. ( scalar == "float" and ".f32" or "" )
local PAIRWISE = ( "{ [64 x " .. scalar .. "], i64 }" )
local a = ( builder . attributes ( module , "alwaysinline nounwind" ) )




local root = builder . metadata ( module , "!{!\"nupp pairwise state\"}" )

local function tag ( name ) 
local scalar = builder . metadata ( module , ("!{!\"%s\", %s, i64 0}") : format ( name , root ) )
return ", !tbaa " .. builder . metadata ( module , ("!{%s, %s, i64 0}") : format ( scalar , scalar ) )
end

local partials , counter = tag ( "partial" ) , tag ( "count" )
local add = define ( module , stem .. ".add" , {
"define internal void @" .. stem .. ".add(ptr %state, " .. scalar .. " %value) " .. a .. " {" ,
"entry:" ,
"  %countp = getelementptr inbounds " .. PAIRWISE .. ", ptr %state, i32 0, i32 1" ,
"  %count = load i64, ptr %countp" .. counter ,
"  br label %carry" ,
"carry:" ,
"  %occupied = phi i64 [ %count, %entry ], [ %shifted, %merge ]" ,
"  %level = phi i64 [ 0, %entry ], [ %next, %merge ]" ,
"  %carried = phi " .. scalar .. " [ %value, %entry ], [ %combined, %merge ]" ,
"  %low = and i64 %occupied, 1" ,
"  %busy = icmp ne i64 %low, 0" ,
"  br i1 %busy, label %merge, label %place" ,
"merge:" ,
"  %slot = getelementptr inbounds " .. PAIRWISE .. ", ptr %state, i32 0, i32 0, i64 %level" ,
"  %partial = load " .. scalar .. ", ptr %slot" .. partials ,
"  %combined = " .. operator .. " " .. scalar .. " %partial, %carried" ,
"  %shifted = lshr i64 %occupied, 1" ,
"  %next = add i64 %level, 1" ,
"  br label %carry" ,
"place:" ,
"  %target = getelementptr inbounds " .. PAIRWISE .. ", ptr %state, i32 0, i32 0, i64 %level" ,
"  store " .. scalar .. " %carried, ptr %target" .. partials ,
"  %more = add i64 %count, 1" ,
"  store i64 %more, ptr %countp" .. counter ,
"  ret void" ,
"}" ,
} )
local init = define ( module , stem .. ".init" , {
"define internal void @" .. stem .. ".init(ptr %state, " .. scalar .. " %initial) " .. a .. " {" ,
"  %countp = getelementptr inbounds " .. PAIRWISE .. ", ptr %state, i32 0, i32 1" ,
"  store i64 0, ptr %countp" .. counter ,
"  call void " .. add .. "(ptr %state, " .. scalar .. " %initial)" ,
"  ret void" ,
"}" ,
} )
local value = define ( module , stem .. ".value" , {
"define internal " .. scalar .. " @" .. stem .. ".value(ptr %state) " .. a .. " {" ,
"entry:" ,
"  %countp = getelementptr inbounds " .. PAIRWISE .. ", ptr %state, i32 0, i32 1" ,
"  %count = load i64, ptr %countp" .. counter ,
"  br label %walk" ,
"walk:" ,
"  %level = phi i64 [ 0, %entry ], [ %next, %step ]" ,
"  %result = phi " .. scalar .. " [ " .. empty .. ", %entry ], [ %kept, %step ]" ,
"  %have = phi i1 [ false, %entry ], [ %had, %step ]" ,
"  %bits = lshr i64 %count, %level" ,
"  %bit = and i64 %bits, 1" ,
"  %set = icmp ne i64 %bit, 0" ,
"  br i1 %set, label %take, label %step" ,
"take:" ,
"  %slot = getelementptr inbounds " .. PAIRWISE .. ", ptr %state, i32 0, i32 0, i64 %level" ,
"  %partial = load " .. scalar .. ", ptr %slot" .. partials ,
"  %joined = " .. operator .. " " .. scalar .. " %partial, %result" ,
"  %taken = select i1 %have, " .. scalar .. " %joined, " .. scalar .. " %partial" ,
"  br label %step" ,
"step:" ,
"  %kept = phi " .. scalar .. " [ %result, %walk ], [ %taken, %take ]" ,
"  %had = phi i1 [ %have, %walk ], [ true, %take ]" ,
"  %next = add i64 %level, 1" ,
"  %done = icmp eq i64 %next, 64" ,
"  br i1 %done, label %out, label %walk" ,
"out:" ,
"  ret " .. scalar .. " %kept" ,
"}" ,
} )

return init , add , value
end

local function compensated ( module , scalar ) 
local COMPENSATED = ( "{ " .. scalar .. ", " .. scalar .. " }" )
local stem = "nupp.compensated" .. ( scalar == "float" and ".f32" or "" )
local a = ( builder . attributes ( module , "alwaysinline nounwind" ) )
local init = define ( module , stem .. ".init" , {
"define internal void @" .. stem .. ".init(ptr %state, " .. scalar .. " %initial) " .. a .. " {" ,
"  store " .. scalar .. " %initial, ptr %state" ,
"  %cp = getelementptr inbounds " .. COMPENSATED .. ", ptr %state, i32 0, i32 1" ,
"  store " .. scalar .. " 0.0, ptr %cp" ,
"  ret void" ,
"}" ,
} )
local add = define ( module , stem .. ".add" , {
"define internal void @" .. stem .. ".add(ptr %state, " .. scalar .. " %value) " .. a .. " {" ,
"  %total = load " .. scalar .. ", ptr %state" ,
"  %cp = getelementptr inbounds " .. COMPENSATED .. ", ptr %state, i32 0, i32 1" ,
"  %compensation = load " .. scalar .. ", ptr %cp" ,
"  %sum = fadd " .. scalar .. " %total, %value" ,
"  %tneg = fcmp olt " .. scalar .. " %total, 0.0" ,
"  %tflip = fneg " .. scalar .. " %total" ,
"  %tabs = select i1 %tneg, " .. scalar .. " %tflip, " .. scalar .. " %total" ,
"  %vneg = fcmp olt " .. scalar .. " %value, 0.0" ,
"  %vflip = fneg " .. scalar .. " %value" ,
"  %vabs = select i1 %vneg, " .. scalar .. " %vflip, " .. scalar .. " %value" ,
"  %larger = fcmp oge " .. scalar .. " %tabs, %vabs" ,
"  %tlost = fsub " .. scalar .. " %total, %sum" ,
"  %tpart = fadd " .. scalar .. " %tlost, %value" ,
"  %vlost = fsub " .. scalar .. " %value, %sum" ,
"  %vpart = fadd " .. scalar .. " %vlost, %total" ,
"  %part = select i1 %larger, " .. scalar .. " %tpart, " .. scalar .. " %vpart" ,
"  %kept = fadd " .. scalar .. " %compensation, %part" ,
"  store " .. scalar .. " %kept, ptr %cp" ,
"  store " .. scalar .. " %sum, ptr %state" ,
"  ret void" ,
"}" ,
} )
local value = define ( module , stem .. ".value" , {
"define internal " .. scalar .. " @" .. stem .. ".value(ptr %state) " .. a .. " {" ,
"  %total = load " .. scalar .. ", ptr %state" ,
"  %cp = getelementptr inbounds " .. COMPENSATED .. ", ptr %state, i32 0, i32 1" ,
"  %compensation = load " .. scalar .. ", ptr %cp" ,
"  %out = fadd " .. scalar .. " %total, %compensation" ,
"  ret " .. scalar .. " %out" ,
"}" ,
} )

return init , add , value
end


local function better ( element , operation ) 
local signed = element == "i32" or element == "i64"
if operation == "min" or operation == "argmin" then
return signed and "slt" or "ult"
end

return signed and "sgt" or "ugt"
end



local function floatBetter ( order , operation , scalar ) 
local less = operation == "min" or operation == "argmin"
local bits = scalar == "float" and "i32" or "i64"
local lines = {
"  %vnan = fcmp uno " .. scalar .. " %value, 0.0" ,
"  %tnan = fcmp uno " .. scalar .. " %total, 0.0" ,
"  %strict = fcmp " .. ( less and "olt" or "ogt" ) .. " " .. scalar .. " %value, %total" ,
"  %vzero = fcmp oeq " .. scalar .. " %value, 0.0" ,
"  %tzero = fcmp oeq " .. scalar .. " %total, 0.0" ,
"  %vbits = bitcast " .. scalar .. " %value to " .. bits ,
"  %tbits = bitcast " .. scalar .. " %total to " .. bits ,
"  %vsign = icmp slt " .. bits .. " %vbits, 0" ,
"  %tsign = icmp slt " .. bits .. " %tbits, 0" ,
}

if less then
lines [ # lines + 1 ] = "  %tsignclear = xor i1 %tsign, true"
lines [ # lines + 1 ] = "  %signs = and i1 %vsign, %tsignclear"
else
lines [ # lines + 1 ] = "  %vsignclear = xor i1 %vsign, true"
lines [ # lines + 1 ] = "  %signs = and i1 %vsignclear, %tsign"
end
lines [ # lines + 1 ] = "  %zeros = and i1 %vzero, %tzero"
lines [ # lines + 1 ] = "  %tie = and i1 %zeros, %signs"
lines [ # lines + 1 ] = "  %ordered = or i1 %strict, %tie"
if order == "propagating" then

lines [ # lines + 1 ] = "  %either = or i1 %vnan, %ordered"
lines [ # lines + 1 ] = "  %tnum = xor i1 %tnan, true"
lines [ # lines + 1 ] = "  %better = and i1 %tnum, %either"
else

lines [ # lines + 1 ] = "  %either = or i1 %tnan, %ordered"
lines [ # lines + 1 ] = "  %vnum = xor i1 %vnan, true"
lines [ # lines + 1 ] = "  %better = and i1 %vnum, %either"
end

return lines
end



local function elemental (
module ,
order ,
operation ,
element
) 
local t = ELEMENT_TYPES [ element ]
if t == nil then
error ( "no reducer state for element " .. element , 0 )
end
local total = t
local state = "{ " .. total .. ", i64, i64 }"
local stem = "nupp.reduce." .. order .. "." .. operation .. "." .. element
local a = ( builder . attributes ( module , "alwaysinline nounwind" ) )
local init = define ( module , stem .. ".init" , {
"define internal void @" .. stem .. ".init(ptr %state, " .. total .. " %initial) " .. a .. " {" ,
"  store " .. total .. " %initial, ptr %state" ,
"  %countp = getelementptr inbounds " .. state .. ", ptr %state, i32 0, i32 1" ,
"  store i64 0, ptr %countp" ,
"  %positionp = getelementptr inbounds " .. state .. ", ptr %state, i32 0, i32 2" ,
"  store i64 0, ptr %positionp" ,
"  ret void" ,
"}" ,
} )
local head = {
"define internal void @" .. stem .. ".add(ptr %state, " .. total .. " %value) " .. a .. " {" ,
"  %total = load " .. total .. ", ptr %state" ,
"  %countp = getelementptr inbounds " .. state .. ", ptr %state, i32 0, i32 1" ,
"  %positionp = getelementptr inbounds " .. state .. ", ptr %state, i32 0, i32 2" ,
}
local lines = head

local function add ( line ) 
lines [ # lines + 1 ] = "  " .. line
end

local result = total
local valueLines = { "  %total = load " .. total .. ", ptr %state" , "  ret " .. total .. " %total" }
if order == "exact" and element == "bool" then
if operation == "any" or operation == "all" then
add ( ("%%next = %s i1 %%total, %%value") : format ( operation == "any" and "or" or "and" ) )
add ( "store i1 %next, ptr %state" )
else
add ( "%count = load i64, ptr %countp" )
add ( "%one = zext i1 %value to i64" )
add ( "%more = add i64 %count, %one" )
add ( "store i64 %more, ptr %countp" )
result = "i64"
valueLines = {
"  %countp = getelementptr inbounds " .. state .. ", ptr %state, i32 0, i32 1" ,
"  %count = load i64, ptr %countp" ,
"  ret i64 %count" ,
}
end
elseif order == "exact" then
local instruction = ( { sum = "add" , product = "mul" , [ "and" ] = "and" , [ "or" ] = "or" , xor = "xor" } ) [ operation ]
if instruction == nil then
error ( "no exact reducer " .. operation , 0 )
end
add ( ("%%next = %s %s %%total, %%value") : format ( instruction , total ) )
add ( ("store %s %%next, ptr %%state") : format ( total ) )
elseif operation == "min" or operation == "max" then
if order == "integer" then
add ( ("%%better = icmp %s %s %%value, %%total") : format ( better ( element , operation ) , total ) )
else
for _ , line in ipairs ( floatBetter ( order , operation , total ) ) do
lines [ # lines + 1 ] = line
end
end
add ( ("%%next = select i1 %%better, %s %%value, %s %%total") : format ( total , total ) )
add ( ("store %s %%next, ptr %%state") : format ( total ) )
if order ~= "integer" then
valueLines = {
"  %total = load " .. total .. ", ptr %state" ,
"  %nan = fcmp uno " .. total .. " %total, 0.0" ,
"  %out = select i1 %nan, " .. total .. " " .. "0x7FF8000000000000" .. ", " .. total .. " %total" ,
"  ret " .. total .. " %out" ,
}
end
else


add ( "%count = load i64, ptr %countp" )
add ( "%more = add i64 %count, 1" )
add ( "store i64 %more, ptr %countp" )
add ( "%position = load i64, ptr %positionp" )
add ( "%first = icmp eq i64 %position, 0" )
if order == "integer" then
add ( ("%%better = icmp %s %s %%value, %%total") : format ( better ( element , operation ) , total ) )
else
for _ , line in ipairs ( floatBetter ( order , operation , total ) ) do
lines [ # lines + 1 ] = line
end
end
add ( "%take = or i1 %first, %better" )
add ( ("%%next = select i1 %%take, %s %%value, %s %%total") : format ( total , total ) )
add ( "%at = select i1 %take, i64 %more, i64 %position" )
add ( ("store %s %%next, ptr %%state") : format ( total ) )
add ( "store i64 %at, ptr %positionp" )
result = "double"
valueLines = {
"  %positionp = getelementptr inbounds " .. state .. ", ptr %state, i32 0, i32 2" ,
"  %position = load i64, ptr %positionp" ,
"  %out = uitofp i64 %position to double" ,
"  ret double %out" ,
}
end
lines [ # lines + 1 ] = "  ret void"
lines [ # lines + 1 ] = "}"
local addName = define ( module , stem .. ".add" , lines )
local skipName = nil
if operation == "argmin" or operation == "argmax" then


skipName = define ( module , stem .. ".skip" , {
"define internal void @" .. stem .. ".skip(ptr %state) " .. a .. " {" ,
"  %countp = getelementptr inbounds " .. state .. ", ptr %state, i32 0, i32 1" ,
"  %count = load i64, ptr %countp" ,
"  %more = add i64 %count, 1" ,
"  store i64 %more, ptr %countp" ,
"  ret void" ,
"}" ,
} )
end
local valueName = define ( module , stem .. ".value" , {
"define internal " .. result .. " @" .. stem .. ".value(ptr %state) " .. a .. " {" ,
table . concat ( valueLines , "\n" ) ,
"}"
} )

return init , addName , valueName , skipName
end



states.Operations = {} states.Operations.__index = states.Operations ;_G.nupp.__reflect.link(states.Operations,__nuppT1[1],{ })

















function states . operations (
module ,
order ,
operation ,
element
) 
if states . bare ( order ) then
return nil
elseif order == "pairwise" then
local product = operation == "product"
local scalar = ( element == "f32" and "float" or "double" )
local init , add , value = pairwise ( module , product and "fmul" or "fadd" , product and "1.0" or "0.0" , scalar )
return ( _G.setmetatable({ init =  init ,  add =  add ,  value =  value ,  input =  scalar ,  result =  scalar }, states.Operations) )
elseif order == "compensated" then
local scalar = ( element == "f32" and "float" or "double" )
local init , add , value = compensated ( module , scalar )
return ( _G.setmetatable({ init =  init ,  add =  add ,  value =  value ,  input =  scalar ,  result =  scalar }, states.Operations) )
end
if element == nil then
error ( "reducer " .. order .. " " .. operation .. " names no element" , 0 )
end
local init , add , value , skip = elemental ( module , order , operation , element )
local input = ELEMENT_TYPES [ element ]
local result = operation == "count" and "i64"
or ( operation == "argmin" or operation == "argmax" ) and "double"
or input

return ( _G.setmetatable({ init =  init ,  add =  add ,  value =  value ,  skip =  skip ,  input =  input ,  result =  result }, states.Operations) )
end

local __nuppExportValue= states ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.simd.states"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.simd.states"]=__nuppExports;return __nuppExports