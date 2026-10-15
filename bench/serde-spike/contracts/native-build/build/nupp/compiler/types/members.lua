_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()
















local T = require ( "nupp.compiler.types" )

local members = { }





function members . constRead ( t ) 
local tag = t . tag
if tag == "union" then
local wrapped = { }
for j , member in ipairs ( ( t ) . members ) do
wrapped [ j ] = members . constRead ( member )
end
return T . union ( wrapped )
end
if tag == "shape" or tag == "nominal" or tag == "array" or tag == "map" or tag == "tuple" then
return T . constOf ( t )
end

return t
end























local function empty ( ) 
return { ordered = { } , byname = { } }
end

local function definitions ( entry ) 
if entry . definitions then
local out = { }
for j , definition in ipairs ( entry . definitions ) do
out [ j ] = definition
end
return out
end

return entry . definition and { entry . definition } or { }
end

local function orderedNames ( byname , writeByname , preferred ) 
local seen , names = { } , { }
for _ , name in ipairs ( preferred or { } ) do
if ( byname [ name ] or writeByname [ name ] ) and not seen [ name ] then
seen [ name ] = true
names [ # names + 1 ] = name
end
end
local remaining = { }
for name in pairs ( byname ) do
if not seen [ name ] then
seen [ name ] = true
remaining [ # remaining + 1 ] = name
end
end
for name in pairs ( writeByname ) do
if not seen [ name ] then
seen [ name ] = true
remaining [ # remaining + 1 ] = name
end
end
table . sort ( remaining )
for _ , name in ipairs ( remaining ) do
names [ # names + 1 ] = name
end

return names
end



local build
















local lookup



local function directEntry ( t , name ) 
local readType = t . byname and t . byname [ name ] or nil
local writeType = t . writeByname and t . writeByname [ name ] or nil
if not readType and not writeType then
return nil
end
local readDefinition , writeDefinition = nil , nil
if t . tag == "nominal" then
readDefinition = t . fieldDefs and t . fieldDefs [ name ] or nil
writeDefinition = t . writeFieldDefs and t . writeFieldDefs [ name ] or nil
end
local defs = { }
if readDefinition then
defs [ # defs + 1 ] = readDefinition
end
if writeDefinition and writeDefinition ~= readDefinition then
defs [ # defs + 1 ] = writeDefinition
end

return {
name = name ,
readType = readType ,
writeType = writeType ,
declarationKind = t . tag == "nominal" and t . declKind or "shape" ,
definition = defs [ 1 ] ,
definitions = # defs > 1 and defs or nil ,
annotations = readDefinition and readDefinition . annotations
or writeDefinition and writeDefinition . annotations
or { }
}
end



local function intersectionEntry ( t , name ) 
local reads , writes , defs = { } , { } , { }
local present = false
for _ , part in ipairs ( t . members ) do
local one = lookup ( part , name )
if one then
present = true
if one . readType then
reads [ # reads + 1 ] = one . readType
end
if one . writeType then
writes [ # writes + 1 ] = one . writeType
end
for _ , definition in ipairs ( definitions ( one ) ) do
defs [ # defs + 1 ] = definition
end
end
end
if not present then
return nil
end

return {
name = name ,
readType = # reads > 0 and T . intersection ( reads ) or nil ,
writeType = # writes > 0 and T . union ( writes ) or nil ,
declarationKind = "intersection" ,
definition = defs [ 1 ] ,
definitions = # defs > 1 and defs or nil ,
annotations = { }
}
end


















local function joinedMethod ( owner , signatures ) 
local first = signatures [ 1 ]
if not first
or first . tag ~= "func"
or first . vararg
or first . typeParams
or first . packParams
or first . constParams
or first . paramPack . tail
or first . paramPack . alternatives
or first . retPack . tail
or first . retPack . alternatives
or first . yieldPack
or first . resumePack
or first . predicate
or first . borrowsParam
or first . borrowsSelf
or first . borrowsParams
or first . borrowsResult
or first . preservesResults
or first . explicitPreserves
or first . ffiOut
or first . partitionResults
or # first . params < 1
then
return nil
end
if not ( first . paramNames and first . paramNames [ 1 ] == "self" ) then
return nil
end
local noYield , sendable , noreturn = true , true , true
for _ , signature in ipairs ( signatures ) do
local one = signature
if one . tag ~= "func"
or one . vararg
or one . typeParams
or one . packParams
or one . constParams
or one . paramPack . tail
or one . paramPack . alternatives
or one . retPack . tail
or one . retPack . alternatives
or one . yieldPack
or one . resumePack
or one . predicate
or one . borrowsParam
or one . borrowsSelf
or one . borrowsParams
or one . borrowsResult
or one . preservesResults
or one . explicitPreserves
or one . ffiOut
or one . partitionResults
or # one . params ~= # first . params
or # one . rets ~= # first . rets
or one . foreign ~= first . foreign
or one . comptimeOnly ~= first . comptimeOnly
or not ( one . paramNames and one . paramNames [ 1 ] == "self" )
then
return nil
end
for j = 1 , # first . params do
if one . paramModes [ j ] ~= first . paramModes [ j ] or one . paramNames [ j ] ~= first . paramNames [ j ] then
return nil
end
end
noYield = noYield and one . noYield == true
sendable = sendable and one . sendable == true
noreturn = noreturn and one . noreturn == true
end
local params = { owner }
local rets = { }
for j = 2 , # first . params do
local alternatives = { }
for _ , signature in ipairs ( signatures ) do
alternatives [ # alternatives + 1 ] = ( signature ) . params [ j ]
end
params [ j ] = T . intersection ( alternatives )
end
for j = 1 , # first . rets do
local alternatives = { }
for _ , signature in ipairs ( signatures ) do
alternatives [ # alternatives + 1 ] = ( signature ) . rets [ j ]
end
rets [ j ] = T . union ( alternatives )
end

return T . funcWith ( first , {
params = params ,
rets = rets ,
paramPack = T . pack ( params , nil , first . paramModes ) ,
retPack = T . pack ( rets ) ,
noYield = noYield or false ,
sendable = sendable or false ,
noreturn = noreturn or false ,
} )
end





local function unionEntry ( t , name ) 
if not t . members [ 1 ] or not lookup ( t . members [ 1 ] , name ) then
return nil
end
local reads , writes , defs = { } , { } , { }
local allRead , allWrite = true , true
for _ , part in ipairs ( t . members ) do
local one = lookup ( part , name )
if not one or not one . readType then
allRead = false
else
reads [ # reads + 1 ] = one . readType
end
if not one or not one . writeType then
allWrite = false
else
writes [ # writes + 1 ] = one . writeType
end
if one then
for _ , definition in ipairs ( definitions ( one ) ) do
defs [ # defs + 1 ] = definition
end
end
end
if not allRead and not allWrite then
return nil
end

local joined = allRead and # reads == # t . members and joinedMethod ( t , reads ) or nil

return {
name = name ,
readType = joined or ( allRead and T . union ( reads ) or nil ) ,
writeType = allWrite and T . intersection ( writes ) or nil ,
declarationKind = "union" ,
definition = defs [ 1 ] ,
definitions = # defs > 1 and defs or nil ,
annotations = { }
}
end

local function direct ( t ) 
local out = ( { ordered = { } , byname = { } } )
local preferred = { }
if t . tag == "nominal" then
preferred = t . fieldOrder or { }
else
for _ , field in ipairs ( t . fields or { } ) do
preferred [ # preferred + 1 ] = field . name
end
end
for _ , name in ipairs ( orderedNames ( t . byname or { } , t . writeByname or { } , preferred ) ) do
local entry = directEntry ( t , name )
if entry then
out . ordered [ # out . ordered + 1 ] = entry
out . byname [ name ] = entry
end
end
if t . indexReadKey and t . indexReadValue then
out . readIndexer = { keyType = t . indexReadKey , valueType = t . indexReadValue }
end
if t . indexWriteKey and t . indexWriteValue then
out . writeIndexer = { keyType = t . indexWriteKey , valueType = t . indexWriteValue }
end

return out
end

local function mergeIntersection ( t , memo ) 
local out = ( { ordered = { } , byname = { } } )
local present = { }
local readKeys , readValues , writeKeys , writeValues = { } , { } , { } , { }
for _ , part in ipairs ( t . members ) do
local one = build ( part , memo )
for _ , entry in ipairs ( one . ordered ) do
present [ entry . name ] = true
end
if one . readIndexer then
readKeys [ # readKeys + 1 ] = one . readIndexer . keyType
readValues [ # readValues + 1 ] = one . readIndexer . valueType
end
if one . writeIndexer then
writeKeys [ # writeKeys + 1 ] = one . writeIndexer . keyType
writeValues [ # writeValues + 1 ] = one . writeIndexer . valueType
end
end
local names = { }
for name in pairs ( present ) do
names [ # names + 1 ] = name
end
table . sort ( names )
for _ , name in ipairs ( names ) do
local entry = intersectionEntry ( t , name )
if entry then
out . ordered [ # out . ordered + 1 ] = entry
out . byname [ name ] = entry
end
end
if # readKeys > 0 then
out . readIndexer = { keyType = T . union ( readKeys ) , valueType = T . intersection ( readValues ) }
end
if # writeKeys > 0 then
out . writeIndexer = { keyType = T . union ( writeKeys ) , valueType = T . union ( writeValues ) }
end

return out
end

local function mergeUnion ( t , memo ) 
local out = ( { ordered = { } , byname = { } } )
local first = t . members [ 1 ] and build ( t . members [ 1 ] , memo ) or ( { ordered = { } , byname = { } } )
for _ , candidate in ipairs ( first . ordered ) do
local entry = unionEntry ( t , candidate . name )
if entry then
out . ordered [ # out . ordered + 1 ] = entry
out . byname [ entry . name ] = entry
end
end
local readKeys , readValues , writeKeys , writeValues = { } , { } , { } , { }
local allReadIndexer , allWriteIndexer = # t . members > 0 , # t . members > 0
for _ , part in ipairs ( t . members ) do
local one = build ( part , memo )
if one . readIndexer then
readKeys [ # readKeys + 1 ] = one . readIndexer . keyType
readValues [ # readValues + 1 ] = one . readIndexer . valueType
else
allReadIndexer = false
end
if one . writeIndexer then
writeKeys [ # writeKeys + 1 ] = one . writeIndexer . keyType
writeValues [ # writeValues + 1 ] = one . writeIndexer . valueType
else
allWriteIndexer = false
end
end
if allReadIndexer then
out . readIndexer = { keyType = T . intersection ( readKeys ) , valueType = T . union ( readValues ) }
end
if allWriteIndexer then
out . writeIndexer = { keyType = T . intersection ( writeKeys ) , valueType = T . intersection ( writeValues ) }
end

return out
end

build = function ( t , memo ) 
local cached = memo [ t ]
if cached then
return cached
end
t = T . unwrapOwnership ( t )
cached = memo [ t ]
if cached then
return cached
end
local out
if t . tag == "ptr" then
out = build ( t . elem , memo )
elseif t . tag == "literal" then
out = build ( t . base , memo )
elseif t . tag == "typevar" and t . bound then
out = build ( t . bound , memo )
elseif t . tag == "neutral" and t . op == "comptimeCall" and t . comptimeBound then
out = build ( t . comptimeBound , memo )
elseif t . tag == "shape" or t . tag == "nominal" then
out = direct ( t )
elseif t . tag == "intersection" then
out = mergeIntersection ( t , memo )
elseif t . tag == "union" then
out = mergeUnion ( t , memo )
elseif t . tag == "const" then
local inner = build ( t . inner , memo )
out = ( { ordered = { } , byname = { } } )
for _ , source in ipairs ( inner . ordered ) do
local entry = {
name = source . name ,
readType = source . readType and members . constRead ( source . readType ) or nil ,
declarationKind = source . declarationKind ,
definition = source . definition ,
definitions = source . definitions ,
annotations = source . annotations
}
out . ordered [ # out . ordered + 1 ] = entry
out . byname [ entry . name ] = entry
end
if inner . readIndexer then
out . readIndexer = {
keyType = inner . readIndexer . keyType ,
valueType = members . constRead ( inner . readIndexer . valueType ) ,
}
end
elseif t . tag == "map" then
out = ( { ordered = { } , byname = { } } )
if t . readable then
out . readIndexer = { keyType = t . key , valueType = t . value }
end
if t . writeKey and t . writeValue then
out . writeIndexer = { keyType = t . writeKey , valueType = t . writeValue }
end
else
out = ( { ordered = { } , byname = { } } )
end
memo [ t ] = out

return out
end

function members . view ( t ) 
return build ( t , { } )
end

lookup = function ( t , name ) 
t = T . unwrapOwnership ( t )
local tag = t . tag
if tag == "ptr" then
return lookup ( ( t ) . elem , name )
elseif tag == "literal" then
return lookup ( ( t ) . base , name )
elseif tag == "typevar" and ( t ) . bound then
return lookup ( ( t ) . bound , name )
elseif tag == "neutral" and ( t ) . op == "comptimeCall" and ( t ) . comptimeBound then
return lookup ( ( t ) . comptimeBound , name )
elseif tag == "shape" or tag == "nominal" then
return directEntry ( t , name )
elseif tag == "intersection" then
return intersectionEntry ( t , name )
elseif tag == "union" then
return unionEntry ( t , name )
elseif tag == "const" then

local inner = lookup ( ( t ) . inner , name )
if not inner then
return nil
end

return {
name = inner . name ,
readType = inner . readType and members . constRead ( inner . readType ) or nil ,
declarationKind = inner . declarationKind ,
definition = inner . definition ,
definitions = inner . definitions ,
annotations = inner . annotations
}
end



return nil
end

members . lookup = lookup




function members . fingerprint ( t , typeFingerprint ) 
local one = members . view ( t )
local parts = { }
for _ , entry in ipairs ( one . ordered ) do
parts [
# parts + 1
] = entry . name .. ":r=" .. (
entry . readType and typeFingerprint ( entry . readType ) or "-"
) .. ":w=" .. ( entry . writeType and typeFingerprint ( entry . writeType ) or "-" )
end
if one . readIndexer then
parts [
# parts + 1
] = "[r=" .. typeFingerprint (
one . readIndexer . keyType
) .. ":" .. typeFingerprint ( one . readIndexer . valueType ) .. "]"
end
if one . writeIndexer then
parts [
# parts + 1
] = "[w=" .. typeFingerprint (
one . writeIndexer . keyType
) .. ":" .. typeFingerprint ( one . writeIndexer . valueType ) .. "]"
end

return table . concat ( parts , "," )
end

local __nuppExportValue= members ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.types.members"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.types.members"]=__nuppExports;return __nuppExports