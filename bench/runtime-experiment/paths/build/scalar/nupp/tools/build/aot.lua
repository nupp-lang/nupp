_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.build.aot\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.tools.build.aot\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.tools.build.aot\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.tools.build.aot\0runtime\0004") , _G.nupp.__reflect.declaration("nupp.tools.build.aot\0runtime\0005") , _G.nupp.__reflect.declaration("nupp.tools.build.aot\0runtime\0006") , _G.nupp.__reflect.declaration("nupp.tools.build.aot\0runtime\0007") , _G.nupp.__reflect.declaration("nupp.tools.build.aot\0runtime\0008") , _G.nupp.__reflect.declaration("nupp.tools.build.aot\0runtime\0009") };


































const json = require ( "nupp.codec.json" )

local bindingRules = require ( "nupp.compiler.aot.binding" )
local gpuBinding = require ( "nupp.compiler.aot.gpubinding" )
local wasmBinding = require ( "nupp.compiler.aot.wasmbinding" )
local wasmBridge = require ( "nupp.compiler.aot.wasmbridge" )
local aotcheck = require ( "nupp.tools.build.aotcheck" )
local aotllvm = require ( "nupp.tools.build.aotllvm" )
local compile = require ( "nupp.compiler.aot.compile" )
local constspecialize = require ( "nupp.compiler.lua.constspecialize" )
local diagnosticMod = require ( "nupp.compiler.diagnostics" )
local fs = require ( "nupp.compiler.fs" )
local envMod = require ( "nupp.compiler.project.env" )
local compilerFingerprint = require ( "nupp.compiler.project.fingerprint" )
local stable = require ( "nupp.compiler.stable" )
local hash = require ( "nupp.compiler.hash" )
local progress = require ( "nupp.tools.build.progress" )
local toolruns = require ( "nupp.tools.build.toolruns" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )
local targets = require ( "nupp.compiler.aot.target" )
local profiles = require ( "nupp.compiler.targetprofile" )

local isFatal = diagnosticMod . isFatal

local aot = { }

local compilerResourceFingerprintMemo = nil








function aot . compilerResourceFingerprint ( contentDigest ) 
if compilerResourceFingerprintMemo ~= nil then
return compilerResourceFingerprintMemo
end
local digest = contentDigest or hash . digest
local bundled = require ( "nupp.compiler.bundled" )
local list = require ( "nupp.compiler.bundledlist" ) . list
local paths = { }
for _ , prefix in ipairs ( { "/aot/llvm" , "/nupp" } ) do
for _ , path in ipairs ( list ( prefix ) ) do
paths [ # paths + 1 ] = path
end
end


if bundled . source ( "/re.g.nupp" ) ~= nil then
paths [ # paths + 1 ] = "/re.g.nupp"
end
table . sort ( paths )
local parts = { }
for _ , path in ipairs ( paths ) do
parts [ # parts + 1 ] = path .. "\0" .. digest ( bundled . source ( path ) or "missing" )
end
compilerResourceFingerprintMemo = digest ( table . concat ( parts , "\0" ) )

return compilerResourceFingerprintMemo
end


aot . POLICIES = { [ "off" ] = true , [ "require" ] = true , [ "emit-wasm" ] = true , [ "require-wasm" ] = true , }


function aot . linksNative ( policy ) 
return policy == "require"
end

function aot . linksWasm ( policy ) 
return policy == "emit-wasm" or policy == "require-wasm"
end


aot.Toolchain = {} aot.Toolchain.__index = aot.Toolchain ;_G.nupp.__reflect.link(aot.Toolchain,__nuppT1[1],{ })








aot . BACKEND = "llvm"













function aot . key ( irText , selected ) 
return hash . digest (
stable ( {
ir = irText ,
irVersion = scalarIR . VERSION ,
numericContract = scalarIR . NUMERIC_CONTRACT ,
numericForRuntime = targets . numericForRuntime ( selected ) ,
triple = selected . triple ,
tier = selected . tier ,
backend = aot . BACKEND ,
compiler = compilerFingerprint . toolFingerprint ( ) ,
} )
)
end










function aot . inputFingerprint ( sources , semantic , contentDigest ) 
local digest = contentDigest or hash . digest
local files = { }
local seen = { }
for _ , path in ipairs ( sources ) do
if path : match ( "%.nupp$" ) ~= nil or path : match ( "%.lua$" ) ~= nil then
local canonical = fs . canonical ( path )
if not seen [ canonical ] then
seen [ canonical ] = true
files [ # files + 1 ] = path
end
end
end
table . sort ( files )
local sources = { }
for _ , path in ipairs ( files ) do
sources [ # sources + 1 ] = { path = fs . normalize ( path ) , digest = compilerFingerprint . hashFile ( path , digest ) , }
end

return digest ( stable ( { version = 1 , semantic = semantic , sources = sources , } ) )
end



function aot . libraryKey ( keys , chain , flags , linkage ) 
local ordered = { }
for _ , one in ipairs ( keys ) do
ordered [ # ordered + 1 ] = one
end



table . sort ( ordered )

return hash . digest ( stable ( { artifacts = ordered , toolchain = chain . version , flags = flags , linkage = linkage , } ) )
end


aot.Emitted = {} aot.Emitted.__index = aot.Emitted ;_G.nupp.__reflect.link(aot.Emitted,__nuppT1[2],{ })








































function aot . objectOf ( output ) 
return ( output : gsub ( "%.ll$" , ".o" ) )
end


aot.Remembered = {} aot.Remembered.__index = aot.Remembered ;_G.nupp.__reflect.link(aot.Remembered,__nuppT1[3],{ })











function aot . toolchainPolicy ( policy , targetTriple , contentDigest ) 
local _ = contentDigest

return { policy = policy , target = targetTriple , desiredCommand = "<llvm>" , codegen = aotllvm . selection ( ) , }
end







local function mentionsAot ( text ) 
return text : find ( "@aot" , 1 , true ) ~= nil
end





function aot . mentionsGpuTarget ( text ) 
return ( text : find ( "@aot" , 1 , true ) ~= nil ) and text : match ( "target%s*=%s*[\"']gpu[\"']" ) ~= nil
end

local mentionsGpuTarget = aot . mentionsGpuTarget























local function checkedTree ( session , source ) 
local checked = session . inc . checkFile ( source )
if checked . missing == true or checked . syntax == true or checked . result == nil then
return nil , { }
end
local authored = { }
for _ , diagnostic in ipairs ( checked . diags or { } ) do
if isFatal ( diagnostic ) then
return nil , { }
end
if ( diagnostic ) . code == "NUPP2507" then
authored [ # authored + 1 ] = diagnostic
end
end

return checked . result , authored
end


function aot . librarySuffix ( selected ) 
local system = targets . system ( selected . triple )
if system == "darwin" then
return ".dylib"
elseif system == "windows" then
return ".dll"
end

return ".so"
end

















function aot . dispatch (
source ,
programs ,
sites ,
gpuArtifacts ,
library ,
tiers ,
constFamilies ,
browser ,
archive
) 
local rewritten = source
local replacements = { }
local detectorAt = nil
for position , site in ipairs ( sites ) do


if programs [ position ] ~= nil
and programs [ position ] . executionTarget ~= "gpu"
and programs [ position ] . nativeOnly ~= true
then
detectorAt = detectorAt == nil and site . from or math . min ( detectorAt , site . from )
end
end
for _ , family in ipairs ( constFamilies or { } ) do
detectorAt = detectorAt == nil and family . site . from or math . min ( detectorAt , family . site . from )
end
for _ , family in ipairs ( constFamilies or { } ) do
replacements [
# replacements + 1
] = {
site = family . site ,
text = bindingRules . familyReplacement ( family , library , tiers , family . site . from == detectorAt , archive ) ,
}
end
for position = 1 , # programs do
local site = sites [ position ]
if site ~= nil then
local program = programs [ position ]
local replacement
if program . executionTarget == "gpu" then
local artifact = gpuArtifacts [ program . symbol ]
assert ( artifact ~= nil , "GPU program has no emitted shader" )
replacement = gpuBinding . replacement ( program , artifact , browser )
else
replacement = bindingRules . replacement (
program ,
library ,
tiers ,
site . from == detectorAt ,
archive ,
site . header
)
end
replacements [ # replacements + 1 ] = { site = site , text = replacement , }
end
end
table . sort ( replacements , function ( a , b ) 
return a . site . from > b . site . from
end )
for _ , replacement in ipairs ( replacements ) do
local site = replacement . site
rewritten = rewritten : sub ( 1 , site . from - 1 ) .. replacement . text .. rewritten : sub ( site . to + 1 )
end

return rewritten
end



function aot . wasmDispatch (
source ,
programs ,
sites ,
units ,
gpuArtifacts ,
constFamilies
) 
local rewritten = source
local replacements = { }
for _ , family in ipairs ( constFamilies or { } ) do
replacements [ # replacements + 1 ] = { site = family . site , text = wasmBinding . familyReplacement ( family , units ) }
end
for position , program in ipairs ( programs ) do
local site = sites [ position ]
if site ~= nil then
local replacement = program . executionTarget == "gpu"
and gpuBinding . replacement ( program , gpuArtifacts [ program . symbol ] , true )
or wasmBinding . replacement ( program , units )
replacements [ # replacements + 1 ] = { site = site , text = replacement }
end
end
table . sort ( replacements , function ( a , b ) 
return a . site . from > b . site . from
end )
for _ , replacement in ipairs ( replacements ) do
local site = replacement . site
rewritten = rewritten : sub ( 1 , site . from - 1 ) .. replacement . text .. rewritten : sub ( site . to + 1 )
end

return rewritten
end


aot.WasmModule = {} aot.WasmModule.__index = aot.WasmModule ;_G.nupp.__reflect.link(aot.WasmModule,__nuppT1[4],{ })












aot.WasmOutcome = {} aot.WasmOutcome.__index = aot.WasmOutcome ;_G.nupp.__reflect.link(aot.WasmOutcome,__nuppT1[5],{ __nuppT1[4] })




















function aot . wasmModuleKey ( source , version , tier ) 
return hash . digest ( stable ( { ir = source , codegen = version , tier = tier , backend = aot . BACKEND } ) )
end


const WASM_TRIPLE = "wasm32-unknown-emscripten"








function aot . compileWasm (
emitted ,
produced ,
previous ,
reporter
) 
local report = reporter or progress . new ( "never" )
local version = aotllvm . version ( )
local known = previous or { }
local outputs = { }
local keys = { version }
local modules = { }
local units = { }
local moduleKeys = { }
local digests = { }
local reused = 0
local dirty = { }
local staged = { }

report : at ( "aot:emit" )
for _ , one in ipairs ( emitted ) do
if one . detector ~= true then
local artifacts = produced [ one . cacheKey ]
if artifacts == nil then
return nil , "missing Wasm AOT artifacts for " .. one . source
end
local validation = wasmBridge . validate ( ( artifacts ) . programs )
if validation ~= nil then
return nil , validation
end
one . wasmSource = one . output
one . bridge = wasmBridge . metadata ( ( artifacts ) . programs , one . tier )
one . unit = "u" .. one . key : sub ( 1 , 16 )
units [ # units + 1 ] = one
moduleKeys [ # moduleKeys + 1 ] = aot . wasmModuleKey ( fs . readFile ( one . output ) or "" , version , one . tier )
end
end

report : at ( "aot:reuse" )
for position , one in ipairs ( units ) do
local record = known [ one . cacheKey ]


if record ~= nil
and ( record ) . key == moduleKeys [ position ]
and fs . exists ( ( record ) . output )
then
reused = reused + 1
one . wasm = ( record ) . output
digests [ position ] = ( record ) . digest
else
local stagedPath = one . output : gsub ( "%.ll$" , ".tmp.wasm" )
os . remove ( stagedPath )
dirty [ # dirty + 1 ] = position
staged [ # staged + 1 ] = stagedPath
end
end

if # dirty > 0 then

report : at ( "aot:compile" )
local compiled = { }
for _ , index in ipairs ( dirty ) do
local one = units [ index ]
compiled [
# compiled + 1
] = _G.setmetatable({ ir =
one . output ,  triple =
WASM_TRIPLE ,  tier =
one . tier ,  object =
( one . output : gsub ( "%.ll$" , ".o" ) ) }, aotllvm.Unit)

end
local compileErr = aotllvm . compileMany ( compiled )
if compileErr ~= nil then
return nil , compileErr
end
local first = units [ dirty [ 1 ] ]
local libm , libmErr = aotllvm . wasmLibm ( first . output : match ( "^(.*/aot)/" ) or fs . dirname ( first . output ) )
if libm == nil then
return nil , libmErr
end
for position , index in ipairs ( dirty ) do
local one = units [ index ]
local exports = { }
for _ , entry in ipairs ( ( one . bridge ) . entries ) do
exports [ # exports + 1 ] = entry . call
for _ , layout in ipairs ( entry . layouts ) do
exports [ # exports + 1 ] = layout . prefix .. "_size"
for _ , field in ipairs ( layout . fields ) do
exports [ # exports + 1 ] = layout . prefix .. "_offset_" .. field
exports [ # exports + 1 ] = layout . prefix .. "_size_" .. field
end
end
end
local linkErr = aotllvm . linkWasm ( compiled [ position ] . object , staged [ position ] , exports , libm )
if linkErr ~= nil then
return nil , linkErr
end
end


report : at ( "aot:emit" )
for position , index in ipairs ( dirty ) do
local one = units [ index ]
local stagedPath = staged [ position ]
local wasm , readErr = fs . readFile ( stagedPath )
os . remove ( stagedPath )
if wasm == nil then
return nil , tostring ( readErr )
end
local wasmDigest = hash . digest ( wasm )
local output = one . output : gsub ( "%.ll$" , "" ) .. "." .. wasmDigest : sub ( 1 , 16 ) .. ".wasm"
if fs . readFile ( output ) ~= wasm then
local wrote , writeErr = fs . writeFile ( output , wasm )
if not wrote then
return nil , tostring ( writeErr )
end
end
one . wasm = output
digests [ index ] = wasmDigest
end
end

for position , one in ipairs ( units ) do
local output = one . wasm
local digest = digests [ position ]
modules [
one . cacheKey
] = _G.setmetatable({ key =  moduleKeys [ position ] ,  output =  output ,  digest =  digest }, aot.WasmModule)
outputs [ # outputs + 1 ] = one . output
outputs [ # outputs + 1 ] = output
keys [ # keys + 1 ] = one . key
keys [ # keys + 1 ] = digest
end

return _G.setmetatable({ outputs =
outputs ,  key =
hash . digest ( table . concat ( keys , "\0" ) ) ,  toolchain =
version ,  modules =
modules ,  reused =
reused ,  compiled =
# dirty }, aot.WasmOutcome)
, nil
end


function aot . libraryFile ( name , suffix ) 
local stem = name : gsub ( "[^%w_]" , "_" )
if suffix == ".dll" then
return stem .. "_aot" .. suffix
end

return "lib" .. stem .. "_aot" .. suffix
end


function aot . libraryPath ( outDir , name , suffix ) 
return outDir .. "/lib/" .. aot . libraryFile ( name , suffix )
end













function aot . libraryReference ( name , suffix ) 
return "@lib/" .. aot . libraryFile ( name , suffix )
end


aot.LinkOutcome = {} aot.LinkOutcome.__index = aot.LinkOutcome ;_G.nupp.__reflect.link(aot.LinkOutcome,__nuppT1[6],{ })




















function aot . objectKey ( unitKey , tier , chain , flags ) 
return hash . digest (
stable ( {
unit = unitKey ,
tier = tier ,
toolchain = chain . version ,
flags = flags ,
backend = aot . BACKEND ,
} )
)
end























function aot . link (
chain ,
selected ,
emitted ,
output ,
static ,
previous ,
reporter ,
root
) 
local report = reporter or progress . new ( "never" )
if not fs . mkdir ( fs . dirname ( output ) ) then
return "could not create " .. fs . dirname ( output ) , nil
end

local known = previous or { }
local objects = { }
local objectKeys = { }
local reused = 0
local dirty = { }

report : at ( "aot:reuse" )
for index , one in ipairs ( emitted ) do
local object = aot . objectOf ( one . output )
local objectKey = aot . objectKey ( one . key , one . tier , chain , aotllvm . flags ( selected . triple , one . tier ) )
objectKeys [ one . cacheKey ] = objectKey
one . object = object
objects [ # objects + 1 ] = object



if known [ one . cacheKey ] == objectKey and fs . exists ( object ) then
reused = reused + 1
else
dirty [ # dirty + 1 ] = index
end
end

if # dirty > 0 then
report : at ( "aot:compile" )
local units = { }
for _ , index in ipairs ( dirty ) do
local one = emitted [ index ]
units [
# units + 1
] = _G.setmetatable({ ir =
one . output ,  triple =
selected . triple ,  tier =
one . tier ,  object =
one . object }, aotllvm.Unit)

end
local compileErr = aotllvm . compileMany ( units )
if compileErr ~= nil then
return compileErr , nil
end
end
table . sort ( objects )

local outcome = _G.setmetatable({ objects =  objectKeys ,  reused =  reused ,  compiled =  # dirty ,  linked =  true }, aot.LinkOutcome)
report : at ( "aot:link" )


local linkErr = nil
if static then
linkErr = aotllvm . archive ( selected . triple , objects , output )
else
linkErr = aotllvm . link ( selected . triple , objects , output , root )
end
if linkErr ~= nil then
return linkErr , nil
end

return nil , outcome
end


















function aot . emit (
root ,
outDir ,
roots ,
previous ,
session ,
features ,
triple ,
staticLinkage ,
reporter ,
scope ,
work
) 
local report = reporter or progress . new ( "never" )
local counted = work or { }
counted . checkedSources = 0
counted . loweredPrograms = 0
counted . optimizedPrograms = 0
counted . emittedUnits = 0




local function at ( step ) 
report : at ( "aot:" .. step )
end

local produced = { }
local gpuSources = { }
bindingRules . passRuntime = aotllvm . takesRuntime ( triple )


local authoredUnused = { }
local selected , targetErr = targets . buildTiers ( triple , features )
if selected == nil then
return nil , tostring ( targetErr ) , produced , authoredUnused , nil , gpuSources
end

local emitted = { }
local seen = { }
local sources = { }
local sourceText = { }
local sourceDirectory = { }
local sourceListed = { }
local checkedBySource = { }
local checkedModules = { }
local sourceRoots = { }
for _ , directory in ipairs ( roots ) do
sourceRoots [ # sourceRoots + 1 ] = directory
end



if # sourceRoots == 0 then
sourceRoots [ 1 ] = ""
end
for _ , listed in ipairs ( envMod . listSourceFilesFor ( session . inc . env , root , roots , fs . join ( root , outDir ) , false ) ) do
local normalized = fs . normalize ( listed )
local directory = nil
local longest = -1
for _ , candidate in ipairs ( sourceRoots ) do
local base = fs . normalize ( fs . join ( root , candidate ) )
if ( base == "." or normalized == base or normalized : sub ( 1 , # base + 1 ) == base .. "/" )
and # base > longest
then
directory = candidate
longest = # base
end
end
if directory ~= nil then


local source = listed
local name = envMod . moduleNameForPath ( session . inc . env , listed )
local resolved = name ~= nil and session . inc . modulePath ( name ) or nil
if resolved ~= nil and resolved ~= listed and fs . canonical ( resolved ) == fs . canonical ( listed ) then
source = resolved
end
if not seen [ source ]
and source : match ( "%.nupp$" ) ~= nil
and ( scope == nil or ( scope ) [ fs . normalize ( source ) ] == true )
then
seen [ source ] = true
local text = fs . readFile ( source )
if text ~= nil then
sources [ # sources + 1 ] = source
sourceText [ source ] = text
sourceDirectory [ source ] = directory
sourceListed [ source ] = listed
end
end
end
end
table . sort ( sources )
local selectedPolicy = session . inc . env . config . _target and session . inc . env . config . _target . aot or nil
if selectedPolicy == "require" then
for _ , source in ipairs ( sources ) do
if mentionsGpuTarget ( sourceText [ source ] ) then
session . stageGpuRuntime ( )
do break end
end
end
elseif selectedPolicy == "require-wasm" then
for _ , source in ipairs ( sources ) do
if mentionsGpuTarget ( sourceText [ source ] ) then
session . stageGpuRuntime ( )
do break end
end
end
end
local checkedSources = { }




local resumeChecking = report : charging ( "aot:check" )
report : at ( "aot:check" )
for _ , source in ipairs ( sources ) do
local checkedSource , unusedHere = checkedTree ( session , source )
if checkedSource ~= nil then
counted . checkedSources = counted . checkedSources + 1
checkedSources [ # checkedSources + 1 ] = source
checkedBySource [ source ] = checkedSource
checkedModules [
# checkedModules + 1
] = { filename = source , module = envMod . moduleNameForPath ( session . inc . env , source ) , result = checkedSource , }
if mentionsAot ( sourceText [ source ] ) then
authoredUnused [ source ] = unusedHere
end
end
end
sources = checkedSources
report : charging ( resumeChecking )
local constPlans = constspecialize . collectGraph ( checkedModules )
local acceptedConst , declinedConst = constspecialize . selectGraph ( constPlans )
local constSelection = { accepted = acceptedConst , declined = declinedConst , plans = constPlans , }
for _ , source in ipairs ( sources ) do
local text = sourceText [ source ]
local tree = checkedBySource [ source ]
local directory = sourceDirectory [ source ]
if ( text : find ( "@aot" , 1 , true ) ~= nil ) then
for tierPosition , tierTarget in ipairs ( selected ) do
local artifacts , diagnostics = compile . artifacts (
text ,
source ,
tree ,
"<object>" ,
tierTarget ,
tierTarget . tier ,
constPlans ,
true ,
at
)
if artifacts == nil then



local first = diagnostics [ 1 ]
if first ~= nil and first . code ~= compile . NO_AOT_FUNCTION then
local rendered = "feature tier " .. tierTarget . tier .. ": " .. compile . renderDiagnostic ( first )
return nil , rendered , produced , authoredUnused , constSelection , gpuSources , first
end
do break end
else
local cpuFunctions = 0
for _ , program in ipairs ( ( artifacts ) . programs ) do
if program . executionTarget ~= "gpu" then
cpuFunctions = cpuFunctions + 1
end
end
if tierPosition == 1 then
produced [ source ] = artifacts
if next ( ( artifacts ) . gpu ) ~= nil then
gpuSources [ # gpuSources + 1 ] = source
end
end
if cpuFunctions == 0 then
do break end
end
counted . loweredPrograms = counted . loweredPrograms + # ( artifacts ) . programs
counted . optimizedPrograms = counted . optimizedPrograms + # ( artifacts ) . programs
counted . emittedUnits = counted . emittedUnits + 1





















local base = fs . join ( root , directory ) : gsub ( "^%./" , "" )
local listed = ( sourceListed [ source ] ) : gsub ( "^%./" , "" )
local relative = listed
if listed : sub ( 1 , # base + 1 ) == base .. "/" then
relative = listed : sub ( # base + 2 )
end
local prefix = directory : gsub ( "^%./" , "" ) : gsub ( "%.%./" , "up/" ) : gsub ( "/$" , "" )
if prefix : sub ( 1 , 1 ) == "/" or prefix : match ( "^[A-Za-z]:/" ) then
prefix = "absolute/" .. hash . digest ( fs . canonical ( base ) )
end
local stem = ( prefix == "" and relative or prefix .. "/" .. relative ) : gsub ( "%.nupp$" , "" )
local output = outDir .. "/aot/" .. stem .. "." .. tierTarget . tier .. ".ll"
local cacheKey = source .. "#" .. tierTarget . tier


local available , backendErr = aotllvm . selected ( )
if available ~= true then
return nil , tostring ( backendErr ) , produced , authoredUnused , constSelection , gpuSources
end





local canonicalSource = fs . canonical ( source )
local canonicalRoot = fs . canonical ( root ) : gsub ( "/*$" , "/" )
local lineFile = canonicalSource : sub ( 1 , # canonicalRoot ) == canonicalRoot
and canonicalSource : sub ( # canonicalRoot + 1 )
or canonicalSource
local ir , why = aotllvm . emit ( artifacts . programs , tierTarget . tier , tierTarget . triple , nil , lineFile )
if ir == nil then
return nil , ("%s: the LLVM backend cannot compile the %s tier: %s")

: format (
source ,
tierTarget . tier ,
tostring ( why )
) , produced , authoredUnused , constSelection , gpuSources
end
local content = ir
local backend = aotllvm . BACKEND
local key = hash . digest (
stable ( {
base = aot . key ( artifacts . irText , tierTarget ) ,
backend = aotllvm . BACKEND ,
codegen = aotllvm . version ( ) ,
facts = aotllvm . factsKey ( ) ,
wasmOracle = aotllvm . wasmOracle ( )
} )
)



report : at ( "aot:reuse" )
local reused = previous [ cacheKey ] == key and fs . readFile ( output ) == content
report : at ( "aot:emit" )
if not reused then
local ok , err = fs . writeFile ( output , content )
if not ok then
return nil , tostring ( err ) , produced , authoredUnused , constSelection , gpuSources
end
end
emitted [
# emitted + 1
] = _G.setmetatable({ source =
source ,  tier =
tierTarget . tier ,  cacheKey =
cacheKey ,  output =
output ,  key =
key ,  backend =
backend }, aot.Emitted)

produced [ cacheKey ] = artifacts
end
end
end
end





if # emitted > 0
and # ( selected ) > 1
and ( selected ) [ 1 ] . architecture ~= "wasm32"
then
local triple = ( selected ) [ 1 ] . triple
local found = aotllvm . detector ( triple )
if found == nil then
return nil , "the LLVM backend has no feature detector for "
.. triple , produced , authoredUnused , constSelection , gpuSources
end
local detector = found
local output = outDir .. "/aot/features.ll"
local backend = aotllvm . BACKEND
local cacheKey = "@feature-detector"
local key = hash . digest (
stable ( {
ir = detector ,
triple = triple ,
compiler = compilerFingerprint . toolFingerprint ( ) ,
backend = backend ,
} )
)
if previous [ "@feature-detector" ] ~= key or fs . readFile ( output ) ~= detector then
local ok , err = fs . writeFile ( output , detector )
if not ok then
return nil , tostring ( err ) , produced , authoredUnused , constSelection , gpuSources
end
end
emitted [
# emitted + 1
] = _G.setmetatable({ source =
"<feature-detector>" ,  tier =
"baseline" ,  cacheKey =
cacheKey ,  output =
output ,  key =
key ,  detector =
true ,  role =
"feature-detector" ,  backend =
backend }, aot.Emitted)

end

return emitted , nil , produced , authoredUnused , constSelection , gpuSources
end


aot.Result = {} aot.Result.__index = aot.Result ;_G.nupp.__reflect.link(aot.Result,__nuppT1[7],{ __nuppT1[2] , __nuppT1[4] , __nuppT1[3] , __nuppT1[8] })
































































aot.Facts = {} aot.Facts.__index = aot.Facts ;_G.nupp.__reflect.link(aot.Facts,__nuppT1[8],{ })














aot.Carried = {} aot.Carried.__index = aot.Carried ;_G.nupp.__reflect.link(aot.Carried,__nuppT1[9],{ __nuppT1[4] , __nuppT1[3] })










local function replayFile ( files , path ) 
if path ~= nil then
files [ path ] = compilerFingerprint . hashFile ( path ) or "missing"
end
end









function aot . captureReplay ( policy , result ) 
local files = { }
local emitted = { }
for _ , one in ipairs ( result . emitted ) do
replayFile ( files , one . output )
replayFile ( files , one . object )
replayFile ( files , one . wasmSource )
replayFile ( files , one . wasm )
emitted [
# emitted + 1
] = {
source = one . source ,
tier = one . tier ,
cacheKey = one . cacheKey ,
output = one . output ,
key = one . key ,
object = one . object ,
detector = one . detector ,
role = one . role ,
wasmSource = one . wasmSource ,
wasm = one . wasm ,
registrar = one . registrar ,
bridge = one . bridge ,
unit = one . unit ,
}
end
replayFile ( files , result . library )
replayFile ( files , result . manifest )
if result . manifest ~= nil then
local linkManifest = fs . join ( fs . dirname ( result . manifest ) , "link.json" )
if fs . exists ( linkManifest ) then
replayFile ( files , linkManifest )
end
end
for _ , path in ipairs ( result . wasmModules or { } ) do
replayFile ( files , path )
end

local selection = result . constSelection
local hasConstSelection = selection ~= nil
and type ( ( selection ) . plans ) == "table"
and # ( ( selection ) . plans ) > 0
local payload = {
version = 1 ,
policy = policy ,
backend = aotllvm . selection ( ) ,
hasConstSelection = hasConstSelection ,
files = files ,
emitted = emitted ,
specializedBodies = result . specializedBodies ,
library = result . library ,
libraryKey = result . libraryKey ,
toolchain = result . toolchain ,
manifest = result . manifest ,
dispatch = result . dispatch ,
remarks = result . remarks ,
authoredUnused = result . authoredUnused ,
wasmModules = result . wasmModules ,
gpu = result . gpu ,
gpuSources = result . gpuSources ,
objects = result . objects ,
modules = result . modules ,
remembered = result . remembered ,
}

return { payload = payload , digest = hash . digest ( stable ( payload ) ) , }
end

local function countMap ( values ) 
local count = 0
for _ in pairs ( values or { } ) do
count = count + 1
end

return count
end

function aot . replayCommandMatches ( policy , remembered , desired ) 
if policy ~= "require" and policy ~= "require-wasm" and policy ~= "emit-wasm" then
return true
end

return remembered ~= nil and desired ~= nil and desired == ( remembered ) . command
end





function aot . replay ( snapshot , desiredCommand ) 
if snapshot == nil or type ( snapshot . payload ) ~= "table" or type ( snapshot . digest ) ~= "string" then
return nil
end
local payload = snapshot . payload
if payload . version ~= 1
or type ( payload . emitted ) ~= "table"
or payload . hasConstSelection == true
or hash . digest ( stable ( payload ) ) ~= snapshot . digest
then
return nil
end
local native = payload . policy == "require"
local wasm = payload . policy == "require-wasm" or payload . policy == "emit-wasm"
for path , digest in pairs ( payload . files or { } ) do
if compilerFingerprint . hashFile ( path ) ~= digest then
return nil
end
end


if payload . backend ~= aotllvm . selection ( ) then
return nil
end
local remembered = payload . remembered
if ( native or wasm ) and not aot . replayCommandMatches ( payload . policy , remembered , desiredCommand ) then
return nil
end
if remembered ~= nil and remembered . version ~= aotllvm . version ( ) then
return nil
end

local units = # payload . emitted

return ( _G.setmetatable({ emitted =
payload . emitted ,  specializedBodies =
payload . specializedBodies or 0 ,  library =
payload . library ,  libraryKey =
payload . libraryKey ,  toolchain =
payload . toolchain ,  manifest =
payload . manifest ,  dispatch =
payload . dispatch or { } ,  remarks =
payload . remarks ,  authoredUnused =
payload . authoredUnused ,  wasmModules =
payload . wasmModules ,  gpu =
payload . gpu ,  gpuSources =
payload . gpuSources ,  objects =
payload . objects ,  modules =
payload . modules ,  remembered =
payload . remembered ,  facts =
_G.setmetatable({ units =
units ,  checkedSources =
0 ,  loweredPrograms =
0 ,  optimizedPrograms =
0 ,  emittedUnits =
0 ,  reusedObjects =
native and units or 0 ,  compiledObjects =
0 ,  reusedModules =
wasm and countMap ( payload . modules ) or 0 ,  compiledModules =
0 ,  linked =
false ,  externalCommands =
0 }, aot.Facts) }, aot.Result) )


end








function aot . archiveIdentity ( name ) 
return hash . digest ( name ) : sub ( 1 , 16 )
end







function aot . archiveFingerprint ( emitted ) 
local keys = { }
for _ , one in ipairs ( emitted ) do
keys [ # keys + 1 ] = one . cacheKey .. "\0" .. one . key
end
table . sort ( keys )

return tonumber ( hash . digest ( table . concat ( keys , "\n" ) ) : sub ( 1 , 12 ) , 16 )
end





function aot . writeArchiveProbe (
outDir ,
name ,
selected ,
emitted
) 
local symbol = "ks_aot_archive_" .. aot . archiveIdentity ( name )
local fingerprint = aot . archiveFingerprint ( emitted )
local unit = ("define i64 @%s() {\n  ret i64 %d\n}\n") : format ( symbol , fingerprint )
local output = outDir .. "/aot/archive.ll"
local backend = aotllvm . BACKEND
if fs . readFile ( output ) ~= unit then
local ok , err = fs . writeFile ( output , unit )
if not ok then
return nil , nil , tostring ( err )
end
end

return _G.setmetatable({ source =
"<archive-probe>" ,  tier =
selected . tier ,  cacheKey =
"@archive-probe" ,  output =
output ,  key =
hash . digest (
stable ( {
ir = unit ,
triple = selected . triple ,
compiler = compilerFingerprint . toolFingerprint ( ) ,
} )
) ,  detector =
true ,  role =
"archive-probe" ,  backend =
backend }, aot.Emitted)
, _G.setmetatable({ symbol =  symbol ,  fingerprint =  fingerprint }, bindingRules.Archive) , nil
end




aot . UNITS_SCHEMA_VERSION = 3




function aot . readUnitsManifest ( path ) 
local text , readErr = fs . readFile ( path )
if not text then
return nil , tostring ( readErr )
end
local document , decodeErr = json . decode ( text )
if type ( document ) ~= "table" then
return nil , path .. " is not a units manifest: " .. tostring ( decodeErr or "not a JSON object" )
end
local found = ( document ) . schemaVersion
if found ~= aot . UNITS_SCHEMA_VERSION then
return nil , ("%s has schemaVersion %s, and this compiler reads %d; rebuild it with this compiler")

: format ( path , tostring ( found ) , aot . UNITS_SCHEMA_VERSION )
end

return document
end








local function sortedJson ( value ) 
if type ( value ) ~= "table" or value == json . EMPTY_ARRAY or value == json . EMPTY_OBJECT or value == json . NULL then
return json . encode ( value )
end
local entries = value
local parts = { }
if json . isArray ( entries ) then
for index = 1 , # entries do
parts [ index ] = sortedJson ( entries [ index ] )
end

return "[" .. table . concat ( parts , "," ) .. "]"
end
local keys = { }
for key in pairs ( entries ) do
if type ( key ) ~= "string" then
error ( "JSON object keys must be strings" , 0 )
end
keys [ # keys + 1 ] = key
end
table . sort ( keys )
for index , key in ipairs ( keys ) do
parts [ index ] = json . encode ( key ) .. ":" .. sortedJson ( entries [ key ] )
end

return "{" .. table . concat ( parts , "," ) .. "}"
end



function aot . writeUnitsManifest ( outDir , triple , emitted ) 
if # emitted == 0 then
return nil , nil
end
local units = { }
local prefix = outDir .. "/aot/"
for _ , one in ipairs ( emitted ) do
local flags = { }
if one . detector ~= true then
for _ , flag in ipairs ( aotllvm . flags ( triple , one . tier ) ) do
flags [ # flags + 1 ] = flag
end
end
units [
# units + 1
] = {
source = one . output : gsub ( "^" .. prefix : gsub ( "%p" , "%%%0" ) , "" ) ,
tier = one . tier ,
cflags = json . asArray ( flags ) ,
detector = one . role == "feature-detector" ,
role = one . role ,
wasm = one . wasm and ( one . wasm ) : gsub ( "^" .. prefix : gsub ( "%p" , "%%%0" ) , "" ) or nil ,
registrar = one . registrar ,
bridge = one . bridge ,
unit = one . unit ,
}
end
local document = sortedJson ( {
schemaVersion = aot . UNITS_SCHEMA_VERSION ,
target = triple ,
units = json . asArray ( units ) ,
} ) .. "\n"
local output = outDir .. "/aot/units.json"
if fs . readFile ( output ) ~= document then
local ok , err = fs . writeFile ( output , document )
if not ok then
return nil , tostring ( err )
end
end

return output , nil
end















function aot . writeLinkManifest (
outDir ,
name ,
profile ,
archive ,
library ,
emitted ,
produced ,
tiers
) 
local kernels = { }
local registrars = { }
local builders = { }
local builderSymbols = { }
local builderEntries = { }
local builderOrder = { }
for _ , one in ipairs ( emitted ) do
local artifacts = produced [ one . cacheKey ]
for _ , program in ipairs ( artifacts ~= nil and ( artifacts ) . programs or { } ) do
if program . executionTarget ~= "gpu" then
kernels [ # kernels + 1 ] = targets . symbol ( program . symbol , one . tier )
local registrar = program . registrar
if registrar ~= nil then




local key = registrar
local symbol = targets . symbol ( key , one . tier )
registrars [ # registrars + 1 ] = symbol
if builderSymbols [ key ] == nil then
builderSymbols [ key ] = { }
builderEntries [ key ] = program . name
builderOrder [ # builderOrder + 1 ] = key
end
local symbols = builderSymbols [ key ]
symbols [ # symbols + 1 ] = symbol
end
end
end
end
table . sort ( kernels )
table . sort ( registrars )
table . sort ( builderOrder )
for _ , key in ipairs ( builderOrder ) do
builders [
# builders + 1
] = { key = key , entry = builderEntries [ key ] , symbols = json . asArray ( builderSymbols [ key ] ) , }
end
local document = sortedJson ( {
schemaVersion = 1 ,
component = name ,
target = profile . target ,
os = profile . os ,
archive = library ~= nil and ( library ) : gsub ( "^" .. outDir : gsub ( "%p" , "%%%0" ) .. "/" , "" ) or nil ,
fingerprint = { symbol = archive . symbol , value = archive . fingerprint , } ,
symbols = { probe = archive . symbol , kernels = json . asArray ( kernels ) , registrars = json . asArray ( registrars ) , } ,
builders = json . asArray ( builders ) ,
retain = { forceLoad = json . asArray ( profile . forceLoad ) , export = json . asArray ( profile . export ) , } ,
tiers = json . asArray ( tiers ) ,
} ) .. "\n"
local output = outDir .. "/aot/link.json"
if fs . readFile ( output ) ~= document then
local ok , err = fs . writeFile ( output , document )
if not ok then
return nil , tostring ( err )
end
end

return output , nil
end











function aot . apply (
policy ,
root ,
outDir ,
roots ,
name ,
previous ,
previousLibraryKey ,
session ,
features ,
triple ,
linkage ,
carried ,
reporter ,
scope
) 
local report = reporter or progress . new ( "never" )
local held = carried or _G.setmetatable({ }, aot.Carried)
toolruns . reset ( )
local wasmPolicy = aot . linksWasm ( policy )

triple , features = aotcheck . selection ( policy , triple , features )
local work = { checkedSources = 0 , loweredPrograms = 0 , optimizedPrograms = 0 , emittedUnits = 0 , }
local emitted , emitErr , produced , authoredUnused , constSelection , gpuSources , refusal = aot . emit (
root ,
outDir ,
roots ,
previous ,
session ,
features ,
triple ,
linkage == "static" ,
report ,
scope ,
work
)
if emitted == nil then
return nil , emitErr , refusal
end
report : at ( "aot" )
local remarks = { }

local function appendRemark ( filename , line , column , code , message ) 
local source = fs . readFile ( filename ) or ""
local offset = 1
for _ = 2 , line do
offset = ( source : find ( "\n" , offset , true ) or ( # source + 1 ) ) + 1
end
remarks [
# remarks + 1
] = {
filename = filename ,
line = line ,
col = column ,
offset = offset + column - 1 ,
length = 1 ,
code = code ,
severity = "note" ,
pass = "aot" ,
status = "fired" ,
hotness = "unknown" ,
msg = message ,
}
end

local remarked = { }
for _ , one in ipairs ( emitted ) do
local artifact = produced [ one . source ]
if artifact ~= nil and not remarked [ one . source ] then
remarked [ one . source ] = true
for position , program in ipairs ( artifact . programs ) do
if program . executionTarget ~= "gpu" then
for _ , loop in ipairs ( artifact . loops [ position ] or { } ) do
appendRemark (
one . source ,
loop . line ,
loop . column ,
"AOT-LOOP" ,
program . name .. ": loop " .. tostring (
loop . id
) .. " " .. loop . outcome .. ( loop . reason ~= nil and ( "; " .. loop . reason ) or "" )
)
end
end
end
end
end
for _ , sourcePath in ipairs ( gpuSources ) do
local artifacts = produced [ sourcePath ]
if artifacts ~= nil then
for _ , program in ipairs ( artifacts . programs ) do
local gpu = artifacts . gpu [ program . symbol ]
if gpu ~= nil then
appendRemark (
sourcePath ,
gpu . sourceLine or 1 ,
gpu . sourceColumn or 1 ,
"GPU-DISPATCH" ,
program . name .. ": GPU shader emitted; " .. tostring (
gpu . threads
) .. " threads per workgroup; artifact " .. tostring ( gpu . artifactId )
)
end
end
end
end
local specializedBodies = 0
local countedSources = { }
for _ , one in ipairs ( emitted ) do
local artifacts = produced [ one . source ]
if not countedSources [ one . source ] and artifacts ~= nil then
countedSources [ one . source ] = true
for _ , family in ipairs ( ( artifacts ) . constFamilies or { } ) do
specializedBodies = specializedBodies + # family . programs
end
end
end
local selectedForManifest , selectedErr = targets . buildTiers ( triple , features )
if selectedForManifest == nil then
return nil , tostring ( selectedErr )
end
local selectedTriple = ( selectedForManifest ) [ 1 ] . triple
local tierNames = { }
for _ , tierTarget in ipairs ( selectedForManifest ) do
tierNames [ # tierNames + 1 ] = tierTarget . tier
end





local archive = nil
local staticProfile = nil
if linkage == "static" then
local profile , profileErr = require ( "nupp.compiler.compilerpacks" ) . profile ( selectedTriple )
if profile == nil then
return nil , tostring ( profileErr )
end
staticProfile = profile
local described = profile
if not described . staticAot then
return nil , "aotLinkage = \"static\" needs a target that produces static AOT archives; "
.. described . target
.. " ("
.. described . origin
.. ") does not"
end
if not described . staticSymbolResolver then
return nil , "aotLinkage = \"static\" needs a target whose VM resolves default-namespace "
.. "symbols from the process image; "
.. described . target
.. " ("
.. described . origin
.. ") does not"
end
if # ( emitted ) > 0 then
local unit , probed , probeErr = aot . writeArchiveProbe (
outDir ,
name ,
( selectedForManifest ) [ 1 ] ,
emitted
)
if unit == nil then
return nil , tostring ( probeErr )
end
local units = emitted
units [ # units + 1 ] = unit
archive = probed
end
end
local manifest , manifestErr = aot . writeUnitsManifest ( outDir , selectedTriple , emitted )
if manifestErr ~= nil then
return nil , manifestErr
end
if archive ~= nil then
local _ , linkErr = aot . writeLinkManifest (
outDir ,
name ,
staticProfile ,
archive ,
aot . libraryPath ( outDir , name , ".a" ) ,
emitted ,
produced ,
tierNames
)
if linkErr ~= nil then
return nil , linkErr
end
end
if wasmPolicy then
local wasm , wasmErr = aot . compileWasm ( emitted , produced , held . modules , report )
if wasm == nil then
return nil , wasmErr
end
local sideModules = wasm
report : at ( "aot" )
manifest , manifestErr = aot . writeUnitsManifest (
outDir ,
( selectedForManifest ) [ 1 ] . triple ,
emitted
)
if manifestErr ~= nil then
return nil , manifestErr
end
local dispatch = { }
if policy == "require-wasm" then




local candidates = { }
local order = { }
for _ , one in ipairs ( emitted ) do
if one . detector ~= true and one . unit ~= nil then
local list = candidates [ one . source ]
if list == nil then
list = { }
candidates [ one . source ] = list
order [ # order + 1 ] = one . source
end
table . insert ( list , 1 , one . unit )
end
end
for _ , sourcePath in ipairs ( order ) do
local artifacts = produced [ sourcePath ]
local source = fs . readFile ( sourcePath )
if artifacts ~= nil and source ~= nil then
dispatch [
sourcePath
] = aot . wasmDispatch (
source ,
( artifacts ) . programs ,
( artifacts ) . sites ,
candidates [ sourcePath ] ,
( artifacts ) . gpu ,
( artifacts ) . constFamilies
)
end
end
for _ , sourcePath in ipairs ( gpuSources ) do
if dispatch [ sourcePath ] == nil then
local artifacts = produced [ sourcePath ]
local source = fs . readFile ( sourcePath )
if artifacts ~= nil and source ~= nil then
dispatch [
sourcePath
] = aot . wasmDispatch (
source ,
( artifacts ) . programs ,
( artifacts ) . sites ,
{ } ,
( artifacts ) . gpu ,
( artifacts ) . constFamilies
)
end
end
end
end
return _G.setmetatable({ remarks =
remarks ,  emitted =
emitted ,  libraryKey =
sideModules . key ,  toolchain =
sideModules . toolchain ,  manifest =
manifest ,  dispatch =
dispatch ,  authoredUnused =
authoredUnused ,  wasmModules =
sideModules . outputs ,  gpu =
# gpuSources > 0 ,  gpuSources =
gpuSources ,  specializedBodies =
specializedBodies ,  constSelection =
constSelection ,  modules =
sideModules . modules ,  remembered =
_G.setmetatable({ command =  "<llvm>" ,  signature =  "" ,  version =  aotllvm . version ( ) }, aot.Remembered) ,  facts =
_G.setmetatable({ units =
# ( emitted ) ,  checkedSources =
work . checkedSources ,  loweredPrograms =
work . loweredPrograms ,  optimizedPrograms =
work . optimizedPrograms ,  emittedUnits =
work . emittedUnits ,  reusedObjects =
0 ,  compiledObjects =
0 ,  reusedModules =
sideModules . reused ,  compiledModules =
sideModules . compiled ,  linked =
false ,  externalCommands =
toolruns . count ( ) }, aot.Facts) }, aot.Result)

, nil
end
if not aot . linksNative ( policy ) then
return _G.setmetatable({ remarks =
remarks ,  emitted =
emitted ,  manifest =
manifest ,  dispatch =
{ } ,  gpu =
# gpuSources > 0 ,  gpuSources =
gpuSources ,  specializedBodies =
specializedBodies ,  constSelection =
constSelection ,  facts =
_G.setmetatable({ units =
# ( emitted ) ,  checkedSources =
work . checkedSources ,  loweredPrograms =
work . loweredPrograms ,  optimizedPrograms =
work . optimizedPrograms ,  emittedUnits =
work . emittedUnits ,  reusedObjects =
0 ,  compiledObjects =
0 ,  reusedModules =
0 ,  compiledModules =
0 ,  linked =
false ,  externalCommands =
toolruns . count ( ) }, aot.Facts) }, aot.Result)

, nil
end
if # ( emitted ) == 0 then
local dispatch = { }
for _ , sourcePath in ipairs ( gpuSources ) do
local artifacts = produced [ sourcePath ]
local source = fs . readFile ( sourcePath )
if artifacts ~= nil and source ~= nil then
dispatch [
sourcePath
] = aot . dispatch (
source ,
( artifacts ) . programs ,
( artifacts ) . sites ,
( artifacts ) . gpu ,
nil ,
nil ,
( artifacts ) . constFamilies ,
wasmPolicy
)
end
end
return _G.setmetatable({ remarks =
remarks ,  emitted =
emitted ,  manifest =
manifest ,  dispatch =
dispatch ,  authoredUnused =
authoredUnused ,  gpu =
# gpuSources > 0 ,  gpuSources =
gpuSources ,  specializedBodies =
specializedBodies ,  constSelection =
constSelection ,  facts =
_G.setmetatable({ units =
0 ,  checkedSources =
work . checkedSources ,  loweredPrograms =
work . loweredPrograms ,  optimizedPrograms =
work . optimizedPrograms ,  emittedUnits =
work . emittedUnits ,  reusedObjects =
0 ,  compiledObjects =
0 ,  reusedModules =
0 ,  compiledModules =
0 ,  linked =
false ,  externalCommands =
toolruns . count ( ) }, aot.Facts) }, aot.Result)

, nil
end

local selected = ( selectedForManifest ) [ 1 ]
report : at ( "aot:reuse" )

local chain = _G.setmetatable({ command =  "<llvm>" ,  version =  aotllvm . version ( ) }, aot.Toolchain)
local keys = { }
for _ , one in ipairs ( emitted ) do
keys [ # keys + 1 ] = one . key
end

local static = linkage == "static"
local suffix = static and ".a" or aot . librarySuffix ( selected )
local library = aot . libraryPath ( outDir , name , suffix )
local reference = nil
if not static then
reference = aot . libraryReference ( name , suffix )
end
local keyedFlags = { }
for _ , one in ipairs ( emitted ) do
keyedFlags [ # keyedFlags + 1 ] = "tier=" .. one . tier
for _ , flag in ipairs ( aotllvm . flags ( selected . triple , one . tier ) ) do
keyedFlags [ # keyedFlags + 1 ] = flag
end
end
local key = aot . libraryKey ( keys , chain , keyedFlags , { static and "static" or "shared" } )










local objects = held . objects or { }
local reusedObjects = # ( emitted )
local compiledObjects = 0
local linked = false




local intact = true
for _ , one in ipairs ( emitted ) do
if not fs . exists ( aot . objectOf ( one . output ) ) then
intact = false
end
end
if previousLibraryKey ~= key or not fs . exists ( library ) or not intact then
local linkErr , outcome = aot . link (
chain ,
selected ,
emitted ,
library ,
static ,
held . objects ,
report ,
root
)
if linkErr ~= nil then
return nil , tostring ( linkErr )
end
local done = outcome
objects = done . objects
reusedObjects , compiledObjects , linked = done . reused , done . compiled , done . linked
else



for _ , one in ipairs ( emitted ) do
one . object = aot . objectOf ( one . output )
end
end
report : at ( "aot" )




local dispatch = { }
local dispatched = { }
local dispatchSources = { }
for _ , one in ipairs ( emitted ) do
if not dispatched [ one . source ] then
dispatched [ one . source ] = true
dispatchSources [ # dispatchSources + 1 ] = one . source
end
end
for _ , sourcePath in ipairs ( gpuSources ) do
if not dispatched [ sourcePath ] then
dispatched [ sourcePath ] = true
dispatchSources [ # dispatchSources + 1 ] = sourcePath
end
end
table . sort ( dispatchSources )
for _ , sourcePath in ipairs ( dispatchSources ) do
local artifacts = produced [ sourcePath ]
local source = fs . readFile ( sourcePath )
if artifacts ~= nil and source ~= nil then
dispatch [
sourcePath
] = aot . dispatch (
source ,
( artifacts ) . programs ,
( artifacts ) . sites ,
( artifacts ) . gpu ,
reference ,
tierNames ,
( artifacts ) . constFamilies ,
wasmPolicy ,
archive
)
end
end

return _G.setmetatable({ remarks =
remarks ,  emitted =
emitted ,  library =
library ,  libraryKey =
key ,  toolchain =
chain . version ,  manifest =
manifest ,  dispatch =
dispatch ,  authoredUnused =
authoredUnused ,  gpu =
# gpuSources > 0 ,  gpuSources =
gpuSources ,  specializedBodies =
specializedBodies ,  constSelection =
constSelection ,  objects =
objects ,  remembered =
_G.setmetatable({ command =  chain . command ,  signature =  chain . version ,  version =  chain . version }, aot.Remembered) ,  facts =
_G.setmetatable({ units =
# ( emitted ) ,  checkedSources =
work . checkedSources ,  loweredPrograms =
work . loweredPrograms ,  optimizedPrograms =
work . optimizedPrograms ,  emittedUnits =
work . emittedUnits ,  reusedObjects =
reusedObjects ,  compiledObjects =
compiledObjects ,  reusedModules =
0 ,  compiledModules =
0 ,  linked =
linked ,  externalCommands =
toolruns . count ( ) }, aot.Facts) }, aot.Result)

, nil
end

local __nuppExportValue= aot ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.aot"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.aot"]=__nuppExports;return __nuppExports