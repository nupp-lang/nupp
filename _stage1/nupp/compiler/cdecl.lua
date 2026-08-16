_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);









local ffi = require ( "ffi" )




local bit = require ( "bit" )




local cdecl = { }

























































































































local CT_NUM , CT_STRUCT , CT_PTR , CT_ARRAY = 0 , 1 , 2 , 3
local CT_VOID , CT_ENUM , CT_FUNC = 4 , 5 , 6
local CT_TYPEDEF , CT_ATTRIB , CT_FIELD , CT_BITFIELD = 7 , 8 , 9 , 10
local CT_CONSTVAL = 11

local CTF_BOOL = 0x08000000
local CTF_FP = 0x04000000
local CTF_UNSIGNED = 0x00800000
local CTF_CONST = 0x02000000
local CTF_UNION = 0x00800000
local MAX_CTYPE_ID = 8192

local function kindOf ( value )
return bit . rshift ( value , 28 )
end

local function refOf ( value )
return bit . band ( value , 0xffff )
end

local function info ( id )
local ok , entry = pcall ( ffi . typeinfo , id )
if ok then
return entry
end

return nil
end




local function resolve ( id )
for _ = 1 , 16 do
local entry = info ( id )
if not entry then
return nil , nil
end
local kind = kindOf ( entry . info )
if kind == CT_TYPEDEF or kind == CT_ATTRIB then
id = refOf ( entry . info )
else
return id , entry
end
end

return nil , nil
end

local decodeType

local function decodeFunction ( entry )
local params = { }
local child = entry . sib
while child do
local centry = info ( child )
if not centry then
break
end
if kindOf ( centry . info ) == CT_FIELD then
params [ # params + 1 ] = { name = centry . name , type = decodeType ( refOf ( centry . info ) ) , }
end
child = centry . sib
end

return {
kind = "function" ,
name = entry . name ,
params = params ,
returns = decodeType ( refOf ( entry . info ) ) ,
vararg = bit . band ( entry . info , CTF_UNSIGNED ) ~= 0 ,
}
end




decodeType = function ( id )
local rid , entry = resolve ( id )
if not entry then
return { kind = "unknown" }
end
local kind = kindOf ( entry . info )
if kind == CT_VOID then
return { kind = "void" }
elseif kind == CT_NUM then
if bit . band ( entry . info , CTF_BOOL ) ~= 0 then
return { kind = "boolean" , bits = ( entry . size or 0 ) * 8 }
end
if bit . band ( entry . info , CTF_FP ) ~= 0 then
return { kind = "float" , bits = ( entry . size or 0 ) * 8 }
end
return { kind = "integer" , bits = ( entry . size or 0 ) * 8 , unsigned = bit . band ( entry . info , CTF_UNSIGNED ) ~= 0 , }
elseif kind == CT_PTR then
local _ , pointee = resolve ( refOf ( entry . info ) )
return {
kind = "pointer" ,
to = decodeType ( refOf ( entry . info ) ) ,
const = pointee and bit . band ( pointee . info , CTF_CONST ) ~= 0 or false ,
}
elseif kind == CT_STRUCT then
return { kind = bit . band ( entry . info , CTF_UNION ) ~= 0 and "union" or "struct" , id = rid , name = entry . name , }
elseif kind == CT_ENUM then
return {
kind = "enum" ,
name = entry . name ,
bits = ( entry . size or 4 ) * 8 ,
unsigned = bit . band ( entry . info , CTF_UNSIGNED ) ~= 0 ,
}
elseif kind == CT_ARRAY then
local element = decodeType ( refOf ( entry . info ) )
return { kind = "array" , of = element , bytes = entry . size }
elseif kind == CT_FUNC then
return decodeFunction ( entry )
end

return { kind = "unknown" }
end

local function decodeStruct ( id , entry )
local fields = { }
local child = entry . sib
while child do
local centry = info ( child )
if not centry then
break
end
if kindOf ( centry . info ) == CT_FIELD and centry . name then
fields [ # fields + 1 ] = { name = centry . name , type = decodeType ( refOf ( centry . info ) ) , offset = centry . size , }
elseif kindOf ( centry . info ) == CT_BITFIELD and centry . name then
local width = bit . band ( bit . rshift ( centry . info , 8 ) , 0xff )



local storageBits = bit . band ( bit . rshift ( centry . info , 16 ) , 0x0f ) * 8
fields [
# fields + 1
] = {
name = centry . name ,
type = { kind = "integer" , bits = storageBits , unsigned = bit . band ( centry . info , CTF_UNSIGNED ) ~= 0 , } ,
bitWidth = width ,
}
end
child = centry . sib
end

return {
kind = bit . band ( entry . info , CTF_UNION ) ~= 0 and "union" or "struct" ,
id = id ,
name = entry . name ,
size = entry . size ,
fields = fields ,
}
end

local INT32_MAX , UINT32 = 2147483647 , 4294967296












local function enumeratorValue ( name , entry )
local ok , value = pcall ( function ( )




return ( ffi . C ) [ name ]
end )
if not ok or type ( value ) ~= "number" then
value = entry . size
end
if type ( value ) ~= "number" then
return nil
end
if value > INT32_MAX then
value = value - UINT32
end

return value
end



local function decodeEnum ( id , entry )
local values = { }
local child = entry . sib
while child do
local centry = info ( child )
if not centry then
break
end
if kindOf ( centry . info ) == CT_CONSTVAL and centry . name then
local value = enumeratorValue ( centry . name , centry )
if value then
values [ # values + 1 ] = { name = centry . name , value = value }
end
end
child = centry . sib
end

return { kind = "enum" , id = id , name = entry . name , bits = ( entry . size or 4 ) * 8 , values = values , }
end



local inspectCache = { }



local function preludeList ( prelude )
if type ( prelude ) == "table" then
return prelude
end
if type ( prelude ) == "string" and # prelude > 0 then
return { prelude }
end

return { }
end




local function targetUnits ( text )
if type ( text ) == "table" then
return text , true
end
return { text } , false
end

function cdecl . inspect ( text , prelude )
local declarations = preludeList ( prelude )
local units , perUnit = targetUnits ( text )
local key = table . concat ( declarations , "\n" ) .. "\0" .. table . concat ( units , "\n" )
local hit = inspectCache [ key ]
if hit then
return hit
end












for _ , declaration in ipairs ( declarations ) do
pcall ( ffi . cdef , declaration )
end

local before = { }
for id = 1 , MAX_CTYPE_ID do
if info ( id ) then
before [ id ] = true
end
end






local rejected = { }
for _ , unit in ipairs ( units ) do
local ok , err = pcall ( ffi . cdef , unit )
if not ok then
rejected [ # rejected + 1 ] = {
text = unit ,

reason = tostring ( err ) : gsub ( "^.-:%d+:%s*" , "" ) ,
}
end
end
if not perUnit and # rejected > 0 then
return nil , rejected [ 1 ] . reason
end

local structs , functions , enums = { } , { } , { }
for id = 1 , MAX_CTYPE_ID do
local entry = info ( id )
if entry and not before [ id ] then
local kind = kindOf ( entry . info )



if kind == CT_ENUM then
enums [ # enums + 1 ] = decodeEnum ( id , entry )
elseif entry . name then
if kind == CT_STRUCT then
structs [ # structs + 1 ] = decodeStruct ( id , entry )
elseif kind == CT_FUNC then
functions [ # functions + 1 ] = decodeFunction ( entry )
end
end
end
end
local result = { structs = structs , functions = functions , enums = enums , rejected = rejected , declared = # units , }
inspectCache [ key ] = result

return result
end



















function cdecl . declare ( text )
local before = { }
for id = 1 , MAX_CTYPE_ID do
if info ( id ) then
before [ id ] = true
end
end
local ok , err = pcall ( ffi . cdef , text )
if not ok then
return false , tostring ( err )
end
local spelled = { }
for word in text : gmatch ( "[%a_][%w_]*" ) do
spelled [ word ] = true
end
local names = { }
for id = 1 , MAX_CTYPE_ID do
local entry = info ( id )
if entry and entry . name and kindOf ( entry . info ) == CT_FUNC and ( not before [ id ] or spelled [ entry . name ] ) then
names [ entry . name ] = true
end
end

return true , nil , names
end

function cdecl . typeFromString ( spec )
local ok , ct = pcall ( ffi . typeof , spec )
if not ok then
return nil , tostring ( ct )
end
local id = tonumber ( ct )
if not id then
return nil , "not a C type: " .. spec
end

return decodeType ( id )
end

function cdecl . structById ( id )
local rid , entry = resolve ( id )
if not entry or kindOf ( entry . info ) ~= CT_STRUCT then
return nil
end

return decodeStruct ( rid , entry )
end






function cdecl . declaredFunctions ( only )
local out = { }
for id = 1 , MAX_CTYPE_ID do
local entry = info ( id )
if entry and entry . name and kindOf ( entry . info ) == CT_FUNC and ( only == nil or only [ entry . name ] ) then
out [ entry . name ] = decodeFunction ( entry )
end
end

return out
end


local abiCache
function cdecl . abiTag ( )
if not abiCache then
local parts = { jit . arch , jit . os }
for _ , param in ipairs ( { "32bit" , "64bit" , "le" , "be" , "fpu" , "softfp" , "hardfp" , "eabi" , "win" } ) do
if ffi . abi ( param ) then
parts [ # parts + 1 ] = param
end
end
abiCache = table . concat ( parts , "," )
end

return abiCache
end

return cdecl
