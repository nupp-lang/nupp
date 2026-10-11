_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.runtime.provider.nativestorage"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local allocateArray;__nuppExports["allocateArray"]=function(...) return allocateArray(...) end;local allocateBytes;__nuppExports["allocateBytes"]=function(...) return allocateBytes(...) end;local borrowString;__nuppExports["borrowString"]=function(...) return borrowString(...) end;local boundedCount;__nuppExports["boundedCount"]=function(...) return boundedCount(...) end;local castBytes;__nuppExports["castBytes"]=function(...) return castBytes(...) end;local castElements;__nuppExports["castElements"]=function(...) return castElements(...) end;local copy;__nuppExports["copy"]=function(...) return copy(...) end;local decodeFloat32;__nuppExports["decodeFloat32"]=function(...) return decodeFloat32(...) end;local decodeFloat64;__nuppExports["decodeFloat64"]=function(...) return decodeFloat64(...) end;local decodeInt16;__nuppExports["decodeInt16"]=function(...) return decodeInt16(...) end;local decodeInt32;__nuppExports["decodeInt32"]=function(...) return decodeInt32(...) end;local decodeInt64;__nuppExports["decodeInt64"]=function(...) return decodeInt64(...) end;local decodeInt8;__nuppExports["decodeInt8"]=function(...) return decodeInt8(...) end;local decodeUint16;__nuppExports["decodeUint16"]=function(...) return decodeUint16(...) end;local decodeUint32;__nuppExports["decodeUint32"]=function(...) return decodeUint32(...) end;local decodeUint64;__nuppExports["decodeUint64"]=function(...) return decodeUint64(...) end;local decodeUint8;__nuppExports["decodeUint8"]=function(...) return decodeUint8(...) end;local descriptor;__nuppExports["descriptor"]=function(...) return descriptor(...) end;local encodeFloat32;__nuppExports["encodeFloat32"]=function(...) return encodeFloat32(...) end;local encodeFloat64;__nuppExports["encodeFloat64"]=function(...) return encodeFloat64(...) end;local encodeInt16;__nuppExports["encodeInt16"]=function(...) return encodeInt16(...) end;local encodeInt32;__nuppExports["encodeInt32"]=function(...) return encodeInt32(...) end;local encodeInt64;__nuppExports["encodeInt64"]=function(...) return encodeInt64(...) end;local encodeInt8;__nuppExports["encodeInt8"]=function(...) return encodeInt8(...) end;local encodeUint16;__nuppExports["encodeUint16"]=function(...) return encodeUint16(...) end;local encodeUint32;__nuppExports["encodeUint32"]=function(...) return encodeUint32(...) end;local encodeUint64;__nuppExports["encodeUint64"]=function(...) return encodeUint64(...) end;local encodeUint8;__nuppExports["encodeUint8"]=function(...) return encodeUint8(...) end;local fill;__nuppExports["fill"]=function(...) return fill(...) end;local scalar;__nuppExports["scalar"]=function(...) return scalar(...) end;local sizeOf;__nuppExports["sizeOf"]=function(...) return sizeOf(...) end;local string;__nuppExports["string"]=function(...) return string(...) end;






















const representation = "native" ;__nuppExports["representation"]=representation
local ffi = require ( "ffi" )

allocateBytes=function ( count ) 





assert ( count >= 0 and count % 1 == 0 , "nupp: storage byte extent must be a whole, finite count" )

return __nuppFfi.new("uint8_t[?]" , count )
end ;__nuppExports["allocateBytes"]=allocateBytes

borrowString=function ( bytes ) 
return __nuppFfi.cast("const uint8_t *" , bytes )
end ;__nuppExports["borrowString"]=borrowString

copy=function ( destination , source , count ) 
ffi . copy ( destination , source , count )
end ;__nuppExports["copy"]=copy



fill=function ( destination , count , value ) 
ffi . fill ( destination , count , value )
end ;__nuppExports["fill"]=fill

sizeOf=function ( element ) 
return ffi . sizeof ( element )
end ;__nuppExports["sizeOf"]=sizeOf

local stringBytes = ffi . string

string=function ( source , count ) 
return stringBytes ( source , count )
end ;__nuppExports["string"]=string

decodeUint8=function ( bytes ) 
local holder = __nuppFfi.new("uint8_t[1]" )
do
ffi . copy ( holder , bytes , 1 )
return holder [ 0 ]
end
end ;__nuppExports["decodeUint8"]=decodeUint8

encodeUint8=function ( value ) 
local holder = __nuppFfi.new("uint8_t[1]" )
do
holder [ 0 ] = value
end

return ffi . string ( holder , 1 )
end ;__nuppExports["encodeUint8"]=encodeUint8

decodeInt8=function ( bytes ) 
local holder = __nuppFfi.new("int8_t[1]" )
do
ffi . copy ( holder , bytes , 1 )
return holder [ 0 ]
end
end ;__nuppExports["decodeInt8"]=decodeInt8

encodeInt8=function ( value ) 
local holder = __nuppFfi.new("int8_t[1]" )
do
holder [ 0 ] = value
end

return ffi . string ( holder , 1 )
end ;__nuppExports["encodeInt8"]=encodeInt8

decodeUint16=function ( bytes ) 
local holder = __nuppFfi.new("uint16_t[1]" )
do
ffi . copy ( holder , bytes , 2 )
return holder [ 0 ]
end
end ;__nuppExports["decodeUint16"]=decodeUint16

encodeUint16=function ( value ) 
local holder = __nuppFfi.new("uint16_t[1]" )
do
holder [ 0 ] = value
end

return ffi . string ( holder , 2 )
end ;__nuppExports["encodeUint16"]=encodeUint16

decodeInt16=function ( bytes ) 
local holder = __nuppFfi.new("int16_t[1]" )
do
ffi . copy ( holder , bytes , 2 )
return holder [ 0 ]
end
end ;__nuppExports["decodeInt16"]=decodeInt16

encodeInt16=function ( value ) 
local holder = __nuppFfi.new("int16_t[1]" )
do
holder [ 0 ] = value
end

return ffi . string ( holder , 2 )
end ;__nuppExports["encodeInt16"]=encodeInt16

decodeUint32=function ( bytes ) 
local holder = __nuppFfi.new("uint32_t[1]" )
do
ffi . copy ( holder , bytes , 4 )
return holder [ 0 ]
end
end ;__nuppExports["decodeUint32"]=decodeUint32

encodeUint32=function ( value ) 
local holder = __nuppFfi.new("uint32_t[1]" )
do
holder [ 0 ] = value
end

return ffi . string ( holder , 4 )
end ;__nuppExports["encodeUint32"]=encodeUint32

decodeInt32=function ( bytes ) 
local holder = __nuppFfi.new("int32_t[1]" )
do
ffi . copy ( holder , bytes , 4 )
return holder [ 0 ]
end
end ;__nuppExports["decodeInt32"]=decodeInt32

encodeInt32=function ( value ) 
local holder = __nuppFfi.new("int32_t[1]" )
do
holder [ 0 ] = value
end

return ffi . string ( holder , 4 )
end ;__nuppExports["encodeInt32"]=encodeInt32

decodeUint64=function ( bytes ) 
local holder = __nuppFfi.new("uint64_t[1]" )
do
ffi . copy ( holder , bytes , 8 )
return holder [ 0 ]
end
end ;__nuppExports["decodeUint64"]=decodeUint64

encodeUint64=function ( value ) 
local holder = __nuppFfi.new("uint64_t[1]" )
do
holder [ 0 ] = value
end

return ffi . string ( holder , 8 )
end ;__nuppExports["encodeUint64"]=encodeUint64

decodeInt64=function ( bytes ) 
local holder = __nuppFfi.new("int64_t[1]" )
do
ffi . copy ( holder , bytes , 8 )
return holder [ 0 ]
end
end ;__nuppExports["decodeInt64"]=decodeInt64

encodeInt64=function ( value ) 
local holder = __nuppFfi.new("int64_t[1]" )
do
holder [ 0 ] = value
end

return ffi . string ( holder , 8 )
end ;__nuppExports["encodeInt64"]=encodeInt64

decodeFloat32=function ( bytes ) 
local holder = __nuppFfi.new("float[1]" )
do
ffi . copy ( holder , bytes , 4 )
return holder [ 0 ]
end
end ;__nuppExports["decodeFloat32"]=decodeFloat32

encodeFloat32=function ( value ) 
local holder = __nuppFfi.new("float[1]" )
do
holder [ 0 ] = value
end

return ffi . string ( holder , 4 )
end ;__nuppExports["encodeFloat32"]=encodeFloat32

decodeFloat64=function ( bytes ) 
local holder = __nuppFfi.new("double[1]" )
do
ffi . copy ( holder , bytes , 8 )
return holder [ 0 ]
end
end ;__nuppExports["decodeFloat64"]=decodeFloat64

encodeFloat64=function ( value ) 
local holder = __nuppFfi.new("double[1]" )
do
holder [ 0 ] = value
end

return ffi . string ( holder , 8 )
end ;__nuppExports["encodeFloat64"]=encodeFloat64

castBytes=function ( pointer ) 
return __nuppFfi.cast("const uint8_t *" , pointer )
end ;__nuppExports["castBytes"]=castBytes

castElements=function ( element , pointer ) 
local pointerSpec = "const $ *"
local pointerType = ffi . typeof ( pointerSpec , element )
do
return ffi . cast ( pointerType , pointer )
end
end ;__nuppExports["castElements"]=castElements

local scalarTypes = { }
local arrayTypes = { }
scalar=function ( kind ) 
local result = scalarTypes [ kind ]
if result == nil then
local spelling = kind == "float" and "float" or kind == "number" and "double" or kind .. "_t"
result = ffi . typeof ( spelling )
scalarTypes [ kind ] = result
end

return result
end ;__nuppExports["scalar"]=scalar

descriptor=function ( value ) 
return ffi . typeof ( value )
end ;__nuppExports["descriptor"]=descriptor

allocateArray=function ( element , count ) 
local width = ffi . sizeof ( element )
assert (
count >= 0 and count % 1 == 0 and count <= math . floor ( 2147483647 / math . max ( width , 1 ) ) ,
"nupp: storage array extent exceeds native allocation limit"
)
local physical = arrayTypes [ element ]
if physical == nil then
local spelling = "$[?]"
physical = ffi . typeof ( spelling , element )
arrayTypes [ element ] = physical
end

return ffi . new ( physical , count )
end ;__nuppExports["allocateArray"]=allocateArray


boundedCount=function ( source , count ) 
return count
end ;__nuppExports["boundedCount"]=boundedCount
local __nuppWorkerSendables=_G.rawget(_G.nupp,"__workerSendables");if _G.type(__nuppWorkerSendables)~="table" then __nuppWorkerSendables=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerSendables",__nuppWorkerSendables) end;__nuppWorkerSendables[__nuppExports["decodeFloat64"]]={module="nupp.runtime.provider.nativestorage",member="decodeFloat64",captures={values={},count=0},input="string",output="number"};__nuppWorkerSendables[__nuppExports["encodeFloat32"]]={module="nupp.runtime.provider.nativestorage",member="encodeFloat32",captures={values={},count=0},input="number",output="string"};__nuppWorkerSendables[__nuppExports["encodeFloat64"]]={module="nupp.runtime.provider.nativestorage",member="encodeFloat64",captures={values={},count=0},input="number",output="string"}; end);if not __nuppOk then package.loaded["nupp.runtime.provider.nativestorage"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.nativestorage"]=__nuppExports;return __nuppExports