_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);








const targetLayout = {} targetLayout.__index = targetLayout







targetLayout . ABI = 1




















local function scalar ( size , alignment )
return { size = size , alignment = alignment or size }
end





local LP64 = { pointer = scalar ( 8 ) , int64 = scalar ( 8 ) , number = scalar ( 8 ) }
local ILP32_SYSV = { pointer = scalar ( 4 ) , int64 = scalar ( 8 , 4 ) , number = scalar ( 8 , 4 ) }
local ILP32_MSVC = { pointer = scalar ( 4 ) , int64 = scalar ( 8 ) , number = scalar ( 8 ) }

local MODELS = { }

local function install ( keys , profile )
for _ , key in ipairs ( keys ) do
MODELS [ key ] = { key = key , pointer = profile . pointer , int64 = profile . int64 , number = profile . number , }
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

local ORDERED_KEYS = {
"aarch64-apple-darwin" ,
"aarch64-pc-windows-msvc" ,
"aarch64-unknown-linux-gnu" ,
"i686-pc-windows-msvc" ,
"i686-unknown-linux-gnu" ,
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
local architecture = architectures [ jit . arch ]
local system = systems [ jit . os ]
local key = architecture and system and architecture .. "-" .. system or nil

return key and MODELS [ key ] and key or nil
end

local function roundUp ( value , alignment )
return math . floor ( ( value + alignment - 1 ) / alignment ) * alignment
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
return nil , ( "field %q %s" ) : format ( name , why or "has no layout" )
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

return nil , ( "%s has no runtime layout" ) : format ( tostring ( subject . tag ) )
end

local measured , why , fields , offsets = layoutType ( t )
if not measured then
return nil , why
end
fields , offsets = fields or { } , offsets or { }
local parts = { key , "abi=" .. targetLayout . ABI }
for _ , field in ipairs ( fields ) do
parts [ # parts + 1 ] = ( "%s@%d:%d/%d" ) : format ( field . name , field . offset , field . size , field . alignment )
end
parts [ # parts + 1 ] = ( "size=%d/align=%d" ) : format ( measured . size , measured . alignment )

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

return targetLayout
