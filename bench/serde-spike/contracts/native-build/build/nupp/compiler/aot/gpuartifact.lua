_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.gpuartifact\0runtime\0001") };









local scalarIR = require ( "nupp.compiler.aot.scalar" )
local spirvemit = require ( "nupp.compiler.aot.spirvemit" )
local visit = require ( "nupp.compiler.aot.visit" )
local wgslemit = require ( "nupp.compiler.aot.wgslemit" )

local gpuartifact = { }

gpuartifact.Artifact = {} gpuartifact.Artifact.__index = gpuartifact.Artifact ;_G.nupp.__reflect.link(gpuartifact.Artifact,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00084","nupp.compiler.aot.scalar") })


































const STORAGE_TYPE

= { float = true , int8 = true , int16 = true , int32 = true , uint8 = true , uint16 = true , uint32 = true , }

const UNIFORM_TYPE = { f32 = true , i32 = true , u32 = true , }






const NARROW_STORAGE = { int8 = true , int16 = true , uint8 = true , uint16 = true , }

local function identifier ( value ) 
return ( value : gsub ( "[^%w_]" , "_" ) )
end

local function fixedStorage ( param ) 
return param . type : match ( "^struct:" ) ~= nil
or ( param . sourceType ~= nil and STORAGE_TYPE [ param . sourceType ] == true )
end






local function outsideSubset (
program ,
spans ,
writable ,
uniforms ,
uniformBytes
) 
if program . executionTarget ~= "gpu" then
return "GPU emission requires @aot(target = \"gpu\")"
end
local loop = program . loop
local workgroup = program . workgroup
if program . entryMode ~= "kernel" or ( loop ~= nil ) == ( workgroup ~= nil ) then
return "GPU entry must be a map or phased workgroup kernel"
end
if loop ~= nil
and ( ( loop ) . first ~= 1 or ( loop ) . last ~= ( loop ) . count )
then
return "GPU entry must dispatch one complete span"
end
for _ , param in ipairs ( program . params ) do
if param . kind == "read_span" or param . kind == "write_span" then
if not ( param . type : match ( "^struct:" ) ~= nil or ( param . sourceType ~= nil and STORAGE_TYPE [ param . sourceType ] == true ) ) then
return "GPU span must have fixed-width elements"
end
elseif param . kind == "uniform" then
if param . type == "bool" then
return "GPU boolean uniforms are not yet supported"
elseif UNIFORM_TYPE [ param . type ] ~= true then
return "GPU uniform must have fixed width"
end
else
return "GPU subset does not admit scalar ABI parameters"
end
end
for _ , param in ipairs ( program . params ) do
if param . sourceType ~= nil and NARROW_STORAGE [ param . sourceType ] == true then
return "GPU span " .. param . name .. " has " .. tostring (
param . sourceType
) .. " elements; GPU kernels need 32-bit storage (WGPU refuses 8- and 16-bit storage buffers)"
end
end
for _ , layout in ipairs ( program . layouts or { } ) do
for _ , field in ipairs ( layout . fields ) do
if field . sourceType ~= nil and NARROW_STORAGE [ field . sourceType ] == true then
return "GPU struct field " .. layout . name .. "." .. field . name .. " is " .. tostring (
field . sourceType
) .. "; GPU kernels need 32-bit storage (WGPU refuses 8- and 16-bit storage buffers)"
end
end
end
if # writable < 1 then
return "GPU kernels require a writable span"
end
for _ , param in ipairs ( uniforms ) do
for _ , span in ipairs ( spans ) do
if param . name == span . name .. "_count" then
return "GPU uniform name collides with a span count: " .. param . name
elseif param . name == span . name .. "_offset" then
return "GPU uniform name collides with a span offset: " .. param . name
end
end
end
if uniformBytes > 128 then
return "GPU uniform block exceeds 128 bytes"
end

return nil
end






function gpuartifact . program ( program , browser ) 
local loop = program . loop
local workgroup = program . workgroup
local readonly = { }
local writable = { }
local uniforms = { }
local spans = { }
for _ , param in ipairs ( program . params ) do
if param . kind == "read_span" then
readonly [ # readonly + 1 ] = param
spans [ # spans + 1 ] = param
elseif param . kind == "write_span" then
writable [ # writable + 1 ] = param
elseif param . kind == "uniform" then
uniforms [ # uniforms + 1 ] = param
end
end
for _ , param in ipairs ( writable ) do
spans [ # spans + 1 ] = param
end
local uniformBytes = 4 * ( 1 + 2 * # spans + # uniforms )
local rule = outsideSubset ( program , spans , writable , uniforms , uniformBytes )
if rule ~= nil then
return nil , rule
end

local exactCounts = { }
for _ , guard in ipairs ( program . guards ) do
exactCounts [ guard . left ] = true
exactCounts [ guard . right ] = true
end
visit . program (
program ,
_G.setmetatable({ scalarExpression =
function ( value ) 
if ( value . op == "load" or value . op == "element_ref" ) and ( value ) . cursor == nil then
exactCounts [ ( value ) . span ] = true
end
end ,  scalarStatement =
function ( statement ) 
if statement . op == "store" and ( statement ) . cursor == nil then
exactCounts [ ( statement ) . span ] = true
end
end }, visit.Visitor)

)

local threads = workgroup ~= nil and ( workgroup ) . size or 256
local spirv = spirvemit . program ( program , readonly , writable , uniforms , threads )
local wgsl , profile = wgslemit . program ( program , readonly , writable , uniforms , threads )
if browser and wgsl == nil then
return nil , profile
end

return _G.setmetatable({ spirv =
spirv ,  wgsl =
wgsl ,  entrypoint =
identifier ( program . symbol ) .. "_gpu" ,  readonly =
readonly ,  writable =
writable ,  uniforms =
uniforms ,  uniformBytes =
uniformBytes ,  threads =
threads ,  countSpan =
workgroup ~= nil and ( workgroup ) . dispatchSpan
or ( loop ) . count ,  exactCounts =
exactCounts }, gpuartifact.Artifact)
, nil
end

local __nuppExportValue= gpuartifact ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.gpuartifact"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.gpuartifact"]=__nuppExports;return __nuppExports