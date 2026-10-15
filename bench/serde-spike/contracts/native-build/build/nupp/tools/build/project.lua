_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()











local envMod = require ( "nupp.compiler.project.env" )
local hash = require ( "nupp.compiler.hash" )
local process = require ( "nupp.compiler.process" )
local fs = require ( "nupp.compiler.fs" )
local cache = require ( "nupp.tools.build.cache" )
local fingerprint = require ( "nupp.compiler.project.fingerprint" )
local manifest = require ( "nupp.tools.build.manifest" )
local tasks = require ( "nupp.tools.build.tasks" )
local deps = require ( "nupp.tools.build.deps" )
local generators = require ( "nupp.tools.build.generators" )
local spi = require ( "nupp.tools.build.spi" )
local modules = require ( "nupp.tools.build.modules" )
local buildPlatform = require ( "nupp.tools.build.platform" )
local storeMod = require ( "nupp.compiler.project.store" )
local native = require ( "nupp.tools.build.native" )
local nativeFeatures = require ( "nupp.compiler.native" )
local materializeObserve = require ( "nupp.compiler.comptime.materialize.observe" )
local progressMod = require ( "nupp.tools.build.progress" )

local project = { }



















































































































local CHECK_STATE_STAMP = "checks/1"

local normalize , join = fs . normalize , fs . join
local dirname , basename = fs . dirname , fs . basename
local readFile , writeFile = fs . readFile , fs . writeFile
local copyFile , listFiles = fs . copyFile , fs . listFiles

local stable = require ( "nupp.compiler.stable" )
local hashFile = fingerprint . hashFile
local loadState , saveState = cache . loadState , cache . saveState
local toolFingerprint = fingerprint . toolFingerprint
local targetConfig = tasks . targetConfig
local buildDependencies = deps . build
local buildModules = modules . build
local aotcheck = require ( "nupp.tools.build.aotcheck" )



const _DYNAMIC_REQUIRES = "@requires-dynamically nupp.tools.build.aot\n@requires-dynamically nupp.tools.hotsession\n@requires-dynamically nupp.tools.doc\n@requires-dynamically nupp.tools.build.package\n"





local loadBuildTool = require

local function mentionsGpuTarget ( path ) 
local source = fs . readFile ( path )
return source ~= nil and aotcheck . mentionsGpuTarget ( source )
end




local function checkedTargetNeedsGpu ( root , config , paths ) 
for _ , path in ipairs ( paths or { } ) do
if mentionsGpuTarget ( path ) or mentionsGpuTarget ( join ( root , path ) ) then
return true
end
end
for _ , directory in ipairs ( config . include or { } ) do
for _ , path in ipairs ( listFiles ( join ( root , directory ) ) ) do
if path : match ( "%.nupp$" ) ~= nil and mentionsGpuTarget ( path ) then
return true
end
end
end

return false
end








local function aotInputSources ( root , outDir , config , target , environment ) 
local sources = envMod . listSourceFilesFor ( environment , root , config . include or { } , join ( root , outDir ) , true )
local sourceRoots = { }
for _ , directory in ipairs ( config . include or { } ) do
local normalized = normalize ( directory )
sourceRoots [ # sourceRoots + 1 ] = ( normalized : sub ( 1 , 1 ) == "/" or normalized : match ( "^[A-Za-z]:/" ) ~= nil )
and normalized
or join ( root , normalized )
end
if # sourceRoots == 0 then
sourceRoots [ 1 ] = root
end
local outputRoot = normalize ( join ( root , outDir ) )

local function skipsBookkeeping ( name ) 
return name : sub ( 1 , 1 ) == "."
end

for _ , sourceRoot in ipairs ( sourceRoots ) do
for _ , path in ipairs ( listFiles ( sourceRoot , skipsBookkeeping ) ) do
local normalized = normalize ( path )
if normalized : match ( "%.lua$" )
and normalized ~= outputRoot
and normalized : sub ( 1 , # outputRoot + 1 ) ~= outputRoot .. "/"
then
sources [ # sources + 1 ] = normalized
end
end
end
for _ , entry in ipairs ( target . entries or { } ) do
if entry : match ( "%.nupp$" ) or entry : match ( "%.lua$" ) or entry : find ( "[/\\]" ) then
sources [ # sources + 1 ] = join ( root , entry )
end
end
for _ , selected in ipairs ( target . sources or { } ) do
for _ , matched in ipairs ( deps . expandGlob ( root , normalize ( selected ) ) ) do
local files = listFiles ( matched )
if # files == 0 then
sources [ # sources + 1 ] = matched
else
for _ , path in ipairs ( files ) do
sources [ # sources + 1 ] = path
end
end
end
end

return sources
end


project . loadManifest = manifest . load


project . describeTasks = tasks . describe

project . encode = tasks . encode






local function say ( opts , code , text ) 
if opts == nil or opts . diagnostics == nil then
io . stderr : write ( text )
return
end
local message = text : gsub ( "\n$" , "" )
local diagnostics = ( opts ) . diagnostics
diagnostics [
# diagnostics + 1
] = require ( "nupp.tools.cli.report" ) . runDiagnostic ( code , message , nil , code == "NUPP0002" and "nupp.lua" or nil )
end

local function buildOne ( root , opts ) 
root , opts = root or "." , ( opts or { } )








local report = progressMod . new ( opts . progress )
local config , loadErr = project . loadManifest ( root )
if not config then
say ( opts , "NUPP0002" , tostring ( loadErr ) .. "\n" ) ;
return 1
end
local target , targetErr = targetConfig ( config , opts . target )
if not target then
say ( opts , "NUPP0003" , "nupp: " .. tostring ( targetErr ) .. "\n" ) ;
return 1
end
if opts . standalone then
if target . kind ~= "binary" or target . stub ~= "nupp" then
say ( opts , "NUPP0002" , "nupp: --standalone requires a binary target with stub = \"nupp\"\n" )
return 1
end
if target . aotLinkage == "shared" then
say ( opts , "NUPP0002" , "nupp: --standalone requires aotLinkage = \"static\"\n" )
return 1
end
target . standalone = true
end
target . host = opts . host or target . host or "native"
if target . host ~= "native" and target . host ~= "browser" then
say ( opts , "NUPP0002" , "nupp: host must be native or browser\n" )
return 1
end
if target . host == "browser" and target . platforms ~= nil then
say (
opts ,
"NUPP0002" ,
"nupp: platforms selects native binary hosts and cannot be combined with host = \"browser\" or --host browser\n"
)
return 1
end
if target . host == "browser" then
if target . layoutTarget ~= nil and target . layoutTarget ~= "i686-unknown-linux-gnu" then
say ( opts , "NUPP0002" , "nupp: the LuaJIT browser guest requires layoutTarget i686-unknown-linux-gnu\n" )
return 1
end
target . layoutTarget = "i686-unknown-linux-gnu"
end
if target . aot == "require-wasm" and target . host ~= "browser" then
say (
opts ,
"NUPP0002" ,
"nupp: require-wasm needs host = \"browser\" or --host browser; use emit-wasm to export kernels for another host\n"
)
return 1
end
local compatibility , compatError = require ( "nupp.compiler.compat" ) . resolve ( opts . compat , config . compat )
if compatError then
say ( opts , "NUPP0002" , "nupp: " .. compatError .. "\n" )
return 1
end
config . compat = compatibility
config . _compatVersion = compatibility and require ( "nupp.compiler.compat" ) . VERSION or nil
if opts . produced then
opts . produced . compat = compatibility
end
local selectedPlatform = opts . platform
if target . platforms then
if selectedPlatform == nil then
if # target . platforms == 1 then
selectedPlatform = target . platforms [ 1 ]
else
say (
opts ,
"NUPP0003" ,
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
say (
opts ,
"NUPP0003" ,
"nupp: platform " .. tostring (
selectedPlatform
) .. " is not configured on binary target " .. tostring ( target . name or opts . target or "default" ) .. "\n"
)
return 1
end
target . layoutTarget = selectedPlatform


if target . aot ~= nil and target . aotTarget == nil and selectedPlatform ~= buildPlatform . hostKey ( ) then
target . aotTarget = selectedPlatform
end
elseif selectedPlatform ~= nil then
say (
opts ,
"NUPP0003" ,
"nupp: --platform requires a binary target with a platforms list; target " .. tostring (
target . name or opts . target or "default"
) .. " has none\n"
)
return 1
end
if selectedPlatform and not opts . checkOnly and not target . standalone then
local record , recordErr = require ( "nupp.tools.build.stubs" ) . record ( selectedPlatform )
if not record then
say ( opts , "NUPP0004" , "nupp: " .. tostring ( recordErr ) .. "\n" )
return 1
end
target . _stubRecord = record
config . _stubCatalogRelease = record . catalogRelease
config . _stubSha256 = record . sha256
end
config . _target = target
config . _platform = selectedPlatform





local defaultLevel = 0
if target . kind == "binary" or target . kind == "bundle" or target . kind == "component" then
defaultLevel = 2
end




config . _reload = target . reload == true
if config . _reload then
defaultLevel = 0
if opts . optLevel and opts . optLevel ~= 0 then
say ( opts , "NUPP0002" , "nupp: a reload component builds at -O0\n" )
return 1
end



local read , pinned = pcall (
loadBuildTool ( "nupp.tools.hotsession" ) . libraries ,
config ,
require ( "nupp.compiler.fs" ) . absolute ( root )
)
if not read then
say ( opts , "NUPP0002" , "nupp: " .. tostring ( pinned ) .. "\n" )
return 1
end
config . _reloadLibraries = pinned
end
config . _optLevel = opts . optLevel or target . optimize or defaultLevel
config . _disabledPasses = opts . disabled or { }


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
say ( opts , "NUPP0004" , "nupp: " .. tostring ( depErr ) .. "\n" )
return 1
end
return ( loadBuildTool ( "nupp.tools.doc" ) . build ( root , config , target , {
checkOnly = opts . checkOnly ,
output = opts . outDir ,
} ) )
elseif target . kind
and target . kind ~= "modules"
and target . kind ~= "bundle"
and target . kind ~= "binary"
and target . kind ~= "component"
then



say ( opts , "NUPP0002" , "nupp: unsupported build target kind " .. tostring ( target . kind ) .. "\n" )
return 1
end
local outDir = normalize ( opts . outDir or target . outDir or "build" )
local completionPath = join ( root , join ( outDir , ".nupp-complete" ) )






local pendingCompletionPath = completionPath .. ".pending"
if not opts . checkOnly then
os . remove ( completionPath )
os . remove ( pendingCompletionPath )
end
local newState = cache . emptyState ( )



local contentDigest = fingerprint . contentDigest ( true )
newState . compilerHash = toolFingerprint ( contentDigest )


if not opts . checkOnly then
local stamped , stampErr = writeFile ( pendingCompletionPath , newState . compilerHash .. "\n" )
if not stamped then
say ( opts , "NUPP0001" , "nupp: " .. tostring ( stampErr ) .. "\n" )
return 1
end
end





newState . moduleCompilerHash = cache . moduleCompilerFingerprint (
fingerprint . sharedCacheDir ( join ( root , join ( outDir , "cache" ) ) ) ,
contentDigest
)
newState . configHash = contentDigest ( stable ( config ) )





local statePath = join ( root , join ( outDir , ".nupp-state.json" ) )
local checkState = nil
local oldState




if opts . checkOnly then
checkState = storeMod . openValue (
join ( root , join ( outDir , "cache/checks.buf" ) ) ,
"checks/1" .. "\0" .. newState . moduleCompilerHash
)
oldState = cache . adoptState ( checkState . value )
else
oldState = loadState ( statePath )
end


for name , produced in pairs ( oldState . targets ) do
newState . targets [ name ] = produced
end
local targetKey = target . name or opts . target or "default"
if selectedPlatform then
targetKey = targetKey .. "@" .. selectedPlatform
end
report : at ( "dependencies" )
report : step ( "resolving dependencies" )
local dependencies , depErr = buildDependencies ( root , outDir , config , oldState . dependencies , target )
report : clear ( )
if not dependencies then
say ( opts , "NUPP0004" , "nupp: " .. tostring ( depErr ) .. "\n" ) ;
return 1
end
newState . dependencies = dependencies
report : at ( "generate" )
report : step ( "running generators" )
local generated , generatorErr = generators . run ( root , outDir , config , dependencies , oldState . generators )
report : clear ( )
if not generated then
say ( opts , "NUPP0004" , "nupp: " .. tostring ( generatorErr ) .. "\n" )
return 1
end
newState . generators = generated
local spiEntries , spiError = spi . read ( root , config , target , dependencies )
if spiEntries == nil then
say ( opts , "NUPP0002" , "nupp: " .. tostring ( spiError ) .. "\n" )
return 1
end
local wroteSpi , writeSpiError = spi . write ( root , outDir , spiEntries )
if not wroteSpi then
say ( opts , "NUPP0001" , "nupp: " .. tostring ( writeSpiError ) .. "\n" )
return 1
end
config . _spiEntries = spiEntries
local session = modules . session ( root , outDir , config , target , dependencies , report )
local validSpi , invalidSpi = spi . check ( session , spiEntries , root , outDir )
if not validSpi then
say ( opts , "NUPP0002" , "nupp: " .. tostring ( invalidSpi ) .. "\n" )
return 1
end
local writtenSpi , publishSpiError = spi . write ( root , outDir , spiEntries )
if not writtenSpi then
say ( opts , "NUPP0001" , "nupp: " .. tostring ( publishSpiError ) .. "\n" )
return 1
end
session . inc . diskChanged ( join ( root , join ( outDir , "generated/nupp/spi/index.nupp" ) ) , 2 )

if opts . checkOnly
and ( target . aot == "require" or target . aot == "require-wasm" )
and checkedTargetNeedsGpu ( root , config , opts . paths )
then
session . stageGpuRuntime ( )
end


















local aotOverlays = nil
local aotAuthoredUnused = nil
local aotLibrary = nil
local aotLinkage = target . aotLinkage or ( target . standalone and "static" or "shared" )
local aotManifest = nil
local aotWasmModules = { }
local aotGpu = false
local aotRemarks = { }
if not opts . checkOnly and aotcheck . applies ( target . aot ) then
local aotPolicy = loadBuildTool ( "nupp.tools.build.aot" )
report : at ( "aot" )
report : step (
( target . aot == "require" or target . aot == "require-wasm" ) and "compiling ahead-of-time code"
or "emitting ahead-of-time code"
)







report : at ( "aot:lookup" )
local aotToolchainPolicy = aotPolicy . toolchainPolicy (
target . aot ,
target . aotTarget ,
contentDigest
)
local aotInput = aotPolicy . inputFingerprint (



aotInputSources ( root , outDir , config , target , session . inc . env ) ,
{
compiler = newState . compilerHash ,
compilerResources = aotPolicy . compilerResourceFingerprint ( contentDigest ) ,
moduleCompiler = newState . moduleCompilerHash ,
config = newState . configHash ,
dependencies = contentDigest ( stable ( newState . dependencies ) ) ,
generators = contentDigest ( stable ( newState . generators ) ) ,
spi = contentDigest ( stable ( spiEntries ) ) ,
target = targetKey ,
platform = selectedPlatform ,
toolchainPolicy = aotToolchainPolicy ,
} ,
contentDigest
)
newState . aotInput = aotInput
local outputsIntact = true
for output in pairs ( oldState . outputs or { } ) do
if not fs . exists ( output ) then
outputsIntact = false
do break end
end
end
if outputsIntact then
for _ , record in pairs ( oldState . modules or { } ) do
if record . output ~= nil
and ( record . artifactHash == nil or hashFile ( record . output ) ~= record . artifactHash )
then
outputsIntact = false
do break end
end
end
end
local produced = nil
if outputsIntact and oldState . aotInput == aotInput then
produced = aotPolicy . replay ( oldState . aotReplay , aotToolchainPolicy . desiredCommand )
end








local aotErr = nil
local aotDiagnostic = nil
if produced == nil then
local resumeChecking = report : charging ( "aot:check" )
report : at ( "aot:check" )
local aotScope , scopeErr = modules . targetScope ( root , target , session )
report : charging ( resumeChecking )
report : at ( "aot" )
if scopeErr then
say ( opts , "NUPP0002" , "nupp: " .. tostring ( scopeErr ) .. "\n" )

return 1
end
produced , aotErr , aotDiagnostic = aotPolicy . apply (
target . aot ,
root ,
outDir ,
config . include or { } ,
( target . name or opts . target or "default" ) ,
( oldState . aot or { } ) ,
oldState . aotLibrary ,
session ,
target . aotFeatures ,
target . aotTarget ,
aotLinkage ,
aotPolicy . carried (
oldState . aotObjects ,


oldState . aotModules ,
oldState . aotToolchain
) ,
report ,
aotScope
)
else
report : at ( "aot:reuse" )
end
report : clear ( )
if produced == nil then
if aotDiagnostic ~= nil and opts . diagnostics ~= nil then



local source = fs . readFile ( aotDiagnostic . file ) or ""
local offset = 1
for _ = 2 , aotDiagnostic . line do
offset = ( source : find ( "\n" , offset , true ) or ( # source + 1 ) ) + 1
end
opts . diagnostics [
# opts . diagnostics + 1
] = {
filename = aotDiagnostic . file ,
line = aotDiagnostic . line ,
col = aotDiagnostic . column ,
offset = offset + aotDiagnostic . column - 1 ,
length = 1 ,
code = aotDiagnostic . code ,
msg = tostring ( aotErr ) ,
help = "Adjust the source to the selected AOT target's supported subset." ,
}
return 1
end
require (
"nupp.tools.cli.report"
) . fileFailure (
fs . join ( root , "nupp.lua" ) ,
tostring ( aotErr ) ,
"Inspect the generated AOT unit and the compiler output above." ,
opts . diagnostics
)
return 1
end
aotRemarks = ( produced ) . remarks or { }
report : addSpecialized ( ( produced ) . specializedBodies or 0 )
local internalTarget = target
internalTarget . _constSelection = ( produced ) . constSelection
local gpuSources = { }
for _ , source in ipairs ( ( produced ) . gpuSources or { } ) do
gpuSources [ normalize ( source ) ] = true
end
internalTarget . _aotGpuSources = gpuSources


local keys = { }
for _ , one in ipairs ( ( produced ) . emitted ) do
newState . outputs [ one . output ] = true
keys [ one . cacheKey ] = one . key
if one . object ~= nil then
newState . outputs [ one . object ] = true
end
end
newState . aot = keys
if ( produced ) . manifest ~= nil then
newState . outputs [ ( produced ) . manifest ] = true
aotManifest = ( produced ) . manifest
end
if ( produced ) . library ~= nil then
newState . outputs [ ( produced ) . library ] = true
aotLibrary = ( produced ) . library
end
for _ , output in ipairs ( ( produced ) . wasmModules or { } ) do
newState . outputs [ output ] = true
if output : match ( "%.wasm$" ) then
aotWasmModules [ # aotWasmModules + 1 ] = output
end
end
if ( produced ) . libraryKey ~= nil then
newState . aotLibrary = ( produced ) . libraryKey
end
newState . aotObjects = ( produced ) . objects
newState . aotModules = ( produced ) . modules
newState . aotToolchain = ( produced ) . remembered
newState . aotReplay = aotPolicy . captureReplay ( target . aot , produced )
report : aotCounted ( ( produced ) . facts )
aotOverlays = ( produced ) . dispatch
aotAuthoredUnused = ( produced ) . authoredUnused
aotGpu = ( produced ) . gpu == true



if aotGpu and ( target . aot == "require" or target . aot == "require-wasm" ) then
session . stageGpuRuntime ( )
end
end
local result , buildErr = buildModules (
root ,
outDir ,
config ,
target ,
oldState ,
newState ,
opts . checkOnly ,
opts . stats ,
opts . diagnostics ,
checkState ,
opts . paths and { paths = opts . paths , unchecked = opts . unchecked or { } , } or nil ,
report ,
aotOverlays ,
aotAuthoredUnused ,
session
)


report : clear ( )
if not result then
if opts . produced then
opts . produced . timing = report : timing ( )
end
if buildErr ~= "project has errors" and buildErr ~= "code generation failed" then
say ( opts , "NUPP0004" , "nupp: " .. tostring ( buildErr ) .. "\n" )
end
return 1
end
if aotGpu then
result . effects = result . effects or { }
( result . effects ) [ "runtime.gpu" ] = true
end
if opts . checkOnly then
report : finish ( "checked" , targetKey )
if opts . produced then
opts . produced . target = target . name or opts . target or "default"
opts . produced . platform = selectedPlatform
opts . produced . outputs = cache . jsonArray ( { } )
opts . produced . timing = report : timing ( )
end
return 0
end
for output in pairs ( result . outputs ) do
newState . outputs [ output ] = true
end

local detectedEffects = native . dependencyEffects ( root , config , target , result . effects )
local reachedWorkers = detectedEffects [ "runtime.workers" ] == true or detectedEffects [ "native.workers" ] == true
local resolvedEffects = native . resolve ( detectedEffects , target . nativeFeatures )
if resolvedEffects [ "native.workers" ] and target . kind == "binary" and target . stub ~= "nupp" then
say (
opts ,
"NUPP0002" ,
"nupp: native workers require a binary host with stub = \"nupp\"; the compiler-owned host supplies the isolated Lua states and early machine-code arena\n"

)
return 1
end
if target . kind == "bundle" then
local unresolved = { }
for effect in pairs ( resolvedEffects ) do
local feature = nativeFeatures . feature ( effect )


local hostModule = feature and feature . externalModule == true
if feature == nil or feature . binary and not hostModule then
unresolved [ # unresolved + 1 ] = effect
end
end
table . sort ( unresolved )
if # unresolved > 0 then
say (
opts ,
"NUPP0002" ,
"nupp: a one-file bundle cannot carry native features; "
.. "build modules or use a binary target with its lib directory ("
.. table . concat (
unresolved ,
", "
) .. ")\n"
)
return 1
end
end
report : at ( "native" )
report : step ( "building native providers" )
local nativeOutputs , nativeErr = native . build (
root ,
outDir ,
resolvedEffects ,
selectedPlatform ,
result . outputs ,
target . standalone
)
report : clear ( )
if not nativeOutputs then
say ( opts , "NUPP0004" , "nupp: " .. tostring ( nativeErr ) .. "\n" )
return 1
end
for output in pairs ( nativeOutputs ) do
newState . outputs [ output ] = true
end


local primaryArtifact = nil
local packagedAotManifest = nil
if target . kind == "bundle" or target . kind == "binary" or target . kind == "component" then
report : at ( "bundle" )
report : step ( "bundling " .. ( target . name or target . kind ) )
local runtimeModules = { }
for _ , feature in ipairs ( nativeFeatures . features ( resolvedEffects ) ) do
if feature . runtimeModule then
runtimeModules [ # runtimeModules + 1 ] = feature . runtimeModule
end
end
table . sort ( runtimeModules )
local requiredHostFeatures = nativeFeatures . requiredHostFeatureNames ( resolvedEffects )
local text , bundleErr , unreachable = loadBuildTool (
"nupp.tools.build.package"
) . bundleText (
root ,
config ,
target ,
nil ,
newState . modules ,
reachedWorkers or resolvedEffects [ "native.workers" ] == true ,
runtimeModules ,
( ( target . kind == "binary" and target . stub == "nupp" ) or target . kind == "component" ) and requiredHostFeatures
or nil ,
target . kind == "component" ,
outDir
)
if not text then
say ( opts , "NUPP0004" , "nupp: " .. tostring ( bundleErr ) .. "\n" )
return 1
end
if unreachable and # unreachable > 0 then
say (
opts ,
"NUPP0002" ,
("nupp: %d resource%s could not be bundled, starting at %s: a bundle can only carry what sits under the entry module's namespace\n")



: format ( # unreachable , # unreachable == 1 and "" or "s" , unreachable [ 1 ] )
)
end
local name = target . name or opts . target or ( target . platforms and "default" ) or target . kind
local output
if target . kind == "binary" then
output = loadBuildTool (
"nupp.tools.build.package"
) . binaryOutput ( root , target , name , outDir , selectedPlatform , opts . outDir ~= nil )
if target . payloadOutput ~= nil then
local payloadOutput = join ( root , target . payloadOutput )
if normalize ( payloadOutput ) == normalize ( output ) then
say ( opts , "NUPP0002" , "nupp: binary payloadOutput must differ from its executable output\n" )
return 1
end
local written , writeErr = writeFile ( payloadOutput , text )
if not written then
say ( opts , "NUPP0001" , "nupp: " .. tostring ( writeErr ) .. "\n" )
return 1
end
newState . outputs [ payloadOutput ] = true
end
local stubPath , hostErr
if target . standalone then
local archives , flags , seenArchives , seenFlags = { } , { } , { } , { }

local function addUnique ( into , seen , value ) 
if not seen [ value ] then
seen [ value ] = true
into [ # into + 1 ] = value
end
end

for dependencyName , dep in pairs ( dependencies ) do
if dep . usage == "target" and dep . staticOutput then
for _ , archive in ipairs ( dep . linkOutputs or { dep . staticOutput } ) do
addUnique ( archives , seenArchives , archive )
end
for _ , flag in ipairs ( dep . linkFlags or { } ) do
addUnique ( flags , seenFlags , flag )
end
elseif dep . usage == "target" and dep . runtimeOutput and dep . reference then
say (
opts ,
"NUPP0002" ,
"nupp: standalone binary cannot carry shared dependency "
.. dependencyName
.. "; provide static linkage or a static prebuilt artifact\n"
)
return 1
end
end
if aotLibrary ~= nil then
addUnique ( archives , seenArchives , aotLibrary )
end
table . sort ( archives )
local linkedPlatform = target . layoutTarget or buildPlatform . hostKey ( )
local executableSuffix = linkedPlatform and buildPlatform . executableSuffix ( linkedPlatform ) or ""
local linkedHost = join ( root , join ( outDir , "cache/standalone-host-" .. name .. executableSuffix ) )
fs . mkdir ( dirname ( linkedHost ) )
stubPath , hostErr = native . linkHost ( root , target , resolvedEffects , linkedHost , archives , flags )
else
stubPath , hostErr = native . hostStub ( root , outDir , target , resolvedEffects )
end
if not stubPath then
say ( opts , "NUPP0004" , "nupp: " .. tostring ( hostErr ) .. "\n" )
return 1
end
local resolvedStub = stubPath == target . stub and join ( root , stubPath ) or stubPath
local stub , stubErr = readFile ( resolvedStub )
if not stub then
say ( opts , "NUPP0001" , ("nupp: cannot read the stub %s: %s\n") : format ( resolvedStub , tostring ( stubErr ) ) )
return 1
end
local payload , payloadFlags , payloadErr = loadBuildTool (
"nupp.tools.build.package"
) . payloadBytes ( text , selectedPlatform )
if not payload then
say ( opts , "NUPP0004" , "nupp: " .. tostring ( payloadErr ) .. "\n" )
return 1
end
local stamped , stampErr , archive = loadBuildTool (
"nupp.tools.build.package"
) . stampFile ( output , stub , payload , selectedPlatform , payloadFlags )
if not stamped then
say ( opts , "NUPP0004" , "nupp: " .. tostring ( stampErr ) .. "\n" )
return 1
end
if archive then
newState . outputs [ archive ] = true
end
else
output = target . kind == "component"
and loadBuildTool ( "nupp.tools.build.package" ) . componentOutput ( root , target , name , opts . outDir )
or loadBuildTool ( "nupp.tools.build.package" ) . bundleOutput ( root , target , name , opts . outDir )
local written , writeErr = writeFile ( output , text )
if not written then
say ( opts , "NUPP0001" , "nupp: " .. tostring ( writeErr ) .. "\n" )
return 1
end
end
primaryArtifact = output
newState . outputs [ output ] = true





if aotLibrary ~= nil and aotLinkage == "shared" then
local beside = join ( dirname ( output ) , "lib/" .. basename ( aotLibrary ) )
local copied , copyErr = copyFile ( aotLibrary , beside )
if not copied then
say (
opts ,
"NUPP0001" ,
("nupp: cannot put the compiled library beside %s: %s\n") : format ( output , tostring ( copyErr ) )
)

return 1
end
newState . outputs [ beside ] = true
end




if # aotWasmModules > 0 and aotManifest ~= nil then
local builtRoot = normalize ( join ( outDir , "aot" ) ) .. "/"
local packagedRoot = join ( dirname ( output ) , "aot" )
for _ , source in ipairs ( aotWasmModules ) do
local normalizedSource = normalize ( source )
if normalizedSource : sub ( 1 , # builtRoot ) ~= builtRoot then
say ( opts , "NUPP0004" , "nupp: Wasm AOT output escaped its build directory: " .. source .. "\n" )
return 1
end
local beside = join ( packagedRoot , normalizedSource : sub ( # builtRoot + 1 ) )
if normalize ( beside ) ~= normalizedSource then
local copied , copyErr = copyFile ( source , beside )
if not copied then
say (
opts ,
"NUPP0001" ,
("nupp: cannot put the Wasm AOT module beside %s: %s\n") : format ( output , tostring ( copyErr ) )
)
return 1
end
end
newState . outputs [ beside ] = true
end
local packagedManifest = join ( packagedRoot , "units.json" )


local _ , manifestErr = loadBuildTool ( "nupp.tools.build.aot" ) . readUnitsManifest ( aotManifest )
if manifestErr ~= nil then
say ( opts , "NUPP0001" , "nupp: " .. manifestErr .. "\n" )
return 1
end
if normalize ( packagedManifest ) ~= normalize ( aotManifest ) then
local copied , copyErr = copyFile ( aotManifest , packagedManifest )
if not copied then
say (
opts ,
"NUPP0001" ,
("nupp: cannot put the Wasm AOT manifest beside %s: %s\n") : format ( output , tostring ( copyErr ) )
)
return 1
end
end
newState . outputs [ packagedManifest ] = true
packagedAotManifest = packagedManifest
end




for _ , dep in pairs ( dependencies ) do
local relative = dep . usage == "target"
and dep . reference ~= nil
and ( dep . reference ) : match ( "^@(.+)$" )
or nil
local runtimeOutput = dep . usage == "target"
and ( dep . runtimeOutput or ( dep . staticOutput == nil and dep . output ) )
or nil
if relative ~= nil and runtimeOutput ~= nil then
local beside = join ( dirname ( output ) , relative )
local copied , copyErr = copyFile ( runtimeOutput , beside )
if not copied then
say (
opts ,
"NUPP0001" ,
("nupp: cannot put the compiled library beside %s: %s\n") : format ( output , tostring ( copyErr ) )
)

return 1
end
newState . outputs [ beside ] = true
end
end
report : clear ( )
end
for _ , dep in pairs ( dependencies ) do
if dep . output then
newState . outputs [ dep . output ] = true
end
if dep . staticOutput then
newState . outputs [ dep . staticOutput ] = true
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
for _ , note in ipairs ( aotRemarks ) do
result . optimizationRemarks [ # result . optimizationRemarks + 1 ] = note
end
if opts . remarks or opts . produced then
if ( config . _optLevel or 0 ) == 0 then
result . optimizationRemarks [
# result . optimizationRemarks + 1
] = {
code = "OPT-0" ,
severity = "note" ,
status = "unavailable" ,
hotness = "unknown" ,
filename = opts . remarksFile or join ( root , "nupp.lua" ) ,
line = 1 ,
col = 1 ,
offset = 1 ,
length = 0 ,
msg = "optimizer unavailable at -O0; select -O1 or -O2 to request optimization" ,
}
end
if opts . remarks then
local selected = require (
"nupp.tools.cli.compile"
) . selectRemarks ( result . optimizationRemarks , opts . remarksFile )
if opts . diagnostics then
for _ , note in ipairs ( selected ) do
opts . diagnostics [ # opts . diagnostics + 1 ] = note
end
else
require ( "nupp.compiler.diagnostics" ) . report ( selected )
end
end
end


if opts . produced then
opts . produced . target = target . name or opts . target or "default"
opts . produced . platform = selectedPlatform
opts . produced . artifact = primaryArtifact
opts . produced . aotManifest = packagedAotManifest
if selectedPlatform == "aarch64-apple-darwin" then
opts . produced . distributionReady = false
opts . produced . notice = "the macOS binary must be signed on macOS and has not passed notarization"
end
opts . produced . outputs = mine
opts . produced . materializations = materializeObserve . public ( result . materializations )
opts . produced . derives = result . derives
opts . produced . spi = spiEntries
opts . produced . optLevel = config . _optLevel
opts . produced . optimizationRemarks = result . optimizationRemarks
opts . produced . allocationSites = result . allocationSites
opts . produced . accountedModules = result . accountedModules
end
report : at ( "write" )
local ok , stateErr = saveState ( statePath , newState )
if not ok then
say ( opts , "NUPP0001" , "nupp: " .. tostring ( stateErr ) .. "\n" ) ;
return 1
end
local completed , completionErr = os . rename ( pendingCompletionPath , completionPath )
if not completed then



completed , completionErr = writeFile ( completionPath , newState . compilerHash .. "\n" )
end
if not completed then
say ( opts , "NUPP0001" , "nupp: " .. tostring ( completionErr ) .. "\n" )
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
say ( opts , "NUPP0002" , tostring ( loadErr ) .. "\n" )
return 1
end
local target , targetErr = targetConfig ( config , opts . target )
if not target then
say ( opts , "NUPP0003" , "nupp: " .. tostring ( targetErr ) .. "\n" )
return 1
end
if not target . platforms then
say ( opts , "NUPP0003" , "nupp: --platform all requires a binary target with a platforms list\n" )
return 1
end
local aggregate = opts . produced
if aggregate then
aggregate . target = target . name or opts . target or "default"
aggregate . outputs = cache . jsonArray ( { } )
aggregate . platforms = cache . jsonArray ( { } )
aggregate . optimizationRemarks = cache . jsonArray ( { } )
aggregate . allocationSites = cache . jsonArray ( { } )
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



if aggregate . accountedModules == nil and produced . accountedModules ~= nil then
aggregate . optLevel = produced . optLevel
aggregate . optimizationRemarks = produced . optimizationRemarks
aggregate . allocationSites = produced . allocationSites
aggregate . accountedModules = produced . accountedModules
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
say ( asked , "NUPP0002" , tostring ( err ) .. "\n" )
return 1 , "manifest"
end
local test = manifest . testConfig ( config )
local produced = { }
if project . build ( root , {
target = test . build ,
outDir = asked . outDir ,
coverage = asked . coverage ,
produced = produced ,
diagnostics = asked . diagnostics
} ) ~= 0 then
return 1 , "build"
end
local argv = { }
for _ , item in ipairs ( manifest . testArgv ( test ) ) do
argv [ # argv + 1 ] = item
end
local builtTarget = assert ( targetConfig ( config , test . build ) )
if asked . outDir ~= nil and builtTarget . output ~= nil and produced . artifact then
for index , item in ipairs ( argv ) do
if item == builtTarget . output then
argv [ index ] = produced . artifact
end
end
end
for _ , item in ipairs ( args or { } ) do
argv [ # argv + 1 ] = item
end




if argv [ 1 ] == "nupp" and argv [ 2 ] == "test" and argv [ 3 ] == "--internal-runner" then
local compilerRoot = os . getenv ( "NUPP_COMPILER_ROOT" )
argv [ 1 ] = compilerRoot and compilerRoot .. "/bin/nupp" or tostring ( arg [ 0 ] or argv [ 1 ] )
end
local env = { }
for key , value in pairs ( test . env or { } ) do
env [ key ] = value
end
for key , value in pairs ( asked . env or { } ) do
env [ key ] = value
end
env . NUPP_TEST_BUILD = normalize ( asked . outDir or env . NUPP_TEST_BUILD or builtTarget . outDir or "build" )




local rocks = deps . rockPaths ( root , config , builtTarget )
if rocks then


env . LUA_PATH = rocks . path .. ";" .. ( env . LUA_PATH or os . getenv ( "LUA_PATH" ) or "" )
env . LUA_CPATH = rocks . cpath .. ";" .. ( env . LUA_CPATH or os . getenv ( "LUA_CPATH" ) or "" )
end





local pid = fs . processId ( )
if pid ~= nil then
env . NUPP_TEST_WATCH_PID = tostring ( pid )
end

return process . run ( argv , { cwd = root , env = env , replaceShell = true } )
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
io . stderr : write ( "nupp: no task named " .. tostring ( name ) .. "; see `nupp task --list`\n" )
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

return process . run ( argv , { cwd = join ( root , task . cwd or "" ) , env = env } )
end









local function treeDigest ( path ) 
local files , parts = listFiles ( path ) , { }
for _ , file in ipairs ( files ) do
local relative = file : sub ( # normalize ( path ) + 2 )
local native = relative : match ( "^native/" ) or relative : match ( "^lib/" )










local derived = relative : match ( "^cache/" ) or relative : match ( "^%.bytecode/" )
if relative ~= ".nupp-state.json"
and not relative : match ( "^%.nupp%-complete" )
and not native
and not derived
then
parts [ # parts + 1 ] = relative .. "\0" .. ( hashFile ( file ) or "" )
end
end

return hash . digest ( table . concat ( parts , "\0" ) )
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
if path == ""
or path == "."
or path : sub ( 1 , 1 ) == "/"
or path : match ( "^%a:" )
or path : find ( "%z" )
or path == ".."
or path : match ( "^%.%./" )
or path : match ( "/%.%./" )
or path : match ( "/%.%.$" )
then
return nil , "unsafe build output path " .. tostring ( path )
end

return path
end

function project . clean ( root , opts ) 
root , opts = root or "." , ( opts or { } )
if opts . target then
local config , loadErr = project . loadManifest ( root )
if not config then
say ( opts , "NUPP0002" , tostring ( loadErr ) .. "\n" )
return 1
end
local target , targetErr = targetConfig ( config , opts . target )
if not target then
say ( opts , "NUPP0003" , "nupp: " .. tostring ( targetErr ) .. "\n" )
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
say (
opts ,
"NUPP0003" ,
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
local raw = loadBuildTool (
"nupp.tools.build.package"
) . binaryOutput ( "." , target , target . name or opts . target , outDir , selectedPlatform )
candidates [ # candidates + 1 ] = raw
if require ( "nupp.tools.build.platform" ) . isPosix ( selectedPlatform ) then
candidates [ # candidates + 1 ] = raw .. ".tar"
end
end
local collected = opts . removed
for _ , candidate in ipairs ( candidates ) do
local safe , safeErr = safeCleanPath ( candidate )
if not safe then
say ( opts , "NUPP0002" , "nupp: refusing to clean " .. safeErr .. "\n" )
return 1
end
if not opts . dryRun and removeTree ( join ( root , safe ) ) ~= 0 then
say ( opts , "NUPP0001" , "nupp: cannot remove build output " .. safe .. "\n" )
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
say ( opts , "NUPP0001" , "nupp: " .. tostring ( saveErr ) .. "\n" )
return 1
end
end
end
return 0
elseif opts . platform then
say ( opts , "NUPP0003" , "nupp: --platform requires a binary target with a platforms list\n" )
return 1
end
end
local described , err = project . describeTasks ( root , opts . target , { buildOnly = true } )
if not described then
say ( opts , "NUPP0002" , tostring ( err ) .. "\n" ) ;
return 1
end
local tasks = opts . target and { described } or described . tasks
local candidates = { }
for _ , task in ipairs ( tasks ) do
local path , pathErr = safeCleanPath ( task . outDir )
if not path then
say ( opts , "NUPP0002" , "nupp: refusing to clean " .. pathErr .. "\n" )
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
do break end
end
end
if not covered then
selected [ # selected + 1 ] = path
end
end


local collected = opts . removed
for _ , path in ipairs ( selected ) do
if not opts . dryRun and removeTree ( join ( root , path ) ) ~= 0 then
say ( opts , "NUPP0001" , "nupp: cannot remove build output " .. path .. "\n" )
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
if relative ~= ".nupp-state.json"
and not relative : match ( "^%.nupp%-complete" )
and not relative : match ( "^native/" )
then
local ok , err = copyFile ( path , join ( destination , relative ) )
if not ok then
return nil , err
end
end
end

return true
end






local function stage0Text ( root , config ) 
local targetName = config . selfHost and ( config . selfHost . bootstrapTarget or config . selfHost . target ) or nil
local target , targetErr = targetConfig ( config , targetName )
if not target then
return nil , targetErr
end


local outDir = target . outDir or "build"
local state = loadState ( join ( root , join ( outDir , ".nupp-state.json" ) ) )
local text , bundleErr = loadBuildTool (
"nupp.tools.build.package"
) . bundleText (
root ,
config ,
target ,
"-- Generated stage-zero compiler. Rebuild with: nupp fixpoint --emit-stage0 PATH\n" ,
state and state . modules or nil
)

return text , bundleErr
end













function project . binaryFixpoint ( root , opts ) 
root = root or "."
local config , err = project . loadManifest ( root )
if not config then
say ( opts , "NUPP0002" , tostring ( err ) .. "\n" ) ;
return 1
end
local targetName = config . selfHost and config . selfHost . binary or nil
if not targetName then
say ( opts , "NUPP0002" , "nupp: selfHost.binary names no target to stamp\n" )
return 1
end
local target , targetErr = targetConfig ( config , targetName )
if not target then
say ( opts , "NUPP0003" , "nupp: " .. tostring ( targetErr ) .. "\n" )
return 1
end
if target . kind ~= "binary" then
say (
opts ,
"NUPP0002" ,
("nupp: selfHost.binary names %s, which is a %s target\n") : format ( targetName , target . kind or "modules" )
)
return 1
end

local built = { }
if project . build ( root , { target = targetName , produced = built } ) ~= 0 then
return 1
end
local produced = built . artifact
if type ( produced ) ~= "string" then
say ( opts , "NUPP0004" , "nupp: binary build produced no executable artifact\n" )
return 1
end
local first , readErr = readFile ( produced )
if not first then
say ( opts , "NUPP0001" , "nupp: " .. tostring ( readErr ) .. "\n" )
return 1
end




local stage1 = produced .. ".stage1"
local copied , copyErr = writeFile ( stage1 , first )
if not copied then
say ( opts , "NUPP0001" , "nupp: " .. tostring ( copyErr ) .. "\n" )
return 1
end
process . capture ( { "chmod" , "+x" , stage1 } )

if process . run ( { stage1 , "build" , "--target" , targetName } , { cwd = root } ) ~= 0 then
say ( opts , "NUPP0004" , "nupp: the stamped binary could not stamp one\n" )
return 1
end
local second , secondErr = readFile ( produced )
if not second then
say ( opts , "NUPP0004" , "nupp: " .. tostring ( secondErr ) .. "\n" )
return 1
end

if first ~= second then
say (
opts ,
"NUPP0004" ,
("nupp: packaging fixpoint mismatch: %d bytes then %d; %s kept for inspection\n")

: format ( # first , # second , stage1 )
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
("packaging fixpoint ok: %s stamps out a binary identical to itself (%d bytes)\n")

: format ( targetName , # first )
)
end

return 0
end








local function stage0Compiler ( root , config ) 
local spelled = config . selfHost and config . selfHost . bootstrap or nil
local command = { }
for word in tostring ( spelled or "" ) : gmatch ( "%S+" ) do
command [ # command + 1 ] = word
end
if # command == 0 then
return nil , "selfHost.bootstrap names no command to find the stage-zero compiler with"
end
local status , output = process . capture ( command , { cwd = root } )
if status ~= 0 then
return nil , table . concat ( command , " " ) .. " failed: " .. output
end
local path = nil
for line in tostring ( output ) : gmatch ( "[^\13\n]+" ) do
path = line
end
if not path or path == "" then
return nil , table . concat ( command , " " ) .. " named no stage-zero compiler"
end
if not fs . exists ( path ) then
return nil , "the stage-zero compiler is not at " .. path
end

return path , nil
end





local function buildWithCompiler (
root ,
compiler ,
packageRoot ,
outDir ,
targetName
) 
local argv = { "luajit" }
if packageRoot then
argv [ # argv + 1 ] = "-e"
argv [ # argv + 1 ] = "package.path=" .. string . format ( "%q" , packageRoot .. "/?.lua;" ) .. " .. package.path"
end
argv [ # argv + 1 ] = compiler
argv [ # argv + 1 ] = "build"
argv [ # argv + 1 ] = "--output"
argv [ # argv + 1 ] = outDir
if targetName then
argv [ # argv + 1 ] = "--target"
argv [ # argv + 1 ] = targetName
end

return process . run ( argv , {
cwd = root ,
env = not packageRoot and { NUPP_COMPILER_ROOT = fs . dirname ( compiler ) , NUPP_STAGE0 = compiler } or nil
} ) == 0
end


local function stageMain ( root , config , target , outDir ) 
local entry = ( target . entries or { } ) [ 1 ] or "nupp.tools.main"
local moduleName = entry : match ( "%.nupp$" ) and envMod . moduleNameForPath (
envMod . new ( root , {
config = config
} ) ,
join ( root , entry )
) or entry
moduleName = moduleName or "nupp.tools.main"

return join ( root , join ( outDir , moduleName : gsub ( "%." , "/" ) .. ".lua" ) )
end














function project . fixpoint ( root , opts ) 
root , opts = root or "." , ( opts or { } )
local config , err = project . loadManifest ( root )
if not config then
say ( opts , "NUPP0002" , tostring ( err ) .. "\n" ) ;
return 1
end
local targetName = config . selfHost and config . selfHost . target or nil
local target , targetErr = targetConfig ( config , targetName )
if not target then
say ( opts , "NUPP0003" , "nupp: " .. tostring ( targetErr ) .. "\n" )
return 1
end
local stage0 , stage0Err = stage0Compiler ( root , config )
if not stage0 then
say ( opts , "NUPP0004" , "nupp: " .. tostring ( stage0Err ) .. "\n" )
return 1
end

local stages = { "_stage1" , "_stage2" , "_stage3" }
for _ , stage in ipairs ( stages ) do
removeTree ( join ( root , stage ) )
end


local compiler = stage0
local packageRoot = nil
for _ , stage in ipairs ( stages ) do
if not buildWithCompiler ( root , compiler , packageRoot , stage , targetName ) then
say ( opts , "NUPP0004" , ("nupp: %s did not build %s\n") : format ( compiler , stage ) )
if opts . result then
opts . result . reason = "a stage did not build"
end
return 1
end
compiler , packageRoot = stageMain ( root , config , target , stage ) , join ( root , stage )
end

local second = treeDigest ( join ( root , stages [ 2 ] ) )
local third = treeDigest ( join ( root , stages [ 3 ] ) )
if second ~= third then
say ( opts , "NUPP0004" , "nupp: self-hosting fixpoint mismatch; stages kept for inspection\n" )
if opts . result then
opts . result . reason = "the two stages differ"
end
return 1
end

local destination = join ( root , target . outDir or "build" )
local copied , copyErr = copyTree ( join ( root , stages [ 3 ] ) , destination )
if not copied then
say ( opts , "NUPP0001" , "nupp: " .. copyErr .. "\n" ) ;
return 1
end
writeFile ( join ( destination , ".nupp-complete" ) , third .. "\n" )
for _ , stage in ipairs ( stages ) do
removeTree ( join ( root , stage ) )
end




if opts . emitStage0 then
local stage0Target = config . selfHost and config . selfHost . bootstrapTarget or nil
if stage0Target and project . build ( root , { target = stage0Target } ) ~= 0 then
return 1
end
local text , textErr = stage0Text ( root , config )
if not text then
say ( opts , "NUPP0004" , "nupp: " .. tostring ( textErr ) .. "\n" ) ;
return 1
end
local written , writeErr = writeFile ( opts . emitStage0 , text )
if not written then
say ( opts , "NUPP0001" , "nupp: " .. tostring ( writeErr ) .. "\n" ) ;
return 1
end
end

if opts . result then
opts . result . target = targetName
opts . result . stage0 = stage0
opts . result . emittedStage0 = opts . emitStage0
else
io . write ( ("fixpoint ok: %s rebuilds itself byte-identically\n") : format ( stage0 ) )
if opts . emitStage0 then
io . write ( ("wrote the stage-zero compiler to %s\n") : format ( opts . emitStage0 ) )
end
end

return 0
end

local __nuppExportValue= project ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.project"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.project"]=__nuppExports;return __nuppExports