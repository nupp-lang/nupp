_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()












local hash = require ( "nupp.compiler.hash" )
local json = require ( "nupp.codec.json" )
local process = require ( "nupp.compiler.process" )
local fs = require ( "nupp.compiler.fs" )
local cache = require ( "nupp.tools.build.cache" )
local fingerprint = require ( "nupp.compiler.project.fingerprint" )
local syntax = require ( "nupp.compiler.shellsyntax" )
local projectconfig = require ( "nupp.compiler.project.projectconfig" )

local normalize , join = fs . normalize , fs . join
local dirname , basename = fs . dirname , fs . basename
local readFile , writeFile = fs . readFile , fs . writeFile
local exists , mkdir = fs . exists , fs . mkdir
local copyFile , listFiles = fs . copyFile , fs . listFiles
local stable = require ( "nupp.compiler.stable" )
local hashFiles = fingerprint . hashFiles

local deps = __nuppNew(0,2)














local windows = package . config : sub ( 1 , 1 ) == "\\"

local absolute , rockTree = projectconfig . absolute , projectconfig . rockTree
local treePaths , rockTypeRoot = projectconfig . treePaths , projectconfig . rockTypeRoot
local rockIdentity , declaredVersion = projectconfig . rockIdentity , projectconfig . declaredVersion
local scopeKey , dependencyRecord = projectconfig . scopeKey , projectconfig . record


deps . targetNames = projectconfig . targetNames



deps . rockspecField = projectconfig . rockspecField








local function expandGlob ( root , glob ) 
glob = normalize ( glob )
if not glob : find ( "[*?]" ) then
local path = join ( root , glob )
return exists ( path ) and { path } or { }
end
local prefix = glob : match ( "^(.-)[*?]" ) or "."
prefix = prefix : match ( "^(.*)/" ) or "."
local base = join ( root , prefix )
local isMatch = syntax . glob ( join ( root , glob ) )
local matches = { }
for _ , path in ipairs ( listFiles ( base ) ) do
if isMatch ( path ) then
matches [ # matches + 1 ] = path
end
end

return matches
end

local function sharedLibraryName ( name ) 
name = name : gsub ( "%-" , "_" )
local osName = ( jit and jit . os or "" ) : lower ( )
if osName == "windows" then
return name .. ".dll"

elseif osName == "osx" then
return "lib" .. name .. ".dylib"
end

return "lib" .. name .. ".so"
end

deps . sharedLibraryName = sharedLibraryName

local function staticLibraryName ( name ) 
return "lib" .. name : gsub ( "%-" , "_" ) .. ".a"
end
















local function libraryReference ( root , outDir , output ) 
local prefix = join ( root , outDir ) .. "/"
local path = normalize ( output )
if path : sub ( 1 , # prefix ) ~= prefix then
return output
end

return "@" .. path : sub ( # prefix + 1 )
end

local function fetchGit ( root , name , source ) 
if type ( source ) ~= "table" or not source . git then
return root
end
if type ( source . rev ) ~= "string" or source . rev == "" then
return nil , "dependency " .. name .. " requires an exact source.rev"
end
local checkout = join ( root , ".nupp/deps/" .. name )
if not exists ( join ( checkout , ".git/HEAD" ) ) then
mkdir ( dirname ( checkout ) )
local code = process . run ( { "git" , "clone" , source . git , checkout } )
if code ~= 0 then
return nil , "git clone failed for " .. name
end
end
local code , head = process . capture ( { "git" , "rev-parse" , "HEAD" } , { cwd = checkout } )
if code ~= 0 or normalize ( ( head : gsub ( "%s+$" , "" ) ) ) ~= source . rev then
if process . run ( { "git" , "fetch" , "--depth" , "1" , "origin" , source . rev } , { cwd = checkout } ) ~= 0 then
return nil , "git fetch failed for " .. name
end
if process . run ( { "git" , "checkout" , "--detach" , "FETCH_HEAD" } , { cwd = checkout } ) ~= 0 then
return nil , "git checkout failed for " .. name
end
end

return checkout
end

local function dependencyFiles ( base , patterns ) 
local files = { }
for _ , pattern in ipairs ( patterns or { } ) do
local expanded = expandGlob ( base , pattern )
for _ , path in ipairs ( expanded ) do
files [ # files + 1 ] = path
end
end
table . sort ( files )

return files
end

local function bindingConfig ( dep ) 
if type ( dep . bindings ) == "table" then
return dep . bindings
end
if dep . header then
return { header = dep . header }
end

return nil
end






local function appendChildLinkInputs ( dep , childResults , outputs , flags ) 
for _ , childName in ipairs ( dep . dependencies or { } ) do
local child = childResults and childResults [ childName ]
for _ , childOutput in ipairs ( child and child . linkOutputs or child and child . output and { child . output } or { } ) do
outputs [ # outputs + 1 ] = childOutput
end
for _ , childFlag in ipairs ( child and child . linkFlags or { } ) do
flags [ # flags + 1 ] = childFlag
end
end
end



local function pkgConfigWords ( argv , packages , label ) 
for _ , packageName in ipairs ( packages ) do
argv [ # argv + 1 ] = packageName
end
local code , flags = process . capture ( argv )
if code ~= 0 then
return nil , "pkg-config failed for " .. label .. ": " .. flags
end
local parsed = syntax . shellWords ( flags )
if not parsed then
return nil , "pkg-config returned invalid flags for " .. label
end

return parsed
end




local function generateBinding ( root , outDir , name , dep , base , libraryPath , extraCppflags , bindingCc , binding ) 
binding = binding or bindingConfig ( dep )
if not binding or not binding . header then
return nil
end
local header = binding . header
if header : sub ( 1 , 1 ) ~= "/" then
header = join ( base , header )
end

local importc = require ( "nupp.compiler.cinterop." .. "importc" )
local text , warnings , details = importc . import ( header , {
module = name ,
lib = binding . library or dep . load or libraryPath ,
cc = bindingCc or dep . cc ,
cppflags = extraCppflags or dep . cppflags ,
bridge = binding . bridge ,
macros = binding . macros ,
ownership = binding . ownership ,
bridgeInclude = binding . header ,
} )
if not text then
return nil , table . concat ( warnings or { } , "; " )
end
for _ , disposition in ipairs ( details and details . dispositions or { } ) do
if disposition . reason == "invalid-macro-signature" then
return nil , "invalid C macro bridge " .. tostring ( disposition . name )
end
end
for _ , warning in ipairs ( warnings or { } ) do
io . stderr : write ( "nupp: warning: " .. warning .. "\n" )
end
local output = join ( root , binding . output or join ( outDir , "generated/" .. name .. ".nupp" ) )
local current = readFile ( output )
if current ~= text then
local ok , err = writeFile ( output , text )
if not ok then
return nil , err
end
end

local bridge = nil
if details and details . bridgeSource then
bridge = join ( root , join ( outDir , "generated/" .. name .. "_bridge.c" ) )
local bridgeCurrent = readFile ( bridge )
if bridgeCurrent ~= details . bridgeSource then
local ok , err = writeFile ( bridge , details . bridgeSource )
if not ok then
return nil , err
end
end
end

return output , nil , bridge
end

local function buildC ( root , outDir , name , dep , previous , childResults , target ) 
local base , fetchErr = fetchGit ( root , name , dep . source )
if not base then
return nil , fetchErr
end
if dep . source then
base = join ( base , dep . path or "." )
else
base = join ( root , dep . path or "." )
end
local sources = dependencyFiles ( base , dep . sources or { } )
local nativeInputs = { }
for _ , path in ipairs ( sources ) do
nativeInputs [ # nativeInputs + 1 ] = path
end
for _ , path in ipairs ( dependencyFiles ( base , dep . headers or { } ) ) do
nativeInputs [ # nativeInputs + 1 ] = path
end
local configuredBinding = bindingConfig ( dep )
if configuredBinding and configuredBinding . header then
local header = configuredBinding . header
if header : sub ( 1 , 1 ) ~= "/" then
header = join ( base , header )
end
nativeInputs [ # nativeInputs + 1 ] = header
end
local standalone = target and target . standalone == true
if standalone and dep . linkage == "shared" then
return nil , "standalone binary requires C dependency " .. name .. " to use linkage = \"static\" or \"both\""
end
local linkage = dep . linkage or ( standalone and "static" or "shared" )
local buildsShared = not standalone and ( linkage == "shared" or linkage == "both" )
local buildsStatic = linkage == "static" or linkage == "both"
table . sort ( nativeInputs )

local artifactTriple = target and target . layoutTarget or require ( "nupp.compiler.targetlayout" ) . hostKey ( )
local pack , packErr = require ( "nupp.compiler.compilerpacks" ) . resolve ( artifactTriple )
if packErr ~= nil and dep . cc == nil and configuredBinding ~= nil then
return nil , packErr
end
local artifactSet = dep . artifacts and artifactTriple and dep . artifacts [ artifactTriple ] or nil
if artifactSet then
if configuredBinding
and ( configuredBinding . bridge or configuredBinding . macros and next ( configuredBinding . macros ) ~= nil )
then
return nil , "prebuilt C dependency " .. name .. " cannot generate a bridge; build it from sources"
end

local function stageArtifact ( kind , record , destination ) 
if type ( record ) ~= "table" then
return nil , "prebuilt C dependency " .. name .. " has no " .. kind .. " artifact for " .. tostring (
artifactTriple
)
end
local absolute = record . path : sub ( 1 , 1 ) == "/" or record . path : match ( "^%a:[/\\]" ) ~= nil
local source = absolute and record . path or join ( base , record . path )
local bytes , readErr = readFile ( source )
if not bytes then
return nil , "cannot read prebuilt C artifact " .. source .. ": " .. tostring ( readErr )
end
if # bytes ~= record . size then
return nil , ("prebuilt C artifact %s has %d bytes, expected %d") : format ( source , # bytes , record . size )
end
local digest = hash . sha256 ( bytes )
if digest ~= record . sha256 then
return nil , "prebuilt C artifact "
.. source
.. " has SHA-256 "
.. digest
.. ", expected "
.. record . sha256
end
if kind == "static" and bytes : sub ( 1 , 8 ) ~= "!<arch>\n" then
return nil , "prebuilt static C artifact " .. source .. " is not an archive"
end
local wrote , writeErr = writeFile ( destination , bytes )
if not wrote then
return nil , tostring ( writeErr )
end

return destination , nil
end

local sharedOutput = buildsShared and join ( root , dep . output or join ( outDir , "lib/" .. sharedLibraryName ( name ) ) )
or nil
local staticOutput = buildsStatic
and join (
root ,
dep . staticOutput
or ( linkage == "static" and dep . output )
or join ( outDir , "lib/" .. ( "lib" .. name : gsub ( "%-" , "_" ) .. ".a" ) )
)
or nil
local problem
if sharedOutput then
_ , problem = stageArtifact ( "shared" , artifactSet . shared , sharedOutput )
end
if problem == nil and staticOutput then
_ , problem = stageArtifact ( "static" , artifactSet . static , staticOutput )
end
if problem ~= nil then
return nil , problem
end
local reference = configuredBinding
and not standalone
and (
configuredBinding . library or dep . load or ( sharedOutput and libraryReference ( root , outDir , sharedOutput ) )
)
or nil
local artifactCppflags = { }
for _ , flag in ipairs ( dep . cppflags or { } ) do
artifactCppflags [ # artifactCppflags + 1 ] = flag
end
for _ , directory in ipairs ( dep . includeDirs or { } ) do
artifactCppflags [ # artifactCppflags + 1 ] = "-I" .. join ( base , directory )
end
local binding , bindingErr = generateBinding (
root ,
outDir ,
name ,
dep ,
base ,
reference ,
artifactCppflags ,
dep . cc or pack and pack . cc or nil
)
if bindingErr then
return nil , bindingErr
end
local linkOutputs = json . asArray ( { } )
local linkFlags = json . asArray ( { } )
if staticOutput then
linkOutputs [ # linkOutputs + 1 ] = staticOutput
appendChildLinkInputs ( dep , childResults , linkOutputs , linkFlags )
for _ , flag in ipairs ( dep . ldflags or { } ) do
linkFlags [ # linkFlags + 1 ] = flag
end
elseif sharedOutput then
linkOutputs [ # linkOutputs + 1 ] = sharedOutput
end

return {
key = hash . digest (
stable ( dep ) .. "\0" .. tostring ( artifactTriple ) .. "\0standalone=" .. tostring ( standalone )
) ,
output = sharedOutput or staticOutput ,
staticOutput = staticOutput ,
runtimeOutput = sharedOutput ,
linkOutputs = linkOutputs ,
linkFlags = linkFlags ,
binding = binding ,
reference = reference ,
}
end
if dep . artifacts ~= nil and # sources == 0 then
return nil , "C dependency " .. name .. " has no prebuilt artifact for " .. tostring ( artifactTriple )
end
if packErr ~= nil and dep . cc == nil then
return nil , packErr
end
local compiler = dep . cc or pack and pack . cc or "cc"
local _ , version = process . capture ( { compiler , "--version" } )
local archiver , archiverIdentity = nil , ""
if buildsStatic then
if pack ~= nil then
archiver = pack . ar
else
local archiveProbe , found = process . capture ( { compiler , "-print-prog-name=ar" } )
found = ( found or "" ) : match ( "^%s*(.-)%s*$" )
archiver = archiveProbe == 0 and found ~= "" and found or "ar"
end
local archiveVersionCode , archiveVersion = process . capture ( { archiver , "--version" } )
archiverIdentity = archiver .. "\0" .. tostring ( archiveVersionCode ) .. "\0" .. archiveVersion
end
local pkgCflags = { }
local pkgSharedLibs = { }
local pkgStaticLibs = { }
if dep . pkgConfig then
local packages = type ( dep . pkgConfig ) == "table" and dep . pkgConfig or { }
if type ( dep . pkgConfig ) == "string" then
for packageName in dep . pkgConfig : gmatch ( "%S+" ) do
packages [ # packages + 1 ] = packageName
end
end
local label = table . concat ( packages , ", " )
local problem
pkgCflags , problem = pkgConfigWords ( { "pkg-config" , "--cflags" } , packages , label )
if not pkgCflags then
return nil , problem
end
pkgSharedLibs , problem = pkgConfigWords ( { "pkg-config" , "--libs" } , packages , label )
if not pkgSharedLibs then
return nil , problem
end
if buildsStatic then
pkgStaticLibs , problem = pkgConfigWords ( { "pkg-config" , "--static" , "--libs" } , packages , label )
if not pkgStaticLibs then
return nil , problem
end
end
end
local cppflags = { }
for _ , flag in ipairs ( dep . cppflags or { } ) do
cppflags [ # cppflags + 1 ] = flag
end
for _ , dir in ipairs ( dep . includeDirs or { } ) do
cppflags [ # cppflags + 1 ] = "-I" .. join ( base , dir )
end
for _ , flag in ipairs ( pkgCflags ) do
cppflags [ # cppflags + 1 ] = flag
end
for _ , flag in ipairs ( pack and pack . compileFlags or { } ) do
cppflags [ # cppflags + 1 ] = flag
end
local hasMacroBridge = configuredBinding and configuredBinding . macros and next ( configuredBinding . macros ) ~= nil
local wantsLibrary = # sources > 0 or ( configuredBinding and configuredBinding . bridge ) or hasMacroBridge
local sharedOutput = wantsLibrary
and buildsShared
and join ( root , dep . output or join ( outDir , "lib/" .. sharedLibraryName ( name ) ) )
or nil
local staticOutput = wantsLibrary
and buildsStatic
and join (
root ,
dep . staticOutput or ( linkage == "static" and dep . output ) or join ( outDir , "lib/" .. ( "lib" .. name : gsub ( "%-" , "_" ) .. ".a" ) )
)
or nil
if sharedOutput ~= nil and staticOutput ~= nil and normalize ( sharedOutput ) == normalize ( staticOutput ) then
return nil , "C dependency " .. name .. " must use different shared and static outputs"
end
local output = sharedOutput or staticOutput



local reference = configuredBinding
and not standalone
and (
configuredBinding . library
or dep . load
or ( sharedOutput and libraryReference ( root , outDir , sharedOutput ) )
or type ( dep . pkgConfig ) == "string" and dep . pkgConfig
)
or nil
local binding , bindingErr , bridge = generateBinding ( root , outDir , name , dep , base , reference , cppflags , compiler )
if bindingErr then
return nil , bindingErr
end
if bridge then
sources [ # sources + 1 ] = bridge
nativeInputs [ # nativeInputs + 1 ] = bridge
table . sort ( sources )
table . sort ( nativeInputs )
end
local key = hash . digest (
stable (
dep
) .. "\0standalone=" .. tostring (
standalone
) .. "\0" .. hashFiles (
nativeInputs
) .. "\0" .. version .. "\0" .. stable (
pack and { version = pack . version , compileFlags = pack . compileFlags , linkFlags = pack . linkFlags , } or { }
) .. "\0" .. stable (
pkgCflags
) .. "\0" .. stable (
pkgSharedLibs
) .. "\0" .. stable ( pkgStaticLibs ) .. "\0" .. archiverIdentity .. "\0" .. stable ( childResults )
)
if # sources > 0 then
if not output then
return nil , "C dependency " .. name .. " has sources but no library output"
end
local outputsExist = ( sharedOutput == nil or exists ( sharedOutput ) )
and ( staticOutput == nil or exists ( staticOutput ) )
if not previous or previous . key ~= key or not outputsExist then
if sharedOutput then
mkdir ( dirname ( sharedOutput ) )
end
if staticOutput then
mkdir ( dirname ( staticOutput ) )
end
local objectStem = sharedOutput or staticOutput
local objects = { }
local osName = ( jit and jit . os or "" ) : lower ( )

local function removeIntermediates ( ) 
for _ , object in ipairs ( objects ) do
os . remove ( object )
end
if sharedOutput then
os . remove ( sharedOutput .. ".tmp" )
end
if staticOutput then
os . remove ( staticOutput .. ".tmp" )
end
end

for index , source in ipairs ( sources ) do
local object = objectStem .. ".nupp-" .. tostring ( index ) .. ".o"
objects [ # objects + 1 ] = object
os . remove ( object )
local argv = { compiler , "-c" , "-o" , object }
if osName ~= "windows" then
argv [ # argv + 1 ] = "-fPIC"
end
for _ , dir in ipairs ( dep . includeDirs or { } ) do
argv [ # argv + 1 ] = "-I" .. join ( base , dir )
end
if bridge then
argv [ # argv + 1 ] = "-I" .. base
end
for _ , flag in ipairs ( dep . cppflags or { } ) do
argv [ # argv + 1 ] = flag
end
for _ , flag in ipairs ( pack and pack . compileFlags or { } ) do
argv [ # argv + 1 ] = flag
end
for _ , flag in ipairs ( pkgCflags ) do
argv [ # argv + 1 ] = flag
end
for _ , flag in ipairs ( dep . cflags or { } ) do
argv [ # argv + 1 ] = flag
end
argv [ # argv + 1 ] = source
if process . run ( argv ) ~= 0 then
removeIntermediates ( )
return nil , "C compilation failed for " .. name
end
end

if sharedOutput then
local staged = sharedOutput .. ".tmp"
os . remove ( staged )
local argv = { compiler }
if osName == "osx" then
argv [ # argv + 1 ] = "-dynamiclib"
else
argv [ # argv + 1 ] = "-shared"
end
argv [ # argv + 1 ] = "-o"
argv [ # argv + 1 ] = staged
for _ , flag in ipairs ( dep . cflags or { } ) do
argv [ # argv + 1 ] = flag
end
for _ , flag in ipairs ( pack and pack . linkFlags or { } ) do
argv [ # argv + 1 ] = flag
end
for _ , object in ipairs ( objects ) do
argv [ # argv + 1 ] = object
end
appendChildLinkInputs ( dep , childResults , argv , argv )
for _ , flag in ipairs ( pkgSharedLibs ) do
argv [ # argv + 1 ] = flag
end
for _ , flag in ipairs ( dep . ldflags or { } ) do
argv [ # argv + 1 ] = flag
end
if process . run ( argv ) ~= 0 then
removeIntermediates ( )
return nil , "C shared link failed for " .. name
end
end

if staticOutput then
local staged = staticOutput .. ".tmp"
os . remove ( staged )
local argv = { archiver , "rcs" , staged }
for _ , object in ipairs ( objects ) do
argv [ # argv + 1 ] = object
end
if process . run ( argv ) ~= 0 then
removeIntermediates ( )
return nil , "C static archive failed for " .. name
end
end

local function install ( builtOutput ) 
if not builtOutput then
return nil
end
local installed , installErr = fs . installStaged ( builtOutput .. ".tmp" , builtOutput )
if not installed then
return installErr
end

return nil
end

local installErr = install ( sharedOutput ) or install ( staticOutput )
if installErr then
removeIntermediates ( )
return nil , installErr
end
removeIntermediates ( )
end
end

local linkOutputs = json . asArray ( { } )
local linkFlags = json . asArray ( { } )
if staticOutput then
linkOutputs [ # linkOutputs + 1 ] = staticOutput
appendChildLinkInputs ( dep , childResults , linkOutputs , linkFlags )
for _ , flag in ipairs ( pkgStaticLibs ) do
linkFlags [ # linkFlags + 1 ] = flag
end
for _ , flag in ipairs ( dep . ldflags or { } ) do
linkFlags [ # linkFlags + 1 ] = flag
end
for _ , flag in ipairs ( pack and pack . linkFlags or { } ) do
linkFlags [ # linkFlags + 1 ] = flag
end
elseif sharedOutput then
linkOutputs [ # linkOutputs + 1 ] = sharedOutput
end

return {
key = key ,
output = output ,
staticOutput = staticOutput ,
runtimeOutput = sharedOutput ,
linkOutputs = linkOutputs ,
linkFlags = linkFlags ,
binding = binding ,
reference = reference ,
}
end



local function buildTypes ( root , _ , name , dep ) 
local checkout , fetchErr = fetchGit ( root , name , dep . source )
if not checkout then
return nil , fetchErr
end
local typesRoot = join ( checkout , dep . path or "." )
if not exists ( typesRoot ) then
return nil , "type dependency " .. name .. " names a path that is not there: " .. ( dep . path or "." )
end
local files = { }
for _ , path in ipairs ( listFiles ( typesRoot ) ) do
if path : match ( "%.lua$" ) then
files [ # files + 1 ] = path
end
end
if # files == 0 then
return nil , "type dependency " .. name .. " has no Lua declaration files under " .. ( dep . path or "." )
end

return { key = hash . digest ( stable ( dep ) .. "\0" .. hashFiles ( files ) ) , typesRoot = typesRoot }
end

local function cargoSourceFiles ( crateDir ) 
local files = { }
for _ , path in ipairs ( listFiles ( crateDir ) ) do
if path : match ( "%.rs$" ) or basename ( path ) == "Cargo.toml" or basename ( path ) == "Cargo.lock" then
files [ # files + 1 ] = path
end
end

return files
end

local function buildCargo ( root , outDir , name , dep , previous ) 
local manifest = join ( root , dep . manifest or join ( dep . path or name , "Cargo.toml" ) )
local crateDir = dirname ( manifest )
local cargo = dep . cargo or "cargo"
local _ , version = process . capture ( { cargo , "--version" } )
local key = hash . digest ( stable ( dep ) .. "\0" .. hashFiles ( cargoSourceFiles ( crateDir ) ) .. "\0" .. version )
local targetDir = join ( root , dep . targetDir or join ( outDir , "cargo/" .. name ) )
local profile = dep . profile or "release"
local crateName = ( dep . library or name ) : gsub ( "%-" , "_" )
local targetPart = dep . target and ( dep . target .. "/" ) or ""
local artifact = dep . artifactPath or join ( targetDir , targetPart .. profile .. "/" .. sharedLibraryName ( crateName ) )
local output = join ( root , dep . output or join ( outDir , "lib/" .. sharedLibraryName ( crateName ) ) )
if not previous or previous . key ~= key or not exists ( output ) then
local argv = { cargo , "build" , "--manifest-path" , manifest , "--target-dir" , targetDir }
if profile == "release" then
argv [ # argv + 1 ] = "--release"
elseif profile ~= "debug" then
argv [ # argv + 1 ] = "--profile" ;
argv [ # argv + 1 ] = profile
end
if dep . target then
argv [ # argv + 1 ] = "--target" ;
argv [ # argv + 1 ] = dep . target
end
if dep . locked ~= false then
argv [ # argv + 1 ] = "--locked"
end
if dep . offline then
argv [ # argv + 1 ] = "--offline"
end
if # ( dep . features or { } ) > 0 then
argv [ # argv + 1 ] = "--features"
argv [ # argv + 1 ] = table . concat ( dep . features , "," )
end
argv [ # argv + 1 ] = "--message-format=json-render-diagnostics"
local cargoCode , cargoOutput = process . capture ( argv , { cwd = root } )
if cargoCode ~= 0 then
io . stderr : write ( cargoOutput )
return nil , "Cargo build failed for " .. name
end
if not dep . artifactPath then
for line in cargoOutput : gmatch ( "[^\13\n]+" ) do
local message = json . decode ( line , json . NULL )
if type ( message ) == "table"
and message . reason == "compiler-artifact"
and message . target
and message . target . name : gsub ( "%-" , "_" ) == crateName
then
for _ , filename in ipairs ( message . filenames or { } ) do
if filename : match ( "%.so$" ) or filename : match ( "%.dylib$" ) or filename : match ( "%.dll$" ) then
artifact = filename
end
end
end
end
end
if not exists ( artifact ) then
return nil , "Cargo artifact not found: " .. artifact
end
local ok , err = copyFile ( artifact , output )
if not ok then
return nil , err
end
end
local binding = bindingConfig ( dep )
if binding and binding . cbindgen then
local header = binding . header or join ( outDir , "generated/" .. name .. ".h" )
header = join ( root , header )
mkdir ( dirname ( header ) )
local argv = { binding . command or "cbindgen" , "--output" , header }
if process . run ( argv , { cwd = crateDir } ) ~= 0 then
return nil , "cbindgen failed for " .. name
end


local resolved = { }
for field , value in pairs ( binding ) do
resolved [ field ] = value
end
resolved . header = header
binding = resolved
end





local reference = binding and ( binding . library or dep . load or libraryReference ( root , outDir , output ) ) or nil
local generated , bindingErr = generateBinding ( root , outDir , name , dep , crateDir , reference , nil , nil , binding )
if bindingErr then
return nil , bindingErr
end

return { key = key , output = output , binding = generated , reference = reference }
end





















local function luaDirectory ( dep ) 
if dep . luaDir then
return dep . luaDir
end
local named = os . getenv ( "NUPP_LUA_DIR" )
if named and named ~= "" then
return named
end
for entry in ( package . cpath .. ";" ) : gmatch ( "([^;]*);" ) do
local prefix = entry : match ( "^(.*)/lib/lua/" )
if prefix and ( exists ( join ( prefix , "include/luajit-2.1/lua.h" ) ) or exists ( join ( prefix , "include/lua.h" ) ) ) then
return prefix
end
end

return nil
end





local function prepended ( current , entries ) 
current = current or ""
local fresh = { }
for entry in ( entries .. ";" ) : gmatch ( "([^;]*);" ) do
if entry ~= "" and not ( ";" .. current .. ";" ) : find ( ";" .. entry .. ";" , 1 , true ) then
fresh [ # fresh + 1 ] = entry
end
end
if # fresh == 0 then
return current
end

return table . concat ( fresh , ";" ) .. ";" .. current
end




local listings = { }
local toolVersions = { }
local toolFailures = { }

local function toolArgv ( tool ) 
local suffix = tool : lower ( ) : match ( "%.([^.]+)$" )
if windows and ( suffix == "bat" or suffix == "cmd" ) then
return { "cmd" , "/d" , "/c" , "call" , tool }
end

return { tool }
end



local function toolVersion ( luarocks ) 
if toolVersions [ luarocks ] == nil then
local argv = toolArgv ( luarocks )
argv [ # argv + 1 ] = "--version"
local code , printed = process . capture ( argv )
toolVersions [ luarocks ] = code == 0 and ( printed or "" ) or false
toolFailures [ luarocks ] = code ~= 0 and printed or nil
end

return toolVersions [ luarocks ]
end

local function installedRocks ( argv , tree , luaVersion ) 
local id = tree .. "\0" .. luaVersion
if listings [ id ] then
return listings [ id ]
end
local listArgv = { }
for _ , item in ipairs ( argv ) do
listArgv [ # listArgv + 1 ] = item
end
listArgv [ # listArgv + 1 ] = "list"
listArgv [ # listArgv + 1 ] = "--porcelain"
local code , printed = process . capture ( listArgv )
local installed = { }
if code == 0 then
for line in printed : gmatch ( "[^\13\n]+" ) do
local rock , version = line : match ( "^(%S+)\9(%S+)\9" )
if rock then
installed [ rock ] = version
end
end
end
listings [ id ] = installed

return installed
end




local ROCK_ARTIFACTS = { o = true , a = true , so = true , dylib = true , dll = true }

local function rockSourceFiles ( dir ) 
local files = { }
for _ , path in ipairs ( listFiles ( dir ) ) do
local suffix = path : match ( "%.([%w]+)$" )
if not ( suffix and ROCK_ARTIFACTS [ suffix : lower ( ) ] ) then
files [ # files + 1 ] = path
end
end
table . sort ( files )

return files
end

local function buildRock ( root , outDir , name , dep , previous ) 
local tree , luaVersion = rockTree ( root , dep )
local source = dep . path and absolute ( join ( root , dep . path ) ) or nil
local rockspec = dep . rockspec and absolute ( join ( root , dep . rockspec ) ) or nil
if rockspec and not exists ( rockspec ) then
return nil , "dependency " .. name .. " names a rockspec that is not " .. "there: " .. dep . rockspec
end
local declaredRock = projectconfig . declaredPackage ( rockspec )
local rock = dep . rock or declaredRock or name
if dep . rock and declaredRock and dep . rock ~= declaredRock then
return nil , ("dependency %s names rock %s, and %s declares package %s")

: format ( name , dep . rock , dep . rockspec , declaredRock )
end
local declared = declaredVersion ( rockspec )
if dep . version and declared and declared ~= dep . version then
return nil , ("dependency %s asks for %s %s, and %s declares %s")

: format ( name , rock , dep . version , dep . rockspec , declared )
end
local wanted = dep . version or declared

local luarocks = dep . luarocks or os . getenv ( "NUPP_LUAROCKS" ) or ( windows and "luarocks.bat" or "luarocks" )
local version = toolVersion ( luarocks )
if not version then
return nil , ("dependency %s cannot run LuaRocks through %s: %s")

: format ( name , luarocks , toolFailures [ luarocks ] or "the command failed" )
end
local argv = toolArgv ( luarocks )
argv [ # argv + 1 ] = "--lua-version=" .. luaVersion
argv [ # argv + 1 ] = "--tree=" .. tree
local luaDir = luaDirectory ( dep )
if luaDir then
argv [ # argv + 1 ] = "--lua-dir=" .. luaDir
end
if dep . server then
argv [ # argv + 1 ] = "--server=" .. dep . server
end

local inputs = { }
if rockspec then
inputs [ # inputs + 1 ] = rockspec
end
if source then
local files = rockSourceFiles ( source )



if # files == 0 then
return nil , ("dependency %s builds from %s, which has nothing in it") : format ( name , dep . path )
end
for _ , path in ipairs ( files ) do
inputs [ # inputs + 1 ] = path
end
end
local key = hash . digest ( stable ( dep ) .. "\0" .. hashFiles ( inputs ) .. "\0" .. version .. "\0" .. tree )







local installed = installedRocks ( argv , tree , luaVersion )
local present = installed [ rock ]
local satisfied = present ~= nil and ( wanted == nil or present == wanted )
local unchanged = previous ~= nil and previous . key == key
if not satisfied or ( source and not unchanged ) then
local install = { }
for _ , item in ipairs ( argv ) do
install [ # install + 1 ] = item
end
if source then


install [ # install + 1 ] = "make"
if rockspec then
install [ # install + 1 ] = rockspec
end
else
install [ # install + 1 ] = "install"
if rockspec then
install [ # install + 1 ] = rockspec
else
install [ # install + 1 ] = rock
install [ # install + 1 ] = dep . version
end
end
if dep . rockDependencies == false then
install [ # install + 1 ] = "--deps-mode=none"
end
local code , printed = process . capture ( install , { cwd = source } )
if code ~= 0 then
io . stderr : write ( printed )
return nil , "LuaRocks install failed for " .. name
end
installed [ rock ] = wanted or "installed"
end

local paths = treePaths ( tree , luaVersion )
package . path = prepended ( package . path , paths . path )
package . cpath = prepended ( package . cpath , paths . cpath )

return {
key = key ,
rock = rock ,
version = installed [ rock ] ,
tree = tree ,
luaVersion = luaVersion ,
path = paths . path ,
cpath = paths . cpath ,
typeRoot = rockTypeRoot ( tree , luaVersion , rock , installed [ rock ] ) ,
}
end




local function runtimeModuleOwner (
root ,
config ,
target ,
records ,
moduleName
) 
local relative = moduleName : gsub ( "%." , "/" )
for _ , name in ipairs ( deps . targetNames ( config , target ) ) do
local dep = ( config . dependencies or { } ) [ name ]
local record = records and records [ name ] or nil
if type ( dep ) == "table" and dep . kind == "luarocks" then
local tree , luaVersion = rockTree ( root , dep )
local candidates = {
join ( tree , "share/lua/" .. luaVersion .. "/" .. relative .. ".lua" ) ,
join ( tree , "share/lua/" .. luaVersion .. "/" .. relative .. "/init.lua" ) ,
join ( tree , "lib/lua/" .. luaVersion .. "/" .. relative .. ".so" ) ,
join ( tree , "lib/lua/" .. luaVersion .. "/" .. relative .. ".dll" ) ,
join ( tree , "lib/lua/" .. luaVersion .. "/" .. relative .. ".dylib" ) ,
}
for _ , candidate in ipairs ( candidates ) do
if exists ( candidate ) then
local rockspec = dep . rockspec and absolute ( join ( root , dep . rockspec ) ) or nil
local package , version = rockIdentity ( record , dep , rockspec , name )

return { dependency = name , package = package , version = version }
end
end
end
end

return nil
end













local function rockModules ( root , config , target ) 
local selected , seen = { } , { }
for _ , name in ipairs ( deps . targetNames ( config , target ) ) do
local dep = ( config . dependencies or { } ) [ name ]
if type ( dep ) == "table" and dep . kind == "luarocks" and dep . bundle then
local tree , luaVersion = rockTree ( root , dep )
local share = join ( tree , "share/lua/" .. luaVersion )
for _ , pattern in ipairs ( dep . bundle ) do
for _ , path in ipairs ( expandGlob ( share , pattern ) ) do
local relative = path : sub ( # share + 2 )
local module = relative : gsub ( "%.lua$" , "" ) : gsub ( "/init$" , "" ) : gsub ( "/" , "." )
if not seen [ module ] then
seen [ module ] = true
selected [ # selected + 1 ] = { name = module , path = path }
end
end
end
end
end
table . sort ( selected , function ( a , b ) 
return a . name < b . name
end )

return selected
end

local PROVIDERS = { c = buildC , cargo = buildCargo , luarocks = buildRock , types = buildTypes }




local function buildDependencies (
root ,
outDir ,
config ,
previous ,
target
) 
local results = { }
local visiting = { }
local targetPlatform = target and target . layoutTarget or require ( "nupp.compiler.targetlayout" ) . hostKey ( )

local function buildOne ( name , usage ) 
local recordKey = scopeKey ( name , usage )
if results [ recordKey ] then
return results [ recordKey ]
end
if visiting [ recordKey ] then
return nil , "dependency cycle involving " .. name
end
local dep = ( config . dependencies and config . dependencies [ name ] )
if type ( dep ) ~= "table" then
return nil , "unknown dependency " .. tostring ( name )
end
local provider = PROVIDERS [ dep . kind ]
if not provider then
return nil , "unsupported dependency kind " .. tostring ( dep . kind )
end
visiting [ recordKey ] = true
local childResults = { }
for _ , child in ipairs ( dep . dependencies or { } ) do
local childResult , err = buildOne ( child , usage )
if err then
return nil , err
end
childResults [ child ] = childResult
end
local old = previous [ recordKey ]
local result , err = provider ( root , outDir , name , dep , old , childResults , usage == "tool" and nil or target )
visiting [ recordKey ] = nil
if not result then
return nil , err
end
result . usage = usage
result . platform = usage == "tool" and require ( "nupp.compiler.targetlayout" ) . hostKey ( ) or targetPlatform
results [ recordKey ] = result

return result
end

local selected = target or config . _target or { }
local targetDeps = selected . dependencies or { }
local compileDeps = selected . compileDependencies
if compileDeps == nil then
compileDeps = { }
for name , dep in pairs ( config . dependencies or { } ) do
if dep . kind == "types" then
compileDeps [ # compileDeps + 1 ] = name
end
end
table . sort ( compileDeps )
end
local targetNames = { }
for _ , name in ipairs ( targetDeps ) do
targetNames [ name ] = true
end
for _ , name in ipairs ( compileDeps ) do
if not targetNames [ name ] then
local _ , err = buildOne ( name , "compile" )
if err then
return nil , err
end
end
end
local targetUsage = selected . kind == "docs" and "tool" or "target"
for _ , name in ipairs ( targetDeps ) do
local _ , err = buildOne ( name , targetUsage )
if err then
return nil , err
end
end
local toolNames = { }
if selected . kind ~= "docs" then
for _ , generator in pairs ( config . generators or { } ) do
local name = generator . using : match ( "^([^/]+)/" )
if name then
toolNames [ name ] = true
end
end
end
for name in pairs ( toolNames ) do
local _ , err = buildOne ( name , "tool" )
if err then
return nil , err
end
end

return results
end

deps . expandGlob = expandGlob
deps . build = buildDependencies
deps . rockPaths = projectconfig . rockPaths
deps . typeRoots = projectconfig . typeRoots
deps . record = dependencyRecord
deps . scopeKey = scopeKey
deps . runtimeModuleOwner = runtimeModuleOwner
deps . rockModules = rockModules

local __nuppExportValue= deps ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.deps"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.deps"]=__nuppExports;return __nuppExports