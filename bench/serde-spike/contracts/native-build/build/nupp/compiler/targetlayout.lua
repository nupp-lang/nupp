_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.targetlayout\0runtime\0001") };










local targetLayout = {} targetLayout.__index = targetLayout ;_G.nupp.__reflect.link(targetLayout,__nuppT1[1],{ })





















targetLayout . ABI = 1














































local function scalar ( size , alignment ) 
return { size = size , alignment = alignment or size }
end





local LP64 = { pointer = scalar ( 8 ) , int64 = scalar ( 8 ) , number = scalar ( 8 ) , vector = { maximumAlignment = 16 } , }
local ILP32_SYSV = { pointer = scalar ( 4 ) , int64 = ( { size = 8 , alignment = 4 } ) , number = ( { size = 8 , alignment = 4 } ) , vector = { maximumAlignment = 8 } , }
local ILP32_MSVC = { pointer = scalar ( 4 ) , int64 = scalar ( 8 ) , number = scalar ( 8 ) , vector = { maximumAlignment = 8 } , }
local WASM32 = { pointer = scalar ( 4 ) , int64 = scalar ( 8 ) , number = scalar ( 8 ) , vector = { maximumAlignment = 16 } , }

local MODELS = { }

local function install ( keys , profile ) 
for _ , key in ipairs ( keys ) do
MODELS [
key
] = {
key = key ,
pointer = profile . pointer ,
int64 = profile . int64 ,
number = profile . number ,
vector = profile . vector ,
}
end
end

install (
{
"x86_64-unknown-linux-gnu" ,
"aarch64-unknown-linux-gnu" ,
"x86_64-apple-darwin" ,
"aarch64-apple-darwin" ,
"x86_64-pc-windows-msvc" ,
"aarch64-pc-windows-msvc" ,
} ,
LP64
)
install ( { "i686-unknown-linux-gnu" } , ILP32_SYSV )
install ( { "i686-pc-windows-msvc" } , ILP32_MSVC )
install ( { "wasm32-unknown-emscripten" } , WASM32 )

local ORDERED_KEYS = {
"aarch64-apple-darwin" ,
"aarch64-pc-windows-msvc" ,
"aarch64-unknown-linux-gnu" ,
"i686-pc-windows-msvc" ,
"i686-unknown-linux-gnu" ,
"wasm32-unknown-emscripten" ,
"x86_64-apple-darwin" ,
"x86_64-pc-windows-msvc" ,
"x86_64-unknown-linux-gnu" ,
}

function targetLayout . keys ( ) 
local out = { }
for index , key in ipairs ( ORDERED_KEYS ) do
out [ index ] = key
end

return out
end

function targetLayout . has ( key ) 
return key ~= nil and MODELS [ key ] ~= nil
end



function targetLayout . hostKey ( ) 
local architectures = { x64 = "x86_64" , x86 = "i686" , arm64 = "aarch64" }
local systems = { OSX = "apple-darwin" , Linux = "unknown-linux-gnu" , Windows = "pc-windows-msvc" }
local host = rawget ( _G , "jit" )
local architecture = host and architectures [ host . arch ] or nil
local system = host and systems [ host . os ] or nil
local key = architecture and system and architecture .. "-" .. system or nil

return key and MODELS [ key ] and key or nil
end

local function roundUp ( value , alignment ) 
return math . floor ( ( value + alignment - 1 ) / alignment ) * alignment
end





function targetLayout . vector ( key , elementBytes , lanes ) 
local model = MODELS [ key ]
if not model then
return nil , "unknown target layout key " .. tostring ( key )
end
if elementBytes < 1 or lanes < 1 or elementBytes % 1 ~= 0 or lanes % 1 ~= 0 then
return nil , "a vector has a positive whole element width and lane count"
end
local payload = elementBytes * lanes
local natural = elementBytes
while natural < payload do
natural = natural * 2
end
local alignment = math . min ( natural , model . vector . maximumAlignment )
if alignment < elementBytes then
alignment = elementBytes
end
local size = roundUp ( payload , alignment )

return { payload = payload , alignment = alignment , padding = size - payload , size = size } , nil
end



const VECTOR_ELEMENT_BYTES

= { float = 4 , number = 8 , int8 = 1 , uint8 = 1 , int16 = 2 , uint16 = 2 , int32 = 4 , uint32 = 4 , int64 = 8 , uint64 = 8 , }

targetLayout . VECTOR_ELEMENT_BYTES = VECTOR_ELEMENT_BYTES






function targetLayout . storageVector ( t ) 
local raw = t
while raw ~= nil and ( raw . tag == "const" or raw . tag == "affine" or raw . tag == "borrowed" or raw . tag == "pinned" ) do
raw = raw . inner
end
while raw ~= nil and raw . tag == "genericAlias" do
raw = raw . body
end
if raw == nil or raw . tag ~= "nominal" then
return nil , nil
end
local origin = raw . origin or raw
if origin . moduleName ~= "nupp.simd" or origin . name ~= "Vector" then
return nil , nil
end
local arguments = raw . typeArgs or { }
local element = arguments [ 1 ]
while element ~= nil and element . tag == "const" do
element = element . inner
end
if element == nil or VECTOR_ELEMENT_BYTES [ element . tag ] == nil then
return nil , nil
end
local species = arguments [ 2 ]
local speciesOrigin = species ~= nil and ( species . origin or species ) or nil
if species == nil
or species . tag ~= "nominal"
or speciesOrigin . moduleName ~= "nupp.simd"
or speciesOrigin . name ~= "Fixed"
then
return nil , nil
end
local count = ( species . constArgs or { } ) [ 1 ]
if count == nil or count . tag ~= "constLiteral" or count . domain ~= "integer" then
return nil , nil
end

return element . tag , count . value
end





function targetLayout . luaVectorAlignment ( elementBytes , lanes ) 
local laid = targetLayout . vector ( "x86_64-unknown-linux-gnu" , elementBytes , lanes )

return ( laid ) . alignment
end

local FIXED

= {
boolean = scalar ( 1 ) ,
float = scalar ( 4 ) ,
integer = scalar ( 4 ) ,
int8 = scalar ( 1 ) ,
int16 = scalar ( 2 ) ,
int32 = scalar ( 4 ) ,
uint8 = scalar ( 1 ) ,
uint16 = scalar ( 2 ) ,
uint32 = scalar ( 4 ) ,
}






function targetLayout . of ( t , key ) 
local model = MODELS [ key ]
if not model then
return nil , "unknown layout target " .. tostring ( key )
end

local active = { }
local layoutType

layoutType = function ( subject ) 
if not subject then
return nil , "the type is unresolved"
end
local fixed = FIXED [ subject . tag ]
if fixed then
return fixed
elseif subject . tag == "number" then
return model . number
elseif subject . tag == "int64" or subject . tag == "uint64" then
return model . int64
elseif subject . tag == "cstring" or subject . tag == "voidptr" or subject . tag == "ptr" then
return model . pointer
elseif subject . tag == "union" and subject . hasNil and # subject . members == 2 then
local other = subject . members [ 1 ] . tag == "nil" and subject . members [ 2 ] or subject . members [ 1 ]
if other and ( other . tag == "ptr" or other . tag == "cstring" or other . tag == "voidptr" ) then
return model . pointer
end
elseif subject . tag == "carray" then
if not subject . count or subject . count < 0 then
return nil , "an unsized C array has no compile-time layout"
end
local element , why = layoutType ( subject . elem )
if not element then
return nil , why
end
return scalar ( element . size * ( subject . count ) , element . alignment )
elseif subject . tag == "nominal" and subject . declKind ~= "struct" then
local element , lanes = targetLayout . storageVector ( subject )
if element ~= nil then



local laid = targetLayout . vector (
key ,
VECTOR_ELEMENT_BYTES [ element ] ,
lanes
)
local vector = laid
return scalar ( vector . size , vector . alignment )
end
local origin = subject . origin or subject
if origin . moduleName == "nupp.simd" and origin . name == "Mask" then
return nil , "a mask has no storage layout"
elseif origin . moduleName == "nupp.simd" and origin . name == "Vector" then
return nil , "a vector of a tier-dependent species has no target-independent layout"
end
elseif subject . tag == "nominal" and subject . declKind == "struct" then
if active [ subject ] then
return nil , "a by-value struct cycle has no finite layout"
end
active [ subject ] = true
local fields , offsets = { } , { }
local cursor , aggregateAlignment = 0 , 1
for _ , name in ipairs ( subject . fieldOrder or { } ) do
local fieldType = subject . byname and subject . byname [ name ] or nil
local one , why = layoutType ( fieldType )
if not one then
active [ subject ] = nil
return nil , ("field %q %s") : format ( name , why or "has no layout" )
end
cursor = roundUp ( cursor , one . alignment )
fields [ # fields + 1 ] = { name = name , offset = cursor , size = one . size , alignment = one . alignment , }
offsets [ name ] = cursor
cursor = cursor + one . size
if one . alignment > aggregateAlignment then
aggregateAlignment = one . alignment
end
end
active [ subject ] = nil
if # fields == 0 then
return nil , "an empty struct has no C layout"
end
return scalar ( roundUp ( cursor , aggregateAlignment ) , aggregateAlignment ) , nil , fields , offsets
end

return nil , ("%s has no runtime layout") : format ( tostring ( subject . tag ) )
end

local measured , why , fields , offsets = layoutType ( t )
if not measured then
return nil , why
end
fields , offsets = fields or { } , offsets or { }
local parts = { key , "abi=" .. targetLayout . ABI }
for _ , field in ipairs ( fields ) do
parts [ # parts + 1 ] = ("%s@%d:%d/%d") : format ( field . name , field . offset , field . size , field . alignment )
end
parts [ # parts + 1 ] = ("size=%d/align=%d") : format ( measured . size , measured . alignment )

return {
target = key ,
abi = targetLayout . ABI ,
size = measured . size ,
alignment = measured . alignment ,
fields = fields ,
offsets = offsets ,
fingerprint = table . concat ( parts , "|" ) ,
}
end

local __nuppExportValue= targetLayout ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.targetlayout"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.targetlayout"]=__nuppExports;return __nuppExports