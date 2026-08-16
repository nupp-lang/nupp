_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);









local T = require ( "nupp.compiler.types" )

local fixed = { }

local VALUE = { float = true , int32 = true , uint32 = true }
local STORAGE_ONLY = { int8 = true , int16 = true , uint8 = true , uint16 = true }
local PHYSICAL = {
float = true ,
int8 = true ,
int16 = true ,
int32 = true ,
int64 = true ,
uint8 = true ,
uint16 = true ,
uint32 = true ,
uint64 = true ,
}

function fixed . isValue ( t )
return t ~= nil and VALUE [ T . unwrapOwnership ( t ) . tag ] == true
end

function fixed . isStorageOnly ( t )
return t ~= nil and STORAGE_ONLY [ T . unwrapOwnership ( t ) . tag ] == true
end




function fixed . storageOnlyValue ( t , seen )
if not t then
return nil
end
local raw = T . unwrapOwnership ( t )
if STORAGE_ONLY [ raw . tag ] then
return raw
end
if raw . tag == "ptr" or raw . tag == "carray" or raw . tag == "ctype" or raw . tag == "const" then
return nil
end
seen = seen or { }
if seen [ raw . id ] then
return nil
end
seen [ raw . id ] = true
if raw . tag == "nominal" then
local origin = ( raw . origin or raw )
if raw . declKind == "struct" or origin . moduleName == "nupp.span" then
return nil
end
for _ , name in ipairs ( raw . fieldOrder or { } ) do
local found = fixed . storageOnlyValue ( raw . byname and raw . byname [ name ] , seen )
if found then
return found
end
end
elseif raw . tag == "func" then
for _ , value in ipairs ( raw . params or { } ) do
local found = fixed . storageOnlyValue ( value , seen )
if found then
return found
end
end
for _ , value in ipairs ( raw . rets or { } ) do
local found = fixed . storageOnlyValue ( value , seen )
if found then
return found
end
end
elseif raw . tag == "array" then
return fixed . storageOnlyValue ( raw . elem , seen )
elseif raw . tag == "map" then
return fixed . storageOnlyValue ( raw . value , seen ) or fixed . storageOnlyValue ( raw . writeValue , seen )
elseif raw . tag == "tuple" then
for _ , value in ipairs ( raw . elems or { } ) do
local found = fixed . storageOnlyValue ( value , seen )
if found then
return found
end
end
elseif raw . tag == "union" or raw . tag == "intersection" then
for _ , value in ipairs ( raw . members or { } ) do
local found = fixed . storageOnlyValue ( value , seen )
if found then
return found
end
end
elseif raw . tag == "shape" then
for _ , field in ipairs ( raw . fields or { } ) do
local found = fixed . storageOnlyValue ( field . read or field . write or field . type , seen )
if found then
return found
end
end
end

return nil
end

function fixed . isPhysical ( t )
return t ~= nil and PHYSICAL [ T . unwrapOwnership ( t ) . tag ] == true
end




function fixed . requiresTrust ( t , seen )
if not t then
return false
end
local raw = T . unwrapOwnership ( t )
if raw . tag ~= "nominal" or raw . declKind ~= "record" then
return false
end
seen = seen or { }
if seen [ raw . id ] then
return false
end
seen [ raw . id ] = true
for _ , name in ipairs ( raw . fieldOrder or { } ) do
local field = raw . byname and raw . byname [ name ] or nil
if fixed . isValue ( field ) or fixed . requiresTrust ( field , seen ) then
return true
end
end

return false
end


function fixed . loaded ( t )
local raw = T . unwrapOwnership ( t )
if raw . tag == "int8" or raw . tag == "int16" then
return T . int32
elseif raw . tag == "uint8" or raw . tag == "uint16" then
return T . uint32
end

return raw
end

local function numeric ( t )
local raw = T . unwrapOwnership ( t )
if raw == T . any then
return true
end
if raw . tag == "literal" then
return raw . base == T . number or raw . base == T . integer
end
if raw . tag == "union" then
for _ , member in ipairs ( raw . members ) do
if not numeric ( member ) then
return false
end
end
return true
end

return raw . tag == "number" or raw . tag == "integer" or PHYSICAL [ raw . tag ] == true
end




function fixed . physicalStoreAccepts ( source , target )
local rawTarget = T . unwrapOwnership ( target )
if not PHYSICAL [ rawTarget . tag ] then
return nil
end

return numeric ( source )
end

local MIN_NORMAL_F32 = 2 ^ - 126
local MIN_SUBNORMAL_F32 = 2 ^ - 149

local function exactFloat ( value )
if value ~= value or value == math . huge or value == - math . huge or value == 0 then
return true
end
local magnitude = math . abs ( value )
if magnitude < MIN_NORMAL_F32 then
local units = magnitude / MIN_SUBNORMAL_F32
return units >= 1 and units <= 8388607 and units % 1 == 0
end
local significand , exponent = math . frexp ( magnitude )
if exponent > 128 then
return false
end
local units = significand * 16777216

return units % 1 == 0
end



function fixed . literalFits ( value , target )
local tag = T . unwrapOwnership ( target ) . tag
if tag == "float" then
return exactFloat ( value )
elseif tag == "int32" then
return value % 1 == 0 and value >= - 2147483648 and value < 2147483648
elseif tag == "uint32" then
return value % 1 == 0 and value >= 0 and value < 4294967296
else
return false
end
end

function fixed . widenedName ( t )
local tag = T . unwrapOwnership ( t ) . tag
if tag == "float" then
return "number"
elseif tag == "int32" or tag == "uint32" then
return "integer"
else
return nil
end
end

function fixed . conversionPath ( t )
local tag = T . unwrapOwnership ( t ) . tag
if tag == "float" then
return "nupp.math.f32.narrow"
elseif tag == "int32" then
return "nupp.math.i32.wrap"
elseif tag == "uint32" then
return "nupp.math.u32.wrap"
else
return nil
end
end

return fixed
