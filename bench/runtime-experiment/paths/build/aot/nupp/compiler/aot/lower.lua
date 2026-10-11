_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.math").install(rawget(__nupp,"math")) require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\0004") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\0005") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\0006") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\0007") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\0008") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\0009") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\00010") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\00011") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\00012") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\00013") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\00014") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\00015") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\00016") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\00017") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\00018") , _G.nupp.__reflect.declaration("nupp.compiler.aot.lower\0runtime\00019") };















local admit = require ( "nupp.compiler.aot.admit" )
local targetLayout = require ( "nupp.compiler.targetlayout" )
local carriedFacts = require ( "nupp.compiler.aot.carried" )
local reducers = require ( "nupp.compiler.aot.reducers" )
local simdindices = require ( "nupp.compiler.aot.simdindices" )
local simdcast = require ( "nupp.compiler.aot.simdcast" )
local shapes = require ( "nupp.compiler.aot.simdshape" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local cst = require ( "nupp.compiler.syntax.cst" )
local relations = require ( "nupp.compiler.aot.relations" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )
local simdbounds = require ( "nupp.compiler.aot.simdbounds" )
local visit = require ( "nupp.compiler.aot.visit" )
local switchplan = require ( "nupp.compiler.lua.switchplan" )
local T = require ( "nupp.compiler.types" )

local lower = { }


lower.Context = {} lower.Context.__index = lower.Context ;_G.nupp.__reflect.link(lower.Context,__nuppT1[1],{ })










































function lower . sourceValueType ( spelling ) 
if spelling == "boolean" then
return "bool"
elseif spelling == "number" or spelling == "integer" then
return "f64"
elseif spelling == "float" then
return "f32"
elseif spelling == "uint32" then
return "u32"
elseif spelling == "int32" then
return "i32"
elseif spelling == "uint64" then
return "u64"
elseif spelling == "int64" then
return "i64"
elseif spelling == "string" then
return "lua_string"
elseif spelling : sub ( 1 , 1 ) == "{" or spelling == "table" then
return "lua_table"
end

return nil
end






function lower . conversion ( value , targetType , source ) 
if value . type == targetType then
return value
end

local op = nil
if targetType == "f64"
and ( value . type == "i32" or value . type == "u32" or value . type == "i64" or value . type == "u64" )
then
op = "int_to_f64"
elseif targetType == "f64" and value . type == "f32" then
op = "widen_f32_f64"
elseif targetType == "f32" and value . type == "f64" then
op = "narrow_f64_f32"
elseif ( targetType == "i32" or targetType == "u32" or targetType == "i64" or targetType == "u64" )
and (
value . type == "f64"
or value . type == "i32"
or value . type == "u32"
or value . type == "i64"
or value . type == "u64"
)
then
op = "numeric_cast"
end
if op == nil then
return nil
end

return ( _G.setmetatable({ op =  op ,  value =  value ,  type =  targetType ,  source =  source }, scalarIR.Convert) )
end


function lower . convert (
value ,
targetType ,
source ,
context
) 
if context . unreachableValues [ value ] then
return lower . zeroValue ( targetType , source , context )
end
local converted = lower . conversion ( value , targetType , source )
if converted == nil then
context . reject (
source ,
"native value cannot convert from " .. tostring ( value . type ) .. " to " .. tostring ( targetType )
)
end

return converted
end






function lower . storeConvert (
value ,
targetType ,
source ,
context
) 
if value . type == "f64"
and ( targetType == "i32" or targetType == "u32" or targetType == "i64" or targetType == "u64" )
and not context . unreachableValues [ value ]
then
return ( _G.setmetatable({ op =  "store_cast" ,  value =  value ,  type =  targetType ,  source =  source }, scalarIR.Convert) )
end

return lower . convert ( value , targetType , source , context )
end








local function exactWidthConstant ( value , wanted ) 
if wanted ~= "i32" and wanted ~= "u32" then
return nil
end
local raw = value
if raw . op ~= "constant" or value . type ~= "f64" then
return nil
end
local number = tonumber ( raw . value )
local low = wanted == "u32" and 0 or lower . INT32_MIN
local high = wanted == "u32" and lower . UINT32_MAX or lower . INT32_MAX
if number == nil or number % 1 ~= 0 or number < low or number > high then
return nil
end

return ( _G.setmetatable({ op =
"constant_i32" ,  value =
raw . value ,  type =
wanted ,  source =
value . source }, scalarIR.IntConstant) )

end



function lower . roundTripsBinary32 ( value ) 
return nupp . math . f32 . narrow ( value ) == value
end







function lower . helperArgument (
value ,
wanted ,
source ,
context
) 
if value . type == wanted then
return value
end
local exact = exactWidthConstant ( value , wanted )
if exact ~= nil then
return exact
end
if wanted == "f32" then



if value . op == "widen_f32_f64" then
return ( value ) . value
end
if value . op == "constant" then
local number = tonumber ( ( value ) . value )
if number ~= nil and ( number ~= number or lower . roundTripsBinary32 ( number ) ) then
return ( _G.setmetatable({ op =  "narrow_f64_f32" ,  value =  value ,  type =  "f32" ,  source =  value . source }, scalarIR.Convert) )
end
end
context . reject ( source , "native helper argument type does not match" )
end
if wanted ~= "f64" then
context . reject ( source , "native helper argument type does not match" )
end

local widened = lower . conversion ( value , "f64" , value . source )
if widened == nil then
context . reject ( source , "native helper argument type does not match" )
end

return widened
end






function lower . site ( node ) 
local token = node ~= nil and cst . firstToken ( node ) or nil
if token == nil then
return ( _G.setmetatable({ line =  1 ,  column =  1 }, scalarIR.Source) )
end

return ( _G.setmetatable({ line =  ( token ) . line ,  column =  ( token ) . col }, scalarIR.Source) )
end



function lower . compactType ( node ) 
if node == nil then
return ""
end

return ( cst . textOf ( node ) : gsub ( "%s+" , "" ) )
end






local function checkedType ( node , context ) 
if not context . checked then
return nil
end
local resolved = node ~= nil and ( node ) . resolvedType or nil
if resolved == nil then
context . reject ( lower . site ( node ) , "the checker did not publish this AOT type" )
end

return resolved
end






local function semanticRaw ( t ) 
local raw = t ~= nil and T . unwrapOwnership ( t ) or nil
while raw ~= nil and raw . tag == "genericAlias" and # ( raw . paramKinds or { } ) == 0 do
raw = T . unwrapOwnership ( raw . body )
end

return raw
end


local function nominal ( t ) 
local raw = semanticRaw ( t )
if raw == nil or raw . tag ~= "nominal" then
return nil , nil
end

return raw , raw . origin or raw
end






local function genericSimdType ( t ) 
local raw , origin = nominal ( t )
if raw == nil or origin == nil or origin . moduleName ~= "nupp.simd" then
return nil
end
local family = origin . name
if family ~= "Vector" and family ~= "Mask" and family ~= "Species" then
return nil
end
local arguments = raw . typeArgs or { }
local element = semanticRaw ( arguments [ 1 ] )
local elementNames

= {
number = "f64" ,
integer = "f64" ,
float = "f32" ,
int8 = "i8" ,
uint8 = "u8" ,
int16 = "i16" ,
uint16 = "u16" ,
int32 = "i32" ,
uint32 = "u32" ,
int64 = "i64" ,
uint64 = "u64" ,
}
local elementName = element ~= nil and elementNames [ element . tag ] or nil
local species , speciesOrigin = nominal ( arguments [ 2 ] )
local shape = nil
if speciesOrigin ~= nil and speciesOrigin . moduleName == "nupp.simd" and speciesOrigin . name == "Preferred" then
shape = "preferred"
elseif species ~= nil
and speciesOrigin ~= nil
and speciesOrigin . moduleName == "nupp.simd"
and speciesOrigin . name == "Fixed"
then
local count = ( species . constArgs or { } ) [ 1 ]
if count ~= nil and count . tag == "constLiteral" and count . domain == "integer" then
shape = "fixed" .. tostring ( count . value )
end
end
if elementName == nil or shape == nil then
return nil
end

return "simd_" .. family : lower ( ) .. "_" .. elementName .. "_" .. shape
end






local function sourceSpelling ( t ) 
local raw = semanticRaw ( t )
if raw . tag == "nominal" then
local _ , origin = nominal ( raw )
if origin ~= nil and origin . moduleName == nil then
return origin . name
end
end

return T . tostring ( raw )
end






local function semanticValueType ( t , helper ) 
if t == nil then
return nil
end
local raw = semanticRaw ( t )
local tag = raw . tag
if tag == "literal" then
return semanticValueType ( raw . base , helper )
elseif tag == "boolean" then
return "bool"
elseif tag == "number" or tag == "integer" then
return "f64"
elseif tag == "float" then
return helper and "f64" or "f32"
elseif tag == "uint32" then
return "u32"
elseif tag == "int32" then
return "i32"
elseif tag == "uint64" then
return "u64"
elseif tag == "int64" then
return "i64"
elseif tag == "string" then
return "lua_string"
elseif tag == "union" then
local hasString , hasBuffer = false , false
for _ , member in ipairs ( raw . members or { } ) do
local item = semanticRaw ( member )
local _ , origin = nominal ( item )
hasString = hasString or item . tag == "string"
hasBuffer = hasBuffer or origin ~= nil and origin . name == "Buffer"
end
if hasString and hasBuffer and # ( raw . members or { } ) == 2 then
return "lua_bytes"
end
local common = nil
for _ , member in ipairs ( raw . members or { } ) do
local valueType = semanticValueType ( member , helper )
if valueType == nil or common ~= nil and common ~= valueType then
return nil
end
common = valueType
end
return common
elseif tag == "nil" then
return "lua_nil"
elseif tag == "any" then
return "lua_value"
elseif tag == "table" or tag == "array" or tag == "map" or tag == "tuple" or tag == "shape" then
return "lua_table"
end

local _ , origin = nominal ( raw )
if origin ~= nil and origin . declKind == "struct" and origin . nativeOnly == true then
return "aggregate:" .. tostring ( origin . name )
end
if origin == nil or origin . moduleName ~= "nupp.simd" then
return nil
end
local generic = genericSimdType ( raw )
if generic ~= nil then
return generic
end
for _ , contract in pairs ( reducers . CONSTRUCTORS ) do
if origin . name == contract . recordName then
local argument = semanticRaw ( ( raw . typeArgs or { } ) [ 1 ] )
local element = contract . element
if contract . order == "integer" or contract . order == "exact" and contract . element ~= "bool" then
element = argument ~= nil and admit . STORAGE [ argument . tag ] or nil
elseif reducers . floatingOrder ( contract . order ) then


element = argument ~= nil and admit . STORAGE [ argument . tag ] or "f64"
end
if element ~= nil and reducers . valid ( contract . order , contract . operation , element ) then
return reducers . typeName ( contract . order , contract . operation , element )
end
end
end



for _ , contract in pairs ( reducers . FLOATING ) do
if origin . name == contract . recordName then
local argument = semanticRaw ( ( raw . typeArgs or { } ) [ 1 ] )
local element = argument ~= nil and admit . STORAGE [ argument . tag ] or nil
if element == "f32" then
return reducers . typeName ( contract . order , contract . operation , "f32" )
elseif element == "f64" then
return "simd_reducer_" .. contract . order .. "_" .. contract . operation
end
return nil
end
end

return nil
end


local function semanticStorageType ( t ) 
local raw = semanticRaw ( t )

return raw ~= nil and admit . STORAGE [ raw . tag ] or nil
end


local function annotatedValueType ( node , context , helper ) 
if node == nil then
return nil
end
if context . checked then
return semanticValueType ( checkedType ( node , context ) , helper )
end
local spelling = lower . compactType ( node )

return helper and lower . helperValueType ( spelling ) or lower . sourceValueType ( spelling )
end







local function stringBytes ( written ) 
local decoded = lexer . stringValue ( written )
if decoded ~= nil then
return decoded
end
local equals = written : match ( "^%[(=*)%[" )
if equals ~= nil then
local width = # ( equals ) + 2
return written : sub ( width + 1 , - width - 1 )
end

return written
end


function lower . unwrapped ( node ) 
local current = node
while current ~= nil and ( current . kind == "paren" or current . kind == "castExpr" ) do
current = current . kind == "paren" and ( current ) . expr or ( current ) . expr
end

return current
end









lower.Layouts = {} lower.Layouts.__index = lower.Layouts ;_G.nupp.__reflect.link(lower.Layouts,__nuppT1[2],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00079","nupp.compiler.aot.scalar") })










function lower . aggregate (
resolved ,
at ,
layouts ,
context
) 
local _ , origin = nominal ( resolved )
if not context . checked or origin == nil or origin . declKind ~= "struct" or origin . nativeOnly ~= true then
context . reject ( lower . site ( at ) , "a native-only aggregate must resolve to a struct holding a vector or a mask" )
end
local name = tostring ( origin . name )
local known = layouts . byName [ name ]
if known ~= nil then
return known
end
if # ( origin . typeParams or { } ) > 0 or # ( origin . supertypes or { } ) > 0 then
context . reject ( lower . site ( at ) , "native-only aggregates must be non-generic and have no supertypes" )
end
local layout = _G.setmetatable({ name =
name ,  uniqueName =
"Ka" .. name ,  fields =
{ } ,  nativeOnly =
true ,  source =
lower . site ( at ) }, scalarIR.Layout)



layouts . byName [ name ] = layout
for _ , fieldName in ipairs ( origin . fieldOrder or { } ) do
local fieldType = origin . byname and origin . byname [ fieldName ] or nil
local site = origin . fieldDefs and origin . fieldDefs [ fieldName ] ~= nil and origin . fieldDefs [ fieldName ] . token or at
local valueType = semanticValueType ( fieldType )
local nested = scalarIR . aggregateLayout ( valueType )
if nested ~= nil then
if nested == name then
context . reject ( lower . site ( site ) , "a native-only aggregate cannot hold itself" )
end
lower . aggregate ( fieldType , site , layouts , context )
elseif valueType == nil
or not (
scalarIR . nativeOnlyType ( valueType )
or valueType == "f32"
or valueType == "f64"
or valueType == "i32"
or valueType == "u32"
or valueType == "i64"
or valueType == "u64"
or valueType == "bool"
)
then
context . reject (
lower . site ( site ) ,
"native-only aggregate field " .. name .. "." .. fieldName .. " is " .. tostring (
fieldType ~= nil and T . tostring ( fieldType ) or "unknown"
) .. ", not a vector, a mask, a scalar or another native-only aggregate"
)
end
layout . fields [
# layout . fields + 1
] = _G.setmetatable({ name =
fieldName ,  type =
valueType ,  sourceType =
fieldType ~= nil and sourceSpelling ( fieldType ) or nil }, scalarIR.Field)

end
if # layout . fields == 0 then
context . reject ( lower . site ( at ) , "native-only aggregates need at least one field" )
end
layouts . ordered [ # layouts . ordered + 1 ] = layout

return layout
end







function lower . layout (
name ,
resolved ,
at ,
declarations ,
layouts ,
context
) 
local semantic , origin = nominal ( resolved )
if context . checked then
if semantic == nil or origin == nil or origin . declKind ~= "struct" then
context . reject ( lower . site ( at ) , "span elements with fields must resolve to a struct" )
end
if origin . nativeOnly == true then



local culprit = "a field"
for _ , fieldName in ipairs ( origin . fieldOrder or { } ) do
local fieldType = origin . byname and origin . byname [ fieldName ] or nil
if scalarIR . nativeOnlyType ( semanticValueType ( fieldType ) ) then
culprit = fieldName .. ": " .. T . tostring ( fieldType )
do break end
end
end
context . reject (
lower . site ( at ) ,
"struct " .. tostring (
origin . name
) .. " is a native-only aggregate (" .. culprit .. ") and cannot be a span element"
)
end
name = origin . name
end
local known = layouts . byName [ name ]
if known ~= nil then
return known
end

local found = declarations [ name ]
if found == nil then
context . reject ( lower . site ( at ) , "span element " .. name .. " is not a visible local struct" )
end

local declaration = found
if context . checked then
local declared = declaration . resolvedType
local _ , declaredOrigin = nominal ( declared )
if declaredOrigin == nil or declaredOrigin . id ~= origin . id then
context . reject ( lower . site ( at ) , "span element " .. name .. " is not the visible local struct of that name" )
end
elseif declaration . generics ~= nil or # ( declaration . supertypes or { } ) > 0 then
context . reject ( lower . site ( declaration ) , "native structs must be non-generic and have no supertypes" )
end

local layout = _G.setmetatable({ name =
name ,  uniqueName =
"Ks" .. name ,  fields =
{ } ,  source =
lower . site ( declaration ) }, scalarIR.Layout)

if context . checked then
if # ( origin . typeParams or { } ) > 0 or # ( origin . supertypes or { } ) > 0 then
context . reject ( lower . site ( declaration ) , "native structs must be non-generic and have no supertypes" )
end
local fields = origin . fieldOrder or { }
for _ , fieldName in ipairs ( fields ) do
local fieldType = origin . byname and origin . byname [ fieldName ] or nil
local storage = semanticStorageType ( fieldType )



local storedVector = targetLayout . storageVector ( fieldType ) ~= nil
if storedVector then
storage = genericSimdType ( fieldType )
end
if storage == nil then
context . reject (
lower . site ( origin . fieldDefs and origin . fieldDefs [ fieldName ] or declaration ) ,
"native struct field type " .. tostring (
fieldType ~= nil and T . tostring ( fieldType ) or "unknown"
) .. " is not admitted"
)
end
layout . fields [
# layout . fields + 1
] = _G.setmetatable({ name =
fieldName ,  type =
storage ,  sourceType =
not storedVector and sourceSpelling ( fieldType ) or nil ,  source =
lower . site ( origin . fieldDefs and origin . fieldDefs [ fieldName ] or declaration ) }, scalarIR.Field)

end
if # layout . fields == 0 then
context . reject ( lower . site ( declaration ) , "native structs need at least one field" )
end
layouts . byName [ name ] = layout
layouts . ordered [ # layouts . ordered + 1 ] = layout

return layout
end

local seen = { }
for _ , entry in ipairs ( declaration . entries ) do
local field = entry
if entry . kind ~= "fieldDecl" or field . name == nil then
context . reject ( lower . site ( entry ) , "native structs initially contain only stored fields" )
end

local fieldName = ( field . name ) . text
local spelling = lower . compactType ( field . type )
local fieldType = admit . STORAGE [ spelling ]
if fieldType == nil then
context . reject (
lower . site ( field . type or entry ) ,
"native struct field type " .. spelling .. " is not admitted"
)
end
if seen [ fieldName ] then
context . reject ( lower . site ( entry ) , "duplicate native struct field " .. fieldName )
end
seen [ fieldName ] = true
layout . fields [
# layout . fields + 1
] = _G.setmetatable({ name =
fieldName ,  type =
fieldType ,  sourceType =
spelling ,  source =
lower . site ( entry ) }, scalarIR.Field)

end
if # layout . fields == 0 then
context . reject ( lower . site ( declaration ) , "native structs need at least one field" )
end

layouts . byName [ name ] = layout
layouts . ordered [ # layouts . ordered + 1 ] = layout

return layout
end


lower.Element = {} lower.Element.__index = lower.Element ;_G.nupp.__reflect.link(lower.Element,__nuppT1[3],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00079","nupp.compiler.aot.scalar") })


















function lower . spanElement (
spelling ,
resolved ,
expected ,
at ,
declarations ,
layouts ,
context
) 
if context . checked then
local span , origin = nominal ( resolved )
if span == nil
or origin == nil
or ( origin . moduleName ~= "nupp.mem.span" )
or origin . name ~= expected
or span . typeArgs == nil
or span . typeArgs [ 1 ] == nil
then
return nil
end
local elementType = span . typeArgs [ 1 ]
local storage = semanticStorageType ( elementType )
if storage ~= nil then
return ( _G.setmetatable({ kind =
"scalar" ,  type =
storage ,  sourceType =
sourceSpelling ( elementType ) ,  spanModule =
origin . moduleName }, lower.Element) )

end
local _ , elementOrigin = nominal ( elementType )
if elementOrigin == nil or elementOrigin . declKind ~= "struct" then
context . reject (
lower . site ( at ) ,
"span element " .. T . tostring ( elementType ) .. " has no admitted physical layout"
)
end

return ( _G.setmetatable({ kind =
"struct" ,  type =
"struct:" .. elementOrigin . name ,  layout =
lower . layout ( elementOrigin . name , elementType , at , declarations , layouts , context ) ,  spanModule =
origin . moduleName }, lower.Element) )

end

local suffix = expected == "WriteSpan" and "WriteSpan" or "Span"
local _module , element = spelling : match ( "^(span)%." .. suffix .. "<(.+)>$" )
if element == nil then
return nil
end

local storage = admit . STORAGE [ element ]
if storage ~= nil then
return ( _G.setmetatable({ kind =
"scalar" ,  type =
storage ,  sourceType =
element ,  spanModule =
"nupp.mem.span" }, lower.Element) )

end

return ( _G.setmetatable({ kind =
"struct" ,  type =
"struct:" .. ( element ) ,  layout =
lower . layout ( element , nil , at , declarations , layouts , context ) ,  spanModule =
"nupp.mem.span" }, lower.Element) )

end


local function soaElement ( resolved ) 
local raw = semanticRaw ( resolved )
local members = raw ~= nil and raw . tag == "intersection" and raw . members or { raw }
local element = nil
local writable = false
local token = false
for _ , member in ipairs ( members ) do
local view , origin = nominal ( member )
if origin == nil or origin . moduleName ~= "nupp.mem.soa" then
return nil , false
end
if origin . name == "WriteToken" and not token then
token = true
elseif ( origin . name == "Span" or origin . name == "WriteSpan" ) and element == nil then
element = ( view . typeArgs or { } ) [ 1 ]
writable = origin . name == "WriteSpan"
else
return nil , false
end
end
if token and not writable then
return nil , false
end

return element , writable
end






function lower . nameOf ( node ) 
if node == nil or node . kind ~= "name" then
return nil
end

local token = ( node ) . token

return token ~= nil and ( token ) . text or nil
end





function lower . dottedName ( node ) 
if node == nil then
return nil
end
if node . kind == "name" then
return lower . nameOf ( node )
end
if node . kind == "dotIndex" then
local indexed = node
if indexed . name == nil then
return nil
end

local base = lower . dottedName ( indexed . obj )

return base ~= nil and ( base ) .. "." .. ( indexed . name ) . text or nil
end

return nil
end






function lower . callIdentity ( node ) 
if node == nil then
return nil
end
local direct = ( node ) . exactCallExport
if direct ~= nil then
return direct . identity
end
if node . kind == "dotIndex" then
local indexed = node
local base = indexed . obj
local token = base ~= nil and base . kind == "name" and ( base ) . token or nil
local definition = token ~= nil and ( token ) . definition or nil
local moduleName = definition ~= nil and definition . requiredModule or nil
if moduleName ~= nil and indexed . name ~= nil then
return moduleName .. "." .. ( indexed . name ) . text
end
end
if node . kind == "name" then
local token = ( node ) . token
local definition = token ~= nil and ( token ) . definition or nil
local aliased = definition ~= nil and definition . exactCallExport or nil
if aliased ~= nil then
return aliased . identity
end
end

return nil
end






lower.Bound = {} lower.Bound.__index = lower.Bound ;_G.nupp.__reflect.link(lower.Bound,__nuppT1[4],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0001","nupp.compiler.aot.scalar") })















lower.GuardForm = {} lower.GuardForm.__index = lower.GuardForm ;_G.nupp.__reflect.link(lower.GuardForm,__nuppT1[5],{ _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00033","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00034","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00071","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00041","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00029","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00035","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00021","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00082","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0002","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00065","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00024","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00070","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00030","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00049","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00083","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00044","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00045","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0001","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00028","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00059","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00062","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00025","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00053","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00090","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00013","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00064","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00011","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00010","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0003","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00063","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00031","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000115","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0005","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00056","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00075","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00039","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00077","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00076","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00015","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00014","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00080","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00017","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00048","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00018","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00046","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00023","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0009","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0008","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00040","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00042","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00084","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00079","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00022","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00019","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00020","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00043","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00066","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0004","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00050","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00072","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00060","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00054","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00051","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00085","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00047","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00058","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00073","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00032","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00037","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00016","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00026","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00068","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00069","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00067","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00061","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00078","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00052","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00087","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00088","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00089","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00086","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00074","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000105","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000117","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000110","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00092","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00091","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000106","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000107","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000114","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00093","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00095","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00099","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000112","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000111","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00096","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000108","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000103","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000104","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00098","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000116","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000118","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000109","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00055","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000100","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000101","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000102","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00097","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000113","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00094","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00036","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00081","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00057","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00038","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00012","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0007","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0006","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00027","nupp.compiler.syntax.cst") })













lower.ReducerState = {} lower.ReducerState.__index = lower.ReducerState ;_G.nupp.__reflect.link(lower.ReducerState,__nuppT1[6],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0001","nupp.compiler.aot.scalar") })















lower.ReducerDo = {} lower.ReducerDo.__index = lower.ReducerDo ;_G.nupp.__reflect.link(lower.ReducerDo,__nuppT1[7],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00050","nupp.compiler.aot.scalar") })






lower.ExpressionFrame = {} lower.ExpressionFrame.__index = lower.ExpressionFrame ;_G.nupp.__reflect.link(lower.ExpressionFrame,__nuppT1[8],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00059","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00072","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00073","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00074","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00071","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00068","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00055","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00063","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00064","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00065","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00061","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00062","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00058","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00077","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00048","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00051","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00070","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00075","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00076","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00046","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00060","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00049","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00069","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00044","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00043","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00036","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0005","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0002","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00042","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00041","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00034","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00035","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00039","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00040","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00045","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0004","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0003","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00033","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00030","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00018","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00025","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00027","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00026","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00024","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00010","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00017","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0006","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00019","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00020","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00021","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00022","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00023","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0008","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00014","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00015","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00012","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0009","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00011","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00013","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00038","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00028","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00047","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00052","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00032","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00029","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00037","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00031","nupp.compiler.aot.scalar") })





lower.ValueFrame = {} lower.ValueFrame.__index = lower.ValueFrame ;_G.nupp.__reflect.link(lower.ValueFrame,__nuppT1[9],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00028","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00054","nupp.compiler.aot.scalar") })






lower.Kernel = {} lower.Kernel.__index = lower.Kernel ;_G.nupp.__reflect.link(lower.Kernel,__nuppT1[10],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00059","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00072","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00073","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00074","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00071","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00068","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00055","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00063","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00064","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00065","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00061","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00062","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00058","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00077","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00048","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00051","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00070","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00075","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00076","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00046","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00060","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00049","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00069","nupp.compiler.aot.scalar") , __nuppT1[8] , __nuppT1[9] , __nuppT1[2] , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00088","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0007","nupp.compiler.aot.scalar") , __nuppT1[7] , __nuppT1[6] , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0001","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00066","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00090","nupp.compiler.aot.scalar") , __nuppT1[1] })












































































































































































local function markLua ( kernel , source ) 
kernel . usesLua = true
if kernel . luaSource == nil then
kernel . luaSource = source
end
end


lower . UINT32_MAX = admit . UINT32_MAX

lower . INT32_MIN = admit . INT32_MIN

lower . INT32_MAX = admit . INT32_MAX

local bitOperand = admit . bitOperand






local function promote ( value , at , context ) 
local widened = lower . conversion ( value , "f64" , value . source )
if widened == nil then
context . reject ( lower . site ( at ) , "arithmetic operands must both be numeric" )
end

return widened
end






local function widenLoad ( loaded , source ) 
if loaded . type ~= "f32" then
return loaded
end

return ( _G.setmetatable({ op =  "widen_f32_f64" ,  value =  loaded ,  type =  "f64" ,  source =  source }, scalarIR.Convert) )
end















local function provenIndex ( spanName , cursor , node , kernel ) 
if cursor ~= nil then
return
end
if kernel . mapEntry then
local provable = kernel . indexSpans
if provable ~= nil and ( provable ) [ spanName ] ~= true then
kernel . context . reject (
lower . site ( node ) ,
("nothing proves %s is that long; a map-indexed span must be the loop bound or guarded equal to it; guard with assert(#%s == #%s) or reach it through a proved cursor")


: format ( spanName , tostring ( kernel . boundSpan ) , spanName )
)
end
return
end
local context = kernel . context
if kernel . indexAssigned then
context . reject ( lower . site ( node ) , "an assigned counted-loop index does not prove span access bounds" )
end
if kernel . boundSpan == nil then
context . reject (
lower . site ( node ) ,
("the loop's bound is not a span count, so nothing proves %s is that long; count the loop with for i = 1, #%s")

: format ( spanName , spanName )
)
end
if spanName ~= kernel . boundSpan
and ( ( kernel . spanBounds or { } ) [ tostring ( kernel . boundSpan ) ] or { } ) [ spanName ] ~= true
and not scalarIR . sameSoaView ( kernel . params [ spanName ] , kernel . params [ tostring ( kernel . boundSpan ) ] )
then
context . reject (
lower . site ( node ) ,
("the loop counts %s, so nothing proves %s is that long; guard it with assert(#%s == #%s)")

: format ( kernel . boundSpan , spanName , kernel . boundSpan , spanName )
)
end
end




local function rootedBytesParam ( value , kernel ) 
if value . op ~= "local" or value . type ~= "lua_string" and value . type ~= "lua_bytes" then
return false
end
local rooted = value
local param = kernel . params [ rooted . name ]

return param ~= nil
and param . kind == "scalar"
and param . type == value . type
and rooted . uniqueName == param . uniqueName
end



local function assignedNames ( body , out ) 
if body == nil then
return out
end
local node = body
if node . kind == "funcExpr" or node . kind == "shortfn" or node . kind == "localFuncStmt" then
return out
end
if node . kind == "assignStmt" then
for _ , target in ipairs ( ( node ) . targets or { } ) do
local name = lower . nameOf ( target )
if name ~= nil then
out [ name ] = true
end
end
end
for _ , child in ipairs ( node ) do
if type ( child ) == "table" then
assignedNames ( child , out )
end
end

return out
end



local function boundRoom ( bounds , cursor , root ) 
local spans = cursor ~= nil and bounds [ cursor ] or nil

return spans ~= nil and root ~= nil and spans [ root ] or nil
end





local function withBound ( bounds , cursor , root , room ) 
local spans = { }
for name , held in pairs ( bounds [ cursor ] or { } ) do
spans [ name ] = held
end
spans [ root ] = simdbounds . widen ( spans [ root ] , room )
bounds [ cursor ] = spans
end



local function cursorIndex ( indexArg ) 
if indexArg == nil or indexArg . kind ~= "binop" then
return nil , nil
end
local index = indexArg
local written = index . op ~= nil and ( index . op ) . text or ""
local token = index . rhs ~= nil and index . rhs . kind == "number" and ( index . rhs ) . token or nil
local offset = token ~= nil and tonumber ( ( token ) . text ) or nil
local candidate = lower . nameOf ( index . lhs )
if written ~= "+" or candidate == nil or offset == nil then
return nil , nil
end
local step = offset
if step < 1 or step > lower . UINT32_MAX or step % 1 ~= 0 then
return nil , nil
end

return candidate , step
end









local function provedCursor (
indexArg ,
spanName ,
kernel ,
room
) 
local candidate , step = cursorIndex ( indexArg )
if candidate == nil then
return nil , nil
end
local param = kernel . params [ tostring ( spanName ) ]
local counted = param ~= nil and param . soa ~= nil and param . soa . view or spanName
local bounded = room == nil
and simdbounds . boundedThrough (
kernel . cursorBounds ,
candidate ,
counted ,
kernel . spanBounds ,
step ,
kernel . spanRooms
)
or room ~= nil
and step == 1
and simdbounds . coveredThrough (
kernel . cursorBounds ,
candidate ,
counted ,
kernel . spanBounds ,
room
)
if bounded then
return candidate , ( step ) - 1
end

return nil , nil
end





local function cursorRefusal ( verb , indexArg , spanName , kernel ) 
local base = "span " .. verb .. " need a counted-loop index or cursor + 1 under cursor < #span"
local candidate , step = cursorIndex ( indexArg )
if candidate == nil or step == 1 then
return base
end
local param = kernel . params [ tostring ( spanName ) ]
local counted = param ~= nil and param . soa ~= nil and param . soa . view or spanName
local reach = simdbounds . reach (
kernel . cursorBounds ,
candidate ,
counted ,
kernel . spanBounds ,
kernel . spanRooms
)
local name , span = candidate , tostring ( spanName )
if reach == 0 then
return ("span %s need a counted-loop index or cursor + k under cursor + k - 1 < #span; nothing bounds %s below #%s")

: format ( verb , name , span )
end

return ("span %s at %s + %d need %s + %d < #%s or %s + %d <= #%s dominating them; the bounds give %s room for %d element%s of %s")

: format (
verb ,
name ,
step ,
name ,
( step ) - 1 ,
span ,
name ,
step ,
span ,
name ,
reach ,
reach == 1 and "" or "s" ,
span
)
end



local function provedVectorCursor (
offset ,
spanName ,
kernel ,
room ,
ways
) 
local base , species , count = simdbounds . offset ( offset )
if base == nil or species ~= nil and not simdbounds . covers ( species , room ) then
return nil
end
local name = ( base ) . name
local param = spanName ~= nil and kernel . params [ spanName ] or nil
local counted = param ~= nil and param . soa ~= nil and param . soa . view or spanName
if simdbounds . coveredThrough (
kernel . cursorBounds ,
name ,
counted ,
kernel . spanBounds ,
room ,
( count or 0 ) + ( ways or 1 )
) then
return name
end

return nil
end


local function laneMultiple ( node , environment ) 
node = lower . unwrapped ( node )
local count = 1
if node ~= nil and node . kind == "binop" then
local product = node
if product . op == nil or ( product . op ) . text ~= "*" then
return nil , nil
end
local lane , factor = lower . unwrapped ( product . lhs ) , lower . unwrapped ( product . rhs )
if lane ~= nil and lane . kind == "number" then
lane , factor = factor , lane
end
local token = factor ~= nil and factor . kind == "number" and ( factor ) . token or nil
local multiple = token ~= nil and tonumber ( ( token ) . text ) or nil
if multiple == nil or multiple < 1 or multiple > 4294967295 or multiple % 1 ~= 0 then
return nil , nil
end
count , node = multiple , lane
end
if node ~= nil and node . kind == "name" then
local alias = environment [ tostring ( lower . nameOf ( node ) ) ]
if alias ~= nil and alias . op == "simd_lanes_generic" then
return ( alias ) . args [ 1 ] . type , count
end
end
if node == nil or node . kind ~= "dotIndex" then
return nil , nil
end
local lanes = node
local name = lanes . name ~= nil and ( lanes . name ) . text == "lanes" and lower . nameOf ( lanes . obj ) or nil
local species = name ~= nil and environment [ name ] or nil
local speciesType = species ~= nil and tostring ( species . type ) or ""
if speciesType : match ( "^simd_species_" ) then
return speciesType , count
end

return nil , nil
end










local function laneBound (
comparison ,
environment ,
kernel
) 
local written = comparison . op ~= nil and ( comparison . op ) . text or ""
local sum , counted = comparison . lhs , comparison . rhs
if written == ">=" then
sum , counted = comparison . rhs , comparison . lhs
elseif written ~= "<=" then
return nil , nil , nil
end
if sum == nil or sum . kind ~= "binop" then
return nil , nil , nil
end
local added = sum
if added . op == nil or ( added . op ) . text ~= "+" then
return nil , nil , nil
end
local cursor = lower . nameOf ( added . lhs )
local cursorBinding = cursor ~= nil and environment [ cursor ] or nil
local speciesType , count = laneMultiple ( added . rhs , environment )
if cursorBinding == nil or cursorBinding . type ~= "u32" or speciesType == nil then
return nil , nil , nil
end
local room = simdbounds . room ( speciesType , count )
local spanName = lower . dotCount ( counted )
local param = spanName ~= nil and kernel . params [ spanName ] or nil
if param ~= nil and param . region ~= nil then
return cursor , spanName , room
end



local lengthName = lower . nameOf ( counted )
local bytesName = lengthName ~= nil and kernel . lengthBounds [ lengthName ] or nil
local bytes = bytesName ~= nil and kernel . params [ bytesName ] or nil
if bytes ~= nil and bytes . kind == "scalar" and ( bytes . type == "lua_string" or bytes . type == "lua_bytes" ) then
return cursor , bytesName , room
end

return nil , nil , nil
end











local NEGATED_COMPARISON = { [ "<" ] = ">=" , [ "<=" ] = ">" , [ ">" ] = "<=" , [ ">=" ] = "<" }

local function cursorSumBound (
comparison ,
environment ,
kernel ,
negated
) 
if kernel . gpuTarget then
return nil , nil , nil
end
local written = comparison . op ~= nil and ( comparison . op ) . text or ""
if negated == true then
written = NEGATED_COMPARISON [ written ] or ""
end
local sum , counted = comparison . lhs , comparison . rhs
local strict = false
if written == "<" or written == "<=" then
strict = written == "<"
elseif written == ">" or written == ">=" then
sum , counted = comparison . rhs , comparison . lhs
strict = written == ">"
else
return nil , nil , nil
end
local cursor , step = cursorIndex ( lower . unwrapped ( sum ) )
local binding = cursor ~= nil and environment [ cursor ] or nil
if cursor == nil or binding == nil or binding . type ~= "u32" then
return nil , nil , nil
end
local spanName = lower . dotCount ( counted )
local param = spanName ~= nil and kernel . params [ spanName ] or nil
if param == nil or param . region == nil then
return nil , nil , nil
end

return cursor , spanName , tostring ( strict and ( step ) + 1 or step )
end






local function spanRead (
node ,
environment ,
activeIndex ,
kernel ,
column
) 
local context = kernel . context
local spanName = column ~= nil and column . name or lower . nameOf ( node . obj )
local param = spanName ~= nil and kernel . params [ spanName ] or nil
if column == nil and param ~= nil and param . soa ~= nil then
context . reject (
lower . site ( node ) ,
"native SoA rows must be accessed through a scalar field; whole-row values are not admitted"
)
end
local readable = param ~= nil and ( param . kind == "read_span" or param . kind == "write_span" )
if not readable then
context . reject ( lower . site ( node ) , "span reads use input[index] or output[index]" )
end
local indexArg = lower . unwrapped ( node . expr )
local direct = lower . nameOf ( indexArg )
local cursor , cursorOffset = provedCursor ( indexArg , spanName , kernel )
if not ( activeIndex ~= nil and direct == activeIndex ) and cursor == nil then
context . reject ( lower . site ( node ) , cursorRefusal ( "loads" , indexArg , spanName , kernel ) )
end
provenIndex ( spanName , cursor , node , kernel )

local element = param . element
local index = cursor == nil and activeIndex or ""
local cursorBinding = cursor ~= nil and environment [ cursor ] or nil
if cursorOffset == 0 then
cursorOffset = nil
end
if element . kind == "struct" then
return ( _G.setmetatable({ op =
"element_ref" ,  span =
spanName ,  index =
index ,  indexUniqueName =
cursor == nil and kernel . indexUniqueName or nil ,  cursor =
cursor ,  cursorUniqueName =
cursorBinding ~= nil and cursorBinding . uniqueName or nil ,  cursorOffset =
cursorOffset ,  layout =
element . layout . name ,  mutable =
param . kind == "write_span" ,  type =
"ref:" .. element . layout . name ,  source =
lower . site ( node ) }, scalarIR.ElementRef) )

end

return widenLoad (
_G.setmetatable({ op =
"load" ,  span =
spanName ,  index =
index ,  indexUniqueName =
cursor == nil and kernel . indexUniqueName or nil ,  cursor =
cursor ,  cursorUniqueName =
cursorBinding ~= nil and cursorBinding . uniqueName or nil ,  cursorOffset =
cursorOffset ,  type =
element . type ,  sourceType =
param . sourceType ,  source =
lower . site ( node ) }, scalarIR.Load)
,
lower . site ( node )
)
end


local function soaColumn ( node , kernel ) 
if node . kind ~= "dotIndex" or node . soaField == nil then
return nil
end
local indexed = lower . unwrapped ( ( node ) . obj )
if indexed == nil or indexed . kind ~= "bracketIndex" then
kernel . context . reject ( lower . site ( node ) , "native SoA fields require an indexed row parameter" )
end
local name = lower . nameOf ( ( indexed ) . obj )
local view = kernel . params [ tostring ( name ) ]
if view == nil or view . soa == nil then
kernel . context . reject ( lower . site ( node ) , "native SoA fields require an existing row-view parameter" )
end
for _ , param in pairs ( kernel . params ) do
if scalarIR . sameSoaView ( view , param )
and param . soa . ordinal == node . soaField . ordinal
and param . soa . field == node . soaField . name
then
return param
end
end
kernel . context . reject ( lower . site ( node ) , "native SoA field identity does not match its column layout" )

return nil
end


local function fieldRead ( node , object , kernel ) 
local context = kernel . context
local aggregateName = scalarIR . aggregateLayout ( object . type )
local layoutName = aggregateName or object . type : match ( "^ref:(.+)$" )
local layout = layoutName ~= nil and kernel . layouts . byName [ layoutName ] or nil
if layout == nil then
context . reject ( lower . site ( node ) , "native field access needs a reified struct element" )
end

local wanted = ( node . name ) . text
local field = nil
for _ , candidate in ipairs ( ( layout ) . fields ) do
if candidate . name == wanted then
field = candidate
end
end
if field == nil then
context . reject ( lower . site ( node ) , "struct " .. tostring ( layoutName ) .. " has no field " .. wanted )
end
if aggregateName ~= nil then


return ( _G.setmetatable({ op =
"aggregate_field" ,  object =
object ,  layout =
aggregateName ,  field =
( field ) . name ,  type =
( field ) . type ,  source =
lower . site ( node ) }, scalarIR.AggregateField) )

end

return widenLoad (
_G.setmetatable({ op =
"field_load" ,  object =
object ,  layout =
layoutName ,  field =
( field ) . name ,  type =
( field ) . type ,  sourceType =
( field ) . sourceType ,  source =
lower . site ( node ) }, scalarIR.FieldLoad)
,
lower . site ( node )
)
end


local function genericSimdParts ( typeName ) 
local family , element , shape = typeName : match ( "^simd_(%a+)_([fiu]%d+)_(.+)$" )

return family , element , shape
end




local function genericSimdScalar ( element ) 
if element == "u8" or element == "u16" then
return "u32"
elseif element == "i8" or element == "i16" then
return "i32"
end

return element
end



local function genericSimdSpanElement ( param ) 
local physical

= {
int8 = "i8" ,
uint8 = "u8" ,
int16 = "i16" ,
uint16 = "u16" ,
float = "f32" ,
int32 = "i32" ,
uint32 = "u32" ,
int64 = "i64" ,
uint64 = "u64" ,
number = "f64" ,
}

return physical [ param . sourceType or "" ] or param . type
end


local function simdOperand (
value ,
vectorType ,
source ,
kernel
) 
if value . type == vectorType then
return value
end
local _ , element = genericSimdParts ( vectorType )
if element == nil then
kernel . context . reject ( source , "explicit SIMD operator has no element type" )
end
local scalar = lower . convert ( value , genericSimdScalar ( element ) , source , kernel . context )

return ( _G.setmetatable({ op =
"simd_splat" ,  args =
{ scalar } ,  intrinsic =
"splat" ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

end





const VECTOR_EXTREMA = {
propagatingMin = "propagating_min" ,
propagatingMax = "propagating_max" ,
numberMin = "number_min" ,
numberMax = "number_max" ,
}


const VECTOR_INTEGER_BINARY = {
saturatingAdd = "saturating_add" ,
saturatingSub = "saturating_sub" ,
mulHigh = "mul_high" ,
}



const SPECIES_WITNESSES

= {
uint8 = true ,
int8 = true ,
uint16 = true ,
int16 = true ,
uint32 = true ,
int32 = true ,
uint64 = true ,
int64 = true ,
float = true ,
number = true ,
}


local function calledIdentity ( node , kernel ) 
local path = lower . dottedName ( node . obj )
local identity = lower . callIdentity ( node . obj )
if identity == nil and path ~= nil then
local root , rest = ( path ) : match ( "^([^.]+)%.(.+)$" )
local moduleName = root ~= nil and kernel . modules [ root ] or nil
if moduleName ~= nil then
identity = moduleName .. "." .. tostring ( rest )
else
identity = kernel . intrinsicAliases [ path ]
end
end

return identity
end


local function admitSpecies ( node , kernel ) 
local context = kernel . context
local site = lower . site ( node )
local arguments = node . args ~= nil and ( node . args ) . exprs or { }
local witness = # arguments >= 1 and lower . dottedName ( arguments [ 1 ] ) or nil
local owner = nil
local field = nil
if witness ~= nil then
local root = nil
root , field = ( witness ) : match ( "^(.+)%.([^.]+)$" )

owner = root ~= nil and ( kernel . modules [ root ] or root ) or nil
end
if owner ~= "nupp.mem.array" or not SPECIES_WITNESSES [ field ] then
context . reject ( site , "simd.species takes one of the scalar witnesses in nupp.mem.array, such as array.uint32" )
end
if # arguments > 2 or # arguments == 2 and arguments [ 2 ] . kind ~= "number" then
context . reject ( site , "simd.species takes a witness and, for a fixed shape, one literal lane count" )
end
if # arguments == 2 then
local token = ( arguments [ 2 ] ) . token
local lanes = token ~= nil and tonumber ( ( ( token ) . text : gsub ( "_" , "" ) ) ) or nil
if lanes == nil or lanes % 1 ~= 0 or lanes < 2 or lanes > 64 then
context . reject (
lower . site ( arguments [ 2 ] ) ,
"a fixed SIMD species needs an integer lane count between 2 and 64"
)
end
end
if kernel . workgroupSize ~= nil or kernel . phasesName ~= nil then
context . reject ( site , "simd.species has no answer inside a GPU kernel; it is for @aot CPU functions" )
end
end












local function species ( node , kernel , asserted , optional ) 
local context = kernel . context
local site = lower . site ( node )
admitSpecies ( node , kernel )
if optional and not context . vectors then
context . reject (
site ,
asserted
and "this tier has no vectors, so simd.vectors is nil here and the assert would always fail; test it against nil and keep the vector path inside that branch, or use simd.species"

or "simd.vectors answers nil on this tier, so it must initialize a local that is tested against nil"
)
end
local inferred = semanticRaw ( ( node ) . inferredType )
local resolved = nil
if inferred ~= nil and inferred . tag == "union" then
for _ , member in ipairs ( inferred . members or { } ) do
if semanticRaw ( member ) . tag ~= "nil" then
resolved = resolved or semanticValueType ( member )
end
end
else
resolved = semanticValueType ( inferred )
end
if resolved == nil or not tostring ( resolved ) : match ( "^simd_species_" ) then
context . reject ( site , "simd.species needs the checker to resolve its species from the witness" )
end
kernel . usesSimd = true

return ( _G.setmetatable({ op =
"simd_species" ,  args =
{ } ,  intrinsic =




"species" ,  type =
resolved ,  source =
site }, scalarIR.Simd) )

end


local function assertedSpecies ( node , kernel ) 
if ( node ) . aotGuardBuiltin ~= "assert" then
return nil , false
end
local arguments = node . args ~= nil and ( node . args ) . exprs or { }
local first = arguments [ 1 ]
local identity = first ~= nil and first . kind == "call" and calledIdentity ( first , kernel ) or nil
if identity ~= "nupp.simd.species" and identity ~= "nupp.simd.vectors" then
return nil , false
end
if # arguments > 2 or # arguments == 2 and arguments [ 2 ] . kind ~= "string" then
kernel . context . reject ( lower . site ( node ) , "assert(simd.species(...)) takes at most a literal message" )
end

return first , identity == "nupp.simd.vectors"
end




local function speciesNilTest ( written , lhs , rhs , environment ) 
if written ~= "==" and written ~= "~=" then
return nil
end
local named = lhs . kind == "nilExpr" and rhs or rhs . kind == "nilExpr" and lhs or nil
if named == nil or ( named ) . kind == "nilExpr" then
return nil
end
local name = lower . nameOf ( named )
local bound = name ~= nil and environment [ name ] or nil
if bound == nil then
return nil
end
if bound . kind == "absent_species" then
return written == "=="
elseif bound . kind == "local" and tostring ( bound . type ) : match ( "^simd_species_" ) ~= nil then
return written == "~="
end

return nil
end




local function exactLaneSum ( sum , source ) 
if sum . op ~= "u32_add" then
return sum
end
local added = sum
local species = simdbounds . lanes ( added . right )
if simdbounds . cursor ( added . left ) == nil or species == nil then
return sum
end
local right = _G.setmetatable({ op =
"numeric_cast" ,  value =
added . right ,  type =
"u64" ,  source =
source }, scalarIR.Convert)

if added . right . op == "u32_mul" then
local product = added . right
right = _G.setmetatable({ op =
"u64_mul" ,  left =
_G.setmetatable({ op =  "numeric_cast" ,  value =  product . left ,  type =  "u64" ,  source =  source }, scalarIR.Convert) ,  right =
_G.setmetatable({ op =  "numeric_cast" ,  value =  product . right ,  type =  "u64" ,  source =  source }, scalarIR.Convert) ,  type =
"u64" ,  source =
source }, scalarIR.Fixed)

end

return ( _G.setmetatable({ op =
"u64_add" ,  left =
_G.setmetatable({ op =  "numeric_cast" ,  value =  added . left ,  type =  "u64" ,  source =  source }, scalarIR.Convert) ,  right =
right ,  type =
"u64" ,  source =
source }, scalarIR.Fixed) )

end






local function exactCursorSum ( sum , source ) 
if sum . op ~= "u32_add" then
return sum
end
local added = sum
local literal = added . right
if simdbounds . cursor ( added . left ) == nil or literal . op ~= "constant_i32" or literal . type ~= "u32" then
return sum
end
if ( tonumber ( ( literal ) . value ) or 0 ) < 1 then
return sum
end

return ( _G.setmetatable({ op =
"u64_add" ,  left =
_G.setmetatable({ op =  "numeric_cast" ,  value =  added . left ,  type =  "u64" ,  source =  source }, scalarIR.Convert) ,  right =
_G.setmetatable({ op =  "numeric_cast" ,  value =  literal ,  type =  "u64" ,  source =  source }, scalarIR.Convert) ,  type =
"u64" ,  source =
source }, scalarIR.Fixed) )

end


local function binary ( node , left , right , kernel ) 
local context = kernel . context
local written = ( node . op ) . text
local source = lower . site ( node )

local leftFamily , leftElement , leftShape = genericSimdParts ( left . type )
if leftFamily == "vector" then
local rightFamily , rightElement , rightShape = genericSimdParts ( right . type )
if rightFamily == "vector" and ( rightElement ~= leftElement or rightShape ~= leftShape ) then
context . reject ( source , "explicit SIMD operands have different element or species identities" )
end
right = simdOperand ( right , left . type , source , kernel )
local arithmeticOps = {
[ "+" ] = "add" ,
[ "-" ] = "sub" ,
[ "*" ] = "mul" ,
[ "/" ] = "div" ,
[ "%" ] = "mod" ,
[ "//" ] = "floor_div" ,
}
local bitOps = { [ "&" ] = "and" , [ "|" ] = "or" , [ "~" ] = "xor" , [ "<<" ] = "shl" , [ ">>" ] = "shr" , [ "~>>" ] = "sar" }
local comparisonOps = { [ "<" ] = "lt" , [ "<=" ] = "le" , [ ">" ] = "gt" , [ ">=" ] = "ge" , [ "==" ] = "eq" , [ "~=" ] = "ne" , }
local intrinsic = arithmeticOps [ written ] or bitOps [ written ] or comparisonOps [ written ]
if intrinsic == nil then
context . reject ( source , "operator " .. written .. " is not an explicit SIMD intrinsic" )
end
local compared = comparisonOps [ written ] ~= nil
return ( _G.setmetatable({ op =
compared and "simd_compare" or "simd_binary" ,  args =
{ left , right } ,  intrinsic =
intrinsic ,  type =
compared and "simd_mask_" .. tostring ( leftElement ) .. "_" .. tostring ( leftShape ) or left . type ,  source =
source }, scalarIR.Simd) )

elseif leftFamily == "mask" then
local rightFamily = genericSimdParts ( right . type )
if rightFamily ~= "mask" or right . type ~= left . type then
context . reject ( source , "explicit SIMD mask operands need the same species" )
end
local intrinsic = ( { [ "&" ] = "and" , [ "|" ] = "or" , [ "~" ] = "xor" , [ "==" ] = "eq" , [ "~=" ] = "ne" , } ) [ written ]
if intrinsic == nil then
context . reject ( source , "operator " .. written .. " is not a mask intrinsic" )
end
return ( _G.setmetatable({ op =
( written == "==" or written == "~=" ) and "simd_compare" or "simd_binary" ,  args =
{ left , right } ,  intrinsic =
intrinsic ,  type =
left . type ,  source =
source }, scalarIR.Simd) )

end

local arithmetic = admit . ARITHMETIC [ written ]
if arithmetic ~= nil then




local wide = ( left . type == "u64" or right . type == "u64" ) and "u64"
or ( left . type == "i64" or right . type == "i64" ) and "i64"
or nil
local wideOps

= { [ "+" ] = "add" , [ "-" ] = "sub" , [ "*" ] = "mul" , [ "/" ] = "div" , [ "%" ] = "mod" , [ "^" ] = "pow" }
if wide ~= nil and wideOps [ written ] ~= nil then
left = lower . convert ( left , wide , source , context )
right = lower . convert ( right , wide , source , context )
return ( _G.setmetatable({ op =
( ( wide == "u64" and "u64_" or "i64_" ) .. ( wideOps [ written ] ) ) ,  left =
left ,  right =
right ,  type =
wide ,  source =
source }, scalarIR.Fixed) )

end
if written == "+" or written == "-" or written == "*" then





local narrowedLeft = exactWidthConstant ( left , right . type ) or left
local narrowedRight = exactWidthConstant ( right , left . type ) or right
local width = narrowedLeft . type == narrowedRight . type
and ( narrowedLeft . type == "u32" or narrowedLeft . type == "i32" )
and narrowedLeft . type
or nil




local annotated = node . fixedArithmetic ~= nil and node . fixedArithmetic : sub ( 1 , 4 ) or ""
if width == nil
and ( annotated == "i32." or annotated == "u32." )
and ( narrowedLeft . type == "u32" or narrowedLeft . type == "i32" )
and ( narrowedRight . type == "u32" or narrowedRight . type == "i32" )
then
width = annotated : sub ( 1 , 3 )
narrowedLeft = lower . convert ( narrowedLeft , width , source , context )
narrowedRight = lower . convert ( narrowedRight , width , source , context )
end
if width ~= nil and ( not context . checked or node . fixedArithmetic ~= nil ) then
return ( _G.setmetatable({ op =
(
tostring ( width ) .. "_" .. ( written == "+" and "add" or written == "-" and "sub" or "mul" )
) ,  left =
narrowedLeft ,  right =
narrowedRight ,  type =
width ,  source =
source }, scalarIR.Fixed) )

end
end
return ( _G.setmetatable({ op =
arithmetic ,  left =
promote ( left , node , context ) ,  right =
promote ( right , node , context ) ,  type =
"f64" ,  source =
source }, scalarIR.Binary) )

end

local bitwise = admit . BITWISE [ written ]
if bitwise ~= nil then



local wide = semanticValueType ( ( node ) . inferredType )
if wide == "i64" or wide == "u64" then
local wideOps

= { [ "&" ] = "and" , [ "|" ] = "or" , [ "~" ] = "xor" , [ "<<" ] = "shl" , [ ">>" ] = "shr" , [ "~>>" ] = "sar" , }
local operation = wideOps [ written ]
if operation == nil then
context . reject ( source , "wide bitwise operator " .. written .. " is not admitted" )
end

return ( _G.setmetatable({ op =
( wide .. "_" .. ( operation ) ) ,  left =
lower . convert ( left , wide , source , context ) ,  right =


lower . convert ( right , wide , source , context ) ,  type =
wide ,  source =
source }, scalarIR.Fixed) )

end
if not bitOperand ( left ) or not bitOperand ( right ) then
context . reject ( source , "bitwise operands must be fixed 32-bit values or nonnegative uint32 literals" )
end

local result = _G.setmetatable({ op =  bitwise ,  left =  left ,  right =  right ,  type =  "i32" ,  source =  source }, scalarIR.Binary)
if node . fixedArithmetic ~= nil and node . fixedArithmetic : sub ( 1 , 4 ) == "u32." then
return lower . convert ( result , "u32" , source , context )
end
return result
end

local comparison = admit . COMPARISON [ written ]
if comparison ~= nil then
local numeric = { [ "f64" ] = true , [ "f32" ] = true , [ "i32" ] = true , [ "u32" ] = true , [ "i64" ] = true , [ "u64" ] = true }
if left . type ~= right . type and not ( numeric [ left . type ] and numeric [ right . type ] ) then
context . reject ( source , "comparison operands must have compatible types" )
end









local narrowedLeft = exactWidthConstant ( left , right . type ) or left
local narrowedRight = exactWidthConstant ( right , left . type ) or right











local countedRight = right . op == "span_count"
or right . op == "local" and ( right ) . lengthOf ~= nil
local countedLeft = left . op == "span_count" or left . op == "local" and ( left ) . lengthOf ~= nil
if ( written == "<=" or written == "<" or written == ">=" ) and countedRight then
if written == "<=" then
narrowedLeft = exactLaneSum ( left , source )
end
if narrowedLeft == left and not kernel . gpuTarget then
narrowedLeft = exactCursorSum ( left , source )
end
elseif ( written == ">=" or written == ">" ) and countedLeft then
if written == ">=" then
narrowedRight = exactLaneSum ( right , source )
end
if narrowedRight == right and not kernel . gpuTarget then
narrowedRight = exactCursorSum ( right , source )
end
if narrowedRight ~= right then
comparison = written == ">=" and "le" or "lt"
narrowedLeft , narrowedRight = narrowedRight , narrowedLeft
end
end

return ( _G.setmetatable({ op =
comparison ,  left =
narrowedLeft ,  right =
narrowedRight ,  type =
"bool" ,  source =
source }, scalarIR.Binary) )

end

if written == "and" or written == "or" then
if left . type ~= "bool" or right . type ~= "bool" then
context . reject ( source , "native and/or operands must both be boolean" )
end

return ( _G.setmetatable({ op =
written ,  left =
left ,  right =
right ,  type =
"bool" ,  source =
source }, scalarIR.Binary) )

end

if written == ".." then
if left . type ~= "lua_string" or right . type ~= "lua_string" then
context . reject ( source , "primitive concatenation needs two strings" )
end
markLua ( kernel , source )
return ( _G.setmetatable({ op =
"lua_concat" ,  left =
left ,  right =
right ,  type =
"lua_string" ,  source =
source }, scalarIR.LuaConcat) )

end

context . reject ( source , "operator " .. tostring ( written ) .. " is not admitted" )

return left
end



const FIXED_UNARY

= {
[ "f32_sqrt" ] = true ,
[ "f32_exp" ] = true ,
[ "u32_not" ] = true ,
[ "u32_popcount" ] = true ,
[ "u32_ctz" ] = true ,
[ "u32_clz" ] = true ,
[ "i64_not" ] = true ,
[ "u64_not" ] = true ,
[ "u64_popcount" ] = true ,
[ "u64_ctz" ] = true ,
[ "u64_clz" ] = true ,
[ "u64_prefix_xor" ] = true ,
}






local function fixedCall (
node ,
path ,
fixed ,
args ,
kernel
) 
local context = kernel . context
local source = lower . site ( node )
if # args ~= fixed . arity then
context . reject ( source , path .. " has an unsupported argument count" )
end

for position , argument in ipairs ( args ) do
local operand = fixed . operands ~= nil and ( fixed . operands ) [ position ] or fixed . operand



if operand == "f32" and argument . op == "widen_f32_f64" then
argument = ( argument ) . value
args [ position ] = argument
end
if argument . op == "constant" and operand ~= "f64" then
local literal = argument
local number = tonumber ( literal . value )
if operand == "i32" or operand == "u32" then
local exact = number ~= nil
and number % 1 == 0
and number >= ( operand == "u32" and 0 or lower . INT32_MIN )
and number <= ( operand == "u32" and lower . UINT32_MAX or lower . INT32_MAX )
if not exact then
context . reject ( source , path .. " needs an exact " .. operand .. " literal" )
end
args [
position
] = _G.setmetatable({ op =
"constant_i32" ,  value =
literal . value ,  type =
operand ,  source =
literal . source }, scalarIR.IntConstant)

elseif operand == "i64" or operand == "u64" then
if number == nil
or number % 1 ~= 0
or number > 9007199254740992
or number < ( operand == "u64" and 0 or - 9007199254740992 )
then
context . reject ( source , path .. " needs an exact " .. operand .. " literal" )
end
args [
position
] = _G.setmetatable({ op =
"constant_i64" ,  value =
( "%.0f" ) : format ( number ) ,  type =
operand ,  source =
literal . source }, scalarIR.Int64Constant)

else
args [
position
] = _G.setmetatable({ op =
"narrow_f64_f32" ,  value =
argument ,  type =
"f32" ,  source =
argument . source }, scalarIR.Convert)

end
elseif operand == "f64" and ( argument . type == "i32" or argument . type == "u32" ) then








args [ position ] = lower . convert ( argument , "f64" , argument . source , context )
elseif argument . type ~= operand then
context . reject (
source ,
path .. " argument " .. tostring (
position
) .. " is " .. tostring ( argument . type ) .. " and was never established as " .. operand
)
end
end

if fixed . op == "u64_rotl" or fixed . op == "u64_rotr" then
args [ 2 ] = lower . convert ( args [ 2 ] , "i64" , args [ 2 ] . source , context )
end

if fixed . form == "binary" then
return ( _G.setmetatable({ op =
fixed . op ,  left =
args [ 1 ] ,  right =
args [ 2 ] ,  type =
fixed . result ,  source =
source }, scalarIR.Binary) )

elseif fixed . form == "unary" then
return ( _G.setmetatable({ op =
fixed . op ,  value =
args [ 1 ] ,  type =
fixed . result ,  source =
source }, scalarIR.Unary) )

end
if fixed . arity == 1 then
if FIXED_UNARY [ tostring ( fixed . op ) ] == true then
return ( _G.setmetatable({ op =
fixed . op ,  value =
args [ 1 ] ,  type =
fixed . result ,  source =
source }, scalarIR.FixedUnary) )

end

return ( _G.setmetatable({ op =
fixed . op ,  value =
args [ 1 ] ,  type =
fixed . result ,  source =
source }, scalarIR.Convert) )

end
if fixed . arity == 3 then
return ( _G.setmetatable({ op =
fixed . op ,  args =
args ,  type =
fixed . result ,  source =
source }, scalarIR.Corrected) )

end
if fixed . op == "f32_min" or fixed . op == "f32_max" then
return ( _G.setmetatable({ op =
fixed . op ,  left =
args [ 1 ] ,  right =
args [ 2 ] ,  type =
fixed . result ,  source =
source }, scalarIR.Corrected) )

end

return ( _G.setmetatable({ op =
fixed . op ,  left =
args [ 1 ] ,  right =
args [ 2 ] ,  type =
fixed . result ,  source =
source }, scalarIR.Fixed) )

end



const LANE_MATH = { sqrt = true , abs = true , floor = true , ceil = true }


local function laneMath (
node ,
intrinsic ,
args ,
kernel
) 
local vector = nil
for _ , argument in ipairs ( args ) do
if genericSimdParts ( argument . type ) == "vector" then
vector = argument
end
end
if vector == nil then
return nil
end
local context = kernel . context
local source = lower . site ( node )
local operand = vector
local _ , element = genericSimdParts ( operand . type )
if LANE_MATH [ intrinsic . name ] ~= true or # args ~= 1 then
context . reject (
source ,
"math." .. intrinsic . name .. " takes no vector; a floating vector takes sqrt, abs, floor and ceil directly"
)
end
if element ~= "f32" and element ~= "f64" then
context . reject ( source , "math." .. intrinsic . name .. " over a vector needs a floating species" )
end
if operand . op ~= "local" then
context . reject ( source , "SIMD math operands must be locals of the species" )
end

return ( _G.setmetatable({ op =
"simd_math" ,  args =
{ operand } ,  intrinsic =
intrinsic . name ,  type =
operand . type ,  source =
source }, scalarIR.Simd) )

end


local function mathCall (
node ,
path ,
intrinsic ,
args ,
kernel
) 
local context = kernel . context
local source = lower . site ( node )
if # args < intrinsic . min or intrinsic . max ~= nil and # args > ( intrinsic . max ) then
context . reject ( source , path .. " has an unsupported argument count" )
end
for position , argument in ipairs ( args ) do
local widened = lower . conversion ( argument , "f64" , argument . source )
if widened == nil then
context . reject ( source , path .. " arguments must be numeric" )
end
args [ position ] = widened
end

return ( _G.setmetatable({ op =  "math" ,  intrinsic =  intrinsic . name ,  args =  args ,  type =  "f64" ,  source =  source }, scalarIR.Math) )
end



function lower . rearrange (
operation ,
args ,
source ,
kernel
) 
if args [ 1 ] == nil then
kernel . context . reject ( source , operation .. " needs matching SIMD vectors" )
end
local family , _ , shape = genericSimdParts ( args [ 1 ] . type )
local count = operation == "transpose" and # args or 2
if family ~= "vector" or # args ~= count then
kernel . context . reject ( source , operation .. " needs matching SIMD vectors" )
end
for _ , arg in ipairs ( args ) do
if arg . type ~= args [ 1 ] . type then
kernel . context . reject ( source , operation .. " needs matching SIMD vectors" )
end
end
if operation == "transpose" and ( count < 2 or count > 64 or shape ~= "fixed" .. tostring ( count ) ) then
kernel . context . reject ( source , "transpose needs a square tile of fixed-width vectors" )
end
local key = "rearrange_" .. operation .. "_" .. args [ 1 ] . type
local helper = kernel . helpers [ "$" .. key ]
if helper == nil then
local params = { }
local values = { }
local resultTypes = { }
for i , arg in ipairs ( args ) do
params [
i
] = _G.setmetatable({ op =
"helper_param" ,  name =
"row" .. tostring ( i ) ,  uniqueName =
"row" .. tostring ( i ) ,  type =
arg . type ,  source =
source }, scalarIR.Name)

end
for i = 1 , count do
local operands = { }
for _ , param in ipairs ( params ) do
operands [ # operands + 1 ] = param
end
operands [
# operands + 1
] = _G.setmetatable({ op =  "constant" ,  value =  tostring ( i - 1 ) ,  type =  "f64" ,  source =  source }, scalarIR.Constant)
values [
i
] = _G.setmetatable({ op =
"simd_permute" ,  intrinsic =
operation ,  args =
operands ,  type =
args [ 1 ] . type ,  source =
source }, scalarIR.Simd)

resultTypes [ i ] = args [ 1 ] . type
end
helper = _G.setmetatable({ name =
"$" .. key ,  uniqueName =
kernel . symbol .. "_" .. key ,  params =
params ,  values =
values ,  resultTypes =
resultTypes ,  source =
source }, scalarIR.Helper)

kernel . helpers [ "$" .. key ] = helper
kernel . helperOrder [ # kernel . helperOrder + 1 ] = helper
end
kernel . usesSimd = true

return ( _G.setmetatable({ op =
"helper_call" ,  helper =
( helper ) . name ,  uniqueName =
( helper ) . uniqueName ,  args =
args ,  type =
"multi" ,  resultTypes =
( helper ) . resultTypes ,  source =
source }, scalarIR.HelperCall) )

end



local function floatingWitness ( argument , kernel ) 
local witness = argument ~= nil and lower . dottedName ( argument ) or nil
if witness == nil then
return nil
end
local root , field = ( witness ) : match ( "^(.+)%.([^.]+)$" )
local owner = root ~= nil and ( kernel . modules [ root ] or root ) or nil
if owner ~= "nupp.mem.array" then
return nil
end

return field == "float" and "f32" or field == "number" and "f64" or nil
end


local function call (
node ,
environment ,
activeIndex ,
kernel
) 
local context = kernel . context
local path = lower . dottedName ( node . obj )
local identity = calledIdentity ( node , kernel )
if identity == "nupp.simd.species" or identity == "nupp.simd.vectors" then


return species ( node , kernel , false , identity == "nupp.simd.vectors" )
end
local required , optional = assertedSpecies ( node , kernel )
if required ~= nil then
return species ( required , kernel , true , optional )
end

local args = { }
local written = node . args ~= nil and ( node . args ) . exprs or { }
local contract = identity ~= nil and reducers . CONSTRUCTORS [ identity ] or nil
local floatingContract = identity ~= nil and reducers . FLOATING [ identity ] or nil




local first = contract ~= nil and ( contract ) . witnessed and 2 or 1
if first == 2 and # written < 1 then
context . reject ( lower . site ( node ) , "an integer reducer names its element with an array witness" )
end
if ( floatingContract ~= nil or contract ~= nil and reducers . floatingOrder ( ( contract ) . order ) )
and floatingWitness ( written [ 1 ] , kernel ) ~= nil
then
first = 2
end
for index = first , # written do
args [ # args + 1 ] = lower . expression ( written [ index ] , environment , activeIndex , kernel )
end





local callee = semanticRaw ( ( node . obj ) . inferredType )
if callee ~= nil and callee . tag == "func" then
for index = first , # written do
local declared = ( callee . params or { } ) [ index ]
local raw = declared ~= nil and semanticRaw ( declared ) or nil
local width = raw ~= nil
and ( raw . tag == "uint32" and "u32" or raw . tag == "int32" and "i32" or nil )
or nil
local position = index - first + 1
if width ~= nil then
args [ position ] = exactWidthConstant ( args [ position ] , width ) or args [ position ]
end
end
end


local preludeString = kernel . modules . string == "@prelude.string" and environment . string == nil
if identity == "string.byte" or identity == "@prelude.string.byte" or path == "string.byte" and preludeString then
if # args ~= 2 or args [ 1 ] . type ~= "lua_string" or args [ 1 ] . op ~= "local" or args [ 2 ] . type ~= "f64" then
context . reject ( lower . site ( node ) , "string.byte in AOT takes one rooted string and one numeric index" )
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ op =
"lua_string_byte_lua" ,  bytes =
args [ 1 ] ,  index =
args [ 2 ] ,  type =
"f64" ,  source =
lower . site ( node ) }, scalarIR.LuaStringByte) )

elseif identity == "string.sub" or identity == "@prelude.string.sub" or path == "string.sub" and preludeString then
if ( # args ~= 2 and # args ~= 3 )
or args [ 1 ] . type ~= "lua_string"
or args [ 1 ] . op ~= "local"
or args [ 2 ] . type ~= "f64"
or args [ 3 ] ~= nil and args [ 3 ] . type ~= "f64"
then
context . reject ( lower . site ( node ) , "string.sub in AOT takes a rooted string and numeric bounds" )
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ op =
"lua_substring" ,  bytes =
args [ 1 ] ,  first =
args [ 2 ] ,  last =
args [ 3 ] ,  type =
"lua_string" ,  source =
lower . site ( node ) }, scalarIR.LuaSubstring) )

elseif contract ~= nil then
local resolved = semanticValueType ( ( node ) . inferredType )
local order , operation , element = reducers . parse ( resolved or "" )
if element == nil or # args ~= ( contract . seeded and 1 or 0 ) then
context . reject (
lower . site ( node ) ,
"an exact reducer needs a concrete element type and its declared initial value"
)
end
if first == 2 and reducers . floatingOrder ( contract . order ) and floatingWitness ( written [ 1 ] , kernel ) ~= element then
context . reject ( lower . site ( node ) , "a floating-point reducer's witness names the element its type carries" )
end
local initial = element == "bool"
and _G.setmetatable({ op =  "bool" ,  value =  operation == "all" ,  type =  "bool" ,  source =  lower . site ( node ) }, scalarIR.Bool)
or lower . convert (
_G.setmetatable({ op =  "constant" ,  value =  "0" ,  type =  "f64" ,  source =  lower . site ( node ) }, scalarIR.Constant) ,
element ,
lower . site ( node ) ,
context
)
if contract . seeded then
initial = lower . convert ( args [ 1 ] , element , lower . site ( node ) , context )
end
return ( _G.setmetatable({ op =
"reducer_init" ,  order =
order ,  operation =
operation ,  initial =
initial ,  type =
resolved ,  source =
lower . site ( node ) }, scalarIR.ReducerInit) )

elseif floatingContract ~= nil then
if # args ~= 1 then
context . reject ( lower . site ( node ) , "a floating-point reducer takes one initial value" )
end
local resolved = semanticValueType ( ( node ) . inferredType ) or ""
local _ , _ , element = reducers . parse ( resolved )
local witness = first == 2 and floatingWitness ( written [ 1 ] , kernel ) or "f64"
if element == nil and resolved ~= "simd_reducer_" .. floatingContract . order .. "_" .. floatingContract . operation
or element ~= nil and element ~= "f32"
or witness ~= ( element or "f64" )
then
context . reject (
lower . site ( node ) ,
"a floating-point reducer accumulates the float or number its witness names"
)
end
return ( _G.setmetatable({ op =
"reducer_init" ,  order =
floatingContract . order ,  operation =
floatingContract . operation ,  initial =
lower . convert ( args [ 1 ] , element or "f64" , lower . site ( node ) , context ) ,  type =
resolved ,  source =
lower . site ( node ) }, scalarIR.ReducerInit) )

elseif identity ~= nil and identity : match ( "^nupp%.simd%.horizontal%." ) ~= nil then
local operation = identity : match ( "^nupp%.simd%.horizontal%.(.+)$" )
local operations



= {
orderedSum = { arity = 1 , order = "ordered" , kind = "sum" } ,
pairwiseSum = { arity = 1 , order = "pairwise" , kind = "sum" } ,
algebraicSum = { arity = 1 , order = "algebraic" , kind = "sum" } ,
orderedProduct = { arity = 1 , order = "ordered" , kind = "product" } ,
pairwiseProduct = { arity = 1 , order = "pairwise" , kind = "product" } ,
algebraicProduct = { arity = 1 , order = "algebraic" , kind = "product" } ,
orderedDot = { arity = 2 , order = "ordered" , kind = "dot" } ,
pairwiseDot = { arity = 2 , order = "pairwise" , kind = "dot" } ,
algebraicDot = { arity = 2 , order = "algebraic" , kind = "dot" } ,



propagatingMin = { arity = 1 , order = "propagating" , kind = "min" } ,
propagatingMax = { arity = 1 , order = "propagating" , kind = "max" } ,
numberMin = { arity = 1 , order = "number" , kind = "min" } ,
numberMax = { arity = 1 , order = "number" , kind = "max" } ,
propagatingArgMin = { arity = 1 , order = "propagating" , kind = "arg_min" } ,
propagatingArgMax = { arity = 1 , order = "propagating" , kind = "arg_max" } ,
numberArgMin = { arity = 1 , order = "number" , kind = "arg_min" } ,
numberArgMax = { arity = 1 , order = "number" , kind = "arg_max" } ,


wrappingSum = { arity = 1 , order = "exact" , kind = "sum" } ,
wrappingProduct = { arity = 1 , order = "exact" , kind = "product" } ,
andBits = { arity = 1 , order = "exact" , kind = "and" } ,
orBits = { arity = 1 , order = "exact" , kind = "or" } ,
xorBits = { arity = 1 , order = "exact" , kind = "xor" } ,
integerMin = { arity = 1 , order = "integer" , kind = "min" } ,
integerMax = { arity = 1 , order = "integer" , kind = "max" } ,
}
local horizontal = operations [ operation ]
if horizontal == nil then
context . reject ( lower . site ( node ) , "unknown explicit SIMD horizontal operation " .. operation )
end
if # args ~= ( horizontal ) . arity then
context . reject ( lower . site ( node ) , "simd.horizontal." .. operation .. " has an unsupported argument count" )
end
local family , element = genericSimdParts ( args [ 1 ] . type )
if family ~= "vector" or element == nil then
context . reject ( lower . site ( node ) , "simd.horizontal." .. operation .. " needs an explicit SIMD vector" )
end
if # args == 2 and args [ 2 ] . type ~= args [ 1 ] . type then
context . reject ( lower . site ( node ) , "explicit SIMD horizontal dot operands need the same element and species" )
end
local kind = ( horizontal ) . kind
local order = ( horizontal ) . order
local extremum = kind == "min" or kind == "max" or kind == "arg_min" or kind == "arg_max"
local floating = element == "f32" or element == "f64"





if order == "exact" or order == "integer" then
if floating then
context . reject ( lower . site ( node ) , "simd.horizontal." .. operation .. " requires an integer vector" )
end
elseif not extremum and not floating then
context . reject ( lower . site ( node ) , "explicit SIMD horizontal arithmetic requires a floating-point vector" )
end
kernel . usesSimd = true
local indexed = kind == "arg_min" or kind == "arg_max"
return ( _G.setmetatable({ op =
"simd_horizontal" ,  args =
args ,  intrinsic =
order .. "_" .. kind ,  type =
( indexed and "f64" or genericSimdScalar ( element ) ) ,  source =
lower . site ( node ) }, scalarIR.Simd) )

elseif identity == "nupp.simd.transpose" then
return lower . rearrange ( "transpose" , args , lower . site ( node ) , kernel )
elseif identity == "nupp.codec.valuebuilder.new"
or identity == "nupp.codec.valuebuilder.newSized"
or identity == "nupp.codec.json.internal.builder.newPull"
or identity == "nupp.codec.json.internal.builder.newSerde"
then
local sized = identity == "nupp.codec.valuebuilder.newSized"
local pulling = identity == "nupp.codec.json.internal.builder.newPull"
or identity == "nupp.codec.json.internal.builder.newSerde"
if ( not sized and not pulling and # args ~= 1 or sized and # args ~= 3 and # args ~= 5 or pulling and # args ~= 8 )
or args [ 1 ] . type ~= "lua_value"
or args [ 1 ] . op ~= "local"
or ( sized or pulling )
and (
args [ 2 ] . type ~= "u32"
or args [ 3 ] . type ~= "u32"
or ( sized and # args == 5 or pulling ) and ( args [ 4 ] . type ~= "lua_value" or args [ 5 ] . type ~= "lua_value" )
or pulling
and (
args [ 6 ] . type ~= "lua_value"
or args [ 6 ] . op ~= "local"
or args [ 7 ] . type ~= "lua_value"
or args [ 7 ] . op ~= "local"
or args [ 8 ] . type ~= "lua_value"
or args [ 8 ] . op ~= "local"
)
)
then
context . reject (
lower . site ( node ) ,
pulling
and "json builder.newPull takes a rooted null replacement, uint32 depth and string capacity, container markers, a rooted shape, its array marker, and serde markers"
or sized
and "valuebuilder.newSized takes a rooted null replacement, uint32 depth and string capacity, and optional container markers"
or "valuebuilder.new takes one rooted null replacement"
)
end
markLua ( kernel , lower . site ( node ) )
local builderMode = identity == "nupp.codec.json.internal.builder.newSerde" and "serde"
or pulling and "pull"
or "eager"
if kernel . builderMode ~= nil and kernel . builderMode ~= builderMode then
context . reject ( lower . site ( node ) , "one AOT entry cannot mix value stream modes" )
end
kernel . builderMode = builderMode
return ( _G.setmetatable({ op =
"lua_builder" ,  mode =
builderMode ,  nullValue =
args [ 1 ] ,  maxDepth =
( sized or pulling ) and args [ 2 ] or nil ,  stringCapacity =
( sized or pulling ) and args [ 3 ] or nil ,  arrayMarker =
( sized or pulling ) and args [ 4 ] or nil ,  objectMarker =
( sized or pulling ) and args [ 5 ] or nil ,  selectionShape =
pulling and args [ 6 ] or nil ,  arrayShapeMarker =
pulling and args [ 7 ] or nil ,  serdeMarkers =
pulling and args [ 8 ] or nil ,  type =
"lua_builder" ,  source =
lower . site ( node ) }, scalarIR.LuaBuilder) )

elseif identity == "nupp.codec.valuebuilder.newWordScratch" then
if # args ~= 1 or args [ 1 ] . type ~= "u32" then
context . reject ( lower . site ( node ) , "valuebuilder.newWordScratch takes one uint32 capacity" )
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ op =
"lua_scratch_u32" ,  capacity =
args [ 1 ] ,  type =
"lua_scratch_u32" ,  source =
lower . site ( node ) }, scalarIR.LuaScratchU32) )

elseif identity == "nupp.codec.valuebuilder.newFixedWordScratch" then






local width = # args == 1 and lower . constantWidth ( args [ 1 ] ) or nil
if width == nil then
context . reject (
lower . site ( node ) ,
"valuebuilder.newFixedWordScratch takes one uint32 capacity written as a literal"
)
end
markLua ( kernel , lower . site ( node ) )




return ( _G.setmetatable({ op =
"lua_scratch_u32" ,  capacity =
_G.setmetatable({ op =
"constant_i32" ,  value =
tostring ( width ) ,  type =
"u32" ,  source =
lower . site ( node ) }, scalarIR.IntConstant) ,  fixed =

width ,  type =
"lua_scratch_u32" ,  source =
lower . site ( node ) }, scalarIR.LuaScratchU32) )

elseif identity == "nupp.codec.valuebuilder.scratchWord"
or identity == "nupp.codec.json.internal.builder.scratchEscapeWord"
then
if # args ~= 2 or args [ 1 ] . type ~= "lua_scratch_u32" or args [ 1 ] . op ~= "local" or args [ 2 ] . type ~= "u32" then
context . reject ( lower . site ( node ) , "valuebuilder.scratchWord takes a local scratch buffer and uint32 index" )
end
markLua ( kernel , lower . site ( node ) )
local scratchName = ( args [ 1 ] ) . name
local cursor = args [ 2 ] . op == "local" and ( args [ 2 ] ) . name or nil
local proved = boundRoom ( kernel . cursorBounds , cursor , scratchName ) ~= nil
return ( _G.setmetatable({ fixedBound =
identity == "nupp.codec.valuebuilder.scratchWord"
and kernel . scratchBounds [ ( args [ 1 ] ) . name ]
or nil ,  op =
identity == "nupp.codec.json.internal.builder.scratchEscapeWord" and "lua_scratch_u32_escape_get"
or "lua_scratch_u32_get" ,  scratch =
args [ 1 ] ,  index =
args [ 2 ] ,  cursor =
proved and cursor or nil ,  cursorUniqueName =
proved and ( args [ 2 ] ) . uniqueName or nil ,  type =
"u32" ,  source =
lower . site ( node ) }, scalarIR.LuaScratchU32Get) )

elseif identity == "nupp.codec.valuebuilder.scratchLength"
or identity == "nupp.codec.json.internal.builder.scratchEscapeLength"
then
if # args ~= 1 or args [ 1 ] . type ~= "lua_scratch_u32" or args [ 1 ] . op ~= "local" then
context . reject ( lower . site ( node ) , "valuebuilder.scratchLength takes one local word scratch" )
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ op =
identity == "nupp.codec.json.internal.builder.scratchEscapeLength" and "lua_scratch_u32_escape_length"
or "lua_scratch_u32_length" ,  scratch =
args [ 1 ] ,  type =
"u32" ,  source =
lower . site ( node ) }, scalarIR.LuaScratchU32Length) )

elseif identity == "nupp.codec.valuebuilder.setScratchWord" then
if # args ~= 3
or args [ 1 ] . type ~= "lua_scratch_u32"
or args [ 1 ] . op ~= "local"
or args [ 2 ] . type ~= "u32"
or args [ 3 ] . type ~= "u32"
then
context . reject (
lower . site ( node ) ,
"valuebuilder.setScratchWord takes a local scratch buffer, uint32 index, and uint32 value"
)
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ fixedBound =
kernel . scratchBounds [ ( args [ 1 ] ) . name ] ,  op =
"lua_scratch_u32_set" ,  scratch =
args [ 1 ] ,  index =
args [ 2 ] ,  value =
args [ 3 ] ,  type =
"lua_effect" ,  source =
lower . site ( node ) }, scalarIR.LuaScratchU32Set) )

elseif identity == "nupp.codec.valuebuilder.newByteScratch" then
if # args ~= 1 or args [ 1 ] . type ~= "u32" then
context . reject ( lower . site ( node ) , "valuebuilder.newByteScratch takes one uint32 capacity" )
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ op =
"lua_scratch_u8" ,  capacity =
args [ 1 ] ,  type =
"lua_scratch_u8" ,  source =
lower . site ( node ) }, scalarIR.LuaScratchU8) )

elseif identity == "nupp.codec.valuebuilder.newFixedByteScratch" then



local width = # args == 1 and lower . constantWidth ( args [ 1 ] ) or nil
if width == nil then
context . reject (
lower . site ( node ) ,
"valuebuilder.newFixedByteScratch takes one uint32 capacity written as a literal"
)
end
markLua ( kernel , lower . site ( node ) )

return ( _G.setmetatable({ op =
"lua_scratch_u8" ,  capacity =
_G.setmetatable({ op =
"constant_i32" ,  value =
tostring ( width ) ,  type =
"u32" ,  source =
lower . site ( node ) }, scalarIR.IntConstant) ,  fixed =

width ,  type =
"lua_scratch_u8" ,  source =
lower . site ( node ) }, scalarIR.LuaScratchU8) )

elseif identity == "nupp.codec.valuebuilder.scratchByte" then
if # args ~= 2 or args [ 1 ] . type ~= "lua_scratch_u8" or args [ 1 ] . op ~= "local" or args [ 2 ] . type ~= "u32" then
context . reject ( lower . site ( node ) , "valuebuilder.scratchByte takes a local byte scratch and uint32 index" )
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ fixedBound =
kernel . scratchBounds [ ( args [ 1 ] ) . name ] ,  op =
"lua_scratch_u8_get" ,  scratch =
args [ 1 ] ,  index =
args [ 2 ] ,  type =
"u32" ,  source =
lower . site ( node ) }, scalarIR.LuaScratchU8Get) )

elseif identity == "nupp.codec.valuebuilder.setScratchByte" then
if # args ~= 3
or args [ 1 ] . type ~= "lua_scratch_u8"
or args [ 1 ] . op ~= "local"
or args [ 2 ] . type ~= "u32"
or args [ 3 ] . type ~= "u32"
then
context . reject ( lower . site ( node ) , "valuebuilder.setScratchByte takes a local byte scratch, index, and byte" )
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ fixedBound =
kernel . scratchBounds [ ( args [ 1 ] ) . name ] ,  op =
"lua_scratch_u8_set" ,  scratch =
args [ 1 ] ,  index =
args [ 2 ] ,  value =
args [ 3 ] ,  type =
"lua_effect" ,  source =
lower . site ( node ) }, scalarIR.LuaScratchU8Set) )

elseif identity == "nupp.codec.valuebuilder.setScratchBytes4" then
if # args ~= 3
or args [ 1 ] . type ~= "lua_scratch_u8"
or args [ 1 ] . op ~= "local"
or args [ 2 ] . type ~= "u32"
or args [ 3 ] . type ~= "u32"
then
context . reject (
lower . site ( node ) ,
"valuebuilder.setScratchBytes4 takes a local byte scratch, index, and word"
)
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ fixedBound =
kernel . scratchBounds [ ( args [ 1 ] ) . name ] ,  op =
"lua_scratch_u8_set4" ,  scratch =
args [ 1 ] ,  index =
args [ 2 ] ,  value =
args [ 3 ] ,  type =
"lua_effect" ,  source =
lower . site ( node ) }, scalarIR.LuaScratchU8Set) )

elseif identity == "nupp.codec.valuebuilder.resetByteScratch" then
if # args ~= 1 or args [ 1 ] . type ~= "lua_scratch_u8" or args [ 1 ] . op ~= "local" then
context . reject ( lower . site ( node ) , "valuebuilder.resetByteScratch takes one local byte scratch" )
end



if kernel . scratchBounds [ ( args [ 1 ] ) . name ] ~= nil then
context . reject ( lower . site ( node ) , "a fixed byte scratch cannot be reset" )
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ op =
"lua_scratch_u8_reset" ,  scratch =
args [ 1 ] ,  type =
"lua_effect" ,  source =
lower . site ( node ) }, scalarIR.LuaScratchU8Set) )

elseif identity == "nupp.codec.valuebuilder.byte"
or identity == "nupp.codec.valuebuilder.byteAt"
or identity == "nupp.codec.valuebuilder.word"
or identity == "nupp.codec.valuebuilder.length"
then
local takesIndex = identity ~= "nupp.codec.valuebuilder.length"
if # args ~= ( takesIndex and 2 or 1 )
or args [ 1 ] . type ~= "lua_string" and args [ 1 ] . type ~= "lua_bytes"
or args [ 1 ] . op ~= "local"
or takesIndex and args [ 2 ] . type ~= "u32"
then
context . reject ( lower . site ( node ) , "valuebuilder rooted byte access has an invalid argument" )
end
markLua ( kernel , lower . site ( node ) )
local byteAt = identity == "nupp.codec.valuebuilder.byteAt"
local cursor = byteAt and args [ 2 ] . op == "local" and ( args [ 2 ] ) . name or nil
local bytesName = ( args [ 1 ] ) . name
if byteAt and boundRoom ( kernel . cursorBounds , cursor , bytesName ) == nil then
context . reject ( lower . site ( node ) , "valuebuilder.byteAt needs offset < length(bytes) to dominate the read" )
end
return ( _G.setmetatable({ op =
byteAt and "lua_string_byte_at"
or identity == "nupp.codec.valuebuilder.byte" and "lua_string_byte"
or identity == "nupp.codec.valuebuilder.word" and "lua_string_u32"
or "lua_string_length" ,  bytes =
args [ 1 ] ,  index =
takesIndex and args [ 2 ] or nil ,  cursor =
cursor ,  cursorUniqueName =
cursor ~= nil and ( args [ 2 ] ) . uniqueName or nil ,  type =
"u32" ,  source =
lower . site ( node ) }, scalarIR.LuaBytes) )

elseif identity == "nupp.codec.valuebuilder.finish" then
if # args ~= 1 or args [ 1 ] . type ~= "lua_builder" or args [ 1 ] . op ~= "local" then
context . reject ( lower . site ( node ) , "valuebuilder.finish takes one local builder" )
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ op =
"lua_builder_finish" ,  builder =
args [ 1 ] ,  mode =
( args [ 1 ] ) . builderMode ,  type =
"lua_value" ,  source =
lower . site ( node ) }, scalarIR.LuaBuilderFinish) )

elseif identity == "nupp.codec.valuebuilder.depth"
or identity == "nupp.codec.valuebuilder.kind"
or identity == "nupp.codec.valuebuilder.count"
or identity == "nupp.codec.valuebuilder.state"
then
if # args ~= 1 or args [ 1 ] . type ~= "lua_builder" or args [ 1 ] . op ~= "local" then
context . reject ( lower . site ( node ) , "valuebuilder stream query takes one local builder" )
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ op =
identity == "nupp.codec.valuebuilder.depth" and "lua_builder_depth"
or identity == "nupp.codec.valuebuilder.kind" and "lua_builder_kind"
or identity == "nupp.codec.valuebuilder.count" and "lua_builder_count"
or "lua_builder_state" ,  builder =
args [ 1 ] ,  mode =
( args [ 1 ] ) . builderMode ,  type =
"u32" ,  source =
lower . site ( node ) }, scalarIR.LuaBuilderQuery) )

elseif identity == "nupp.codec.json.internal.builder.numberToken" then
if # args ~= 4
or args [ 1 ] . type ~= "lua_builder"
or args [ 1 ] . op ~= "local"
or args [ 2 ] . type ~= "lua_string" and args [ 2 ] . type ~= "lua_bytes"
or args [ 2 ] . op ~= "local"
or args [ 3 ] . type ~= "u32"
or args [ 4 ] . type ~= "u32"
then
context . reject (
lower . site ( node ) ,
"json builder.numberToken takes a local builder, rooted bytes, uint32 start, and uint32 limit"
)
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ op =
"lua_builder_number_token" ,  builder =
args [ 1 ] ,  mode =
( args [ 1 ] ) . builderMode ,  sourceBytes =
args [ 2 ] ,  start =
args [ 3 ] ,  limit =
args [ 4 ] ,  type =
"u32" ,  source =
lower . site ( node ) }, scalarIR.LuaBuilderNumberToken) )

elseif identity ~= nil
and (
identity : match ( "^nupp%.codec%.valuebuilder%." ) ~= nil
or identity == "nupp.codec.json.internal.builder.keyEscapes"
or identity == "nupp.codec.json.internal.builder.stringEscapes"
)
then
local action = tostring ( identity ) : match ( "^.*%.(.+)$" )
local operations

= {
openArray = "lua_builder_open_array" ,
openObject = "lua_builder_open_object" ,
key = "lua_builder_key" ,
string = "lua_builder_string" ,
number = "lua_builder_number" ,
numberSlice = "lua_builder_number_slice" ,
integerSlice = "lua_builder_integer_slice" ,
integer64 = "lua_builder_integer64" ,
decimal64 = "lua_builder_decimal64" ,
boolean = "lua_builder_boolean" ,
null = "lua_builder_null" ,
close = "lua_builder_close" ,
keyScratch = "lua_builder_key_scratch" ,
stringScratch = "lua_builder_string_scratch" ,
keyEscapes = "lua_builder_key_escapes" ,
stringEscapes = "lua_builder_string_escapes" ,
}
local operation = operations [ tostring ( action ) ]
if ( action == "keyEscapes" or action == "stringEscapes" ) ~= ( identity : match ( "^nupp%.codec%.json%." ) ~= nil ) then
operation = nil
end
if operation ~= nil then
if # args < 1 or args [ 1 ] . type ~= "lua_builder" or args [ 1 ] . op ~= "local" then
context . reject ( lower . site ( node ) , "valuebuilder event needs one local builder" )
end
local event = _G.setmetatable({ op =
operation ,  builder =
args [ 1 ] ,  mode =
( args [ 1 ] ) . builderMode ,  type =
"lua_effect" ,  source =
lower . site ( node ) }, scalarIR.LuaBuild)

if action == "openArray" or action == "openObject" then
if # args ~= 2 or args [ 2 ] . type ~= "u32" then
context . reject ( lower . site ( node ) , "valuebuilder container opening needs a uint32 capacity" )
end
event . capacity = args [ 2 ]
elseif action == "key" or action == "string" then
if # args ~= 5
or args [ 2 ] . type ~= "lua_string" and args [ 2 ] . type ~= "lua_bytes"
or args [ 2 ] . op ~= "local"
or args [ 3 ] . type ~= "u32"
or args [ 4 ] . type ~= "u32"
or args [ 5 ] . type ~= "bool"
then
context . reject ( lower . site ( node ) , "valuebuilder string event has invalid arguments" )
end
event . sourceBytes , event . start , event . length , event . escaped = args [ 2 ] , args [ 3 ] , args [ 4 ] , args [ 5 ]
elseif action == "keyScratch" or action == "stringScratch" then
if # args ~= 4
or args [ 2 ] . type ~= "lua_scratch_u8"
or args [ 2 ] . op ~= "local"
or args [ 3 ] . type ~= "u32"
or args [ 4 ] . type ~= "u32"
then
context . reject ( lower . site ( node ) , "valuebuilder scratch string event has invalid arguments" )
end
event . scratch , event . start , event . length = args [ 2 ] , args [ 3 ] , args [ 4 ]
elseif action == "keyEscapes" or action == "stringEscapes" then
if # args ~= 7
or args [ 2 ] . type ~= "lua_string" and args [ 2 ] . type ~= "lua_bytes"
or args [ 2 ] . op ~= "local"
or args [ 3 ] . type ~= "u32"
or args [ 4 ] . type ~= "u32"
or args [ 5 ] . type ~= "lua_scratch_u32"
or args [ 5 ] . op ~= "local"
or args [ 6 ] . type ~= "u32"
or args [ 7 ] . type ~= "u32"
then
context . reject ( lower . site ( node ) , "valuebuilder indexed escape event has invalid arguments" )
end
event . sourceBytes , event . start , event . length = args [ 2 ] , args [ 3 ] , args [ 4 ]
event . escapeScratch , event . escapeIndex , event . escapeCount = args [ 5 ] , args [ 6 ] , args [ 7 ]
elseif action == "numberSlice" or action == "integerSlice" then
if # args ~= 4
or args [ 2 ] . type ~= "lua_string" and args [ 2 ] . type ~= "lua_bytes"
or args [ 2 ] . op ~= "local"
or args [ 3 ] . type ~= "u32"
or args [ 4 ] . type ~= "u32"
then
context . reject ( lower . site ( node ) , "valuebuilder number slice has invalid arguments" )
end
event . sourceBytes , event . start , event . length = args [ 2 ] , args [ 3 ] , args [ 4 ]
elseif action == "number" then
if # args ~= 2 or args [ 2 ] . type ~= "f64" then
context . reject ( lower . site ( node ) , "valuebuilder.number takes one number" )
end
event . value = args [ 2 ]
elseif action == "integer64" then
if # args ~= 3 or args [ 2 ] . type ~= "u64" or args [ 3 ] . type ~= "bool" then
context . reject ( lower . site ( node ) , "valuebuilder.integer64 takes a uint64 magnitude and sign" )
end
event . value , event . negative = args [ 2 ] , args [ 3 ]
elseif action == "decimal64" then
if # args ~= 8
or args [ 2 ] . type ~= "lua_string" and args [ 2 ] . type ~= "lua_bytes"
or args [ 2 ] . op ~= "local"
or args [ 3 ] . type ~= "u32"
or args [ 4 ] . type ~= "u32"
or args [ 5 ] . type ~= "u64"
or args [ 6 ] . type ~= "i32"
or args [ 7 ] . type ~= "bool"
or args [ 8 ] . type ~= "bool"
then
context . reject (
lower . site ( node ) ,
"valuebuilder.decimal64 takes a source slice, uint64 magnitude, int32 exponent, sign, and exactness"
)
end
event . sourceBytes , event . start , event . length = args [ 2 ] , args [ 3 ] , args [ 4 ]
event . value , event . exponent , event . negative , event . exact = args [ 5 ] , args [ 6 ] , args [ 7 ] , args [ 8 ]
elseif action == "boolean" then
if # args ~= 2 or args [ 2 ] . type ~= "bool" then
context . reject ( lower . site ( node ) , "valuebuilder.boolean takes one boolean" )
end
event . value = args [ 2 ]
elseif # args ~= 1 then
context . reject ( lower . site ( node ) , "valuebuilder event takes only its builder" )
end
markLua ( kernel , lower . site ( node ) )
return event
end
end
if identity == "table.new"
or path == "table.new" and kernel . modules . table == "@prelude.table" and environment . table == nil
then
if # args ~= 2 then
context . reject ( lower . site ( node ) , "table.new in an AOT builder takes array and hash capacities" )
end
for _ , capacity in ipairs ( args ) do
if capacity . type ~= "f64" and capacity . type ~= "i32" and capacity . type ~= "u32" then
context . reject ( lower . site ( node ) , "table.new capacities must be numeric" )
end
end
markLua ( kernel , lower . site ( node ) )

return ( _G.setmetatable({ op =
"lua_new_table" ,  arrayCapacity =
args [ 1 ] ,  hashCapacity =
args [ 2 ] ,  type =
"lua_table" ,  source =
lower . site ( node ) }, scalarIR.LuaNewTable) )

end




local fixedIdentity = ( node ) . scalarIntrinsic
local fixed = fixedIdentity ~= nil and admit . FIXED [ fixedIdentity ]
or not context . checked and path ~= nil and admit . fixed ( path )
or nil
if fixed ~= nil then
return fixedCall ( node , path or tostring ( fixedIdentity ) , fixed , args , kernel )
end

local intrinsic = path ~= nil and admit . math ( path ) or nil
if intrinsic ~= nil then
local laneWise = laneMath ( node , intrinsic , args , kernel )
if laneWise ~= nil then
return laneWise
end
return mathCall ( node , path , intrinsic , args , kernel )
end

local helperName = lower . nameOf ( node . obj )
if helperName == nil and ( node . obj ) . aotOrigin ~= nil and ( node . obj ) . kind == "dotIndex" then


helperName = ( ( node . obj ) . name ) . text
end
if helperName == nil then
context . reject ( lower . site ( node ) , "call target " .. tostring ( path ) .. " is not an admitted intrinsic or helper" )
end

local helper = lower . helper ( helperName , node , kernel )
if # args ~= # helper . params then
context . reject ( lower . site ( node ) , "native helper argument count does not match" )
end
for position , argument in ipairs ( args ) do
args [ position ] = lower . helperArgument ( argument , helper . params [ position ] . type , lower . site ( node ) , context )
end

return ( _G.setmetatable({ op =
"helper_call" ,  helper =
helper . name ,  uniqueName =
helper . uniqueName ,  args =
args ,  type =
# helper . resultTypes == 1 and helper . resultTypes [ 1 ] or "multi" ,  resultTypes =
helper . resultTypes ,  source =
lower . site ( node ) }, scalarIR.HelperCall) )

end



local function genericSimdFieldElement ( field ) 
local physical

= {
int8 = "i8" ,
uint8 = "u8" ,
int16 = "i16" ,
uint16 = "u16" ,
float = "f32" ,
int32 = "i32" ,
uint32 = "u32" ,
int64 = "i64" ,
uint64 = "u64" ,
number = "f64" ,
}

return physical [ field . sourceType or "" ] or field . type
end




local function maskedContribution (
node ,
receiver ,
reducerState ,
reducerOrder ,
reducerOperation ,
reducerElement ,
raw ,
environment ,
activeIndex ,
kernel
) 
local context = kernel . context
local source = lower . site ( node )
local scope = kernel . simdDo
if scope == nil then
context . reject ( source , "a masked reducer contribution belongs inside a do block, which is its region" )
end
local region = ( scope ) . region
if reducerState . finalized then
context . reject ( source , "a finalized reducer cannot receive another contribution" )
end
if reducerState . region ~= nil and reducerState . region ~= region then
context . reject ( source , "a reducer is scoped to exactly one region" )
end
local value = lower . expression ( raw [ 1 ] , environment , activeIndex , kernel )
local family , element , shape = genericSimdParts ( value . type )
local scalar = reducerElement or "f64"


if scalar == "bool" then
if family ~= "mask" then
context . reject ( source , "a masked predicate contribution takes a mask of the lanes it tests" )
end
elseif family ~= "vector" or genericSimdScalar ( element ) ~= scalar then
context . reject ( source , "a masked reducer contribution takes a vector whose element the reducer accumulates" )
end
local maskType = "simd_mask_" .. tostring ( element ) .. "_" .. tostring ( shape )
local right = nil
if reducerOperation == "dot" then
right = lower . expression ( raw [ 2 ] , environment , activeIndex , kernel )
if ( right ) . type ~= value . type then
context . reject ( source , "a masked dot contribution takes two vectors of one species" )
end
end
local mask = lower . expression ( raw [ # raw ] , environment , activeIndex , kernel )
if mask . type ~= maskType then
context . reject ( source , "a masked reducer contribution takes the mask of its vector's species" )
end
reducerState . region = region
local byName = ( scope ) . byName
if byName [ reducerState . name ] ~= true then
byName [ reducerState . name ] = true
local reducers = ( scope ) . reducers
reducers [
# reducers + 1
] = _G.setmetatable({ name =
reducerState . name ,  uniqueName =
reducerState . uniqueName ,  order =
reducerOrder ,  operation =
reducerOperation ,  element =
reducerElement ,  vectorType =
value . type }, scalarIR.ReducerRegionAccumulator)

end

return ( _G.setmetatable({ op =
"simd_reducer_add" ,  reducer =
receiver ,  value =
value ,  mask =
mask ,  right =
right ,  order =
reducerOrder ,  operation =
reducerOperation ,  element =
reducerElement ,  type =
"lua_effect" ,  source =
source }, scalarIR.VectorReducerAdd) )

end




const CORRECTED_LANES = { [ "f32_min" ] = 2 , [ "f32_max" ] = 2 , [ "f32_fma" ] = 3 , }




local function laneWiseMap (
node ,
raw ,
vectorType ,
element ,
environment ,
activeIndex ,
kernel
) 
local context = kernel . context
local source = lower . site ( node )
local scalar = genericSimdScalar ( element )
local args = { }
for position = 2 , # raw do
local operand = lower . expression ( raw [ position ] , environment , activeIndex , kernel )
if operand . op ~= "local" or operand . type ~= vectorType then
context . reject ( source , "SIMD map operands must be locals of the species" )
end
args [ # args + 1 ] = operand
end
local path = lower . dottedName ( raw [ 1 ] )
local intrinsic = path ~= nil and admit . math ( path ) or nil
if intrinsic ~= nil then
local math = intrinsic
if element ~= "f32" and element ~= "f64" then
context . reject ( source , "SIMD map applies a math operation to a floating species" )
end
if # args < math . min or math . max ~= nil and # args > ( math . max ) then
context . reject ( source , tostring ( path ) .. " has an unsupported argument count" )
end
return ( _G.setmetatable({ op =
"simd_math" ,  args =
args ,  intrinsic =
math . name ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

end


local corrected = path ~= nil and admit . fixed ( path ) or nil
if corrected ~= nil and CORRECTED_LANES [ tostring ( ( corrected ) . op ) ] ~= nil then
local fixed = corrected
if element ~= "f32" then
context . reject ( source , "SIMD map applies a binary32 correction to a binary32 species" )
end
if # args ~= fixed . arity then
context . reject ( source , tostring ( path ) .. " has an unsupported argument count" )
end

return ( _G.setmetatable({ op =
"simd_call" ,  args =
args ,  intrinsic =
tostring ( fixed . op ) ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

end
local helperName = lower . nameOf ( raw [ 1 ] )
if helperName == nil then
context . reject ( source , "SIMD map applies a math operation, a binary32 correction, or a visible pure helper" )
end
local helper = lower . helper ( helperName , node , kernel )


local carrier = scalar == "f32" and "f64" or scalar
if # helper . params ~= # args or # helper . resultTypes ~= 1 or helper . resultTypes [ 1 ] ~= carrier then
context . reject ( source , "SIMD map needs a helper over the species' scalar taking one argument per vector" )
end
for _ , param in ipairs ( helper . params ) do
if param . type ~= carrier then
context . reject ( source , "SIMD map needs a helper over the species' scalar taking one argument per vector" )
end
end

return ( _G.setmetatable({ op =
"simd_call" ,  args =
args ,  intrinsic =
"map" ,  helper =
helper . name ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

end



local function fieldAccess (
node ,
receiver ,
reading ,
spanName ,
span ,
raw ,
vectorType ,
maskType ,
element ,
environment ,
activeIndex ,
kernel
) 
local context = kernel . context
local source = lower . site ( node )
local method = reading and "load" or "store"
local wantedKind = reading and "read_span" or "write_span"
local layoutName = span ~= nil and ( span . soa ~= nil and span . soa . layout or span . type : match ( "^struct:(.+)$" ) ) or nil
local layout = layoutName ~= nil and kernel . layouts . byName [ layoutName ] or nil
if span == nil or ( span . kind ~= wantedKind and not ( reading and span . kind == "write_span" ) ) or layout == nil then
context . reject (
source ,
"SIMD field " .. method .. " needs a matching " .. (
reading and "borrowed Span or WriteSpan" or "exclusive WriteSpan"
) .. " of a reified struct or SoA row view"
)
end
local expected = reading and ( # raw == 3 or # raw == 4 ) or not reading and ( # raw == 4 or # raw == 5 )
if not expected then
context . reject ( source , "SIMD field " .. method .. " has an unsupported argument count" )
end
local token = ( raw [ 3 ] ) . token
local written = token ~= nil and ( token ) . text or ""
local fieldName = written : match ( "^\"(.*)\"$" ) or written : match ( "^'(.*)'$" ) or ""
local field = nil
for _ , candidate in ipairs ( ( layout ) . fields ) do
if candidate . name == fieldName then
field = candidate
end
end
if field == nil then
context . reject ( source , "struct " .. tostring ( layoutName ) .. " has no field " .. fieldName )
end
if tostring ( ( field ) . type ) : match ( "^simd_" ) ~= nil then



context . reject (
source ,
"field "
.. fieldName
.. " is a stored vector: read or write it whole through its row, rows[i]."
.. fieldName
)
end
local column = nil
if span ~= nil and span . soa ~= nil then
for _ , candidate in pairs ( kernel . params ) do
if candidate . soa ~= nil and scalarIR . sameSoaView ( span , candidate ) and candidate . soa . field == fieldName then
column = candidate
do break end
end
end
if column == nil then
context . reject ( source , "SoA row view has no column " .. fieldName )
end
end
if (
column ~= nil and genericSimdSpanElement ( column )
or genericSimdFieldElement ( field )
) ~= element then
context . reject ( source , "SIMD field " .. method .. " needs a field of the species' element" )
end
local offset = lower . convert ( lower . expression ( raw [ 2 ] , environment , activeIndex , kernel ) , "f64" , source , context )
local maskPosition = reading and 4 or 5


local active = raw [ maskPosition ] ~= nil and lower . expression ( raw [ maskPosition ] , environment , activeIndex , kernel )
or nil
if active ~= nil and kernel . allLaneMasks [ active ] then
active = nil
end
local masked = active ~= nil
local cursor = not masked and provedVectorCursor ( offset , spanName , kernel , receiver . type ) or nil
local cursorBinding = cursor ~= nil and environment [ cursor ] or nil
local cursorUniqueName = cursorBinding ~= nil and cursorBinding . uniqueName or nil
local args = { receiver , offset }
if not reading then
local stored = lower . expression ( raw [ 4 ] , environment , activeIndex , kernel )
if stored . type ~= vectorType then
context . reject ( source , "SIMD store value has a different element or species type" )
end
args [ # args + 1 ] = stored
end
if active ~= nil then
if ( active ) . type ~= maskType then
context . reject ( source , "SIMD " .. method .. " mask has a different species" )
end
args [ # args + 1 ] = active
end

return ( _G.setmetatable({ op =
column ~= nil and ( reading and "simd_load" or "simd_store" )
or ( reading and "simd_field_load" or "simd_field_store" ) ,  args =
args ,  span =
column ~= nil and ( column ) . name or spanName ,  layout =
column == nil and layoutName or nil ,  field =
column == nil and fieldName or nil ,  intrinsic =
column ~= nil and method or "field" ,  cursor =
cursor ,  cursorUniqueName =
cursorUniqueName ,  type =
reading and vectorType or "lua_effect" ,  source =
source }, scalarIR.Simd) )

end












local function rootedLoad (
node ,
receiver ,
method ,
bytesName ,
raw ,
vectorType ,
maskType ,
element ,
receiverType ,
environment ,
activeIndex ,
kernel
) 
local context = kernel . context
local source = lower . site ( node )
if method ~= "load" then
context . reject ( source , "a rooted byte view is read-only, so only a load may name one" )
end
if element ~= "u8" then
context . reject ( source , "a rooted byte view carries bytes, so only a uint8 species may load from it" )
end



local param = kernel . params [ bytesName ]
if param == nil or param . kind ~= "scalar" or param . type ~= "lua_string" and param . type ~= "lua_bytes" then
context . reject ( source , "SIMD rooted loads require a rooted string parameter" )
end
local rooted = _G.setmetatable({ op =
"local" ,  name =
bytesName ,  type =
param . type ,  uniqueName =
param . uniqueName ,  source =
source }, scalarIR.Name)

local offset = lower . convert ( lower . expression ( raw [ 2 ] , environment , activeIndex , kernel ) , "f64" , source , context )
local masked = raw [ 3 ] ~= nil
local cursor = not masked and provedVectorCursor ( offset , bytesName , kernel , receiverType ) or nil
local cursorBinding = cursor ~= nil and environment [ cursor ] or nil
local args = { receiver , offset }
if masked then
local active = lower . expression ( raw [ 3 ] , environment , activeIndex , kernel )
if active . type ~= maskType then
context . reject ( source , "SIMD load mask has a different species" )
end
args [ # args + 1 ] = active
end
markLua ( kernel , source )

return ( _G.setmetatable({ op =
"simd_load" ,  args =
args ,  span =
bytesName ,  rooted =
rooted ,  intrinsic =
"load" ,  cursor =
cursor ,  cursorUniqueName =
cursorBinding ~= nil and cursorBinding . uniqueName or nil ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

end





local INTERLEAVED

= { loadPairs = 2 , loadTriples = 3 , loadQuads = 4 , storePairs = 2 , storeTriples = 3 , storeQuads = 4 , }

local INTERLEAVED_NAMES = { [ 2 ] = "pairs" , [ 3 ] = "triples" , [ 4 ] = "quads" }







local function interleavedAccess (
node ,
receiver ,
method ,
raw ,
vectorType ,
element ,
environment ,
activeIndex ,
kernel
) 
local source = lower . site ( node )
local ways = INTERLEAVED [ method ] or 1
local reading = method : sub ( 1 , 4 ) == "load"
local part = kernel . interleavedPart
kernel . interleavedPart = nil
if # raw ~= ( reading and 2 or 2 + ways ) then
kernel . context . reject ( source , "SIMD " .. method .. " has an unsupported argument count" )
end
if reading and ( part == nil or ( part ) >= ways ) then
kernel . context . reject (
source ,
"SIMD " .. method .. " initializes up to " .. tostring ( ways ) .. " locals, one per interleaved vector"
)
end
local spanName = lower . nameOf ( raw [ 1 ] )
local span = spanName ~= nil and kernel . params [ spanName ] or nil
local wantedKind = reading and "read_span" or "write_span"
if span == nil
or ( span . kind ~= wantedKind and not ( reading and span . kind == "write_span" ) )
or genericSimdSpanElement ( span ) ~= element
then
kernel . context . reject (
source ,
"SIMD " .. method .. " needs a matching " .. (
reading and "borrowed Span or WriteSpan" or "exclusive WriteSpan"
)
)
end
local offset = lower . convert (
lower . expression ( raw [ 2 ] , environment , activeIndex , kernel ) ,
"f64" ,
source ,
kernel . context
)
local cursor = provedVectorCursor ( offset , spanName , kernel , tostring ( receiver . type ) , ways )
local cursorBinding = cursor ~= nil and environment [ cursor ] or nil
local cursorUniqueName = cursorBinding ~= nil and cursorBinding . uniqueName or nil
local intrinsic = ( reading and "load_" or "store_" ) .. tostring ( INTERLEAVED_NAMES [ ways ] )
if reading then
return ( _G.setmetatable({ op =
"simd_load" ,  args =
{ receiver , offset } ,  span =
spanName ,  intrinsic =
intrinsic ,  part =
part ,  cursor =
cursor ,  cursorUniqueName =
cursorUniqueName ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

end
local args = { receiver , offset }
for position = 3 , 2 + ways do
local value = lower . expression ( raw [ position ] , environment , activeIndex , kernel )
if value . type ~= vectorType then
kernel . context . reject ( source , "SIMD " .. method .. " values have a different element or species type" )
end
args [ # args + 1 ] = value
end

return ( _G.setmetatable({ op =
"simd_store" ,  args =
args ,  span =
spanName ,  intrinsic =
intrinsic ,  cursor =
cursor ,  cursorUniqueName =
cursorUniqueName ,  type =
"lua_effect" ,  source =
source }, scalarIR.Simd) )

end



local function interleavedLoadWays ( expression ) 
if expression . kind ~= "methodCall" then
return nil
end
local name = ( expression ) . name
local method = name ~= nil and ( name ) . text or ""

return method : sub ( 1 , 4 ) == "load" and INTERLEAVED [ method ] or nil
end


local function spelledElement ( element ) 
if element == "f32" then
return "float"
elseif element == "f64" then
return "number"
end

return ( element : sub ( 1 , 1 ) == "u" and "uint" or "int" ) .. element : sub ( 2 )
end



local function fixedLanesOf ( speciesType ) 
local _ , element , shape = genericSimdParts ( speciesType )
if element == nil or shape == nil or tostring ( shape ) : match ( "^fixed" ) == nil then
return nil
end

return shapes . lanes ( 16 , tostring ( element ) , tostring ( shape ) )
end





local function laneIndexOf (
index ,
what ,
least ,
element ,
shape ,
source ,
kernel
) 
local context = kernel . context
local converted = lower . convert ( index , "f64" , source , context )
local wanted = least == 0 and "a nonnegative compile-time lane count" or "a positive compile-time lane index"
if not shapes . laneExpression ( converted ) then
context . reject (
source ,
"SIMD " .. what .. " needs " .. wanted .. ": a literal, a species' lane count, or arithmetic over those"
)
end
local value = shapes . laneValue ( converted , fixedLanesOf )
if value == nil then
return converted
end
local folded = value
if folded < least or folded % 1 ~= 0 then
context . reject ( source , "SIMD " .. what .. " needs " .. wanted )
end
local lanes = fixedLanesOf ( "simd_species_" .. element .. "_" .. shape )
if least > 0 and lanes ~= nil and folded > ( lanes ) then
context . reject ( source , "SIMD " .. what .. " index exceeds the logical species lanes" )
end

return shapes . laneConstant ( folded , source )
end







local function resizedSpecies (
node ,
method ,
witness ,
receiverType ,
element ,
kernel
) 
local context = kernel . context
local source = lower . site ( node )
local wider = method == "widen"
local wanted = shapes . resizedElement ( tostring ( element ) , wider )
if wanted == nil then
context . reject (
source ,
wider and "no element is wider than 64 bits, so " .. spelledElement ( tostring ( element ) ) .. " cannot widen"
or "no element is narrower than 8 bits, so " .. spelledElement ( tostring ( element ) ) .. " cannot narrow"
)
end
local inferred = semanticRaw ( ( node ) . inferredType )
local resolved = inferred ~= nil and semanticValueType ( inferred ) or nil
local _ , named = genericSimdParts ( tostring ( resolved ) )
local dotted = lower . dottedName ( witness )
local field = dotted ~= nil and ( dotted ) : match ( "%.([^.]+)$" ) or nil
if named ~= wanted or field == nil or not SPECIES_WITNESSES [ field ] then
context . reject (
source ,
"species:" .. method .. " takes the witness of the next " .. (
wider and "wider" or "narrower"
) .. " element of the same signedness, array." .. spelledElement ( wanted ) .. " for this species"
)
end
kernel . usesSimd = true

return ( _G.setmetatable({ op =
"simd_species" ,  args =
{ } ,  intrinsic =
"species" ,  type =
shapes . resized ( receiverType , wanted ) ,  source =
source }, scalarIR.Simd) )

end

local function simdMethod (
node ,
environment ,
activeIndex ,
kernel
) 
local receiverName = lower . nameOf ( node . obj )
local binding = receiverName ~= nil and environment [ receiverName ] or nil
local receiver = nil
local receiverType = binding ~= nil and binding . type or ""
if binding == nil and node . obj ~= nil then
receiver = lower . expression ( node . obj , environment , activeIndex , kernel )
receiverType = ( receiver ) . type
end
if not tostring ( receiverType ) : match ( "^simd_" ) then
return nil
end

local method = node . name ~= nil and ( node . name ) . text or ""
local raw = node . args ~= nil and ( node . args ) . exprs or { }
receiver = receiver or lower . expression ( node . obj , environment , activeIndex , kernel )
local args = { receiver }
local source = lower . site ( node )
kernel . usesSimd = true

local reducerOrder , reducerOperation = tostring ( receiverType ) : match ( "^simd_reducer_(%a+)_(%a+)$" )
local exactOrder , exactOperation , reducerElement = reducers . parse ( tostring ( receiverType ) )
if exactOrder ~= nil then
reducerOrder , reducerOperation = exactOrder , exactOperation
end
if reducerOrder ~= nil
and (
reducerElement ~= nil
or reducerOperation == "sum"
or reducerOperation == "product"
or reducerOperation == "dot"
)
then
if receiver == nil or ( receiver ) . op ~= "local" then
kernel . context . reject ( source , "a reducer operation must name its scoped reducer binding" )
end
local reducerName = ( receiver ) . uniqueName
if reducerName == nil then
kernel . context . reject ( source , "a reducer operation must name its scoped reducer binding" )
end
local reducerState = kernel . reducers [ reducerName ]
if reducerState == nil then
kernel . context . reject ( source , "a reducer cannot be copied or passed through another value" )
end
local argumentCount = reducerOperation == "dot" and 2 or 1
if method == "add" and # raw == argumentCount + 1 then
return maskedContribution (
node ,
receiver ,
reducerState ,
reducerOrder ,
reducerOperation ,
reducerElement ,
raw ,
environment ,
activeIndex ,
kernel
)
elseif method == "add" and # raw == argumentCount then
if ( reducerState ) . finalized then
kernel . context . reject ( source , "a finalized reducer cannot receive another contribution" )
end



( reducerState ) . contributed = true
local right = nil
if reducerOperation == "dot" then
right = lower . convert (
lower . expression ( raw [ 2 ] , environment , activeIndex , kernel ) ,
reducerElement or "f64" ,
source ,
kernel . context
)
end
return ( _G.setmetatable({ op =
"reducer_add" ,  reducer =
receiver ,  value =
lower . convert (
lower . expression ( raw [ 1 ] , environment , activeIndex , kernel ) ,
reducerElement or "f64" ,
source ,
kernel . context
) ,  right =
right ,  order =
reducerOrder ,  operation =
reducerOperation ,  type =
"lua_effect" ,  source =
source }, scalarIR.ReducerAdd) )

elseif method == "value" and # raw == 0 then
if ( reducerState ) . region == nil
and not ( reducerState ) . contributed
then
kernel . context . reject ( source , "a reducer must receive its contribution before it is finalized" )
end
if ( reducerState ) . finalized then
kernel . context . reject ( source , "a reducer is finalized exactly once" )
end
( reducerState ) . finalized = true
return ( _G.setmetatable({ op =
"reducer_value" ,  reducer =
receiver ,  order =
reducerOrder ,  operation =
reducerOperation ,  type =
reducerElement ~= nil and reducers . result ( reducerOperation , reducerElement ) or "f64" ,  source =
source }, scalarIR.ReducerValue) )

end
kernel . context . reject ( source , reducerOperation .. " reducer operation " .. method .. " is not admitted" )
end

local genericFamily , genericElement , genericShape = genericSimdParts ( receiverType )
if genericFamily ~= nil then
local vectorType = "simd_vector_" .. tostring ( genericElement ) .. "_" .. tostring ( genericShape )
local maskType = "simd_mask_" .. tostring ( genericElement ) .. "_" .. tostring ( genericShape )
if genericFamily == "species" and method == "mask" and # raw == 1 then


local value = lower . expression ( raw [ 1 ] , environment , activeIndex , kernel )
if value . type == "bool" then
return ( _G.setmetatable({ op =
"simd_mask_splat" ,  args =
{ value } ,  intrinsic =
"mask" ,  type =
maskType ,  source =
source }, scalarIR.Simd) )

end
local fromFamily = genericSimdParts ( value . type )
if fromFamily ~= "mask" then
kernel . context . reject ( source , "SIMD mask takes a boolean or a mask of another species" )
end
if not shapes . sameLanes ( value . type , maskType ) then
kernel . context . reject ( source , "SIMD mask conversion requires matching logical lane counts" )
end
return ( _G.setmetatable({ op =
"simd_mask_convert" ,  args =
{ value } ,  intrinsic =
"mask" ,  type =
maskType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "species" and method == "map" and # raw >= 2 then
return laneWiseMap ( node , raw , vectorType , genericElement , environment , activeIndex , kernel )
elseif genericFamily == "species" and ( method == "widen" or method == "narrow" ) and # raw == 1 then
return resizedSpecies ( node , method , raw [ 1 ] , tostring ( receiverType ) , genericElement , kernel )
elseif genericFamily == "species" and method == "splat" and # raw == 1 then
local value = lower . convert (
lower . expression ( raw [ 1 ] , environment , activeIndex , kernel ) ,
genericSimdScalar ( genericElement ) ,
source ,
kernel . context
)
return ( _G.setmetatable({ op =
"simd_splat" ,  args =
{ value } ,  intrinsic =
"splat" ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "species" and ( method == "convert" or method == "reinterpret" ) and # raw == 1 then
local value = lower . expression ( raw [ 1 ] , environment , activeIndex , kernel )
if not simdcast . matches ( value . type , vectorType , method == "reinterpret" ) then
kernel . context . reject (
source ,
"SIMD " .. method .. " requires matching logical lane counts" .. (
method == "reinterpret" and " and equal element widths"
or "; use Fixed<N> or the species widen and narrow derive when changing element width"
)
)
end
return ( _G.setmetatable({ op =
method == "convert" and "simd_convert" or "simd_reinterpret" ,  args =
{ value } ,  intrinsic =
method ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "species" and method == "iota" and # raw == 2 then
for _ , argument in ipairs ( raw ) do
args [
# args + 1
] = lower . convert (
lower . expression ( argument , environment , activeIndex , kernel ) ,
genericSimdScalar ( genericElement ) ,
source ,
kernel . context
)
end
return ( _G.setmetatable({ op =
"simd_iota" ,  args =
{ args [ 2 ] , args [ 3 ] } ,  intrinsic =
"iota" ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "species" and method == "tail" and # raw == 1 then
local active = lower . convert (
lower . expression ( raw [ 1 ] , environment , activeIndex , kernel ) ,
"u32" ,
source ,
kernel . context
)
return ( _G.setmetatable({ op =
"simd_tail" ,  args =
{ active } ,  intrinsic =
"tail" ,  type =
maskType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "species" and INTERLEAVED [ method ] ~= nil then
return interleavedAccess (
node ,
receiver ,
method ,
raw ,
vectorType ,
genericElement ,
environment ,
activeIndex ,
kernel
)
elseif genericFamily == "species"
and (
method == "load"
or method == "store"
or method == "gather"
or method == "scatter"
or method == "scatterUnchecked"
)
then
local reading = method == "load" or method == "gather"
local indexed = method == "gather" or method == "scatter" or method == "scatterUnchecked"
local named = not indexed and raw [ 3 ] ~= nil and raw [ 3 ] . kind == "string"
local expected = reading and ( # raw == 2 or # raw == 3 ) or not reading and ( # raw == 3 or # raw == 4 )
if named then
expected = reading and ( # raw == 3 or # raw == 4 ) or not reading and ( # raw == 4 or # raw == 5 )
end
if not expected then
kernel . context . reject ( source , "SIMD " .. method .. " has an unsupported argument count" )
end
local spanName = lower . nameOf ( raw [ 1 ] )
local rootedBinding = spanName ~= nil and environment [ spanName ] or nil
if rootedBinding ~= nil and rootedBinding . kind == "rooted_span" then
return rootedLoad (
node ,
receiver ,
method ,
tostring ( rootedBinding . bytes ) ,
raw ,
vectorType ,
maskType ,
genericElement ,
receiverType ,
environment ,
activeIndex ,
kernel
)
end
local span = spanName ~= nil and kernel . params [ spanName ] or nil
local wantedKind = reading and "read_span" or "write_span"
if named then
return fieldAccess (
node ,
receiver ,
reading ,
spanName ,
span ,
raw ,
vectorType ,
maskType ,
genericElement ,
environment ,
activeIndex ,
kernel
)
end
if span == nil
or ( span . kind ~= wantedKind and not ( reading and span . kind == "write_span" ) )
or genericSimdSpanElement ( span ) ~= genericElement
then
kernel . context . reject (
source ,
"SIMD " .. method .. " needs a matching " .. (
reading and "borrowed Span or WriteSpan" or "exclusive WriteSpan"
)
)
end
local offset = lower . expression ( raw [ 2 ] , environment , activeIndex , kernel )
if indexed then
if not simdindices . matches ( offset . type , receiverType ) then
kernel . context . reject (
source ,
"SIMD indexed memory needs 32-bit or 64-bit integer indices with the same logical lane count"
)
end
if method == "scatter" and not simdindices . unique ( offset ) then
kernel . context . reject (
source ,
"SIMD scatter needs provably unique indices; scatterUnchecked explicitly asserts uniqueness without a runtime check"
)
end
else
offset = lower . convert ( offset , "f64" , source , kernel . context )
end







local activeArgument = raw [ reading and 3 or 4 ]
local active = activeArgument ~= nil and lower . expression ( activeArgument , environment , activeIndex , kernel )
or nil
if active ~= nil and kernel . allLaneMasks [ active ] then
active = nil
end
local masked = active ~= nil
local cursor = not indexed
and not masked
and provedVectorCursor ( offset , spanName , kernel , tostring ( receiverType ) )
or nil
local cursorBinding = cursor ~= nil and environment [ cursor ] or nil
local cursorUniqueName = cursorBinding ~= nil and cursorBinding . uniqueName or nil
if reading then
local loadArgs = { receiver , offset }
if active ~= nil then
if ( active ) . type ~= maskType then
kernel . context . reject ( source , "SIMD load mask has a different species" )
end
loadArgs [ # loadArgs + 1 ] = active
end
return ( _G.setmetatable({ op =
"simd_load" ,  args =
loadArgs ,  span =
spanName ,  intrinsic =
method ,  cursor =
cursor ,  cursorUniqueName =
cursorUniqueName ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

else
local stored = lower . expression ( raw [ 3 ] , environment , activeIndex , kernel )
if stored . type ~= vectorType then
kernel . context . reject ( source , "SIMD store value has a different element or species type" )
end
local storeArgs = { receiver , offset , stored }
if active ~= nil then
if ( active ) . type ~= maskType then
kernel . context . reject ( source , "SIMD store mask has a different species" )
end
storeArgs [ # storeArgs + 1 ] = active
end
return ( _G.setmetatable({ op =
"simd_store" ,  args =
storeArgs ,  span =
spanName ,  intrinsic =
method ,  cursor =
cursor ,  cursorUniqueName =
cursorUniqueName ,  type =
"lua_effect" ,  source =
source }, scalarIR.Simd) )

end
elseif genericFamily == "mask" and method == "select" and # raw == 2 then
local trueValue = simdOperand (
lower . expression ( raw [ 1 ] , environment , activeIndex , kernel ) ,
vectorType ,
source ,
kernel
)
local falseValue = simdOperand (
lower . expression ( raw [ 2 ] , environment , activeIndex , kernel ) ,
vectorType ,
source ,
kernel
)
return ( _G.setmetatable({ op =
"simd_select" ,  args =
{ receiver , trueValue , falseValue } ,  intrinsic =
"select" ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "vector" and method == "extract" and # raw == 1 then
local laneIndex = laneIndexOf (
lower . expression ( raw [ 1 ] , environment , activeIndex , kernel ) ,
"lane extraction" ,
1 ,
tostring ( genericElement ) ,
tostring ( genericShape ) ,
source ,
kernel
)
return ( _G.setmetatable({ op =
"simd_extract" ,  args =
{ receiver , laneIndex } ,  intrinsic =
"extract" ,  type =
genericSimdScalar ( genericElement ) ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "vector" and method == "insert" and # raw == 2 then
local laneIndex = laneIndexOf (
lower . expression ( raw [ 1 ] , environment , activeIndex , kernel ) ,
"lane insertion" ,
1 ,
tostring ( genericElement ) ,
tostring ( genericShape ) ,
source ,
kernel
)
return ( _G.setmetatable({ op =
"simd_insert" ,  args =
{
receiver ,
laneIndex ,
lower . convert (
lower . expression ( raw [ 2 ] , environment , activeIndex , kernel ) ,
genericSimdScalar ( genericElement ) ,
source ,
kernel . context
) ,
} ,  intrinsic =
"insert" ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "vector" and ( method == "interleave" or method == "deinterleave" ) and # raw == 1 then
return lower . rearrange (
method ,
{ receiver , lower . expression ( raw [ 1 ] , environment , activeIndex , kernel ) } ,
source ,
kernel
)
elseif genericFamily == "vector" and method == "reverse" and # raw == 0 then
return ( _G.setmetatable({ op =
"simd_permute" ,  args =
{ receiver } ,  intrinsic =
"reverse" ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "vector" and ( method == "rotateLeft" or method == "rotateRight" ) and # raw == 1 then
local count = lower . convert (
lower . expression ( raw [ 1 ] , environment , activeIndex , kernel ) ,
"f64" ,
source ,
kernel . context
)
local constant = count . op == "constant" and tonumber ( ( count ) . value ) or nil
if constant == nil or constant < 0 or constant % 1 ~= 0 then
kernel . context . reject ( source , "SIMD rotation needs a nonnegative compile-time lane count" )
end
return ( _G.setmetatable({ op =
"simd_permute" ,  args =
{ receiver , count } ,  intrinsic =
method == "rotateLeft" and "rotate_left" or "rotate_right" ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "vector" and method == "align" and # raw == 2 then
local previous = lower . expression ( raw [ 1 ] , environment , activeIndex , kernel )
if previous . type ~= vectorType then
kernel . context . reject ( source , "SIMD align operands need the same element and species" )
end
local count = laneIndexOf (
lower . expression ( raw [ 2 ] , environment , activeIndex , kernel ) ,
"alignment" ,
0 ,
tostring ( genericElement ) ,
tostring ( genericShape ) ,
source ,
kernel
)
return ( _G.setmetatable({ op =
"simd_permute" ,  args =
{ previous , receiver , count } ,  intrinsic =
"align" ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "vector" and VECTOR_EXTREMA [ method ] ~= nil and # raw == 1 then
local other = lower . expression ( raw [ 1 ] , environment , activeIndex , kernel )
local otherFamily , otherElement , otherShape = genericSimdParts ( other . type )
if otherFamily == "vector" and ( otherElement ~= genericElement or otherShape ~= genericShape ) then
kernel . context . reject ( source , "explicit SIMD operands have different element or species identities" )
end
return ( _G.setmetatable({ op =
"simd_binary" ,  args =
{ receiver , simdOperand ( other , vectorType , source , kernel ) } ,  intrinsic =
VECTOR_EXTREMA [ method ] ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "vector" and method == "fma" and # raw == 2 then
if tostring ( genericElement ) : sub ( 1 , 1 ) ~= "f" then
kernel . context . reject ( source , "SIMD fma requires a floating vector element" )
end
local operands = { receiver }
for position = 1 , 2 do
local other = lower . expression ( raw [ position ] , environment , activeIndex , kernel )
local otherFamily , otherElement , otherShape = genericSimdParts ( other . type )
if otherFamily == "vector" and ( otherElement ~= genericElement or otherShape ~= genericShape ) then
kernel . context . reject ( source , "explicit SIMD operands have different element or species identities" )
end
operands [ # operands + 1 ] = simdOperand ( other , vectorType , source , kernel )
end
return ( _G.setmetatable({ op =
"simd_binary" ,  args =
operands ,  intrinsic =
"fma" ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "vector" and VECTOR_INTEGER_BINARY [ method ] ~= nil and # raw == 1 then
if tostring ( genericElement ) : sub ( 1 , 1 ) == "f" then
kernel . context . reject ( source , "SIMD " .. method .. " requires an integer vector element" )
end
local other = lower . expression ( raw [ 1 ] , environment , activeIndex , kernel )
local otherFamily , otherElement , otherShape = genericSimdParts ( other . type )
if otherFamily == "vector" and ( otherElement ~= genericElement or otherShape ~= genericShape ) then
kernel . context . reject ( source , "explicit SIMD operands have different element or species identities" )
end
return ( _G.setmetatable({ op =
"simd_binary" ,  args =
{ receiver , simdOperand ( other , vectorType , source , kernel ) } ,  intrinsic =
VECTOR_INTEGER_BINARY [ method ] ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "vector" and method == "popcount" and # raw == 0 then
if tostring ( genericElement ) : sub ( 1 , 1 ) == "f" then
kernel . context . reject ( source , "SIMD popcount requires an integer vector element" )
end
return ( _G.setmetatable({ op =
"simd_unary" ,  args =
{ receiver } ,  intrinsic =
"popcount" ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "vector" and method == "swizzle" and # raw >= 1 and # raw <= 4 then
local indices = lower . expression ( raw [ 1 ] , environment , activeIndex , kernel )
if indices . type ~= vectorType then
kernel . context . reject ( source , "SIMD swizzle indices have a different element or species" )
end
if tostring ( genericElement ) : sub ( 1 , 1 ) == "f" then
kernel . context . reject (
source ,
"SIMD swizzle reads its indices as lane numbers and needs an integer vector"
)
end
local args = { receiver , indices }
for position = 2 , # raw do
local other = lower . expression ( raw [ position ] , environment , activeIndex , kernel )
if other . type ~= vectorType then
kernel . context . reject ( source , "SIMD swizzle operands have a different element or species" )
end
args [ position + 1 ] = other
end
local forms = { "swizzle" , "swizzle_pair" , "swizzle_triple" , "swizzle_quad" }
return ( _G.setmetatable({ op =
"simd_permute" ,  args =
args ,  intrinsic =
forms [ # raw ] ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "vector" and ( method == "compress" or method == "expand" ) and # raw == 1 then
local selected = lower . expression ( raw [ 1 ] , environment , activeIndex , kernel )
if selected . type ~= maskType then
kernel . context . reject ( source , "SIMD " .. method .. " mask has a different species" )
end
return ( _G.setmetatable({ op =
method == "compress" and "simd_compress" or "simd_expand" ,  args =
{ receiver , selected } ,  intrinsic =
method ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "vector" and ( method == "orderedPrefixSum" or method == "prefixXor" ) and # raw == 0 then
if method == "prefixXor" and tostring ( genericElement ) : sub ( 1 , 1 ) == "f" then
kernel . context . reject ( source , "SIMD prefixXor requires an integer vector element" )
end
return ( _G.setmetatable({ op =
"simd_prefix" ,  args =
{ receiver } ,  intrinsic =
method == "prefixXor" and "prefix_xor" or "prefix_sum_ordered" ,  type =
vectorType ,  source =
source }, scalarIR.Simd) )

elseif genericFamily == "mask" and # raw == 0 then
local reductions = {
any = { op = "simd_mask_any" , type = "bool" } ,
all = { op = "simd_mask_all" , type = "bool" } ,
count = { op = "simd_mask_count" , type = "u32" } ,
first = { op = "simd_mask_first" , type = "u32" } ,
bits = { op = "simd_mask_bits" , type = "u64" } ,
}
local reduction = reductions [ method ]
if reduction ~= nil then
return ( _G.setmetatable({ op =
reduction . op ,  args =
{ receiver } ,  intrinsic =
method ,  type =
reduction . type ,  source =
source }, scalarIR.Simd) )

end
end
kernel . context . reject ( source , "SIMD operation " .. method .. " is not admitted for " .. receiverType )
end

return nil
end


local function unary ( node , value , kernel ) 
local written = ( node . op ) . text
local source = lower . site ( node )
local family = genericSimdParts ( value . type )
if family == "vector" and ( written == "-" or written == "~" ) or family == "mask" and written == "~" then
return ( _G.setmetatable({ op =
"simd_unary" ,  args =
{ value } ,  intrinsic =
written == "-" and "neg" or "not" ,  type =
value . type ,  source =
source }, scalarIR.Simd) )

end


if written == "-" and ( value . type == "i64" or value . type == "u64" ) then

return ( _G.setmetatable({ op =
( value . type == "u64" and "u64_sub" or "i64_sub" ) ,  left =
_G.setmetatable({ op =  "constant_i64" ,  value =  "0" ,  type =  value . type ,  source =  source }, scalarIR.Int64Constant) ,  right =
value ,  type =
value . type ,  source =
source }, scalarIR.Fixed) )

end
local negated = written == "-" and lower . conversion ( value , "f64" , value . source ) or nil
if negated ~= nil then
return ( _G.setmetatable({ op =  "neg" ,  value =  negated ,  type =  "f64" ,  source =  source }, scalarIR.Unary) )
elseif written == "not" and value . type == "bool" then
return ( _G.setmetatable({ op =  "not" ,  value =  value ,  type =  "bool" ,  source =  source }, scalarIR.Unary) )
elseif written == "~" and ( value . type == "i64" or value . type == "u64" ) then
return ( _G.setmetatable({ op =
( value . type .. "_not" ) ,  value =
value ,  type =
value . type ,  source =
source }, scalarIR.FixedUnary) )

elseif written == "~" and bitOperand ( value ) then
local result = _G.setmetatable({ op =  "bnot" ,  value =  value ,  type =  "i32" ,  source =  source }, scalarIR.Unary)
return node . fixedArithmetic == "u32.notBits" and lower . convert ( result , "u32" , source , kernel . context ) or result
end

kernel . context . reject ( source , "unary operator " .. tostring ( written ) .. " is not admitted for this type" )

return value
end







function lower . constantWidth ( value ) 
local raw = value




while raw . op == "numeric_cast" or raw . op == "int_to_f64" do
raw = raw . value
if raw == nil then
return nil
end
end
if raw . op ~= "constant" and raw . op ~= "constant_i32" then
return nil
end
local number = tonumber ( raw . value )
if number == nil or number % 1 ~= 0 or number < 0 or number > lower . UINT32_MAX then
return nil
end

return number
end











function lower . constantString ( node ) 
local resolved = ( node ) . inferredType
if resolved == nil or resolved . tag ~= "literal" or ( node ) . immutablePath ~= true then
return nil
end
local base = resolved . base
if base == nil or base . tag ~= "string" or type ( resolved . constant ) ~= "string" then
return nil
end

return resolved . constant
end


function lower . constantNumber ( node ) 
local resolved = ( node ) . inferredType
if resolved == nil or resolved . tag ~= "literal" or ( node ) . immutablePath ~= true then
return nil
end
local base = resolved . base
if base == nil or base . tag ~= "number" or type ( resolved . constant ) ~= "number" then
return nil
end

return tostring ( resolved . constant )
end


function lower . constantBytes ( value , kernel , source ) 
local shared = kernel . context . constantNames [ value ]
if shared == nil then
kernel . context . constantValues [ # kernel . context . constantValues + 1 ] = value
shared = ("konst_%d") : format ( # kernel . context . constantValues - 1 )
kernel . context . constantNames [ value ] = shared
end
local existing = kernel . constantNames [ value ]
if existing == nil then
existing = shared
kernel . constantNames [ value ] = existing
kernel . constantOrder [
# kernel . constantOrder + 1
] = _G.setmetatable({ uniqueName =  existing ,  value =  value }, scalarIR.ConstantBytes)
end

return ( _G.setmetatable({ op =
"local" ,  name =
existing ,  uniqueName =
existing ,  type =
"lua_string" ,  source =
source }, scalarIR.Name) )

end














local function shortCircuitBound (
connective ,
left ,
environment ,
kernel
) 
if left == nil or left . kind ~= "binop" then
return nil , nil , nil
end
local comparison = left
local written = comparison . op ~= nil and ( comparison . op ) . text or ""
if connective == "and" then
local vectorCursor , vectorSpan , speciesType = laneBound ( comparison , environment , kernel )
if vectorCursor ~= nil then
return vectorCursor , vectorSpan , speciesType
end
end



if connective == "and" or written == ">=" and lower . dotCount ( comparison . rhs ) ~= nil then
local sumCursor , sumSpan , sumRoom = cursorSumBound ( comparison , environment , kernel , connective == "or" )
if sumCursor ~= nil then
return sumCursor , sumSpan , sumRoom
end
end
if not ( connective == "and" and written == "<" or connective == "or" and written == ">=" ) then
return nil , nil , nil
end
local cursor = lower . nameOf ( comparison . lhs )
local cursorBinding = cursor ~= nil and environment [ cursor ] or nil
if cursorBinding == nil or cursorBinding . type ~= "u32" then
return nil , nil , nil
end
local spanName = lower . dotCount ( comparison . rhs )
local param = spanName ~= nil and kernel . params [ spanName ] or nil
if param ~= nil and param . region ~= nil then
return cursor , spanName , scalarIR . ONE_ELEMENT
end
local lengthName = lower . nameOf ( comparison . rhs )
local scratchName = lengthName ~= nil and kernel . scratchLengthBounds [ lengthName ] or nil
local scratchBinding = scratchName ~= nil and environment [ scratchName ] or nil
if scratchBinding ~= nil and scratchBinding . type == "lua_scratch_u32" then
return cursor , scratchName , scalarIR . ONE_ELEMENT
end

return nil , nil , nil
end


local function temporary ( value , kernel , out ) 
kernel . serial = kernel . serial + 1
local name = "$value_" .. tostring ( kernel . serial )
local uniqueName = "__nupp_value_" .. tostring ( kernel . serial )
local ref = _G.setmetatable({ op =
"local" ,  name =
name ,  uniqueName =
uniqueName ,  type =
value . type ,  source =
value . source }, scalarIR.Name)

out [
# out + 1
] = _G.setmetatable({ op =
"let" ,  name =
name ,  uniqueName =
uniqueName ,  type =
value . type ,  value =
value ,  source =
value . source }, scalarIR.Let)


return ref
end


local function firstValue ( value , kernel , out ) 
if value . type ~= "multi" then
return value
end
local call = value
local bindings = { }
for position , valueType in ipairs ( call . resultTypes or { } ) do
if position > 1 then
do break end
end
kernel . serial = kernel . serial + 1
local suffix = tostring ( kernel . serial )
bindings [
# bindings + 1
] = _G.setmetatable({ kind =
"local" ,  name =
"$first_" .. suffix ,  uniqueName =
"__nupp_first_" .. suffix ,  type =
valueType }, scalarIR.Binding)

end
if # bindings == 0 then
kernel . context . reject ( value . source , "a value expression needs at least one result" )
end
out [ # out + 1 ] = _G.setmetatable({ op =  "multi_let" ,  call =  call ,  bindings =  bindings ,  source =  value . source }, scalarIR.MultiLet)
local first = bindings [ 1 ]

return ( _G.setmetatable({ op =
"local" ,  name =
first . name ,  uniqueName =
first . uniqueName ,  type =
first . type ,  source =
value . source }, scalarIR.Name) )

end

local function joinedType (
left ,
right ,
at ,
context
) 
if left == nil or left == right then
return right
end
local ordinary = { f64 = true , f32 = true , i32 = true , u32 = true }
if ordinary [ left ] and ordinary [ right ] then
return "f64"
end
context . reject ( at , "native expression results need a common scalar representation" )

return right
end

local function neverExpression ( node ) 
local inferred = semanticRaw ( ( node ) . inferredType )
return inferred ~= nil and inferred . tag == "never"
end

local function assignValue ( target , value ) 
return ( _G.setmetatable({ op =
"assign" ,  values =
{
_G.setmetatable({ target =
_G.setmetatable({ kind =
"local" ,  name =
target . name ,  uniqueName =
target . uniqueName ,  type =
target . type }, scalarIR.Target) ,  value =

value }, scalarIR.Assignment)

} ,  source =
value . source }, scalarIR.Assign) )

end

local function booleanValue ( value , kernel ) 
if kernel . context . unreachableValues [ value ] then
return ( _G.setmetatable({ op =  "bool" ,  value =  false ,  type =  "bool" ,  source =  value . source }, scalarIR.Bool) )
end
return value
end

local function negate ( value ) 
return ( _G.setmetatable({ op =  "not" ,  value =  value ,  type =  "bool" ,  source =  value . source }, scalarIR.Unary) )
end

local function guarded ( condition , body ) 
return ( _G.setmetatable({ op =
"if" ,  clauses =
{ _G.setmetatable({ condition =  condition ,  body =  body }, scalarIR.Clause) } ,  source =
condition . source }, scalarIR.If) )

end


function lower . capture (
node ,
environment ,
activeIndex ,
kernel
) 
local previous , parent = kernel . pending , kernel . expressionFrame
kernel . pending , kernel . expressionFrame = { } , nil
local value = lower . expression ( node , environment , activeIndex , kernel )
local setup = kernel . pending
kernel . pending , kernel . expressionFrame = previous , parent

return value , setup
end




function lower . logicalValue (
node ,
environment ,
activeIndex ,
kernel ,
resultType
) 
local out = kernel . pending
local result = temporary ( lower . zeroValue ( resultType , lower . site ( node ) , kernel . context ) , kernel , out )
local visitLogical





visitLogical = function ( expression , yes , no , statements ) 
expression = lower . unwrapped ( expression )
local operator = expression . kind == "binop" and ( expression ) . op or nil
local written = operator ~= nil and ( operator ) . text or ""
if written == "and" or written == "or" then
local binary = expression

local function nextOperand ( _value , branch ) 
visitLogical ( binary . rhs , yes , no , branch )
end

visitLogical (
binary . lhs ,
written == "and" and nextOperand or yes ,
written == "or" and nextOperand or no ,
statements
)
return
end
local value , setup = lower . capture ( expression , environment , activeIndex , kernel )
value = firstValue ( value , kernel , setup )
for _ , statement in ipairs ( setup ) do
statements [ # statements + 1 ] = statement
end
if kernel . context . unreachableValues [ value ] then
return
elseif value . type == "lua_nil" then
no ( value , statements )
elseif value . type == "bool" then
if value . op == "bool" then
if ( value ) . value then
yes ( value , statements )
else
no ( value , statements )
end
else
local whenTrue = { }
local whenFalse = { }
local cursor , root , room = shortCircuitBound ( "and" , expression , environment , kernel )
local whenTrueValue = true
if cursor == nil and value . op == "ge" then
cursor , root , room = shortCircuitBound ( "or" , expression , environment , kernel )
if cursor ~= nil then
local comparison = value
value = _G.setmetatable({ op =
"lt" ,  left =
comparison . left ,  right =
comparison . right ,  type =
"bool" ,  source =
comparison . source }, scalarIR.Binary)

yes , no = no , yes
whenTrueValue = false
end
end
local previous = kernel . cursorBounds
local trueBounds = { }
local falseBounds = { }
for name , spans in pairs ( previous ) do
trueBounds [ name ] , falseBounds [ name ] = spans , spans
end
local proved = nil
if cursor ~= nil then
proved = { }
withBound ( proved , cursor , root , room )
withBound ( trueBounds , cursor , root , room )
end
kernel . cursorBounds = trueBounds
yes (
_G.setmetatable({ op =  "bool" ,  value =  whenTrueValue ,  type =  "bool" ,  source =  value . source }, scalarIR.Bool) ,
whenTrue
)
trueBounds = kernel . cursorBounds
kernel . cursorBounds = falseBounds
no (
_G.setmetatable({ op =  "bool" ,  value =  not whenTrueValue ,  type =  "bool" ,  source =  value . source }, scalarIR.Bool) ,
whenFalse
)
falseBounds = kernel . cursorBounds

local invalidated = { }
for name in pairs ( previous ) do
if trueBounds [ name ] == nil or falseBounds [ name ] == nil then
invalidated [ # invalidated + 1 ] = name
end
end
for _ , name in ipairs ( invalidated ) do
previous [ name ] = nil
end
kernel . cursorBounds = previous
statements [
# statements + 1
] = _G.setmetatable({ op =
"if" ,  clauses =
{ _G.setmetatable({ condition =  value ,  body =  whenTrue ,  cursorBounds =  proved }, scalarIR.Clause) } ,  elseBody =
whenFalse ,  source =
value . source }, scalarIR.If)

end
elseif value . type == "f64"
or value . type == "f32"
or value . type == "i32"
or value . type == "u32"
or value . type == "i64"
or value . type == "u64"
or value . type == "lua_string"
then

yes ( temporary ( value , kernel , statements ) , statements )
else
kernel . context . reject ( value . source , "native logical value needs an admitted scalar type" )
end
end

local function finish ( value , statements ) 
statements [
# statements + 1
] = assignValue ( result , lower . convert ( value , resultType , value . source , kernel . context ) )
end

visitLogical ( node , finish , finish , out )

return result
end

local function expressionRaw (
node ,
environment ,
activeIndex ,
kernel
) 
local context = kernel . context
if node == nil then
context . reject ( kernel . loopSource , "an expression is missing" )
end
node = node

local kind = node . kind


if kind == "paren" or kind == "castExpr" then
local inner = kind == "paren" and ( node ) . expr or ( node ) . expr

return lower . expression ( inner , environment , activeIndex , kernel )
elseif kind == "doExpr" then
return lower . doExpression ( node , environment , kernel )
elseif kind == "switchExpr" then
return lower . switchExpression ( node , environment , kernel )
elseif kind == "ternary" then
local choice = node
local condition = booleanValue (
lower . expression ( choice . cond , environment , activeIndex , kernel ) ,
kernel
)
if condition . type ~= "bool" then
context . reject ( lower . site ( node ) , "native conditional expressions require a boolean condition" )
end
local yes , yesBody = lower . capture ( choice . ifTrue , environment , activeIndex , kernel )
local no , noBody = lower . capture ( choice . ifFalse , environment , activeIndex , kernel )
local yesNever = neverExpression ( choice . ifTrue )
local noNever = neverExpression ( choice . ifFalse )
local resultType = not yesNever and yes . type or nil
if not noNever then
resultType = joinedType ( resultType , no . type , lower . site ( node ) , context )
end
resultType = resultType or yes . type
local result = temporary ( lower . zeroValue ( resultType , lower . site ( node ) , context ) , kernel , kernel . pending )
if not yesNever then
yesBody [ # yesBody + 1 ] = assignValue ( result , lower . convert ( yes , resultType , lower . site ( node ) , context ) )
end
if not noNever then
noBody [ # noBody + 1 ] = assignValue ( result , lower . convert ( no , resultType , lower . site ( node ) , context ) )
end
local branch = guarded ( condition , yesBody )
branch . elseBody = noBody
kernel . pending [ # kernel . pending + 1 ] = branch
return result
elseif kind == "name" then
local name = lower . nameOf ( node )
local bound = name ~= nil and environment [ name ] or nil
if bound ~= nil and bound . kind == "alias" then




return ( bound . build ) ( )
end
if bound == nil then
if activeIndex ~= nil and name == activeIndex and kernel . mapEntry then
return ( _G.setmetatable({ op =  "loop_index" ,  type =  "f64" ,  source =  lower . site ( node ) }, scalarIR.LoopIndex) )
end






local constant = lower . constantString ( node )
if constant ~= nil then
return lower . constantBytes ( constant , kernel , lower . site ( node ) )
end
local number = kernel . constantNumbers [ tostring ( name ) ] or lower . constantNumber ( node )
if number ~= nil then
return ( _G.setmetatable({ op =
"constant" ,  value =
number ,  type =
"f64" ,  source =
lower . site ( node ) }, scalarIR.Constant) )

end
context . reject ( lower . site ( node ) , "value " .. tostring ( name ) .. " is not available in native code" )
end
if bound . kind == "absent_species" then
context . reject (
lower . site ( node ) ,
"this tier has no vectors, so " .. tostring (
name
) .. " is nil here; keep the vector path inside the branch that tested it against nil"
)
end
if bound . kind == "rooted_span" then
context . reject (
lower . site ( node ) ,
tostring (
name
)
.. " is a view over a rooted parameter rather than a value; a vector load may read it and nothing else"
)
end




if bound . op == "constant"
or bound . op == "constant_i32"
or bound . op == "bool"
or bound . op == "simd_lanes_generic"
or bound . op == "workgroup_index"
or bound . op == "local_index"
then
return bound
elseif bound . op == "lua_string" then
markLua ( kernel , lower . site ( node ) )
return bound
end











local op = bound . kind == "uniform" and "uniform"
or ( bound . kind == "helper_param" or bound . op == "helper_param" ) and "helper_param"
or "local"

return ( _G.setmetatable({ op =
op ,  name =
name ,  type =
bound . type ,  uniqueName =
bound . uniqueName ,  mutable =
bound . mutable ,  lengthOf =
bound . lengthOf ,  builderMode =
bound . builderMode ,  source =
lower . site ( node ) }, scalarIR.Name) )

elseif kind == "number" then
local token = ( node ) . token
local value = token ~= nil and ( token ) . text or ""
local wide = value : lower ( ) : match ( "ull$" ) and "u64" or value : lower ( ) : match ( "ll$" ) and "i64" or nil
if wide ~= nil then
return ( _G.setmetatable({ op =
"constant_i64" ,  value =
value : sub ( 1 , wide == "u64" and - 4 or - 3 ) ,  type =
wide ,  source =
lower . site ( node ) }, scalarIR.Int64Constant) )

end
if tonumber ( value ) == nil then
context . reject ( lower . site ( node ) , "the kernel needs a finite decimal numeric literal" )
end

return ( _G.setmetatable({ op =  "constant" ,  value =  value ,  type =  "f64" ,  source =  lower . site ( node ) }, scalarIR.Constant) )
elseif kind == "trueExpr" or kind == "falseExpr" then
return ( _G.setmetatable({ op =  "bool" ,  value =  kind == "trueExpr" ,  type =  "bool" ,  source =  lower . site ( node ) }, scalarIR.Bool) )
elseif kind == "nilExpr" then
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ op =  "lua_nil" ,  type =  "lua_nil" ,  source =  lower . site ( node ) }, scalarIR.LuaNil) )
elseif kind == "string" then
local token = ( node ) . token
local written = token ~= nil and ( token ) . text or "\"\""
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ op =
"lua_string" ,  value =
stringBytes ( written ) ,  type =
"lua_string" ,  source =
lower . site ( node ) }, scalarIR.LuaString) )

elseif kind == "tableExpr" then
local literal = node
local fields = { }
local arrayCapacity , hashCapacity = 0 , 0
for _ , raw in ipairs ( literal . fields or { } ) do
local key
local value
local indexed = false
if raw . kind == "fieldItem" then
arrayCapacity = arrayCapacity + 1
indexed = true
key = _G.setmetatable({ op =
"constant_i32" ,  value =
tostring ( arrayCapacity ) ,  type =
"i32" ,  source =
lower . site ( raw ) }, scalarIR.IntConstant)

value = lower . expression ( ( raw ) . value , environment , activeIndex , kernel )
elseif raw . kind == "fieldNamed" then
hashCapacity = hashCapacity + 1
local named = raw
key = _G.setmetatable({ op =
"lua_string" ,  value =
named . name ~= nil and ( named . name ) . text or "" ,  type =
"lua_string" ,  source =
lower . site ( raw ) }, scalarIR.LuaString)

value = lower . expression ( named . value , environment , activeIndex , kernel )
else
hashCapacity = hashCapacity + 1
local bracket = raw
key = lower . expression ( bracket . key , environment , activeIndex , kernel )
value = lower . expression ( bracket . value , environment , activeIndex , kernel )
end
fields [
# fields + 1
] = _G.setmetatable({ key =  key ,  value =  value ,  indexed =  indexed ,  source =  lower . site ( raw ) }, scalarIR.LuaField)
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ op =
"lua_new_table" ,  arrayCapacity =
_G.setmetatable({ op =
"constant" ,  value =
tostring ( arrayCapacity ) ,  type =
"f64" ,  source =
lower . site ( node ) }, scalarIR.Constant) ,  hashCapacity =

_G.setmetatable({ op =
"constant" ,  value =
tostring ( hashCapacity ) ,  type =
"f64" ,  source =
lower . site ( node ) }, scalarIR.Constant) ,  fields =

fields ,  type =
"lua_table" ,  source =
lower . site ( node ) }, scalarIR.LuaNewTable) )

elseif kind == "unop" and ( node ) . op ~= nil then
local operator = node
local counted = lower . dotCount ( operator )
local shared = counted ~= nil and environment [ counted ] or nil
if shared ~= nil and shared . kind == "workgroup_shared" then
return ( _G.setmetatable({ op =
"constant" ,  value =
tostring ( shared . count ) ,  type =
"f64" ,  source =
lower . site ( node ) }, scalarIR.Constant) )

end
local spanParam = counted ~= nil and kernel . params [ counted ] or nil
if spanParam ~= nil and spanParam . region ~= nil then
return ( _G.setmetatable({ op =
"span_count" ,  span =
counted ,  type =
"f64" ,  source =
lower . site ( node ) }, scalarIR.SpanCount) )

end
local stringBinding = counted ~= nil and environment [ counted ] or nil
if stringBinding ~= nil and stringBinding . type == "lua_string" then
local bytes = lower . expression ( operator . operand , environment , activeIndex , kernel )
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ op =
"lua_string_length" ,  bytes =
bytes ,  type =
"u32" ,  source =
lower . site ( node ) }, scalarIR.LuaBytes) )

end

return unary ( operator , lower . expression ( operator . operand , environment , activeIndex , kernel ) , kernel )
elseif kind == "methodCall" then
local simd = simdMethod ( node , environment , activeIndex , kernel )
if simd ~= nil then
return simd
end


local call = node
local method = call . name ~= nil and ( call . name ) . text or "?"
local receiverName = lower . nameOf ( call . obj )
local binding = receiverName ~= nil and environment [ receiverName ] or nil
local receiverType = binding ~= nil and tostring ( binding . type ) or nil
local kind = binding ~= nil and tostring ( binding . kind ) or nil
local described = receiverType == "lua_string" and "a string"
or ( kind == "write_span" or kind == "read_span" ) and "a span"
or receiverType ~= nil and "a " .. receiverType
or "this receiver"
context . reject (
lower . site ( node ) ,
"method :" .. method .. " on " .. described .. " is not admitted; only SIMD values have native methods"
)
elseif kind == "bracketIndex" then
local indexed = node
local tableName = lower . nameOf ( indexed . obj )
local tableBinding = tableName ~= nil and environment [ tableName ] or nil
if tableBinding ~= nil and tableBinding . kind == "workgroup_shared" then
if kernel . inPhase ~= true then
context . reject ( lower . site ( node ) , "workgroup scratch is read only inside phases:run" )
end
local index = lower . expression ( indexed . expr , environment , activeIndex , kernel )

local function indexRange ( value ) 
local op = value . op
if op == "constant" or op == "constant_i32" then
local constant = tonumber ( ( value ) . value )
if constant ~= nil and constant == math . floor ( constant ) and constant >= 0 then
return constant , constant
end
elseif op == "local_index" then
return 0 , ( kernel . workgroupSize ) - 1
elseif op == "numeric_cast" or op == "int_to_f64" then
return indexRange ( ( value ) . value )
elseif op == "u32_add" or op == "u32_mul" then
local pair = value
local leftMin , leftMax = indexRange ( pair . left )
local rightMin , rightMax = indexRange ( pair . right )
if leftMin ~= nil and leftMax ~= nil and rightMin ~= nil and rightMax ~= nil then
local low = op == "u32_add" and ( leftMin ) + ( rightMin )
or ( leftMin ) * ( rightMin )
local high = op == "u32_add" and ( leftMax ) + ( rightMax )
or ( leftMax ) * ( rightMax )
if high <= 4294967295 then
return low , high
end
end
elseif op == "u32_div" or op == "u32_mod" then
local pair = value
local leftMin , leftMax = indexRange ( pair . left )
local rightMin , rightMax = indexRange ( pair . right )
if leftMin ~= nil
and leftMax ~= nil
and rightMin ~= nil
and rightMin == rightMax
and rightMin > 0
then
if op == "u32_div" then
return math . floor (
( leftMin ) / ( rightMin )
) , math . floor ( ( leftMax ) / ( rightMin ) )
end
return 0 , math . min ( leftMax , ( rightMin ) - 1 )
end
end

return nil , nil
end

local minimum , maximum = indexRange ( index )
if minimum == nil or maximum == nil or minimum < 0 or maximum >= tableBinding . count then
context . reject ( lower . site ( indexed . expr ) , "shared scratch read is not statically proved in bounds" )
end
if index . op == "constant" then
index = _G.setmetatable({ op =
"constant_i32" ,  value =
tostring ( minimum ) ,  type =
"u32" ,  source =
lower . site ( indexed . expr ) }, scalarIR.IntConstant)

end
return widenLoad (
_G.setmetatable({ op =
"shared_load" ,  shared =
tableName ,  index =
index ,  type =
tableBinding . element ,  source =
lower . site ( node ) }, scalarIR.SharedLoad)
,
lower . site ( node )
)
end
if tableBinding ~= nil and tableBinding . type == "lua_table" then
local key = lower . expression ( indexed . expr , environment , activeIndex , kernel )
if key . type ~= "f64" and key . type ~= "i32" and key . type ~= "u32" then
context . reject ( lower . site ( indexed . expr ) , "fresh numeric table reads need a numeric key" )
end
markLua ( kernel , lower . site ( node ) )
return ( _G.setmetatable({ op =
"lua_table_get_index" ,  table =
lower . expression ( indexed . obj , environment , activeIndex , kernel ) ,  key =
key ,  type =
"f64" ,  source =
lower . site ( node ) }, scalarIR.LuaTableGet) )

end
return spanRead ( indexed , environment , activeIndex , kernel )
elseif kind == "dotIndex" and ( node ) . name ~= nil then
local indexed = node
local column = soaColumn ( node , kernel )
if column ~= nil then
return spanRead ( lower . unwrapped ( indexed . obj ) , environment , activeIndex , kernel , column )
end
local counted = lower . dotCount ( indexed )
local spanParam = counted ~= nil and kernel . params [ counted ] or nil
if spanParam ~= nil and spanParam . region ~= nil then
return ( _G.setmetatable({ op =
"span_count" ,  span =
counted ,  type =
"f64" ,  source =
lower . site ( node ) }, scalarIR.SpanCount) )

end
local objectName = lower . nameOf ( indexed . obj )
local object = objectName ~= nil and environment [ objectName ] or nil
if object ~= nil
and tostring ( object . type ) : match ( "^simd_species_" )
and ( indexed . name ) . text == "lanes" then
kernel . usesSimd = true
return ( _G.setmetatable({ op =
"simd_lanes_generic" ,  args =
{ lower . expression ( indexed . obj , environment , activeIndex , kernel ) } ,  intrinsic =
"lanes" ,  type =
"u32" ,  source =
lower . site ( node ) }, scalarIR.Simd) )

end

if objectName == "math" and object == nil then



local member = ( indexed . name ) . text
local spelled = member == "huge" and "inf" or member == "pi" and ("%.17g") : format ( math . pi ) or nil
if spelled ~= nil then
return ( _G.setmetatable({ op =
"constant" ,  value =
spelled ,  type =
"f64" ,  source =
lower . site ( node ) }, scalarIR.Constant) )

end
end

return fieldRead ( indexed , lower . expression ( indexed . obj , environment , activeIndex , kernel ) , kernel )
elseif kind == "binop" and ( node ) . op ~= nil then
local operator = node
local written = ( operator . op ) . text
local decided = speciesNilTest ( written , operator . lhs , operator . rhs , environment )
if decided ~= nil then
return ( _G.setmetatable({ op =  "bool" ,  value =  decided ,  type =  "bool" ,  source =  lower . site ( node ) }, scalarIR.Bool) )
end
if written == "and" or written == "or" then
local leftType = semanticValueType ( ( operator . lhs ) . inferredType )
local rightType = semanticValueType ( ( operator . rhs ) . inferredType )
local resultType = semanticValueType ( ( node ) . inferredType ) or kernel . expectedType
if resultType ~= nil and ( leftType ~= "bool" or rightType ~= "bool" ) then
return lower . logicalValue ( node , environment , activeIndex , kernel , resultType )
end
end
local left = lower . expression ( operator . lhs , environment , activeIndex , kernel )
local cursor , boundName , room = shortCircuitBound ( written , operator . lhs , environment , kernel )
local previous = kernel . cursorBounds
if cursor ~= nil then
local bounds = { }
for name , spans in pairs ( previous ) do
bounds [ name ] = spans
end
withBound ( bounds , cursor , boundName , room )
kernel . cursorBounds = bounds
end
local right , setup = lower . capture ( operator . rhs , environment , activeIndex , kernel )
kernel . cursorBounds = previous
if written == "and" or written == "or" then
left , right = booleanValue ( left , kernel ) , booleanValue ( right , kernel )
else
if context . unreachableValues [ left ] then
left = lower . zeroValue ( right . type , lower . site ( node ) , context )
end
if context . unreachableValues [ right ] then
right = lower . zeroValue ( left . type , lower . site ( node ) , context )
end
end
if # setup > 0 and ( written == "and" or written == "or" ) then
if left . type ~= "bool" or right . type ~= "bool" then
context . reject ( lower . site ( node ) , "native logical operands must be boolean" )
end
local result = temporary ( left , kernel , kernel . pending )
setup [ # setup + 1 ] = assignValue ( result , right )
kernel . pending [ # kernel . pending + 1 ] = guarded ( written == "and" and result or negate ( result ) , setup )
return result
end
if # setup > 0 then
left = temporary ( left , kernel , kernel . pending )
for _ , statement in ipairs ( setup ) do
kernel . pending [ # kernel . pending + 1 ] = statement
end
end
return binary ( operator , left , right , kernel )
elseif kind == "call" then
return call ( node , environment , activeIndex , kernel )
end

if kind == "newExpr" then




local call = ( node ) . call
local constructed = call ~= nil and call . inferredType or ( node ) . inferredType
local layout = lower . aggregate ( constructed , node , kernel . layouts , context )
local bindings = call ~= nil and call . recordFields or { }
if # bindings ~= # layout . fields then
context . reject ( lower . site ( node ) , "a native-only aggregate construction supplies every field" )
end
local values = { }
for position , binding in ipairs ( bindings ) do
local field = layout . fields [ position ]
if binding . isDefault == true or binding . node == nil then
context . reject ( lower . site ( node ) , "a native-only aggregate construction supplies every field" )
end
local value = lower . expression ( binding . node , environment , activeIndex , kernel )
values [ position ] = lower . convert ( value , field . type , lower . site ( binding . node ) , context )
end

return ( _G.setmetatable({ op =
"aggregate_new" ,  layout =
layout . name ,  values =
values ,  type =
"aggregate:" .. layout . name ,  source =
lower . site ( node ) }, scalarIR.AggregateNew) )

end
context . reject ( lower . site ( node ) , "expression kind " .. tostring ( kind ) .. " is not admitted" )

return ( _G.setmetatable({ op =  "bool" ,  value =  false ,  type =  "bool" ,  source =  lower . site ( node ) }, scalarIR.Bool) )
end



function lower . expression (
node ,
environment ,
activeIndex ,
kernel
) 
local parent , previous = kernel . expressionFrame , kernel . pending
local frame = _G.setmetatable({ output =  { } ,  operands =  {} ,  replacements =  {} }, lower.ExpressionFrame)
kernel . expressionFrame , kernel . pending = frame , frame . output
local value = expressionRaw ( node , environment , activeIndex , kernel )

local function rewrite ( child ) 
local replacement = frame . replacements [ child ]
if replacement ~= nil then
return replacement
end
local copy = { }
for key , entry in pairs ( child ) do
copy [ key ] = entry
end
visit . expressionChildren ( copy , rewrite )

return copy
end

if next ( frame . replacements ) ~= nil then
value = rewrite ( value )
end
if neverExpression ( node ) then
kernel . context . unreachableValues [ value ] = true
end
kernel . expressionFrame , kernel . pending = parent , previous
if # frame . output > 0 and parent ~= nil then
for _ , operand in ipairs ( parent . operands ) do
if parent . replacements [ operand ] == nil
and operand . op ~= "constant"
and operand . op ~= "constant_i32"
and operand . op ~= "constant_i64"
and operand . op ~= "bool"
then
parent . replacements [ operand ] = temporary ( operand , kernel , previous )
end
end
end
for _ , statement in ipairs ( frame . output ) do
previous [ # previous + 1 ] = statement
end
if parent ~= nil then
parent . operands [ # parent . operands + 1 ] = value
end

return value
end










function lower . helperValueType ( spelling ) 
if spelling == "boolean" then
return "bool"
elseif spelling == "number" or spelling == "float" or spelling == "integer" then
return "f64"
elseif spelling == "uint32" then
return "u32"
elseif spelling == "int32" then
return "i32"
elseif spelling == "uint64" then
return "u64"
elseif spelling == "int64" then
return "i64"
end

return nil
end











function lower . foreignEntry ( name , at , kernel ) 
local context = kernel . context
local call = at
local callee = call ~= nil and call . kind == "call" and call . obj or nil
local origin = callee ~= nil and callee . aotOrigin or nil
if origin == nil or origin . filename == nil or origin . name == nil then
return nil
end
local signature = call . signatureType
if not context . checked or signature == nil or signature . tag ~= "func" then
context . reject ( lower . site ( at ) , "the checker did not publish this native call signature" )
end
if signature . vararg == true or signature . generics ~= nil and # signature . generics > 0 then
context . reject ( lower . site ( at ) , "a native call into another module reaches a non-generic entry" )
end
local resultTypes = { }
for position , result in ipairs ( signature . rets or { } ) do
local resultType = semanticValueType ( result , true )
if resultType == nil or tostring ( resultType ) : match ( "^simd_reducer_" ) ~= nil then
context . reject ( lower . site ( at ) , "native entry results are scalar or SIMD values" )
end
if scalarIR . aggregateLayout ( resultType ) ~= nil then
lower . aggregate ( result , at , kernel . layouts , context )
end
resultTypes [ position ] = resultType
end
if # resultTypes ~= 1 then
context . reject ( lower . site ( at ) , "a compiled entry called from another returns one value" )
end
local params = { }
for position , param in ipairs ( signature . params or { } ) do
local mode = ( signature . paramModes or { } ) [ position ]
local paramType = semanticValueType ( param , false )
if paramType == nil
or mode ~= nil
and mode ~= "plain"
or tostring ( paramType ) : match ( "^simd_reducer_" ) ~= nil then
context . reject ( lower . site ( at ) , "native entry parameters are unowned scalar or SIMD values" )
end
if scalarIR . aggregateLayout ( paramType ) ~= nil then
lower . aggregate ( param , at , kernel . layouts , context )
end
params [
# params + 1
] = _G.setmetatable({ op =
"helper_param" ,  name =
"a" .. tostring ( position ) ,  type =
paramType ,  uniqueName =
scalarIR . identifier ( "a" , "a" .. tostring ( position ) ) ,  source =
lower . site ( at ) }, scalarIR.Name)

end
local symbol = scalarIR . qualifiedPrivateSymbol ( origin . filename , origin . name )
local known = kernel . helpers [ symbol ]
if known ~= nil then
return known
end
local called = _G.setmetatable({ name =
name ,  uniqueName =
symbol ,  params =
params ,  values =
{ } ,  resultTypes =
resultTypes ,  native =
true ,  qualified =
true ,  source =
lower . site ( at ) }, scalarIR.Helper)

kernel . helpers [ symbol ] = called
kernel . helperOrder [ # kernel . helperOrder + 1 ] = called

return called
end






function lower . helper ( name , at , kernel ) 
local context = kernel . context
if kernel . helperState [ name ] == "lowering" then
context . reject ( lower . site ( at ) , "recursive native helpers are not admitted" )
end

local declaration = kernel . helperDecls [ name ]




local native = false
if declaration == nil and kernel . entryDecls [ name ] ~= nil then
declaration = kernel . entryDecls [ name ]
native = true
end
if declaration == nil then



local foreign = lower . foreignEntry ( name , at , kernel )
if foreign ~= nil then
return foreign
end
context . reject ( lower . site ( at ) , "call target " .. name .. " is not a visible pure helper" )
end
kernel . helperState [ name ] = "lowering"

local body = declaration . body
if body == nil or body . varargParam ~= nil or body . captureTakes ~= nil or body . captureBorrows ~= nil then
context . reject ( lower . site ( declaration ) , "native helpers must be non-variadic and non-capturing" )
end

local generic = body . generics ~= nil
local checkedSignature = context . checked
and ( generic and at ~= nil and ( at ) . signatureType or body . signatureType )
or nil
if context . checked and checkedSignature == nil then
context . reject ( lower . site ( body ) , "the checker did not publish this native helper signature" )
end
if context . checked then
local effects = body . effectSummary
if effects == nil then
context . reject ( lower . site ( body ) , "the checker did not publish this native helper effect summary" )
end







if effects . allocates == true and effects . allocatesBeyondWideArithmetic ~= false
or effects . yields == true
or effects . raises == true
or effects . external == true
or next ( effects . writes or { } ) ~= nil
or next ( effects . shapes or { } ) ~= nil
or next ( effects . metatables or { } ) ~= nil
or next ( effects . escapes or { } ) ~= nil
then
context . reject ( lower . site ( body ) , "the checker reports side effects in this native helper" )
end
end

local resultTypes = { }
for position , result in ipairs ( body . rets or { } ) do
local resultType = context . checked and semanticValueType ( checkedSignature . rets [ position ] , true )
or lower . helperValueType ( lower . compactType ( result ) )
if resultType == nil then
context . reject ( lower . site ( result ) , "native helper results are scalar or SIMD values" )
end
if scalarIR . aggregateLayout ( resultType ) ~= nil then
lower . aggregate ( checkedSignature . rets [ position ] , result , kernel . layouts , context )
end
if tostring ( resultType ) : match ( "^simd_reducer_" ) ~= nil then
context . reject ( lower . site ( result ) , "reducers cannot cross a native helper result boundary" )
end
resultTypes [ # resultTypes + 1 ] = resultType
end
if # resultTypes == 0 then
context . reject ( lower . site ( body ) , "native helpers need at least one result" )
end

local params = { }
local environment = { }
for position , raw in ipairs ( body . params or { } ) do
local paramName = raw . name ~= nil and ( raw . name ) . text or nil




local paramType = context . checked and semanticValueType ( checkedSignature . params [ position ] , not native )
or ( native and lower . sourceValueType or lower . helperValueType ) ( lower . compactType ( raw . type ) )
local mode = context . checked and checkedSignature . paramModes [ position ]
or raw . modeTok ~= nil and ( raw . modeTok ) . text
or nil
if paramName == nil or paramType == nil or mode ~= nil and mode ~= "plain" then
context . reject ( lower . site ( raw ) , "native helper parameters are unowned scalar or SIMD values" )
end
if scalarIR . aggregateLayout ( paramType ) ~= nil then
lower . aggregate ( checkedSignature . params [ position ] , raw , kernel . layouts , context )
end
if tostring ( paramType ) : match ( "^simd_reducer_" ) ~= nil then
context . reject ( lower . site ( raw ) , "reducers cannot cross a native helper parameter boundary" )
end
if environment [ paramName ] ~= nil then
context . reject ( lower . site ( raw ) , "duplicate helper parameter " .. ( paramName ) )
end

local param = _G.setmetatable({ op =
"helper_param" ,  name =
paramName ,  type =
paramType ,  uniqueName =
scalarIR . identifier ( "a" , paramName ) ,  source =
lower . site ( raw ) }, scalarIR.Name)

params [ # params + 1 ] = param
environment [ paramName ] = param
end

local keyParts = { name }
for _ , param in ipairs ( params ) do
keyParts [ # keyParts + 1 ] = param . type
end
keyParts [ # keyParts + 1 ] = "returns"
for _ , result in ipairs ( resultTypes ) do
keyParts [ # keyParts + 1 ] = result
end
local helperKey = generic and table . concat ( keyParts , "_" ) or name
local known = kernel . helpers [ helperKey ]
if known ~= nil then
kernel . helperState [ name ] = "done"
return known
end

if native and # resultTypes ~= 1 then
context . reject ( lower . site ( declaration ) , "a compiled entry called from another returns one value" )
end
if native then
local called = _G.setmetatable({ name =
name ,  uniqueName =
scalarIR . privateSymbol ( name ) ,  params =
params ,  values =
{ } ,  resultTypes =
resultTypes ,  native =
true ,  source =
lower . site ( declaration ) }, scalarIR.Helper)

kernel . helpers [ helperKey ] = called
kernel . helperState [ name ] = "done"
kernel . helperOrder [ # kernel . helperOrder + 1 ] = called

return called
end

local statements = body . body ~= nil and ( body . body ) . stats or { }
local returned = statements [ 1 ]
local single = # statements == 1
and returned ~= nil
and returned . kind == "returnStmt"
and # ( ( returned ) . exprs or { } ) == # resultTypes
if not single then
context . reject ( lower . site ( body . body or body ) , "a native helper body is one matching return list" )
end

local helper = _G.setmetatable({ name =
helperKey ,  uniqueName =
kernel . symbol .. "_helper_" .. scalarIR . privateSymbol ( helperKey ) : sub ( 4 ) ,  params =
params ,  values =
{ } ,  resultTypes =
resultTypes ,  source =
lower . site ( declaration ) }, scalarIR.Helper)

kernel . helpers [ helperKey ] = helper

for position , result in ipairs ( ( returned ) . exprs or { } ) do
local value , setup = lower . capture ( result , environment , nil , kernel )
if # setup > 0 then
context . reject ( lower . site ( result ) , "a statementful helper must be declared @aot" )
end
if value . type ~= resultTypes [ position ] then
context . reject ( lower . site ( returned ) , "native helper result type does not match" )
end
helper . values [ position ] = value
end
kernel . helperState [ name ] = "done"
kernel . helperOrder [ # kernel . helperOrder + 1 ] = helper

return helper
end







local function inherit ( environment ) 
local copied = { }
for name , bound in pairs ( environment ) do
copied [ name ] = bound
end

return copied
end







local function bind (
name ,
valueType ,
mutable ,
at ,
environment ,
kernel
) 
if environment [ name ] ~= nil then
kernel . context . reject ( lower . site ( at ) , "native locals may not shadow " .. name )
end
kernel . serial = kernel . serial + 1

local binding = _G.setmetatable({ kind =
"local" ,  name =
name ,  type =
valueType ,  mutable =
mutable ,  uniqueName =
scalarIR . identifier ( "v" .. tostring ( kernel . serial ) , name ) ,  source =
lower . site ( at ) }, scalarIR.Binding)

environment [ name ] = binding

return binding
end


local function scratchLengthSource ( value , kernel ) 
if value . op == "lua_scratch_u32_length" or value . op == "lua_scratch_u32_escape_length" then
return ( ( value ) . scratch ) . name
elseif value . op == "local" then
return kernel . scratchLengthBounds [ ( value ) . name ]
elseif value . op == "u32_and" then
local pair = value

local function mask ( other ) 
return other . op == "constant_i32" and tonumber ( ( other ) . value ) == 2147483647
end

if mask ( pair . right ) then
return scratchLengthSource ( pair . left , kernel )
elseif mask ( pair . left ) then
return scratchLengthSource ( pair . right , kernel )
end
end

return nil
end













local function noteBinding ( name , value , binding , kernel ) 
kernel . lengthBounds [ name ] = nil
if value . op == "lua_string_length" then
local bytes = ( value ) . bytes
binding . lengthOf = bytes . name
kernel . lengthBounds [ name ] = bytes . name
end
local scratchLength = scratchLengthSource ( value , kernel )
if scratchLength ~= nil then
kernel . scratchLengthBounds [ name ] = scratchLength
else
kernel . scratchLengthBounds [ name ] = nil
end
kernel . scratchBounds [ name ] = nil
if value . op == "lua_scratch_u32" and ( value ) . fixed ~= nil then
kernel . scratchBounds [ name ] = ( value ) . fixed
elseif value . op == "lua_scratch_u8" and ( value ) . fixed ~= nil then
kernel . scratchBounds [ name ] = ( value ) . fixed
end
if value . op == "lua_builder" then
binding . builderMode = ( value ) . mode
end
end






local function staticTruth ( value ) 
if value . op == "bool" then
return ( value ) . value
end
if value . op ~= "eq"
and value . op ~= "ne"
and value . op ~= "lt"
and value . op ~= "le"
and value . op ~= "gt"
and value . op ~= "ge"
then
return nil
end
local binary = value
local left = scalarIR . exactInteger ( binary . left )
local right = scalarIR . exactInteger ( binary . right )
if left == nil or right == nil then
return nil
end
local leftValue = left
local rightValue = right

local __nuppT108= binary . op ; local __nuppT109;
if  __nuppT108== "eq"  then  __nuppT109= leftValue == rightValue
elseif  __nuppT108== "ne"  then  __nuppT109= leftValue ~= rightValue
elseif  __nuppT108== "lt"  then  __nuppT109= leftValue < rightValue
elseif  __nuppT108== "le"  then  __nuppT109= leftValue <= rightValue
elseif  __nuppT108== "gt"  then  __nuppT109= leftValue > rightValue
else  __nuppT109= leftValue >= rightValue
end; return __nuppT109
end



local function switchCaseValue ( node , kernel ) 
local exact = ( node ) . switchStaticValue
local value = nil
local kind = nil
if exact ~= nil then
kind = exact . tag == "literal" and type ( exact . constant ) or "nil"
value = exact . constant
else
local raw = node
while raw . kind == "paren" do
raw = raw . expr
end
if raw . kind == "number" then
kind , value = "number" , tonumber ( ( raw . token . text : gsub ( "_" , "" ) ) )
elseif raw . kind == "unop" and raw . op . text == "-" and raw . operand . kind == "number" then
kind , value = "number" , - ( tonumber ( ( raw . operand . token . text : gsub ( "_" , "" ) ) ) )
elseif raw . kind == "string" then
kind , value = "string" , stringBytes ( raw . token . text )
elseif raw . kind == "trueExpr" or raw . kind == "falseExpr" then
kind , value = "boolean" , raw . kind == "trueExpr"
elseif raw . kind == "nilExpr" then
kind = "nil"
end
end
local source = lower . site ( node )
if kind == "number" and value ~= nil then
return ( _G.setmetatable({ op =  "constant" ,  value =  ( "%.17g" ) : format ( value ) ,  type =  "f64" ,  source =  source }, scalarIR.Constant) )
elseif kind == "string" then
return ( _G.setmetatable({ op =  "lua_string" ,  value =  value ,  type =  "lua_string" ,  source =  source }, scalarIR.LuaString) )
elseif kind == "boolean" then
return ( _G.setmetatable({ op =  "bool" ,  value =  value ,  type =  "bool" ,  source =  source }, scalarIR.Bool) )
elseif kind == "nil" then
return ( _G.setmetatable({ op =  "lua_nil" ,  type =  "lua_nil" ,  source =  source }, scalarIR.LuaNil) )
end
kernel . context . reject ( source , "native switch cases must be static primitive values" )

return ( _G.setmetatable({ op =  "bool" ,  value =  false ,  type =  "bool" ,  source =  source }, scalarIR.Bool) )
end



local function switchLocal (
stat ,
node ,
out ,
environment ,
kernel
) 
local context = kernel . context
local names = stat . names or { }
if # names ~= 1 or # ( stat . exprs or { } ) ~= 1 then
context . reject ( lower . site ( stat ) , "a native switch initializes exactly one local" )
end
if # ( node . cases or { } ) == 0 and node . elseCase == nil then
context . reject ( lower . site ( node ) , "a native numeric switch requires an arm" )
end



local constantString = lower . constantString ( lower . unwrapped ( node . selector ) )
local selector
if constantString ~= nil then
selector = _G.setmetatable({ op =
"lua_string" ,  value =
constantString ,  type =
"lua_string" ,  source =
lower . site ( node . selector ) }, scalarIR.LuaString)

else
selector = lower . expression ( node . selector , environment , kernel . index , kernel )
end
local numeric = selector . type == "f64" or selector . type == "f32" or selector . type == "i32" or selector . type == "u32"
if not numeric and selector . type ~= "bool" and selector . type ~= "lua_nil" and selector . type ~= "lua_string" then
context . reject ( lower . site ( node . selector ) , "a native switch selector needs a supported primitive representation" )
end
if selector . type == "lua_nil" or selector . type == "lua_string" then
markLua ( kernel , lower . site ( node ) )
end
local nativeLabelsFit = selector . type == "i32" or selector . type == "u32"


for _ , arm in ipairs ( node . cases or { } ) do
if arm . patternKind ~= "static" then
context . reject ( lower . site ( arm ) , "native switches do not admit type cases" )
elseif arm . guard ~= nil then




context . reject ( lower . site ( arm ) , "native switches do not admit a `where` guard" )
elseif arm . body ~= nil or arm . expr == nil then
context . reject ( lower . site ( arm ) , "native switches require expression arms" )
end
for _ , caseValue in ipairs ( arm . values or { } ) do
local constant = switchCaseValue ( caseValue , kernel )
local number = constant . op == "constant" and tonumber ( ( constant ) . value ) or nil
nativeLabelsFit = nativeLabelsFit
and number ~= nil
and number == math . floor ( number )
and (
selector . type == "i32" and number >= -2147483648 and number <= 2147483647
or selector . type == "u32" and number >= 0 and number <= 4294967295
)
end
end
local otherwise = node . elseCase
if otherwise and ( otherwise . body ~= nil or otherwise . expr == nil ) then
context . reject ( lower . site ( otherwise ) , "native switches require expression arms" )
end

local staticSelector = scalarIR . exactInteger ( selector )
local staticPrimitive = selector . op == "bool" or selector . type == "lua_nil" or selector . op == "lua_string"
if staticSelector ~= nil or staticPrimitive then


local chosen = nil
for _ , arm in ipairs ( node . cases or { } ) do
for _ , caseValue in ipairs ( arm . values or { } ) do
local label = switchCaseValue ( caseValue , kernel )
local matched = staticSelector ~= nil
and label . op == "constant"
and tonumber ( ( label ) . value ) == staticSelector
or staticPrimitive
and label . type == selector . type
and ( selector . type == "lua_nil" or ( label ) . value == ( selector ) . value )
if chosen == nil and matched then
chosen = arm . expr
end
end
end
if chosen == nil and otherwise ~= nil then
chosen = otherwise . expr
end
if chosen == nil then
context . reject ( lower . site ( node ) , "a constant switch selector matches no arm" )
end
local chosenValue = firstValue (
lower . expression ( chosen , environment , kernel . index , kernel ) ,
kernel ,
out
)
local annotation = stat . types ~= nil and ( stat . types ) [ 1 ] or nil
local resultType = annotatedValueType ( annotation , context ) or kernel . expectedType or chosenValue . type
if resultType == nil or resultType == "multi" or resultType : match ( "^ref:" ) then
context . reject ( lower . site ( stat ) , "native switch results must be scalar" )
end
resultType = resultType
local resultBinding = bind ( names [ 1 ] . text , resultType , false , stat , environment , kernel )
local converted = lower . convert ( chosenValue , resultType , lower . site ( node ) , context )
noteBinding ( names [ 1 ] . text , converted , resultBinding , kernel )
out [
# out + 1
] = _G.setmetatable({ op =
"let" ,  name =
names [ 1 ] . text ,  uniqueName =
resultBinding . uniqueName ,  value =
converted ,  type =
resultType ,  source =
lower . site ( stat ) }, scalarIR.Let)

return
end

local selectorName = "$switch_selector_" .. tostring ( kernel . serial + 1 )
local selectorBinding = bind ( selectorName , selector . type , false , node , environment , kernel )
out [
# out + 1
] = _G.setmetatable({ op =
"let" ,  name =
selectorName ,  uniqueName =
selectorBinding . uniqueName ,  value =
selector ,  type =
selector . type ,  source =
lower . site ( node . selector ) }, scalarIR.Let)

local selectorRef = _G.setmetatable({ op =
"local" ,  name =
selectorName ,  uniqueName =
selectorBinding . uniqueName ,  type =
selector . type ,  source =
lower . site ( node . selector ) }, scalarIR.Name)


local arms




= { }
for _ , arm in ipairs ( node . cases or { } ) do
local value , setup = lower . capture ( arm . expr , environment , kernel . index , kernel )
value = firstValue ( value , kernel , setup )
arms [ # arms + 1 ] = { case = arm , value = value , setup = setup , never = neverExpression ( arm . expr ) }
end
local elseValue = nil
local elseSetup = { }
if otherwise ~= nil then
local value , setup = lower . capture ( otherwise . expr , environment , kernel . index , kernel )
elseValue , elseSetup = firstValue ( value , kernel , setup ) , setup
end
local annotation = stat . types ~= nil and ( stat . types ) [ 1 ] or nil
local inferredResult = nil
for _ , arm in ipairs ( arms ) do
if not arm . never then
inferredResult = joinedType ( inferredResult , arm . value . type , lower . site ( arm . case ) , context )
end
end
local elseNever = otherwise ~= nil and neverExpression ( otherwise . expr )
if elseValue ~= nil and not elseNever then
inferredResult = joinedType ( inferredResult , elseValue . type , lower . site ( otherwise ) , context )
end
inferredResult = inferredResult or "f64"
local resultType = annotatedValueType ( annotation , context )
or kernel . expectedType
or semanticValueType ( ( node ) . inferredType )
or inferredResult
if resultType == nil or resultType == "multi" or resultType : match ( "^ref:" ) then
context . reject ( lower . site ( stat ) , "native switch results must be scalar" )
end
resultType = resultType

local resultBinding = bind ( names [ 1 ] . text , resultType , false , stat , environment , kernel )
local zero = lower . zeroValue ( resultType , lower . site ( stat ) , context )
out [
# out + 1
] = _G.setmetatable({ op =
"let" ,  name =
names [ 1 ] . text ,  uniqueName =
resultBinding . uniqueName ,  value =
zero ,  type =
resultType ,  source =
lower . site ( stat ) }, scalarIR.Let)


local target = _G.setmetatable({ kind =
"local" ,  name =
resultBinding . name ,  uniqueName =
resultBinding . uniqueName ,  type =
resultType }, scalarIR.Target)

local clauses = { }
local nativePlan = switchplan . native ( nativeLabelsFit and selector . type or "f64" )
for _ , lowered in ipairs ( arms ) do
local condition = nil
for _ , caseValue in ipairs ( lowered . case . values or { } ) do
local label = switchCaseValue ( caseValue , kernel )
local number = label . op == "constant" and tonumber ( ( label ) . value ) or nil
local right
if nativePlan . tag == "NativeIntegerSwitch" then
local number = number
if selector . type == "i32" and ( number < -2147483648 or number > 2147483647 ) then
context . reject ( lower . site ( caseValue ) , "native switch case is outside int32" )
elseif selector . type == "u32" and ( number < 0 or number > 4294967295 ) then
context . reject ( lower . site ( caseValue ) , "native switch case is outside uint32" )
end
local spelling = ("%.0f") : format ( number )
right = _G.setmetatable({ op =
"constant_i32" ,  value =
spelling ,  type =
selector . type ,  source =
lower . site ( caseValue ) }, scalarIR.IntConstant)

else
right = label
end
local equal
local comparable = right . type == selector . type or numeric and right . type == "f64"
if not comparable then
equal = _G.setmetatable({ op =  "bool" ,  value =  false ,  type =  "bool" ,  source =  lower . site ( caseValue ) }, scalarIR.Bool)
elseif right . type == "lua_string" then
equal = _G.setmetatable({ op =
"lua_string_match" ,  bytes =
selectorRef ,  value =
( right ) . value ,  type =
"bool" ,  source =
lower . site ( caseValue ) }, scalarIR.LuaStringMatch)

elseif right . type == "lua_nil" then
equal = _G.setmetatable({ op =  "bool" ,  value =  true ,  type =  "bool" ,  source =  lower . site ( caseValue ) }, scalarIR.Bool)
else
equal = _G.setmetatable({ op =
"eq" ,  left =
selectorRef ,  right =
right ,  type =
"bool" ,  source =
lower . site ( caseValue ) }, scalarIR.Binary)

end
condition = condition ~= nil
and _G.setmetatable({ op =
"or" ,  left =
condition ,  right =
equal ,  type =
"bool" ,  source =
lower . site ( caseValue ) }, scalarIR.Binary)

or equal
end
if not lowered . never then
local assignment = _G.setmetatable({ target =
target ,  value =
lower . convert ( lowered . value , resultType , lower . site ( lowered . case ) , context ) }, scalarIR.Assignment)

lowered . setup [
# lowered . setup + 1
] = _G.setmetatable({ op =  "assign" ,  values =  { assignment } ,  source =  lower . site ( lowered . case ) }, scalarIR.Assign)
end
clauses [
# clauses + 1
] = _G.setmetatable({ condition =
condition ,  body =
lowered . setup ,  source =
lower . site ( lowered . case ) }, scalarIR.Clause)

end
local elseBody = nil
if otherwise and elseValue and not elseNever then
local elseAssignment = _G.setmetatable({ target =
target ,  value =
lower . convert ( elseValue , resultType , lower . site ( otherwise ) , context ) }, scalarIR.Assignment)

elseSetup [
# elseSetup + 1
] = _G.setmetatable({ op =  "assign" ,  values =  { elseAssignment } ,  source =  lower . site ( otherwise ) }, scalarIR.Assign)
elseBody = elseSetup
end
if elseNever then
elseBody = elseSetup
end
out [ # out + 1 ] = _G.setmetatable({ op =  "if" ,  clauses =  clauses ,  elseBody =  elseBody ,  source =  lower . site ( node ) }, scalarIR.If)
environment [ selectorName ] = nil
end

function lower . zeroValue ( valueType , source , context ) 
if valueType == "bool" then
return ( _G.setmetatable({ op =  "bool" ,  value =  false ,  type =  "bool" ,  source =  source }, scalarIR.Bool) )
elseif valueType == "i32" or valueType == "u32" then
return ( _G.setmetatable({ op =  "constant_i32" ,  value =  "0" ,  type =  valueType ,  source =  source }, scalarIR.IntConstant) )
elseif valueType == "i64" or valueType == "u64" then
return ( _G.setmetatable({ op =  "constant_i64" ,  value =  "0" ,  type =  valueType ,  source =  source }, scalarIR.Int64Constant) )
elseif valueType == "f64" or valueType == "f32" then
return lower . convert (
_G.setmetatable({ op =  "constant" ,  value =  "0" ,  type =  "f64" ,  source =  source }, scalarIR.Constant) ,
valueType ,
source ,
context
)
elseif valueType == "lua_nil" then
return ( _G.setmetatable({ op =  "lua_nil" ,  type =  "lua_nil" ,  source =  source }, scalarIR.LuaNil) )
elseif valueType == "lua_string" then
return ( _G.setmetatable({ op =  "lua_string" ,  value =  "" ,  type =  "lua_string" ,  source =  source }, scalarIR.LuaString) )
end
context . reject ( source , "native expression blocks require an admitted scalar result" )

return ( _G.setmetatable({ op =  "bool" ,  value =  false ,  type =  "bool" }, scalarIR.Bool) )
end



local function exitValueLoops ( body , done ) 
for _ , statement in ipairs ( body ) do
if statement . op == "if" then
local branch = statement
for _ , clause in ipairs ( branch . clauses ) do
exitValueLoops ( clause . body , done )
end
if branch . elseBody ~= nil then
exitValueLoops ( branch . elseBody , done )
end
elseif statement . op == "block" then
exitValueLoops ( ( statement ) . body , done )
elseif statement . op == "fornum" or statement . op == "while" or statement . op == "repeat" then
local loop = statement
exitValueLoops ( loop . body , done )
if loop . conditionBody ~= nil then
exitValueLoops ( loop . conditionBody , done )
loop . condition = _G.setmetatable({ op =
loop . op == "repeat" and "or" or "and" ,  left =
loop . op == "repeat" and done or negate ( done ) ,  right =
loop . condition ,  type =
"bool" }, scalarIR.Binary)

end
loop . body [ # loop . body + 1 ] = guarded ( done , { _G.setmetatable({ op =  "break" }, scalarIR.Break) } )
end
end
end

function lower . doExpression ( node , environment , kernel ) 
local output = kernel . pending
local done = temporary (
_G.setmetatable({ op =  "bool" ,  value =  false ,  type =  "bool" ,  source =  lower . site ( node ) }, scalarIR.Bool) ,
kernel ,
output
)
local previous = kernel . valueFrame
local frame = _G.setmetatable({ done =  done ,  assignments =  {} ,  yields =  0 }, lower.ValueFrame)
kernel . valueFrame = frame
local body = lower . block ( node . body ~= nil and ( node . body ) . stats or { } , inherit ( environment ) , kernel )
kernel . valueFrame = previous
local result = frame . result
if result == nil then


output [ # output ] = nil
output [ # output + 1 ] = _G.setmetatable({ op =  "block" ,  body =  body ,  source =  lower . site ( node ) }, scalarIR.Block)
return lower . zeroValue ( kernel . expectedType or kernel . resultTypes [ 1 ] or "f64" , lower . site ( node ) , kernel . context )
end
local inferred = nil
for _ , assignment in ipairs ( frame . assignments ) do
inferred = joinedType ( inferred , assignment . value . type , lower . site ( node ) , kernel . context )
end
local valueType = semanticValueType ( ( node ) . inferredType )
or inferred
or kernel . expectedType
or kernel . resultTypes [ 1 ]
or result . type
result . type = valueType
for _ , assignment in ipairs ( frame . assignments ) do
assignment . target . type = valueType
assignment . value = lower . convert ( assignment . value , valueType , lower . site ( node ) , kernel . context )
end
output [
# output + 1
] = _G.setmetatable({ op =
"let" ,  name =
result . name ,  uniqueName =
result . uniqueName ,  type =
result . type ,  value =
lower . zeroValue ( result . type , lower . site ( node ) , kernel . context ) ,  source =
lower . site ( node ) }, scalarIR.Let)

exitValueLoops ( body , done )
output [ # output + 1 ] = _G.setmetatable({ op =  "block" ,  body =  body ,  source =  lower . site ( node ) }, scalarIR.Block)

return result
end

function lower . switchExpression ( node , environment , kernel ) 
local name = "$switch_value_" .. tostring ( kernel . serial + 1 )
local stat = _G.setmetatable({ kind =
"localStmt" ,  names =
{
(
{
kind = "name" ,
text = name ,
line = 1 ,
col = 1 ,
offset = 1 ,
trivia = lexer . arena ( "" ) ,
triviaCount = 0 ,
triviaFirst = 0
}
)
} ,  exprs =
{ node } ,  types =
{ } }, cst.LocalStmt)

stat [ 1 ] = node
local inner = inherit ( environment )
switchLocal ( stat , node , kernel . pending , inner , kernel )
local bound = inner [ name ]

return ( _G.setmetatable({ op =
"local" ,  name =
bound . name ,  uniqueName =
bound . uniqueName ,  type =
bound . type ,  source =
lower . site ( node ) }, scalarIR.Name) )

end


local function stringAppendPieces ( node , name ) 
if node == nil then
return nil
end
if node . kind == "name" and lower . nameOf ( node ) == name then
return { }
end
if node . kind ~= "binop" then
return nil
end
local joined = node
if joined . op == nil or ( joined . op ) . text ~= ".." then
return nil
end
local pieces = stringAppendPieces ( joined . lhs , name )
if pieces == nil then
return nil
end
pieces [ # pieces + 1 ] = joined . rhs

return pieces
end




function lower . stringAccumulators ( statements ) 
local declared = { }
local appended , returned , invalid = { } , { } , { }

local function walk ( node ) 
if node == nil then
return
end
if node . kind == "localStmt" then
local stat = node
if # ( stat . names or { } ) == 1 and # ( stat . exprs or { } ) == 1 then
local name = ( stat . names or { } ) [ 1 ] . text
if declared [ name ] then
invalid [ name ] = true
else
declared [ name ] = true
end
end
elseif node . kind == "assignStmt" then
local stat = node
local targets , exprs = stat . targets or { } , stat . exprs or { }
if # targets == 1 and # exprs == 1 and targets [ 1 ] . kind == "name" then
local name = tostring ( lower . nameOf ( targets [ 1 ] ) )
if stringAppendPieces ( exprs [ 1 ] , name ) ~= nil then
appended [ name ] = true
else
invalid [ name ] = true
end
end
elseif node . kind == "returnStmt" then
for _ , value in ipairs ( ( node ) . exprs or { } ) do
local name = lower . nameOf ( value )
if name ~= nil then
returned [ name ] = true
end
end
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

for _ , statement in ipairs ( statements ) do
walk ( statement )
end
local found = { }
for name in pairs ( declared ) do
if appended [ name ] and returned [ name ] and not invalid [ name ] then
found [ name ] = true
end
end

return found
end


local function localStmt (
stat ,
out ,
environment ,
kernel
) 
local context = kernel . context
local names = stat . names or { }
local exprs = stat . exprs or { }
if # names == 0 or # exprs == 0 then
context . reject ( lower . site ( stat ) , "native locals must be initialized" )
end
if kernel . phasesName ~= nil and # names == 1 and # exprs == 1 and exprs [ 1 ] . kind == "methodCall" then
local call = exprs [ 1 ]
local args = call . args ~= nil and ( ( call . args ) . exprs or { } ) or { }
if lower . nameOf ( call . obj ) == kernel . phasesName
and call . name ~= nil
and ( call . name ) . text == "scratch"
then
if # args ~= 2 then
context . reject ( lower . site ( call ) , "phases:scratch takes an initial value and a static count" )
end
local token = cst . firstToken ( args [ 2 ] )
local count = token ~= nil and tonumber ( ( token ) . text ) or nil
if count == nil or count ~= math . floor ( count ) or count < 1 then
context . reject ( lower . site ( args [ 2 ] ) , "workgroup scratch count must be a positive integer literal" )
end
local initial = lower . expression ( args [ 1 ] , environment , kernel . index , kernel )
if initial . type ~= "f32" and initial . type ~= "i32" and initial . type ~= "u32" then
context . reject ( lower . site ( args [ 1 ] ) , "workgroup scratch elements must be f32, int32, or uint32" )
end
local shared = _G.setmetatable({ name =
names [ 1 ] . text ,  element =
initial . type ,  count =
count ,  initial =
initial ,  source =
lower . site ( stat ) }, scalarIR.Shared)

local byName = kernel . shared
if byName [ names [ 1 ] . text ] ~= nil then
context . reject ( lower . site ( stat ) , "workgroup scratch names may not be shadowed" )
end
byName [ names [ 1 ] . text ] = shared
local ordered = kernel . sharedOrder
ordered [ # ordered + 1 ] = shared
environment [ names [ 1 ] . text ] = { kind = "workgroup_shared" , element = initial . type , count = count , }
return
end
end
if # names == 1 and # exprs == 1 and kernel . stringAccumulators [ names [ 1 ] . text ] then
local initial = lower . expression ( exprs [ 1 ] , environment , kernel . index , kernel )
if initial . type ~= "lua_string" then
context . reject ( lower . site ( exprs [ 1 ] ) , "a string accumulator must start with a string" )
end
local binding = bind ( names [ 1 ] . text , "lua_string_buffer" , nil , stat , environment , kernel )
out [
# out + 1
] = _G.setmetatable({ op =
"let" ,  name =
names [ 1 ] . text ,  uniqueName =
binding . uniqueName ,  type =
"lua_string_buffer" ,  value =
_G.setmetatable({ op =
"lua_string_buffer" ,  initial =
initial ,  type =
"lua_string_buffer" ,  source =
lower . site ( exprs [ 1 ] ) }, scalarIR.LuaStringBuffer) ,  source =

lower . site ( stat ) }, scalarIR.Let)

markLua ( kernel , lower . site ( stat ) )
return
end

if # exprs == 1 and # names == 1 and exprs [ 1 ] . kind == "switchExpr" then
return switchLocal ( stat , exprs [ 1 ] , out , environment , kernel )
end

if # exprs == 1
and exprs [ 1 ] . kind == "call"
and not context . vectors
and calledIdentity ( exprs [ 1 ] , kernel ) == "nupp.simd.vectors"
then


admitSpecies ( exprs [ 1 ] , kernel )
if # names ~= 1 then
context . reject ( lower . site ( stat ) , "native local initializer count must match names" )
end
if environment [ names [ 1 ] . text ] ~= nil then
context . reject ( lower . site ( stat ) , "native locals may not shadow " .. names [ 1 ] . text )
end
environment [ names [ 1 ] . text ] = { kind = "absent_species" }
return
end

if # exprs == 1
and exprs [ 1 ] . kind == "call"
and calledIdentity ( exprs [ 1 ] , kernel ) == "nupp.codec.valuebuilder.bytes"
then







local call = exprs [ 1 ]
local arguments = call . args ~= nil and ( ( call . args ) . exprs or { } ) or { }
if # names ~= 1 or # arguments ~= 1 then
context . reject ( lower . site ( stat ) , "valuebuilder.bytes takes one rooted string parameter" )
end
local rooted = lower . expression ( arguments [ 1 ] , environment , kernel . index , kernel )
if not rootedBytesParam ( rooted , kernel ) then
context . reject ( lower . site ( call ) , "valuebuilder.bytes needs a rooted string parameter" )
end
if environment [ names [ 1 ] . text ] ~= nil then
context . reject ( lower . site ( stat ) , "native locals may not shadow " .. names [ 1 ] . text )
end
environment [ names [ 1 ] . text ] = { kind = "rooted_span" , bytes = ( rooted ) . name }
return
end

local values = { }
local interleaved = # exprs == 1 and interleavedLoadWays ( exprs [ 1 ] ) or nil
if interleaved ~= nil then


for position = 1 , math . min ( # names , interleaved ) do
kernel . interleavedPart = position - 1
values [ position ] = lower . expression ( exprs [ 1 ] , environment , kernel . index , kernel )
end
kernel . interleavedPart = nil
elseif # exprs == 1 then
local previousType = kernel . expectedType
kernel . expectedType = annotatedValueType ( stat . types ~= nil and ( stat . types ) [ 1 ] or nil , context )
local only = lower . expression ( exprs [ 1 ] , environment , kernel . index , kernel )
kernel . expectedType = previousType
if only . type == "multi" then


local call = only
local resultTypes = call . resultTypes or { }
if # resultTypes < # names then
context . reject ( lower . site ( stat ) , "multiple-result helper count does not match local names" )
end

local bindings = { }
for position , token in ipairs ( names ) do
local annotated = annotatedValueType (
stat . types ~= nil and ( stat . types ) [ position ] or nil ,
context
)
local valueType = resultTypes [ position ]
if annotated ~= nil and annotated ~= valueType then
context . reject ( lower . site ( stat ) , "native local annotation does not match" )
end
bindings [ position ] = bind ( token . text , valueType , nil , stat , environment , kernel )
end
out [
# out + 1
] = _G.setmetatable({ op =  "multi_let" ,  call =  call ,  bindings =  bindings ,  source =  lower . site ( stat ) }, scalarIR.MultiLet)

return
end
values [ 1 ] = only
else
for _ , expression in ipairs ( exprs ) do
local value = lower . expression ( expression , environment , kernel . index , kernel )
if value . type == "multi" then
context . reject ( lower . site ( expression ) , "a multiple-result call must be the only initializer" )
end
values [ # values + 1 ] = value
end
end

if # values ~= # names then
context . reject ( lower . site ( stat ) , "native local initializer count must match names" )
end
for position , token in ipairs ( names ) do
local annotation = stat . types ~= nil and ( stat . types ) [ position ] or nil
local expected = annotatedValueType ( annotation , context ) or values [ position ] . type







if annotation == nil and values [ position ] . op == "widen_f32_f64" and # exprs == # names then
local inferred = semanticValueType ( ( exprs [ position ] ) . inferredType )
if inferred == "f32" then
expected = "f32"
end
end
if expected == nil then
context . reject (
lower . site ( stat ) ,
"native local annotation " .. lower . compactType ( annotation ) .. " is not admitted"
)
end

local value = lower . convert ( values [ position ] , expected , lower . site ( stat ) , context )
if tostring ( expected ) : match ( "^simd_reducer_" ) ~= nil and value . op ~= "reducer_init" then
context . reject ( lower . site ( stat ) , "a reducer cannot be copied or passed through another value" )
end
local binding = bind (
token . text ,
expected ,
( value ) . mutable ,
stat ,
environment ,
kernel
)
noteBinding ( token . text , value , binding , kernel )
if value . op == "reducer_init" then
local state = _G.setmetatable({ name =
token . text ,  uniqueName =
binding . uniqueName ,  contributed =
false ,  finalized =
false ,  source =
lower . site ( stat ) }, lower.ReducerState)

kernel . reducers [ binding . uniqueName ] = state
kernel . reducerOrder [ # kernel . reducerOrder + 1 ] = state
end
if value . op == "simd_lanes_generic" and not kernel . reassignedNames [ token . text ] then


environment [ token . text ] = value
else
out [
# out + 1
] = _G.setmetatable({ op =
"let" ,  name =
token . text ,  uniqueName =
binding . uniqueName ,  type =
expected ,  value =
value ,  source =
lower . site ( stat ) }, scalarIR.Let)

end
end
end


local function assignTarget ( target , environment , kernel ) 
local context = kernel . context
if target . kind == "name" then
local binding = environment [ tostring ( lower . nameOf ( target ) ) ]
if binding == nil or binding . kind ~= "local" then
context . reject ( lower . site ( target ) , "native assignment target must be a local" )
end
if tostring ( binding . type ) : match ( "^lua_" ) ~= nil and binding . type ~= "lua_string" then
context . reject ( lower . site ( target ) , "Lua construction handles cannot be reassigned" )
end
if tostring ( binding . type ) : match ( "^simd_reducer_" ) ~= nil then
context . reject ( lower . site ( target ) , "a reducer binding cannot be reassigned" )
end

return ( _G.setmetatable({ kind =
"local" ,  name =
binding . name ,  uniqueName =
binding . uniqueName ,  type =
binding . type }, scalarIR.Target) )

end

local indexed = target
if target . kind ~= "dotIndex" or indexed . name == nil then
context . reject ( lower . site ( target ) , "native assignment targets are locals or mutable struct fields" )
end

local object = lower . expression ( indexed . obj , environment , kernel . index , kernel )
if scalarIR . aggregateLayout ( object . type ) ~= nil then
context . reject (
lower . site ( target ) ,
"a native-only aggregate is a value: construct a new one with the field changed"
)
end
local layoutName = object . type : match ( "^ref:(.+)$" )
local layout = layoutName ~= nil and kernel . layouts . byName [ layoutName ] or nil
if layout == nil or ( object ) . mutable ~= true then
context . reject ( lower . site ( target ) , "native field assignment needs getMut(index)" )
end

local wanted = ( indexed . name ) . text
local field = nil
for _ , candidate in ipairs ( ( layout ) . fields ) do
if candidate . name == wanted then
field = candidate
end
end
if field == nil then
context . reject ( lower . site ( target ) , "unknown native struct field " .. wanted )
end

return ( _G.setmetatable({ kind =
"field" ,  object =
object ,  layout =
layoutName ,  field =
( field ) . name ,  type =
( field ) . type ,  sourceType =
( field ) . sourceType }, scalarIR.Target) )

end


local function soaStore (
target ,
valueNode ,
out ,
environment ,
kernel ,
compound
) 
local column = soaColumn ( target , kernel )
if column == nil then
return false
end
if column . kind ~= "write_span" then
kernel . context . reject ( lower . site ( target ) , "native SoA stores require an exclusive writable view" )
end
local indexed = lower . unwrapped ( ( target ) . obj )
local loaded = spanRead ( indexed , environment , kernel . index , kernel , column )
local address = ( loaded . op == "widen_f32_f64" and ( loaded ) . value or loaded )


local changed = assignedNames ( valueNode , { } )
if changed [ address . cursor or address . index ] then
kernel . context . reject (
lower . site ( valueNode ) ,
"a native SoA store cannot change its index while evaluating the value"
)
end
local left = compound ~= nil and temporary ( loaded , kernel , out ) or loaded
local value = lower . expression ( valueNode , environment , kernel . index , kernel )
if compound ~= nil then
local operator = { kind = "binop" , op = { text = compound . text : sub ( 1 , -2 ) } , [ 1 ] = target }
value = binary ( operator , left , value , kernel )
end
out [
# out + 1
] = _G.setmetatable({ op =
"store" ,  span =
column . name ,  index =
address . index ,  indexUniqueName =
address . indexUniqueName ,  cursor =
address . cursor ,  cursorUniqueName =
address . cursorUniqueName ,  value =
lower . storeConvert ( value , column . type , lower . site ( target ) , kernel . context ) ,  source =
lower . site ( target ) }, scalarIR.Store)


return true
end


local function assignStmt (
stat ,
out ,
environment ,
kernel
) 
local context = kernel . context
local exprs = stat . exprs or { }
local targets = stat . targets or { }
if # targets == 1 and # exprs == 1 and soaStore ( targets [ 1 ] , exprs [ 1 ] , out , environment , kernel ) then
return
end

if # targets == 1 and # exprs == 1 and targets [ 1 ] . kind == "name" then
local name = tostring ( lower . nameOf ( targets [ 1 ] ) )
local binding = environment [ name ]
if binding ~= nil and binding . type == "lua_string_buffer" then
local pieces = stringAppendPieces ( exprs [ 1 ] , name )
if pieces == nil then
context . reject ( lower . site ( stat ) , "a lowered string accumulator is append-only" )
end
for _ , piece in ipairs ( pieces ) do
local value = lower . expression ( piece , environment , kernel . index , kernel )
if value . type ~= "lua_string" then
context . reject ( lower . site ( piece ) , "a string accumulator appends only strings" )
end
out [
# out + 1
] = _G.setmetatable({ op =
"lua_string_buffer_append" ,  buffer =
_G.setmetatable({ op =
"local" ,  name =
binding . name ,  uniqueName =
binding . uniqueName ,  type =
"lua_string_buffer" ,  source =
lower . site ( targets [ 1 ] ) }, scalarIR.Name) ,  value =

value ,  source =
lower . site ( stat ) }, scalarIR.LuaStringBufferAppend)

end
markLua ( kernel , lower . site ( stat ) )
return
end
end

if # targets ~= 1 or # exprs ~= 1 then
for _ , target in ipairs ( targets ) do
local name = lower . nameOf ( target )
local binding = name ~= nil and environment [ name ] or nil
if binding ~= nil and binding . type == "lua_string" then
context . reject ( lower . site ( stat ) , "AOT Lua string reassignment must have one target and one value" )
end
end
end

if # targets == 1 and # exprs == 1 and targets [ 1 ] . kind == "dotIndex" then
local target = targets [ 1 ]
local tableName = lower . nameOf ( target . obj )
local tableBinding = tableName ~= nil and environment [ tableName ] or nil
if tableBinding ~= nil and tableBinding . type == "lua_table" and target . name ~= nil then
local value = lower . expression ( exprs [ 1 ] , environment , kernel . index , kernel )
out [
# out + 1
] = _G.setmetatable({ op =
"lua_set_key" ,  table =
_G.setmetatable({ op =
"local" ,  name =
tableBinding . name ,  uniqueName =
tableBinding . uniqueName ,  type =
"lua_table" ,  source =
lower . site ( target . obj ) }, scalarIR.Name) ,  key =

_G.setmetatable({ op =
"lua_string" ,  value =
( target . name ) . text ,  type =
"lua_string" ,  source =
lower . site ( target . name ) }, scalarIR.LuaString) ,  value =

value ,  source =
lower . site ( stat ) }, scalarIR.LuaSet)

markLua ( kernel , lower . site ( stat ) )
return
end
end

if # targets == 1 and # exprs == 1 and targets [ 1 ] . kind == "bracketIndex" then
local target = targets [ 1 ]
local spanName = lower . nameOf ( target . obj )
local output = spanName ~= nil and kernel . params [ spanName ] or nil
local tableBinding = spanName ~= nil and environment [ spanName ] or nil
if tableBinding ~= nil and tableBinding . kind == "workgroup_shared" then
if kernel . inPhase ~= true then
context . reject ( lower . site ( target ) , "workgroup scratch is written only inside phases:run" )
end
local index = lower . expression ( target . expr , environment , kernel . index , kernel )
if index . op ~= "local_index" then
context . reject ( lower . site ( target . expr ) , "shared scratch writes must use exactly localIndex" )
end
local value = lower . expression ( exprs [ 1 ] , environment , kernel . index , kernel )
out [
# out + 1
] = _G.setmetatable({ op =
"shared_store" ,  shared =
spanName ,  index =
index ,  value =
lower . convert ( value , tableBinding . element , lower . site ( stat ) , context ) ,  source =
lower . site ( stat ) }, scalarIR.SharedStore)

return
end
if tableBinding ~= nil and tableBinding . type == "lua_table" then
local key = lower . expression ( target . expr , environment , kernel . index , kernel )
if key . type ~= "f64" and key . type ~= "i32" and key . type ~= "u32" and key . type ~= "lua_string" then
context . reject ( lower . site ( target . expr ) , "fresh table keys must be numeric or strings" )
end
local value = lower . expression ( exprs [ 1 ] , environment , kernel . index , kernel )
if value . type ~= "f64"
and value . type ~= "f32"
and value . type ~= "i32"
and value . type ~= "u32"
and value . type ~= "bool"
and value . type ~= "lua_table"
and value . type ~= "lua_string"
and value . type ~= "lua_nil"
then
context . reject ( lower . site ( exprs [ 1 ] ) , "fresh table values must be admitted Lua primitives or tables" )
end
out [
# out + 1
] = _G.setmetatable({ op =
( key . type == "lua_string" and "lua_set_key" or "lua_set_index" ) ,  table =
_G.setmetatable({ op =
"local" ,  name =
tableBinding . name ,  uniqueName =
tableBinding . uniqueName ,  type =
"lua_table" ,  source =
lower . site ( target . obj ) }, scalarIR.Name) ,  key =

key ,  value =
value ,  source =
lower . site ( stat ) }, scalarIR.LuaSet)

markLua ( kernel , lower . site ( stat ) )
return
end
if output == nil or output . kind ~= "write_span" then
context . reject ( lower . site ( target ) , "native indexed stores require a writable span" )
end
local indexArg = lower . unwrapped ( target . expr )
local direct = lower . nameOf ( indexArg )
local cursor , cursorOffset = provedCursor ( indexArg , spanName , kernel )
if not ( kernel . index ~= "" and direct == kernel . index ) and cursor == nil then
context . reject ( lower . site ( target ) , cursorRefusal ( "stores" , indexArg , spanName , kernel ) )
end
provenIndex ( spanName , cursor , target , kernel )
local value = lower . expression ( exprs [ 1 ] , environment , kernel . index , kernel )
local cursorBinding = cursor ~= nil and environment [ cursor ] or nil
out [
# out + 1
] = _G.setmetatable({ op =
"store" ,  span =
spanName ,  index =
cursor == nil and kernel . index or "" ,  indexUniqueName =
cursor == nil and kernel . indexUniqueName or nil ,  cursor =
cursor ,  cursorUniqueName =
cursorBinding ~= nil and cursorBinding . uniqueName or nil ,  cursorOffset =
cursorOffset ~= 0 and cursorOffset or nil ,  value =
lower . storeConvert ( value , output . element . type , lower . site ( stat ) , context ) ,  source =
lower . site ( stat ) }, scalarIR.Store)

return
end

local values = { }
if # exprs == 1 then
local only = lower . expression ( exprs [ 1 ] , environment , kernel . index , kernel )
if only . type == "multi" then
context . reject (
lower . site ( stat ) ,
"multiple-result helpers initialize locals; ordinary multiple assignment uses explicit values"
)
end
values [ 1 ] = only
else
for _ , expression in ipairs ( exprs ) do
values [ # values + 1 ] = lower . expression ( expression , environment , kernel . index , kernel )
end
end
if # values ~= # targets then
context . reject ( lower . site ( stat ) , "native assignment counts must match" )
end

local assignments = { }
for position , target in ipairs ( targets ) do
local lowered = assignTarget ( target , environment , kernel )
local store = lowered . kind == "field" and lower . storeConvert or lower . convert
assignments [
position
] = _G.setmetatable({ target =
lowered ,  value =
store ( values [ position ] , lowered . type , lower . site ( stat ) , context ) }, scalarIR.Assignment)

end
out [ # out + 1 ] = _G.setmetatable({ op =  "assign" ,  values =  assignments ,  source =  lower . site ( stat ) }, scalarIR.Assign)
for _ , entry in ipairs ( assignments ) do
local target = entry . target
if target . kind == "local" and target . name ~= nil then
kernel . cursorBounds [ target . name ] = nil
kernel . lengthBounds [ target . name ] = nil
kernel . scratchBounds [ target . name ] = nil
local scratchLength = scratchLengthSource ( entry . value , kernel )
if scratchLength ~= nil then
kernel . scratchLengthBounds [ target . name ] = scratchLength
else
kernel . scratchLengthBounds [ target . name ] = nil
end
end
end
end





local function forBound ( bound , at , kernel ) 
local literal = bound
local sign = 1
if literal . op == "neg" then
literal = ( literal ) . value
sign = -1
end
if literal . op == "constant" then
local number = tonumber ( ( literal ) . value )
if number ~= nil then
number = number * sign
end


if not kernel . gpuTarget and number == 0 and ( sign < 0 or 1 / ( number ) < 0 ) then
return bound
end
if number ~= nil and number == math . floor ( number ) then


local spelling = ("%.0f") : format ( number )
if number < lower . INT32_MIN or number > lower . INT32_MAX then
if kernel . gpuTarget then
kernel . context . reject ( lower . site ( at ) , "native for bound " .. spelling .. " is outside int32" )
end
return bound
end
return ( _G.setmetatable({ op =  "constant_i32" ,  value =  spelling ,  type =  "i32" ,  source =  bound . source }, scalarIR.IntConstant) )
end
end
if kernel . gpuTarget and bound . type ~= "i32" then
kernel . context . reject ( lower . site ( at ) , "GPU counted loop bounds must be int32 or exact int32 literals" )
end
if bound . type ~= "i32" and bound . type ~= "u32" and bound . type ~= "f64" then
kernel . context . reject ( lower . site ( at ) , "native for bounds must be numeric" )
end

return bound
end





local function sharedPhaseCollision ( statements ) 
local written = { }
local crossRead = { }
local inspectExpression
inspectExpression = function ( value ) 
if value . op == "shared_load" then
local load = value
if load . index . op ~= "local_index" then
crossRead [ load . shared ] = true
end
end
visit . expressionChildren ( value , function ( child ) 
inspectExpression ( child )
return child
end )
end
local inspectBlock
inspectBlock = function ( block ) 
for _ , statement in ipairs ( block ) do
if statement . op == "shared_store" then
written [ ( statement ) . shared ] = true
end
visit . statementExpressions ( statement , function ( value ) 
inspectExpression ( value )
return value
end )
if statement . op == "if" then
for _ , clause in ipairs ( ( statement ) . clauses ) do
inspectBlock ( clause . body )
end
inspectBlock ( ( statement ) . elseBody or { } )
elseif statement . op == "while"
or statement . op == "repeat"
or statement . op == "fornum"
or statement . op == "block"
then
inspectBlock ( ( statement ) . body )
end
end
end
inspectBlock ( statements )
for name in pairs ( written ) do
if crossRead [ name ] == true then
return name
end
end

return nil
end






function lower . block ( statements , environment , kernel ) 
local context = kernel . context
local out = { }
local root = out
local previous , parent = kernel . pending , kernel . expressionFrame
kernel . pending , kernel . expressionFrame = out , nil


local function nested ( body ) 
local block = body

return lower . block ( block ~= nil and ( block ) . stats or { } , inherit ( environment ) , kernel )
end





local function comparedBound ( comparison ) 
local vectorCursor , vectorSpan , speciesType = laneBound ( comparison , environment , kernel )
if vectorCursor ~= nil then
return vectorCursor , vectorSpan , speciesType
end
local sumCursor , sumSpan , sumRoom = cursorSumBound ( comparison , environment , kernel )
if sumCursor ~= nil then
return sumCursor , sumSpan , sumRoom
end
local written = comparison . op ~= nil and ( comparison . op ) . text or ""
local cursor = lower . nameOf ( comparison . lhs )
local spanName = lower . dotCount ( comparison . rhs )
local binding = cursor ~= nil and environment [ cursor ] or nil
local param = spanName ~= nil and kernel . params [ spanName ] or nil
if written == "<" and binding ~= nil and binding . type == "u32" and param ~= nil and param . region ~= nil then
return cursor , spanName , scalarIR . ONE_ELEMENT
end
local lengthName = lower . nameOf ( comparison . rhs )
local bytesName = lengthName ~= nil and kernel . lengthBounds [ lengthName ] or nil
local bytes = bytesName ~= nil and kernel . params [ bytesName ] or nil
if written == "<"
and binding ~= nil
and binding . type == "u32"
and bytes ~= nil
and bytes . kind == "scalar"
and ( bytes . type == "lua_string" or bytes . type == "lua_bytes" )
then
return cursor , bytesName , scalarIR . ONE_ELEMENT
end
local scratchName = lengthName ~= nil and kernel . scratchLengthBounds [ lengthName ] or nil
local scratch = scratchName ~= nil and environment [ scratchName ] or nil
if written == "<"
and binding ~= nil
and binding . type == "u32"
and scratch ~= nil
and scratch . type == "lua_scratch_u32"
then
return cursor , scratchName , scalarIR . ONE_ELEMENT
end

return nil , nil , nil
end



local function cursorBound ( condition , into ) 
if condition == nil or condition . kind ~= "binop" then
return into
end
local comparison = condition
local written = comparison . op ~= nil and ( comparison . op ) . text or ""
if written == "and" then
return cursorBound ( comparison . rhs , cursorBound ( comparison . lhs , into ) )
end
local cursor , root , room = comparedBound ( comparison )
if cursor == nil then
return into
end
local bounds = into or { }
withBound ( bounds , cursor , root , room )

return bounds
end










local function nestedWithCursor (
body ,
proved ,
loop
) 
if loop ~= true and proved == nil then
return nested ( body )
end
local previous = kernel . cursorBounds
local reassigned = loop == true and assignedNames ( body , { } ) or { }
local bounds = { }
for name , spans in pairs ( previous ) do
if reassigned [ name ] ~= true then
bounds [ name ] = spans
end
end
for name , spans in pairs ( proved or { } ) do
for root , room in pairs ( spans ) do
withBound ( bounds , name , root , room )
end
end
kernel . cursorBounds = bounds
local lowered = nested ( body )
local invalidated = { }
for name in pairs ( previous ) do
if bounds [ name ] == nil then
invalidated [ # invalidated + 1 ] = name
end
end
for _ , name in ipairs ( invalidated ) do
previous [ name ] = nil
end
kernel . cursorBounds = previous

return lowered
end

for _ , authored in ipairs ( statements ) do
local stat = authored
while stat . kind == "pragmaStmt" do
local pragma = stat
stat = pragma . stat
end
local expressionFrame = _G.setmetatable({ output =  out ,  operands =  {} ,  replacements =  {} }, lower.ExpressionFrame)
kernel . expressionFrame = expressionFrame
local firstStatement = # out + 1
local frame = kernel . valueFrame
local before = frame ~= nil and frame . yields or 0
local kind = stat . kind
if kind == "yieldStmt" then
if frame == nil then
context . reject ( lower . site ( stat ) , "yield requires an enclosing do expression" )
end
local frame = frame
local value = firstValue (
lower . expression ( ( stat ) . value , environment , kernel . index , kernel ) ,
kernel ,
out
)
local target = ( frame ) . result
if target == nil then
target = _G.setmetatable({ op =
"local" ,  name =
frame . done . name .. "_result" ,  uniqueName =
tostring ( frame . done . uniqueName ) .. "_result" ,  type =
value . type ,  source =
lower . site ( stat ) }, scalarIR.Name)

frame . result = target
end
local assigned = assignValue ( target , value )
frame . assignments [ # frame . assignments + 1 ] = assigned . values [ 1 ]
out [ # out + 1 ] = assigned
out [ # out + 1 ] = assignValue ( frame . done , _G.setmetatable({ op =  "bool" ,  value =  true ,  type =  "bool" }, scalarIR.Bool) )
frame . yields = frame . yields + 1
elseif kind == "localStmt" then
localStmt ( stat , out , environment , kernel )
elseif kind == "callStmt" then
local statement = stat
local method = statement . expr ~= nil
and statement . expr . kind == "methodCall"
and statement . expr
or nil
local phaseMethod = method ~= nil
and kernel . phasesName ~= nil
and lower . nameOf ( ( method ) . obj ) == kernel . phasesName
and ( method ) . name ~= nil
and ( ( method ) . name ) . text
or nil
if method ~= nil and phaseMethod == "reduceSum" then
local args = ( method ) . args ~= nil
and ( ( ( ( method ) . args ) . exprs or { } ) )
or { }
local sharedName = # args == 1 and lower . nameOf ( args [ 1 ] ) or nil
local shared = sharedName ~= nil and environment [ sharedName ] or nil
local size = kernel . workgroupSize
if shared == nil or shared . kind ~= "workgroup_shared" or shared . element ~= "f32" then
context . reject ( lower . site ( method ) , "phases:reduceSum takes one f32 scratch array" )
end
if size == nil or size < 1 or size & ( size - 1 ) ~= 0 then
context . reject ( lower . site ( method ) , "fixed-tree reduction needs a power-of-two workgroup size" )
end
local stride = _G.math.floor(( ( size ) ) / ( 2 ))
while stride > 0 do
local lane = _G.setmetatable({ op =
"local_index" ,  type =
"u32" ,  source =
lower . site ( method ) }, scalarIR.WorkgroupIndex)

local offset = _G.setmetatable({ op =
"constant_i32" ,  value =
tostring ( stride ) ,  type =
"u32" ,  source =
lower . site ( method ) }, scalarIR.IntConstant)

local rightIndex = _G.setmetatable({ op =
"u32_add" ,  left =
lane ,  right =
offset ,  type =
"u32" ,  source =
lower . site ( method ) }, scalarIR.Fixed)

local left = _G.setmetatable({ op =
"shared_load" ,  shared =
sharedName ,  index =
lane ,  type =
"f32" ,  source =
lower . site ( method ) }, scalarIR.SharedLoad)

local right = _G.setmetatable({ op =
"shared_load" ,  shared =
sharedName ,  index =
rightIndex ,  type =
"f32" ,  source =
lower . site ( method ) }, scalarIR.SharedLoad)

local write = _G.setmetatable({ op =
"shared_store" ,  shared =
sharedName ,  index =
lane ,  value =
_G.setmetatable({ op =
"f32_add" ,  left =
left ,  right =
right ,  type =
"f32" ,  source =
lower . site ( method ) }, scalarIR.Fixed) ,  source =

lower . site ( method ) }, scalarIR.SharedStore)

out [
# out + 1
] = _G.setmetatable({ op =
"phase" ,  body =
{
_G.setmetatable({ op =
"if" ,  clauses =
{
_G.setmetatable({ condition =
_G.setmetatable({ op =
"lt" ,  left =
lane ,  right =
offset ,  type =
"bool" ,  source =
lower . site ( method ) }, scalarIR.Binary) ,  body =

{ write } ,  source =
lower . site ( method ) }, scalarIR.Clause)
,
} ,  source =
lower . site ( method ) }, scalarIR.If)
,
} ,  source =
lower . site ( stat ) }, scalarIR.Phase)

stride = _G.math.floor(( stride ) / ( 2 ))
end
elseif method ~= nil and phaseMethod == "inclusiveScan" then
local args = ( method ) . args ~= nil
and ( ( ( ( method ) . args ) . exprs or { } ) )
or { }
local valuesName = # args == 2 and lower . nameOf ( args [ 1 ] ) or nil
local temporaryName = # args == 2 and lower . nameOf ( args [ 2 ] ) or nil
local values = valuesName ~= nil and environment [ valuesName ] or nil
local temporary = temporaryName ~= nil and environment [ temporaryName ] or nil
local size = kernel . workgroupSize
if values == nil
or temporary == nil
or values . kind ~= "workgroup_shared"
or temporary . kind ~= "workgroup_shared"
or values . element ~= "u32"
or temporary . element ~= "u32"
or valuesName == temporaryName
then
context . reject ( lower . site ( method ) , "phases:inclusiveScan takes two distinct u32 scratch arrays" )
end
if size == nil
or size < 1
or size & ( size - 1 ) ~= 0
or values . count ~= size
or temporary . count ~= size
then
context . reject (
lower . site ( method ) ,
"fixed scan needs two power-of-two arrays with one value per lane"
)
end

local sourceName = valuesName
local targetName = temporaryName
local offset = 1
while offset < ( size ) do
local lane = _G.setmetatable({ op =
"local_index" ,  type =
"u32" ,  source =
lower . site ( method ) }, scalarIR.WorkgroupIndex)

local distance = _G.setmetatable({ op =
"constant_i32" ,  value =
tostring ( offset ) ,  type =
"u32" ,  source =
lower . site ( method ) }, scalarIR.IntConstant)

local current = _G.setmetatable({ op =
"shared_load" ,  shared =
sourceName ,  index =
lane ,  type =
"u32" ,  source =
lower . site ( method ) }, scalarIR.SharedLoad)

local previous = _G.setmetatable({ op =
"shared_load" ,  shared =
sourceName ,  index =
_G.setmetatable({ op =
"u32_sub" ,  left =
lane ,  right =
distance ,  type =
"u32" ,  source =
lower . site ( method ) }, scalarIR.Fixed) ,  type =

"u32" ,  source =
lower . site ( method ) }, scalarIR.SharedLoad)

local accumulated = _G.setmetatable({ op =
"u32_add" ,  left =
current ,  right =
previous ,  type =
"u32" ,  source =
lower . site ( method ) }, scalarIR.Fixed)


local function store ( value ) 
return ( _G.setmetatable({ op =
"shared_store" ,  shared =
targetName ,  index =
lane ,  value =
value ,  source =
lower . site ( method ) }, scalarIR.SharedStore) )

end

out [
# out + 1
] = _G.setmetatable({ op =
"phase" ,  body =
{
_G.setmetatable({ op =
"if" ,  clauses =
{
_G.setmetatable({ condition =
_G.setmetatable({ op =
"ge" ,  left =
lane ,  right =
distance ,  type =
"bool" ,  source =
lower . site ( method ) }, scalarIR.Binary) ,  body =

{ store ( accumulated ) } ,  source =
lower . site ( method ) }, scalarIR.Clause)
,
} ,  elseBody =
{ store ( current ) } ,  source =
lower . site ( method ) }, scalarIR.If)
,
} ,  source =
lower . site ( stat ) }, scalarIR.Phase)

sourceName , targetName = targetName , sourceName
offset = offset * 2
end
if sourceName ~= valuesName then
local lane = _G.setmetatable({ op =
"local_index" ,  type =
"u32" ,  source =
lower . site ( method ) }, scalarIR.WorkgroupIndex)

out [
# out + 1
] = _G.setmetatable({ op =
"phase" ,  body =
{
_G.setmetatable({ op =
"shared_store" ,  shared =
valuesName ,  index =
lane ,  value =
_G.setmetatable({ op =
"shared_load" ,  shared =
sourceName ,  index =
lane ,  type =
"u32" ,  source =
lower . site ( method ) }, scalarIR.SharedLoad) ,  source =

lower . site ( method ) }, scalarIR.SharedStore)
,
} ,  source =
lower . site ( stat ) }, scalarIR.Phase)

end
elseif method ~= nil and phaseMethod == "run" then
local args = ( method ) . args ~= nil
and ( ( ( ( method ) . args ) . exprs or { } ) )
or { }
if # args ~= 1 or args [ 1 ] . kind ~= "funcExpr" then
context . reject ( lower . site ( method ) , "phases:run takes one immediate function" )
end
local callback = ( args [ 1 ] ) . body
local params = callback ~= nil and ( callback ) . params or { }
if callback == nil or # params ~= 1 or ( params [ 1 ] ) . name == nil then
context . reject ( lower . site ( args [ 1 ] ) , "a phase callback takes exactly one localIndex parameter" )
end
local localName = ( ( params [ 1 ] ) . name ) . text
local inner = inherit ( environment )
inner [
localName
] = _G.setmetatable({ op =  "local_index" ,  type =  "u32" ,  source =  lower . site ( params [ 1 ] ) }, scalarIR.WorkgroupIndex)
local previousPhase , previousLocal = kernel . inPhase , kernel . localIndexName
kernel . inPhase = true
kernel . localIndexName = localName
local callbackBlock = ( callback ) . body
local lowered = lower . block (
callbackBlock ~= nil and ( callbackBlock ) . stats or { } ,
inner ,
kernel
)
kernel . inPhase = previousPhase
kernel . localIndexName = previousLocal
if # lowered == 0 then
context . reject ( lower . site ( args [ 1 ] ) , "a workgroup phase may not be empty" )
end
if sharedPhaseCollision ( lowered ) ~= nil then
context . reject ( lower . site ( args [ 1 ] ) , "a phase cannot read another lane from scratch it also writes" )
end
out [ # out + 1 ] = _G.setmetatable({ op =  "phase" ,  body =  lowered ,  source =  lower . site ( stat ) }, scalarIR.Phase)
else
local effect = lower . expression ( statement . expr , environment , kernel . index , kernel )
if effect . type ~= "lua_effect"
or tostring ( effect . op ) : match ( "^lua_builder_" ) == nil
and effect . op ~= "lua_scratch_u32_set"
and effect . op ~= "lua_scratch_u8_set"
and effect . op ~= "lua_scratch_u8_set4"
and effect . op ~= "simd_store"
and effect . op ~= "simd_field_store"
and effect . op ~= "reducer_add"
and effect . op ~= "simd_reducer_add"
and effect . op ~= "lua_scratch_u8_reset" then
context . reject ( lower . site ( stat ) , "native element stores use output[index] = value" )
end
out [ # out + 1 ] = effect
end
elseif kind == "assignStmt" then
assignStmt ( stat , out , environment , kernel )
elseif kind == "compoundAssign" then
local assignment = stat
if not soaStore (
assignment . target ,
assignment . value ,
out ,
environment ,
kernel ,
assignment . op
) then
context . reject ( lower . site ( stat ) , "native compound assignment requires an indexed SoA scalar field" )
end
elseif kind == "ifStmt" then
local branch = stat
local clauses = { }
local setups = { }



local decided = false
for _ , arm in ipairs ( branch . clauses or { } ) do
local bindingToken = arm . binding
if not decided and bindingToken ~= nil then




local bound = arm . cond
local boundIdentity = bound . kind == "call" and calledIdentity ( bound , kernel ) or nil
if boundIdentity ~= "nupp.simd.species" and boundIdentity ~= "nupp.simd.vectors" then
context . reject ( lower . site ( bound ) , "a native if binding takes simd.vectors only" )
end
if context . vectors or boundIdentity == "nupp.simd.species" then
local value = lower . expression ( bound , environment , kernel . index , kernel )
local inner = inherit ( environment )
local binding = bind ( ( bindingToken ) . text , value . type , nil , arm , inner , kernel )
noteBinding ( ( bindingToken ) . text , value , binding , kernel )
local body

= {
_G.setmetatable({ op =
"let" ,  name =
binding . name ,  uniqueName =
binding . uniqueName ,  type =
value . type ,  value =
value ,  source =
lower . site ( arm ) }, scalarIR.Let)
,
}
local block = arm . body
local stats = block ~= nil and ( block ) . stats or { }
for _ , lowered in ipairs ( lower . block ( stats , inner , kernel ) ) do
body [ # body + 1 ] = lowered
end
clauses [
# clauses + 1
] = _G.setmetatable({ condition =
_G.setmetatable({ op =
"bool" ,  value =
true ,  type =
"bool" ,  source =
lower . site ( arm ) }, scalarIR.Bool) ,  body =

body ,  source =
lower . site ( arm ) }, scalarIR.Clause)

decided = true
else
admitSpecies ( bound , kernel )
end
elseif not decided then
local condition , setup = lower . capture ( arm . cond , environment , kernel . index , kernel )
condition = booleanValue ( condition , kernel )
setups [ # clauses + 1 ] = setup
if condition . type ~= "bool" then
context . reject ( lower . site ( arm . cond ) , "native branch conditions must be boolean" )
end
local known = staticTruth ( condition )
if known ~= false then
local cursorBounds = cursorBound ( arm . cond , nil )
clauses [
# clauses + 1
] = _G.setmetatable({ condition =
condition ,  body =
nestedWithCursor ( arm . body , cursorBounds ) ,  cursorBounds =
cursorBounds ,  source =
lower . site ( arm ) }, scalarIR.Clause)

if known == true then
decided = true
end
end
end
end

local elseClause = branch . elseClause
local elseBody = not decided and elseClause ~= nil and nested ( ( elseClause ) . body ) or nil
if # clauses == 0 and elseBody ~= nil then



clauses [
1
] = _G.setmetatable({ condition =
_G.setmetatable({ op =  "bool" ,  value =  true ,  type =  "bool" ,  source =  lower . site ( stat ) }, scalarIR.Bool) ,  body =
elseBody ,  source =
lower . site ( stat ) }, scalarIR.Clause)

elseBody = nil
end
if # clauses > 0 then
local hasSetup = false
for _ , setup in pairs ( setups ) do
hasSetup = hasSetup or # setup > 0
end
if hasSetup then
local tail = elseBody
for position = # clauses , 1 , -1 do
local setup = setups [ position ] or { }
setup [
# setup + 1
] = _G.setmetatable({ op =
"if" ,  clauses =
{ clauses [ position ] } ,  elseBody =
tail ,  source =
lower . site ( stat ) }, scalarIR.If)

tail = setup
end
for _ , statement in ipairs ( tail or { } ) do
out [ # out + 1 ] = statement
end
else
out [
# out + 1
] = _G.setmetatable({ op =  "if" ,  clauses =  clauses ,  elseBody =  elseBody ,  source =  lower . site ( stat ) }, scalarIR.If)
end
end
elseif kind == "fornumStmt" then


local loop = stat
if loop . step ~= nil then
context . reject ( lower . site ( stat ) , "a native nested for loop takes no explicit step" )
end

local function bound ( node ) 



local value , setup = lower . capture ( node , environment , kernel . index , kernel )
for _ , statement in ipairs ( setup ) do
out [ # out + 1 ] = statement
end

value = forBound ( value , kernel . gpuTarget and node or stat , kernel )


if not kernel . gpuTarget and ( value . op == "constant_i32" or value . op == "span_count" ) then
return value
end

return temporary ( value , kernel , out )
end

local from = bound ( loop . start )
local to = bound ( loop . stop )
if loop . var == nil then
context . reject ( lower . site ( stat ) , "a native for loop needs an induction variable" )
end

local inner = inherit ( environment )



local reassigned = assignedNames ( loop . body , { } )
local counterType = from . type == "i32"
and to . type == "i32"
and ( kernel . gpuTarget or reassigned [ ( loop . var ) . text ] ~= true )
and "i32"
or "f64"
local binding = bind ( ( loop . var ) . text , counterType , nil , stat , inner , kernel )
local bounding = from . op == "constant_i32"
and ( tonumber ( ( from ) . value ) or 0 ) >= 1
and to . op == "span_count"
and ( to ) . span
or nil



local previousIndex , previousUniqueName = kernel . index , kernel . indexUniqueName
local previousAssigned = kernel . indexAssigned
local previousBound , previousMapEntry = kernel . boundSpan , kernel . mapEntry
kernel . index = binding . name
kernel . indexUniqueName = binding . uniqueName
kernel . indexAssigned = reassigned [ binding . name ] == true
kernel . boundSpan = bounding
kernel . mapEntry = false
local previousBounds = kernel . cursorBounds
local loopBounds = { }
for name , spans in pairs ( previousBounds ) do
if reassigned [ name ] ~= true then
loopBounds [ name ] = spans
end
end
kernel . cursorBounds = loopBounds
local loopBody = lower . block ( loop . body ~= nil and ( loop . body ) . stats or { } , inner , kernel )
for name in pairs ( previousBounds ) do
if loopBounds [ name ] == nil then
previousBounds [ name ] = nil
end
end
kernel . cursorBounds = previousBounds
kernel . index = previousIndex
kernel . indexUniqueName = previousUniqueName
kernel . indexAssigned = previousAssigned
kernel . boundSpan = previousBound
kernel . mapEntry = previousMapEntry
out [
# out + 1
] = _G.setmetatable({ op =
"fornum" ,  binding =
binding ,  from =
from ,  to =
to ,  body =
loopBody ,  carried =
{ } ,  boundSpan =
bounding ,  source =
lower . site ( stat ) }, scalarIR.Fornum)

elseif kind == "whileStmt" then






local loop = stat
local condition , conditionBody = lower . capture ( loop . cond , environment , kernel . index , kernel )
condition = booleanValue ( condition , kernel )
if condition . type ~= "bool" then
context . reject ( lower . site ( loop . cond ) , "native loop conditions must be boolean" )
end
local cursorBounds = cursorBound ( loop . cond , nil )
out [
# out + 1
] = _G.setmetatable({ op =
"while" ,  condition =
condition ,  conditionBody =
# conditionBody > 0 and conditionBody or nil ,  body =
nestedWithCursor ( loop . body , cursorBounds , true ) ,  carried =
{ } ,  cursorBounds =
cursorBounds ,  source =
lower . site ( stat ) }, scalarIR.While)

elseif kind == "repeatStmt" then


local loop = stat
local inner = inherit ( environment )
local body = loop . body
local lowered = lower . block ( body ~= nil and ( body ) . stats or { } , inner , kernel )
local condition , conditionBody = lower . capture ( loop . cond , inner , kernel . index , kernel )
condition = booleanValue ( condition , kernel )
if condition . type ~= "bool" then
context . reject ( lower . site ( loop . cond ) , "native repeat conditions must be boolean" )
end
out [
# out + 1
] = _G.setmetatable({ op =
"repeat" ,  condition =
condition ,  conditionBody =
# conditionBody > 0 and conditionBody or nil ,  body =
lowered ,  carried =
{ } ,  source =
lower . site ( stat ) }, scalarIR.Repeat)

elseif kind == "doStmt" then



local previousDo = kernel . simdDo
kernel . nextReducerRegion = kernel . nextReducerRegion + 1
local scope = _G.setmetatable({ region =  kernel . nextReducerRegion ,  reducers =  { } ,  byName =  { } }, lower.ReducerDo)
kernel . simdDo = scope
local body = nested ( ( stat ) . body )
kernel . simdDo = previousDo
if # scope . reducers > 0 then
out [
# out + 1
] = _G.setmetatable({ op =
"reducer_region" ,  body =
body ,  reducers =
scope . reducers ,  source =
lower . site ( stat ) }, scalarIR.ReducerRegion)

else
out [ # out + 1 ] = _G.setmetatable({ op =  "block" ,  body =  body ,  source =  lower . site ( stat ) }, scalarIR.Block)
end
elseif kind == "forinStmt" then








local loop = stat
local names = loop . names or { }
local exprs = loop . exprs or { }
local call = # exprs == 1 and exprs [ 1 ] . kind == "methodCall" and exprs [ 1 ] or nil
local receiverName = call ~= nil and lower . nameOf ( call . obj ) or nil
local receiver = receiverName ~= nil and environment [ receiverName ] or nil
local speciesType = receiver ~= nil and receiver . kind == "local" and tostring ( receiver . type ) or ""
local methodName = call ~= nil and call . name ~= nil and ( call . name ) . text or nil
local arguments = call ~= nil and call . args ~= nil and ( ( call . args ) . exprs or { } ) or { }
local element , shape = speciesType : match ( "^simd_species_(.-)_(.+)$" )
if call == nil or element == nil or methodName ~= "over" or # arguments ~= 1 or # names ~= 2 then
context . reject ( lower . site ( stat ) , "a native for-in takes `for at, active in species:over(count)` only" )
end
local countNode = arguments [ 1 ]
kernel . usesSimd = true
local site = lower . site ( stat )
local maskType = ( "simd_mask_" .. tostring ( element ) .. "_" .. tostring ( shape ) )
local speciesValue = lower . expression (
( call ) . obj ,
environment ,
kernel . index ,
kernel
)
local count = lower . expression ( countNode , environment , kernel . index , kernel )
if count . op ~= "span_count" and count . op ~= "constant" and count . op ~= "constant_i32" then
count = temporary ( count , kernel , out )
end
kernel . serial = kernel . serial + 1
local cursorName = "over#" .. tostring ( kernel . serial )
local cursor = bind ( cursorName , "u32" , true , stat , environment , kernel )

local function cursorRead ( ) 
return ( _G.setmetatable({ op =
"local" ,  name =
cursorName ,  type =
"u32" ,  uniqueName =
cursor . uniqueName ,  mutable =
true ,  source =
site }, scalarIR.Name) )

end

local function lanes ( ) 
return ( _G.setmetatable({ op =
"simd_lanes_generic" ,  args =
{ speciesValue } ,  intrinsic =
"lanes" ,  type =
"u32" ,  source =
site }, scalarIR.Simd) )

end

local function u32 ( value ) 
return ( _G.setmetatable({ op =  "constant_i32" ,  value =  value ,  type =  "u32" ,  source =  site }, scalarIR.IntConstant) )
end

local function sum ( left , right ) 
return ( _G.setmetatable({ op =  "u32_add" ,  left =  left ,  right =  right ,  type =  "u32" ,  source =  site }, scalarIR.Fixed) )
end



local firstToken = cst . firstToken ( stat )

local function operator ( text ) 
local token = { }
for key , value in pairs ( firstToken ) do
token [ key ] = value
end
token . text = text
local node = { kind = "binop" , op = token }
( node ) [ 1 ] = token

return node
end

out [
# out + 1
] = _G.setmetatable({ op =
"let" ,  name =
cursorName ,  uniqueName =
cursor . uniqueName ,  type =
"u32" ,  value =
u32 ( "0" ) ,  source =
site }, scalarIR.Let)

local bounds = nil
local spanName = lower . dotCount ( countNode )
local counted = spanName ~= nil and kernel . params [ spanName ] or nil
if counted ~= nil and counted . region ~= nil then
local proved = { }
withBound ( proved , cursorName , spanName , simdbounds . room ( speciesType , 1 ) )
bounds = proved
end
local atName = ( names [ 1 ] ) . text
local activeName = ( names [ 2 ] ) . text
if environment [ atName ] ~= nil or environment [ activeName ] ~= nil then
context . reject ( site , "native locals may not shadow " .. atName )
end
environment [ atName ] = {
kind = "alias" ,
type = "u32" ,
build = function ( ) 
return sum ( cursorRead ( ) , u32 ( "1" ) )
end ,
}
local activeAlias = { kind = "alias" , type = maskType }
activeAlias . build = function ( ) 
local everyLane = _G.setmetatable({ op =
"simd_mask_splat" ,  args =
{ _G.setmetatable({ op =  "bool" ,  value =  true ,  type =  "bool" ,  source =  site }, scalarIR.Bool) } ,  intrinsic =
"mask" ,  type =
maskType ,  source =
site }, scalarIR.Simd)

kernel . allLaneMasks [ everyLane ] = true

return everyLane
end
environment [ activeName ] = activeAlias
local previousDo = kernel . simdDo
kernel . nextReducerRegion = kernel . nextReducerRegion + 1
local scope = _G.setmetatable({ region =  kernel . nextReducerRegion ,  reducers =  { } ,  byName =  { } }, lower.ReducerDo)
kernel . simdDo = scope
local region = { }
local full = binary ( operator ( "<=" ) , sum ( cursorRead ( ) , lanes ( ) ) , count , kernel )
local fullBody = nestedWithCursor ( loop . body , bounds , true )
fullBody [ # fullBody + 1 ] = assignValue ( cursorRead ( ) , sum ( cursorRead ( ) , lanes ( ) ) )
region [
# region + 1
] = _G.setmetatable({ op =
"while" ,  condition =
full ,  body =
fullBody ,  carried =
{ } ,  cursorBounds =
bounds ,  source =
site }, scalarIR.While)

activeAlias . build = function ( ) 
return ( _G.setmetatable({ op =
"simd_tail" ,  args =
{ lower . convert ( binary ( operator ( "-" ) , count , cursorRead ( ) , kernel ) , "u32" , site , context ) } ,  intrinsic =
"tail" ,  type =
maskType ,  source =
site }, scalarIR.Simd) )

end
local remaining = binary ( operator ( "<" ) , cursorRead ( ) , count , kernel )
region [ # region + 1 ] = guarded ( remaining , nested ( loop . body ) )
kernel . simdDo = previousDo
environment [ atName ] = nil
environment [ activeName ] = nil
if # scope . reducers > 0 then
out [
# out + 1
] = _G.setmetatable({ op =
"reducer_region" ,  body =
region ,  reducers =
scope . reducers ,  source =
site }, scalarIR.ReducerRegion)

else
for _ , statement in ipairs ( region ) do
out [ # out + 1 ] = statement
end
end
elseif kind == "breakStmt" then
out [ # out + 1 ] = _G.setmetatable({ op =  "break" ,  source =  lower . site ( stat ) }, scalarIR.Break)
elseif kind == "continueStmt" then
out [ # out + 1 ] = _G.setmetatable({ op =  "continue" ,  source =  lower . site ( stat ) }, scalarIR.Continue)
elseif kind == "returnStmt" then
local returned = stat
local exprs = returned . exprs or { }
if # exprs ~= # kernel . resultTypes then
context . reject ( lower . site ( stat ) , "native return count does not match the function result" )
end
local values = { }
for position , expression in ipairs ( exprs ) do
local returnedName = lower . nameOf ( expression )
local returnedBinding = returnedName ~= nil and environment [ returnedName ] or nil
if returnedBinding ~= nil and returnedBinding . type == "lua_string_buffer" then
values [
position
] = _G.setmetatable({ op =
"lua_string_buffer_finish" ,  buffer =
_G.setmetatable({ op =
"local" ,  name =
returnedBinding . name ,  uniqueName =
returnedBinding . uniqueName ,  type =
"lua_string_buffer" ,  source =
lower . site ( expression ) }, scalarIR.Name) ,  type =

"lua_string" ,  source =
lower . site ( expression ) }, scalarIR.LuaStringBufferFinish)

else
values [
position
] = lower . convert (
lower . expression ( expression , environment , kernel . index ~= "" and kernel . index or nil , kernel ) ,
kernel . resultTypes [ position ] ,
lower . site ( expression ) ,
context
)
end
end
out [ # out + 1 ] = _G.setmetatable({ op =  "return" ,  values =  values ,  source =  lower . site ( stat ) }, scalarIR.Return)
else
context . reject (
lower . site ( stat ) ,
"statement kind " .. tostring ( kind ) .. " is not admitted in the native loop"
)
end
if next ( expressionFrame . replacements ) ~= nil then
local function rewrite ( child ) 
local replacement = expressionFrame . replacements [ child ]
if replacement ~= nil then
return replacement
end
local copy = { }
for key , value in pairs ( child ) do
copy [ key ] = value
end
visit . expressionChildren ( copy , rewrite )

return copy
end

for position = firstStatement , # out do
local statement = out [ position ]
local captured = statement . op == "let" and expressionFrame . replacements [ statement . value ] or nil
if captured == nil or ( captured ) . uniqueName ~= ( statement ) . uniqueName then
visit . statementExpressions ( statement , rewrite )
end
end
end
kernel . expressionFrame = nil
if frame ~= nil and frame . yields > before then
local rest = { }
out [ # out + 1 ] = guarded ( negate ( frame . done ) , rest )
out = rest
kernel . pending = out
end
end
kernel . pending , kernel . expressionFrame = previous , parent

return root
end






function lower . dotCount ( node ) 
if node == nil or node . kind ~= "unop" then
return nil
end
local length = node
if length . op == nil or ( length . op ) . text ~= "#" then
return nil
end

return lower . nameOf ( length . operand )
end


lower.Signature = {} lower.Signature.__index = lower.Signature ;_G.nupp.__reflect.link(lower.Signature,__nuppT1[11],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00084","nupp.compiler.aot.scalar") })



























function lower . parameters (
raws ,
checkedSignature ,
declarations ,
layouts ,
context ,
useSignatureTypes ,
omitted
) 
local signature = _G.setmetatable({ params =  { } ,  byName =  { } ,  spans =  { } ,  writes =  { } ,  reads =  { } }, lower.Signature)
local reserved = { }
for _ , raw in ipairs ( raws ) do
if raw . name ~= nil then
reserved [ ( raw . name ) . text ] = true
end
end
for position , raw in ipairs ( raws ) do
if omitted ~= nil and omitted [ position ] == true then
goto continue
end
local name = raw . name ~= nil and ( raw . name ) . text or nil
if name == nil then
context . reject ( lower . site ( raw ) , "every kernel parameter must be named" )
end
if signature . byName [ name ] ~= nil then
context . reject ( lower . site ( raw ) , "duplicate kernel parameter " .. ( name ) )
end

local spelling = lower . compactType ( raw . type )
local resolved = useSignatureTypes == true and checkedSignature ~= nil and checkedSignature . params [ position ]
or checkedType ( raw . type , context )
local mode = context . checked and checkedSignature ~= nil and checkedSignature . paramModes [ position ]
or raw . modeTok ~= nil and ( raw . modeTok ) . text
or nil
local sourceType = context . checked and sourceSpelling ( resolved ) or spelling
local valueType = context . checked and semanticValueType ( resolved ) or lower . sourceValueType ( spelling )
local at = raw . type or raw
local rowType , writable = soaElement ( resolved )
if rowType ~= nil then
if not context . nativeCpu then
context . reject ( lower . site ( raw ) , "SoA row-view parameters are supported only by native CPU AOT" )
end
if mode ~= ( writable and "exclusive" or "borrows" ) then
context . reject (
lower . site ( raw ) ,
"a native SoA view must be declared " .. ( writable and "exclusive" or "borrows" )
)
end
local _ , origin = nominal ( rowType )
if origin == nil or origin . declKind ~= "struct" then
context . reject ( lower . site ( raw ) , "native SoA rows require a scalar-field struct layout" )
end
local layout = lower . layout ( origin . name , rowType , at , declarations , layouts , context )
for _ , entry in ipairs ( ( declarations [ layout . name ] ) . entries ) do
if entry . kind == "fieldDecl" and ( entry ) . bitWidth ~= nil then
context . reject ( lower . site ( entry ) , "native SoA columns cannot contain bitfields" )
end
end
for ordinal , field in ipairs ( layout . fields ) do
if tostring ( field . type ) : match ( "^simd_" ) ~= nil then


context . reject (
lower . site ( raw ) ,
"native SoA columns cannot hold a vector field (" .. field . name .. "); use a span of the struct"
)
end
local columnName = name
if ordinal > 1 then
columnName = "__nuppSoa_" .. tostring ( position ) .. "_" .. tostring ( ordinal )
while reserved [ columnName ] do
columnName = columnName .. "_"
end
reserved [ columnName ] = true
end
local param = _G.setmetatable({ kind =
writable and "write_span" or "read_span" ,  name =
columnName ,  type =
field . type ,  sourceType =
field . sourceType ,  spanModule =
"nupp.mem.soa" ,  soa =
_G.setmetatable({ view =
name ,  sourceType =
spelling ,  layout =
layout . name ,  field =
field . name ,  ordinal =
ordinal }, scalarIR.SoaColumn) ,  region =

"r" .. tostring ( # signature . spans ) ,  access =
writable and "readwrite" or "read" ,  ownership =
writable and "exclusive" or "shared" ,  element =
_G.setmetatable({ kind =
"scalar" ,  type =
field . type ,  sourceType =
field . sourceType ,  spanModule =
"nupp.mem.soa" }, lower.Element) ,  source =

lower . site ( raw ) }, scalarIR.Param)

signature . params [ # signature . params + 1 ] = param
signature . byName [ columnName ] = param
signature . spans [ # signature . spans + 1 ] = param
if writable then
signature . writes [ # signature . writes + 1 ] = param
else
signature . reads [ # signature . reads + 1 ] = param
end
end
goto continue
end
local writeElement = lower . spanElement ( spelling , resolved , "WriteSpan" , at , declarations , layouts , context )
local readElement = lower . spanElement ( spelling , resolved , "Span" , at , declarations , layouts , context )
if writeElement ~= nil
and tostring ( ( writeElement ) . type ) : match ( "^simd_" ) ~= nil
or readElement ~= nil
and tostring ( ( readElement ) . type ) : match ( "^simd_" ) ~= nil then
context . reject ( lower . site ( raw ) , "explicit SIMD values cannot be stored in an AOT entry span" )
end
local region = "r" .. tostring ( # signature . spans )

local param
if writeElement ~= nil then
if mode ~= "exclusive" then
context . reject ( lower . site ( raw ) , "a writable native span must be declared exclusive" )
end
param = _G.setmetatable({ kind =
"write_span" ,  name =
name ,  type =
( writeElement ) . type ,  sourceType =
( writeElement ) . sourceType ,  spanModule =
( writeElement ) . spanModule ,  region =
region ,  access =
"readwrite" ,  ownership =
"exclusive" ,  source =
lower . site ( raw ) }, scalarIR.Param)

param . element = writeElement
signature . writes [ # signature . writes + 1 ] = param
signature . spans [ # signature . spans + 1 ] = param
elseif readElement ~= nil then
if mode ~= "borrows" then
context . reject ( lower . site ( raw ) , "a readable native span must be declared borrows" )
end
param = _G.setmetatable({ kind =
"read_span" ,  name =
name ,  type =
( readElement ) . type ,  sourceType =
( readElement ) . sourceType ,  spanModule =
( readElement ) . spanModule ,  region =
region ,  access =
"read" ,  ownership =
"shared" ,  source =
lower . site ( raw ) }, scalarIR.Param)

param . element = readElement
signature . reads [ # signature . reads + 1 ] = param
signature . spans [ # signature . spans + 1 ] = param
elseif valueType == "f32" or valueType == "f64" then
if mode ~= nil and mode ~= "plain" then
context . reject ( lower . site ( raw ) , "a uniform float parameter has no ownership mode" )
end
param = _G.setmetatable({ kind =
"uniform" ,  name =
name ,  type =
valueType ,  sourceType =
sourceType ,  source =
lower . site ( raw ) }, scalarIR.Param)

elseif valueType == "u32" or valueType == "i32" or valueType == "u64" or valueType == "i64" then
if mode ~= nil and mode ~= "plain" then
context . reject ( lower . site ( raw ) , "a uniform integer parameter has no ownership mode" )
end
param = _G.setmetatable({ kind =
"uniform" ,  name =
name ,  type =
valueType ,  sourceType =
sourceType ,  source =
lower . site ( raw ) }, scalarIR.Param)

elseif valueType == "bool" then
if mode ~= nil and mode ~= "plain" then
context . reject ( lower . site ( raw ) , "a boolean parameter has no ownership mode" )
end
param = _G.setmetatable({ kind =
"uniform" ,  name =
name ,  type =
"bool" ,  sourceType =
sourceType ,  source =
lower . site ( raw ) }, scalarIR.Param)

elseif valueType == "lua_string" or valueType == "lua_bytes" then
if valueType == "lua_string" and mode ~= nil and mode ~= "plain" then
context . reject ( lower . site ( raw ) , "a string parameter has no ownership mode" )
elseif valueType == "lua_bytes" and mode ~= "borrows" then
context . reject ( lower . site ( raw ) , "a string-or-buffer parameter must be declared borrows" )
end
param = _G.setmetatable({ kind =
"scalar" ,  name =
name ,  type =
valueType ,  sourceType =
sourceType ,  source =
lower . site ( raw ) }, scalarIR.Param)

elseif valueType == "lua_value" then
if mode ~= nil and mode ~= "plain" then
context . reject ( lower . site ( raw ) , "an opaque Lua value parameter has no ownership mode" )
end
param = _G.setmetatable({ kind =
"scalar" ,  name =
name ,  type =
"lua_value" ,  sourceType =
sourceType ,  source =
lower . site ( raw ) }, scalarIR.Param)

elseif scalarIR . nativeOnlyType ( valueType ) then




if mode ~= nil and mode ~= "plain" then
context . reject ( lower . site ( raw ) , "a vector or mask parameter has no ownership mode" )
end
if not context . nativeCpu then
context . reject ( lower . site ( at ) , "a vector or mask parameter is admitted only by native CPU AOT" )
end
if scalarIR . aggregateLayout ( valueType ) ~= nil then
lower . aggregate ( resolved , at , layouts , context )
end
param = _G.setmetatable({ kind =
"uniform" ,  name =
name ,  type =
valueType ,  sourceType =
sourceType ,  source =
lower . site ( raw ) }, scalarIR.Param)

signature . nativeOnly = true
else
context . reject ( lower . site ( at ) , "parameter type " .. sourceType .. " is not admitted" )
param = _G.setmetatable({ kind =  "uniform" ,  name =  name ,  type =  "f64" }, scalarIR.Param)
end

signature . params [ # signature . params + 1 ] = param
signature . byName [ name ] = param
:: continue ::
end

return signature
end





function lower . regions ( spans ) 
local regions = { }
for position , param in ipairs ( spans ) do
regions [
position
] = _G.setmetatable({ id =
param . region ,  param =
param . name ,  access =
param . access ,  proof =
tostring ( param . ownership ) .. "_borrow" }, scalarIR.Region)

end

local facts = { }
for left = 1 , # spans do
for right = left + 1 , # spans do
local hasWrite = spans [ left ] . kind == "write_span" or spans [ right ] . kind == "write_span"
local siblings = scalarIR . sameSoaView ( spans [ left ] , spans [ right ] )
facts [
# facts + 1
] = _G.setmetatable({ relation =
( hasWrite or siblings ) and "disjoint" or "may_alias" ,  left =
spans [ left ] . region ,  right =
spans [ right ] . region ,  proof =
siblings and "soa_columns" or hasWrite and "exclusive_borrow" or "shared_borrows" }, scalarIR.AliasFact)

end
end

return regions , facts
end






local function inertGuardArgument ( node ) 
if node == nil then
return true
end
if node . kind == "paren" then
return inertGuardArgument ( ( node ) . expr )
end

return node . kind == "string"
or node . kind == "number"
or node . kind == "nilExpr"
or node . kind == "trueExpr"
or node . kind == "falseExpr"
end







function lower . guardForm ( stat ) 
if stat == nil then
return nil
end
local asserted = stat . kind == "callStmt" and ( stat ) . expr or nil
if asserted ~= nil and asserted . kind == "call" and ( asserted ) . aotGuardBuiltin == "assert" then
local args = ( asserted ) . args
local exprs = args ~= nil and args . kind == "args" and ( ( args ) . exprs or { } ) or { }
if # exprs < 1 or # exprs > 2 or exprs [ 1 ] == nil then
return nil
end

return ( _G.setmetatable({ cond =
exprs [ 1 ] ,  asserted =
true ,  discarded =
exprs [ 2 ] ~= nil and not inertGuardArgument ( exprs [ 2 ] ) and exprs [ 2 ] or nil }, lower.GuardForm) )

end
if stat . kind ~= "ifStmt" then
return nil
end

local branch = stat
if # ( branch . clauses or { } ) ~= 1 or branch . elseClause ~= nil then
return nil
end

local clause = ( branch . clauses ) [ 1 ]
local body = clause . body ~= nil and ( clause . body ) . stats or { }
local first = body [ 1 ]
local call = first ~= nil and first . kind == "callStmt" and ( first ) . expr or nil
if # body ~= 1
or call == nil
or call . kind ~= "call"
or ( call ) . aotGuardBuiltin ~= "error"
or clause . cond == nil
then
return nil
end

local args = ( call ) . args
local exprs = args ~= nil and args . kind == "args" and ( ( args ) . exprs or { } ) or { }
local discarded = nil
for _ , argument in ipairs ( exprs ) do
if not inertGuardArgument ( argument ) then
discarded = argument
do break end
end
end

return ( _G.setmetatable({ cond =  clause . cond ,  asserted =  false ,  discarded =  discarded }, lower.GuardForm) )
end


local function quoted ( node ) 
if node == nil then
return ""
end
local collapsed = cst . textOf ( node ) : gsub ( "%s+" , " " )

return ( collapsed : match ( "^%s*(.-)%s*$" ) or collapsed )
end


local function guardLiteral ( node ) 
if node == nil then
return nil
end
if node . kind == "unop" then
local unary = node
local operator = unary . op ~= nil and ( unary . op ) . text or ""
if operator ~= "-" then
return nil
end
local magnitude = guardLiteral ( unary . operand )
return magnitude ~= nil and - ( magnitude ) or nil
end
if node . kind ~= "number" then
return nil
end
local token = ( node ) . token
local text = token ~= nil and ( token ) . text or ""
if text : match ( "^%d[%d_]*$" ) == nil and text : match ( "^0[xX][%da-fA-F_]+$" ) == nil then
return nil
end
local value = tonumber ( ( text : gsub ( "_" , "" ) ) )
if value == nil or ( value ) > relations . MAX_OFFSET then
return nil
end

return ( value )
end






function lower . guardTerm ( node , signature ) 
if node == nil then
return nil , 0
end
if node . kind == "paren" then
return lower . guardTerm ( ( node ) . expr , signature )
end

local literal = guardLiteral ( node )
if literal ~= nil then
return relations . zero ( ) , literal
end
if node . kind == "name" then
local name = lower . nameOf ( node )
local param = name ~= nil and signature . byName [ name ] or nil
if param == nil or ( param ) . kind ~= "uniform" then
return nil , 0
end



local sourceType = ( param ) . sourceType
if sourceType ~= "integer" and sourceType ~= "int32" and sourceType ~= "uint32" then
return nil , 0
end

return relations . uniform ( name ) , 0
end

local counted = lower . dotCount ( node )
if counted ~= nil then
local param = signature . byName [ counted ]
if param == nil or ( param ) . region == nil then
return nil , 0
end

return relations . count ( counted ) , 0
end
if node . kind ~= "binop" then
return nil , 0
end

local operator = node
local text = operator . op ~= nil and ( operator . op ) . text or ""
if text ~= "+" and text ~= "-" and text ~= "*" then
return nil , 0
end

local leftTerm , leftConstant = lower . guardTerm ( operator . lhs , signature )
local rightTerm , rightConstant = lower . guardTerm ( operator . rhs , signature )
if leftTerm == nil or rightTerm == nil then
return nil , 0
end
if text == "*" then





local literalTerm , literal , scaled , scaledConstant = leftTerm , leftConstant , rightTerm , rightConstant
if ( literalTerm ) . kind ~= "zero" then
literalTerm , literal , scaled , scaledConstant = rightTerm , rightConstant , leftTerm , leftConstant
end
if ( literalTerm ) . kind ~= "zero" then
return nil , 0
end
local term = scaled
local factor = literal * ( term . factor or 1 )
if term . kind == "zero" then
return relations . zero ( ) , literal * scaledConstant
elseif term . kind ~= "count" or literal < 1 or factor > relations . MAX_OFFSET then
return nil , 0
else
return relations . scaledCount ( term . name , factor ) , literal * scaledConstant
end
end
local signed = text == "+" and rightConstant or - rightConstant
if ( rightTerm ) . kind == "zero" then
return leftTerm , leftConstant + signed
end
if ( leftTerm ) . kind == "zero" and text == "+" then
return rightTerm , leftConstant + rightConstant
end

return nil , 0
end


local NEGATED

= { [ "<=" ] = ">" , [ "<" ] = ">=" , [ ">=" ] = "<" , [ ">" ] = "<=" , [ "==" ] = "~=" , [ "~=" ] = "==" }






local function guardComparison (
node ,
polarity ,
signature ,
out
) 
local operator = node
local written = operator . op ~= nil and ( operator . op ) . text or ""
local text = polarity and written or NEGATED [ written ] or ""
if text == "" or text == "~=" then
return false
end

local leftTerm , leftConstant = lower . guardTerm ( operator . lhs , signature )
local rightTerm , rightConstant = lower . guardTerm ( operator . rhs , signature )
if leftTerm == nil or rightTerm == nil then
return false
end
local left , right = leftTerm , rightTerm
local source = lower . site ( node )
local forward = rightConstant - leftConstant
local backward = leftConstant - rightConstant
local firstOffset
local secondOffset = nil
if text == "<=" then
firstOffset = forward
elseif text == "<" then
firstOffset = forward - 1
elseif text == ">=" then
firstOffset = backward
left , right = right , left
elseif text == ">" then
firstOffset = backward - 1
left , right = right , left
elseif text == "==" then
firstOffset = forward
secondOffset = backward
else
return false
end
if firstOffset > relations . MAX_OFFSET or firstOffset < - relations . MAX_OFFSET then
return false
end
if secondOffset ~= nil
and ( ( secondOffset ) > relations . MAX_OFFSET or ( secondOffset ) < - relations . MAX_OFFSET )
then
return false
end
out [ # out + 1 ] = relations . relation ( left , right , firstOffset , source )
if secondOffset ~= nil then
out [ # out + 1 ] = relations . relation ( right , left , secondOffset , source )
end

return true
end






function lower . guardFacts (
node ,
polarity ,
signature ,
out
) 
if node == nil then
return node
end
if node . kind == "paren" then
return lower . guardFacts ( ( node ) . expr , polarity , signature , out )
end
if node . kind == "unop" then
local unary = node
if unary . op ~= nil and ( unary . op ) . text == "not" then
return lower . guardFacts ( unary . operand , not polarity , signature , out )
end

return node
end
if node . kind == "binop" then
local operator = node
local text = operator . op ~= nil and ( operator . op ) . text or ""




if text == ( polarity and "and" or "or" ) then
return lower . guardFacts ( operator . lhs , polarity , signature , out )
or lower . guardFacts ( operator . rhs , polarity , signature , out )
end
if NEGATED [ text ] ~= nil then
if guardComparison ( node , polarity , signature , out ) then
return nil
end

return node
end
end

return node
end



function lower . scaledRelation ( pool ) 
for _ , relation in ipairs ( pool ) do
if relation . left . factor ~= nil or relation . right . factor ~= nil then
return relation
end
end

return nil
end


lower.GuardReading = {} lower.GuardReading.__index = lower.GuardReading ;_G.nupp.__reflect.link(lower.GuardReading,__nuppT1[12],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00081","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0001","nupp.compiler.aot.scalar") })






















function lower . readGuards ( statements , upTo , signature ) 
local pool = { }
local committed = false
for position = 1 , upTo do
local form = lower . guardForm ( statements [ position ] )
if form == nil then
return ( _G.setmetatable({ relations =
{ } ,  reason =
"a guard must be `assert(...)` or `if ... then error(...) end`" ,  at =
lower . site ( statements [ position ] ) ,  committed =  false }, lower.GuardReading) )

end
committed = true
if ( form ) . discarded ~= nil then
local discarded = ( form ) . discarded
return ( _G.setmetatable({ relations =
{ } ,  reason =
"`" .. quoted (
discarded
) .. "` cannot be discarded from a guard; its message and level arguments must be literals" ,  at =
lower . site ( discarded ) ,  committed =
true }, lower.GuardReading) )

end
local failed = lower . guardFacts (
( form ) . cond ,
( form ) . asserted ,
signature ,
pool
)
if failed ~= nil then
return ( _G.setmetatable({ relations =
{ } ,  reason =
"`" .. quoted (
failed
)
.. "` cannot be read as a guard: a guard compares integer parameters, integer literals and span lengths, offset by a literal" ,  at =
lower . site ( failed ) ,  committed =
true }, lower.GuardReading) )

end
if # pool > relations . BUDGET then
return ( _G.setmetatable({ relations =
{ } ,  reason =
"a kernel's guards may state at most " .. tostring ( relations . BUDGET ) .. " relations" ,  at =
lower . site ( statements [ position ] ) ,  committed =
true }, lower.GuardReading) )

end
end

return ( _G.setmetatable({ relations =  relations . canonical ( pool ) ,  committed =  committed }, lower.GuardReading) )
end


function lower . guardTerms ( signature ) 
local terms = { relations . zero ( ) }
for _ , param in ipairs ( signature . params ) do
if param . region ~= nil then
terms [ # terms + 1 ] = relations . count ( param . name )
elseif param . kind == "uniform" then
terms [ # terms + 1 ] = relations . uniform ( param . name )
end
end

return terms
end


lower.LoopShape = {} lower.LoopShape.__index = lower.LoopShape ;_G.nupp.__reflect.link(lower.LoopShape,__nuppT1[13],{ })















local function annotatedStatement ( node ) 
while node ~= nil and node . kind == "pragmaStmt" do
node = ( node ) . stat
end

return node
end







function lower . loopShape ( loop , signature ) 
loop = annotatedStatement ( loop )
if loop == nil or loop . kind ~= "fornumStmt" then
return nil
end
local counted = loop
if counted . step ~= nil or counted . var == nil then
return nil
end

local index = ( counted . var ) . text
local startName = lower . nameOf ( counted . start )
local startLiteral = guardLiteral ( counted . start )
local stopName = lower . nameOf ( counted . stop )
local stopSpan = lower . dotCount ( counted . stop )
if startLiteral == 1 and stopSpan ~= nil then
local param = signature . byName [ stopSpan ]
if param == nil or ( param ) . region == nil then
return nil
end

return ( _G.setmetatable({ index =  index ,  stopSpan =  stopSpan }, lower.LoopShape) )
end
if startName == nil or stopName == nil then
return nil
end



local from = signature . byName [ startName ]
local to = signature . byName [ stopName ]
if from == nil
or to == nil
or ( from ) . kind ~= "uniform"
or ( to ) . kind ~= "uniform"
or ( from ) . sourceType ~= "integer"
or ( to ) . sourceType ~= "integer"
then
return nil
end

return ( _G.setmetatable({ index =  index ,  first =  startName ,  last =  stopName }, lower.LoopShape) )
end


lower.Obligation = {} lower.Obligation.__index = lower.Obligation ;_G.nupp.__reflect.link(lower.Obligation,__nuppT1[14],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00080","nupp.compiler.aot.scalar") })














function lower . loopObligations ( shape , primary ) 
local count = relations . count ( primary )
if shape . first == nil then
local span = shape . stopSpan
if span == primary then
return { }
end
local other = relations . count ( span )

return {
_G.setmetatable({ needed =  "#" .. span .. " <= #" .. primary ,  left =  other ,  right =  count ,  offset =  0 }, lower.Obligation) ,
_G.setmetatable({ needed =  "#" .. primary .. " <= #" .. span ,  left =  count ,  right =  other ,  offset =  0 }, lower.Obligation) ,
}
end

local first = relations . uniform ( shape . first )
local last = relations . uniform ( shape . last )

return {
_G.setmetatable({ needed =
"1 <= " .. tostring ( shape . first ) ,  left =
relations . zero ( ) ,  right =
first ,  offset =
- 1 }, lower.Obligation)
,
_G.setmetatable({ needed =
tostring ( shape . last ) .. " <= #" .. primary ,  left =
last ,  right =
count ,  offset =
0 }, lower.Obligation)
,
_G.setmetatable({ needed =
tostring ( shape . first ) .. " <= " .. tostring ( shape . last ) .. " + 1" ,  left =
first ,  right =
last ,  offset =
1 }, lower.Obligation)
,
}
end










lower.MapAdmission = {} lower.MapAdmission.__index = lower.MapAdmission ;_G.nupp.__reflect.link(lower.MapAdmission,__nuppT1[15],{ __nuppT1[13] , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00081","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00087","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00082","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0001","nupp.compiler.aot.scalar") , __nuppT1[14] })































local function spanNames ( signature ) 
local names = { }
for _ , span in ipairs ( signature . spans ) do
names [ # names + 1 ] = span . name
end

return names
end

function lower . admitMap ( statements , signature ) 
local primary = signature . writes [ 1 ]
local shape = lower . loopShape ( statements [ # statements ] , signature )
if shape == nil then
return ( _G.setmetatable({ relations =
{ } ,  guards =
{ } ,  understood =
{ } ,  declined =
"a map kernel is a guard prefix and one counted loop over a span or a uniform range" ,  declinedAt =
lower . site ( statements [ # statements ] ) ,  committed =  false }, lower.MapAdmission) )

end

local reading = lower . readGuards ( statements , # statements - 1 , signature )
if reading . reason ~= nil then
return ( _G.setmetatable({ relations =
{ } ,  guards =
{ } ,  understood =
{ } ,  declined =
reading . reason ,  declinedAt =
reading . at ,  committed =
reading . committed }, lower.MapAdmission) )

end

local closure = relations . solve (
relations . withSoaCounts ( reading . relations , signature . params ) ,
spanNames ( signature ) ,
lower . guardTerms ( signature )
)
if closure . contradiction ~= nil then


return ( _G.setmetatable({ relations =
{ } ,  guards =
{ } ,  understood =
reading . relations ,  declined =
"these guards cannot all hold at once, so nothing follows from them" ,  declinedAt =
lower . site ( statements [ 1 ] ) ,  committed =
reading . committed }, lower.MapAdmission) )

end

local loop = shape
for _ , obligation in ipairs ( lower . loopObligations ( loop , primary . name ) ) do
if relations . proves ( closure , obligation . left , obligation . right , obligation . offset ) == nil then
if loop . first == nil then



return ( _G.setmetatable({ relations =
{ } ,  guards =
{ } ,  understood =
reading . relations ,  declined =
"the loop does not run over the primary output's length" ,  declinedAt =
lower . site ( statements [ # statements ] ) ,  committed =
reading . committed }, lower.MapAdmission) )

end

return ( _G.setmetatable({ relations =
reading . relations ,  guards =
{ } ,  understood =
reading . relations ,  unproved =
obligation ,  committed =  false }, lower.MapAdmission) )

end
end






local guards = { }
for _ , span in ipairs ( signature . spans ) do
if span . name ~= primary . name and relations . equalCounts ( closure , primary . name , span . name ) then
local proof = relations . proves ( closure , relations . count ( span . name ) , relations . count ( primary . name ) , 0 )
local contributing = proof ~= nil and proof or { }
guards [
# guards + 1
] = _G.setmetatable({ op =
"equal_count" ,  left =
primary . name ,  right =
span . name ,  source =
# contributing > 0 and contributing [ 1 ] . source or nil }, scalarIR.Guard)

end
end

local rangeGuard = nil
if loop . first ~= nil then
rangeGuard = _G.setmetatable({ first =
loop . first ,  last =
loop . last ,  count =
primary . name ,  source =
lower . site ( statements [ # statements ] ) }, scalarIR.RangeGuard)

end

return ( _G.setmetatable({ shape =
shape ,  relations =
reading . relations ,  guards =
guards ,  rangeGuard =
rangeGuard ,  understood =
reading . relations ,  committed =  false }, lower.MapAdmission) )

end





function lower . unprovedMessage ( admission ) 
local understood = { }
for _ , relation in ipairs ( admission . understood ) do
local at = relation . source
understood [
# understood + 1
] = "`" .. relations . text (
relation
) .. "`" .. (
at ~= nil
and (
" (" .. tostring ( ( at ) . line ) .. ":" .. tostring ( ( at ) . column ) .. ")"
)
or ""
)
end

return "the loop range is not proved: needed `" .. (
admission . unproved
) . needed .. "`, understood " .. ( # understood > 0 and table . concat ( understood , ", " ) or "nothing" )
end






lower.Application = {} lower.Application.__index = lower.Application ;_G.nupp.__reflect.link(lower.Application,__nuppT1[16],{ _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00032","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00033","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00034","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00071","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00041","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00029","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00035","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00021","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00082","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0002","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00065","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00024","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00070","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00030","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00049","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00083","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00044","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00045","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0001","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00028","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00059","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00062","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00025","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00053","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00090","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00013","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00064","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00011","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00010","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0003","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00063","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00031","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000115","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0005","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00056","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00075","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00039","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00077","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00076","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00015","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00014","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00080","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00017","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00048","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00018","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00046","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00023","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0009","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0008","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00040","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00042","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00084","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00079","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00022","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00019","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00020","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00043","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00066","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0004","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00050","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00072","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00060","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00054","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00051","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00085","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00047","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00058","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00073","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00037","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00016","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00026","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00068","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00069","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00067","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00061","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00078","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00052","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00087","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00088","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00089","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00086","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00074","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000105","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000117","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000110","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00092","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00091","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000106","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000107","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000114","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00093","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00095","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00099","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000112","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000111","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00096","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000108","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000103","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000104","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00098","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000116","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000118","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000109","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00055","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000100","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000101","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000102","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00097","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\000113","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00094","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00036","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00081","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00057","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00038","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00012","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0007","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\0006","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00027","nupp.compiler.syntax.cst") })















lower.Specialization = {} lower.Specialization.__index = lower.Specialization ;_G.nupp.__reflect.link(lower.Specialization,__nuppT1[17],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00044","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00043","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00036","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0005","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0002","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00042","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00041","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00034","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00035","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00039","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00040","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00045","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0004","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0003","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00033","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00030","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00063","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00018","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00025","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00027","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00026","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00024","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00010","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00017","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0006","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00019","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00020","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00021","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00064","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00022","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00023","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00065","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0008","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00014","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00015","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00012","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\0009","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00011","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00013","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00038","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00028","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00048","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00047","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00052","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00032","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00046","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00029","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00037","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00049","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00031","nupp.compiler.aot.scalar") })







lower.Declarations = {} lower.Declarations.__index = lower.Declarations ;_G.nupp.__reflect.link(lower.Declarations,__nuppT1[18],{ __nuppT1[16] , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00019","nupp.compiler.syntax.cst") , _G.nupp.__reflect.reference("nupp.compiler.syntax.cst\0runtime\00037","nupp.compiler.syntax.cst") })


























function lower . scan ( chunk , checked ) 
local found = _G.setmetatable({ applications =
{ } ,  helpers =
{ } ,  entries =
{ } ,  structs =
{ } ,  modules =
{ table = "@prelude.table" , string = "@prelude.string" } ,  intrinsicAliases =
{ } ,  constantNumbers =
{ } }, lower.Declarations)

for _ , block in ipairs ( chunk . blocks or { } ) do
for _ , stat in ipairs ( ( block ) . stats or { } ) do
if stat . kind == "localStmt" then
local declaration = stat
local names , exprs = declaration . names or { } , declaration . exprs or { }
for _ , declared in ipairs ( names ) do
if declared . text == "table" then
found . modules . table = "@shadowed.table"
elseif declared . text == "string" then
found . modules . string = "@shadowed.string"
end
end
if # names == 1 and # exprs == 1 and exprs [ 1 ] . kind == "call" then
local required = ( exprs [ 1 ] ) . requiredModule
local called = exprs [ 1 ]
if required == nil and lower . nameOf ( called . obj ) == "require" and called . args ~= nil then
local arguments = ( called . args ) . exprs or { }
local literal = # arguments == 1
and arguments [ 1 ] . kind == "string"
and ( arguments [ 1 ] ) . token
or nil
local written = literal ~= nil and ( literal ) . text or ""
required = written : match ( "^\"(.*)\"$" ) or written : match ( "^'(.*)'$" )
end
if required ~= nil then
found . modules [ names [ 1 ] . text ] = required
end
end


if # names == 1 and # exprs == 1 and exprs [ 1 ] . kind == "dotIndex" then
local path = lower . dottedName ( exprs [ 1 ] )
if path ~= nil and ( path ) : match ( "^nupp%." ) ~= nil then
found . modules [ names [ 1 ] . text ] = path
end
end
if declaration . isConst and # names == 1 and # exprs == 1 and exprs [ 1 ] . kind == "number" then
local token = ( exprs [ 1 ] ) . token
if token ~= nil and tonumber ( ( token ) . text ) ~= nil then
found . constantNumbers [ names [ 1 ] . text ] = ( token ) . text
end
end
end
if stat . kind == "pragmaStmt" then
local chain = { }
local cursor = stat
while cursor ~= nil and cursor . kind == "pragmaStmt" do
chain [ # chain + 1 ] = cursor
cursor = ( cursor ) . stat
end

local isAot = false
for _ , link in ipairs ( chain ) do
if link . name ~= nil and ( link . name ) . text == "aot" then
isAot = true
end
end
if checked then




local decorated = cursor ~= nil and cursor . kind == "localFuncStmt" and ( cursor )
or nil
isAot = decorated ~= nil
and ( decorated ) . body ~= nil
and ( ( decorated ) . body ) . aotRequired == true
end
if isAot then
found . applications [
# found . applications + 1
] = _G.setmetatable({ chain =  chain ,  tail =  cursor ,  at =  stat }, lower.Application)
local named = cursor ~= nil and cursor . kind == "localFuncStmt" and ( cursor )
or nil
if named ~= nil and ( named ) . name ~= nil then
found . entries [ ( ( named ) . name ) . text ] = named
end
end
elseif stat . kind == "localFuncStmt" and ( stat ) . name ~= nil then
local declaration = stat
found . helpers [ ( declaration . name ) . text ] = declaration
elseif stat . kind == "recordDecl" then
local declaration = stat
if declaration . declKind == "struct" and declaration . name ~= nil then
found . structs [ ( declaration . name ) . text ] = declaration
end
end
end
end



for _ , block in ipairs ( chunk . blocks or { } ) do
for _ , stat in ipairs ( ( block ) . stats or { } ) do
if stat . kind == "localStmt" then
local declaration = stat
local names , exprs = declaration . names or { } , declaration . exprs or { }
if # names == 1 and # exprs == 1 and exprs [ 1 ] . kind == "dotIndex" then
local indexed = exprs [ 1 ]
local root = lower . nameOf ( indexed . obj )
local moduleName = root ~= nil and found . modules [ root ] or nil
if moduleName ~= nil and indexed . name ~= nil then
found . intrinsicAliases [ names [ 1 ] . text ] = moduleName .. "." .. indexed . name . text
end
end
end
end
end

return found
end


lower.Contract = {} lower.Contract.__index = lower.Contract ;_G.nupp.__reflect.link(lower.Contract,__nuppT1[19],{ })


















function lower . contract (
application ,
body ,
checked ,
context
) 
local relaxed = body . relaxedGuarantees
local contract = _G.setmetatable({ target =
body . aotTarget == "gpu" and "gpu" or "cpu" ,  fpContract =
relaxed ~= nil and relaxed [ "fp-contract" ] == true ,  fpTranscendentals =
relaxed ~= nil and relaxed [ "fp-transcendentals" ] == true }, lower.Contract)

if checked then
return contract
end

for _ , link in ipairs ( application . chain ) do
local written = link . name ~= nil and ( link . name ) . text or nil
if written == "aot" then
for _ , argument in ipairs ( link . annotationArgs or { } ) do
local name = argument . name ~= nil and ( argument . name ) . text or nil
if name ~= "target" then
context . reject ( lower . site ( link ) , "@aot takes target = \"cpu\", target = \"gpu\", or nothing" )
end

local value = argument . expr
if name == "target" then
local token = value ~= nil and cst . firstToken ( value ) or nil
local requested = token ~= nil and ( token ) . text or ""
if requested == "\"gpu\"" or requested == "'gpu'" then
contract . target = "gpu"
elseif requested ~= "\"cpu\"" and requested ~= "'cpu'" then
context . reject ( lower . site ( argument ) , "@aot target must be \"cpu\" or \"gpu\"" )
end
end
end
elseif written == "relax" then
for _ , argument in ipairs ( link . annotationArgs or { } ) do
local token = argument . expr ~= nil and cst . firstToken ( argument . expr ) or nil
local text = token ~= nil and ( token ) . text or ""
if text : sub ( 1 , 1 ) == "\"" or text : sub ( 1 , 1 ) == "'" then
text = text : sub ( 2 , -2 )
end
if text == "fp-contract" then
contract . fpContract = true
elseif text == "fp-transcendentals" then
contract . fpTranscendentals = true
end
end
end
end

return contract
end


function lower . kernelBody (
application ,
context ,
specialization
) 
local fn = application . tail
if fn == nil or fn . kind ~= "localFuncStmt" then
context . reject ( lower . site ( fn or application . at ) , "@aot must decorate a local function with a visible body" )
end

local declaration = fn
local body = declaration . body
if body == nil
or body . generics ~= nil and specialization == nil
or body . varargParam ~= nil
or body . captureTakes ~= nil
or body . captureBorrows ~= nil
then
context . reject ( lower . site ( body or fn ) , "generic, variadic, and capturing kernels are not admitted" )
end

return declaration , body
end




local function loweringEnvironment ( signature , specialization ) 
local environment = { }
if specialization ~= nil then
for carrier , value in pairs ( ( specialization ) . values ) do
environment [ carrier ] = value
end
end
for position , param in ipairs ( signature . params ) do
if param . kind == "uniform" or param . kind == "scalar" then
if param . kind == "scalar" then
( param ) . uniqueName = tostring ( position )
else
param . uniqueName = "p_" .. param . name
end
environment [ param . name ] = specialization ~= nil
and ( specialization ) . values [ param . name ]
or param
end
end

return environment
end







local function newKernel (
signature ,
declarations ,
layouts ,
symbol ,
context ,
overrides
) 
local kernel = _G.setmetatable({ params =
signature . byName ,  layouts =
layouts ,  helperDecls =
declarations . helpers ,  entryDecls =
declarations . entries ,  helpers =
{ } ,  helperOrder =
{ } ,  constantNames =
{ } ,  scratchBounds =
{ } ,  constantOrder =
{ } ,  constantNumbers =
declarations . constantNumbers ,  helperState =
{ } ,  modules =
declarations . modules ,  intrinsicAliases =
declarations . intrinsicAliases ,  stringAccumulators =
{ } ,  reducers =
{ } ,  reducerOrder =
{ } ,  nextReducerRegion =
0 ,  symbol =
symbol ,  index =
"" ,  indexUniqueName =
"" ,  mapEntry =
false ,  resultTypes =
{ } ,  cursorBounds =
{ } ,  lengthBounds =
{ } ,  scratchLengthBounds =
{ } ,  usesSimd =
false ,  allLaneMasks =
{ } ,  usesLua =
false ,  serial =
0 ,  context =
context ,  reassignedNames =  {} ,  pending =  {} ,  indexAssigned =  false }, lower.Kernel)

for field , value in pairs ( overrides ) do
( kernel ) [ field ] = value
end

return kernel
end




local function validateReducers ( kernel ) 
for _ , reducer in ipairs ( kernel . reducerOrder ) do
if reducer . region == nil and not reducer . contributed then
kernel . context . reject ( reducer . source , "a reducer must receive a contribution before finalization" )
end
if not reducer . finalized then
kernel . context . reject ( reducer . source , "a reducer is finalized exactly once after its contribution region" )
end
end
end






function lower . program (
declarations ,
application ,
checked ,
context ,
specialization
) 
local fn , body = lower . kernelBody ( application , context , specialization )
local contract = lower . contract ( application , body , checked , context )

local layouts = _G.setmetatable({ ordered =  { } ,  byName =  { } }, lower.Layouts)
local checkedSignature = context . checked
and ( specialization ~= nil and ( specialization ) . signature or body . signatureType )
or nil
if context . checked and checkedSignature == nil then
context . reject ( lower . site ( body ) , "the checker did not publish this AOT signature" )
end
local signature = lower . parameters (
( body . params or { } ) ,
checkedSignature ,
declarations . structs ,
layouts ,
context ,
specialization ~= nil ,
specialization ~= nil and ( specialization ) . omitted or nil
)
local hasSoa = false
for _ , param in ipairs ( signature . params ) do
if param . soa ~= nil then
hasSoa = true
end
end
if hasSoa and contract . target ~= "cpu" then
context . reject ( lower . site ( body ) , "SoA row-view parameters are supported only by native CPU AOT" )
end
local regions , aliasFacts = lower . regions ( signature . spans )
local sourceName = ( fn . name ) . text
local name = specialization ~= nil and ( specialization ) . name or sourceName
local symbol = scalarIR . privateSymbol ( name )

local resultTypes = { }
local resultSourceTypes = { }
local nativeOnly = signature . nativeOnly == true
local rets = body . rets or { }
local resolvedResults = checkedSignature ~= nil and checkedSignature . rets or nil
if # rets == 1
and (
context . checked and resolvedResults [ 1 ] ~= nil and semanticRaw ( resolvedResults [ 1 ] ) . tag == "nil"
or not context . checked and lower . compactType ( rets [ 1 ] ) == "nil"
)
then
rets = { }
end
for position , result in ipairs ( rets ) do
local resolved = context . checked and resolvedResults [ position ] or nil
local sourceType = context . checked and sourceSpelling ( resolved ) or lower . compactType ( result )
local resultType = context . checked and semanticValueType ( resolved , true ) or lower . helperValueType ( sourceType )
if not context . checked then
if resultType == nil and sourceType == "string" then
resultType = "lua_string"
elseif resultType == nil and sourceType == "any" then
resultType = "lua_value"
elseif resultType == nil and sourceType == "nil" then
resultType = "lua_nil"
elseif resultType == nil and ( sourceType : sub ( 1 , 1 ) == "{" or sourceType == "table" ) then
resultType = "lua_table"
end
end
if resultType == nil then
context . reject ( lower . site ( result ) , "AOT entry results are admitted scalar values or fresh tables" )
end
if scalarIR . nativeOnlyType ( resultType ) then
if not context . nativeCpu then
context . reject ( lower . site ( result ) , "a vector or mask result is admitted only by native CPU AOT" )
end
if scalarIR . aggregateLayout ( resultType ) ~= nil then
lower . aggregate ( resolved , result , layouts , context )
end
nativeOnly = true
elseif tostring ( resultType ) : match ( "^simd_" ) ~= nil then
context . reject ( lower . site ( result ) , "a species or a reducer cannot cross an AOT entry result ABI" )
end
resultTypes [ position ] = resultType
resultSourceTypes [ position ] = sourceType
end
if nativeOnly and contract . target == "gpu" then
context . reject ( lower . site ( body ) , "a vector or mask signature is admitted only by native CPU AOT" )
end

local statements = body . body ~= nil and ( body . body ) . stats or { }
local workgroupCall = nil
if contract . target == "gpu" and # statements >= 1 and statements [ # statements ] . kind == "callStmt" then
local expression = ( statements [ # statements ] ) . expr
if expression ~= nil and expression . kind == "call" then
local candidate = expression
local path = lower . dottedName ( candidate . obj )
local root = path ~= nil and ( path ) : match ( "^([^.]+)%.workgroups$" ) or nil
if root ~= nil and declarations . modules [ root ] == "nupp.gpu" then
workgroupCall = candidate
end
end
end

if workgroupCall ~= nil then
for index = 1 , # statements - 1 do
if statements [ index ] . kind ~= "localStmt" then
context . reject (
lower . site ( statements [ index ] ) ,
"only initialized scalar locals may precede gpu.workgroups"
)
end
end
if # resultTypes ~= 0 or # signature . writes == 0 then
context . reject ( lower . site ( body ) , "a GPU workgroup entry returns nil and takes a writable span" )
end
local args = ( workgroupCall ) . args ~= nil
and ( ( ( ( workgroupCall ) . args ) . exprs or { } ) )
or { }
if # args ~= 3 or args [ 3 ] . kind ~= "funcExpr" then
context . reject (
lower . site ( workgroupCall ) ,
"gpu.workgroups takes groups, a static size, and an immediate function"
)
end
local sizeToken = cst . firstToken ( args [ 2 ] )
local size = sizeToken ~= nil and tonumber ( ( sizeToken ) . text ) or nil
if size == nil or size ~= math . floor ( size ) or size < 1 or size > 256 then
context . reject ( lower . site ( args [ 2 ] ) , "GPU workgroup size must be an integer literal from 1 through 256" )
end
local controller = ( args [ 3 ] ) . body
local controllerParams = controller ~= nil and ( controller ) . params or { }
if controller == nil
or # controllerParams ~= 2
or ( controllerParams [ 1 ] ) . name == nil
or ( controllerParams [ 2 ] ) . name == nil
then
context . reject ( lower . site ( args [ 3 ] ) , "a workgroup controller takes groupIndex and phases" )
end
local groupName = ( ( controllerParams [ 1 ] ) . name ) . text
local phasesName = ( ( controllerParams [ 2 ] ) . name ) . text
local kernel = newKernel ( signature , declarations , layouts , symbol , context , {
gpuTarget = contract . target == "gpu" ,
reassignedNames = assignedNames ( body . body , { } ) ,
loopSource = lower . site ( workgroupCall ) ,
phasesName = phasesName ,
workgroupSize = size ,
shared = { } ,
sharedOrder = { } ,
} )
local environment = loweringEnvironment ( signature , specialization )
local prefix = { }
for index = 1 , # statements - 1 do
prefix [ index ] = statements [ index ]
end
local prelude = lower . block ( prefix , environment , kernel )
local groups = lower . expression ( args [ 1 ] , environment , nil , kernel )
if groups . op == "local" then
for index = # prelude , 1 , -1 do
local statement = prelude [ index ]
if statement . op == "let" and statement . uniqueName == ( groups ) . uniqueName then
groups = ( statement ) . value
do break end
end
end
end
if groups . type ~= "u32" then
context . reject ( lower . site ( args [ 1 ] ) , "GPU workgroup count must be uint32" )
end
local numerator = groups . op == "u32_div" and ( groups ) . left or nil
local divisor = groups . op == "u32_div" and ( groups ) . right or nil
while numerator ~= nil and ( numerator . op == "numeric_cast" or numerator . op == "int_to_f64" ) do
numerator = ( numerator ) . value
end
while divisor ~= nil and ( divisor . op == "numeric_cast" or divisor . op == "int_to_f64" ) do
divisor = ( divisor ) . value
end
local divisorValue = divisor ~= nil
and ( divisor . op == "constant" or divisor . op == "constant_i32" )
and tonumber ( ( divisor ) . value )
or nil
if numerator == nil or numerator . op ~= "span_count" or divisorValue ~= size then
context . reject ( lower . site ( args [ 1 ] ) , "GPU workgroup count must be u32.div(u32.wrap(#span), workgroupSize)" )
end
local dispatchSpan = ( numerator ) . span
local groupBinding = bind ( groupName , "u32" , nil , controllerParams [ 1 ] , environment , kernel )
local groupValue = _G.setmetatable({ op =
"workgroup_index" ,  type =
"u32" ,  source =
lower . site ( controllerParams [ 1 ] ) }, scalarIR.WorkgroupIndex)

local controllerBlock = ( controller ) . body
local controllerBody = lower . block (
controllerBlock ~= nil and ( controllerBlock ) . stats or { } ,
environment ,
kernel
)
local lowered

= {
_G.setmetatable({ op =
"let" ,  name =
groupName ,  uniqueName =
groupBinding . uniqueName ,  type =
"u32" ,  value =
groupValue ,  source =
lower . site ( controllerParams [ 1 ] ) }, scalarIR.Let)
,
}
for _ , statement in ipairs ( controllerBody ) do
lowered [ # lowered + 1 ] = statement
end
local phaseCount = 0

local function countPhases ( block ) 
for _ , statement in ipairs ( block ) do
if statement . op == "phase" then
phaseCount = phaseCount + 1
elseif statement . op == "if" then
for _ , clause in ipairs ( ( statement ) . clauses ) do
countPhases ( clause . body )
end
countPhases ( ( statement ) . elseBody or { } )
elseif statement . op == "fornum"
or statement . op == "while"
or statement . op == "repeat"
or statement . op == "block"
then
countPhases ( ( statement ) . body )
end
end
end

countPhases ( lowered )
if phaseCount == 0 then
context . reject ( lower . site ( args [ 3 ] ) , "a workgroup controller must run at least one phase" )
end
local scratchBytes = 0
for _ , shared in ipairs ( kernel . sharedOrder ) do
if shared . count ~= size then
context . reject (
shared . source ,
"workgroup scratch count must equal the workgroup size in the initial portable subset"
)
end
scratchBytes = scratchBytes + shared . count * 4
end
if scratchBytes > 16384 then
context . reject ( lower . site ( args [ 3 ] ) , "workgroup scratch exceeds the portable 16384-byte limit" )
end
if kernel . usesLua or kernel . usesSimd then
context . reject ( lower . site ( args [ 3 ] ) , "workgroup phases admit fixed-width scalar operations only" )
end

return carriedFacts . program (
_G.setmetatable({ version =
scalarIR . VERSION ,  name =
name ,  symbol =
symbol ,  entryMode =
"kernel" ,  executionTarget =
"gpu" ,  fpContract =
contract . fpContract ,  fpTranscendentals =
contract . fpTranscendentals ,  params =
signature . params ,  layouts =
layouts . ordered ,  regions =
regions ,  aliasFacts =
aliasFacts ,  guards =
{ } ,  helpers =
kernel . helperOrder ,  constants =
kernel . constantOrder ,  resultTypes =
{ } ,  resultSourceTypes =
{ } ,  usesSimd =
false ,  workgroup =
_G.setmetatable({ prelude =
prelude ,  groups =
groups ,  dispatchSpan =
dispatchSpan ,  size =
size ,  shared =
kernel . sharedOrder ,  statements =
lowered ,  source =
lower . site ( workgroupCall ) }, scalarIR.Workgroup) ,  source =

lower . site ( fn ) }, scalarIR.Program)

)
end










local candidate = # resultTypes == 0 and # signature . writes > 0 and # signature . reads > 0 and # statements > 0
local admission = candidate and lower . admitMap ( statements , signature )
or _G.setmetatable({ relations =
{ } ,  guards =
{ } ,  understood =
{ } ,  declined =
"a map kernel writes a span and reads one, and returns nothing" ,  declinedAt =
lower . site ( body ) ,  committed =  false }, lower.MapAdmission)

if admission . unproved ~= nil then
context . reject ( lower . site ( statements [ # statements ] ) , lower . unprovedMessage ( admission ) )
end
if admission . declined ~= nil and admission . committed then
context . reject ( admission . declinedAt , tostring ( admission . declined ) )
end
if contract . target == "gpu" then




for _ , relation in ipairs ( admission . relations ) do
if relation . left . kind ~= "count"
or relation . right . kind ~= "count"
or relation . left . factor ~= nil
or relation . right . factor ~= nil
then
context . reject (
relation . source ,
"a GPU kernel's guards may only relate span lengths, and nothing enforces `" .. relations . text (
relation
) .. "` on a dispatch"
)
end
end
end
local mapShape = admission . shape ~= nil

if not mapShape then



local guardCount = 0
while guardCount < # statements and lower . guardForm ( statements [ guardCount + 1 ] ) ~= nil do
guardCount = guardCount + 1
end
local reading = lower . readGuards ( statements , guardCount , signature )
if reading . reason ~= nil then
context . reject ( reading . at or lower . site ( body ) , reading . reason )
end
local closure = relations . solve (
relations . withSoaCounts ( reading . relations , signature . params ) ,
spanNames ( signature ) ,
lower . guardTerms ( signature )
)
if closure . contradiction ~= nil then
context . reject ( lower . site ( statements [ 1 ] ) , "these guards cannot all hold at once" )
end
local scaled = lower . scaledRelation ( reading . relations )
if scaled ~= nil and contract . target == "gpu" then
context . reject (
( scaled ) . source ,
"a GPU guard compares span lengths without a factor; the GPU binding checks counts alone"
)
end
local spanBounds = { }
for _ , from in ipairs ( signature . spans ) do
local proved = { }
for _ , to in ipairs ( signature . spans ) do
if relations . proves ( closure , relations . count ( from . name ) , relations . count ( to . name ) , 0 ) ~= nil then
proved [ to . name ] = true
end
end
spanBounds [ from . name ] = proved
end
local blockStatements = { }
for position = guardCount + 1 , # statements do
blockStatements [ # blockStatements + 1 ] = statements [ position ]
end
local kernel = newKernel ( signature , declarations , layouts , symbol , context , {
gpuTarget = contract . target == "gpu" ,
reassignedNames = assignedNames ( body . body , { } ) ,
stringAccumulators = lower . stringAccumulators ( statements ) ,
loopSource = lower . site ( body . body or body ) ,
resultTypes = resultTypes ,
usesLua = ( function ( ) 
for _ , resultType in ipairs ( resultTypes ) do
if resultType == "lua_table"
or resultType == "lua_string"
or resultType == "lua_nil"
or resultType == "lua_value"
then
return true
end
end

return false
end ) ( ) ,
} )
kernel . spanBounds = spanBounds
kernel . spanRooms = relations . transfers ( closure , spanNames ( signature ) )
local environment = loweringEnvironment ( signature , specialization )
local lowered = lower . block ( blockStatements , environment , kernel )
validateReducers ( kernel )
if # lowered == 0 then
context . reject ( lower . site ( body . body or body ) , "an AOT block body may not be empty" )
end

local entryMode = kernel . usesLua and "lua-builder" or "kernel"
if hasSoa and kernel . usesLua then
context . reject ( lower . site ( body ) , "SoA row-view parameters require a native kernel without Lua values" )
end
local blockProgram = _G.setmetatable({ version =
scalarIR . VERSION ,  name =
name ,  symbol =
symbol ,  entryMode =
entryMode ,  executionTarget =
contract . target ,  builderMode =
kernel . builderMode ,  runtimeAbi =
kernel . usesLua and "lua-5.1" or nil ,  registrar =
kernel . usesLua and symbol .. "_register" or nil ,  fpContract =
contract . fpContract ,  fpTranscendentals =
contract . fpTranscendentals ,  params =
signature . params ,  layouts =
layouts . ordered ,  regions =
regions ,  aliasFacts =
aliasFacts ,  relations =
reading . relations ,  guards =
{ } ,  helpers =
kernel . helperOrder ,  constants =
kernel . constantOrder ,  body =
lowered ,  resultTypes =
resultTypes ,  resultSourceTypes =
resultSourceTypes ,  usesSimd =
kernel . usesSimd or nativeOnly ,  nativeOnly =
nativeOnly or nil ,  source =
lower . site ( fn ) }, scalarIR.Program)





blockProgram . reusableScratch = visit . reusableScratch ( blockProgram )

return carriedFacts . program ( blockProgram )
end

local primary = signature . writes [ 1 ]

local guards = admission . guards
local rangeGuard = admission . rangeGuard
local loop = annotatedStatement ( statements [ # statements ] )
local index = ( admission . shape ) . index
local kernel = newKernel ( signature , declarations , layouts , symbol , context , {
gpuTarget = contract . target == "gpu" ,
reassignedNames = assignedNames ( body . body , { } ) ,
loopSource = lower . site ( loop ) ,
index = index ,
indexUniqueName = "i" ,
mapEntry = true ,
boundSpan = primary . name ,
indexSpans = ( function ( ) 
local provable = { [ primary . name ] = true }
for _ , guard in ipairs ( guards ) do
provable [ guard . right ] = true
end

return provable
end ) ( ) ,
} )

local environment = loweringEnvironment ( signature , specialization )

local counted = loop
local body_ = lower . block ( counted . body ~= nil and ( counted . body ) . stats or { } , environment , kernel )
if # body_ == 0 then
context . reject ( lower . site ( counted . body or loop ) , "the native loop body may not be empty" )
end






if kernel . usesLua then
context . reject (
kernel . luaSource or lower . site ( counted . body or loop ) ,
"a value only the VM can hold is not admitted in a counted native loop"
)
end

return carriedFacts . program (
_G.setmetatable({ version =
scalarIR . VERSION ,  name =
name ,  symbol =
symbol ,  entryMode =
"kernel" ,  executionTarget =
contract . target ,  fpContract =
contract . fpContract ,  fpTranscendentals =
contract . fpTranscendentals ,  params =
signature . params ,  layouts =
layouts . ordered ,  regions =
regions ,  aliasFacts =
aliasFacts ,  relations =
admission . relations ,  guards =
guards ,  rangeGuard =
rangeGuard ,  helpers =
kernel . helperOrder ,  constants =
kernel . constantOrder ,  resultTypes =
{ } ,  resultSourceTypes =
{ } ,  usesSimd =
kernel . usesSimd or nativeOnly ,  nativeOnly =
nativeOnly or nil ,  loop =
_G.setmetatable({ index =
index ,  first =
rangeGuard ~= nil and ( rangeGuard ) . first or 1 ,  last =
rangeGuard ~= nil and ( rangeGuard ) . last or primary . name ,  count =
primary . name ,  statements =
body_ ,  source =
lower . site ( loop ) }, scalarIR.Loop) ,  source =

lower . site ( fn ) }, scalarIR.Program)

)
end

local __nuppExportValue= lower ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.lower"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.lower"]=__nuppExports;return __nuppExports