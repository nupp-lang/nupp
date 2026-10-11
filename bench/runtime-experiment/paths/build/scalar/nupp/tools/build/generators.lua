_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

const files2 = require ( "nupp.io.files" )

local capabilities = require ( "nupp.tools.build.capabilities" )
local fingerprint = require ( "nupp.compiler.project.fingerprint" )
local stable = require ( "nupp.compiler.stable" )
local deps = require ( "nupp.tools.build.deps" )
local fs = require ( "nupp.compiler.fs" )
local hash = require ( "nupp.compiler.hash" )
local process = require ( "nupp.compiler.process" )
local json = require ( "nupp.codec.json" )

local generators = { }

local function removeTree ( path ) 
if fs . exists ( path ) then
files2 . remove ( path , true )
end
end

local function inputsFor ( root , patterns ) 
local selected , seen = { } , { }
local canonicalRoot = fs . canonical ( root )
for _ , pattern in ipairs ( patterns or { } ) do
local matches = deps . expandGlob ( root , pattern )
if # matches == 0 then
return nil , "generator input matches no files: " .. pattern
end
for _ , matched in ipairs ( matches ) do
local files = fs . listFiles ( matched )
if # files == 0 then
files = { matched }
end
for _ , path in ipairs ( files ) do
local canonical = fs . canonical ( path )
if canonical ~= canonicalRoot and canonical : sub ( 1 , # canonicalRoot + 1 ) ~= canonicalRoot .. "/" then
return nil , "generator input escapes the project: " .. pattern
end
if not seen [ canonical ] then
seen [ canonical ] = true
selected [ # selected + 1 ] = canonical
end
end
end
end
table . sort ( selected )

return selected
end

function generators . run ( root , outDir , config , records , previous ) 
local result = { }
local names = { }
for name in pairs ( config . generators or { } ) do
names [ # names + 1 ] = name
end
table . sort ( names )
for _ , name in ipairs ( names ) do
local configured = config . generators [ name ]
local dependencyName , providerName = configured . using : match ( "^([^/]+)/([^/]+)$" )
local record = deps . record ( records , dependencyName , "tool" )
local capability , capabilityErr = capabilities . find ( record , dependencyName , "generator" , providerName )
if not capability then
return nil , capabilityErr
end
if capability . api ~= 1 then
return nil , "generator " .. configured . using .. " requires unsupported API " .. capability . api
end
local inputs , inputErr = inputsFor ( root , configured . inputs )
if not inputs then
return nil , inputErr
end
local output = fs . join ( root , fs . join ( outDir , "generated/" .. name ) )
local staged = output .. ".nupp-staged"
local old = previous and previous [ name ]
local key = hash . digest (
stable (
configured
) .. "\0" .. stable ( capability ) .. "\0" .. tostring ( record . key ) .. "\0" .. fingerprint . hashFiles ( inputs )
)
local oldFiles = old and old . files or { }
local currentFiles = fs . listFiles ( output )
if old
and old . key == key
and stable ( currentFiles ) == stable ( oldFiles )
and fingerprint . hashFiles ( currentFiles ) == old . outputHash
then
result [ name ] = old
else
removeTree ( staged )
fs . mkdir ( staged )
local requestPath = staged .. ".request.json"
local resultPath = staged .. ".result.json"
local wrote , writeErr = fs . writeFile (
requestPath ,
json . encode ( {
name = name ,
inputRoot = fs . absolute ( root ) ,
outputRoot = fs . absolute ( staged ) ,
inputs = inputs ,
options = configured . options or { } ,
entry = capability . entry ,
path = record . path ,
cpath = record . cpath ,
} ) .. "\n"
)
if not wrote then
return nil , writeErr
end
local compilerRoot = os . getenv ( "NUPP_COMPILER_ROOT" )
local executable = compilerRoot and fs . join ( compilerRoot , "bin/nupp" ) or tostring ( arg [ 0 ] or "nupp" )




local startedAt = os . time ( )
local code , captured = process . captureIsolated (
{ executable , "__generator-worker" , requestPath , resultPath } ,
{ cwd = root , timeoutMs = 120000 , memoryMb = 512 }
)
local responseText = fs . readFile ( resultPath )
local response = nil
if responseText then
response = json . decode ( responseText , json . NULL )
end
if type ( response ) ~= "table" then
response = nil
end
os . remove ( requestPath )
os . remove ( resultPath )
if code ~= 0 or not response or not response . ok then
removeTree ( staged )
if captured ~= "" then
io . stderr : write ( captured )
if captured : sub ( -1 ) ~= "\n" then
io . stderr : write ( "\n" )
end
end
local reason = response and response . error
if not reason and code == 124 then





reason = ("worker timed out after %ds of a %dms budget; it wrote %s and said %s")

: format (
os . time ( ) - startedAt ,
120000 ,
responseText and ( tostring ( # responseText ) .. " bytes of result" ) or "no result" ,
captured ~= "" and ( tostring ( # captured ) .. " bytes" ) or "nothing"
)
elseif not reason then
reason = "worker failed"
end
return nil , "generator " .. name .. " failed: " .. tostring ( reason )
end
for _ , diagnostic in ipairs ( response . diagnostics or { } ) do
io . stderr : write (
"nupp: " .. tostring ( diagnostic . severity ) .. ": " .. tostring ( diagnostic . message ) .. "\n"
)
end
local backup = output .. ".nupp-previous"
removeTree ( backup )
if fs . exists ( output ) then
local moved , moveErr = os . rename ( output , backup )
if not moved then
removeTree ( staged )
return nil , tostring ( moveErr )
end
end
local published , publishErr = os . rename ( staged , output )
if not published then
if fs . exists ( backup ) then
os . rename ( backup , output )
end
removeTree ( staged )
return nil , tostring ( publishErr )
end
removeTree ( backup )
local outputFiles = fs . listFiles ( output )
result [ name ] = { key = key , files = outputFiles , outputHash = fingerprint . hashFiles ( outputFiles ) }
end
end

return result
end

local __nuppExportValue= generators ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.generators"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.generators"]=__nuppExports;return __nuppExports