_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()









local gpuartifact = require ( "nupp.compiler.aot.gpuartifact" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )

local gpubinding = { }

const SOURCE_TYPE

= { f64 = "number" , f32 = "float" , i32 = "int32" , u32 = "uint32" , bool = "boolean" , }

const C_TYPE = { f32 = "float" , i32 = "int32_t" , u32 = "uint32_t" , }

local function sourceType ( param ) 
return param . sourceType or param . type : match ( "^struct:(.+)$" ) or tostring ( SOURCE_TYPE [ param . type ] )
end

local function typeName ( prefix , program ) 
return scalarIR . identifier ( prefix , program . symbol )
end

local function append ( lines , value ) 
lines [ # lines + 1 ] = value
end


local function binaryLiteral ( value ) 
local quoted = string . format ( "%q" , value )
return ( quoted : gsub ( "[€-ÿ]" , function ( byte ) 
return ("\\%03d") : format ( byte : byte ( 1 ) )
end ) )
end

local function parameterNames ( params ) 
local names = { }
for _ , param in ipairs ( params ) do
names [ # names + 1 ] = string . format ( "%q" , param . name )
end

return "{" .. table . concat ( names , ", " ) .. "}"
end

local function parameterName ( names , name ) 
local generated = name ~= nil and names [ name ] or nil
assert ( generated ~= nil , "GPU binding parameter has no generated name" )

return generated
end


local function relationRefusal ( relation , names ) 
assert ( relation . left . kind == "count" and relation . right . kind == "count" , "GPU binding relation is not over counts" )
local left = parameterName ( names , relation . left . name ) .. ".count"
local right = parameterName ( names , relation . right . name ) .. ".count"
if relation . offset == 0 then
return left .. " > " .. right
elseif relation . offset > 0 then
return left .. " > " .. right .. " + " .. tostring ( relation . offset )
else
return left .. " > " .. right .. " - " .. tostring ( - relation . offset )
end
end


local function relationChecks ( program , names ) 
local conditions = { }
for _ , relation in ipairs ( program . relations or { } ) do
conditions [ # conditions + 1 ] = relationRefusal ( relation , names )
end
if # conditions == 0 then
return { }
end

return {
"    if " .. table . concat ( conditions , " or " ) .. " then" ,
"        error(\"GPU precondition failed\", 2)" ,
"    end" ,
}
end

local function freshName ( reserved , preferred ) 
local name = preferred
while reserved [ name ] do
name = name .. "_"
end
reserved [ name ] = true

return name
end


function gpubinding . replacement ( program , artifact , browser ) 
local reserved = { [ program . name ] = true , self = true , }
local names = { }
for _ , param in ipairs ( program . params ) do
reserved [ param . name ] = true
names [ param . name ] = param . name
end
if names . self ~= nil then
names . self = freshName ( reserved , "gpuParameter" )
end
local runtime = freshName ( reserved , scalarIR . identifier ( "gpuRuntime" , program . symbol ) )
local implementation = freshName ( reserved , scalarIR . identifier ( "gpuImplementation" , program . symbol ) )
local native = freshName ( reserved , scalarIR . identifier ( "gpuNative" , program . symbol ) )
local uniformType = freshName ( reserved , scalarIR . identifier ( "gpuUniformType" , program . symbol ) )
local specType = freshName ( reserved , ( scalarIR . identifier ( "GpuSpec" , program . symbol ) ) )
local kernelType = freshName ( reserved , ( scalarIR . identifier ( "GpuKernel" , program . symbol ) ) )
local bindingType = freshName ( reserved , ( scalarIR . identifier ( "GpuBinding" , program . symbol ) ) )
local bindReserved = { self = true , }
for _ , param in ipairs ( program . params ) do
if param . kind == "read_span" or param . kind == "write_span" then
bindReserved [ parameterName ( names , param . name ) ] = true
end
end
local rawBinding = freshName ( bindReserved , "raw" )
local dispatchReserved = { self = true , }
for _ , param in ipairs ( artifact . uniforms ) do
dispatchReserved [ parameterName ( names , param . name ) ] = true
end
local scalarWords = freshName ( dispatchReserved , "scalars" )
local uniformBlock = freshName ( dispatchReserved , "uniforms" )
local lines = { }
local recordDeclaration = artifact . exportTypes and "export record " or "local record "


append ( lines , "local " .. runtime .. " = require(\"nupp.gpu\")" )
append ( lines , "local " .. implementation .. " = require(\"nupp.gpu.internal\")" )
if not browser then
append ( lines , "local " .. native .. " = require(\"nupp.runtime.native\")" )
end




local fields = { "uint32_t dispatch_count;" }
local spanPosition = 0
for _ in ipairs ( artifact . readonly ) do
spanPosition = spanPosition + 1
fields [ # fields + 1 ] = "uint32_t span_" .. tostring ( spanPosition ) .. "_count;"
end
for _ in ipairs ( artifact . writable ) do
spanPosition = spanPosition + 1
fields [ # fields + 1 ] = "uint32_t span_" .. tostring ( spanPosition ) .. "_count;"
end
spanPosition = 0
for _ in ipairs ( artifact . readonly ) do
spanPosition = spanPosition + 1
fields [ # fields + 1 ] = "uint32_t span_" .. tostring ( spanPosition ) .. "_offset;"
end
for _ in ipairs ( artifact . writable ) do
spanPosition = spanPosition + 1
fields [ # fields + 1 ] = "uint32_t span_" .. tostring ( spanPosition ) .. "_offset;"
end
for position , param in ipairs ( artifact . uniforms ) do
fields [ # fields + 1 ] = tostring ( C_TYPE [ param . type ] ) .. " uniform_" .. tostring ( position ) .. ";"
end
if not browser then
append (
lines ,
"local " .. uniformType .. " = " .. native .. ".ffi.typeof(" .. string . format (
"%q" ,
"struct { " .. table . concat ( fields , " " ) .. " }"
) .. ")"
)
end
append ( lines , "" )





append ( lines , recordDeclaration .. bindingType .. " is nupp.Closeable" )
append ( lines , "    @private _binding: " .. implementation .. ".Binding" )
append ( lines , "    function close(takes self): nil" )
append ( lines , "        self._binding:close()" )
append ( lines , "    end" )
local dispatchParams = { "borrows self: " .. bindingType }
for _ , param in ipairs ( artifact . uniforms ) do
dispatchParams [ # dispatchParams + 1 ] = parameterName ( names , param . name ) .. ": " .. ( param . sourceType or param . type : match ( "^struct:(.+)$" ) or tostring ( SOURCE_TYPE [ param . type ] ) )
end
append ( lines , "    dispatch: function(" )
for position , param in ipairs ( dispatchParams ) do
append ( lines , "        " .. param .. ( position < # dispatchParams and "," or "" ) )
end
append ( lines , "    ): nil" )
append ( lines , "end" )
append ( lines , "" )

append ( lines , recordDeclaration .. kernelType .. " is nupp.Closeable" )
append ( lines , "    @private _kernel: " .. implementation .. ".Kernel" )
append ( lines , "    function close(takes self): nil" )
append ( lines , "        self._kernel:close()" )
append ( lines , "    end" )
local bindParams = { "borrows self: " .. kernelType }
for _ , param in ipairs ( program . params ) do
if param . kind == "read_span" or param . kind == "write_span" then
bindParams [
# bindParams + 1
] = "borrows " .. parameterName (
names ,
param . name
) .. ": " .. runtime .. ".Buffer<" .. ( param . sourceType or param . type : match ( "^struct:(.+)$" ) or tostring ( SOURCE_TYPE [ param . type ] ) ) .. ">"
end
end
append ( lines , "    bind: function(" )
for position , param in ipairs ( bindParams ) do
append ( lines , "        " .. param .. ( position < # bindParams and "," or "" ) )
end
append ( lines , "    ): affine(" .. bindingType .. ") borrows (self)" )
append ( lines , "end" )
append ( lines , "" )

append ( lines , recordDeclaration .. specType )
append ( lines , "    @private @readonly _marker: boolean" )
append (
lines ,
"    compile: function(borrows self: "
.. specType
.. ", borrows context: "
.. runtime
.. ".Context): affine("
.. kernelType
.. ") borrows (context)"
)
append ( lines , "end" )
append ( lines , "" )

append (
lines ,
"function "
.. specType
.. ".compile(borrows self: "
.. specType
.. ", borrows context: "
.. runtime
.. ".Context): affine("
.. kernelType
.. ") borrows (context)"
)
append ( lines , "    local artifacts = new " .. implementation .. ".ArtifactSet(" )
if browser then
append ( lines , "        wgsl = " .. string . format ( "%q" , artifact . wgsl ) .. "," )
else
append ( lines , "        spirv = " .. binaryLiteral ( artifact . spirv ) .. "," )
end
if artifact . sourceFile ~= nil then
append ( lines , "        sourceFile = " .. string . format ( "%q" , artifact . sourceFile ) .. "," )
append ( lines , "        sourceLine = " .. tostring ( artifact . sourceLine ) .. "," )
append ( lines , "        artifactId = " .. string . format ( "%q" , artifact . artifactId ) .. "," )
end
append ( lines , "        readonlyNames = " .. parameterNames ( artifact . readonly ) .. "," )
append ( lines , "        writableNames = " .. parameterNames ( artifact . writable ) .. "," )
append ( lines , "        entrypoint = " .. string . format ( "%q" , artifact . entrypoint ) )
append ( lines , "    )" )


append (
lines ,
"    return new "
.. kernelType
.. "(_kernel = "
.. implementation
.. ".compileGenerated(context, artifacts, "
.. tostring (
# artifact . readonly
) .. ", " .. tostring (
# artifact . writable
) .. ", " .. tostring ( artifact . uniformBytes ) .. ", " .. tostring ( artifact . threads ) .. "))"
)
append ( lines , "end" )
append ( lines , "" )

append ( lines , "function " .. kernelType .. ".bind(" )
for position , param in ipairs ( bindParams ) do
append ( lines , "    " .. param .. ( position < # bindParams and "," or "" ) )
end
append ( lines , "): affine(" .. bindingType .. ") borrows (self)" )
for _ , line in ipairs ( relationChecks ( program , names ) ) do
append ( lines , line )
end
append (
lines ,
"    local " .. rawBinding .. " = " .. implementation .. ".bindKernel(self._kernel, " .. parameterName (
names ,
artifact . countSpan
) .. ".count)"
)
for slot , param in ipairs ( artifact . readonly ) do
append (
lines ,
"    " .. rawBinding .. ":setRead(" .. tostring (
slot - 1
) .. ", " .. parameterName (
names ,
param . name
) .. ", " .. tostring ( artifact . exactCounts [ param . name ] == true ) .. ")"
)
end
for slot , param in ipairs ( artifact . writable ) do
append (
lines ,
"    " .. rawBinding .. ":setWrite(" .. tostring (
slot - 1
) .. ", " .. parameterName (
names ,
param . name
) .. ", " .. tostring ( artifact . exactCounts [ param . name ] == true ) .. ")"
)
end
append ( lines , "    return new " .. bindingType .. "(_binding = " .. rawBinding .. ")" )
append ( lines , "end" )
append ( lines , "" )

append ( lines , "function " .. bindingType .. ".dispatch(" )
for position , param in ipairs ( dispatchParams ) do
append ( lines , "    " .. param .. ( position < # dispatchParams and "," or "" ) )
end
append ( lines , "): nil" )
if browser then
append ( lines , "    local " .. scalarWords .. ": {uint32} = {}" )
for _ , param in ipairs ( artifact . uniforms ) do
append (
lines ,
"    " .. scalarWords .. "[#" .. scalarWords .. " + 1] = nupp.math.u32.wrap(" .. parameterName (
names ,
param . name
) .. " as integer)"
)
end
append ( lines , "    self._binding:dispatchWords(" .. scalarWords .. ")" )
else
append ( lines , "    local " .. uniformBlock .. " = " .. native .. ".ffi.new(" .. uniformType .. ")" )
append ( lines , "    " .. uniformBlock .. ".dispatch_count = self._binding.count" )
for position , param in ipairs ( artifact . uniforms ) do
append (
lines ,
"    " .. uniformBlock .. ".uniform_" .. tostring ( position ) .. " = " .. parameterName ( names , param . name )
)
end
append (
lines ,
"    self._binding:dispatchPacked(" .. uniformBlock .. ", " .. tostring ( artifact . uniformBytes ) .. ")"
)
end
append ( lines , "end" )
append ( lines , "" )
append ( lines , "local " .. program . name .. " = new " .. specType .. "(_marker = true)" )

return table . concat ( lines , "\n" )
end

local __nuppExportValue= gpubinding ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.gpubinding"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.gpubinding"]=__nuppExports;return __nuppExports