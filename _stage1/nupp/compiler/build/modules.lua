_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);









local envMod = require ( "nupp.compiler.env" )
local gen = require ( "nupp.compiler.gen" )
local optimize = require ( "nupp.compiler.optimize" )
local hash = require ( "nupp.compiler.build.hash" )
local incremental = require ( "nupp.compiler.incremental" )
local diagnosticMod = require ( "nupp.compiler.diagnostics" )
local fs = require ( "nupp.compiler.fs" )
local cache = require ( "nupp.compiler.build.cache" )
local deps = require ( "nupp.compiler.build.deps" )
local materializeObserve = require ( "nupp.compiler.materialize.observe" )
local progress = require ( "nupp.compiler.build.progress" )

local normalize , join = fs . normalize , fs . join
local readFile , writeFile = fs . readFile , fs . writeFile
local stable , hashFile , jsonArray = cache . stable , cache . hashFile , cache . jsonArray
local expandGlob = deps . expandGlob
local isFatal , printErrors = diagnosticMod . isFatal , diagnosticMod . report

local modules = { }

local function exportDeprecationsFingerprint ( exports )
local items = { }
for _ , field in ipairs ( { "typeDefs" , "valueDefs" } ) do
for name , definition in pairs ( exports and exports [ field ] or { } ) do
local deprecated = definition . deprecated
if deprecated then
items [
# items + 1
] = field .. ":" .. name .. ":" .. stable ( deprecated . reason ) .. ":" .. stable ( deprecated . replacement )
end
end
end
table . sort ( items )

return table . concat ( items , "\0" )
end
























































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

local function packFingerprint (
pack ,
active ,
binders
)
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

typeFingerprint = function (
t ,
active ,
binders
)
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
templates [
# templates + 1
] = type (
part
) == "string" and "text(" .. stable (
part
) .. ")" or typeFingerprint ( part , active , binders )
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

local function resourceOutput (
config ,
resource ,
source ,
root
)
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
local effects = jsonArray ( { } )
for _ , effect in ipairs ( record . effects or { } ) do
effects [ # effects + 1 ] = effect
end
local projectDependencies = jsonArray ( { } )
for _ , dependency in ipairs ( record . projectDependencies or { } ) do
projectDependencies [
# projectDependencies + 1
] = { name = dependency . name , key = dependency . key , fingerprint = dependency . fingerprint , }
end

return {
sourceHash = record . sourceHash ,
interfaceHash = record . interfaceHash ,
artifactHash = record . artifactHash ,
dependencies = dependencies ,
projectDependencies = projectDependencies ,
effects = effects ,
output = record . output ,
external = record . external ,
diags = record . diags ,
coverage = record . coverage ,
materializations = record . materializations ,
derives = record . derives ,
}
end

local function buildModules ( root , outDir , config , target , oldState , newState , checkOnly , strict , stats , diagnostics

, checkState ,




narrow ,




reporter )
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
local rocks = deps . rockPaths ( root , config , target , newState . dependencies )






local checkMs = { }
local open


= { }


local resumeActivity = "scan"
local rootPrefix = normalize ( root )
local function shortPath ( path )
if rootPrefix ~= "." and path : sub ( 1 , # rootPrefix + 1 ) == rootPrefix .. "/" then
return path : sub ( # rootPrefix + 2 )
end

return path
end

local observer = {
checking = function ( path )




if # open == 0 then
resumeActivity = report . activity
report : at ( "check" )
end
open [ # open + 1 ] = { startedAt = progress . now ( ) , children = 0 }
report : step ( "checking " .. shortPath ( path ) )
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
typeRoots = rocks and rocks . typeRoots or { } ,
observe = observer ,
} )




local cacheCompatible = oldState . compilerHash == newState . compilerHash
and oldState . configHash == newState . configHash
















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
if # queue == 0 then
return nil , "build.entries must contain at least one entry"
end




for _ , path in ipairs ( envMod . listSourceFiles ( inc . env , false ) ) do
local name = envMod . moduleNameForPath ( inc . env , path )
if name then
seed ( name , path )
end
end
end

local records , reused , codeFor , paths = { } , { } , { } , { }
local order , queued , cursor = { } , { } , 1



report : expect ( # queue )



local generateMs = { }
stats = ( stats or { } )
stats . checkedModules , stats . generatedModules , stats . reusedModules = 0 , 0 , 0





local said = { }

local function enqueue ( name , path )
if queued [ name ] or records [ name ] then
return
end
path = path or inc . modulePath ( name )
if path then
queued [ name ] = true
queue [ # queue + 1 ] = { name = name , path = normalize ( path ) }
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

local function compile ( name , path , sourceHash )
local external = envMod . isDependencyTypePath ( inc . env , path )
local result = inc . checkFile ( path )
stats . checkedModules = stats . checkedModules + 1
local mine = { }
for _ , diag in ipairs ( result . diags or { } ) do
mine [ # mine + 1 ] = diag
end
local fatal = isFatalIn ( mine )
local depNames = inc . moduleDependencies ( path )
local effectNames = { }
if fatal or checkOnly or external then
for effect in pairs ( result . result . effects or { } ) do
effectNames [ # effectNames + 1 ] = effect
end
table . sort ( effectNames )
end
local output = external and nil or join ( root , join ( outDir , name : gsub ( "%." , "/" ) .. ".lua" ) )
local artifactHash , code , coverage
if not external and not fatal and not checkOnly then
report : at ( "generate" )
report : step ( "generating " .. name )
local startedGenerating = progress . now ( )
local genDiags
local remarks = optimize . run ( result . result , {
level = config . _optLevel or 0 ,
filename = path ,
disabled = config . _disabledPasses ,
relaxed = config . _relaxedGuarantees
} )
if config . _remarks then
for _ , note in ipairs ( remarks ) do
mine [ # mine + 1 ] = note
end
end
local emittedEffects
code , genDiags , coverage , emittedEffects = gen . generate (
result . result ,
path ,
config . _coverage and { path = path } or nil
)




result . result . effects = emittedEffects
for effect in pairs ( emittedEffects ) do
effectNames [ # effectNames + 1 ] = effect
end
table . sort ( effectNames )
stats . generatedModules = stats . generatedModules + 1
for _ , diag in ipairs ( genDiags or { } ) do
mine [ # mine + 1 ] = diag
end
if # genDiags == 0 then
artifactHash = hash . digest ( code )
end
generateMs [ name ] = ( generateMs [ name ] or 0 ) + ( progress . now ( ) - startedGenerating )
end
said [ name ] = mine
local materializations = materializeObserve . collect ( result . result and result . result . root , path )
local derives = result . result and result . result . deriveObservations or { }
local projectDependencies = inc . projectDependencies ( path )
local checkedExports = result . exports or { }
records [ name ] = {
sourceHash = sourceHash ,
interfaceHash = hash . digest (
typeFingerprint (
result . moduleType
) .. "\0deprecated\0" .. exportDeprecationsFingerprint (
checkedExports
) .. "\0nominal-callables:" .. (
checkedExports . nominalEffectFingerprint or ""
) .. "\0derives:" .. (
checkedExports . deriveInterfaceFingerprint or ""
) .. "\0comptime-functions:" .. (
checkedExports . comptimeFunctionFingerprint or ""
) .. ( external and ( "\0" .. sourceHash ) or "" )
) ,
artifactHash = artifactHash ,
dependencies = jsonArray ( depNames ) ,
projectDependencies = jsonArray ( projectDependencies ) ,
effects = jsonArray ( effectNames ) ,
output = output ,
external = external or nil ,



diags = jsonArray ( result . diags or { } ) ,
coverage = coverage ,
materializations = jsonArray ( materializations ) ,
derives = jsonArray ( derives ) ,
}
codeFor [ name ] = code
reused [ name ] = nil
for _ , depName in ipairs ( depNames ) do
enqueue ( depName )
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
local sourceHash = hashFile ( path )
local previous = oldState . modules [ item . name ]
local external = envMod . isDependencyTypePath ( inc . env , path )
local output = external and nil or join ( root , join ( outDir , item . name : gsub ( "%." , "/" ) .. ".lua" ) )



local usable = cacheCompatible
and previous
and previous . sourceHash == sourceHash
and previous . interfaceHash
and type (
previous . dependencies
) == "table" and type (
previous . projectDependencies
) == "table" and type (
previous . effects
) == "table" and type (
previous . diags
) == "table" and type ( previous . materializations ) == "table" and type ( previous . derives ) == "table"
if usable and previous then
for _ , dependency in ipairs ( previous . projectDependencies or { } ) do
if type ( dependency ) ~= "table" then
usable = false
break
end
local dependencyName = dependency . name
local dependencyKey = dependency . key
local dependencyFingerprint = dependency . fingerprint
if type (
dependencyName
) ~= "string" or type ( dependencyKey ) ~= "string" or type ( dependencyFingerprint ) ~= "string" then
usable = false
break
end
if inc . projectDependencyFingerprint (
dependencyName ,
dependencyKey
) ~= dependencyFingerprint then
usable = false
break
end
end
end
if usable and previous and not checkOnly and not external then
usable = previous . artifactHash and hashFile ( output ) == previous . artifactHash
end
if usable and previous then
records [ item . name ] = copyModuleRecord ( previous )
records [ item . name ] . output = output
records [ item . name ] . external = external or nil
reused [ item . name ] = true




said [ item . name ] = previous . diags
for _ , depName in ipairs ( previous . dependencies or { } ) do
enqueue ( depName )
end
else
compile ( item . name , path , sourceHash )
end
report : resolved ( )
end
end
end

processQueue ( )
local invalidated = true
while invalidated do
invalidated = false
for _ , name in ipairs ( order ) do
local record = records [ name ]
if reused [ name ] and record then
local dependencyChanged = false
for _ , depName in ipairs ( record . dependencies or { } ) do
local depPath = inc . modulePath ( depName )
if depPath then
local current = records [ depName ]
local previous = oldState . modules [ depName ]
if not current or not previous or current . interfaceHash ~= previous . interfaceHash then
dependencyChanged = true
break
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





for _ , name in ipairs ( order ) do
if reused [ name ] then
stats . reusedModules = stats . reusedModules + 1
end
end


report : counted ( # order - stats . reusedModules , stats . reusedModules )
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








if asked then
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
for _ , name in ipairs ( order ) do
if not asked or asked [ name ] then
for _ , diag in ipairs ( said [ name ] or { } ) do
errors [ # errors + 1 ] = diag
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
for _ , name in ipairs ( order ) do
for _ , observation in ipairs ( records [ name ] . materializations or { } ) do
materializations [ # materializations + 1 ] = observation
end
for _ , observation in ipairs ( records [ name ] . derives or { } ) do
derives [ # derives + 1 ] = observation
end
end
if checkOnly then
return { outputs = { } , materializations = materializations , derives = derives }
end





local pending , outputs = { } , { }
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
if hashFile ( output ) ~= hash . digest ( text ) then
pending [ # pending + 1 ] = { path = output , text = text }
end
end
end
report : at ( "write" )
for _ , item in ipairs ( pending ) do
report : step ( "writing " .. shortPath ( item . path ) )
local ok , err = writeFile ( item . path , item . text )
if not ok then
return nil , err
end
end

return { outputs = outputs , effects = effects , materializations = materializations , derives = derives }
end

modules . typeFingerprint = typeFingerprint
modules . resourceRelative = resourceRelative
modules . resourceOutput = resourceOutput
modules . build = buildModules

return modules
