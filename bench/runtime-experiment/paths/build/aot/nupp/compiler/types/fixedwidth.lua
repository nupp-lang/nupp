_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()











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
if raw . declKind == "struct"
or origin . moduleName == "nupp.mem.span"
or origin . moduleName == "nupp.simd"
or origin . sealedModule == "nupp.simd"
then
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
local found = fixed . storageOnlyValue ( field . read , seen )
or fixed . storageOnlyValue ( field . write , seen )
or fixed . storageOnlyValue ( field . type , seen )
if found then
return found
end
end
return fixed . storageOnlyValue ( raw . indexReadKey , seen )
or fixed . storageOnlyValue ( raw . indexReadValue , seen )
or fixed . storageOnlyValue ( raw . indexWriteKey , seen )
or fixed . storageOnlyValue ( raw . indexWriteValue , seen )
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

local MIN_NORMAL_F32 = 2 ^ -126
local MIN_SUBNORMAL_F32 = 2 ^ -149

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
return value % 1 == 0 and value >= -2147483648 and value < 2147483648
elseif tag == "uint32" then
return value % 1 == 0 and value >= 0 and value < 4294967296
elseif tag == "int64" then


return value % 1 == 0 and value >= - 9007199254740992 and value <= 9007199254740992
elseif tag == "uint64" then
return value % 1 == 0 and value >= 0 and value <= 9007199254740992
else
return false
end
end

local MAX_F32 = 3.4028234663852886e38

local INTEGER_RANGE

= {
int8 = { -128 , 127 } ,
int16 = { -32768 , 32767 } ,
int32 = { -2147483648 , 2147483647 } ,
uint8 = { 0 , 255 } ,
uint16 = { 0 , 65535 } ,
uint32 = { 0 , 4294967295 } ,
}





function fixed . physicalLiteralFits ( value , target ) 
local tag = T . unwrapOwnership ( target ) . tag



if tag == "int64" or tag == "uint64" then
local lower = tag == "int64" and - 2 ^ 63 or 0
local upper = tag == "int64" and 2 ^ 63 or 2 ^ 64
return value % 1 == 0 and value >= lower and value < upper
end
local range = INTEGER_RANGE [ tag ]
if range then
return value % 1 == 0 and value >= range [ 1 ] and value <= range [ 2 ]
end

return tag ~= "float" or value ~= value or math . abs ( value ) <= MAX_F32
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

local __nuppExportValue= fixed ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.types.fixedwidth"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.types.fixedwidth"]=__nuppExports;return __nuppExports