_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.targetprofile\0runtime\0001") };





























local layouts = require ( "nupp.compiler.targetlayout" )

local targetProfile = { }


targetProfile.Profile = {} targetProfile.Profile.__index = targetProfile.Profile ;_G.nupp.__reflect.link(targetProfile.Profile,__nuppT1[1],{ })




















































local function hostedLinking ( system ) 
if system == "darwin" then
return { "-Wl,-force_load,<archive>" } , { "-Wl,-export_dynamic" }
elseif system == "windows" then
return { "-Wl,--whole-archive" , "<archive>" , "-Wl,--no-whole-archive" , } , { "-Wl,--export-all-symbols" }
end

return { "-Wl,--whole-archive" , "<archive>" , "-Wl,--no-whole-archive" } , { "-Wl,-E" }
end


function targetProfile . system ( target ) 
if target : find ( "apple" , 1 , true ) ~= nil then
return "darwin"
elseif target : find ( "windows" , 1 , true ) ~= nil then
return "windows"
elseif target : find ( "emscripten" , 1 , true ) ~= nil then
return "emscripten"
end

return "linux"
end






local function builtin ( target ) 
if not layouts . has ( target ) then
return nil
end
local system = targetProfile . system ( target )
if system == "emscripten" then
return ( _G.setmetatable({ target =
target ,  origin =
"built-in" ,  layoutModel =
target ,  os =
system ,  dynamicLoader =
true ,  tracingJit =
false ,  ffiCallbacks =
true ,  staticSymbolResolver =
false ,  staticAot =
false ,  forceLoad =
{ } ,  export =
{ } }, targetProfile.Profile) )

end
local forceLoad , export = hostedLinking ( system )

return ( _G.setmetatable({ target =
target ,  origin =
"built-in" ,  layoutModel =
target ,  os =
system ,  dynamicLoader =
true ,  tracingJit =
true ,  ffiCallbacks =
true ,  staticSymbolResolver =
true ,  staticAot =
true ,  forceLoad =
forceLoad ,  export =
export }, targetProfile.Profile) )

end






local function capability ( value , field , label ) 
if type ( value ) ~= "boolean" then
return nil , label .. " requires a boolean " .. field
end

return value , nil
end

local function flagList ( value , field , label ) 
if value == nil then
return { } , nil
end
if type ( value ) ~= "table" then
return nil , label .. "." .. field .. " must be an array of strings"
end
local count = 0
for key in pairs ( value ) do
if type ( key ) ~= "number" or key < 1 or key ~= math . floor ( key ) then
return nil , label .. "." .. field .. " must be an array of strings"
end
count = count + 1
end
if count ~= # value then
return nil , label .. "." .. field .. " must not have gaps"
end
local out = { }
for index , entry in ipairs ( value ) do
if type ( entry ) ~= "string" then
return nil , label .. "." .. field .. "[" .. tostring ( index ) .. "] must be a string"
end
out [ # out + 1 ] = entry
end

return out , nil
end






function targetProfile . fromDescriptor ( target , value , origin ) 
local label = "target profile for " .. target .. " in " .. origin
if type ( value ) ~= "table" then
return nil , label .. " must be an object"
end
local descriptor = value
local model = descriptor . layoutModel
if type ( model ) ~= "string" or not layouts . has ( model ) then
return nil , label .. " must name a modelled layoutModel"
end



local system = descriptor . os
if type ( system ) ~= "string" then
return nil , label .. " must name its os"
end
local capabilities = descriptor . capabilities
if type ( capabilities ) ~= "table" then
return nil , label .. " must carry a capabilities object"
end
local read = capabilities
local loader , loaderErr = capability ( read . dynamicLoader , "dynamicLoader" , label )
if loader == nil then
return nil , loaderErr
end
local jit , jitErr = capability ( read . tracingJit , "tracingJit" , label )
if jit == nil then
return nil , jitErr
end
local callbacks , callbackErr = capability ( read . ffiCallbacks , "ffiCallbacks" , label )
if callbacks == nil then
return nil , callbackErr
end
local resolver , resolverErr = capability ( read . staticSymbolResolver , "staticSymbolResolver" , label )
if resolver == nil then
return nil , resolverErr
end
local staticAot , staticErr = capability ( read . staticAot , "staticAot" , label )
if staticAot == nil then
return nil , staticErr
end
if staticAot == true and resolver == false then
return nil , label .. " claims static AOT without a static symbol resolver"
end
local link = descriptor . link
if link ~= nil and type ( link ) ~= "table" then
return nil , label .. ".link must be an object"
end
local linkTable = type ( link ) == "table" and link or { }
local forceLoad , forceErr = flagList ( linkTable . forceLoad , "link.forceLoad" , label )
if forceLoad == nil then
return nil , forceErr
end
local export , exportErr = flagList ( linkTable . export , "link.export" , label )
if export == nil then
return nil , exportErr
end

return _G.setmetatable({ target =
target ,  origin =
origin ,  layoutModel =
model ,  os =
system ,  dynamicLoader =
loader ,  tracingJit =
jit ,  ffiCallbacks =
callbacks ,  staticSymbolResolver =
resolver ,  staticAot =
staticAot ,  forceLoad =
forceLoad ,  export =
export }, targetProfile.Profile)
, nil
end







function targetProfile . resolve ( target , descriptor , origin ) 
if target == nil then
return nil , "a target profile needs a target triple"
end
local named = target
if descriptor ~= nil then
return targetProfile . fromDescriptor ( named , descriptor , origin or "a compiler pack" )
end
local known = builtin ( named )
if known == nil then
return nil , "no target profile describes " .. named
end

return known , nil
end

local __nuppExportValue= targetProfile ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.targetprofile"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.targetprofile"]=__nuppExports;return __nuppExports