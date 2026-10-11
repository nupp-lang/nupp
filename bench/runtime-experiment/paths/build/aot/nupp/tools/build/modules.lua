_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.build.modules\0runtime\0001") };










const files = require ( "nupp.io.files" )











local aotcheck = require ( "nupp.tools.build.aotcheck" )
local envMod = require ( "nupp.compiler.project.env" )
local gen = require ( "nupp.compiler.lua.gen" )
local optimize = require ( "nupp.compiler.lua.optimize" )
local hash = require ( "nupp.compiler.hash" )
local incremental = require ( "nupp.compiler.project.incremental" )
local diagnosticMod = require ( "nupp.compiler.diagnostics" )
local fs = require ( "nupp.compiler.fs" )
local cache = require ( "nupp.tools.build.cache" )
local fingerprint = require ( "nupp.compiler.project.fingerprint" )
local deps = require ( "nupp.tools.build.deps" )
local materializeObserve = require ( "nupp.compiler.comptime.materialize.observe" )
local progress = require ( "nupp.tools.build.progress" )
local constspecialize = require ( "nupp.compiler.lua.constspecialize" )
local native = require ( "nupp.compiler.native" )
local moduleTargets = require ( "nupp.compiler.standardsurface" )

local normalize , join = fs . normalize , fs . join
local readFile , writeFile = fs . readFile , fs . writeFile
local stable = require ( "nupp.compiler.stable" )
local hashFile , jsonArray = fingerprint . hashFile , cache . jsonArray
local expandGlob = deps . expandGlob
local isFatal , printErrors = diagnosticMod . isFatal , diagnosticMod . report

local modules = { }

local function hiddenDirectory ( name ) 
return name : sub ( 1 , 1 ) == "."
end








local function selectedSourceFiles ( root , target ) 
if target . sources == nil then
return nil
end

local selected , seen = { } , { }
for _ , source in ipairs ( target . sources ) do
local normalized = normalize ( source )
if normalized == ""
or normalized : sub ( 1 , 1 ) == "/"
or normalized : match ( "^[A-Za-z]:/" )
or ( "/" .. normalized .. "/" ) : find ( "/../" , 1 , true )
then
return nil , "build.sources must stay inside the project: " .. source
end
local matches = expandGlob ( root , normalized )
if # matches == 0 then
return nil , "build.sources matched nothing: " .. source
end
local candidates = { }
for _ , matched in ipairs ( matches ) do
local info = files . info ( matched )
if info and info . kind == "directory" then
for _ , path in ipairs ( fs . listFiles ( matched , hiddenDirectory ) ) do
candidates [ # candidates + 1 ] = path
end
else
candidates [ # candidates + 1 ] = matched
end
end
local accepted = 0
for _ , path in ipairs ( candidates ) do
path = normalize ( path )
if ( path : match ( "%.nupp$" ) and not path : match ( "%.d%.nupp$" ) ) or path : match ( "%.lua$" ) then
accepted = accepted + 1
if not seen [ path ] then
seen [ path ] = true
selected [ # selected + 1 ] = path
end
end
end
if accepted == 0 then
return nil , "build.sources selected no compilable source: " .. source
end
end
table . sort ( selected )

return selected
end

local function exportDefinitionFingerprint ( exports ) 
local items = { }
for _ , field in ipairs ( { "typeDefs" , "valueDefs" } ) do
for name , definition in pairs ( exports and exports [ field ] or { } ) do
local deprecated = definition . deprecated
if deprecated then
items [
# items + 1
] = field .. ":" .. name .. ":" .. stable ( deprecated . reason ) .. ":" .. stable ( deprecated . replacement )
end
if definition . comptimeOnly then
items [ # items + 1 ] = field .. ":" .. name .. ":comptime"
end
end
end
table . sort ( items )

return table . concat ( items , "\0" )
end


























































modules.Session = {} modules.Session.__index = modules.Session ;_G.nupp.__reflect.link(modules.Session,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.compiler.project.incremental\0runtime\0001","nupp.compiler.project.incremental") })







































local function binderFingerprint ( binder , binders , prefix ) 
local at = binders . order [ binder ]
if not at then
at = binders . count + 1
binders . count = at
binders . order [ binder ] = at
end

return prefix .. "#" .. at
end

local function constFingerprint ( term , binders ) 
if not term then
return "nil"
end
if term . tag == "constLiteral" then
return "const(" .. term . domain .. ":" .. stable ( term . value ) .. ")"
elseif term . tag == "constVar" then
return binderFingerprint ( term , binders , "constvar" ) .. ":" .. term . domain
end
local operands = { }
for j , operand in ipairs ( term . operands ) do
operands [ j ] = constFingerprint ( operand , binders )
end

return "constop(" .. term . operation .. ":" .. table . concat ( operands , "," ) .. ")"
end

local typeFingerprint

local function packFingerprint ( pack , active , binders ) 
if pack . alternatives then
local alternatives = { }
for j , alternative in ipairs ( pack . alternatives ) do
alternatives [ j ] = packFingerprint ( alternative , active , binders )
end
return "packunion(" .. table . concat ( alternatives , "|" ) .. ")"
end
local head = { }
for j , member in ipairs ( pack . head ) do
head [ j ] = ( pack . modes [ j ] or "plain" ) .. ":" .. typeFingerprint ( member , active , binders )
end
local tail = pack . tail
local tailFingerprint = "-"
if tail and tail . kind == "generic" then
tailFingerprint = "generic:" .. binderFingerprint ( tail . var , binders , "packvar" )
elseif tail and tail . type then
tailFingerprint = tail . kind .. ":" .. (
tail . mode or "plain"
) .. ":" .. typeFingerprint ( tail . type , active , binders )
end

return "pack(" .. table . concat ( head , "," ) .. ";" .. tailFingerprint .. ")"
end

typeFingerprint = function ( t , active , binders ) 
if not t then
return "nil"
end
active = active or { }
binders = binders or { order = { } , count = 0 }
if active [ t ] then


local named = t
return "@" .. ( named . name or t . tag )
end
active [ t ] = true
local tag , value = t . tag , nil
if tag == "nominal" then












local arguments = { }
for _ , argument in ipairs ( t . typeArgs or { } ) do
arguments [ # arguments + 1 ] = typeFingerprint ( argument , active , binders )
end
for _ , argument in ipairs ( t . packArgs or { } ) do
arguments [ # arguments + 1 ] = packFingerprint ( argument , active , binders )
end
for _ , argument in ipairs ( t . constArgs or { } ) do
arguments [ # arguments + 1 ] = constFingerprint ( argument , binders )
end
value = "nominal(" .. tostring (
t . declKind
) .. ":" .. tostring ( t . name ) .. ( # arguments > 0 and "<" .. table . concat ( arguments , "," ) .. ">" or "" ) .. ")"
elseif tag == "shape" then
local fields = { }
for _ , field in ipairs ( t . fields or { } ) do
fields [
# fields + 1
] = field . name .. ":r=" .. typeFingerprint (
field . read ,
active ,
binders
) .. ":w=" .. typeFingerprint ( field . write , active , binders )
end
fields [
# fields + 1
] = "index:r=" .. typeFingerprint (
t . indexReadKey ,
active ,
binders
) .. ":" .. typeFingerprint (
t . indexReadValue ,
active ,
binders
) .. ":w=" .. typeFingerprint (
t . indexWriteKey ,
active ,
binders
) .. ":" .. typeFingerprint ( t . indexWriteValue , active , binders )
value = "shape(" .. table . concat ( fields , "," ) .. ")"
elseif tag == "func" then
local params , returns = { } , { }
local typeAt , packAt , constAt = 1 , 1 , 1
for _ , kind in ipairs ( t . paramKinds or { } ) do
if kind == "type" then
binderFingerprint ( ( t . typeParams or { } ) [ typeAt ] , binders , "typevar" )
typeAt = typeAt + 1
elseif kind == "pack" then
binderFingerprint ( ( t . packParams or { } ) [ packAt ] , binders , "packvar" )
packAt = packAt + 1
elseif kind == "const" then
binderFingerprint ( ( t . constParams or { } ) [ constAt ] , binders , "constvar" )
constAt = constAt + 1
end
end
for index , item in ipairs ( t . params or { } ) do
params [
# params + 1
] = tostring (
t . paramNames and t . paramNames [ index ] or ""
) .. "=" .. tostring (
t . paramModes and t . paramModes [ index ] or "plain"
) .. ":" .. typeFingerprint ( item , active , binders )
end
for _ , item in ipairs ( t . rets or { } ) do
returns [ # returns + 1 ] = typeFingerprint ( item , active , binders )
end




local partitions = { }
for result , fields in pairs ( t . partitionResults or { } ) do
for name , region in pairs ( fields ) do
partitions [ # partitions + 1 ] = tostring ( result ) .. ":" .. name .. "=" .. region
end
end
table . sort ( partitions )
value = "fn(" .. table . concat (
params ,
","
) .. (
t . vararg and ",..." or ""
) .. ")->(" .. table . concat (
returns ,
","
) .. ")" .. (
# partitions > 0 and "!partition(" .. table . concat ( partitions , "," ) .. ")" or ""
) .. ( t . noYield and "!noyield" or "" ) .. ( t . comptimeOnly and "!comptime" or "" )
elseif tag == "array" or tag == "ptr" then
value = tag .. "(" .. typeFingerprint ( t . elem , active , binders ) .. ")"
elseif tag == "carray" then
value = "carray(" .. typeFingerprint (
t . elem ,
active ,
binders
) .. ":" .. constFingerprint ( t . countTerm , binders ) .. ")"
elseif tag == "affine" then
local cleanupIds = { }
for j , cleanup in ipairs ( t . cleanups or { } ) do
cleanupIds [ j ] = cleanup . id
end
value = tag .. "(" .. table . concat (
cleanupIds ,
","
) .. ( t . transferOnly and ":transfer" or "" ) .. "," .. typeFingerprint ( t . inner , active , binders ) .. ")"
elseif tag == "borrowed" or tag == "pinned" then
value = tag .. "(" .. typeFingerprint ( t . inner , active , binders ) .. ")"
elseif tag == "map" then
value = "map(r=" .. (
t . readable and typeFingerprint ( t . key , active , binders ) or "nil"
) .. ":" .. (
t . readable and typeFingerprint ( t . value , active , binders ) or "nil"
) .. ",w=" .. typeFingerprint (
t . writeKey ,
active ,
binders
) .. ":" .. typeFingerprint ( t . writeValue , active , binders ) .. ")"
elseif tag == "tuple" then
local items = { }
for _ , item in ipairs ( t . elems or { } ) do
items [ # items + 1 ] = typeFingerprint ( item , active , binders )
end
value = "tuple(" .. table . concat ( items , "," ) .. ")"
elseif tag == "union" or tag == "intersection" then
local items = { }
for _ , item in ipairs ( t . members or { } ) do
items [ # items + 1 ] = typeFingerprint ( item , active , binders )
end
table . sort ( items ) ;
value = tag .. "(" .. table . concat ( items , tag == "union" and "|" or "&" ) .. ")"
elseif tag == "projection" then




value = "proj(" .. typeFingerprint ( t . of , active , binders ) .. "," .. t . name .. ")"
elseif tag == "typeHandle" then
value = "typeHandle(" .. typeFingerprint ( t . bound , active , binders ) .. ")"
elseif tag == "packResult" then
value = "packResult(" .. packFingerprint ( t . pack , active , binders ) .. ")"
elseif tag == "literal" then
value = "literal(" .. stable ( t . constant ) .. ":" .. typeFingerprint ( t . base , active , binders ) .. ")"
elseif tag == "neutral" then
local templates , comptimeArguments = { } , { }
for _ , part in ipairs ( t . templateParts or { } ) do
templates [ # templates + 1 ] = type ( part ) == "string" and "text(" .. stable ( part ) .. ")"
or typeFingerprint ( part , active , binders )
end
for _ , argument in ipairs ( t . comptimeArguments or { } ) do
if argument . kind == "type" then
comptimeArguments [ # comptimeArguments + 1 ] = "type=" .. typeFingerprint ( argument . value , active , binders )
elseif argument . kind == "typepack" then
comptimeArguments [ # comptimeArguments + 1 ] = "pack=" .. packFingerprint ( argument . value , active , binders )
else
comptimeArguments [ # comptimeArguments + 1 ] = "const=" .. constFingerprint ( argument . value , binders )
end
end
value = "neutral#1(" .. t . op .. ":" .. tostring (
t . capability or "-"
) .. ":subject=" .. typeFingerprint (
t . subject ,
active ,
binders
) .. ":key=" .. typeFingerprint (
t . key ,
active ,
binders
) .. ":binder=" .. typeFingerprint (
t . binder ,
active ,
binders
) .. ":keys=" .. typeFingerprint (
t . keys ,
active ,
binders
) .. ":value=" .. typeFingerprint (
t . value ,
active ,
binders
) .. ":remap=" .. typeFingerprint (
t . remap ,
active ,
binders
) .. ":const=" .. constFingerprint (
t . constTerm ,
binders
) .. ":template=" .. table . concat (
templates ,
","
) .. ":comptime=" .. tostring (
t . comptimeIdentity or "-"
) .. "(" .. table . concat ( comptimeArguments , "," ) .. "):" .. ( t . comptimeResultPack and "pack" or "type" ) .. ")"
elseif tag == "genericAlias" then
local parameters = { }
for _ , parameter in ipairs ( t . typeParams or { } ) do
parameters [ # parameters + 1 ] = typeFingerprint ( parameter , active , binders )
end
for _ , parameter in ipairs ( t . packParams or { } ) do
parameters [ # parameters + 1 ] = binderFingerprint ( parameter , binders , "packvar" )
end
for _ , parameter in ipairs ( t . constParams or { } ) do
parameters [ # parameters + 1 ] = binderFingerprint ( parameter , binders , "constvar" ) .. ":" .. parameter . domain
end
value = "alias(" .. table . concat ( parameters , "," ) .. ":" .. typeFingerprint ( t . body , active , binders ) .. ")"
elseif tag == "typevar" then






value = binderFingerprint ( t , binders , "typevar" )
else
value = tag or tostring ( t )
end
active [ t ] = nil

return value
end










function modules . interfaceHash (
moduleType ,
exports ,
externalSourceHash ,
digest
) 
exports = exports or { }

return (
digest or hash . digest
) (
typeFingerprint (
moduleType
) .. "\0definitions\0" .. exportDefinitionFingerprint (
exports
) .. "\0nominal-callables:" .. (
exports . nominalEffectFingerprint or ""
) .. "\0derives:" .. (
exports . deriveInterfaceFingerprint or ""
) .. "\0comptime-functions:" .. (
exports . comptimeFunctionFingerprint or ""
) .. ( externalSourceHash and ( "\0" .. externalSourceHash ) or "" )
)
end



local function shortPath ( root , path ) 
local rootPrefix = normalize ( root )
if rootPrefix ~= "." and path : sub ( 1 , # rootPrefix + 1 ) == rootPrefix .. "/" then
return path : sub ( # rootPrefix + 2 )
end

return path
end

local function resourceRelative ( config , path , root ) 
local normalized = normalize ( path )
local rootPrefix = normalize ( root )
if rootPrefix ~= "." and normalized : sub ( 1 , # rootPrefix + 1 ) == rootPrefix .. "/" then
normalized = normalized : sub ( # rootPrefix + 2 )
end
local best = normalized
for _ , include in ipairs ( config . include or { } ) do
include = normalize ( include )
if normalized : sub ( 1 , # include + 1 ) == include .. "/" then
local relative = normalized : sub ( # include + 2 )
if # relative < # best then
best = relative
end
end
end

return best
end

local function resourceOutput ( config , resource , source , root ) 
if type ( resource ) == "table" then
return normalize ( ( resource ) . output )
end

return resourceRelative ( config , source , root )
end

local function copyModuleRecord ( record ) 
local dependencies = jsonArray ( { } )
for _ , name in ipairs ( record . dependencies or { } ) do
dependencies [ # dependencies + 1 ] = name
end
local runtimeModules = jsonArray ( { } )
for _ , name in ipairs ( record . runtimeModules or { } ) do
runtimeModules [ # runtimeModules + 1 ] = name
end
local externalInputs = jsonArray ( { } )
for _ , input in ipairs ( record . externalInputs or { } ) do
externalInputs [ # externalInputs + 1 ] = { path = input . path , fingerprint = input . fingerprint }
end
local effects = jsonArray ( { } )
for _ , effect in ipairs ( record . effects or { } ) do
effects [ # effects + 1 ] = effect
end



local function list ( items ) 
return items ~= nil and jsonArray ( items ) or nil
end

local projectDependencies = jsonArray ( { } )
for _ , dependency in ipairs ( record . projectDependencies or { } ) do
projectDependencies [
# projectDependencies + 1
] = { name = dependency . name , key = dependency . key , fingerprint = dependency . fingerprint , }
end

return {
sourcePath = record . sourcePath ,
sourceHash = record . sourceHash ,
interfaceHash = record . interfaceHash ,
artifactHash = record . artifactHash ,
dependencies = dependencies ,
runtimeModules = runtimeModules ,
compilerRuntime = record . compilerRuntime ,
projectDependencies = projectDependencies ,
externalInputs = externalInputs ,
effects = effects ,
output = record . output ,
external = record . external ,
diags = list ( record . diags ) ,
aotRefusals = list ( record . aotRefusals ) ,
aotKey = record . aotKey ,
aotFamilies = list ( record . aotFamilies ) ,
aotGraphRefusals = list ( record . aotGraphRefusals ) ,
aotGraphKey = record . aotGraphKey ,
coverage = record . coverage ,
materializations = list ( record . materializations ) ,
derives = list ( record . derives ) ,
optimizationRemarks = list ( record . optimizationRemarks ) ,
allocationSites = list ( record . allocationSites ) ,
optimizationAccounted = record . optimizationAccounted ,
specializationHash = record . specializationHash ,
}
end






local function openSession (
root ,
outDir ,
config ,
target ,
dependencies ,
strict ,
reporter ,
projectNominals ,
isolated ,
checkGuard
) 
local report = reporter or progress . new ( "never" )
local envConfig = { }
for key , value in pairs ( config ) do
envConfig [ key ] = value
end
envConfig . include = { }
for _ , include in ipairs ( config . include or { } ) do
envConfig . include [ # envConfig . include + 1 ] = include
end
envConfig . include [ # envConfig . include + 1 ] = join ( outDir , "generated" )
local generatorNames = { }
for name in pairs ( config . generators or { } ) do
generatorNames [ # generatorNames + 1 ] = name
end
table . sort ( generatorNames )
for _ , name in ipairs ( generatorNames ) do
envConfig . include [ # envConfig . include + 1 ] = join ( outDir , "generated/" .. name )
end
local rocks = deps . rockPaths ( root , config , target , dependencies )
local ambientTypeRoots = deps . typeRoots ( root , config , dependencies )
local checkMs = { }
local stagedRoot = join ( root , join ( outDir , "cache/runtime-source" ) )
local stagedReady = false
local open


= { }


local resumeActivity = "scan"
local observer = {
checking = function ( path ) 
if checkGuard then
checkGuard ( path )
end




if # open == 0 then
resumeActivity = report . activity
report : at ( report . checking )
end
open [ # open + 1 ] = { startedAt = progress . now ( ) , children = 0 }
report : step ( "checking " .. shortPath ( root , path ) )
end ,
checked = function ( path ) 
local frame = open [ # open ]
if not frame then
return
end
open [ # open ] = nil
local spent = progress . now ( ) - frame . startedAt
local parent = open [ # open ]
if parent then
parent . children = parent . children + spent
end
checkMs [ path ] = ( checkMs [ path ] or 0 ) + spent - frame . children
if # open == 0 then
report : at ( resumeActivity )
end
end ,
}

local inc = incremental . new ( root , {
config = envConfig ,
strict = strict ,
nativeCompilerServices = true ,
typeRoots = rocks and rocks . typeRoots or { } ,
ambientTypeRoots = ambientTypeRoots ,
runtimeSourceRoots = { stagedRoot } ,
observe = observer ,
projectNominals = projectNominals ,


cacheReadOnly = isolated or nil ,
} )

local staged = { }
local stageBundled
stageBundled = function ( name , replaceTypeOnly ) 
local existing = inc . modulePath ( name )
if existing ~= nil and not ( replaceTypeOnly and envMod . isDependencyTypePath ( inc . env , existing ) ) then
return existing
end
local carried = require ( "nupp.compiler.bundled" )
local source = nil
local resource = ""




for _ , suffix in ipairs ( { ".nupp" , ".g.nupp" , "/init.nupp" , "/init.g.nupp" , ".d.nupp" , ".lua" } ) do
resource = "/" .. name : gsub ( "%." , "/" ) .. suffix
source = carried . source ( resource )
if source ~= nil then
do break end
end
end
if source == nil then
return nil
end
if not stagedReady then
if not isolated then
files . remove ( stagedRoot , true )
assert ( fs . mkdir ( stagedRoot ) , "cannot create runtime source staging tree" )
end
inc . env . roots [ # inc . env . roots + 1 ] = stagedRoot
stagedReady = true
end
local suffix = resource : match ( "/init%.g%.nupp$" ) and "/init.g.nupp"
or resource : match ( "/init%.nupp$" ) and "/init.nupp"
or resource : match ( "%.g%.nupp$" ) and ".g.nupp"
or resource : match ( "%.d%.nupp$" ) and ".d.nupp"
or resource : match ( "%.lua$" ) and ".lua"
or ".nupp"
local path = join ( stagedRoot , name : gsub ( "%." , "/" ) .. suffix )
if not isolated then
local wrote , problem = writeFile ( path , source )
assert ( wrote , problem )
end
inc . stageCarriedDocument ( name , path , source )
staged [ # staged + 1 ] = { name = name , replaceTypeOnly = replaceTypeOnly }
local header = inc . projectHeader ( path )
for _ , dependency in ipairs ( header and header . dependencies or { } ) do
stageBundled ( dependency , replaceTypeOnly )
end

return path
end

local function stageGpuRuntime ( ) 
stageBundled ( "nupp.gpu.internal" )
stageBundled ( "nupp.gpu.layout" )
if target . host ~= "browser" then
stageBundled ( "nupp.runtime.native" )
end
stageBundled ( "nupp.gpu" )
end

return ( _G.setmetatable({ inc =
inc ,  checkMs =
checkMs ,  stageBundled =
stageBundled ,  stageGpuRuntime =
stageGpuRuntime ,  staged =
staged }, modules.Session) )

end










local GUARANTEE_QUERY = { moduleCallGuarantees = true , moduleCallGuarantee = true , moduleCallableFact = true }


local function runtimeImports ( name , code , config , target ) 
local required = gen . runtimeModules ( code )



if config . _reload then
required [ # required + 1 ] = "nupp.runtime.hotreload"
end
if name == "nupp.spi" then
required [ # required + 1 ] = "nupp.spi.index"
elseif name == "nupp.spi.index" then
for _ , provider in ipairs ( config . _spiEntries or { } ) do
required [ # required + 1 ] = provider . implementation
end
end
local unique , seen = { } , { }
for _ , dependency in ipairs ( required ) do
if not seen [ dependency ] and moduleTargets . supports ( dependency , target . host ) then
seen [ dependency ] = true
unique [ # unique + 1 ] = dependency
end
end
table . sort ( unique )

return jsonArray ( unique )
end


local function aotFamilies ( path , checked ) 
local candidates , plans = { } , { }
constspecialize . collectCandidates ( checked , path , candidates , plans )
local names = { }
for _ , plan in ipairs ( plans ) do
if plan . requiredAot then
names [ # names + 1 ] = plan . name
end
end
if # names == 0 then
return nil
end
table . sort ( names )

return jsonArray ( names )
end

























































function modules . compileChecked ( job ) 
local name , path , result = job . name , job . path , job . checked
local config , target , inc = job . config , job . target , job . inc





local checkedDiags = { }










for _ , diag in ipairs ( result . diags or { } ) do
if not ( job . rewritten and diag . code == "NUPP2507" ) then
checkedDiags [ # checkedDiags + 1 ] = diag
end
end
if job . rewritten then
for _ , diag in ipairs ( job . authoredLints or { } ) do
checkedDiags [ # checkedDiags + 1 ] = diag
end
end
local mine = { }
for _ , diag in ipairs ( checkedDiags ) do
mine [ # mine + 1 ] = diag
end
local fatal = false
for _ , diag in ipairs ( mine ) do
fatal = fatal or isFatal ( diag )
end
local external = job . external


local refusals = jsonArray ( { } )
local aotKey = nil
local families = nil
if not fatal and not external then
local found , lowered = job . aotRefusals ( name , path , result . result )
for _ , diag in ipairs ( found ) do
refusals [ # refusals + 1 ] = diag
end
aotKey = lowered and job . aotKey ( ) or nil
families = lowered and aotFamilies ( path , result . result ) or nil
end
local depNames = inc . moduleDependencies ( path )
local effectNames = { }
if fatal or job . checkOnly or external then
for effect in pairs ( result . result and result . result . effects or { } ) do
effectNames [ # effectNames + 1 ] = effect
end
table . sort ( effectNames )
end
local output = nil
if not external then
output = join ( job . root , join ( job . outDir , name : gsub ( "%." , "/" ) .. ".lua" ) )
end
local artifactHash , code , coverage
local optimizationRemarks = jsonArray ( { } )
local allocationSites = jsonArray ( { } )
local optimizationAccounted = false
local runtimeModules = jsonArray ( { } )
local generated = false
local generateMs = 0
if not external and not fatal and not job . checkOnly then
if job . generating ~= nil then
job . generating ( name )
end
local startedGenerating = progress . now ( )
local genDiags
local remarks = optimize . run ( result . result , {
level = config . _optLevel or 0 ,
filename = path ,
disabled = config . _disabledPasses ,
constSelection = job . constSelection ,
} )
optimizationAccounted = true
for _ , note in ipairs ( remarks ) do
optimizationRemarks [ # optimizationRemarks + 1 ] = note
end
for _ , site in ipairs ( optimize . allocationSites ( result . result ) ) do
allocationSites [ # allocationSites + 1 ] = { file = path , kind = site . kind , line = site . line , col = site . col , }
end
local emittedEffects





local hotRequest = config . _reload
and { mode = "initial" , module = name , libraries = config . _reloadLibraries or { } }
or nil
code , genDiags , coverage , emittedEffects = gen . generate (
result . result ,
path ,
config . _coverage and { path = path } or nil ,
hotRequest ,
nil ,
( ( target ) . _aotGpuSources or { } ) [ normalize ( path ) ] and { [ "runtime.gpu" ] = true } or nil
)




result . result . effects = emittedEffects
runtimeModules = runtimeImports ( name , code , config , target )
for effect in pairs ( emittedEffects ) do
effectNames [ # effectNames + 1 ] = effect
end
table . sort ( effectNames )
generated = true
for _ , diag in ipairs ( genDiags ) do
mine [ # mine + 1 ] = diag
end
if # genDiags == 0 then
artifactHash = job . contentDigest ( code )
end
generateMs = progress . now ( ) - startedGenerating
end
local moduleEffect = native . forModule ( name )
if moduleEffect ~= nil then
local found = false
for _ , effect in ipairs ( effectNames ) do
found = found or effect == moduleEffect
end
if not found then
effectNames [ # effectNames + 1 ] = moduleEffect ;
table . sort ( effectNames )
end
end
local checkedExports = result . exports or { }
local record = {
sourcePath = path ,
sourceHash = job . sourceHash ,
interfaceHash = modules . interfaceHash (
result . moduleType ,
checkedExports ,
external and job . sourceHash or nil ,
job . contentDigest
) ,
artifactHash = artifactHash ,
dependencies = jsonArray ( depNames ) ,
runtimeModules = runtimeModules ,
compilerRuntime = job . compilerRuntime or nil ,
projectDependencies = jsonArray ( inc . projectDependencies ( path ) ) ,
externalInputs = jsonArray ( inc . externalInputs ( path ) ) ,
effects = jsonArray ( effectNames ) ,
output = output ,
external = external or nil ,



diags = jsonArray ( checkedDiags ) ,
aotRefusals = refusals ,
aotKey = aotKey ,
aotFamilies = families ,
coverage = coverage ,
materializations = jsonArray ( materializeObserve . collect ( result . result and result . result . root , path ) ) ,
derives = jsonArray ( result . result and result . result . deriveObservations or { } ) ,
optimizationRemarks = optimizationRemarks ,
allocationSites = allocationSites ,
optimizationAccounted = optimizationAccounted ,
specializationHash = job . specializationHash ,
}

return { record = record , code = code , said = mine , generated = generated , generateMs = generateMs , }
end

local function buildModules ( root , outDir , config , target , oldState , newState , checkOnly , strict , stats , diagnostics

, checkState ,




narrow ,




reporter ,





overlays ,






authoredUnused ,




session ) 
local report = reporter or progress . new ( "never" )
local opened = session or openSession ( root , outDir , config , target , newState . dependencies , strict , reporter )
local inc = opened . inc
local checkMs = opened . checkMs






local contentDigest = fingerprint . contentDigest ( true )

local function hashFile ( path ) 
return fingerprint . hashFile ( path , contentDigest )
end

local substituted = { }
for path , text in pairs ( overlays or { } ) do
local at = normalize ( path )
substituted [ at ] = text
inc . openGeneratedDocument ( at , text )
end


local authoredLints = { }
for path , diagnostics in pairs ( authoredUnused or { } ) do
authoredLints [ normalize ( path ) ] = diagnostics
end





for _ , problem in ipairs ( inc . env . ambientTypeProblems or { } ) do
local diagnostic = {
filename = problem . path ,
line = problem . line ,
col = problem . col ,
offset = 0 ,
length = 1 ,
severity = "warning" ,
code = "NUPP0005" ,
msg = "type dependency declaration not imported: " .. problem . msg ,
help = "the declarations beside it were imported; pin a revision this compiler can read, or report the construct"
,
docs = "docs/learn/projects/integrations/luacats.md" ,
}
if diagnostics ~= nil then
diagnostics [ # diagnostics + 1 ] = diagnostic
else
require ( "nupp.compiler.diagnostics" ) . report ( { diagnostic } )
end
end

local linkedModules = { }
local stageBundled = opened . stageBundled

local linkingRuntimeSource = { }
local linkedRuntimeSource = { }
local packagedRuntimeModules = { }
local packagedCheckSources = { }
local stagingPackagedChecks = { }




local cacheCompatible = oldState . moduleCompilerHash == newState . moduleCompilerHash
and oldState . configHash == newState . configHash













local function sourceContentHash ( path ) 
local text = substituted [ path ]
if text ~= nil then


return contentDigest ( "compiler-generated\0" .. text )
end
local checked = inc . fileText ( path )
if checked ~= nil then
return contentDigest ( checked )
end




return hashFile ( path )
end





local function moduleDependencies ( name , path ) 
local previous = oldState . modules [ name ]
if cacheCompatible
and previous
and previous . sourcePath == path
and previous . sourceHash == sourceContentHash ( path )
and type ( previous . dependencies ) == "table"
then
return previous . dependencies
end

return inc . moduleDependencies ( path )
end



local browserTarget = target . host == "browser"


local selfContainedTarget = target . kind == nil
or target . kind == "modules"
or target . kind == "bundle"
or target . kind == "binary"
or target . kind == "component"

local enqueueLinked

local function compatibleModule ( name ) 
return moduleTargets . supports ( name , target . host )
end

local linkRuntimeSource
linkRuntimeSource = function ( name ) 
if linkedRuntimeSource [ name ] or linkingRuntimeSource [ name ] or not compatibleModule ( name ) then
return
end
linkingRuntimeSource [ name ] = true
local path = inc . modulePath ( name ) or stageBundled ( name )
if path ~= nil and not path : match ( "%.d%.nupp$" ) then
linkedModules [ name ] = true
if enqueueLinked ~= nil then
enqueueLinked ( name )
end
for _ , dependency in ipairs ( moduleDependencies ( name , path ) ) do
linkRuntimeSource ( dependency )
end
end
linkingRuntimeSource [ name ] = nil
linkedRuntimeSource [ name ] = true
end





local function stagePackagedChecks ( name ) 
if packagedCheckSources [ name ] or stagingPackagedChecks [ name ] then
return inc . modulePath ( name )
end
local existing = inc . modulePath ( name )
if existing ~= nil and not envMod . isDependencyTypePath ( inc . env , existing ) then
return nil
end
stagingPackagedChecks [ name ] = true
local path = stageBundled ( name , true )
if path ~= nil and not path : match ( "%.d%.nupp$" ) then
packagedCheckSources [ name ] = true
for _ , dependency in ipairs ( moduleDependencies ( name , path ) ) do
stagePackagedChecks ( dependency )
end
end
stagingPackagedChecks [ name ] = nil

return path
end





local function linkPackagedRuntime ( name ) 
local existing = inc . modulePath ( name )
if not selfContainedTarget
or (
existing ~= nil
and not envMod . isDependencyTypePath ( inc . env , existing )
and not packagedCheckSources [ name ]
)
then
return
end
local path = packagedCheckSources [ name ] and existing or stagePackagedChecks ( name )
if path ~= nil and not path : match ( "%.d%.nupp$" ) then
linkedModules [ name ] = true
packagedRuntimeModules [ name ] = true
end
end





local function linkFeatureRuntime ( effects ) 
if not browserTarget and not selfContainedTarget then
return
end
local named = { }
for _ , effect in ipairs ( effects ) do
named [ effect ] = true
end
for effect in pairs ( native . expand ( named ) ) do
local feature = native . feature ( effect )
if feature ~= nil and feature . runtimeModule ~= nil and ( feature . portableRuntime or not browserTarget ) then
local runtimeModule = feature . runtimeModule
linkRuntimeSource ( runtimeModule )
if linkedModules [ runtimeModule ] and enqueueLinked ~= nil then
enqueueLinked ( runtimeModule )
end
end
end
end

local function linkSelectedDependencies ( name , names , effects ) 
linkFeatureRuntime ( effects )
local selected = name == "nupp.spi" or ( linkedModules [ name ] == true and not packagedRuntimeModules [ name ] )
if not selected then
return
end
for _ , dependency in ipairs ( names ) do
linkRuntimeSource ( dependency )
end
end


















local queue , queuedPaths = { } , { }

local function seed ( name , path ) 
path = normalize ( path )
if queuedPaths [ path ] then
return
end
queuedPaths [ path ] = true
queue [ # queue + 1 ] = { name = name , path = path }
end









local asked = nil
if checkOnly and narrow and # narrow . paths > 0 then
asked = { }
for _ , path in ipairs ( narrow . paths ) do
local file = normalize ( path )
local name = envMod . moduleNameForPath ( inc . env , file )
if name then
asked [ name ] = true
seed ( name , file )
else
narrow . unchecked [ # narrow . unchecked + 1 ] = path
end
end
else
for _ , entry in ipairs ( target . entries or { } ) do
local path , name
if entry : match ( "%.nupp$" ) or entry : find ( "[/\\]" ) then
path = join ( root , entry )
name = envMod . moduleNameForPath ( inc . env , path )
else
name = entry
path = inc . modulePath ( entry )
end
if not path then
return nil , "entry not found: " .. entry
end
if not name then
return nil , "cannot determine module name for " .. path
end
seed ( name , path )
end
if # queue == 0 and ( target . kind or "modules" ) ~= "modules" then
return nil , "build.entries must contain at least one entry"
end





local sourceSet , sourceSetErr = selectedSourceFiles ( root , target )
if sourceSetErr then
return nil , sourceSetErr
end
for _ , path in ipairs ( sourceSet or envMod . listSourceFiles ( inc . env , false ) ) do
local name = envMod . moduleNameForPath ( inc . env , path )
if name then
seed ( name , path )
elseif sourceSet then
return nil , "cannot determine module name for selected source " .. path
end
end
for name in pairs ( linkedModules ) do
local path = inc . modulePath ( name )
if path ~= nil then
seed ( name , path )
end
end
end

local suppliedConstSelection = ( target ) . _constSelection
local constEnabled = not checkOnly and ( config . _optLevel or 0 ) >= 1 and not ( config . _disabledPasses or { } ) [ "OPT-8" ]



local parallelChecked = { }
local parallelCode = { }
local parallelAccepted = { }











if narrow == nil
and next ( oldState . modules or { } ) == nil
and next ( overlays or { } ) == nil
and suppliedConstSelection == nil
then
local parallelcheck = require ( "nupp.tools.build.parallelcheck" )
local linked = { }
for name in pairs ( linkedModules ) do
linked [ # linked + 1 ] = name
end
table . sort ( linked )
local produced = parallelcheck . run ( {
queue = queue ,
inc = inc ,
root = root ,
outDir = outDir ,
config = config ,
target = target ,
strict = strict ,
state = newState ,
staged = opened . staged ,
reporter = report ,
build = not checkOnly ,
constSelection = constEnabled and { accepted = { } , declined = { } } or nil ,
linked = linked ,
} )
if produced ~= nil then
for name in pairs ( produced . records ) do
parallelChecked [ name ] = true
end
for name , code in pairs ( produced . codes ) do
parallelCode [ name ] = code
end
oldState . modules = produced . records
oldState . moduleCompilerHash = newState . moduleCompilerHash
oldState . configHash = newState . configHash
cacheCompatible = true
end
end

local specializationPlans = { }
local acceptedSpecializations = { }
local declinedSpecializations = { }




local mayPlan = false
if constEnabled and next ( parallelChecked ) == nil then
for _ , item in ipairs ( queue ) do
local text = inc . fileText ( item . path )
if text == nil or ( text ) : find ( "[<,]%s*const%s+[%a_]" ) ~= nil then
mayPlan = true
do break end
end
end
end



local selectorMs = 0
if mayPlan then





local checkedForSpecialization = { }
local specializationCursor = 1
while specializationCursor <= # queue do
local item = queue [ specializationCursor ]
specializationCursor = specializationCursor + 1
local checked = inc . checkFile ( item . path )
if checked . result ~= nil and checked . missing ~= true and checked . syntax ~= true then
checkedForSpecialization [
# checkedForSpecialization + 1
] = { filename = item . path , module = item . name , result = checked . result , }
end
for _ , dependency in ipairs ( inc . moduleDependencies ( item . path ) ) do
local dependencyPath = inc . modulePath ( dependency )
if dependencyPath ~= nil and not packagedCheckSources [ dependency ] then
seed ( dependency , dependencyPath )
end
end
end
if suppliedConstSelection ~= nil then
specializationPlans = suppliedConstSelection . plans
acceptedSpecializations = suppliedConstSelection . accepted
declinedSpecializations = suppliedConstSelection . declined
else
local selectorStart = os . clock ( )
specializationPlans = constspecialize . collectGraph ( checkedForSpecialization )
acceptedSpecializations , declinedSpecializations = constspecialize . selectGraph ( specializationPlans )
selectorMs = ( os . clock ( ) - selectorStart ) * 1000
end
end





local constSelection = constEnabled
and { accepted = acceptedSpecializations , declined = declinedSpecializations , }
or nil
local acceptedBodies = 0
for _ , specialization in ipairs ( acceptedSpecializations ) do
if specialization . physical == specialization
and not ( suppliedConstSelection ~= nil and specialization . requiredAot )
then
acceptedBodies = acceptedBodies + 1
end
end
local specializationKeys = { }
for _ , plan in ipairs ( specializationPlans ) do
local keys = specializationKeys [ normalize ( plan . filename ) ]
if keys == nil then
keys = { }
specializationKeys [ normalize ( plan . filename ) ] = keys
end
for _ , specialization in ipairs ( plan . specializations ) do
keys [ # keys + 1 ] = specialization . key
end
end
local specializationHashes = { }
for path , keys in pairs ( specializationKeys ) do
table . sort ( keys )
specializationHashes [ path ] = contentDigest ( table . concat ( keys , "\0" ) )
end
local emptySpecializationHash = contentDigest ( "" )

local records , reused , codeFor , paths = { } , { } , { } , { }
local order = { }
local queued , cursor = { } , 1



report : expect ( # queue )



local generateMs = { }
stats = ( stats or { } )
stats . checkedModules , stats . generatedModules , stats . reusedModules = 0 , 0 , 0
stats . specializedBodies = acceptedBodies
report : addSpecialized ( acceptedBodies )





local said = { }






local addingCarriedRuntime = { }
local carriedRuntime = { }
local runtimeSourceRoot = join ( root , join ( outDir , "cache/runtime-source" ) )

local function addCarriedRuntime ( name ) 
if browserTarget then
return false
end



if name == "nupp.workers.native" then
return false
end
if records [ name ] ~= nil then
return records [ name ] . compilerRuntime == true
end
local existing = inc . modulePath ( name )
if existing ~= nil
and not envMod . isDependencyTypePath ( inc . env , existing )
and existing : sub ( 1 , # runtimeSourceRoot + 1 ) ~= runtimeSourceRoot .. "/"
then
return false
end
local bundled = require ( "nupp.compiler.bundled" )
local modulePath = name : gsub ( "^nupp%." , "" ) : gsub ( "%." , "/" ) .. ".lua"
local text = readFile ( join ( bundled . moduleDir ( ) , "../" .. modulePath ) )
or bundled . source ( "/" .. name : gsub ( "%." , "/" ) .. ".lua" )
local carried = rawget ( _G , "__nuppCompilerModuleArtifacts" )
local carriedRecord = carried and carried [ name ]
if text == nil and carriedRecord and type ( carriedRecord . source ) == "string" then
text = carriedRecord . source
end
if text == nil then
return false
end
if addingCarriedRuntime [ name ] then
return true
end
addingCarriedRuntime [ name ] = true
local required = runtimeImports ( name , text , config , target )
local carriedEffects = jsonArray ( { } )
if carriedRecord then
for _ , effect in ipairs ( carriedRecord . effects or { } ) do
carriedEffects [ # carriedEffects + 1 ] = effect
end
end
local moduleEffect = native . forModule ( name )
if moduleEffect ~= nil then
local found = false
for _ , effect in ipairs ( carriedEffects ) do
found = found or effect == moduleEffect
end
if not found then
carriedEffects [ # carriedEffects + 1 ] = moduleEffect
end
end
local output = join ( root , join ( outDir , name : gsub ( "%." , "/" ) .. ".lua" ) )
local artifactHash = contentDigest ( text )
records [
name
] = {
sourceHash = artifactHash ,
interfaceHash = contentDigest ( "compiler-runtime\0" .. text ) ,
artifactHash = artifactHash ,
dependencies = required ,
runtimeModules = required ,
compilerRuntime = true ,
projectDependencies = jsonArray ( { } ) ,
externalInputs = jsonArray ( { } ) ,
effects = carriedEffects ,
output = output ,
diags = jsonArray ( { } ) ,
materializations = jsonArray ( { } ) ,
derives = jsonArray ( { } ) ,
optimizationRemarks = jsonArray ( { } ) ,
allocationSites = jsonArray ( { } ) ,
optimizationAccounted = false ,
specializationHash = emptySpecializationHash ,
}
codeFor [ name ] = text
carriedRuntime [ name ] = true
paths [ name ] = output
local previous = oldState . modules [ name ]
if cacheCompatible
and previous
and previous . compilerRuntime
and previous . artifactHash == artifactHash
and ( checkOnly or hashFile ( output ) == artifactHash )
then
reused [ name ] = true
end
order [ # order + 1 ] = name
for _ , dependency in ipairs ( required ) do
if not addCarriedRuntime ( dependency ) then
linkPackagedRuntime ( dependency )
if enqueueLinked ~= nil then
enqueueLinked ( dependency )
end
end
end
addingCarriedRuntime [ name ] = nil

return true
end

local function enqueue ( name , path ) 
if queued [ name ] or records [ name ] or not compatibleModule ( name ) then
return
end
path = path or inc . modulePath ( name )
if path then
queued [ name ] = true
queue [ # queue + 1 ] = { name = name , path = normalize ( path ) }
end
end

enqueueLinked = function ( name ) 
if not addCarriedRuntime ( name ) then
enqueue ( name )
end
end

local configuredEffects = { }
for effect in pairs ( native . resolve ( nil , target . nativeFeatures ) ) do
configuredEffects [ # configuredEffects + 1 ] = effect
end
linkFeatureRuntime ( configuredEffects )

if # ( config . _spiEntries or { } ) > 0 then
linkRuntimeSource ( "nupp.spi" )
linkRuntimeSource ( "nupp.spi.index" )
for _ , provider in ipairs ( config . _spiEntries ) do
linkRuntimeSource ( provider . implementation )
end
end




local function isFatalIn ( diags ) 
for _ , diag in ipairs ( diags or { } ) do
if isFatal ( diag ) then
return true
end
end

return false
end

local aotApplies = checkOnly and aotcheck . applies ( target . aot )




local aotBackendKey = nil

local function currentAotKey ( ) 
if aotBackendKey == nil then
aotBackendKey = aotcheck . backendKey (
fingerprint . sharedCacheDir ( join ( root , join ( outDir , "cache" ) ) ) ,
contentDigest
)
end

return aotBackendKey
end






local function aotRefusals ( name , path , checked ) 
if not aotApplies
or checked == nil
or linkedModules [ name ]
or packagedRuntimeModules [ name ]
or not aotcheck . projectSource ( root , config . include , outDir , path )
then
return { } , false
end
local text = substituted [ normalize ( path ) ] or inc . fileText ( path )
if text == nil or ( text ) : find ( "@aot" , 1 , true ) == nil then
return { } , false
end

return aotcheck . refusals ( text , path , checked , target ) , true
end


local linkCompiled

local function compile ( name , path , sourceHash ) 
local external = path : match ( "%.d%.nupp$" ) ~= nil
or envMod . isDependencyTypePath ( inc . env , path ) and not linkedModules [ name ]
local result = inc . checkFile ( path )
stats . checkedModules = stats . checkedModules + 1
local compiled = modules . compileChecked ( {
name = name ,
path = path ,
sourceHash = sourceHash ,
checked = result ,
inc = inc ,
root = root ,
outDir = outDir ,
config = config ,
target = target ,
checkOnly = checkOnly == true ,
external = external ,
constSelection = constSelection ,
specializationHash = specializationHashes [ normalize ( path ) ] or emptySpecializationHash ,
rewritten = substituted [ normalize ( path ) ] ~= nil ,
authoredLints = authoredLints [ normalize ( path ) ] ,
aotRefusals = aotRefusals ,
aotKey = currentAotKey ,
compilerRuntime = packagedRuntimeModules [ name ] ,
contentDigest = contentDigest ,
generating = function ( generatingName ) 
report : at ( "generate" )
report : step ( "generating " .. generatingName )
end ,
} )
if compiled . generated then
stats . generatedModules = stats . generatedModules + 1
generateMs [ name ] = ( generateMs [ name ] or 0 ) + compiled . generateMs
end
said [ name ] = compiled . said
records [ name ] = compiled . record
codeFor [ name ] = compiled . code
reused [ name ] = nil
linkCompiled ( name , compiled . record )
end

linkCompiled = function ( name , record ) 
local depNames = record . dependencies
local runtimeModules = record . runtimeModules
linkSelectedDependencies ( name , depNames , record . effects )
for _ , runtimeModule in ipairs ( runtimeModules ) do
if not addCarriedRuntime ( runtimeModule ) then
linkPackagedRuntime ( runtimeModule )
enqueue ( runtimeModule )
end
end
for _ , depName in ipairs ( depNames ) do
if linkedModules [ name ] and not packagedRuntimeModules [ name ] then
linkRuntimeSource ( depName )
elseif browserTarget and inc . modulePath ( depName ) == nil then


linkRuntimeSource ( depName )
end
if not packagedCheckSources [ depName ] or packagedRuntimeModules [ depName ] then
enqueue ( depName )
end
end
end

local function processQueue ( ) 
while cursor <= # queue do
local item = queue [ cursor ]
cursor = cursor + 1
queued [ item . name ] = nil
if not records [ item . name ] then
local path = item . path
paths [ item . name ] = path
order [ # order + 1 ] = item . name



report : at ( "scan" )
report : step ( item . name )
local sourceHash = sourceContentHash ( path )
local previous = oldState . modules [ item . name ]
local external = path : match ( "%.d%.nupp$" ) ~= nil
or envMod . isDependencyTypePath ( inc . env , path ) and not linkedModules [ item . name ]
local output = nil
if not external then
output = join ( root , join ( outDir , item . name : gsub ( "%." , "/" ) .. ".lua" ) )
end



local usable = cacheCompatible
and previous
and previous . sourcePath == path
and previous . sourceHash == sourceHash
and previous . specializationHash == (
specializationHashes [ normalize ( path ) ] or emptySpecializationHash
)
and previous . interfaceHash
and type ( previous . dependencies ) == "table"
and type ( previous . projectDependencies ) == "table"
and type ( previous . externalInputs ) == "table"
and type ( previous . effects ) == "table"
and type ( previous . runtimeModules ) == "table"
and type ( previous . diags ) == "table"
and type ( previous . aotRefusals ) == "table"
and ( previous . aotKey == nil or previous . aotKey == currentAotKey ( ) )
and type ( previous . materializations ) == "table"
and type ( previous . derives ) == "table"
and type ( previous . optimizationRemarks ) == "table"
and type ( previous . allocationSites ) == "table"
and type ( previous . optimizationAccounted ) == "boolean"
if usable and previous then
for _ , dependency in ipairs ( previous . projectDependencies or { } ) do
if type ( dependency ) ~= "table" then
usable = false
do break end
end
local dependencyName = dependency . name
local dependencyKey = dependency . key
local dependencyFingerprint = dependency . fingerprint
if type ( dependencyName ) ~= "string"
or type ( dependencyKey ) ~= "string"
or type ( dependencyFingerprint ) ~= "string"
then
usable = false
do break end
end
if not GUARANTEE_QUERY [ dependencyName ]
and inc . projectDependencyFingerprint (
dependencyName ,
dependencyKey
) ~= dependencyFingerprint
then
usable = false
do break end
end
end
end
if usable and previous then



for _ , input in ipairs ( previous . externalInputs or { } ) do
if type ( input ) ~= "table"
or type ( input . path ) ~= "string"
or type ( input . fingerprint ) ~= "string"
or inc . externalInputFingerprint ( input . path ) ~= input . fingerprint
then
usable = false
do break end
end
end
end
local builtCode = parallelCode [ item . name ]
if usable and previous and builtCode ~= nil then


usable = previous . artifactHash ~= nil and contentDigest ( builtCode ) == previous . artifactHash
elseif usable and previous and not checkOnly and not external then
usable = previous . artifactHash ~= nil and hashFile ( output ) == previous . artifactHash
end
if usable and previous and parallelChecked [ item . name ] then
parallelAccepted [ item . name ] = true
end
if usable and previous and builtCode ~= nil then

local record = copyModuleRecord ( previous )
record . output = output
record . external = external or nil
records [ item . name ] = record
codeFor [ item . name ] = builtCode
reused [ item . name ] = nil
said [ item . name ] = previous . diags
stats . checkedModules = stats . checkedModules + 1
stats . generatedModules = stats . generatedModules + 1
linkCompiled ( item . name , record )
elseif usable and previous then
records [ item . name ] = copyModuleRecord ( previous )
records [ item . name ] . output = output
records [ item . name ] . external = external or nil
reused [ item . name ] = true




said [ item . name ] = previous . diags
linkSelectedDependencies ( item . name , previous . dependencies or { } , previous . effects or { } )
for _ , runtimeModule in ipairs ( previous . runtimeModules or { } ) do
if not addCarriedRuntime ( runtimeModule ) then
linkPackagedRuntime ( runtimeModule )
enqueue ( runtimeModule )
end
end
for _ , depName in ipairs ( previous . dependencies or { } ) do
if not packagedCheckSources [ depName ] or packagedRuntimeModules [ depName ] then
enqueue ( depName )
end
end
else
compile ( item . name , path , sourceHash )
end
report : resolved ( )
end
end
end














local function refusalScope ( ) 
local pending = { }
local seeds = false
for _ , entry in ipairs ( target . entries or { } ) do
seeds = true
local name = entry
if entry : match ( "%.nupp$" ) or entry : find ( "[/\\]" ) then
name = envMod . moduleNameForPath ( inc . env , join ( root , entry ) )
end
if name == nil then
return nil
end
pending [ # pending + 1 ] = name
end
if target . sources ~= nil then
seeds = true
for _ , path in ipairs ( selectedSourceFiles ( root , target ) or { } ) do
local name = envMod . moduleNameForPath ( inc . env , path )
if name == nil then
return nil
end
pending [ # pending + 1 ] = name
end
end
if not seeds then
return nil
end
for _ , provider in ipairs ( config . _spiEntries or { } ) do
pending [ # pending + 1 ] = provider . implementation
end
local reached = { }
while # pending > 0 do
local name = table . remove ( pending )
if not reached [ name ] then
reached [ name ] = true
local record = records [ name ] or oldState . modules [ name ]
if record == nil then
if inc . modulePath ( name ) ~= nil then
return nil
end
else
for _ , dependency in ipairs ( record . dependencies or { } ) do
pending [ # pending + 1 ] = dependency
end
end
end
end

return reached
end

processQueue ( )
local invalidated = true
while invalidated do
invalidated = false
for _ , name in ipairs ( order ) do
local record = records [ name ]
if reused [ name ] and record and not carriedRuntime [ name ] then
local dependencyChanged = false
for _ , depName in ipairs ( record . dependencies or { } ) do
local depPath = inc . modulePath ( depName )



if depPath and not ( parallelChecked [ name ] and not parallelChecked [ depName ] ) then
local current = records [ depName ]
local previous = oldState . modules [ depName ]
if not current or not previous or current . interfaceHash ~= previous . interfaceHash then
dependencyChanged = true
do break end
end
end
end
if not dependencyChanged then
for _ , dependency in ipairs ( record . projectDependencies or { } ) do
if type ( dependency ) == "table" and GUARANTEE_QUERY [ dependency . name ] then






local named = tostring ( dependency . key ) : match ( "^([^%z]+)" )
if not ( named ~= nil and reused [ named ] and records [ named ] ) then
if inc . projectDependencyFingerprint (
dependency . name ,
dependency . key
) ~= dependency . fingerprint then
dependencyChanged = true
do break end
end
end
end
end
end
if dependencyChanged then
compile ( name , paths [ name ] , record . sourceHash )
invalidated = true
end
end
end
processQueue ( )
end












if aotApplies then
local dependents = { }
for _ , name in ipairs ( order ) do
local record = records [ name ]
if record and not carriedRuntime [ name ] then
for _ , dependency in ipairs ( record . dependencies or { } ) do
local list = dependents [ dependency ] or { }
list [ # list + 1 ] = name
dependents [ dependency ] = list
end
end
end
for _ , name in ipairs ( order ) do
local record = records [ name ]
local families = record and record . aotFamilies or nil
if record and families and # families > 0 and not carriedRuntime [ name ] then
local callers = { }
local seen = { [ name ] = true }
local pending = { name }
while # pending > 0 do
for _ , dependent in ipairs ( dependents [ table . remove ( pending ) ] or { } ) do
if not seen [ dependent ] then
seen [ dependent ] = true
pending [ # pending + 1 ] = dependent
local path = paths [ dependent ]
local text = path and ( substituted [ normalize ( path ) ] or inc . fileText ( path ) ) or nil
local mentions = false
for _ , family in ipairs ( families ) do
mentions = mentions or ( text ~= nil and ( text ) : find ( family , 1 , true ) ~= nil )
end
if mentions
and not linkedModules [ dependent ]
and aotcheck . projectSource ( root , config . include , outDir , path )
then
callers [ # callers + 1 ] = dependent
end
end
end
end
table . sort ( callers )
if # callers == 0 then


if not asked then
record . aotGraphRefusals , record . aotGraphKey = nil , nil
end
else
local keyed = { currentAotKey ( ) , name , record . sourceHash or "" }
for _ , caller in ipairs ( callers ) do
keyed [ # keyed + 1 ] = caller .. "=" .. tostring ( records [ caller ] . sourceHash )
end
local key = hash . digest ( table . concat ( keyed , "\0" ) )
if record . aotGraphKey ~= key or type ( record . aotGraphRefusals ) ~= "table" then
local path = paths [ name ]
local text = substituted [ normalize ( path ) ] or inc . fileText ( path )
local own = inc . checkFile ( path )
local graph = { { filename = path , module = name , result = own . result } }
local complete = own . result ~= nil and not isFatalIn ( own . diags ) and text ~= nil
for _ , caller in ipairs ( callers ) do
local checked = inc . checkFile ( paths [ caller ] )
complete = complete and checked . result ~= nil and not isFatalIn ( checked . diags )
graph [ # graph + 1 ] = { filename = paths [ caller ] , module = caller , result = checked . result }
end



if complete then
local found = jsonArray ( { } )
local plans = constspecialize . collectGraph ( graph )
for _ , diag in ipairs (
aotcheck . refusals ( text , path , own . result , target , plans )
) do
found [ # found + 1 ] = diag
end
record . aotGraphRefusals , record . aotGraphKey = found , key
else
record . aotGraphRefusals , record . aotGraphKey = nil , nil
end
end
end
end
end
end





local compiledModules = 0
local rechecked = 0
for _ , name in ipairs ( order ) do
if not carriedRuntime [ name ] then
if reused [ name ] and not parallelChecked [ name ] then
stats . reusedModules = stats . reusedModules + 1
else
compiledModules = compiledModules + 1
end
if parallelChecked [ name ] and not parallelAccepted [ name ] then
rechecked = rechecked + 1
end
end
end
if next ( parallelChecked ) ~= nil and report . parallelFacts ~= nil then
report . parallelFacts . rechecked = rechecked
end
local factCounts , seenFacts = { } , { }
local factConsumers , uniqueFacts , selectionChanges = 0 , 0 , 0
for _ , name in ipairs ( order ) do
local record = records [ name ]
for _ , edge in ipairs ( record . projectDependencies or { } ) do
if edge . name == "moduleCallableFact" then
factConsumers = factConsumers + 1
if not seenFacts [ edge . key ] then
seenFacts [ edge . key ] , uniqueFacts = true , uniqueFacts + 1
local family = edge . key : match ( "[^%z]+$" ) or "unknown"
factCounts [ family ] = ( factCounts [ family ] or 0 ) + 1
end
end
end
local previous = oldState . modules and oldState . modules [ name ]
if record . specializationHash
and record . specializationHash ~= ( previous and previous . specializationHash or emptySpecializationHash )
then
selectionChanges = selectionChanges + 1
end
end
report . optimizerFacts = {
produced = inc . q . stats . moduleCallableFact or 0 ,
consumed = factConsumers ,
unique = uniqueFacts ,
families = factCounts ,
selectorMs = selectorMs ,
selectionChangedModules = selectionChanges
}

report : counted ( compiledModules , stats . reusedModules )
for _ , name in ipairs ( order ) do
local spent = ( checkMs [ paths [ name ] or "" ] or 0 ) + ( generateMs [ name ] or 0 )
if spent > 0 then
report : spent ( name , spent )
end
end






report : at ( "persist" )
report : step ( "saving what this run worked out" )
inc . persist ( )
if checkOnly and checkState then
local checked = { }

















if asked and cacheCompatible then
for name , record in pairs ( oldState . modules or { } ) do
checked [ name ] = record
end
end
for _ , name in ipairs ( order ) do
checked [ name ] = records [ name ]
end
newState . modules = checked
checkState . set ( newState )
checkState . save ( )
end









local errors = { }
local aotScope = aotApplies and refusalScope ( ) or nil
for _ , name in ipairs ( order ) do
if not asked or asked [ name ] then
for _ , diag in ipairs ( said [ name ] or { } ) do
errors [ # errors + 1 ] = diag
end
if aotScope == nil or aotScope [ name ] then
local record = records [ name ]
local refused = record and ( record . aotGraphRefusals or record . aotRefusals ) or nil
for _ , diag in ipairs ( refused or { } ) do
errors [ # errors + 1 ] = diag
end
end
end
end
local fatal , checkFailed = false , false
for _ , e in ipairs ( errors ) do
if isFatal ( e ) then
fatal = true


if not e . code or e . code : sub ( 1 , 5 ) ~= "NUPP3" then
checkFailed = true
end
end
end
if diagnostics then
for _ , diagnostic in ipairs ( errors ) do
diagnostics [ # diagnostics + 1 ] = diagnostic
end
elseif # errors > 0 then


report : clear ( )
printErrors ( errors )
end
if fatal then
return nil , checkFailed and "project has errors" or "code generation failed"
end
local materializations = { }
local derives = { }
local optimizationRemarks = { }
local allocationSites = { }
local accountedModules = 0
for _ , name in ipairs ( order ) do
for _ , observation in ipairs ( records [ name ] . materializations or { } ) do
materializations [ # materializations + 1 ] = observation
end
for _ , observation in ipairs ( records [ name ] . derives or { } ) do
derives [ # derives + 1 ] = observation
end
if records [ name ] . optimizationAccounted then
accountedModules = ( accountedModules + 1 )
for _ , remark in ipairs ( records [ name ] . optimizationRemarks or { } ) do
optimizationRemarks [ # optimizationRemarks + 1 ] = remark
end
for _ , site in ipairs ( records [ name ] . allocationSites or { } ) do
allocationSites [ # allocationSites + 1 ] = site
end
end
end
if checkOnly then
return {
outputs = { } ,
materializations = materializations ,
derives = derives ,
optimizationRemarks = optimizationRemarks ,
allocationSites = allocationSites ,
accountedModules = accountedModules
}
end





local pending


= { }
local outputs = { }
local effects = { }
newState . modules = { }
for _ , name in ipairs ( order ) do
local record = records [ name ]
newState . modules [ name ] = record
for _ , effect in ipairs ( record . effects or { } ) do
effects [ effect ] = true
end
if record . output then
outputs [ record . output ] = true
end
if not record . external and not reused [ name ] then
local code = codeFor [ name ]
if code and hashFile ( record . output ) ~= record . artifactHash then
pending [ # pending + 1 ] = { path = record . output , text = code }
end
end
end

for _ , name in ipairs ( order ) do
if not records [ name ] . external and not records [ name ] . artifactHash then
return nil , "code generation failed"
end
end

for _ , resource in ipairs ( target . resources or { } ) do
local pattern
if type ( resource ) == "table" then
pattern = ( resource ) . source
else
pattern = resource
end
for _ , source in ipairs ( expandGlob ( root , pattern ) ) do
local output = join ( root , join ( outDir , resourceOutput ( config , resource , source , root ) ) )
local text , err = readFile ( source )
if not text then
return nil , err
end
outputs [ output ] = true
if hashFile ( output ) ~= contentDigest ( text ) then
pending [ # pending + 1 ] = { path = output , text = text }
end
end
end
report : at ( "write" )
for _ , item in ipairs ( pending ) do
report : step ( "writing " .. shortPath ( root , item . path ) )
local ok , err = writeFile ( item . path , item . text )
if not ok then
return nil , err
end
end




require ( "nupp.tools.bytecodecache" ) . refresh ( join ( root , outDir ) , newState . modules )

return {
outputs = outputs ,
effects = effects ,
materializations = materializations ,
derives = derives ,
optimizationRemarks = optimizationRemarks ,
allocationSites = allocationSites ,
accountedModules = accountedModules
}
end















local function targetScope ( root , target , session ) 
if target . sources == nil and # ( target . entries or { } ) == 0 then
return nil , nil
end
local inc = session . inc
local reached = { }
local queue = { }

local function seed ( path ) 
local file = normalize ( path )
if not reached [ file ] then
reached [ file ] = true
queue [ # queue + 1 ] = file
end
end

for _ , entry in ipairs ( target . entries or { } ) do
local path = nil
if entry : match ( "%.nupp$" ) or entry : find ( "[/\\]" ) then
path = join ( root , entry )
else
path = inc . modulePath ( entry )
end
if path == nil then
return nil , "entry not found: " .. entry
end
seed ( path )
end
local selected , selectedErr = selectedSourceFiles ( root , target )
if selectedErr then
return nil , selectedErr
end
for _ , path in ipairs ( selected or { } ) do
seed ( path )
end


for _ , implementation in ipairs ( inc . env . config . _spiEntries or { } ) do
local path = inc . modulePath ( implementation . implementation )
or session . stageBundled ( implementation . implementation )
if path ~= nil then
seed ( path )
end
end
local cursor = 1
while cursor <= # queue do
local path = queue [ cursor ]
cursor = cursor + 1
for _ , dependency in ipairs ( inc . moduleDependencies ( path ) ) do
local dependencyPath = inc . modulePath ( dependency )
if dependencyPath ~= nil then
seed ( dependencyPath )
end
end
end

return reached , nil
end

modules . targetScope = targetScope
modules . typeFingerprint = typeFingerprint
modules . resourceOutput = resourceOutput
modules . build = buildModules

modules . session = openSession

local __nuppExportValue= modules ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.modules"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.modules"]=__nuppExports;return __nuppExports