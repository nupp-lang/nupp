_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()











local hash = require ( "nupp.compiler.hash" )







local methodslots = { }

local fingerprint

local function constFingerprint ( term , binders , active ) 
if not term then
return "nil"
end
local binder = binders [ term ]
if binder then
return binder
elseif term . tag == "constLiteral" then
local value = tostring ( term . value )
return "literal(" .. tostring (
# term . domain
) .. ":" .. term . domain .. ":" .. tostring ( # value ) .. ":" .. value .. ")"
elseif term . tag == "constVar" then
return "constvar(" .. tostring ( term . domain ) .. ":" .. tostring ( term . name ) .. ")"
elseif term . tag == "constOp" then
local parts = { }
for index , operand in ipairs ( term . operands or { } ) do
parts [ index ] = constFingerprint ( operand , binders , active )
end
return "constop(" .. tostring ( term . operation ) .. ":" .. table . concat ( parts , "," ) .. ")"
end

return tostring ( term . tag )
end

local function valuePackFingerprint ( pack , binders , active ) 
if not pack then
return "nil"
end
local binder = binders [ pack ]
if binder then
return binder
end
local alternatives = { }
for index , alternative in ipairs ( pack . alternatives or { } ) do
alternatives [ index ] = valuePackFingerprint ( alternative , binders , active )
end
if # alternatives > 0 then
table . sort ( alternatives )
return "packs(" .. table . concat ( alternatives , "|" ) .. ")"
end
local parts = { }
for index , item in ipairs ( pack . head or { } ) do
parts [
index
] = tostring ( pack . modes and pack . modes [ index ] or "plain" ) .. ":" .. fingerprint ( item , binders , active )
end
local tail = pack . tail
if tail then
if tail . kind == "generic" then
parts [ # parts + 1 ] = "...:" .. ( binders [ tail . var ] or "$P" )
else
parts [ # parts + 1 ] = "...:" .. tostring ( tail . kind ) .. ":" .. fingerprint ( tail . type , binders , active )
end
end

return "pack(" .. table . concat ( parts , "," ) .. ")"
end

fingerprint = function ( t , binders , active ) 
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
local origin = t . origin or t
local arguments = { }
for index , argument in ipairs ( t . typeArgs or { } ) do
arguments [ # arguments + 1 ] = "type" .. tostring ( index ) .. ":" .. fingerprint ( argument , binders , active )
end
for index , argument in ipairs ( t . packArgs or { } ) do
arguments [
# arguments + 1
] = "pack" .. tostring ( index ) .. ":" .. valuePackFingerprint ( argument , binders , active )
end
for index , argument in ipairs ( t . constArgs or { } ) do
arguments [ # arguments + 1 ] = "const" .. tostring ( index ) .. ":" .. constFingerprint ( argument , binders , active )
end
out = "nominal(" .. tostring (
t . declKind
) .. ":" .. tostring (
origin . runtimePath or origin . moduleName and ( origin . moduleName .. "." .. origin . name ) or origin . name
) .. "<" .. table . concat ( arguments , "," ) .. ">)"
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
local constant = tostring ( t . constant )
out = "literal(" .. tostring ( # constant ) .. ":" .. constant .. ":" .. fingerprint ( t . base , binders , active ) .. ")"
elseif tag == "carray" then
out = "carray(" .. fingerprint (
t . elem ,
binders ,
active
) .. ":" .. constFingerprint ( t . countTerm , binders , active ) .. ")"
elseif tag == "constrained" then
out = "constrained(" .. fingerprint ( t . base , binders , active ) .. ":" .. tostring ( t . constraintKey ) .. ")"
elseif tag == "ctype" or tag == "metatable" or tag == "typeobject" then
out = tag .. "(" .. fingerprint ( t . of , binders , active ) .. ")"
elseif tag == "func" then
local nested = { }
for key , value in pairs ( binders ) do
nested [ key ] = value
end
for index , tv in ipairs ( t . typeParams or { } ) do
nested [ tv ] = "$T" .. tostring ( index )
end
for index , pv in ipairs ( t . packParams or { } ) do
nested [ pv ] = "$P" .. tostring ( index )
end
for index , cv in ipairs ( t . constParams or { } ) do
nested [ cv ] = "$C" .. tostring ( index )
end
local params = { }
for j , param in ipairs ( t . params or { } ) do
params [
j
] = tostring (
t . paramNames and t . paramNames [ j ] or ""
) .. "=" .. tostring (
t . paramModes and t . paramModes [ j ] or "plain"
) .. ":" .. fingerprint ( param , nested , active )
end
local returns = { }
for index , returned in ipairs ( t . rets or { } ) do
returns [ index ] = fingerprint ( returned , nested , active )
end
out = "fn(" .. table . concat ( params , "," ) .. ")->(" .. table . concat ( returns , "," ) .. ")"
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
for j , cv in ipairs ( ft . constParams or { } ) do
binders [ cv ] = "$C" .. j
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
return "__nupp_m_" .. hash . sha256 ( name .. ":" .. packFingerprint ( ft , true ) )
end


function methodslots . parameters ( ft ) 
return packFingerprint ( ft , true )
end



function methodslots . unlabeledParameters ( ft ) 
return packFingerprint ( ft , false )
end

local __nuppExportValue= methodslots ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.lua.methodslots"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.lua.methodslots"]=__nuppExports;return __nuppExports