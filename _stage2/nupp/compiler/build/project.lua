_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local function __nuppLoadJSON()local source=require("cjson");local aliases={EMPTY_ARRAY="empty_array",ARRAY_MT="array_mt",EMPTY_ARRAY_MT="empty_array_mt",encodeEmptyTableAsObject="encode_empty_table_as_object",decodeArrayWithArrayMt="decode_array_with_array_mt",encodeSparseArray="encode_sparse_array",encodeMaxDepth="encode_max_depth",decodeMaxDepth="decode_max_depth",encodeNumberPrecision="encode_number_precision",encodeKeepBuffer="encode_keep_buffer",encodeInvalidNumbers="encode_invalid_numbers",decodeInvalidNumbers="decode_invalid_numbers",encodeEscapeForwardSlash="encode_escape_forward_slash"};local function adopt(target,json)target.encodeJSON=json.encode;target.decodeJSON=json.decode;target.NULL=json.null;for public,name in pairs(aliases)do target[public]=json[name]end;return target end;local json=adopt({},source);json.newJSON=function()return adopt({},source.new())end;return json end __nuppLazy(__nuppData,"json",__nuppLoadJSON);








local envMod = require ( "nupp.compiler.env" )
local hash = require ( "nupp.compiler.build.hash" )
local json = require ( "cjson" ) . new ( )
local process = require ( "nupp.compiler.build.process" )
local fs = require ( "nupp.compiler.fs" )
local cache = require ( "nupp.compiler.build.cache" )
local manifest = require ( "nupp.compiler.build.manifest" )
local tasks = require ( "nupp.compiler.build.tasks" )
local deps = require ( "nupp.compiler.build.deps" )
local modules = require ( "nupp.compiler.build.modules" )
local packaging = require ( "nupp.compiler.build.package" )
local storeMod = require ( "nupp.compiler.build.store" )
local native = require ( "nupp.compiler.build.native" )
local nativeFeatures = require ( "nupp.compiler.native" )
local materializeObserve = require ( "nupp.compiler.materialize.observe" )
local progressMod = require ( "nupp.compiler.build.progress" )

local project = { }





































































































local CHECK_STATE_STAMP = "checks/1"

local normalize , join = fs . normalize , fs . join
local readFile , writeFile = fs . readFile , fs . writeFile
local copyFile , listFiles = fs . copyFile , fs . listFiles
local stable , hashFile = cache . stable , cache . hashFile
local loadState , saveState = cache . loadState , cache . saveState
local toolFingerprint = cache . toolFingerprint
local targetConfig = tasks . targetConfig
local buildDependencies = deps . build
local buildModules = modules . build
local bundleText , bundleOutput = packaging . bundleText , packaging . bundleOutput
local binaryOutput = packaging . binaryOutput
local stampFile = packaging . stampFile


project . loadManifest = manifest . load


project . describeTasks = tasks . describe

project . encodeJson = tasks . encodeJson

json . decode_array_with_array_mt ( true )
json . decode_invalid_numbers ( false )
json . encode_empty_table_as_object ( true )
json . encode_invalid_numbers ( false )

local function buildOne ( root , opts )
root , opts = root or "." , ( opts or { } )







local report = progressMod . new ( opts . checkOnly and "never" or opts . progress )
local config , loadErr = project . loadManifest ( root )
if not config then
io . stderr : write ( tostring ( loadErr ) .. "\n" ) ;
return 1
end


local strict = opts . strict
local target , targetErr = targetConfig ( config , opts . target )
if not target then
io . stderr : write ( "nupp: " .. tostring ( targetErr ) .. "\n" ) ;
return 1
end
local selectedPlatform = opts . platform
if target . platforms then
if selectedPlatform == nil then
if # target . platforms == 1 then
selectedPlatform = target . platforms [ 1 ]
else
io . stderr : write (
"nupp: binary target " .. tostring (
target . name or opts . target or "default"
) .. " configures several platforms; select one with --platform or use --platform all\n"
)
return 1
end
end
local configured = false
for _ , name in ipairs ( target . platforms ) do
configured = configured or name == selectedPlatform
end
if not configured then
io . stderr : write (
"nupp: platform " .. tostring (
selectedPlatform
) .. " is not configured on binary target " .. tostring ( target . name or opts . target or "default" ) .. "\n"
)
return 1
end
target . layoutTarget = selectedPlatform
elseif selectedPlatform ~= nil then
io . stderr : write (
"nupp: --platform requires a binary target with a platforms list; target " .. tostring (
target . name or opts . target or "default"
) .. " has none\n"
)
return 1
end
if selectedPlatform and not opts . checkOnly then
local record , recordErr = require ( "nupp.compiler.build.stubs" ) . record ( selectedPlatform )
if not record then
io . stderr : write ( "nupp: " .. tostring ( recordErr ) .. "\n" )
return 1
end
target . _stubRecord = record
config . _stubCatalogRelease = record . catalogRelease
config . _stubSha256 = record . sha256
end
config . _target = target
config . _platform = selectedPlatform
config . _strict = strict and true or false



config . _optLevel = opts . optLevel or 0
config . _remarks = opts . remarks and true or false
config . _disabledPasses = opts . disabled or { }
config . _relaxedGuarantees = opts . relaxed or { }


config . _coverage = opts . coverage == true
if target . kind == "docs" then




local installed , depErr = buildDependencies (
root ,
normalize ( opts . outDir or target . outDir or "build" ) ,
config ,
{ } ,
target
)
if not installed then
io . stderr : write ( "nupp: " .. tostring ( depErr ) .. "\n" )
return 1
end
return ( require ( "nupp.compiler.doc" ) . build ( root , config , target , {
checkOnly = opts . checkOnly ,
output = opts . outDir ,
} ) )
elseif target . kind and target . kind ~= "modules" and target . kind ~= "bundle" and target . kind ~= "binary" then



io . stderr : write ( "nupp: unsupported build target kind " .. tostring ( target . kind ) .. "\n" )
return 1
end
local outDir = normalize ( opts . outDir or target . outDir or "build" )
local completionPath = join ( root , join ( outDir , ".nupp-complete" ) )
if not opts . checkOnly then
os . remove ( completionPath )
end





local statePath = join ( root , join ( outDir , ".nupp-state.json" ) )
local checkState = nil
local oldState
if opts . checkOnly then
checkState = storeMod . openValue ( join ( root , join ( outDir , "cache/checks.buf" ) ) , CHECK_STATE_STAMP )
oldState = checkState . value or cache . emptyState ( )
oldState . targets = oldState . targets or { }
oldState . dependencies = oldState . dependencies or { }
else
oldState = loadState ( statePath )
end
local newState = cache . emptyState ( )
newState . compilerHash = toolFingerprint ( )
newState . configHash = hash . digest ( stable ( config ) )


for name , produced in pairs ( oldState . targets ) do
newState . targets [ name ] = produced
end
local targetKey = target . name or opts . target or "default"
if selectedPlatform then
targetKey = targetKey .. "@" .. selectedPlatform
end
report : at ( "dependencies" )
report : step ( "resolving dependencies" )
local dependencies , depErr = buildDependencies ( root , outDir , config , oldState . dependencies )
report : clear ( )
if not dependencies then
io . stderr : write ( "nupp: " .. tostring ( depErr ) .. "\n" ) ;
return 1
end
newState . dependencies = dependencies
local result , buildErr = buildModules (
root ,
outDir ,
config ,
target ,
oldState ,
newState ,
opts . checkOnly ,
strict ,
opts . stats ,
opts . diagnostics ,
checkState ,
opts . paths and { paths = opts . paths , unchecked = opts . unchecked or { } , } or nil ,
report
)


report : clear ( )
if not result then
if buildErr ~= "project has errors" and buildErr ~= "code generation failed" then
io . stderr : write ( "nupp: " .. tostring ( buildErr ) .. "\n" )
end
return 1
end
if opts . checkOnly then
if opts . produced then
opts . produced . target = target . name or opts . target or "default"
opts . produced . platform = selectedPlatform
opts . produced . outputs = cache . jsonArray ( { } )
end
return 0
end
for output in pairs ( result . outputs ) do
newState . outputs [ output ] = true
end
local detectedEffects = native . dependencyEffects ( root , config , target , result . effects )
local resolvedEffects = native . resolve ( detectedEffects , target . nativeFeatures )
if resolvedEffects [ "native.workers" ] and ( target . kind ~= "binary" or target . stub ~= "nupp" ) then
io . stderr : write (
"nupp: workers currently require a binary target with stub = \"nupp\"; "
.. "the compiler-owned host supplies the isolated Lua states and early machine-code arena\n"
)
return 1
end
if target . kind == "bundle" and next ( resolvedEffects ) then
io . stderr : write (
"nupp: a one-file bundle cannot carry native features; "
.. "build modules or use a binary target with its lib directory\n"
)
return 1
end
report : at ( "native" )
report : step ( "building native providers" )
local nativeOutputs , nativeErr = native . build ( root , outDir , resolvedEffects , selectedPlatform )
report : clear ( )
if not nativeOutputs then
io . stderr : write ( "nupp: " .. tostring ( nativeErr ) .. "\n" )
return 1
end
for output in pairs ( nativeOutputs ) do
newState . outputs [ output ] = true
end


if target . kind == "bundle" or target . kind == "binary" then
report : at ( "bundle" )
report : step ( "bundling " .. ( target . name or target . kind ) )
local runtimeModules = { }
local requiredHostFeatures = { }
for _ , feature in ipairs ( nativeFeatures . features ( resolvedEffects ) ) do
if feature . runtimeModule then
runtimeModules [ # runtimeModules + 1 ] = feature . runtimeModule
end
if feature . host then
requiredHostFeatures [ # requiredHostFeatures + 1 ] = feature . host
end
end
table . sort ( runtimeModules )
table . sort ( requiredHostFeatures )
local text , bundleErr , unreachable = bundleText (
root ,
config ,
target ,
nil ,
newState . modules ,
resolvedEffects [ "native.workers" ] == true ,
runtimeModules ,
target . kind == "binary" and target . stub == "nupp" and requiredHostFeatures or nil
)
if not text then
io . stderr : write ( "nupp: " .. tostring ( bundleErr ) .. "\n" )
return 1
end
if unreachable and # unreachable > 0 then
io . stderr : write (
(
"nupp: %d resource%s could not be bundled, "
.. "starting at %s: a bundle can only carry what sits under "
.. "the entry module's directory\n"
) : format ( # unreachable , # unreachable == 1 and "" or "s" , unreachable [ 1 ] )
)
end
local name = target . name or opts . target or ( target . platforms and "default" ) or target . kind
local output
if target . kind == "binary" then
local stubPath , hostErr = native . hostStub ( root , outDir , target , resolvedEffects )
if not stubPath then
io . stderr : write ( "nupp: " .. tostring ( hostErr ) .. "\n" )
return 1
end
local resolvedStub = stubPath == target . stub and join ( root , stubPath ) or stubPath
local stub , stubErr = readFile ( resolvedStub )
if not stub then
io . stderr : write ( ( "nupp: cannot read the stub %s: %s\n" ) : format ( resolvedStub , tostring ( stubErr ) ) )
return 1
end
output = binaryOutput ( root , target , name , outDir , selectedPlatform )
local stamped , stampErr , archive = stampFile ( output , stub , text , selectedPlatform )
if not stamped then
io . stderr : write ( "nupp: " .. tostring ( stampErr ) .. "\n" )
return 1
end
if archive then
newState . outputs [ archive ] = true
end
else
output = bundleOutput ( root , target , name )
local written , writeErr = writeFile ( output , text )
if not written then
io . stderr : write ( "nupp: " .. tostring ( writeErr ) .. "\n" )
return 1
end
end
newState . outputs [ output ] = true
report : clear ( )
end
for _ , dep in pairs ( dependencies ) do
if dep . output then
newState . outputs [ dep . output ] = true
end
if dep . binding then
newState . outputs [ dep . binding ] = true
end
end




local mine = { }
for output in pairs ( newState . outputs ) do
mine [ # mine + 1 ] = output
end
table . sort ( mine )
for _ , output in ipairs ( oldState . targets [ targetKey ] or { } ) do
if not newState . outputs [ output ] then
os . remove ( output )
end
end
newState . targets [ targetKey ] = mine


if opts . produced then
opts . produced . target = target . name or opts . target or "default"
opts . produced . platform = selectedPlatform
if selectedPlatform == "aarch64-apple-darwin" then
opts . produced . distributionReady = false
opts . produced . notice = "the macOS binary must be signed on macOS and has not passed notarization"
end
opts . produced . outputs = mine
opts . produced . materializations = materializeObserve . public ( result . materializations )
opts . produced . derives = result . derives
end
report : at ( "write" )
local ok , stateErr = saveState ( statePath , newState )
if not ok then
io . stderr : write ( "nupp: " .. tostring ( stateErr ) .. "\n" ) ;
return 1
end
local completed , completionErr = writeFile ( completionPath , newState . compilerHash .. "\n" )
if not completed then
io . stderr : write ( "nupp: " .. tostring ( completionErr ) .. "\n" )
return 1
end
report : finish ( "built" , targetKey )


if opts . produced then
opts . produced . timing = report : timing ( )
end

return 0
end




function project . build ( root , opts )
root , opts = root or "." , ( opts or { } )
if opts . platform ~= "all" then
return buildOne ( root , opts )
end
local config , loadErr = project . loadManifest ( root )
if not config then
io . stderr : write ( tostring ( loadErr ) .. "\n" )
return 1
end
local target , targetErr = targetConfig ( config , opts . target )
if not target then
io . stderr : write ( "nupp: " .. tostring ( targetErr ) .. "\n" )
return 1
end
if not target . platforms then
io . stderr : write ( "nupp: --platform all requires a binary target with a platforms list\n" )
return 1
end
local aggregate = opts . produced
if aggregate then
aggregate . target = target . name or opts . target or "default"
aggregate . outputs = cache . jsonArray ( { } )
aggregate . platforms = cache . jsonArray ( { } )
end
local failed = false
for _ , selected in ipairs ( target . platforms ) do
local childOptions = { }
for key , value in pairs ( opts ) do
if key ~= "produced" then
childOptions [ key ] = value
end
end
childOptions . platform = selected
local produced = aggregate and { } or nil
childOptions . produced = produced
local code = buildOne ( root , childOptions )
failed = failed or code ~= 0
if aggregate then
local entry = {
platform = selected ,
status = code == 0 and "built" or "failed" ,
outputs = cache . jsonArray ( produced . outputs or { } ) ,
error = code == 0 and nil or "platform build failed; see diagnostics or standard error" ,
distributionReady = produced . distributionReady ,
notice = produced . notice ,
}
aggregate . platforms [ # aggregate . platforms + 1 ] = entry
for _ , output in ipairs ( produced . outputs or { } ) do
aggregate . outputs [ # aggregate . outputs + 1 ] = output
end
end
end
if aggregate then
table . sort ( aggregate . outputs )
end

return failed and 1 or 0
end

function project . check ( root , opts )
opts = ( opts or { } ) ;
opts . checkOnly = true
return project . build ( root , opts )
end

function project . test ( root , args , opts )
root = root or "."
local asked = opts or { }
local config , err = project . loadManifest ( root )
if not config then
io . stderr : write ( tostring ( err ) .. "\n" ) ;
return 1
end


local test = config . test
if type ( test ) ~= "table" or type ( test . argv ) ~= "table" then
io . stderr : write ( "nupp: test.argv is not configured\n" ) ;
return 1
end
if project . build ( root , { target = test . build , outDir = asked . outDir , coverage = asked . coverage } ) ~= 0 then
return 1
end
local argv = { }
for _ , item in ipairs ( test . argv ) do
argv [ # argv + 1 ] = item
end
for _ , item in ipairs ( args or { } ) do
argv [ # argv + 1 ] = item
end
local env = { }
for key , value in pairs ( test . env or { } ) do
env [ key ] = value
end
for key , value in pairs ( asked . env or { } ) do
env [ key ] = value
end




local rocks = deps . rockPaths ( root , config , ( targetConfig ( config , test . build ) ) )
if rocks then


env . LUA_PATH = rocks . path .. ";" .. ( env . LUA_PATH or os . getenv ( "LUA_PATH" ) or "" )
env . LUA_CPATH = rocks . cpath .. ";" .. ( env . LUA_CPATH or os . getenv ( "LUA_CPATH" ) or "" )
end

return process . run ( argv , { cwd = root , env = env } )
end






function project . runTask ( root , name , args )
root = root or "."
local config , err = project . loadManifest ( root )
if not config then
io . stderr : write ( tostring ( err ) .. "\n" ) ;
return 1
end
local tasks = config . tasks or { }


local task = tasks [ name ]
if type ( task ) ~= "table" or type ( task . argv ) ~= "table" then
io . stderr : write ( "nupp: no task named " .. tostring ( name ) .. "; see `nupp tasks`\n" )
return 1
end
if task . build then
if project . build ( root , { target = task . build } ) ~= 0 then
return 1
end
end
local argv = { }
for _ , item in ipairs ( task . argv or { } ) do
argv [ # argv + 1 ] = item
end
for _ , item in ipairs ( args or { } ) do
argv [ # argv + 1 ] = item
end
local env = task . env
if task . build then



local rocks = deps . rockPaths ( root , config , ( targetConfig ( config , task . build ) ) )
if rocks then
env = { }
for key , value in pairs ( task . env or { } ) do
env [ key ] = value
end
env . LUA_PATH = rocks . path .. ";" .. ( env . LUA_PATH or os . getenv ( "LUA_PATH" ) or "" )
env . LUA_CPATH = rocks . cpath .. ";" .. ( env . LUA_CPATH or os . getenv ( "LUA_CPATH" ) or "" )
end
end

return process . run ( argv , { cwd = root , env = env } )
end









local function treeDigest ( path )
local files , parts = listFiles ( path ) , { }
for _ , file in ipairs ( files ) do
local relative = file : sub ( # normalize ( path ) + 2 )
local native = relative : match ( "^native/" ) or relative : match ( "^lib/" )
if relative ~= ".nupp-state.json" and relative ~= ".nupp-complete" and not native then
parts [ # parts + 1 ] = relative .. "\0" .. ( hashFile ( file ) or "" )
end
end

return hash . digest ( table . concat ( parts , "\0" ) ) , files
end

local function removeTree ( path )
if os . remove ( path ) then
return 0
end
if package . config : sub ( 1 , 1 ) == "\\" then
return process . run ( { "cmd" , "/d" , "/c" , "if" , "exist" , path , "rmdir" , "/s" , "/q" , path } )
end

return process . run ( { "rm" , "-rf" , path } )
end

local function safeCleanPath ( path )
path = normalize ( path or "" )
if path == "" or path == "." or path : sub (
1 ,
1
) == "/" or path : match (
"^%a:"
) or path : find ( "%z" ) or path == ".." or path : match ( "^%.%./" ) or path : match ( "/%.%./" ) or path : match ( "/%.%.$" ) then
return nil , "unsafe build output path " .. tostring ( path )
end

return path
end

function project . clean ( root , opts )
root , opts = root or "." , ( opts or { } )
if opts . target then
local config , loadErr = project . loadManifest ( root )
if not config then
io . stderr : write ( tostring ( loadErr ) .. "\n" )
return 1
end
local target , targetErr = targetConfig ( config , opts . target )
if not target then
io . stderr : write ( "nupp: " .. tostring ( targetErr ) .. "\n" )
return 1
end
if target . platforms then
local selected = { }
if opts . platform == nil or opts . platform == "all" then
for _ , name in ipairs ( target . platforms ) do
selected [ # selected + 1 ] = name
end
else
for _ , name in ipairs ( target . platforms ) do
if name == opts . platform then
selected [ 1 ] = name
end
end
if # selected == 0 then
io . stderr : write (
"nupp: platform "
.. opts . platform
.. " is not configured on binary target "
.. opts . target
.. "\n"
)
return 1
end
end
local outDir = normalize ( target . outDir or "build" )
local candidates = { }
for _ , selectedPlatform in ipairs ( selected ) do
local raw = binaryOutput ( "." , target , target . name or opts . target , outDir , selectedPlatform )
candidates [ # candidates + 1 ] = raw
if require ( "nupp.compiler.build.platform" ) . isPosix ( selectedPlatform ) then
candidates [ # candidates + 1 ] = raw .. ".tar"
end
end
local collected = opts . removed
for _ , candidate in ipairs ( candidates ) do
local safe , safeErr = safeCleanPath ( candidate )
if not safe then
io . stderr : write ( "nupp: refusing to clean " .. safeErr .. "\n" )
return 1
end
if not opts . dryRun and removeTree ( join ( root , safe ) ) ~= 0 then
io . stderr : write ( "nupp: cannot remove build output " .. safe .. "\n" )
return 1
end
if collected then
collected [ # collected + 1 ] = safe
elseif opts . dryRun then
io . write ( "would remove " .. safe .. "\n" )
else
io . write ( "removed " .. safe .. "\n" )
end
end
if not opts . dryRun then
local statePath = join ( root , join ( outDir , ".nupp-state.json" ) )
if readFile ( statePath ) then
local state = loadState ( statePath )
for _ , selectedPlatform in ipairs ( selected ) do
state . targets [ ( target . name or opts . target ) .. "@" .. selectedPlatform ] = nil
end
local saved , saveErr = saveState ( statePath , state )
if not saved then
io . stderr : write ( "nupp: " .. tostring ( saveErr ) .. "\n" )
return 1
end
end
end
return 0
elseif opts . platform then
io . stderr : write ( "nupp: --platform requires a binary target with a platforms list\n" )
return 1
end
end
local described , err = project . describeTasks ( root , opts . target , { buildOnly = true } )
if not described then
io . stderr : write ( tostring ( err ) .. "\n" ) ;
return 1
end
local tasks = opts . target and { described } or described . tasks
local candidates = { }
for _ , task in ipairs ( tasks ) do
local path , pathErr = safeCleanPath ( task . outDir )
if not path then
io . stderr : write ( "nupp: refusing to clean " .. pathErr .. "\n" )
return 1
end
candidates [ path ] = true
end
local paths = { }
for path in pairs ( candidates ) do
paths [ # paths + 1 ] = path
end
table . sort ( paths )
local selected = { }
for _ , path in ipairs ( paths ) do
local covered = false
for _ , parent in ipairs ( selected ) do
if path == parent or path : sub ( 1 , # parent + 1 ) == parent .. "/" then
covered = true
break
end
end
if not covered then
selected [ # selected + 1 ] = path
end
end


local collected = opts . removed
for _ , path in ipairs ( selected ) do
if not opts . dryRun and removeTree ( join ( root , path ) ) ~= 0 then
io . stderr : write ( "nupp: cannot remove build output " .. path .. "\n" )
return 1
end
if collected then
collected [ # collected + 1 ] = path
elseif opts . dryRun then
io . write ( "would remove " .. path .. "\n" )
else
io . write ( "removed " .. path .. "\n" )
end
end

return 0
end











local function copyTree ( source , destination )
for _ , path in ipairs ( listFiles ( source ) ) do
local relative = path : sub ( # normalize ( source ) + 2 )
if relative ~= ".nupp-state.json" and relative ~= ".nupp-complete" and not relative : match ( "^native/" ) then
local ok , err = copyFile ( path , join ( destination , relative ) )
if not ok then
return nil , err
end
end
end

return true
end

function project . updateBootstrap ( root )
root = root or "."
local config , err = project . loadManifest ( root )
if not config then
return nil , err
end
local target = assert ( targetConfig ( config , config . selfHost and config . selfHost . target or nil ) )
local bootstrapPath = join ( root , config . selfHost and config . selfHost . bootstrap or "bootstrap/nupp.lua" )


local outDir = target . outDir or "build"
local state = loadState ( join ( root , join ( outDir , ".nupp-state.json" ) ) )
local text , bundleErr = bundleText (
root ,
config ,
target ,
"-- Generated stage-0 compiler. " .. "Update with: nupp fixpoint --update-bootstrap\n" ,
state and state . modules or nil
)
if not text then
return nil , bundleErr
end
local ok , writeErr = writeFile ( bootstrapPath , text )
if not ok then
return nil , writeErr
end

return true
end













function project . binaryFixpoint ( root , opts )
root = root or "."
local config , err = project . loadManifest ( root )
if not config then
io . stderr : write ( tostring ( err ) .. "\n" ) ;
return 1
end
local targetName = config . selfHost and config . selfHost . binary or nil
if not targetName then
io . stderr : write ( "nupp: selfHost.binary names no target to stamp\n" )
return 1
end
local target , targetErr = targetConfig ( config , targetName )
if not target then
io . stderr : write ( "nupp: " .. tostring ( targetErr ) .. "\n" )
return 1
end
if target . kind ~= "binary" then
io . stderr : write (
( "nupp: selfHost.binary names %s, which is a %s target\n" ) : format ( targetName , target . kind or "modules" )
)
return 1
end

if project . build ( root , { target = targetName } ) ~= 0 then
return 1
end
local outDir = target . outDir or "build"
local produced = join ( root , target . output or join ( outDir , targetName ) )
local first , readErr = readFile ( produced )
if not first then
io . stderr : write ( "nupp: " .. tostring ( readErr ) .. "\n" )
return 1
end




local stage1 = produced .. ".stage1"
local copied , copyErr = writeFile ( stage1 , first )
if not copied then
io . stderr : write ( "nupp: " .. tostring ( copyErr ) .. "\n" )
return 1
end
process . capture ( { "chmod" , "+x" , stage1 } )

if process . run ( { stage1 , "build" , "--target" , targetName } , { cwd = root } ) ~= 0 then
io . stderr : write ( "nupp: the stamped binary could not stamp one\n" )
return 1
end
local second , secondErr = readFile ( produced )
if not second then
io . stderr : write ( "nupp: " .. tostring ( secondErr ) .. "\n" )
return 1
end

if first ~= second then
io . stderr : write (
(
"nupp: packaging fixpoint mismatch: %d bytes then %d; " .. "%s kept for inspection\n"
) : format ( # first , # second , stage1 )
)
if opts and opts . result then
opts . result . reason = "the stamped binary stamped a different one"
end
return 1
end
os . remove ( stage1 )
if opts and opts . result then
opts . result . target , opts . result . bytes = targetName , # first
else
io . write (
(
"packaging fixpoint ok: %s stamps out a binary identical to " .. "itself (%d bytes)\n"
) : format ( targetName , # first )
)
end

return 0
end

function project . fixpoint ( root , opts )
root , opts = root or "." , ( opts or { } )
local config , err = project . loadManifest ( root )
if not config then
io . stderr : write ( tostring ( err ) .. "\n" ) ;
return 1
end
local targetName = config . selfHost and config . selfHost . target or nil
local stage1 , stage2 = "_stage1" , "_stage2"
removeTree ( join ( root , stage1 ) ) ;
removeTree ( join ( root , stage2 ) )
if project . build ( root , { target = targetName , outDir = stage1 } ) ~= 0 then
return 1
end
local target = assert ( targetConfig ( config , targetName ) )
local entry = ( target . entries or { } ) [ 1 ] or "nupp.compiler.main"
local moduleName = entry : match ( "%.nupp$" ) and envMod . moduleNameForPath (
envMod . new ( root , {
config = config
} ) ,
join ( root , entry )
) or entry
moduleName = moduleName or "nupp.compiler.main"
local mainPath = join ( root , join ( stage1 , moduleName : gsub ( "%." , "/" ) .. ".lua" ) )
local packagePath = join ( root , stage1 ) .. "/?.lua;" .. package . path
local argv = {
"luajit" ,
"-e" ,
"package.path=" .. string . format ( "%q" , packagePath ) .. " .. package.path" ,
mainPath ,
"build" ,
"--out-dir" ,
stage2
}
if targetName then
argv [ # argv + 1 ] = "--target" ;
argv [ # argv + 1 ] = targetName
end
if process . run ( argv , { cwd = root } ) ~= 0 then
return 1
end
local first = treeDigest ( join ( root , stage1 ) )
local second = treeDigest ( join ( root , stage2 ) )
if first ~= second then
io . stderr : write ( "nupp: self-hosting fixpoint mismatch; stages kept for inspection\n" )
if opts . result then
opts . result . reason = "the two stages differ"
end
return 1
end
local destination = join ( root , target . outDir or "build" )
local copied , copyErr = copyTree ( join ( root , stage2 ) , destination )
if not copied then
io . stderr : write ( "nupp: " .. copyErr .. "\n" ) ;
return 1
end
writeFile ( join ( destination , ".nupp-complete" ) , second .. "\n" )
if opts . updateBootstrap then
local updated , updateErr = project . updateBootstrap ( root )
if not updated then
io . stderr : write ( "nupp: " .. tostring ( updateErr ) .. "\n" ) ;
return 1
end
end
removeTree ( join ( root , stage1 ) ) ;
removeTree ( join ( root , stage2 ) )
if opts . result then
opts . result . target = targetName
opts . result . updatedBootstrap = opts . updateBootstrap and true or false
else
io . write ( "fixpoint ok: compiler rebuilds itself byte-identically\n" )
end

return 0
end

return project
