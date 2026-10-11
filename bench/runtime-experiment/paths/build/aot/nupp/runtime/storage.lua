_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.runtime.storage"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()


local representation = require ( "nupp.mem.representation" )
local provider = assert ( representation . storage , "nupp.runtime.storage: no implementation is available for the target" )

const allocateBytes = provider . allocateBytes ;__nuppExports["allocateBytes"]=allocateBytes
const borrowString = provider . borrowString ;__nuppExports["borrowString"]=borrowString
const copy = provider . copy ;__nuppExports["copy"]=copy
const fill = provider . fill ;__nuppExports["fill"]=fill
const sizeOf = provider . sizeOf ;__nuppExports["sizeOf"]=sizeOf
const string = provider . string ;__nuppExports["string"]=string
const decodeUint8 = provider . decodeUint8 ;__nuppExports["decodeUint8"]=decodeUint8
const encodeUint8 = provider . encodeUint8 ;__nuppExports["encodeUint8"]=encodeUint8
const decodeInt8 = provider . decodeInt8 ;__nuppExports["decodeInt8"]=decodeInt8
const encodeInt8 = provider . encodeInt8 ;__nuppExports["encodeInt8"]=encodeInt8
const decodeUint16 = provider . decodeUint16 ;__nuppExports["decodeUint16"]=decodeUint16
const encodeUint16 = provider . encodeUint16 ;__nuppExports["encodeUint16"]=encodeUint16
const decodeInt16 = provider . decodeInt16 ;__nuppExports["decodeInt16"]=decodeInt16
const encodeInt16 = provider . encodeInt16 ;__nuppExports["encodeInt16"]=encodeInt16
const decodeUint32 = provider . decodeUint32 ;__nuppExports["decodeUint32"]=decodeUint32
const encodeUint32 = provider . encodeUint32 ;__nuppExports["encodeUint32"]=encodeUint32
const decodeInt32 = provider . decodeInt32 ;__nuppExports["decodeInt32"]=decodeInt32
const encodeInt32 = provider . encodeInt32 ;__nuppExports["encodeInt32"]=encodeInt32
const decodeUint64 = provider . decodeUint64 ;__nuppExports["decodeUint64"]=decodeUint64
const encodeUint64 = provider . encodeUint64 ;__nuppExports["encodeUint64"]=encodeUint64
const decodeInt64 = provider . decodeInt64 ;__nuppExports["decodeInt64"]=decodeInt64
const encodeInt64 = provider . encodeInt64 ;__nuppExports["encodeInt64"]=encodeInt64
const decodeFloat32 = provider . decodeFloat32 ;__nuppExports["decodeFloat32"]=decodeFloat32
const encodeFloat32 = provider . encodeFloat32 ;__nuppExports["encodeFloat32"]=encodeFloat32
const decodeFloat64 = provider . decodeFloat64 ;__nuppExports["decodeFloat64"]=decodeFloat64
const encodeFloat64 = provider . encodeFloat64 ;__nuppExports["encodeFloat64"]=encodeFloat64
const castBytes = provider . castBytes ;__nuppExports["castBytes"]=castBytes
const castElements = provider . castElements ;__nuppExports["castElements"]=castElements
const scalar = provider . scalar ;__nuppExports["scalar"]=scalar
const descriptor = provider . descriptor ;__nuppExports["descriptor"]=descriptor
const allocateArray = provider . allocateArray ;__nuppExports["allocateArray"]=allocateArray
const boundedCount = provider . boundedCount ;__nuppExports["boundedCount"]=boundedCount
const layout = provider . layout ;__nuppExports["layout"]=layout
const reference = provider . reference ;__nuppExports["reference"]=reference
 end);if not __nuppOk then package.loaded["nupp.runtime.storage"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.storage"]=__nuppExports;return __nuppExports