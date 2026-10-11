_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()
local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.reducers\0runtime\0001") };




local reducers = { }

reducers.Contract = {} reducers.Contract.__index = reducers.Contract ;_G.nupp.__reflect.link(reducers.Contract,__nuppT1[1],{ })












const constructors

= {
[
"nupp.simd.reducer.wrappingSum"
] = _G.setmetatable({ recordName =
"WrappingSum" ,  order =
"exact" ,  operation =
"sum" ,  element =
"" ,  witnessed =
true ,  seeded =
true ,  result =
"" }, reducers.Contract)
,
[
"nupp.simd.reducer.wrappingProduct"
] = _G.setmetatable({ recordName =
"WrappingProduct" ,  order =
"exact" ,  operation =
"product" ,  element =
"" ,  witnessed =
true ,  seeded =
true ,  result =
"" }, reducers.Contract)
,
[
"nupp.simd.reducer.andBits"
] = _G.setmetatable({ recordName =
"AndBits" ,  order =
"exact" ,  operation =
"and" ,  element =
"" ,  witnessed =
true ,  seeded =
true ,  result =
"" }, reducers.Contract)
,
[
"nupp.simd.reducer.orBits"
] = _G.setmetatable({ recordName =
"OrBits" ,  order =
"exact" ,  operation =
"or" ,  element =
"" ,  witnessed =
true ,  seeded =
true ,  result =
"" }, reducers.Contract)
,
[
"nupp.simd.reducer.xorBits"
] = _G.setmetatable({ recordName =
"XorBits" ,  order =
"exact" ,  operation =
"xor" ,  element =
"" ,  witnessed =
true ,  seeded =
true ,  result =
"" }, reducers.Contract)
,
[
"nupp.simd.reducer.any"
] = _G.setmetatable({ recordName =
"Any" ,  order =
"exact" ,  operation =
"any" ,  element =
"bool" ,  witnessed =
false ,  seeded =
false ,  result =
"bool" }, reducers.Contract)
,
[
"nupp.simd.reducer.all"
] = _G.setmetatable({ recordName =
"All" ,  order =
"exact" ,  operation =
"all" ,  element =
"bool" ,  witnessed =
false ,  seeded =
false ,  result =
"bool" }, reducers.Contract)
,
[
"nupp.simd.reducer.count"
] = _G.setmetatable({ recordName =
"Count" ,  order =
"exact" ,  operation =
"count" ,  element =
"bool" ,  witnessed =
false ,  seeded =
false ,  result =
"u64" }, reducers.Contract)
,
[
"nupp.simd.reducer.integerMin"
] = _G.setmetatable({ recordName =
"IntegerMin" ,  order =
"integer" ,  operation =
"min" ,  element =
"" ,  witnessed =
true ,  seeded =
true ,  result =
"" }, reducers.Contract)
,
[
"nupp.simd.reducer.integerMax"
] = _G.setmetatable({ recordName =
"IntegerMax" ,  order =
"integer" ,  operation =
"max" ,  element =
"" ,  witnessed =
true ,  seeded =
true ,  result =
"" }, reducers.Contract)
,
[
"nupp.simd.reducer.integerArgMin"
] = _G.setmetatable({ recordName =
"IntegerArgMin" ,  order =
"integer" ,  operation =
"argmin" ,  element =
"" ,  witnessed =
true ,  seeded =
false ,  result =
"f64" }, reducers.Contract)
,
[
"nupp.simd.reducer.integerArgMax"
] = _G.setmetatable({ recordName =
"IntegerArgMax" ,  order =
"integer" ,  operation =
"argmax" ,  element =
"" ,  witnessed =
true ,  seeded =
false ,  result =
"f64" }, reducers.Contract)
,
[
"nupp.simd.reducer.propagatingMin"
] = _G.setmetatable({ recordName =
"PropagatingMin" ,  order =
"propagating" ,  operation =
"min" ,  element =
"f64" ,  witnessed =
false ,  seeded =
true ,  result =
"f64" }, reducers.Contract)
,
[
"nupp.simd.reducer.propagatingMax"
] = _G.setmetatable({ recordName =
"PropagatingMax" ,  order =
"propagating" ,  operation =
"max" ,  element =
"f64" ,  witnessed =
false ,  seeded =
true ,  result =
"f64" }, reducers.Contract)
,
[
"nupp.simd.reducer.propagatingArgMin"
] = _G.setmetatable({ recordName =
"PropagatingArgMin" ,  order =
"propagating" ,  operation =
"argmin" ,  element =
"f64" ,  witnessed =
false ,  seeded =
false ,  result =
"f64" }, reducers.Contract)
,
[
"nupp.simd.reducer.propagatingArgMax"
] = _G.setmetatable({ recordName =
"PropagatingArgMax" ,  order =
"propagating" ,  operation =
"argmax" ,  element =
"f64" ,  witnessed =
false ,  seeded =
false ,  result =
"f64" }, reducers.Contract)
,
[
"nupp.simd.reducer.numberMin"
] = _G.setmetatable({ recordName =
"NumberMin" ,  order =
"number" ,  operation =
"min" ,  element =
"f64" ,  witnessed =
false ,  seeded =
true ,  result =
"f64" }, reducers.Contract)
,
[
"nupp.simd.reducer.numberMax"
] = _G.setmetatable({ recordName =
"NumberMax" ,  order =
"number" ,  operation =
"max" ,  element =
"f64" ,  witnessed =
false ,  seeded =
true ,  result =
"f64" }, reducers.Contract)
,
[
"nupp.simd.reducer.numberArgMin"
] = _G.setmetatable({ recordName =
"NumberArgMin" ,  order =
"number" ,  operation =
"argmin" ,  element =
"f64" ,  witnessed =
false ,  seeded =
false ,  result =
"f64" }, reducers.Contract)
,
[
"nupp.simd.reducer.numberArgMax"
] = _G.setmetatable({ recordName =
"NumberArgMax" ,  order =
"number" ,  operation =
"argmax" ,  element =
"f64" ,  witnessed =
false ,  seeded =
false ,  result =
"f64" }, reducers.Contract)
,
}

reducers . CONSTRUCTORS = constructors






const floatingConstructors = { }

for _ , entry in ipairs ( {
{ "orderedSum" , "OrderedSum" , "ordered" , "sum" } ,
{ "pairwiseSum" , "PairwiseSum" , "pairwise" , "sum" } ,
{ "compensatedSum" , "CompensatedSum" , "compensated" , "sum" } ,
{ "algebraicSum" , "AlgebraicSum" , "algebraic" , "sum" } ,
{ "orderedProduct" , "OrderedProduct" , "ordered" , "product" } ,
{ "pairwiseProduct" , "PairwiseProduct" , "pairwise" , "product" } ,
{ "algebraicProduct" , "AlgebraicProduct" , "algebraic" , "product" } ,
{ "orderedDot" , "OrderedDot" , "ordered" , "dot" } ,
{ "pairwiseDot" , "PairwiseDot" , "pairwise" , "dot" } ,
{ "algebraicDot" , "AlgebraicDot" , "algebraic" , "dot" } ,
} ) do
floatingConstructors [
"nupp.simd.reducer." .. entry [ 1 ]
] = _G.setmetatable({ recordName =
entry [ 2 ] ,  order =
entry [ 3 ] ,  operation =
entry [ 4 ] ,  element =
"f64" ,  witnessed =
false ,  seeded =
true ,  result =
"f64" }, reducers.Contract)

end

reducers . FLOATING = floatingConstructors



function reducers . floatingOrder ( order ) 
return order == "ordered"
or order == "pairwise"
or order == "algebraic"
or order == "compensated"
or order == "propagating"
or order == "number"
end

function reducers . typeName ( order , operation , element ) 
return "simd_reducer_" .. order .. "_" .. operation .. "_" .. element
end

function reducers . parse ( name ) 
return name : match ( "^simd_reducer_(%a+)_(%a+)_(%w+)$" )
end

function reducers . valid ( order , operation , element ) 
local integer = element == "i32" or element == "u32" or element == "i64" or element == "u64"
if order == "exact" then
return integer
and (
operation == "sum"
or operation == "product"
or operation == "and"
or operation == "or"
or operation == "xor"
)
or element == "bool" and ( operation == "any" or operation == "all" or operation == "count" )
end

local floating = element == "f64" or element == "f32"
if order == "ordered" or order == "pairwise" or order == "algebraic" then
return floating and ( operation == "sum" or operation == "product" or operation == "dot" )
elseif order == "compensated" then
return floating and operation == "sum"
end

return ( order == "integer" and integer or ( order == "number" or order == "propagating" ) and floating )
and ( operation == "min" or operation == "max" or operation == "argmin" or operation == "argmax" )
end

function reducers . result ( operation , element ) 
return operation == "count" and "u64" or ( operation == "argmin" or operation == "argmax" ) and "f64" or element
end


function reducers . input ( name , order , operation ) 
local namedOrder , namedOperation , element = reducers . parse ( name )
if element ~= nil then
if namedOrder == order and namedOperation == operation and reducers . valid ( order , operation , element ) then
return element
end
return nil
end
if name == "simd_reducer_" .. order .. "_" .. operation
and (
( order == "ordered" or order == "pairwise" or order == "algebraic" )
and ( operation == "sum" or operation == "product" or operation == "dot" )
or order == "compensated" and operation == "sum"
)
then
return "f64"
end

return nil
end




function reducers . parallel ( order ) 
return order == "algebraic" or order == "exact"
end

local __nuppExportValue= reducers ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.reducers"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.reducers"]=__nuppExports;return __nuppExports