_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()











local ffi = require ( "ffi" )




local bit = require ( "bit" )





local cdecl = { }






































































































































































local CT_NUM , CT_STRUCT , CT_PTR , CT_ARRAY = 0 , 1 , 2 , 3
local CT_VOID , CT_ENUM , CT_FUNC = 4 , 5 , 6
local CT_TYPEDEF , CT_ATTRIB , CT_FIELD , CT_BITFIELD = 7 , 8 , 9 , 10
local CT_CONSTVAL = 11

local CTF_BOOL = 134217728
local CTF_FP = 67108864
local CTF_UNSIGNED = 8388608
local CTF_CONST = 33554432
local CTF_UNION = 8388608
local CTF_VECTOR = 134217728
local CTF_COMPLEX = 67108864



local CTA_SUBTYPE = 3

local function kindOf ( value ) 
return bit . rshift ( value , 28 )
end

local function refOf ( value ) 
return bit . band ( value , 65535 )
end


local function alignOf ( value ) 
return bit . lshift ( 1 , bit . band ( bit . rshift ( value , 16 ) , 15 ) )
end

local function info ( id ) 
local ok , entry = pcall ( ffi . typeinfo , id )
if ok then
return entry
end

return nil
end




local function ctypes ( ) 
local id = 0

return function ( ) 
id = id + 1
local entry = info ( id )
if entry == nil then
return nil
end

return id , entry
end
end

local function entryFingerprint ( entry ) 
return table . concat ( { tostring ( entry . info ) , tostring ( entry . size ) , tostring ( entry . sib ) , tostring ( entry . name ) } , "\0" )
end




local function resolve ( id ) 
for _ = 1 , 16 do
local entry = info ( id )
if not entry then
return nil , nil
end
local kind = kindOf ( entry . info )
if kind == 7 or kind == 8 then
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
do break end
end
if kindOf ( centry . info ) == 9 then
params [ # params + 1 ] = { name = centry . name , type = decodeType ( refOf ( centry . info ) ) , }
end
child = centry . sib
end

return {
kind = "function" ,
name = entry . name ,
params = params ,
returns = decodeType ( refOf ( entry . info ) ) ,
vararg = bit . band ( entry . info , 8388608 ) ~= 0 ,
}
end




decodeType = function ( id ) 
local rid , entry = resolve ( id )
if not entry then
return { kind = "unknown" }
end
local kind = kindOf ( entry . info )
if kind == 4 then
return { kind = "void" }
elseif kind == 0 then
if bit . band ( entry . info , 134217728 ) ~= 0 then
return { kind = "boolean" , bits = ( entry . size or 0 ) * 8 , size = entry . size }
end
if bit . band ( entry . info , 67108864 ) ~= 0 then
return { kind = "float" , bits = ( entry . size or 0 ) * 8 , size = entry . size }
end
return {
kind = "integer" ,
bits = ( entry . size or 0 ) * 8 ,
size = entry . size ,
unsigned = bit . band ( entry . info , 8388608 ) ~= 0 ,
}
elseif kind == 2 then
local _ , pointee = resolve ( refOf ( entry . info ) )
return {
kind = "pointer" ,
to = decodeType ( refOf ( entry . info ) ) ,
const = pointee and bit . band ( pointee . info , 33554432 ) ~= 0 or false ,
size = entry . size ,
}
elseif kind == 1 then
return {
kind = bit . band ( entry . info , 8388608 ) ~= 0 and "union" or "struct" ,
id = rid ,
name = entry . name ,
size = entry . size ,
align = alignOf ( entry . info ) ,
}
elseif kind == 5 then
return {
kind = "enum" ,
name = entry . name ,
bits = ( entry . size or 4 ) * 8 ,
size = entry . size or 4 ,
unsigned = bit . band ( entry . info , 8388608 ) ~= 0 ,
}
elseif kind == 3 then
if bit . band ( entry . info , 134217728 ) ~= 0 then
return { kind = "vector" , size = entry . size , of = decodeType ( refOf ( entry . info ) ) }
end
if bit . band ( entry . info , 67108864 ) ~= 0 then
return { kind = "complex" , size = entry . size , of = decodeType ( refOf ( entry . info ) ) }
end
local element = decodeType ( refOf ( entry . info ) )
local count = nil
if entry . size and element . size and element . size > 0 and entry . size % element . size == 0 then
count = entry . size / element . size
end
return { kind = "array" , of = element , bytes = entry . size , size = entry . size , count = count }
elseif kind == 6 then
return decodeFunction ( entry )
end

return { kind = "unknown" }
end

local function decodeStruct ( id , entry ) 
local fields = { }
local anonymous , unnamed = 0 , 0
local child = entry . sib
while child do
local centry = info ( child )
if not centry then
do break end
end
local kind = kindOf ( centry . info )
if kind == 9 then
if centry . name then
fields [ # fields + 1 ] = { name = centry . name , type = decodeType ( refOf ( centry . info ) ) , offset = centry . size , }
else
unnamed = unnamed + 1
end
elseif kind == 10 then
if centry . name then
local width = bit . band ( bit . rshift ( centry . info , 8 ) , 127 )



local storageBits = bit . band ( bit . rshift ( centry . info , 16 ) , 127 ) * 8

local fieldType = bit . band ( centry . info , 134217728 ) ~= 0
and { kind = "boolean" , bits = storageBits , size = storageBits / 8 }
or { kind = "integer" , bits = storageBits , unsigned = bit . band ( centry . info , 8388608 ) ~= 0 , }
fields [
# fields + 1
] = {
name = centry . name ,
type = fieldType ,
offset = centry . size ,
bitWidth = width ,
bitPos = bit . band ( centry . info , 127 ) ,
}
else
unnamed = unnamed + 1
end
elseif kind == 8 and bit . band ( bit . rshift ( centry . info , 16 ) , 255 ) == 3 then
anonymous = anonymous + 1
end
child = centry . sib
end

return {
kind = bit . band ( entry . info , 8388608 ) ~= 0 and "union" or "struct" ,
id = id ,
name = entry . name ,
size = entry . size ,
align = alignOf ( entry . info ) ,
fields = fields ,
anonymous = anonymous ,
unnamed = unnamed ,
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
if value > 2147483647 then
value = value - 4294967296
end

return value
end



local function decodeEnum ( id , entry ) 
local values = { }
local child = entry . sib
while child do
local centry = info ( child )
if not centry then
do break end
end
if kindOf ( centry . info ) == 11 and centry . name then
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
local top = 0
for id , entry in ctypes ( ) do
before [ id ] = ( table . concat ( { tostring ( entry . info ) , tostring ( entry . size ) , tostring ( entry . sib ) , tostring ( entry . name ) } , "\0" ) )
top = id
end











local preludeNames = { }
for _ , declaration in ipairs ( declarations ) do
for word in declaration : gmatch ( "[%a_][%w_]*" ) do
preludeNames [ word ] = true
end
end
local spelled = { }
for _ , unit in ipairs ( units ) do
for word in unit : gmatch ( "[%a_][%w_]*" ) do
if not preludeNames [ word ] then
spelled [ word ] = true
end
end
end










local rejected = { }
local unitOf = { }
for index , unit in ipairs ( units ) do
local ok , err = pcall ( ffi . cdef , unit )
while info ( top + 1 ) do
top = top + 1
unitOf [ top ] = index
end
if not ok then
rejected [ # rejected + 1 ] = {
text = unit ,

reason = tostring ( err ) : gsub ( "^.-:%d+:%s*" , "" ) ,
unit = index ,
}
end
end
if not perUnit and # rejected > 0 then
return nil , rejected [ 1 ] . reason
end

local structs , functions , enums = { } , { } , { }
local anonymousStructs = { }
for id , entry in ctypes ( ) do
if before [ id ] ~= ( table . concat ( { tostring ( entry . info ) , tostring ( entry . size ) , tostring ( entry . sib ) , tostring ( entry . name ) } , "\0" ) ) or ( entry . name ~= nil and spelled [ entry . name ] ) then
local kind = kindOf ( entry . info )



if kind == 5 then
local declaration = decodeEnum ( id , entry )
declaration . unit = unitOf [ id ]
enums [ # enums + 1 ] = declaration
elseif kind == 7 and entry . name then
local rid , target = resolve ( refOf ( entry . info ) )
if target and kindOf ( target . info ) == 1 and not target . name and not anonymousStructs [ rid ] then
local declaration = decodeStruct ( rid , target )
declaration . name = entry . name
declaration . typedefName = true
declaration . unit = unitOf [ rid ] or unitOf [ id ]
structs [ # structs + 1 ] = declaration
anonymousStructs [ rid ] = true
end
elseif entry . name then
if kind == 1 then
local declaration = decodeStruct ( id , entry )
declaration . unit = unitOf [ id ]
structs [ # structs + 1 ] = declaration
elseif kind == 6 then
local declaration = decodeFunction ( entry )
declaration . unit = unitOf [ id ]
functions [ # functions + 1 ] = declaration
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
for id in ctypes ( ) do
before [ id ] = true
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
for id , entry in ctypes ( ) do
if entry . name and kindOf ( entry . info ) == 6 and ( not before [ id ] or spelled [ entry . name ] ) then
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



local layoutCache = { }





function cdecl . layout ( kind , body ) 
local key = kind .. "\0" .. body
local hit = layoutCache [ key ]
if hit then
return hit
end
local ok , ct = pcall ( ffi . typeof , kind .. " { " .. body .. " }" )
if not ok then
return nil , ( tostring ( ct ) : gsub ( "^.-:%d+:%s*" , "" ) )
end
local rid , entry = resolve ( tonumber ( ct ) )
if not entry or kindOf ( entry . info ) ~= 1 then
return nil , "not an aggregate: " .. body
end
local declaration = decodeStruct ( rid , entry )
local result = { size = declaration . size , align = declaration . align , fields = declaration . fields }
layoutCache [ key ] = result

return result
end


function cdecl . sizeof ( spec ) 
local ok , size = pcall ( ffi . sizeof , spec )
if ok and type ( size ) == "number" then
return size
end

return nil
end



function cdecl . float32 ( value ) 
return tonumber ( ffi . new ( "float" , value ) )
end

function cdecl . structById ( id ) 
local rid , entry = resolve ( id )
if not entry or kindOf ( entry . info ) ~= 1 then
return nil
end

return decodeStruct ( rid , entry )
end






function cdecl . declaredFunctions ( only ) 
local out = { }
for _ , entry in ctypes ( ) do
if entry . name and kindOf ( entry . info ) == 6 and ( only == nil or only [ entry . name ] ) then
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

local __nuppExportValue= cdecl ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.cinterop.cdecl"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.cinterop.cdecl"]=__nuppExports;return __nuppExports