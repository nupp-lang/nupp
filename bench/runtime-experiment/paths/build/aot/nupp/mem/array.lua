_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.mem.array\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.mem.array\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.mem.array\0runtime\0003") };























local array = { }



array.Scalar = {} array.Scalar.__index = array.Scalar ;_G.nupp.__reflect.link(array.Scalar,__nuppT1[1],{ })










local function narrow ( kind , _shape ) 
return ( _G.setmetatable({ _elementType =  nil ,  physical =  kind }, array.Scalar) )
end

array . uint8 = narrow ( "uint8" , nil )
array . int8 = narrow ( "int8" , nil )
array . uint16 = narrow ( "uint16" , nil )
array . int16 = narrow ( "int16" , nil )
array . uint32 = _G.setmetatable({ _elementType =  nil ,  physical =  "uint32" }, array.Scalar)
array . int32 = _G.setmetatable({ _elementType =  nil ,  physical =  "int32" }, array.Scalar)
array . uint64 = _G.setmetatable({ _elementType =  nil ,  physical =  "uint64" }, array.Scalar)
array . int64 = _G.setmetatable({ _elementType =  nil ,  physical =  "int64" }, array.Scalar)
array . float = _G.setmetatable({ _elementType =  nil ,  physical =  "float" }, array.Scalar)
array . number = _G.setmetatable({ _elementType =  nil ,  physical =  "number" }, array.Scalar)

array.Array = {} array.Array.__index = array.Array ;_G.nupp.__reflect.link(array.Array,__nuppT1[2],{ })






function array . Array . read ( self ) 
return require ( "nupp.mem.span" ) . fromCarray ( self . pointer , self . count )
end

function array . Array . write ( self ) 
return require ( "nupp.mem.span" ) . writeCarray ( self . pointer , self . count )
end




function array . newArray ( witness , count ) 
local storage = require ( "nupp.runtime.storage" )
local raw = witness
local element = storage . descriptor ( raw )
return ( _G.setmetatable({ pointer =  storage . allocateArray ( element , count ) ,  count =  count }, array.Array) )
end




function array . scalar ( witness , count ) 
local storage = require ( "nupp.runtime.storage" )
return ( _G.setmetatable({ pointer =
storage . allocateArray ( storage . scalar ( witness . physical ) , count ) ,  count =
count }, array.Array) )

end


array.Bytes = {} array.Bytes.__index = array.Bytes



function array.Bytes:read() 
return require ( "nupp.mem.span" ) . fromCarray ( self . pointer , self . count )
end

function array.Bytes:write() 
return require ( "nupp.mem.span" ) . writeCarray ( self . pointer , self . count )
end ;_G.nupp.__reflect.link(array.Bytes,__nuppT1[3],{ })




function array . bytes ( count ) 
if count < 0 or count ~= math . floor ( count ) then
error ( "nupp: byte array count must be a non-negative integer" , 2 )
end
return ( _G.setmetatable({ pointer =  require ( "nupp.runtime.storage" ) . allocateBytes ( count ) ,  count =  count }, array.Bytes) )
end

local __nuppExportValue= array ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.mem.array"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.mem.array"]=__nuppExports;return __nuppExports