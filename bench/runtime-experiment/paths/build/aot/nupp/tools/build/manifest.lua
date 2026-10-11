_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()











local aotTargets = require ( "nupp.compiler.aot.target" )
local check = require ( "nupp.compiler.check" )
local fs = require ( "nupp.compiler.fs" )
local native = require ( "nupp.compiler.native" )

local join = fs . join

local manifest = { }





























































































































































































function manifest . testConfig ( config ) 
return config . test or ( { } )
end



function manifest . testArgv ( test ) 
return test . argv or { "nupp" , "test" , "--internal-runner" }
end

local function validateArray ( value , label , itemType , required ) 
if value == nil then
if required then
return nil , label .. " is required"
end
return true
end
if type ( value ) ~= "table" then
return nil , label .. " must be an array"
end
local count , highest = 0 , 0
for key , item in pairs ( value ) do
if type ( key ) ~= "number" or key < 1 or key ~= math . floor ( key ) then
return nil , label .. " must be an array"
end
count = count + 1
if key > highest then
highest = key
end
if itemType and type ( item ) ~= itemType then
return nil , label .. "[" .. key .. "] must be a " .. itemType
end
end
if count ~= highest then
return nil , label .. " must not contain gaps"
end
if required and count == 0 then
return nil , label .. " must not be empty"
end

return true
end

local function validateString ( value , label ) 
if type ( value ) ~= "string" or value == "" then
return nil , label .. " must be a non-empty string"
end
return true
end




local function validatePlainData ( value , label , visiting ) 
local valueType = type ( value )
if valueType == "string" or valueType == "boolean" then
return true
elseif valueType == "number" then
if value ~= value or value == math . huge or value == - math . huge then
return nil , label .. " must contain only finite numbers"
end
return true
elseif valueType ~= "table" then
return nil , label .. " must contain only strings, numbers, booleans, arrays, and tables"
else
value = value
end
local entries = value
if getmetatable ( value ) ~= nil then
return nil , label .. " must not contain tables with metatables"
end
visiting = visiting or { }
if visiting [ value ] then
return nil , label .. " must not contain cycles"
end
visiting [ value ] = true

local numeric , stringKeys , highest = 0 , 0 , 0
for key in pairs ( entries ) do
if type ( key ) == "number" and key >= 1 and key == math . floor ( key ) then
numeric = numeric + 1
highest = math . max ( highest , key )
elseif type ( key ) == "string" then
stringKeys = stringKeys + 1
else
visiting [ value ] = nil
return nil , label .. " must use either array indexes or string keys"
end
end
if numeric > 0 and stringKeys > 0 then
visiting [ value ] = nil
return nil , label .. " must not mix array indexes and string keys"
end
if numeric > 0 and numeric ~= highest then
visiting [ value ] = nil
return nil , label .. " must not contain gaps"
end
for key , item in pairs ( entries ) do
local valid , err = validatePlainData ( item , label .. "[" .. tostring ( key ) .. "]" , visiting )
if not valid then
visiting [ value ] = nil
return nil , err
end
end
visiting [ value ] = nil

return true
end










local DOCS_KEYS = {

"sources" ,
"format" ,
"outDir" ,
"title" ,
"name" ,
"description" ,
"github" ,
"logo" ,
"favicon" ,
"public" ,
"customCss" ,
"lexers" ,
"includePrivate" ,
"pages" ,
"diagnostics" ,
"stdlib" ,

"kind" ,
"dependencies" ,
"compileDependencies" ,
"entries" ,
"exports" ,
"resources" ,
"output" ,
"payloadOutput" ,
"stub" ,
"standalone" ,
"reload" ,
"platforms" ,
"platformOutputs" ,
"nativeFeatures" ,
"host" ,
"layoutTarget" ,
}

local PAGE_KEYS = {
"path" ,
"title" ,
"source" ,


"directory" ,




"glob" ,
"base" ,
"exclude" ,
"layout" ,
"redirects" ,
}




local GENERATED_KEYS = { "path" , "redirects" , "source" , "title" }

local TASK_KEYS = { "description" , "argv" , "build" , "cwd" , "env" }
local GENERATOR_KEYS = { "description" , "using" , "inputs" , "options" }








local CONFIG_KEYS = {
"compat" ,
"name" ,
"include" ,
"fmt" ,
"lints" ,
"dependencies" ,
"generators" ,
"build" ,
"test" ,
"tasks" ,
"selfHost" ,
"docs" ,
}



local TARGET_KEYS = {
"kind" ,
"optimize" ,
"aot" ,
"aotLinkage" ,
"aotFeatures" ,
"aotTarget" ,
"description" ,
"outDir" ,
"output" ,
"payloadOutput" ,
"stub" ,
"standalone" ,
"reload" ,
"platforms" ,
"platformOutputs" ,
"entries" ,
"exports" ,
"sources" ,
"resources" ,
"dependencies" ,
"compileDependencies" ,
"nativeFeatures" ,
"host" ,
"layoutTarget" ,
"format" ,
"title" ,
"name" ,
"targetName"
}



local BUILD_KEYS = { "targets" , "default" }

for _ , key in ipairs ( TARGET_KEYS ) do
BUILD_KEYS [ # BUILD_KEYS + 1 ] = key
end

local TEST_KEYS = { "argv" , "build" , "env" }
local SELF_HOST_KEYS = { "target" , "bootstrapTarget" , "bootstrap" , "binary" }




local CARGO_KEYS = {
"kind" ,
"dependencies" ,
"manifest" ,
"path" ,
"cargo" ,
"target" ,
"targetDir" ,
"profile" ,
"library" ,
"artifactPath" ,
"features" ,
"locked" ,
"offline" ,
"output" ,
"load" ,
"header" ,
"bindings" ,
"cc" ,
"cppflags"
}

local DEPENDENCY_KEYS

= {
c = {
"kind" ,
"dependencies" ,
"source" ,
"path" ,
"sources" ,
"headers" ,
"includeDirs" ,
"cc" ,
"cflags" ,
"cppflags" ,
"ldflags" ,
"pkgConfig" ,
"linkage" ,
"output" ,
"staticOutput" ,
"artifacts" ,
"load" ,
"header" ,
"bindings"
} ,
cargo = CARGO_KEYS ,
luarocks = {
"kind" ,
"dependencies" ,
"rock" ,
"version" ,
"rockspec" ,
"path" ,
"tree" ,
"luaVersion" ,
"server" ,
"luaDir" ,
"luarocks" ,
"rockDependencies" ,
"bundle"
} ,
types = { "kind" , "format" , "source" , "path" } ,
}


local BINDING_KEYS = { "header" , "library" , "output" , "bridge" , "macros" , "cbindgen" , "command" , "ownership" }
local NATIVE_ARTIFACT_KEYS = { "path" , "sha256" , "size" }
local NATIVE_ARTIFACT_SET_KEYS = { "shared" , "static" }

local function validateKeys ( value , known , label ) 
if type ( value ) ~= "table" then
return true
end
local allowed = { }
for _ , name in ipairs ( known ) do
allowed [ name ] = true
end
local unknown = { }
for key in pairs ( value ) do



if type ( key ) == "string" and not allowed [ key ] and key : sub ( 1 , 1 ) ~= "_" then
unknown [ # unknown + 1 ] = key
end
end
table . sort ( unknown )
local key = unknown [ 1 ]
if not key then
return true
end
local suggestion = require ( "nupp.compiler.check.fixits" ) . nearest ( key , known )
if suggestion then
return nil , ("%s has no key %q; did you mean %q?") : format ( label , key , suggestion )
end

return nil , ("%s has no key %q") : format ( label , key )
end

local function validSymbol ( value ) 
return type ( value ) == "string" and value : match ( "^[A-Za-z_][A-Za-z0-9_]*$" ) ~= nil
end

local function validateOwnership ( value , label ) 
if value == nil then
return true
end
if type ( value ) ~= "table" then
return nil , label .. " must be a table"
end
local valid , err = validateKeys ( value , { "returns" , "takes" } , label )
if not valid then
return nil , err
end
for functionName , cleanup in pairs ( value . returns or { } ) do
if not ( type ( functionName ) == "string" and functionName : match ( "^[A-Za-z_][A-Za-z0-9_]*$" ) ~= nil ) or not ( type ( cleanup ) == "string" and cleanup : match ( "^[A-Za-z_][A-Za-z0-9_]*$" ) ~= nil ) then
return nil , label .. ".returns must map C symbols to cleanup C symbols"
end
end
for functionName , positions in pairs ( value . takes or { } ) do
if not ( type ( functionName ) == "string" and functionName : match ( "^[A-Za-z_][A-Za-z0-9_]*$" ) ~= nil ) then
return nil , label .. ".takes must be keyed by C symbols"
end
valid , err = validateArray ( positions , label .. ".takes." .. functionName , "number" )
if not valid then
return nil , err
end
for _ , position in ipairs ( positions ) do
if position < 1 or position % 1 ~= 0 then
return nil , label .. ".takes." .. functionName .. " must contain positive parameter positions"
end
end
end

return true
end

local function validateDocsTarget ( target , label ) 
local valid , err = validateKeys ( target , DOCS_KEYS , label )
if not valid then
return nil , err
end
if target . pages ~= nil and type ( target . pages ) ~= "table" then
return nil , label .. ".pages must be an array of page tables"
end
for _ , generated in ipairs ( { "diagnostics" , "stdlib" } ) do
local configured = target [ generated ]
if configured ~= nil then
if type ( configured ) ~= "table" then
return nil , label .. "." .. generated .. " must be a table"
end
valid , err = validateKeys ( configured , GENERATED_KEYS , label .. "." .. generated )
if not valid then
return nil , err
end
end
end
for index , page in ipairs ( target . pages or { } ) do
local pageLabel = ("%s.pages[%d]") : format ( label , index )
if type ( page ) ~= "table" then
return nil , pageLabel .. " must be a table"
end
valid , err = validateKeys ( page , PAGE_KEYS , pageLabel )
if not valid then
return nil , err
end


if page . glob ~= nil then
if type ( page . glob ) ~= "string" then
valid , err = validateArray ( page . glob , pageLabel .. ".glob" , "string" , true )
if not valid then
return nil , err
end
end
valid , err = validateArray ( page . exclude , pageLabel .. ".exclude" , "string" , false )
if not valid then
return nil , err
end
elseif type ( page . path ) ~= "string" then
return nil , pageLabel .. ".path must be a string"
end
end

return true
end

local function validateTarget ( target , label , dependencies ) 
if type ( target ) ~= "table" then
return nil , label .. " must be a table"
end
local kind = target . kind or "modules"
if kind ~= "modules" and kind ~= "docs" and kind ~= "bundle" and kind ~= "binary" and kind ~= "component" then
return nil , label .. ".kind must be \"modules\", \"bundle\", \"binary\", \"component\", or \"docs\""
end
if kind ~= "docs" then
local valid , err = validateKeys ( target , TARGET_KEYS , label )
if not valid then
return nil , err
end
end
if target . optimize ~= nil
and (
type ( target . optimize ) ~= "number"
or ( target . optimize ~= 0 and target . optimize ~= 1 and target . optimize ~= 2 )
)
then
return nil , label .. ".optimize must be 0, 1, or 2"
end
if kind == "binary" and target . stub == nil then
return nil , label
.. ".stub is required for a binary target: it names the executable the payload is stamped into"

end
if target . stub ~= nil then
local valid , err = validateString ( target . stub , label .. ".stub" )
if not valid then
return nil , err
end
end
if target . standalone ~= nil and type ( target . standalone ) ~= "boolean" then
return nil , label .. ".standalone must be a boolean"
end
if target . standalone then
if kind ~= "binary" then
return nil , label .. ".standalone is only valid for a binary target"
end
if target . stub ~= "nupp" then
return nil , label .. ".standalone requires the compiler-owned stub = \"nupp\""
end
end
if target . reload ~= nil and type ( target . reload ) ~= "boolean" then
return nil , label .. ".reload must be a boolean"
end
if target . reload then
if kind ~= "component" then
return nil , label .. ".reload is only valid for a component target"
end



if target . optimize ~= nil and target . optimize ~= 0 then
return nil , label .. ".reload builds at optimize = 0"
end




if target . aot ~= nil and target . aot ~= "off" then
return nil , label
.. ".reload cannot be combined with aot; hot reload replaces Lua bodies, not compiled kernels"
end
end
if target . platforms ~= nil then
if kind ~= "binary" then
return nil , label .. ".platforms is only valid for a binary target"
end
if target . stub ~= "nupp" then
return nil , label .. ".platforms requires the compiler-owned stub = \"nupp\""
end
local valid , err = validateArray ( target . platforms , label .. ".platforms" , "string" , true )
if not valid then
return nil , err
end
local distribution = require ( "nupp.tools.build.platform" )
local layouts = require ( "nupp.compiler.targetlayout" )
local seen = { }
for index , name in ipairs ( target . platforms ) do
if seen [ name ] then
return nil , label .. ".platforms[" .. index .. "] duplicates " .. name
end
seen [ name ] = true
if not distribution . has ( name ) then
return nil , label
.. ".platforms names unsupported binary platform "
.. name
.. "; supported platforms: "
.. table . concat (
distribution . keys ( ) ,
", "
)
end
if not layouts . has ( name ) then
return nil , label .. ".platforms names a platform with no C layout model " .. name
end
end
if target . layoutTarget ~= nil and ( # target . platforms ~= 1 or target . layoutTarget ~= target . platforms [ 1 ] ) then
return nil , label .. ".layoutTarget must equal the selected binary platform; omit it for platform selection"
end
if # target . platforms > 1 and target . output ~= nil then
return nil , label .. ".output cannot name several platform binaries; use platformOutputs"
end
end
if target . platformOutputs ~= nil then
if target . platforms == nil then
return nil , label .. ".platformOutputs requires platforms"
end
if type ( target . platformOutputs ) ~= "table" then
return nil , label .. ".platformOutputs must be a table"
end
local configured = { }
local outputs = { }
for _ , name in ipairs ( target . platforms ) do
configured [ name ] = true
end
for name , output in pairs ( target . platformOutputs ) do
if type ( name ) ~= "string" or not configured [ name ] then
return nil , label .. ".platformOutputs names unconfigured platform " .. tostring ( name )
end
local valid , err = validateString ( output , label .. ".platformOutputs." .. name )
if not valid then
return nil , err
end
if outputs [ output ] then
return nil , label .. ".platformOutputs maps several platforms to " .. output
end
outputs [ output ] = true
end
end
if target . description ~= nil and type ( target . description ) ~= "string" then
return nil , label .. ".description must be a string"
end
if target . layoutTarget ~= nil then
local valid , err = validateString ( target . layoutTarget , label .. ".layoutTarget" )
if not valid then
return nil , err
end
local layouts = require ( "nupp.compiler.targetlayout" )
if not layouts . has ( target . layoutTarget ) then
return nil , label
.. ".layoutTarget names unsupported target "
.. target . layoutTarget
.. "; supported targets: "
.. table . concat (
layouts . keys ( ) ,
", "
)
end
end
if target . nativeFeatures ~= nil then
if type ( target . nativeFeatures ) ~= "table" then
return nil , label .. ".nativeFeatures must be a table"
end
local known = { }
for _ , name in ipairs ( native . featureNames ( ) ) do
known [ name ] = true
end
for name , enabled in pairs ( target . nativeFeatures ) do
if type ( name ) ~= "string" or not known [ name ] then
return nil , label .. ".nativeFeatures names no feature " .. tostring ( name )
end
if type ( enabled ) ~= "boolean" then
return nil , label .. ".nativeFeatures." .. name .. " must be true or false"
end
end
end
if target . host ~= nil and target . host ~= "native" and target . host ~= "browser" then
return nil , label .. ".host must be \"native\" or \"browser\""
end
if target . host == "browser" and target . platforms ~= nil then
return nil , label .. ".platforms selects native binary hosts and cannot be combined with host = \"browser\""
end
if target . outDir ~= nil then
local valid , err = validateString ( target . outDir , label .. ".outDir" )
if not valid then
return nil , err
end
end
if target . aot ~= nil then

local valid , err = validateString ( target . aot , label .. ".aot" )
if not valid then
return nil , err
end
if target . aot ~= "off"
and target . aot ~= "require"
and target . aot ~= "emit-wasm"
and target . aot ~= "require-wasm"
then
return nil , label .. ".aot must be \"off\", \"require\", \"emit-wasm\" or \"require-wasm\""
end
if ( target . aot == "emit-wasm" or target . aot == "require-wasm" )
and target . aotTarget ~= nil
and target . aotTarget ~= "wasm32-unknown-emscripten"
then
return nil , label .. ".aot = \"" .. target . aot .. "\" fixes aotTarget to wasm32-unknown-emscripten"
end
end
if target . aotLinkage ~= nil then
local valid , err = validateString ( target . aotLinkage , label .. ".aotLinkage" )
if not valid then
return nil , err
end
if target . aotLinkage ~= "shared" and target . aotLinkage ~= "static" then
return nil , label .. ".aotLinkage must be \"shared\" or \"static\""
end
if target . aotLinkage == "static" and kind ~= "component" and not target . standalone then
return nil , label .. ".aotLinkage = \"static\" requires a component or standalone binary target"
end
if target . aotLinkage == "shared" and target . standalone then
return nil , label .. ".standalone requires aotLinkage = \"static\""
end
end
if target . aotTarget ~= nil then



local valid , err = validateString ( target . aotTarget , label .. ".aotTarget" )
if not valid then
return nil , err
end
local _ , targetErr = aotTargets . select ( target . aotTarget , nil )
if targetErr ~= nil then
return nil , label .. ".aotTarget: " .. tostring ( targetErr )
end



if target . aot == "require"
and target . aotLinkage ~= "static"
and ( target . aotTarget ) : match ( "^wasm32%-" ) ~= nil
then
return nil , label .. ".aot = \"require\" links a native library, and " .. tostring (
target . aotTarget
) .. " has none: use \"emit-wasm\" or \"require-wasm\""
end
end
if target . aotFeatures ~= nil then






if type ( target . aotFeatures ) ~= "table" then
return nil , label .. ".aotFeatures must be a table of minimum and maximum tiers"
end
local valid , err = validateKeys ( target . aotFeatures , { "minimum" , "maximum" } , label .. ".aotFeatures" )
if not valid then
return nil , err
end
if target . aotFeatures . minimum == nil and target . aotFeatures . maximum == nil then
return nil , label .. ".aotFeatures needs a minimum, a maximum, or both"
end
if target . aotFeatures . minimum ~= nil then
valid , err = validateString ( target . aotFeatures . minimum , label .. ".aotFeatures.minimum" )
if not valid then
return nil , err
end
end
if target . aotFeatures . maximum ~= nil then
valid , err = validateString ( target . aotFeatures . maximum , label .. ".aotFeatures.maximum" )
if not valid then
return nil , err
end
end
local featureTarget = ( target . aot == "emit-wasm" or target . aot == "require-wasm" )
and "wasm32-unknown-emscripten"
or target . aotTarget
local _ , tierErr = aotTargets . buildTiers ( featureTarget , target . aotFeatures )
if tierErr ~= nil then
return nil , label .. ".aotFeatures: " .. tostring ( tierErr )
end
end
local valid , err = validateArray (
target . entries ,
label .. ".entries" ,
"string" ,
kind == "bundle" or kind == "binary" or kind == "component"
)
if not valid then
return nil , err
end
if target . output ~= nil then
valid , err = validateString ( target . output , label .. ".output" )
if not valid then
return nil , err
end
end
if target . payloadOutput ~= nil then
if kind ~= "binary" then
return nil , label .. ".payloadOutput is only valid for a binary target"
end
valid , err = validateString ( target . payloadOutput , label .. ".payloadOutput" )
if not valid then
return nil , err
end
if target . payloadOutput == target . output then
return nil , label .. ".payloadOutput must differ from output"
end
if target . platforms ~= nil and # target . platforms > 1 then
return nil , label .. ".payloadOutput cannot name several platform payloads"
end
end
valid , err = validateArray ( target . exports , label .. ".exports" , "string" )
if not valid then
return nil , err
end
if target . exports ~= nil and kind ~= "component" then
return nil , label .. ".exports is only valid for a component target"
end
local seenExports = { }
for index , export in ipairs ( target . exports or { } ) do
if not export : match ( "^[%a_][%w_%.]*%.[%a_][%w_]*$" ) then
return nil , label .. ".exports[" .. index .. "] must name a dotted module function"
end
if seenExports [ export ] then
return nil , label .. ".exports[" .. index .. "] duplicates " .. export
end
seenExports [ export ] = true
end
valid , err = validateArray ( target . sources , label .. ".sources" , "string" , kind == "docs" )
if not valid then
return nil , err
end
if target . format ~= nil and target . format ~= "site" and target . format ~= "markdown" and target . format ~= "both" then
return nil , label .. ".format must be \"site\", \"markdown\", or \"both\""
end
if target . title ~= nil and type ( target . title ) ~= "string" then
return nil , label .. ".title must be a string"
end
if target . resources ~= nil then
if type ( target . resources ) ~= "table" then
return nil , label .. ".resources must be an array"
end
for index , resource in ipairs ( target . resources ) do
if type ( resource ) == "string" then
valid , err = validateString ( resource , label .. ".resources[" .. index .. "]" )
elseif type ( resource ) == "table" then
valid , err = validateString ( resource . source , label .. ".resources[" .. index .. "].source" )
if valid then
valid , err = validateString ( resource . output , label .. ".resources[" .. index .. "].output" )
end
if valid
and ( resource . output : sub ( 1 , 1 ) == "/" or ( "/" .. resource . output .. "/" ) : find ( "/../" , 1 , true ) )
then
valid , err = nil , label .. ".resources[" .. index .. "].output must stay inside the target"
end
else
valid , err = nil , label .. ".resources[" .. index .. "] must be a string or resource table"
end
if not valid then
return nil , err
end
end
end
valid , err = validateArray ( target . dependencies , label .. ".dependencies" , "string" )
if not valid then
return nil , err
end
for _ , name in ipairs ( target . dependencies or { } ) do
if type ( dependencies [ name ] ) ~= "table" then
return nil , label .. ".dependencies references unknown dependency " .. name
end
end
valid , err = validateArray ( target . compileDependencies , label .. ".compileDependencies" , "string" )
if not valid then
return nil , err
end
for _ , name in ipairs ( target . compileDependencies or { } ) do
if type ( dependencies [ name ] ) ~= "table" then
return nil , label .. ".compileDependencies references unknown dependency " .. name
end
end
if kind == "docs" then
valid , err = validateDocsTarget ( target , label )
if not valid then
return nil , err
end
end

return true
end






local ROCK_STRINGS = { "rock" , "version" , "rockspec" , "path" , "tree" , "luaVersion" , "server" , "luaDir" , "luarocks" }

local function validateRock ( dep , label ) 
for _ , field in ipairs ( ROCK_STRINGS ) do
if dep [ field ] ~= nil then
local valid , err = validateString ( dep [ field ] , label .. "." .. field )
if not valid then
return nil , err
end
end
end
if dep . version == nil and dep . rockspec == nil and dep . path == nil then
return nil , label .. " must pin the rock: give a version, a rockspec, or a path to build it from"
end



local valid , err = validateArray ( dep . bundle , label .. ".bundle" , "string" )
if not valid then
return nil , err
end
if dep . rockDependencies ~= nil and type ( dep . rockDependencies ) ~= "boolean" then
return nil , label .. ".rockDependencies must be a boolean"
end



if # ( dep . dependencies or { } ) > 0 then
return nil , label .. ".dependencies is not for a rock: LuaRocks resolves what a rock depends on"
end

return true
end

local LINT_LEVELS = { off = true , note = true , warning = true , error = true }



local FMT_KEYS = { "methodParens" }



local function validateTargetReference ( build , value , label ) 
local valid , err = validateString ( value , label )
if not valid then
return nil , err
end
if not build or not build . targets then
return nil , label .. " requires build.targets"
end
if type ( build . targets [ value ] ) ~= "table" then
return nil , label .. " references unknown target " .. value
end

return true
end



local function validateEnv ( env , label ) 
if type ( env ) ~= "table" then
return nil , label .. " must be a table"
end
for key , value in pairs ( env ) do
if type ( key ) ~= "string" or type ( value ) ~= "string" then
return nil , label .. " keys and values must be strings"
end
end

return true
end

local function validateManifest ( config ) 
local _ , compatError = require ( "nupp.compiler.compat" ) . resolve ( config . compat )
if compatError then
return nil , compatError
end
local valid , err = validateArray ( config . include , "include" , "string" )
if not valid then
return nil , err
end


valid , err = validateKeys ( config , CONFIG_KEYS , "nupp.lua" )
if not valid then
return nil , err
end

if config . fmt ~= nil then
if type ( config . fmt ) ~= "table" then
return nil , "fmt must be a table"
end
valid , err = validateKeys ( config . fmt , FMT_KEYS , "fmt" )
if not valid then
return nil , err
end
if config . fmt . methodParens ~= nil and type ( config . fmt . methodParens ) ~= "boolean" then
return nil , "fmt.methodParens must be a boolean"
end
end



if config . lints ~= nil then
if type ( config . lints ) ~= "table" then
return nil , "lints must be a table"
end
for key , level in pairs ( config . lints ) do
if type ( key ) ~= "string" or key == "" then
return nil , "lint names must be non-empty strings"
end
if not LINT_LEVELS [ level ] then
return nil , ("lints.%s must be off, note, warning or error") : format ( key )
end
if not check . lintFor ( key ) and not check . lintCategories [ key ] then
return nil , ("lints.%s names no lint or category; see `nupp lints`") : format ( key )
end
end
end

local dependencies = config . dependencies or { }
if type ( dependencies ) ~= "table" then
return nil , "dependencies must be a table"
end
for name , dep in pairs ( dependencies ) do
if type ( name ) ~= "string" or name == "" then
return nil , "dependency names must be non-empty strings"
end
if type ( dep ) ~= "table" then
return nil , "dependencies." .. name .. " must be a table"
end
local kind = dep . kind or ""
if kind ~= "c" and kind ~= "cargo" and kind ~= "luarocks" and kind ~= "types" then
return nil , "dependencies." .. name .. ".kind must be \"c\", \"cargo\", \"luarocks\", or \"types\""
end
valid , err = validateKeys ( dep , DEPENDENCY_KEYS [ kind ] , "dependencies." .. name )
if not valid then
return nil , err
end
if dep . bindings ~= nil then
if type ( dep . bindings ) ~= "table" then
return nil , "dependencies." .. name .. ".bindings must be a table"
end
valid , err = validateKeys ( dep . bindings , BINDING_KEYS , "dependencies." .. name .. ".bindings" )
if not valid then
return nil , err
end
if dep . bindings . bridge ~= nil and type ( dep . bindings . bridge ) ~= "boolean" then
return nil , "dependencies." .. name .. ".bindings.bridge must be a boolean"
end
if dep . bindings . cbindgen ~= nil and type ( dep . bindings . cbindgen ) ~= "boolean" then
return nil , "dependencies." .. name .. ".bindings.cbindgen must be a boolean"
end
if dep . bindings . command ~= nil
and ( type ( dep . bindings . command ) ~= "string" or dep . bindings . command == "" )
then
return nil , "dependencies." .. name .. ".bindings.command must be a non-empty string"
end
valid , err = validateOwnership ( dep . bindings . ownership , "dependencies." .. name .. ".bindings.ownership" )
if not valid then
return nil , err
end
if dep . bindings . macros ~= nil then
if type ( dep . bindings . macros ) ~= "table" then
return nil , "dependencies." .. name .. ".bindings.macros must be a table"
end
for macro , recipe in pairs ( dep . bindings . macros ) do
local prefix = "dependencies." .. name .. ".bindings.macros." .. tostring ( macro )
if type ( macro ) ~= "string" or macro == "" or type ( recipe ) ~= "table" then
return nil , prefix .. " must name a signature table"
end
valid , err = validateKeys ( recipe , { "parameters" , "result" } , prefix )
if not valid then
return nil , err
end
if type ( recipe . parameters ) ~= "table" then
return nil , prefix .. ".parameters must be an array of strings"
end
valid , err = validateArray ( recipe . parameters , prefix .. ".parameters" , "string" )
if not valid then
return nil , err
end
if recipe . result ~= nil and type ( recipe . result ) ~= "string" then
return nil , prefix .. ".result must be a string"
end
end
end
end
valid , err = validateArray ( dep . dependencies , "dependencies." .. name .. ".dependencies" , "string" )
if not valid then
return nil , err
end
if dep . kind == "luarocks" then
valid , err = validateRock ( dep , "dependencies." .. name )
if not valid then
return nil , err
end
end
if dep . kind == "types" then
if dep . format ~= "luacats" then
return nil , "dependencies." .. name .. ".format must be \"luacats\""
end
if type ( dep . source ) ~= "table" or type ( dep . source . git ) ~= "string" or dep . source . git == "" then
return nil , "dependencies." .. name .. ".source.git must be a non-empty string"
end
if type ( dep . source . rev ) ~= "string"
or not dep . source . rev : match ( "^[0-9a-fA-F]+$" )
or # dep . source . rev < 40
then
return nil , "dependencies." .. name .. ".source.rev must be a full Git commit id"
end
if dep . path ~= nil and ( type ( dep . path ) ~= "string" or dep . path == "" ) then
return nil , "dependencies." .. name .. ".path must be a non-empty string"
end
end
for _ , child in ipairs ( dep . dependencies or { } ) do
if type ( dependencies [ child ] ) ~= "table" then
return nil , "dependencies." .. name .. ".dependencies references unknown dependency " .. child
end
end
if dep . pkgConfig ~= nil then
if type ( dep . pkgConfig ) == "string" then
if dep . pkgConfig == "" then
return nil , "dependencies." .. name .. ".pkgConfig must not be empty"
end
elseif type ( dep . pkgConfig ) == "table" then
local label = "dependencies." .. name .. ".pkgConfig"
valid , err = validateArray ( dep . pkgConfig , label , "string" , true )
if not valid then
return nil , err
end
for index , packageName in ipairs ( dep . pkgConfig ) do
if packageName == "" then
return nil , ("dependencies.%s.pkgConfig[%d] must be a non-empty string") : format ( name , index )
end
end
else
return nil , "dependencies." .. name .. ".pkgConfig must be a string or array of strings"
end
end
if dep . kind == "c"
and dep . linkage ~= nil
and dep . linkage ~= "shared"
and dep . linkage ~= "static"
and dep . linkage ~= "both"
then
return nil , "dependencies." .. name .. ".linkage must be \"shared\", \"static\", or \"both\""
end
if dep . kind == "c" and dep . staticOutput ~= nil then
if type ( dep . staticOutput ) ~= "string" or dep . staticOutput == "" then
return nil , "dependencies." .. name .. ".staticOutput must be a non-empty string"
end
if dep . linkage ~= "static" and dep . linkage ~= "both" then
return nil , "dependencies." .. name .. ".staticOutput requires linkage = \"static\" or \"both\""
end
end
if dep . kind == "c" and dep . artifacts ~= nil then
local artifactLabel = "dependencies." .. name .. ".artifacts"
if type ( dep . artifacts ) ~= "table" then
return nil , artifactLabel .. " must be a table keyed by target triple"
end
local layouts = require ( "nupp.compiler.targetlayout" )
for triple , artifactSet in pairs ( dep . artifacts ) do
local setLabel = artifactLabel .. "." .. tostring ( triple )
if type ( triple ) ~= "string" or not layouts . has ( triple ) then
return nil , artifactLabel .. " names unknown target " .. tostring ( triple )
end
if type ( artifactSet ) ~= "table" then
return nil , setLabel .. " must be a table"
end
valid , err = validateKeys ( artifactSet , NATIVE_ARTIFACT_SET_KEYS , setLabel )
if not valid then
return nil , err
end
if artifactSet . shared == nil and artifactSet . static == nil then
return nil , setLabel .. " must provide shared, static, or both"
end
for _ , artifactKind in ipairs ( { "shared" , "static" } ) do
local artifact = artifactSet [ artifactKind ]
if artifact ~= nil then
local oneLabel = setLabel .. "." .. artifactKind
if type ( artifact ) ~= "table" then
return nil , oneLabel .. " must be a table"
end
valid , err = validateKeys ( artifact , NATIVE_ARTIFACT_KEYS , oneLabel )
if not valid then
return nil , err
end
if type ( artifact . path ) ~= "string" or artifact . path == "" then
return nil , oneLabel .. ".path must be a non-empty string"
end
if type ( artifact . sha256 ) ~= "string"
or not artifact . sha256 : match ( "^[0-9a-f][0-9a-f]+$" )
or # artifact . sha256 ~= 64
then
return nil , oneLabel .. ".sha256 must be a lowercase SHA-256"
end
if type ( artifact . size ) ~= "number"
or artifact . size < 1
or artifact . size ~= math . floor ( artifact . size )
then
return nil , oneLabel .. ".size must be a positive integer"
end
end
end
end
end
end

local visiting , visited = { } , { }

local function visit ( name ) 
if visiting [ name ] then
return nil , "dependency cycle involving " .. name
end
if visited [ name ] then
return true
end
visiting [ name ] = true
for _ , child in ipairs ( ( dependencies [ name ] ) . dependencies or { } ) do
local ok , cycleErr = visit ( child )
if not ok then
return nil , cycleErr
end
end
visiting [ name ] , visited [ name ] = nil , true

return true
end

for name in pairs ( dependencies ) do
valid , err = visit ( name )
if not valid then
return nil , err
end
end

local generators = config . generators or { }
if type ( generators ) ~= "table" then
return nil , "generators must be a table"
end
for name , generator in pairs ( generators ) do
local label = "generators." .. tostring ( name )
if type ( name ) ~= "string" or not name : match ( "^[A-Za-z0-9][A-Za-z0-9_-]*$" ) then
return nil , "generator names must contain only letters, digits, underscores, and hyphens"
end
if type ( generator ) ~= "table" then
return nil , label .. " must be a table"
end
valid , err = validateKeys ( generator , GENERATOR_KEYS , label )
if not valid then
return nil , err
end
valid , err = validateString ( generator . using , label .. ".using" )
if not valid then
return nil , err
end
local dependencyName , providerName = generator . using : match ( "^([A-Za-z0-9_-]+)/([A-Za-z0-9_-]+)$" )
if not dependencyName or not providerName then
return nil , label .. ".using must be dependency/provider"
end
local dependency = dependencies [ dependencyName ]
if type ( dependency ) ~= "table" then
return nil , label .. ".using references unknown dependency " .. dependencyName
end
if ( dependency ) . kind ~= "luarocks" then
return nil , label .. ".using requires a luarocks dependency"
end
if generator . description ~= nil then
valid , err = validateString ( generator . description , label .. ".description" )
if not valid then
return nil , err
end
end
valid , err = validateArray ( generator . inputs , label .. ".inputs" , "string" )
if not valid then
return nil , err
end
for index , input in ipairs ( generator . inputs or { } ) do
if input == "" then
return nil , label .. ".inputs[" .. index .. "] must be a non-empty string"
end
end
if generator . options ~= nil then
if type ( generator . options ) ~= "table" then
return nil , label .. ".options must be a table"
end
valid , err = validatePlainData ( generator . options , label .. ".options" )
if not valid then
return nil , err
end
end
end

if config . build ~= nil and type ( config . build ) ~= "table" then
return nil , "build must be a table"
end
local build = config . build
if build then


if build . targets ~= nil then
valid , err = validateKeys ( build , BUILD_KEYS , "build" )
if not valid then
return nil , err
end
end
if build . outDir ~= nil then
valid , err = validateString ( build . outDir , "build.outDir" )
if not valid then
return nil , err
end
end
if build . targets ~= nil then
if type ( build . targets ) ~= "table" then
return nil , "build.targets must be a table"
end
local targetCount = 0
for name , target in pairs ( build . targets ) do
targetCount = targetCount + 1
if type ( name ) ~= "string" or name == "" then
return nil , "build target names must be non-empty strings"
end
if type ( target ) ~= "table" then
return nil , "build.targets." .. name .. " must be a table"
end
local effective = { }
for key , value in pairs ( build ) do
if key ~= "targets" and key ~= "default" then
effective [ key ] = value
end
end
for key , value in pairs ( target ) do
effective [ key ] = value
end
valid , err = validateTarget ( effective , "build.targets." .. name , dependencies )
if not valid then
return nil , err
end
end
if targetCount == 0 then
return nil , "build.targets must not be empty"
end
if build . default ~= nil then
valid , err = validateString ( build . default , "build.default" )
if not valid then
return nil , err
end
if type ( build . targets [ build . default ] ) ~= "table" then
return nil , "build.default references unknown target " .. build . default
end
end
else
if build . default ~= nil then
return nil , "build.default requires build.targets"
end
valid , err = validateTarget ( build , "build" , dependencies )
if not valid then
return nil , err
end
end
end

if config . test ~= nil then
if type ( config . test ) ~= "table" then
return nil , "test must be a table"
end
if not build then
return nil , "test requires build configuration"
end
valid , err = validateKeys ( config . test , TEST_KEYS , "test" )
if not valid then
return nil , err
end
valid , err = validateArray ( config . test . argv , "test.argv" , "string" , false )
if not valid then
return nil , err
end
if config . test . build ~= nil then
valid , err = validateTargetReference ( build , config . test . build , "test.build" )
if not valid then
return nil , err
end
end
if config . test . env ~= nil then
local envOk , envErr = validateEnv ( config . test . env , "test.env" )
if not envOk then
return nil , envErr
end
end
end
if config . tasks ~= nil then
if type ( config . tasks ) ~= "table" then
return nil , "tasks must be a table"
end
for name , task in pairs ( config . tasks ) do
if type ( name ) ~= "string" or name == "" then
return nil , "task names must be non-empty strings"
end
local label = "tasks." .. name
if type ( task ) ~= "table" then
return nil , label .. " must be a table"
end
valid , err = validateKeys ( task , TASK_KEYS , label )
if not valid then
return nil , err
end
valid , err = validateArray ( task . argv , label .. ".argv" , "string" , true )
if not valid then
return nil , err
end
if task . description ~= nil then
valid , err = validateString ( task . description , label .. ".description" )
if not valid then
return nil , err
end
end




if task . build ~= nil then
valid , err = validateTargetReference ( build , task . build , label .. ".build" )
if not valid then
return nil , err
end
end
if task . cwd ~= nil then
valid , err = validateString ( task . cwd , label .. ".cwd" )
if not valid then
return nil , err
end
end
if task . env ~= nil then
local envOk , envErr = validateEnv ( task . env , label .. ".env" )
if not envOk then
return nil , envErr
end
end
end
end
if config . selfHost ~= nil then
if type ( config . selfHost ) ~= "table" then
return nil , "selfHost must be a table"
end
if not build then
return nil , "selfHost requires build configuration"
end
valid , err = validateKeys ( config . selfHost , SELF_HOST_KEYS , "selfHost" )
if not valid then
return nil , err
end
if config . selfHost . target ~= nil then
valid , err = validateTargetReference ( build , config . selfHost . target , "selfHost.target" )
if not valid then
return nil , err
end
end
if config . selfHost . bootstrapTarget ~= nil then
valid , err = validateTargetReference ( build , config . selfHost . bootstrapTarget , "selfHost.bootstrapTarget" )
if not valid then
return nil , err
end
end
if config . selfHost . bootstrap ~= nil then
valid , err = validateString ( config . selfHost . bootstrap , "selfHost.bootstrap" )
if not valid then
return nil , err
end
end
end

return true
end






function manifest . load ( root ) 
root = root or "."
local path = join ( root , "nupp.lua" )
local chunk , loadErr = loadfile ( path )
if not chunk then
return nil , "nupp: cannot load " .. path .. ": " .. tostring ( loadErr )
end
local ok , config = pcall ( chunk )
if not ok then
return nil , "nupp: " .. path .. ": " .. tostring ( config )
end
if type ( config ) ~= "table" then
return nil , "nupp: " .. path .. " must return a table"
end
local valid , err = validateManifest ( config )
if not valid then
return nil , "nupp: " .. tostring ( err )
end

return config
end

local __nuppExportValue= manifest ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.manifest"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.manifest"]=__nuppExports;return __nuppExports