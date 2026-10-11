_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local binding = require ( "nupp.compiler.aot.binding" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )

local wasmbinding = { }

local function sourceType ( param ) 
return param . sourceType
or (
param . type == "f32" and "float"
or param . type == "f64" and "number"
or param . type == "u32" and "uint32"
or param . type == "i32" and "int32"
or param . type == "bool" and "boolean"
or param . type
)
end

local function logical ( param ) 
local element = param . type : match ( "^struct:(.+)$" ) or ( param . sourceType or ( param . type == "f32" and "float" or param . type == "f64" and "number" or param . type == "u32" and "uint32" or param . type == "i32" and "int32" or param . type == "bool" and "boolean" or param . type ) )
if param . kind == "write_span" then
return "exclusive " .. param . name .. ": nupp.mem.span.WriteSpan<" .. tostring ( element ) .. ">"
elseif param . kind == "read_span" then
return "borrows " .. param . name .. ": nupp.mem.span.Span<" .. tostring ( element ) .. ">"
elseif param . type == "lua_bytes" then
return "borrows " .. param . name .. ": " .. ( param . sourceType or ( param . type == "f32" and "float" or param . type == "f64" and "number" or param . type == "u32" and "uint32" or param . type == "i32" and "int32" or param . type == "bool" and "boolean" or param . type ) )
else
return param . name .. ": " .. ( param . sourceType or ( param . type == "f32" and "float" or param . type == "f64" and "number" or param . type == "u32" and "uint32" or param . type == "i32" and "int32" or param . type == "bool" and "boolean" or param . type ) )
end
end

local function cast ( value , named ) 
if named == "uint32" then
return "nupp.math.u32.wrap(" .. value .. " as integer)"
elseif named == "int32" then
return "nupp.math.i32.wrap(" .. value .. " as integer)"
elseif named == "float" then
return "nupp.math.f32.narrow(" .. value .. " as number)"
end

return value .. " as " .. named
end




function wasmbinding . replacement ( program , units ) 
local prefix = "__nuppWasm_" .. program . symbol
local lines = binding . numericForGuard ( program )
local ffi = binding . ffiLocal ( program )
if binding . checksOverlap ( program . params ) then
lines [ # lines + 1 ] = "local " .. ffi .. " = require(\"ffi\")"
end
lines [
# lines + 1
] = "local " .. prefix .. "Native: any = " .. require ( "nupp.compiler.aot.wasmbridge" ) . binding ( program , units )
local params = { }
for position , param in ipairs ( program . params ) do
params [ position ] = logical ( param )
end
lines [ # lines + 1 ] = "local function " .. program . name .. "("
for position , param in ipairs ( params ) do
lines [ # lines + 1 ] = "    " .. param .. ( position < # params and "," or "" )
end
local results = program . resultSourceTypes or { }
local result = # results == 0 and "nil" or # results == 1 and results [ 1 ] or "(" .. table . concat ( results , ", " ) .. ")"
lines [ # lines + 1 ] = "): " .. result



for _ , line in ipairs ( binding . relations ( program ) ) do
lines [ # lines + 1 ] = line
end

local arguments = { }
local counts = { }
local physicalParams = { }
local taken = { }
local primary = nil
for _ , param in ipairs ( program . params ) do
if param . kind == "write_span" or param . kind == "read_span" then
local token = prefix .. "_" .. param . name
local count = prefix .. "_" .. param . name .. "Count"
lines [ # lines + 1 ] = "    local " .. token .. ", " .. count .. " = " .. param . name .. ":ref()"
if primary == nil then
primary = count
elseif program . body == nil and program . loop == nil then



lines [
# lines + 1
] = "    if " .. count .. " ~= " .. tostring (
primary
) .. " then error(\"Wasm AOT spans have incompatible lengths\", 2) end"
end
arguments [ # arguments + 1 ] = token
taken [ # taken + 1 ] = _G.setmetatable({ param =  param ,  pointer =  token ,  count =  count }, binding.TakenSpan)
local element = param . type : match ( "^struct:(.+)$" ) or ( param . sourceType or ( param . type == "f32" and "float" or param . type == "f64" and "number" or param . type == "u32" and "uint32" or param . type == "i32" and "int32" or param . type == "bool" and "boolean" or param . type ) )
physicalParams [
# physicalParams + 1
] = (
param . kind == "write_span" and "exclusive " or "borrows "
) .. token .. ": " .. ( param . kind == "read_span" and "const " or "" ) .. tostring ( element ) .. "[?]"
counts [ # counts + 1 ] = count
else
arguments [ # arguments + 1 ] = param . name
physicalParams [ # physicalParams + 1 ] = logical ( param )
end
end


for _ , line in ipairs ( binding . overlapChecks ( taken , ffi ) ) do
lines [ # lines + 1 ] = line
end
if program . body ~= nil then
for _ , count in ipairs ( counts ) do
arguments [ # arguments + 1 ] = count
physicalParams [ # physicalParams + 1 ] = count .. ": integer"
end
else
arguments [ # arguments + 1 ] = tostring ( primary )
physicalParams [ # physicalParams + 1 ] = "count: integer"
end
lines [
# lines + 1
] = "    local " .. prefix .. "Call = " .. prefix .. "Native as @nosuspend function(" .. table . concat (
physicalParams ,
", "
) .. "): " .. result
local call = prefix .. "Call(" .. table . concat ( arguments , ", " ) .. ")"
if # results == 0 then
lines [ # lines + 1 ] = "    " .. call
elseif # results == 1 then
lines [ # lines + 1 ] = "    return " .. cast ( call , results [ 1 ] )
else
local names = { }
local values = { }
for position , named in ipairs ( results ) do
names [ position ] = prefix .. "Result" .. tostring ( position )
values [ position ] = cast ( names [ position ] , named )
end
lines [ # lines + 1 ] = "    local " .. table . concat ( names , ", " ) .. " = " .. call
lines [ # lines + 1 ] = "    return " .. table . concat ( values , ", " )
end
lines [ # lines + 1 ] = "end"
for _ , line in ipairs ( binding . compiledMarker ( program ) ) do
lines [ # lines + 1 ] = line
end

return table . concat ( lines , "\n" )
end


function wasmbinding . familyReplacement ( family , units ) 
local lines = { }
for _ , program in ipairs ( family . programs ) do
lines [ # lines + 1 ] = wasmbinding . replacement ( program , units )
end
lines [ # lines + 1 ] = binding . familyDispatch ( family )

return table . concat ( lines , "\n\n" )
end

local __nuppExportValue= wasmbinding ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.wasmbinding"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.wasmbinding"]=__nuppExports;return __nuppExports