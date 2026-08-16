_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);









local hash = require ( "nupp.compiler.build.hash" )







local methodslots = { }

local function fingerprint ( t , binders , active )
if not t then
return "nil"
end
local binder = binders [ t ]
if binder then
return binder
end
if active [ t ] then
return "@" .. ( t . runtimePath or t . name or t . tag )
end
active [ t ] = true
local tag = t . tag
local out
if tag == "nominal" then
out = "nominal(" .. tostring ( t . declKind ) .. ":" .. tostring ( t . runtimePath or t . name ) .. ")"
elseif tag == "array" or tag == "ptr" or tag == "const" then
out = tag .. "(" .. fingerprint ( t . elem or t . inner , binders , active ) .. ")"
elseif tag == "affine" or tag == "borrowed" or tag == "pinned" then
out = tag .. "(" .. fingerprint ( t . inner , binders , active ) .. ")"
elseif tag == "map" then
out = "map(" .. fingerprint (
t . key ,
binders ,
active
) .. ":" .. fingerprint (
t . value ,
binders ,
active
) .. ":" .. fingerprint ( t . writeKey , binders , active ) .. ":" .. fingerprint ( t . writeValue , binders , active ) .. ")"
elseif tag == "tuple" then
local parts = { }
for j , item in ipairs ( t . elems or { } ) do
parts [ j ] = fingerprint ( item , binders , active )
end
out = "tuple(" .. table . concat ( parts , "," ) .. ")"
elseif tag == "union" or tag == "intersection" then
local parts = { }
for j , item in ipairs ( t . members or { } ) do
parts [ j ] = fingerprint ( item , binders , active )
end
table . sort ( parts )
out = tag .. "(" .. table . concat ( parts , tag == "union" and "|" or "&" ) .. ")"
elseif tag == "shape" then
local parts = { }
for _ , field in ipairs ( t . fields or { } ) do
parts [
# parts + 1
] = field . name .. ":" .. fingerprint (
field . read ,
binders ,
active
) .. ":" .. fingerprint ( field . write , binders , active )
end
table . sort ( parts )
out = "shape(" .. table . concat ( parts , "," ) .. ")"
elseif tag == "literal" then
out = "literal(" .. tostring ( t . constant ) .. ":" .. fingerprint ( t . base , binders , active ) .. ")"
elseif tag == "func" then
local params = { }
for j , param in ipairs ( t . params or { } ) do
params [
j
] = tostring (
t . paramNames and t . paramNames [ j ] or ""
) .. "=" .. tostring (
t . paramModes and t . paramModes [ j ] or "plain"
) .. ":" .. fingerprint ( param , binders , active )
end
out = "fn(" .. table . concat ( params , "," ) .. ")"
else
out = tag or tostring ( t )
end
active [ t ] = nil

return out
end

local function packFingerprint ( ft , includeLabels )
local binders = { }
local generic = { }
for j , tv in ipairs ( ft . typeParams or { } ) do
binders [ tv ] = "$T" .. j
end
for j , pv in ipairs ( ft . packParams or { } ) do
binders [ pv ] = "$P" .. j
end
for j , tv in ipairs ( ft . typeParams or { } ) do
local bound = ft . typeBounds and ft . typeBounds [ j ] or nil
generic [ j ] = binders [ tv ] .. "<:" .. fingerprint ( bound , binders , { } )
end
local parts = { }
for j , param in ipairs ( ft . paramPack . head or { } ) do
parts [
j
] = tostring (
includeLabels and ft . paramNames and ft . paramNames [ j ] or ""
) .. "=" .. tostring (
ft . paramPack . modes and ft . paramPack . modes [ j ] or "plain"
) .. ":" .. fingerprint ( param , binders , { } )
end
local tail = ft . paramPack . tail
if tail then
if tail . kind == "homogeneous" then
parts [ # parts + 1 ] = "...:" .. fingerprint ( tail . type , binders , { } )
elseif tail . kind == "generic" then
parts [ # parts + 1 ] = "...:" .. ( binders [ tail . var ] or "$P" )
elseif tail . kind == "computed" then
parts [ # parts + 1 ] = "...:unpackof:" .. fingerprint ( tail . type , binders , { } )
else
parts [ # parts + 1 ] = "...:unknown"
end
end

return "<" .. table . concat ( generic , "," ) .. ">(" .. table . concat ( parts , "," ) .. ")"
end



function methodslots . member ( name , ft )
return "__nupp_m_" .. hash . digest ( name .. ":" .. packFingerprint ( ft , true ) )
end


function methodslots . parameters ( ft )
return packFingerprint ( ft , true )
end



function methodslots . unlabeledParameters ( ft )
return packFingerprint ( ft , false )
end

return methodslots
