_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);









local check = require ( "nupp.compiler.check" )
local fs = require ( "nupp.compiler.fs" )
local native = require ( "nupp.compiler.native" )

local join = fs . join

local manifest = { }





































































































































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
"all" ,
"pages" ,
"constructorPattern" ,
"diagnostics" ,
"stdlib" ,

"kind" ,
"dependencies" ,
"entries" ,
"resources" ,
"output" ,
"stub" ,
"platforms" ,
"platformOutputs" ,
"nativeFeatures" ,
"layoutTarget" ,
}

local PAGE_KEYS = {
"path" ,
"title" ,
"source" ,
"layout" ,
"redirects" ,
"heroTitle" ,
"heroText" ,
"heroContent" ,
"heroImage" ,
"heroImageAlt" ,
"heroActions" ,

"hero_title" ,
"hero_text" ,
"hero_content" ,
"hero_image" ,
"hero_image_alt" ,
"hero_actions" ,
"features" ,
}



local GENERATED_KEYS = { "path" , "title" }

local HERO_ACTION_KEYS = { "text" , "path" , "theme" }
local FEATURE_KEYS = { "icon" , "image" , "imageAlt" , "title" , "details" , "code" , "codeLanguage" }
local TASK_KEYS = { "description" , "argv" , "build" , "env" }








local CONFIG_KEYS = { "name" , "include" , "fmt" , "lints" , "dependencies" , "build" , "test" , "tasks" , "selfHost" , "docs" }



local TARGET_KEYS = {
"kind" ,
"description" ,
"outDir" ,
"output" ,
"stub" ,
"platforms" ,
"platformOutputs" ,
"entries" ,
"sources" ,
"resources" ,
"dependencies" ,
"nativeFeatures" ,
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
local SELF_HOST_KEYS = { "target" , "bootstrap" , "binary" }





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
"out" ,
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
"out" ,
"load" ,
"header" ,
"bindings"
} ,
cargo = CARGO_KEYS ,
rust = CARGO_KEYS ,
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
"bundle"
} ,
}


local BINDING_KEYS = { "header" , "library" , "out" }

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
return nil , ( "%s has no key %q; did you mean %q?" ) : format ( label , key , suggestion )
end

return nil , ( "%s has no key %q" ) : format ( label , key )
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
local pageLabel = ( "%s.pages[%d]" ) : format ( label , index )
if type ( page ) ~= "table" then
return nil , pageLabel .. " must be a table"
end
valid , err = validateKeys ( page , PAGE_KEYS , pageLabel )
if not valid then
return nil , err
end
for actionIndex , action in ipairs ( page . heroActions or page . hero_actions or { } ) do
valid , err = validateKeys ( action , HERO_ACTION_KEYS , ( "%s.heroActions[%d]" ) : format ( pageLabel , actionIndex ) )
if not valid then
return nil , err
end
end
for featureIndex , feature in ipairs ( page . features or { } ) do
valid , err = validateKeys ( feature , FEATURE_KEYS , ( "%s.features[%d]" ) : format ( pageLabel , featureIndex ) )
if not valid then
return nil , err
end
end
end

return true
end

local function validateTarget ( target , label , dependencies )
if type ( target ) ~= "table" then
return nil , label .. " must be a table"
end
local kind = target . kind or "modules"
if kind ~= "modules" and kind ~= "docs" and kind ~= "bundle" and kind ~= "binary" then
return nil , label .. ".kind must be \"modules\", \"bundle\", \"binary\", or \"docs\""
end
if kind ~= "docs" then
local valid , err = validateKeys ( target , TARGET_KEYS , label )
if not valid then
return nil , err
end
end
if kind == "binary" and target . stub == nil then
return nil , label
.. ".stub is required for a binary target: it names "
.. "the executable the payload is stamped into"
end
if target . stub ~= nil then
local valid , err = validateString ( target . stub , label .. ".stub" )
if not valid then
return nil , err
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
local distribution = require ( "nupp.compiler.build.platform" )
local layouts = require ( "nupp.compiler.target_layout" )
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
local layouts = require ( "nupp.compiler.target_layout" )
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
if target . outDir ~= nil then
local valid , err = validateString ( target . outDir , label .. ".outDir" )
if not valid then
return nil , err
end
end
local valid , err = validateArray (
target . entries ,
label .. ".entries" ,
"string" ,
kind == "modules" or kind == "bundle" or kind == "binary"
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
if valid and (
resource . output : sub ( 1 , 1 ) == "/" or ( "/" .. resource . output .. "/" ) : find ( "/../" , 1 , true )
) then
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
return nil , label .. " must pin the rock: give a version, a rockspec, " .. "or a path to build it from"
end



local valid , err = validateArray ( dep . bundle , label .. ".bundle" , "string" )
if not valid then
return nil , err
end



if # ( dep . dependencies or { } ) > 0 then
return nil , label .. ".dependencies is not for a rock: LuaRocks " .. "resolves what a rock depends on"
end

return true
end

local LINT_LEVELS = { off = true , note = true , warning = true , error = true }



local FMT_KEYS = { "methodParens" }

local function validateManifest ( config )
local valid , err = validateArray ( config . include , "include" , "string" )
if not valid then
return nil , err
end




if config . strict ~= nil then
return nil , "strict is no longer a manifest key: a file's extension "
.. "decides its floor, so `.nupp` is strict and `.g.nupp` is not. "
.. "Rename the files that are not ready, or pass --strict to hold "
.. "every file to it regardless"
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
return nil , ( "lints.%s must be off, note, warning or error" ) : format ( key )
end
if not check . lintFor ( key ) and not check . lintCategories [ key ] then
return nil , ( "lints.%s names no lint or category; " .. "see `nupp lints`" ) : format ( key )
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
if kind ~= "c" and kind ~= "cargo" and kind ~= "rust" and kind ~= "luarocks" then
return nil , "dependencies." .. name .. ".kind must be \"c\", \"cargo\", \"rust\", or \"luarocks\""
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
for _ , child in ipairs ( dep . dependencies or { } ) do
if type ( dependencies [ child ] ) ~= "table" then
return nil , "dependencies." .. name .. ".dependencies references unknown dependency " .. child
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
valid , err = validateArray ( config . test . argv , "test.argv" , "string" , true )
if not valid then
return nil , err
end
if config . test . build ~= nil then
valid , err = validateString ( config . test . build , "test.build" )
if not valid then
return nil , err
end
if not build . targets then
return nil , "test.build requires build.targets"
end
if type ( build . targets [ config . test . build ] ) ~= "table" then
return nil , "test.build references unknown target " .. config . test . build
end
end
if config . test . env ~= nil then
if type ( config . test . env ) ~= "table" then
return nil , "test.env must be a table"
end
for key , value in pairs ( config . test . env ) do
if type ( key ) ~= "string" or type ( value ) ~= "string" then
return nil , "test.env keys and values must be strings"
end
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
valid , err = validateString ( task . build , label .. ".build" )
if not valid then
return nil , err
end
if not build or not build . targets then
return nil , label .. ".build requires build.targets"
end
if type ( build . targets [ task . build ] ) ~= "table" then
return nil , label .. ".build references unknown target " .. task . build
end
end
if task . env ~= nil then
if type ( task . env ) ~= "table" then
return nil , label .. ".env must be a table"
end
for key , value in pairs ( task . env ) do
if type ( key ) ~= "string" or type ( value ) ~= "string" then
return nil , label .. ".env keys and values must be strings"
end
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
valid , err = validateString ( config . selfHost . target , "selfHost.target" )
if not valid then
return nil , err
end
if not build . targets then
return nil , "selfHost.target requires build.targets"
end
if type ( build . targets [ config . selfHost . target ] ) ~= "table" then
return nil , "selfHost.target references unknown target " .. config . selfHost . target
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

manifest . validate = validateManifest

return manifest
