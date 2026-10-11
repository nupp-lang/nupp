_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.types.indexedviews\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.types.indexedviews\0runtime\0002") };







local T = require ( "nupp.compiler.types" )

local indexed = { }



indexed.Descriptor = {} indexed.Descriptor.__index = indexed.Descriptor ;_G.nupp.__reflect.link(indexed.Descriptor,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00017","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\0002","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00018","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\0009","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00028","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00027","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00035","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00033","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00032","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\0007","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00034","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\0003","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00040","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00039","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00047","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00038","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00019","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\0001","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00042","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00031","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\0008","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\0005","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\0004","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00037","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00041","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\00036","nupp.compiler.types") , _G.nupp.__reflect.reference("nupp.compiler.types\0runtime\0006","nupp.compiler.types") })







indexed.Producer = {} indexed.Producer.__index = indexed.Producer ;_G.nupp.__reflect.link(indexed.Producer,__nuppT1[2],{ __nuppT1[1] })




local function describe ( t ) 
local raw = T . unwrapOwnership ( t )
if raw . tag == "intersection" then
for _ , member in ipairs ( raw . members ) do
local found = describe ( member )
if found then
return found
end
end
return nil
end
if raw . tag ~= "nominal" then
return nil
end

local nominal = raw
local origin = ( nominal . origin or nominal )
local moduleName = origin . moduleName or nominal . moduleName or origin . sealedModule
local name = origin . name
local args = nominal . typeArgs or { }
local element = args [ 1 ]
if not element then
return nil
end

if ( moduleName == "nupp.mem.span" )
and ( name == "Span" or name == "FixedSpan" or name == "WriteSpan" or name == "FixedWriteSpan" )
then
return ( _G.setmetatable({ adapter =
"span" ,  element =
element ,  writable =
name == "WriteSpan" or name == "FixedWriteSpan" ,  fixedCount =
( name == "FixedSpan" or name == "FixedWriteSpan" ) and args [ 2 ] or nil ,  nominal =
nominal }, indexed.Descriptor) )

elseif moduleName == "nupp.mem.soa" and ( name == "Span" or name == "WriteSpan" ) then
return ( _G.setmetatable({ adapter =
"soa" ,  element =
element ,  writable =
name == "WriteSpan" ,  nominal =
nominal }, indexed.Descriptor) )

end

return nil
end

indexed . describe = describe





function indexed . spanElement ( t ) 
if t . tag ~= "nominal" then
return nil
end
local nominal = t
local origin = ( nominal . origin or nominal )
if origin . moduleName ~= "nupp.mem.span" then
return nil
end
if origin . name ~= "Span"
and origin . name ~= "FixedSpan"
and origin . name ~= "WriteSpan"
and origin . name ~= "FixedWriteSpan"
then
return nil
end

return nominal . typeArgs and nominal . typeArgs [ 1 ] or nil
end




function indexed . exportProducer ( moduleName , member , result ) 
if moduleName ~= "nupp.mem.span" then
return nil
end
local descriptor = describe ( result )
if not descriptor then
return nil
end
local kind
if member == "fromCarray" or member == "writeCarray" then
kind = "carray"
elseif member == "fromFixedCarray" or member == "writeFixedCarray" then
kind = "fixed-carray"
elseif member == "fromString" then
kind = "string"
else
return nil
end

return ( _G.setmetatable({ kind =  kind ,  descriptor =  descriptor }, indexed.Producer) )
end




function indexed . methodProducer ( receiver , member , result ) 
local raw = T . unwrapOwnership ( receiver )
if raw . tag ~= "nominal" then
return nil
end
local nominal = raw
local origin = ( nominal . origin or nominal )
local moduleName = origin . moduleName or nominal . moduleName or origin . sealedModule
if origin . name ~= "Array" or ( member ~= "read" and member ~= "write" ) then
return nil
end
local kind
if moduleName == "nupp.mem.heap" then
kind = "heap"
elseif moduleName == "nupp.mem.soa" then
kind = "soa"
else
return nil
end
local descriptor = describe ( result )
if not descriptor then
return nil
end

return ( _G.setmetatable({ kind =  kind ,  descriptor =  descriptor }, indexed.Producer) )
end

local __nuppExportValue= indexed ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.types.indexedviews"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.types.indexedviews"]=__nuppExports;return __nuppExports