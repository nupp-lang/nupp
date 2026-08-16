_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);














local T = require ( "nupp.compiler.types" )

local members = { }























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

local function direct ( t )
local out = empty ( )
local readByname = t . byname or { }
local writeByname = t . writeByname or { }
local preferred = { }
if t . tag == "nominal" then
preferred = t . fieldOrder or { }
else
for _ , field in ipairs ( t . fields or { } ) do
preferred [ # preferred + 1 ] = field . name
end
end
for _ , name in ipairs ( orderedNames ( readByname , writeByname , preferred ) ) do
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
local entry = {
name = name ,
readType = readByname [ name ] ,
writeType = writeByname [ name ] ,
declarationKind = t . tag == "nominal" and t . declKind or "shape" ,
definition = defs [ 1 ] ,
definitions = # defs > 1 and defs or nil ,
annotations = readDefinition
and readDefinition . annotations
or writeDefinition
and writeDefinition . annotations
or { }
}
out . ordered [ # out . ordered + 1 ] = entry
out . byname [ name ] = entry
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
local out = empty ( )
local reads , writes , defs = { } , { } , { }
local readKeys , readValues , writeKeys , writeValues = { } , { } , { } , { }
for _ , part in ipairs ( t . members ) do
local one = build ( part , memo )
for _ , entry in ipairs ( one . ordered ) do
local rs = reads [ entry . name ] or { }
local ws = writes [ entry . name ] or { }
if entry . readType then
rs [ # rs + 1 ] = entry . readType
end
if entry . writeType then
ws [ # ws + 1 ] = entry . writeType
end
reads [ entry . name ] , writes [ entry . name ] = rs , ws
local ds = defs [ entry . name ] or { }
for _ , definition in ipairs ( definitions ( entry ) ) do
ds [ # ds + 1 ] = definition
end
defs [ entry . name ] = ds
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
for name in pairs ( reads ) do
names [ # names + 1 ] = name
end
table . sort ( names )
for _ , name in ipairs ( names ) do
local rs , ws , ds = reads [ name ] , writes [ name ] , defs [ name ]
local entry = {
name = name ,
readType = # rs > 0 and T . intersection ( rs ) or nil ,
writeType = # ws > 0 and T . union ( ws ) or nil ,
declarationKind = "intersection" ,
definition = ds [ 1 ] ,
definitions = # ds > 1 and ds or nil ,
annotations = { }
}
out . ordered [ # out . ordered + 1 ] = entry
out . byname [ name ] = entry
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
local out = empty ( )
local first = t . members [ 1 ] and build ( t . members [ 1 ] , memo ) or empty ( )
for _ , candidate in ipairs ( first . ordered ) do
local readTypes , writeTypes , defs = { } , { } , { }
local allRead , allWrite = true , true
for _ , part in ipairs ( t . members ) do
local entry = build ( part , memo ) . byname [ candidate . name ]
if not entry or not entry . readType then
allRead = false
else
readTypes [ # readTypes + 1 ] = entry . readType
end
if not entry or not entry . writeType then
allWrite = false
else
writeTypes [ # writeTypes + 1 ] = entry . writeType
end
if entry then
for _ , definition in ipairs ( definitions ( entry ) ) do
defs [ # defs + 1 ] = definition
end
end
end
if allRead or allWrite then
local entry = {
name = candidate . name ,
readType = allRead and T . union ( readTypes ) or nil ,
writeType = allWrite and T . intersection ( writeTypes ) or nil ,
declarationKind = "union" ,
definition = defs [ 1 ] ,
definitions = # defs > 1 and defs or nil ,
annotations = { }
}
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
out = empty ( )
for _ , source in ipairs ( inner . ordered ) do
local entry = {
name = source . name ,
readType = source . readType ,
declarationKind = source . declarationKind ,
definition = source . definition ,
definitions = source . definitions ,
annotations = source . annotations
}
out . ordered [ # out . ordered + 1 ] = entry
out . byname [ entry . name ] = entry
end
out . readIndexer = inner . readIndexer
elseif t . tag == "map" then
out = empty ( )
if t . readable then
out . readIndexer = { keyType = t . key , valueType = t . value }
end
if t . writeKey and t . writeValue then
out . writeIndexer = { keyType = t . writeKey , valueType = t . writeValue }
end
else
out = empty ( )
end
memo [ t ] = out

return out
end

function members . view ( t )
return build ( t , { } )
end















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
annotations = readDefinition
and readDefinition . annotations
or writeDefinition
and writeDefinition . annotations
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

return {
name = name ,
readType = allRead and T . union ( reads ) or nil ,
writeType = allWrite and T . intersection ( writes ) or nil ,
declarationKind = "union" ,
definition = defs [ 1 ] ,
definitions = # defs > 1 and defs or nil ,
annotations = { }
}
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
readType = inner . readType ,
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

return members
