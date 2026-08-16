_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);









local targetLayout = require ( "nupp.compiler.target_layout" )
local reflection = require ( "nupp.compiler.reflection" )
local hash = require ( "nupp.compiler.build.hash" )

const cabi = {} cabi.__index = cabi









cabi . ABI = 1

local SCALARS

= {
boolean = "_Bool" ,
float = "float" ,
number = "double" ,
integer = "int32_t" ,
int8 = "int8_t" ,
int16 = "int16_t" ,
int32 = "int32_t" ,
int64 = "int64_t" ,
uint8 = "uint8_t" ,
uint16 = "uint16_t" ,
uint32 = "uint32_t" ,
uint64 = "uint64_t" ,
cstring = "const char *" ,
string = "const char *" ,
voidptr = "void *" ,
}

local function optionalPointer ( t )
if t and t . tag == "union" and t . hasNil and # ( t . members or { } ) == 2 then
local first , second = t . members [ 1 ] , t . members [ 2 ]
local other = first and first . tag == "nil" and second or first
if other and ( other . tag == "ptr" or other . tag == "cstring" or other . tag == "voidptr" ) then
return other
end
end

return nil
end

local function identityOf ( t )
local origin = t and ( t . origin or t ) or nil
local moduleName = origin and origin . moduleName or nil
local name = origin and origin . name or "anonymous"
return ( moduleName and moduleName .. "." or "" ) .. name
end

local function encodeNameByte ( byte )
return ( "_%02X" ) : format ( byte : byte ( ) )
end

function cabi . identity ( t )
return identityOf ( t )
end



local function cName ( identity )
local out = { "nupp" }
for component in identity : gmatch ( "[^%.]+" ) do
local encoded = component : gsub ( "[^%w]" , encodeNameByte )
out [ # out + 1 ] = tostring ( # component )
out [ # out + 1 ] = encoded
end

return table . concat ( out , "_" )
end

local function ordinaryStruct ( t )
return t ~= nil and t . tag == "nominal" and t . declKind == "struct" and not t . cdefName
end

local function baseName ( t )
local scalar = t and SCALARS [ t . tag ] or nil
if scalar then
return scalar
end
if t and t . tag == "nominal" and t . declKind == "struct" then
if t . cdefName then
return ( t . cdefKind or "struct" ) .. " " .. t . cdefName
end
return cName ( identityOf ( t ) )
end

return nil , ( t and tostring ( t . tag ) or "unresolved type" ) .. " has no C spelling"
end

local function renderDeclaration ( t , name , eraseOrdinaryPointer )
while t and ( t . tag == "affine" or t . tag == "borrowed" ) do
t = t . inner
end
local optional = optionalPointer ( t )
if optional then
t = optional
end
if not t then
return nil , "the type is unresolved"
end
if t . tag == "const" then
local rendered , why = renderDeclaration ( t . inner , name , eraseOrdinaryPointer )
if not rendered then
return nil , why
end
return "const " .. rendered
elseif t . tag == "ptr" then
local pointee = t . elem
if eraseOrdinaryPointer then
local unqualified = pointee and pointee . tag == "const" and pointee . inner or pointee
if ordinaryStruct ( unqualified ) then
return "void *" .. ( # name > 0 and " " .. name or "" )
end
end
local pointerName = "*" .. name
if pointee and pointee . tag == "carray" then
pointerName = "(" .. pointerName .. ")"
end
return renderDeclaration ( pointee , pointerName , eraseOrdinaryPointer )
elseif t . tag == "carray" then
if eraseOrdinaryPointer then
local element = t . elem and t . elem . tag == "const" and t . elem . inner or t . elem
if ordinaryStruct ( element ) then
return "void *" .. ( # name > 0 and " " .. name or "" )
end
end
local count = t . count and tostring ( t . count ) or ""
return renderDeclaration ( t . elem , name .. "[" .. count .. "]" , eraseOrdinaryPointer )
elseif t . tag == "func" then
local parameters = { }
for index , parameter in ipairs ( t . params or { } ) do
local rendered , why = renderDeclaration ( parameter , "" , eraseOrdinaryPointer )
if not rendered then
return nil , ( "callback parameter %d %s" ) : format ( index , why or "has no C spelling" )
end
parameters [ # parameters + 1 ] = rendered
end
if t . varargs then
parameters [ # parameters + 1 ] = "..."
end
if # parameters == 0 then
parameters [ 1 ] = "void"
end
local result = "void"
if t . rets and t . rets [ 1 ] then
local rendered , why = renderDeclaration ( t . rets [ 1 ] , "" , false )
if not rendered then
return nil , "callback result " .. tostring ( why )
end
result = rendered
end
return result .. " (*" .. name .. ")(" .. table . concat ( parameters , ", " ) .. ")"
end
local base , why = baseName ( t )
if not base then
return nil , why
end

return base .. ( # name > 0 and " " .. name or "" )
end

function cabi . declaration ( t , name , view )
return renderDeclaration ( t , name , view == "ffi" )
end

local function collectDependencies (
t ,
byValue ,
byPointer ,
valueSeen ,
pointerSeen ,
throughPointer
)
if not t then
return
end
if t . tag == "const" then
collectDependencies ( t . inner , byValue , byPointer , valueSeen , pointerSeen , throughPointer )
elseif t . tag == "ptr" then
collectDependencies ( t . elem , byValue , byPointer , valueSeen , pointerSeen , true )
elseif t . tag == "carray" then
collectDependencies ( t . elem , byValue , byPointer , valueSeen , pointerSeen , throughPointer )
elseif ordinaryStruct ( t ) then
if throughPointer and not pointerSeen [ t ] then
pointerSeen [ t ] = true
byPointer [ # byPointer + 1 ] = t
elseif not throughPointer and not valueSeen [ t ] then
valueSeen [ t ] = true
byValue [ # byValue + 1 ] = t
end
end
end

function cabi . aggregate ( t , target )
if not ordinaryStruct ( t ) then
return nil , "only ordinary Nupp structs have canonical exported C identities"
end
local layout , why = targetLayout . of ( t , target )
if not layout then
return nil , why
end
local identity = identityOf ( t )
local semantic = reflection . describe ( t , identity ) . fingerprint
local dependencies , pointerDependencies , seen , pointerSeen = { } , { } , { } , { }
local fields = { }
for index , name in ipairs ( t . fieldOrder or { } ) do
local fieldType = t . byname and t . byname [ name ] or nil
local declaration , fieldWhy = renderDeclaration ( fieldType , name )
if not declaration then
return nil , ( "field %q %s" ) : format ( name , fieldWhy or "has no C spelling" )
end
collectDependencies ( fieldType , dependencies , pointerDependencies , seen , pointerSeen )
local measured = layout . fields [ index ]
fields [
# fields + 1
] = {
name = name ,
type = fieldType ,
cType = declaration ,
offset = measured . offset ,
size = measured . size ,
alignment = measured . alignment ,
}
end
local typedef = cName ( identity )
local layoutFingerprint = hash . sha256 (
"nupp.cabi\0v" .. tostring ( cabi . ABI ) .. "\0" .. semantic .. "\0" .. layout . fingerprint
)

return {
schema = cabi . ABI ,
identity = identity ,
semanticFingerprint = semantic ,
target = target ,
layoutSchema = targetLayout . ABI ,
layoutFingerprint = layoutFingerprint ,
size = layout . size ,
alignment = layout . alignment ,
fields = fields ,
dependencies = dependencies ,
pointerDependencies = pointerDependencies ,
tag = typedef .. "_tag" ,
typedef = typedef ,
type = t ,
}
end

function cabi . functionRecord ( symbol , params , result , varargs , convention )
return {
schema = cabi . ABI ,
symbol = symbol ,
params = params ,
result = result ,
varargs = varargs == true ,
convention = convention or "c" ,
}
end

function cabi . prototype ( signature , erased )
if not signature or signature . schema ~= cabi . ABI then
return nil , "the C function signature has an unsupported schema"
end
local params = { }
for index , parameter in ipairs ( signature . params or { } ) do
local declaration , why = renderDeclaration (
parameter . type ,
erased and "" or ( parameter . name or ( "arg" .. tostring ( index ) ) ) ,
erased
)
if not declaration then
return nil , ( "parameter %d %s" ) : format ( index , why or "has no C spelling" )
end
params [ # params + 1 ] = declaration
end
if signature . varargs then
params [ # params + 1 ] = "..."
end
if # params == 0 then
params [ 1 ] = "void"
end
local result = "void"
if signature . result then
local rendered , why = renderDeclaration ( signature . result , "" , false )
if not rendered then
return nil , "result " .. tostring ( why )
end
result = rendered
end

return result .. " " .. signature . symbol .. "(" .. table . concat ( params , ", " ) .. ");"
end

local function macroName ( name )
local rendered = name : upper ( ) : gsub ( "[^A-Z0-9]" , "_" )
return rendered
end

function cabi . header ( aggregates , functions , guard )
local descriptions , byType = { } , { }
local visiting , visited = { } , { }
local function visit ( t )
if visited [ t ] then
return nil
end
if visiting [ t ] then
return "a by-value struct dependency cycle has no finite C declaration"
end
visiting [ t ] = true
local description = byType [ t ]
if not description then
return "a dependency was not described for the selected target"
end
for _ , dependency in ipairs ( description . dependencies or { } ) do
local why = visit ( dependency )
if why then
return why
end
end
visiting [ t ] , visited [ t ] = nil , true
descriptions [ # descriptions + 1 ] = description

return nil
end

for _ , description in ipairs ( aggregates or { } ) do
byType [ description . type ] = description
end
for _ , description in ipairs ( aggregates or { } ) do
local why = visit ( description . type )
if why then
return nil , why
end
end

guard = macroName ( guard or "NUPP_EXPORTED_C_H" )
local out = {
"#ifndef " .. guard ,
"#define " .. guard ,
"" ,
"#include <stddef.h>" ,
"#include <stdint.h>" ,
"" ,
"#if defined(__cplusplus)" ,
"extern \"C\" {" ,
"#endif" ,
"" ,
}
for _ , description in ipairs ( descriptions ) do
out [ # out + 1 ] = "typedef struct " .. description . tag .. " " .. description . typedef .. ";"
end
if # descriptions > 0 then
out [ # out + 1 ] = ""
end
for _ , description in ipairs ( descriptions ) do
out [ # out + 1 ] = "struct " .. description . tag .. " {"
for _ , field in ipairs ( description . fields ) do
out [ # out + 1 ] = "    " .. field . cType .. ";"
end
out [ # out + 1 ] = "};"
local prefix = macroName ( description . typedef )
out [ # out + 1 ] = "#define " .. prefix .. "_LAYOUT_FINGERPRINT \"" .. description . layoutFingerprint .. "\""
out [
# out + 1
] = (
"_Static_assert(sizeof(%s) == %d, \"%s size\");"
) : format ( description . typedef , description . size , description . identity )
out [
# out + 1
] = (
"_Static_assert(_Alignof(%s) == %d, \"%s alignment\");"
) : format ( description . typedef , description . alignment , description . identity )
for _ , field in ipairs ( description . fields ) do
out [
# out + 1
] = (
"_Static_assert(offsetof(%s, %s) == %d, \"%s.%s offset\");"
) : format ( description . typedef , field . name , field . offset , description . identity , field . name )
end
out [ # out + 1 ] = ""
end
for _ , signature in ipairs ( functions or { } ) do
local prototype , why = cabi . prototype ( signature , false )
if not prototype then
return nil , why
end
out [ # out + 1 ] = prototype
end
if # ( functions or { } ) > 0 then
out [ # out + 1 ] = ""
end
out [ # out + 1 ] = "#if defined(__cplusplus)"
out [ # out + 1 ] = "}"
out [ # out + 1 ] = "#endif"
out [ # out + 1 ] = ""
out [ # out + 1 ] = "#endif"
out [ # out + 1 ] = ""

return table . concat ( out , "\n" )
end

return cabi
