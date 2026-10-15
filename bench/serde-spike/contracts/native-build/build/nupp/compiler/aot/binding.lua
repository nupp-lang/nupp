_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.binding\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.binding\0runtime\0002") };


























local relations = require ( "nupp.compiler.aot.relations" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )
local target = require ( "nupp.compiler.aot.target" )

local binding = __nuppNew(0,2)





binding . passRuntime = false


binding . SOURCE_TYPE = {
[ "f64" ] = "number" ,
[ "f32" ] = "float" ,
[ "i32" ] = "int32" ,
[ "u32" ] = "uint32" ,
[ "i64" ] = "int64" ,
[ "u64" ] = "uint64" ,
}


local function sourceType ( valueType , physicalType ) 
return physicalType or tostring ( binding . SOURCE_TYPE [ valueType ] )
end





local function pointerType ( param ) 
local layout = param . type : match ( "^struct:(.+)$" )
local element = layout or sourceType ( param . type , param . sourceType )
local prefix = param . kind == "read_span" and "const " or ""

return prefix .. tostring ( element ) .. "*"
end


binding . ABI_TYPE = {
[ "f64" ] = "number" ,
[ "f32" ] = "float" ,
[ "u32" ] = "uint32" ,
[ "i32" ] = "int32" ,
[ "i64" ] = "int64" ,
[ "u64" ] = "uint64" ,
[ "bool" ] = "boolean" ,
}


local function from ( library ) 
return library and ( "from" .. string . format ( "%q" , library ) ) or ""
end

local function resultName ( program ) 
return scalarIR . identifier ( "KsResult" , program . symbol )
end


function binding . resultStruct ( program ) 
local lines = { "cdef struct " .. ( scalarIR . identifier ( "KsResult" , program . symbol ) ) }
for position , resultType in ipairs ( program . resultTypes or { } ) do
lines [ # lines + 1 ] = "    v" .. tostring ( position ) .. ": " .. tostring ( binding . ABI_TYPE [ resultType ] or "int32" )
end
lines [ # lines + 1 ] = "end"

return lines
end


function binding . struct ( layout ) 
local lines = { "local struct " .. layout . name }
for _ , field in ipairs ( layout . fields ) do
lines [ # lines + 1 ] = "    " .. field . name .. ": " .. sourceType ( field . type , field . sourceType )
end
lines [ # lines + 1 ] = "end"

return lines
end






function binding . layoutReporters ( symbol , layout , library ) 
local prefix = "cdef function " .. symbol .. "_layout_" .. layout . name
local aligned = scalarIR . holdsStoredVector ( layout )
local lines = { prefix .. "_size(): uint64 " .. ( library and ( "from" .. string . format ( "%q" , library ) ) or "" ) }
if aligned then
lines [ # lines + 1 ] = prefix .. "_align(): uint64 " .. ( library and ( "from" .. string . format ( "%q" , library ) ) or "" )
end
for _ , field in ipairs ( layout . fields ) do
lines [ # lines + 1 ] = prefix .. "_offset_" .. field . name .. "(): uint64 " .. ( library and ( "from" .. string . format ( "%q" , library ) ) or "" )
lines [ # lines + 1 ] = prefix .. "_size_" .. field . name .. "(): uint64 " .. ( library and ( "from" .. string . format ( "%q" , library ) ) or "" )
if aligned then
lines [ # lines + 1 ] = prefix .. "_align_" .. field . name .. "(): uint64 " .. ( library and ( "from" .. string . format ( "%q" , library ) ) or "" )
end
end

return lines
end














function binding . layoutChecks ( symbol , layout ) 




local name = symbol .. "_" .. layout . name .. "Layout"
local reporter = symbol .. "_layout_" .. layout . name


local function agrees ( measured , reported , mismatch ) 
local raise = "error(\"native struct " .. mismatch .. " mismatch\", 0)"

return "if " .. measured .. " ~= " .. reported .. " then " .. raise .. " end"
end

local aligned = scalarIR . holdsStoredVector ( layout )
local lines = { "const " .. name .. " = layoutof(" .. layout . name .. ")" }
lines [ # lines + 1 ] = agrees ( name .. ".size" , reporter .. "_size()" , "layout size" )
if aligned then
lines [ # lines + 1 ] = agrees ( name .. ".alignment" , reporter .. "_align()" , "layout alignment" )
end
for position , field in ipairs ( layout . fields ) do
local at = name .. ".fields[" .. tostring ( position ) .. "]"
lines [ # lines + 1 ] = agrees ( at .. ".offset" , reporter .. "_offset_" .. field . name .. "()" , "field offset" )
lines [ # lines + 1 ] = agrees ( at .. ".size" , reporter .. "_size_" .. field . name .. "()" , "field size" )
if aligned then
lines [
# lines + 1
] = agrees ( at .. ".alignment" , reporter .. "_align_" .. field . name .. "()" , "field alignment" )
end
end

return lines
end






function binding . foreign ( program , library , symbol ) 
local params = { }
for _ , param in ipairs ( program . params ) do
if param . kind == "write_span" then
params [ # params + 1 ] = "exclusive " .. param . name .. ": " .. pointerType ( param )
elseif param . kind == "read_span" then
params [ # params + 1 ] = "borrows " .. param . name .. ": " .. pointerType ( param )
else
params [ # params + 1 ] = param . name .. ": " .. tostring ( binding . ABI_TYPE [ param . type ] or "int32" )
end
end
if scalarIR . independentCounts ( program ) then
for _ , param in ipairs ( program . params ) do
if ( param . kind == "write_span" or param . kind == "read_span" )
and ( param . soa == nil or param . soa . ordinal == 1 )
then
params [ # params + 1 ] = "count_" .. param . name .. ": uint64"
end
end
else
params [ # params + 1 ] = "count: uint64"
end

local resultTypes = program . resultTypes or { }


if # resultTypes > 1 then
params [ # params + 1 ] = "ks_result: " .. ( scalarIR . identifier ( "KsResult" , program . symbol ) ) .. "*"
end
local lines = { "cdef function " .. ( symbol or program . symbol ) .. "(" }
for position , param in ipairs ( params ) do
lines [ # lines + 1 ] = "    " .. param .. ( position < # params and "," or "" )
end
local result = ( # resultTypes == 0 or # resultTypes > 1 ) and ""
or ": " .. tostring ( binding . ABI_TYPE [ resultTypes [ 1 ] ] or "int32" )
lines [ # lines + 1 ] = ")" .. result .. " " .. ( library and ( "from" .. string . format ( "%q" , library ) ) or "" )

return lines
end


local function logical ( param ) 
if param . soa ~= nil then
return (
param . ownership == "exclusive" and "exclusive " or "borrows "
) .. param . soa . view .. ": " .. param . soa . sourceType
end
local element = param . type : match ( "^struct:(.+)$" ) or sourceType ( param . type , param . sourceType )

if param . kind == "write_span" then
return "exclusive " .. param . name .. ": " .. "span" .. ".WriteSpan<" .. tostring ( element ) .. ">"
elseif param . kind == "read_span" then
return "borrows " .. param . name .. ": " .. "span" .. ".Span<" .. tostring ( element ) .. ">"
elseif param . type == "lua_bytes" then




return "borrows " .. param . name .. ": " .. tostring ( param . sourceType )
else
return param . name .. ": " .. tostring ( param . sourceType )
end
end


local function termSource ( term ) 
if term . kind == "count" then
local count = "#" .. tostring ( term . name )

return term . factor ~= nil and tostring ( term . factor ) .. " * " .. count or count
else
return tostring ( term . name )
end
end






local function refusal ( relation ) 
local left , right = termSource ( relation . left ) , termSource ( relation . right )



local fromOrigin = relation . left . kind == "zero"
local toOrigin = relation . right . kind == "zero"
if fromOrigin then
return right .. " < " .. tostring ( - relation . offset )
elseif toOrigin then
return left .. " > " .. tostring ( relation . offset )
elseif relation . offset == 0 then
return left .. " > " .. right
elseif relation . offset > 0 then
return left .. " > " .. right .. " + " .. tostring ( relation . offset )
else
return left .. " > " .. right .. " - " .. tostring ( - relation . offset )
end
end










function binding . relations ( program ) 
local pool = program . relations or { }
local paired = { }
for _ , relation in ipairs ( pool ) do
if relation . offset == 0 and relation . left . kind == "count" and relation . right . kind == "count" then
paired [ relations . key ( relation . left ) .. "|" .. relations . key ( relation . right ) ] = true
end
end

local conditions = { }
local equalities = { }
for _ , relation in ipairs ( pool ) do
local leftKey , rightKey = relations . key ( relation . left ) , relations . key ( relation . right )
if paired [ rightKey .. "|" .. leftKey ] == true and paired [ leftKey .. "|" .. rightKey ] == true then


if leftKey < rightKey then
equalities [
# equalities + 1
] = "    if " .. termSource (
relation . left
) .. " ~= " .. termSource (
relation . right
) .. " then error(\"native spans have incompatible lengths\", 2) end"
end
else
conditions [ # conditions + 1 ] = refusal ( relation )
end
end

local lines = { }
if # conditions > 0 then
lines [ # lines + 1 ] = "    if " .. table . concat ( conditions , " or " ) .. " then"
lines [ # lines + 1 ] = "        error(\"native precondition failed\", 2)"
lines [ # lines + 1 ] = "    end"
end
for _ , line in ipairs ( equalities ) do
lines [ # lines + 1 ] = line
end

return lines
end



binding.TakenSpan = {} binding.TakenSpan.__index = binding.TakenSpan ;_G.nupp.__reflect.link(binding.TakenSpan,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00084","nupp.compiler.aot.scalar") })






const ELEMENT_BYTES

= {
[ "number" ] = 8 ,
[ "float" ] = 4 ,
[ "int8" ] = 1 ,
[ "uint8" ] = 1 ,
[ "int16" ] = 2 ,
[ "uint16" ] = 2 ,
[ "int32" ] = 4 ,
[ "uint32" ] = 4 ,
[ "int64" ] = 8 ,
[ "uint64" ] = 8 ,
}


local function elementBytes ( param , ffi ) 
local layout = param . type : match ( "^struct:(.+)$" )
if layout ~= nil then
return ffi .. ".sizeof(" .. ( layout ) .. ")"
end
local element = sourceType ( param . type , param . sourceType )
local bytes = ELEMENT_BYTES [ element ]
if bytes ~= nil then
return tostring ( bytes )
end

return ffi .. ".sizeof(" .. string . format ( "%q" , element ) .. ")"
end




local function needsDisjoint ( left , right ) 
return ( left . kind == "write_span" or right . kind == "write_span" ) and not scalarIR . sameSoaView ( left , right )
end


function binding . checksOverlap ( params ) 
for left = 1 , # params do
for right = left + 1 , # params do
if scalarIR . isSpan ( params [ left ] )
and scalarIR . isSpan ( params [ right ] )
and needsDisjoint ( params [ left ] , params [ right ] )
then
return true
end
end
end

return false
end


function binding . ffiLocal ( program ) 
return scalarIR . identifier ( "ks_ffi" , program . symbol )
end








function binding . overlapChecks ( spans , module ) 
local checks = { }




local function address ( span ) 
return "ffi.cast(\"uintptr_t\", " .. span . pointer .. ")"
end

local function limit ( span ) 
return address ( span ) .. " + " .. span . count .. " * " .. elementBytes ( span . param , "ffi" )
end

for left = 1 , # spans do
for right = left + 1 , # spans do
local a , b = spans [ left ] , spans [ right ]
if needsDisjoint ( a . param , b . param ) then
checks [ # checks + 1 ] = "        if " .. a . count .. " > 0 and " .. b . count .. " > 0"
checks [ # checks + 1 ] = "            and " .. address ( a ) .. " < " .. limit ( b )
checks [ # checks + 1 ] = "            and " .. address ( b ) .. " < " .. limit ( a )
checks [ # checks + 1 ] = "        then"
checks [ # checks + 1 ] = "            error(\"native spans overlap\", 2)"
checks [ # checks + 1 ] = "        end"
end
end
end
if # checks == 0 then
return { }
end
local lines = { "    do" , "        local ffi = " .. module }
for _ , line in ipairs ( checks ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = "    end"

return lines
end








function binding . spanArguments (
params ,
independent
) 
local lines = { }
local arguments = { }
local counts = { }
local taken = { }
local viewCounts = { }
local primary = nil
local reserved = { }
for _ , param in ipairs ( params ) do
reserved [ param . name ] = true
end

local function fresh ( name ) 
while reserved [ name ] do
name = name .. "_"
end
reserved [ name ] = true

return name
end

for _ , param in ipairs ( params ) do
if param . kind == "write_span" or param . kind == "read_span" then
local pointer = fresh ( "native_" .. param . name )
local count = fresh ( "native_" .. param . name .. "Count" )
local value = param . name
if param . soa ~= nil then
value = fresh ( "native_" .. param . name .. "Column" )
lines [
# lines + 1
] = "    local " .. value .. " = " .. param . soa . view .. "[" .. string . format (
"%q" ,
param . soa . field
) .. "]"
end
local hasCount = param . soa == nil or param . soa . ordinal == 1
lines [
# lines + 1
] = "    local " .. pointer .. ( hasCount and ", " .. count or "" ) .. " = " .. value .. ":ref()"
if primary == nil then
primary = count
end
arguments [ # arguments + 1 ] = pointer .. " as " .. pointerType ( param )
if hasCount then
counts [ # counts + 1 ] = count
if param . soa ~= nil then
viewCounts [ param . soa . view ] = count
end
end

local elements = hasCount and count or viewCounts [ ( param . soa ) . view ] or count
taken [ # taken + 1 ] = _G.setmetatable({ param =  param ,  pointer =  pointer ,  count =  elements }, binding.TakenSpan)
else
arguments [ # arguments + 1 ] = param . name
end
end

if independent then
for _ , count in ipairs ( counts ) do
arguments [ # arguments + 1 ] = count
end
else
arguments [ # arguments + 1 ] = tostring ( primary )
end

return lines , arguments , primary , taken
end


function binding . wrapper ( program , nativeSymbol ) 
local params = { }
for _ , param in ipairs ( program . params ) do
if param . soa == nil or param . soa . ordinal == 1 then
params [ # params + 1 ] = logical ( param )
end
end

local resultSourceTypes = program . resultSourceTypes or { }
local lines = { }
local ffi = binding . ffiLocal ( program )
if binding . checksOverlap ( program . params ) then
lines [ # lines + 1 ] = "local " .. ffi .. " = require(\"ffi\")"
end
local block = scalarIR . identifier ( "ks_result_block" , program . symbol )
if # resultSourceTypes > 1 then


lines [ # lines + 1 ] = "local " .. block .. " = new " .. ( scalarIR . identifier ( "KsResult" , program . symbol ) ) .. "()"
end
lines [ # lines + 1 ] = "local function " .. program . name .. "("
for position , param in ipairs ( params ) do
lines [ # lines + 1 ] = "    " .. param .. ( position < # params and "," or "" )
end
local result = # resultSourceTypes == 0 and "nil"
or # resultSourceTypes == 1 and resultSourceTypes [ 1 ]
or "(" .. table . concat ( resultSourceTypes , ", " ) .. ")"
lines [ # lines + 1 ] = "): " .. result
for _ , line in ipairs ( binding . relations ( program ) ) do
lines [ # lines + 1 ] = line
end

local independentCounts = scalarIR . independentCounts ( program )
local taken , arguments , _ , spans = binding . spanArguments ( program . params , independentCounts )
for _ , line in ipairs ( taken ) do
lines [ # lines + 1 ] = line
end
for _ , line in ipairs ( binding . overlapChecks ( spans , ffi ) ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = "    @unsafe do"
if # resultSourceTypes > 1 then
local withBlock = { }
for position , argument in ipairs ( arguments ) do
withBlock [ position ] = argument
end
withBlock [ # withBlock + 1 ] = block
lines [
# lines + 1
] = "        " .. ( nativeSymbol or program . symbol ) .. "(" .. table . concat ( withBlock , ", " ) .. ")"
local values = { }
for position , sourceType in ipairs ( resultSourceTypes ) do
local read = block .. ".v" .. tostring ( position )
if sourceType == "integer" then
read = read .. " as integer"
elseif sourceType == "float" then



read = "nupp.math.f32.narrow(" .. read .. ")"
end
values [ position ] = read
end
lines [ # lines + 1 ] = "        return " .. table . concat ( values , ", " )
else
local call = ( nativeSymbol or program . symbol ) .. "(" .. table . concat ( arguments , ", " ) .. ")"
if resultSourceTypes [ 1 ] == "integer" then
call = call .. " as integer"
elseif resultSourceTypes [ 1 ] == "float" then



call = "nupp.math.f32.narrow(" .. call .. ")"
end
lines [ # lines + 1 ] = "        " .. ( # resultSourceTypes == 0 and "" or "return " ) .. call
end
lines [ # lines + 1 ] = "    end"
lines [ # lines + 1 ] = "end"

return lines
end















local function builderType ( program ) 
local params = { }
for position , param in ipairs ( program . params ) do
params [ position ] = logical ( param )
end
local count = # ( program . resultSourceTypes or { } )
local results = { }
for position = 1 , count do
results [ position ] = "any"
end
local result = count == 0 and "nil" or count == 1 and "any" or "(" .. table . concat ( results , ", " ) .. ")"

return "function(" .. table . concat ( params , ", " ) .. "): " .. result
end







function binding . builderLoader (
program ,
library ,
tiers ,
detector
) 
local prefix = program . symbol .. "_builder"
if library == nil then



local key = tostring ( program . registrar )
return {
"local " .. prefix .. ": " .. builderType ( program ) ,
"do" ,
"    local modules: any = rawget(_G, \"__nuppAotBuilderModules\")" ,
"    local registered: any = modules and modules[" .. string . format ( "%q" , key ) .. "]" ,
"    if type(registered) ~= \"table\" then error(\"AOT builder archive is not registered: "
.. key
.. "\", 0) end" ,
"    " .. prefix .. " = registered[" .. string . format ( "%q" , program . name ) .. "]" ,
"    if type("
.. prefix
.. ") ~= \"function\" then error(\"AOT builder registration is malformed\", 0) end" ,
"end" ,
}
end
local relative = library : match ( "^@(.+)$" ) or library
local relativeSuffix = string . format ( "%q" , "/" .. relative )
local registrar = tostring ( program . registrar )


local lines = { "local " .. prefix .. ": " .. builderType ( program ) }




if tiers ~= nil and # tiers > 0 and detector == true then
for _ , line in ipairs ( binding . featureDetector ( library ) ) do
lines [ # lines + 1 ] = line
end
end
lines [ # lines + 1 ] = "do"
if tiers ~= nil and # tiers > 0 then
registrar = target . symbol ( registrar , tiers [ 1 ] )
lines [ # lines + 1 ] = "local " .. prefix .. "Registrar = \"" .. registrar .. "\""
for position = 2 , # tiers do
local tier = tiers [ position ]
lines [
# lines + 1
] = "if ks_aot_feature_tier() >= " .. tostring (
target . rank ( tier )
) .. " then " .. prefix .. "Registrar = \"" .. target . symbol ( tostring ( program . registrar ) , tier ) .. "\" end"
end
else
lines [ # lines + 1 ] = "local " .. prefix .. "Registrar = \"" .. registrar .. "\""
end
local loader = {
"local function " .. prefix .. "Load()" ,
"    local modules: any = rawget(_G, \"__nuppAotBuilderModules\") or {}" ,
"    rawset(_G, \"__nuppAotBuilderModules\", modules)" ,
"    local here = debug.getinfo(1, \"S\").source:match(\"^@(.*)$\")" ,
"    local directory = here and here:match(\"^(.*)[/\\\\]\") or \".\"" ,
"    local started = directory" ,
"    for _ = 0, 8 do" ,
"        local path = directory .. " .. relativeSuffix ,
"        local cacheKey = path .. \"\\0\" .. " .. prefix .. "Registrar" ,
"        local registered: any = modules[cacheKey]" ,
"        if registered then return registered[\"" .. program . name .. "\"] end" ,
"        local probe = io.open(path, \"rb\")" ,
"        if probe then" ,
"            probe:close()" ,
"            local loadlib = rawget(package, \"loadlib\")" ,
"            local open, why = loadlib(path, " .. prefix .. "Registrar)" ,
"            if not open then error(\"cannot register AOT builder: \" .. tostring(why), 0) end" ,
binding . passRuntime and "            registered = open((require(\"nupp.runtime.aotruntime\") as any).table())"
or "            registered = open()" ,
"            if type(registered) ~= \"table\" or type(registered[\""
.. program . name
.. "\"]) ~= \"function\" then error(\"malformed AOT builder registration\", 0) end" ,
"            modules[cacheKey] = registered" ,
"            return registered[\"" .. program . name .. "\"]" ,
"        end" ,
"        directory = directory .. \"/..\"" ,
"    end" ,
"    error(" .. string . format (
"%q" ,
"cannot find " .. relative .. " at or above "
) .. " .. started .. " .. string . format (
"%q" ,
"; the compiled library has to travel with the module that calls it"
) .. ", 0)" ,
"end" ,
prefix .. " = " .. prefix .. "Load()" ,
}
for _ , line in ipairs ( loader ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = "end"

return lines
end






local function established ( resultType , name ) 
if resultType == "uint32" then
return "nupp.math.u32.wrap(" .. name .. " as integer)"
elseif resultType == "int32" then
return "nupp.math.i32.wrap(" .. name .. " as integer)"
elseif resultType == "boolean" then
return name .. " as boolean"
elseif resultType == "float" then
return "nupp.math.f32.narrow(" .. name .. " as number)"
elseif resultType == "number" or resultType == "integer" then
return name .. " as " .. resultType
end

return name
end


function binding . builderWrapper ( program ) 
local params = { }
local arguments = { }
for position , param in ipairs ( program . params ) do
params [ position ] = logical ( param )
arguments [ position ] = param . name
end
local results = program . resultSourceTypes or { }
local result = # results == 0 and "nil" or # results == 1 and results [ 1 ] or "(" .. table . concat ( results , ", " ) .. ")"
local lines = { "local function " .. program . name .. "(" }
for position , param in ipairs ( params ) do
lines [ # lines + 1 ] = "    " .. param .. ( position < # params and "," or "" )
end
lines [ # lines + 1 ] = "): " .. result
local call = program . symbol .. "_builder(" .. table . concat ( arguments , ", " ) .. ")"
if # results == 0 then
lines [ # lines + 1 ] = "    " .. call
elseif # results == 1 then
local converted = established ( results [ 1 ] , "native1" )
if converted == "native1" then
lines [ # lines + 1 ] = "    return " .. call
else
lines [ # lines + 1 ] = "    local native1 = " .. call
lines [ # lines + 1 ] = "    return " .. converted
end
else
local names = { }
local values = { }
for position , resultType in ipairs ( results ) do
names [ position ] = "native" .. tostring ( position )
values [ position ] = established ( resultType , names [ position ] )
end
lines [ # lines + 1 ] = "    local " .. table . concat ( names , ", " ) .. " = " .. call
lines [ # lines + 1 ] = "    return " .. table . concat ( values , ", " )
end
lines [ # lines + 1 ] = "end"

return lines
end












function binding . compiledMarker ( program ) 
return {
"do" ,
"    local entries: any = rawget(_G, \"__nuppAotCompiled\")" ,
"    if entries == nil then" ,
"        entries = setmetatable({}, {__mode = \"k\"})" ,
"        rawset(_G, \"__nuppAotCompiled\", entries)" ,
"    end" ,
"    entries[" .. program . name .. "] = true" ,
"end" ,
}
end


function binding . featureDetector ( library ) 
return { "cdef function ks_aot_feature_tier(): int32 " .. ( library and ( "from" .. string . format ( "%q" , library ) ) or "" ) }
end


binding.Archive = {} binding.Archive.__index = binding.Archive ;_G.nupp.__reflect.link(binding.Archive,__nuppT1[2],{ })



























function binding . archiveProbe ( archive ) 
return {
"do" ,
"    local archiveFfi: any = require(\"ffi\")" ,
"    pcall(archiveFfi.cdef, \"uint64_t " .. archive . symbol .. "(void);\")" ,
"    local archiveLinked, archiveProbe = pcall(function(): any" ,
"        return archiveFfi.C." .. archive . symbol ,
"    end)" ,
"    if not archiveLinked then" ,
"        error(\"this module's AOT archive was not linked into the host: "
.. archive . symbol
.. " is not in the default C namespace\", 0)" ,
"    end" ,
"    if tonumber((archiveProbe as any)()) ~= " .. string . format ( "%d" , archive . fingerprint ) .. " then" ,
"        error(\"the linked AOT archive is not the one this module was compiled against\", 0)" ,
"    end" ,
"end" ,
}
end
















function binding . multiversion (
program ,
library ,
tiers ,
detector
) 
local lines = { }
local native = program . symbol .. "_native"




for _ , line in ipairs ( binding . foreign ( program , library , target . symbol ( program . symbol , tiers [ 1 ] ) ) ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = "local " .. native .. " = " .. target . symbol ( program . symbol , tiers [ 1 ] )
if # tiers > 1 then


if detector == true then
for _ , line in ipairs ( binding . featureDetector ( library ) ) do
lines [ # lines + 1 ] = line
end
end
lines [ # lines + 1 ] = "do"
for position = 2 , # tiers do
local symbol = target . symbol ( program . symbol , tiers [ position ] )
for _ , line in ipairs ( binding . foreign ( program , library , symbol ) ) do
lines [ # lines + 1 ] = "    " .. line
end
end
for position = 2 , # tiers do
local tier = tiers [ position ]
lines [
# lines + 1
] = "    if ks_aot_feature_tier() >= " .. tostring (
target . rank ( tier )
) .. " then " .. native .. " = " .. target . symbol ( program . symbol , tier ) .. " end"
end
lines [ # lines + 1 ] = "end"
end

return lines , native
end




function binding . numericForGuard ( program ) 
local mode = program . numericForRuntime
if mode ~= "luajit-single" and mode ~= "luajit-dual" then
return { }
end
if program . numericForRuntimeRequired ~= true then
return { }
end
local probe = program . symbol .. "_loop_runtime"
local expected = mode == "luajit-dual" and "true" or "false"

return {
"do" ,
"    local function " .. probe .. "(): boolean" ,
"        for cursor = -0.0, 0 do return 1 / cursor > 0 end" ,
"        return false" ,
"    end" ,
"    local loopVm: any = rawget(_G, \"jit\")" ,
"    if loopVm == nil then error(\"AOT numeric-for runtime requires LuaJIT\", 0) end" ,
"    loopVm.off(" .. probe .. ", true)" ,
"    if " .. probe .. "() ~= " .. expected .. " then" ,
"        error(\"AOT numeric-for runtime mismatch (expected " .. ( mode ) .. ")\", 0)" ,
"    end" ,
"end" ,
}
end








function binding . nativeOnlyStub ( program , header ) 
local lines = { }
lines [ # lines + 1 ] = "--- `" .. program . name .. "` is a native-only AOT entry: its signature carries a vector or a"
lines [ # lines + 1 ] = "--- mask, so other compiled code calls it directly and Lua has no entry to it."
lines [ # lines + 1 ] = "--- @raises string when called, which only Lua can do"
if header ~= nil then
lines [ # lines + 1 ] = ( header ) : gsub ( "%s+$" , "" )
else
local params = { }
for _ , param in ipairs ( program . params ) do
params [ # params + 1 ] = logical ( param )
end
local resultSourceTypes = program . resultSourceTypes or { }
local result = # resultSourceTypes == 0 and "nil"
or # resultSourceTypes == 1 and resultSourceTypes [ 1 ]
or "(" .. table . concat ( resultSourceTypes , ", " ) .. ")"
lines [ # lines + 1 ] = "local function " .. program . name .. "(" .. table . concat ( params , ", " ) .. "): " .. result
end
lines [
# lines + 1
] = "    error(\""
.. program . name
.. " is a native-only AOT entry: it takes or answers a vector and cannot be called from Lua\", 2)"
lines [ # lines + 1 ] = "end"

return lines
end













function binding . replacement (
program ,
library ,
tiers ,
includeDetector ,
archive ,
header
) 
if program . nativeOnly == true then
return table . concat ( binding . nativeOnlyStub ( program , header ) , "\n" )
end
local lines = binding . numericForGuard ( program )




local detector = includeDetector == true and tiers ~= nil and # tiers > 1


local probe = includeDetector == true and archive ~= nil and archive or nil
if probe ~= nil then
for _ , line in ipairs ( binding . archiveProbe ( probe ) ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = ""
end
if program . entryMode == "lua-builder" then
for _ , line in ipairs ( binding . builderLoader ( program , library , tiers , detector ) ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = ""
for _ , line in ipairs ( binding . builderWrapper ( program ) ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = ""
for _ , line in ipairs ( binding . compiledMarker ( program ) ) do
lines [ # lines + 1 ] = line
end

return table . concat ( lines , "\n" )
elseif program . entryMode == "kernel" then

else
error ( "unknown AOT entry mode" , 0 )
end
if # ( program . resultTypes or { } ) > 1 then
for _ , line in ipairs ( binding . resultStruct ( program ) ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = ""
end
local reporterSymbol = program . symbol
if tiers ~= nil and # tiers > 0 then
reporterSymbol = target . symbol ( program . symbol , tiers [ 1 ] )
end
for _ , layout in ipairs ( program . layouts or { } ) do
if layout . nativeOnly == true then

goto nextLayout
end
for _ , line in ipairs ( binding . layoutReporters ( reporterSymbol , layout , library ) ) do
lines [ # lines + 1 ] = line
end
for _ , line in ipairs ( binding . layoutChecks ( reporterSymbol , layout ) ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = ""
:: nextLayout ::
end
local native = nil
if tiers ~= nil and # tiers > 0 then
local declarations , selected = binding . multiversion ( program , library , tiers , detector )
native = selected
for _ , line in ipairs ( declarations ) do
lines [ # lines + 1 ] = line
end
else
for _ , line in ipairs ( binding . foreign ( program , library ) ) do
lines [ # lines + 1 ] = line
end
end
lines [ # lines + 1 ] = ""
for _ , line in ipairs ( binding . wrapper ( program , native ) ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = ""
for _ , line in ipairs ( binding . compiledMarker ( program ) ) do
lines [ # lines + 1 ] = line
end

return table . concat ( lines , "\n" )
end

local function specializedLiteral ( value ) 
if value . op == "constant" then
return ( value ) . value
elseif value . op == "bool" then
return tostring ( ( value ) . value )
elseif value . op == "lua_string" then
return string . format ( "%q" , ( value ) . value )
end

error ( "const specialization carries a non-scalar value" , 0 )
end





function binding . familyReplacement (
family ,
library ,
tiers ,
includeDetector ,
archive
) 
local lines = { }
for position , program in ipairs ( family . programs ) do
lines [
# lines + 1
] = binding . replacement ( program , library , tiers , includeDetector == true and position == 1 , archive )
lines [ # lines + 1 ] = ""
end

lines [ # lines + 1 ] = binding . familyDispatch ( family )

return table . concat ( lines , "\n" )
end


function binding . familyDispatch ( family ) 
local lines = { }
lines [ # lines + 1 ] = family . header
for position , specialization in ipairs ( family . specializations ) do
local conditions = { }
for _ , binder in ipairs ( family . binders ) do
for _ , carrier in ipairs ( binder . carriers ) do
local value = specialization . values [ carrier . name ]
conditions [ # conditions + 1 ] = carrier . name .. " == " .. specializedLiteral ( value )
end
end
local program = ( family . dispatchPrograms or family . programs ) [ position ]
local arguments = { }
for _ , param in ipairs ( program . params ) do
if param . soa == nil or param . soa . ordinal == 1 then
arguments [ # arguments + 1 ] = param . name
end
end
local branch = position == 1 and "if" or "elseif"
lines [ # lines + 1 ] = "    " .. branch .. " " .. table . concat ( conditions , " and " ) .. " then"
lines [ # lines + 1 ] = "        return " .. program . name .. "(" .. table . concat ( arguments , ", " ) .. ")"
end
lines [ # lines + 1 ] = "    end"
lines [ # lines + 1 ] = "    error(\"no compiled const application exists for this argument tuple\", 2)"
lines [ # lines + 1 ] = "end"

local first = family . programs [ 1 ]
local registry = first . symbol .. "_compiledEntries"
lines [ # lines + 1 ] = "local " .. registry .. ": any = rawget(_G, \"__nuppAotCompiled\")"
lines [ # lines + 1 ] = "if " .. registry .. " == nil then"
lines [ # lines + 1 ] = "    " .. registry .. " = setmetatable({}, {__mode = \"k\"})"
lines [ # lines + 1 ] = "    rawset(_G, \"__nuppAotCompiled\", " .. registry .. ")"
lines [ # lines + 1 ] = "end"
lines [ # lines + 1 ] = registry .. "[" .. family . name .. "] = true"

return table . concat ( lines , "\n" )
end



function binding . module ( programs , library ) 
local lines

= { "-- Generated from verified test-only native IR." , "" , "local span = require(\"nupp.mem.span\")" , "" , }

local function append ( more ) 
for _ , line in ipairs ( more ) do
lines [ # lines + 1 ] = line
end
end




local declared = { }
local exports = { }
for _ , program in ipairs ( programs ) do
for _ , layout in ipairs ( program . layouts or { } ) do
if layout . nativeOnly ~= true then
if not declared [ layout . name ] then
declared [ layout . name ] = true
append ( binding . struct ( layout ) )
lines [ # lines + 1 ] = ""
exports [ # exports + 1 ] = layout . name .. " = " .. layout . name
end
append ( binding . layoutReporters ( program . symbol , layout , library ) )
append ( binding . layoutChecks ( program . symbol , layout ) )
lines [ # lines + 1 ] = ""
end
end
end

for _ , program in ipairs ( programs ) do
if program . nativeOnly == true then
append ( binding . nativeOnlyStub ( program ) )
lines [ # lines + 1 ] = ""
exports [ # exports + 1 ] = program . name .. " = " .. program . name
goto continue
end
append ( binding . numericForGuard ( program ) )
if program . entryMode == "lua-builder" then
append ( binding . builderLoader ( program , library ) )
lines [ # lines + 1 ] = ""
append ( binding . builderWrapper ( program ) )
append ( binding . compiledMarker ( program ) )
lines [ # lines + 1 ] = ""
exports [ # exports + 1 ] = program . name .. " = " .. program . name
else
if # ( program . resultTypes or { } ) > 1 then
append ( binding . resultStruct ( program ) )
lines [ # lines + 1 ] = ""
end
append ( binding . foreign ( program , library ) )
lines [ # lines + 1 ] = ""
append ( binding . wrapper ( program ) )
append ( binding . compiledMarker ( program ) )
lines [ # lines + 1 ] = ""
exports [ # exports + 1 ] = program . name .. " = " .. program . name
end
:: continue ::
end

lines [ # lines + 1 ] = "return {" .. table . concat ( exports , ", " ) .. ",}"

return table . concat ( lines , "\n" ) .. "\n"
end

local __nuppExportValue= binding ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.binding"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.binding"]=__nuppExports;return __nuppExports