_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local scalar = require ( "nupp.compiler.aot.scalar" )
local target = require ( "nupp.compiler.aot.target" )
local json = require ( "nupp.runtime.provider.lunajson" )
local bridge = { }

function bridge . validate ( programs ) 
for _ , program in ipairs ( programs ) do

if program . entryMode ~= "kernel" then
return "independent Wasm AOT cannot bind Lua-builder entry "
.. program . name
.. "; Lua construction requires a Lua VM ABI"
end
end

return nil
end

function bridge . metadata ( programs , tier ) 
local entries = json . asArray ( { } )
for index , program in ipairs ( programs ) do
local params = json . asArray ( { } )
for _ , param in ipairs ( program . params ) do
params [ # params + 1 ] = { kind = param . kind , type = param . type , sourceType = param . sourceType }
end
local layouts = json . asArray ( { } )
for _ , layout in ipairs ( program . layouts or { } ) do
if layout . nativeOnly == true then
goto nextLayout
end
local fields = json . asArray ( { } )
for _ , field in ipairs ( layout . fields ) do
fields [ # fields + 1 ] = field . name
end
layouts [
# layouts + 1
] = {
name = layout . name ,
fields = fields ,
prefix = target . symbol ( program . symbol , tier ) .. "_layout_" .. layout . name
}
:: nextLayout ::
end
entries [
# entries + 1
] = {
symbol = program . symbol ,
call = "nupp_bridge_" .. tostring ( index ) ,
params = params ,
independentCounts = scalar . independentCounts ( program ) ,
results = json . asArray ( program . resultTypes or { } ) ,
layouts = layouts
}
end

return { abi = 1 , entries = entries }
end



function bridge . binding ( program , units ) 
local quoted = { }
for _ , unit in ipairs ( units ) do
quoted [ # quoted + 1 ] = string . format ( "%q" , unit )
end
local unit = # quoted == 1 and quoted [ 1 ] or "{" .. table . concat ( quoted , ", " ) .. "}"
local params = { }
for _ , param in ipairs ( program . params ) do
local layout = param . type : match ( "^struct:(.+)$" )
params [
# params + 1
] = "{kind = " .. string . format (
"%q" ,
param . kind
) .. ", type = " .. string . format (
"%q" ,
param . type
) .. ", sourceType = " .. string . format (
"%q" ,
param . sourceType or ""
) .. ( layout and ", layout = layoutof(" .. layout .. ")" or "" ) .. "}"
end
local results = { }
for _ , kind in ipairs ( program . resultTypes or { } ) do
results [ # results + 1 ] = string . format ( "%q" , kind )
end

return "assert(rawget(_G, \"__nuppBrowser\"), \"LuaJIT browser host is not installed\").kernel("
.. unit
.. ", "
.. string . format (
"%q" ,
program . symbol
) .. ", {params = {" .. table . concat (
params ,
", "
) .. "}, results = {" .. table . concat (
results ,
", "
) .. "}, independentCounts = " .. tostring ( scalar . independentCounts ( program ) ) .. "})"
end

local __nuppExportValue= bridge ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.wasmbridge"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.wasmbridge"]=__nuppExports;return __nuppExports